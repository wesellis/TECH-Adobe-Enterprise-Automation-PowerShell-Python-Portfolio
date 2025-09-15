#!/usr/bin/env python3
"""
Main entry point for Adobe Automation Python services
"""

import asyncio
import logging
import os
import signal
import sys
from datetime import datetime
from typing import Optional

import redis
from aiohttp import web
from prometheus_client import start_http_server, Counter, Histogram, Gauge
import schedule

from adobe_api_client import AdobeAPIClient
from bulk_user_processor import BulkUserProcessor

# Configure logging
logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO')),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f"/app/logs/automation_{datetime.now():%Y%m%d}.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Metrics
api_calls = Counter('adobe_api_calls_total', 'Total API calls made')
api_errors = Counter('adobe_api_errors_total', 'Total API errors')
processing_time = Histogram('adobe_processing_seconds', 'Time spent processing')
active_users = Gauge('adobe_active_users', 'Number of active users')
license_utilization = Gauge('adobe_license_utilization', 'License utilization percentage', ['product'])

class AdobeAutomationService:
    """Main service class for Adobe automation"""

    def __init__(self):
        self.adobe_client = None
        self.redis_client = None
        self.running = True
        self.bulk_processor = None

    async def initialize(self):
        """Initialize service components"""
        logger.info("Initializing Adobe Automation Service...")

        # Initialize Adobe API client
        self.adobe_client = AdobeAPIClient(
            org_id=os.getenv('ADOBE_ORG_ID'),
            client_id=os.getenv('ADOBE_CLIENT_ID'),
            client_secret=os.getenv('ADOBE_CLIENT_SECRET'),
            tech_account_id=os.getenv('ADOBE_TECH_ACCOUNT_ID'),
            private_key_path=os.getenv('ADOBE_PRIVATE_KEY_PATH')
        )

        # Initialize Redis
        self.redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'localhost'),
            port=int(os.getenv('REDIS_PORT', 6379)),
            decode_responses=True
        )

        # Initialize bulk processor
        self.bulk_processor = BulkUserProcessor(self.adobe_client)

        # Start metrics server
        start_http_server(8001)
        logger.info("Metrics server started on port 8001")

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

        logger.info("Service initialization complete")

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info(f"Received signal {signum}, shutting down...")
        self.running = False

    async def sync_users(self):
        """Sync users from AD/Azure to Adobe"""
        logger.info("Starting user synchronization...")
        api_calls.inc()

        try:
            async with self.adobe_client:
                # Get users from queue
                queued_users = self._get_queued_users()

                if queued_users:
                    results = await self.bulk_processor.process_users(queued_users)

                    # Update metrics
                    successful = sum(1 for r in results if r.get('success'))
                    failed = len(results) - successful

                    logger.info(f"Sync complete: {successful} successful, {failed} failed")

                    if failed > 0:
                        api_errors.inc(failed)

                    # Cache results
                    self._cache_results(results)

                # Update user count metric
                all_users = await self.adobe_client.get_all_users()
                active_users.set(len(all_users))

        except Exception as e:
            logger.error(f"User sync failed: {str(e)}")
            api_errors.inc()
            raise

    async def optimize_licenses(self):
        """Optimize license allocation"""
        logger.info("Starting license optimization...")

        try:
            async with self.adobe_client:
                # Get all users and their activity
                users = await self.adobe_client.get_all_users()

                # Identify inactive users (90+ days)
                inactive_users = []
                for user in users:
                    last_login = user.get('lastLoginDate')
                    if last_login:
                        days_inactive = (datetime.now() - datetime.fromisoformat(last_login)).days
                        if days_inactive > 90 and user.get('products'):
                            inactive_users.append(user)

                logger.info(f"Found {len(inactive_users)} inactive users with licenses")

                # Reclaim licenses
                reclaimed = 0
                for user in inactive_users:
                    for product in user.get('products', []):
                        await self.adobe_client.remove_products(
                            email=user['email'],
                            products=[product]
                        )
                        reclaimed += 1

                logger.info(f"Reclaimed {reclaimed} licenses")

                # Update utilization metrics
                products = await self.adobe_client.get_products()
                for product in products:
                    if product.get('totalLicenses', 0) > 0:
                        utilization = (product.get('usedLicenses', 0) / product['totalLicenses']) * 100
                        license_utilization.labels(product=product['name']).set(utilization)

        except Exception as e:
            logger.error(f"License optimization failed: {str(e)}")
            api_errors.inc()

    def _get_queued_users(self) -> list:
        """Get users from Redis queue"""
        users = []
        try:
            # Get up to 100 users from queue
            for _ in range(100):
                user_data = self.redis_client.lpop('user_provision_queue')
                if not user_data:
                    break
                users.append(eval(user_data))  # In production, use json.loads
        except Exception as e:
            logger.error(f"Failed to get queued users: {str(e)}")

        return users

    def _cache_results(self, results: list):
        """Cache processing results"""
        try:
            for result in results:
                key = f"user_result:{result.get('email', 'unknown')}"
                self.redis_client.setex(
                    key,
                    86400,  # 24 hour TTL
                    str(result)
                )
        except Exception as e:
            logger.error(f"Failed to cache results: {str(e)}")

    async def health_check(self) -> dict:
        """Perform health check"""
        health = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'checks': {}
        }

        # Check Redis
        try:
            self.redis_client.ping()
            health['checks']['redis'] = 'healthy'
        except:
            health['checks']['redis'] = 'unhealthy'
            health['status'] = 'degraded'

        # Check Adobe API
        try:
            async with self.adobe_client:
                await self.adobe_client.authenticate()
                health['checks']['adobe_api'] = 'healthy'
        except:
            health['checks']['adobe_api'] = 'unhealthy'
            health['status'] = 'unhealthy'

        return health

    async def run_scheduled_tasks(self):
        """Run scheduled tasks"""
        while self.running:
            try:
                # Check for scheduled tasks
                schedule.run_pending()
                await asyncio.sleep(60)  # Check every minute
            except Exception as e:
                logger.error(f"Scheduled task error: {str(e)}")

    async def start(self):
        """Start the service"""
        await self.initialize()

        # Schedule tasks
        if os.getenv('ENABLE_AUTO_PROVISIONING', 'true').lower() == 'true':
            schedule.every(4).hours.do(lambda: asyncio.create_task(self.sync_users()))

        if os.getenv('ENABLE_LICENSE_OPTIMIZATION', 'true').lower() == 'true':
            schedule.every().day.at("02:00").do(lambda: asyncio.create_task(self.optimize_licenses()))

        # Start API server
        app = web.Application()
        app.router.add_get('/health', self.handle_health)
        app.router.add_post('/api/users/sync', self.handle_sync)
        app.router.add_post('/api/licenses/optimize', self.handle_optimize)

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', 8000)
        await site.start()

        logger.info("API server started on port 8000")

        # Run scheduled tasks
        await self.run_scheduled_tasks()

    async def handle_health(self, request):
        """Handle health check endpoint"""
        health = await self.health_check()
        return web.json_response(health)

    async def handle_sync(self, request):
        """Handle manual sync request"""
        try:
            await self.sync_users()
            return web.json_response({'status': 'success', 'message': 'Sync initiated'})
        except Exception as e:
            return web.json_response({'status': 'error', 'message': str(e)}, status=500)

    async def handle_optimize(self, request):
        """Handle manual optimization request"""
        try:
            await self.optimize_licenses()
            return web.json_response({'status': 'success', 'message': 'Optimization complete'})
        except Exception as e:
            return web.json_response({'status': 'error', 'message': str(e)}, status=500)

async def main():
    """Main entry point"""
    service = AdobeAutomationService()
    try:
        await service.start()
    except KeyboardInterrupt:
        logger.info("Service stopped by user")
    except Exception as e:
        logger.error(f"Service error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())