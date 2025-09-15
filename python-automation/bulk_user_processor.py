#!/usr/bin/env python3
"""
Adobe Bulk User Processor
Efficiently processes large-scale user operations with async capabilities
"""

import asyncio
import aiohttp
import pandas as pd
import json
import logging
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from pathlib import Path
import jwt
import time
from dataclasses import dataclass, field

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class AdobeUser:
    """Adobe user data model"""
    email: str
    first_name: str
    last_name: str
    country: str = "US"
    products: List[str] = field(default_factory=list)
    groups: List[str] = field(default_factory=list)
    status: str = "active"

    def to_api_format(self) -> Dict:
        """Convert to Adobe API format"""
        return {
            "user": {
                "email": self.email,
                "firstname": self.first_name,
                "lastname": self.last_name,
                "country": self.country
            },
            "do": [
                {"addUser": {}},
                {"add": {"product": self.products}} if self.products else {}
            ]
        }

class AdobeBulkProcessor:
    """High-performance bulk user processor"""

    def __init__(self, config_path: str):
        self.config = self._load_config(config_path)
        self.session = None
        self.access_token = None
        self.token_expiry = None
        self.stats = {
            "processed": 0,
            "successful": 0,
            "failed": 0,
            "start_time": None,
            "end_time": None
        }

    def _load_config(self, path: str) -> Dict:
        """Load configuration from file"""
        with open(path, 'r') as f:
            return json.load(f)

    async def __aenter__(self):
        """Async context manager entry"""
        connector = aiohttp.TCPConnector(limit=50, limit_per_host=10)
        self.session = aiohttp.ClientSession(connector=connector)
        await self._authenticate()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.session.close()

    async def _authenticate(self):
        """Authenticate with Adobe API using JWT"""
        logger.info("Authenticating with Adobe API...")

        # Create JWT token
        payload = {
            'exp': datetime.utcnow() + timedelta(hours=24),
            'iss': self.config['adobe']['org_id'],
            'sub': self.config['adobe']['tech_account_id'],
            'aud': f"https://ims-na1.adobelogin.com/c/{self.config['adobe']['client_id']}",
            'https://ims-na1.adobelogin.com/s/ent_user_sdk': True
        }

        # Read private key
        with open(self.config['adobe']['private_key_path'], 'r') as key_file:
            private_key = key_file.read()

        # Generate JWT
        encoded_jwt = jwt.encode(payload, private_key, algorithm='RS256')

        # Exchange JWT for access token
        token_url = 'https://ims-na1.adobelogin.com/ims/exchange/jwt'
        data = {
            'client_id': self.config['adobe']['client_id'],
            'client_secret': self.config['adobe']['client_secret'],
            'jwt_token': encoded_jwt
        }

        async with self.session.post(token_url, data=data) as resp:
            if resp.status == 200:
                token_data = await resp.json()
                self.access_token = token_data['access_token']
                self.token_expiry = datetime.utcnow() + timedelta(hours=23)
                logger.info("Authentication successful")
            else:
                error = await resp.text()
                raise Exception(f"Authentication failed: {error}")

    async def _ensure_token_valid(self):
        """Ensure access token is still valid"""
        if datetime.utcnow() >= self.token_expiry:
            logger.info("Token expired, re-authenticating...")
            await self._authenticate()

    async def process_csv(self, csv_path: str, batch_size: int = 100):
        """Process users from CSV file"""
        logger.info(f"Processing CSV: {csv_path}")
        self.stats["start_time"] = datetime.now()

        # Read CSV
        df = pd.read_csv(csv_path)
        total_users = len(df)
        logger.info(f"Found {total_users} users to process")

        # Process in batches
        for i in range(0, total_users, batch_size):
            batch = df.iloc[i:i+batch_size]
            await self._process_batch(batch)

            # Progress update
            processed = min(i + batch_size, total_users)
            logger.info(f"Progress: {processed}/{total_users} ({processed*100/total_users:.1f}%)")

        self.stats["end_time"] = datetime.now()
        return self._generate_report()

    async def _process_batch(self, batch: pd.DataFrame):
        """Process a batch of users"""
        await self._ensure_token_valid()

        tasks = []
        for _, row in batch.iterrows():
            user = AdobeUser(
                email=row['email'],
                first_name=row['first_name'],
                last_name=row['last_name'],
                country=row.get('country', 'US'),
                products=row.get('products', '').split(';') if pd.notna(row.get('products')) else []
            )
            tasks.append(self._create_user(user))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Update statistics
        for result in results:
            self.stats["processed"] += 1
            if isinstance(result, Exception):
                self.stats["failed"] += 1
                logger.error(f"Failed to process user: {result}")
            elif result.get('success'):
                self.stats["successful"] += 1
            else:
                self.stats["failed"] += 1

    async def _create_user(self, user: AdobeUser) -> Dict:
        """Create a single user via API"""
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'X-Api-Key': self.config['adobe']['client_id'],
            'Content-Type': 'application/json'
        }

        url = f"https://usermanagement.adobe.io/v2/usermanagement/action/{self.config['adobe']['org_id']}"

        try:
            async with self.session.post(
                url,
                headers=headers,
                json=user.to_api_format(),
                timeout=aiohttp.ClientTimeout(total=30)
            ) as resp:
                if resp.status in [200, 201]:
                    return {"success": True, "email": user.email}
                else:
                    error = await resp.text()
                    return {"success": False, "email": user.email, "error": error}
        except asyncio.TimeoutError:
            return {"success": False, "email": user.email, "error": "Timeout"}
        except Exception as e:
            return {"success": False, "email": user.email, "error": str(e)}

    async def remove_inactive_users(self, inactive_days: int = 30):
        """Remove products from inactive users"""
        logger.info(f"Checking for users inactive for {inactive_days} days...")

        # Get all users
        users = await self._get_all_users()

        # Filter inactive users
        cutoff_date = datetime.now() - timedelta(days=inactive_days)
        inactive_users = [
            u for u in users
            if datetime.fromisoformat(u.get('lastLogin', '2000-01-01')) < cutoff_date
        ]

        logger.info(f"Found {len(inactive_users)} inactive users")

        # Remove products from inactive users
        for user in inactive_users:
            await self._remove_user_products(user['email'])

        return {
            "total_users": len(users),
            "inactive_users": len(inactive_users),
            "licenses_reclaimed": len(inactive_users)
        }

    async def _get_all_users(self) -> List[Dict]:
        """Get all users from Adobe"""
        await self._ensure_token_valid()

        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'X-Api-Key': self.config['adobe']['client_id']
        }

        url = f"https://usermanagement.adobe.io/v2/usermanagement/users/{self.config['adobe']['org_id']}"

        users = []
        page = 0

        while True:
            async with self.session.get(
                url,
                headers=headers,
                params={'page': page}
            ) as resp:
                data = await resp.json()
                users.extend(data.get('users', []))

                if data.get('lastPage', True):
                    break
                page += 1

        return users

    async def _remove_user_products(self, email: str):
        """Remove all products from a user"""
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'X-Api-Key': self.config['adobe']['client_id'],
            'Content-Type': 'application/json'
        }

        body = {
            "user": {"email": email},
            "do": [{"removeFromOrg": {}}]
        }

        url = f"https://usermanagement.adobe.io/v2/usermanagement/action/{self.config['adobe']['org_id']}"

        async with self.session.post(url, headers=headers, json=body) as resp:
            if resp.status in [200, 201]:
                logger.info(f"Removed products from {email}")
            else:
                logger.error(f"Failed to remove products from {email}")

    def _generate_report(self) -> Dict:
        """Generate processing report"""
        duration = (self.stats["end_time"] - self.stats["start_time"]).total_seconds()

        report = {
            "summary": {
                "total_processed": self.stats["processed"],
                "successful": self.stats["successful"],
                "failed": self.stats["failed"],
                "success_rate": f"{self.stats['successful']/max(self.stats['processed'], 1)*100:.1f}%",
                "duration_seconds": duration,
                "users_per_second": self.stats["processed"] / max(duration, 1)
            },
            "timestamp": datetime.now().isoformat()
        }

        # Save report to file
        report_path = f"reports/bulk_processing_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        Path("reports").mkdir(exist_ok=True)

        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)

        logger.info(f"Report saved to {report_path}")
        return report

