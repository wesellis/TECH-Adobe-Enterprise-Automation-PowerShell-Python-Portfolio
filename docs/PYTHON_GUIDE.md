# Python Integration Guide

## Setup & Installation

```bash
# Create virtual environment
python -m venv adobe-env
source adobe-env/bin/activate  # Linux/Mac
adobe-env\Scripts\activate     # Windows

# Install dependencies
pip install -r requirements.txt
```

## Core Classes

### AdobeClient
```python
import asyncio
import aiohttp
from typing import List, Dict, Optional

class AdobeClient:
    """Async Adobe API Client"""

    def __init__(self, config: Dict):
        self.config = config
        self.session = None
        self.token = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        await self.authenticate()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.session.close()

    async def authenticate(self):
        """Get access token using JWT"""
        jwt_token = self._create_jwt()
        async with self.session.post(
            'https://ims-na1.adobelogin.com/ims/exchange/jwt',
            data={
                'client_id': self.config['client_id'],
                'client_secret': self.config['client_secret'],
                'jwt_token': jwt_token
            }
        ) as resp:
            data = await resp.json()
            self.token = data['access_token']

    async def create_users(self, users: List[Dict]) -> List[Dict]:
        """Bulk create users"""
        tasks = [self._create_user(user) for user in users]
        return await asyncio.gather(*tasks)

    async def _create_user(self, user: Dict) -> Dict:
        """Create single user"""
        headers = {
            'Authorization': f'Bearer {self.token}',
            'X-Api-Key': self.config['client_id']
        }

        async with self.session.post(
            f"{self.config['api_url']}/users",
            headers=headers,
            json=user
        ) as resp:
            return await resp.json()
```

### User Manager
```python
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, List

@dataclass
class AdobeUser:
    """Adobe User Model"""
    email: str
    first_name: str
    last_name: str
    country: str = "US"
    products: List[str] = None
    groups: List[str] = None
    created_at: Optional[datetime] = None
    last_login: Optional[datetime] = None

    def __post_init__(self):
        if self.products is None:
            self.products = []
        if self.groups is None:
            self.groups = []
        if self.created_at is None:
            self.created_at = datetime.now()

class UserManager:
    """Manage Adobe users"""

    def __init__(self, client: AdobeClient):
        self.client = client

    async def provision_users(self, csv_path: str):
        """Provision users from CSV"""
        import pandas as pd

        df = pd.read_csv(csv_path)
        users = []

        for _, row in df.iterrows():
            user = AdobeUser(
                email=row['email'],
                first_name=row['first_name'],
                last_name=row['last_name'],
                products=row.get('products', '').split(';')
            )
            users.append(user)

        results = await self.client.create_users(
            [self._user_to_dict(u) for u in users]
        )

        return self._process_results(users, results)

    def _user_to_dict(self, user: AdobeUser) -> Dict:
        """Convert user object to API format"""
        return {
            'user': {
                'email': user.email,
                'firstname': user.first_name,
                'lastname': user.last_name,
                'country': user.country
            },
            'do': [
                {'addUser': {}},
                {'add': {'product': user.products}} if user.products else {}
            ]
        }

    def _process_results(self, users: List[AdobeUser], results: List[Dict]):
        """Process API results"""
        report = {
            'successful': [],
            'failed': [],
            'stats': {
                'total': len(users),
                'success': 0,
                'failed': 0
            }
        }

        for user, result in zip(users, results):
            if result.get('success'):
                report['successful'].append(user.email)
                report['stats']['success'] += 1
            else:
                report['failed'].append({
                    'email': user.email,
                    'error': result.get('error')
                })
                report['stats']['failed'] += 1

        return report
```

### License Optimizer
```python
import pandas as pd
from datetime import datetime, timedelta

class LicenseOptimizer:
    """Optimize Adobe license allocation"""

    def __init__(self, client: AdobeClient):
        self.client = client

    async def analyze_usage(self, days: int = 30) -> pd.DataFrame:
        """Analyze license usage patterns"""
        users = await self.client.get_all_users()

        df = pd.DataFrame(users)
        df['last_login'] = pd.to_datetime(df['last_login'])
        df['days_inactive'] = (datetime.now() - df['last_login']).dt.days

        # Categorize users
        df['status'] = df['days_inactive'].apply(
            lambda x: 'active' if x < days else 'inactive'
        )

        return df

    async def optimize(self, inactive_days: int = 30) -> Dict:
        """Optimize license allocation"""
        df = await self.analyze_usage(inactive_days)

        inactive_users = df[df['status'] == 'inactive']
        active_users = df[df['status'] == 'active']

        # Calculate savings
        licenses_to_reclaim = len(inactive_users)
        cost_per_license = 50  # Monthly cost
        potential_savings = licenses_to_reclaim * cost_per_license

        # Reclaim licenses
        for email in inactive_users['email']:
            await self.client.remove_all_products(email)

        return {
            'total_users': len(df),
            'active_users': len(active_users),
            'inactive_users': len(inactive_users),
            'licenses_reclaimed': licenses_to_reclaim,
            'monthly_savings': potential_savings,
            'annual_savings': potential_savings * 12
        }

    def generate_report(self, optimization_results: Dict) -> str:
        """Generate optimization report"""
        report = f"""
        License Optimization Report
        ==========================
        Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}

        Summary:
        - Total Users: {optimization_results['total_users']}
        - Active Users: {optimization_results['active_users']}
        - Inactive Users: {optimization_results['inactive_users']}

        Actions Taken:
        - Licenses Reclaimed: {optimization_results['licenses_reclaimed']}

        Cost Savings:
        - Monthly: ${optimization_results['monthly_savings']:,.2f}
        - Annual: ${optimization_results['annual_savings']:,.2f}

        Recommendations:
        - Review inactive users monthly
        - Implement automated license reclamation
        - Consider usage-based allocation
        """
        return report
```

### Monitoring & Alerting
```python
import logging
from prometheus_client import Counter, Histogram, Gauge
import time

# Metrics
api_calls = Counter('adobe_api_calls_total', 'Total API calls')
api_errors = Counter('adobe_api_errors_total', 'Total API errors')
api_latency = Histogram('adobe_api_latency_seconds', 'API latency')
active_users = Gauge('adobe_active_users', 'Number of active users')

class MonitoredClient(AdobeClient):
    """Adobe client with monitoring"""

    @api_latency.time()
    @api_calls.count_exceptions()
    async def make_request(self, method: str, endpoint: str, **kwargs):
        """Make monitored API request"""
        start = time.time()

        try:
            async with self.session.request(
                method, endpoint, **kwargs
            ) as response:
                api_calls.inc()

                if response.status >= 400:
                    api_errors.inc()
                    logging.error(f"API error: {response.status}")

                return await response.json()

        except Exception as e:
            api_errors.inc()
            logging.error(f"Request failed: {e}")
            raise

        finally:
            duration = time.time() - start
            logging.info(f"API call to {endpoint} took {duration:.2f}s")
```

### Batch Processing
```python
from concurrent.futures import ThreadPoolExecutor
import asyncio

class BatchProcessor:
    """Process operations in batches"""

    def __init__(self, client: AdobeClient, batch_size: int = 100):
        self.client = client
        self.batch_size = batch_size

    async def process_csv(self, csv_path: str):
        """Process large CSV in batches"""
        import pandas as pd

        # Read CSV in chunks
        chunks = pd.read_csv(csv_path, chunksize=self.batch_size)

        results = []
        for i, chunk in enumerate(chunks):
            logging.info(f"Processing batch {i+1}")

            batch_results = await self._process_batch(chunk)
            results.extend(batch_results)

            # Rate limiting
            await asyncio.sleep(1)

        return results

    async def _process_batch(self, df: pd.DataFrame):
        """Process single batch"""
        tasks = []

        for _, row in df.iterrows():
            task = self.client.create_user({
                'email': row['email'],
                'firstname': row['first_name'],
                'lastname': row['last_name']
            })
            tasks.append(task)

        return await asyncio.gather(*tasks, return_exceptions=True)
```

### Configuration Management
```python
from pydantic import BaseSettings, Field
from typing import Optional

class AdobeConfig(BaseSettings):
    """Adobe configuration with validation"""

    org_id: str = Field(..., env='ADOBE_ORG_ID')
    client_id: str = Field(..., env='ADOBE_CLIENT_ID')
    client_secret: str = Field(..., env='ADOBE_CLIENT_SECRET')
    tech_account_id: str = Field(..., env='ADOBE_TECH_ACCOUNT')
    private_key_path: str = Field(..., env='ADOBE_PRIVATE_KEY')
    api_url: str = Field(
        default='https://usermanagement.adobe.io/v2',
        env='ADOBE_API_URL'
    )

    class Config:
        env_file = '.env'
        case_sensitive = False

# Usage
config = AdobeConfig()
client = AdobeClient(config.dict())
```

### Testing
```python
import pytest
from unittest.mock import AsyncMock, patch

@pytest.mark.asyncio
async def test_create_user():
    """Test user creation"""
    mock_client = AsyncMock(spec=AdobeClient)
    mock_client.create_user.return_value = {
        'success': True,
        'user': {'email': 'test@example.com'}
    }

    result = await mock_client.create_user({
        'email': 'test@example.com',
        'firstname': 'Test',
        'lastname': 'User'
    })

    assert result['success'] is True
    assert result['user']['email'] == 'test@example.com'

@pytest.mark.asyncio
async def test_license_optimization():
    """Test license optimization"""
    mock_client = AsyncMock(spec=AdobeClient)
    mock_client.get_all_users.return_value = [
        {'email': 'active@example.com', 'last_login': '2024-01-01'},
        {'email': 'inactive@example.com', 'last_login': '2023-01-01'}
    ]

    optimizer = LicenseOptimizer(mock_client)
    results = await optimizer.optimize(inactive_days=30)

    assert results['inactive_users'] == 1
    assert results['licenses_reclaimed'] == 1
```

## CLI Tool
```python
import click
import asyncio

@click.group()
def cli():
    """Adobe Enterprise Automation CLI"""
    pass

@cli.command()
@click.option('--csv', required=True, help='CSV file with users')
@click.option('--products', multiple=True, help='Products to assign')
async def provision(csv, products):
    """Provision users from CSV"""
    async with AdobeClient(config) as client:
        manager = UserManager(client)
        results = await manager.provision_users(csv)
        click.echo(f"Provisioned {results['stats']['success']} users")

@cli.command()
@click.option('--days', default=30, help='Inactive days threshold')
async def optimize(days):
    """Optimize license allocation"""
    async with AdobeClient(config) as client:
        optimizer = LicenseOptimizer(client)
        results = await optimizer.optimize(days)
        click.echo(optimizer.generate_report(results))

if __name__ == '__main__':
    cli()
```

## Best Practices

1. **Use Async/Await for API Calls**
2. **Implement Connection Pooling**
3. **Add Comprehensive Logging**
4. **Use Type Hints**
5. **Implement Retry Logic with Backoff**
6. **Cache Frequently Accessed Data**
7. **Use Environment Variables for Config**
8. **Write Unit Tests for All Functions**
9. **Document All Public APIs**
10. **Monitor Performance Metrics**