async def main():
    """Main execution function"""
    import argparse

    parser = argparse.ArgumentParser(description='Adobe Bulk User Processor')
    parser.add_argument('--config', required=True, help='Path to configuration file')
    parser.add_argument('--csv', help='Path to CSV file with users')
    parser.add_argument('--batch-size', type=int, default=100, help='Batch size for processing')
    parser.add_argument('--remove-inactive', type=int, help='Remove inactive users (days)')

    args = parser.parse_args()

    async with AdobeBulkProcessor(args.config) as processor:
        if args.csv:
            report = await processor.process_csv(args.csv, args.batch_size)
            print(f"\nProcessing Complete:")
            print(f"  Total: {report['summary']['total_processed']}")
            print(f"  Success: {report['summary']['successful']}")
            print(f"  Failed: {report['summary']['failed']}")
            print(f"  Success Rate: {report['summary']['success_rate']}")
            print(f"  Duration: {report['summary']['duration_seconds']:.1f}s")

        if args.remove_inactive:
            result = await processor.remove_inactive_users(args.remove_inactive)
            print(f"\nInactive User Cleanup:")
            print(f"  Total Users: {result['total_users']}")
            print(f"  Inactive Users: {result['inactive_users']}")
            print(f"  Licenses Reclaimed: {result['licenses_reclaimed']}")

if __name__ == "__main__":
    asyncio.run(main())