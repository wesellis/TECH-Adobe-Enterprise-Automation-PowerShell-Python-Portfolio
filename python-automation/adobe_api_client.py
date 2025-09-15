#!/usr/bin/env python3
"""
Adobe API Client - Async Python client for Adobe User Management API
"""

import asyncio
import aiohttp
from typing import List, Dict, Optional, Any
import jwt
from datetime import datetime, timedelta
import logging
import json
from functools import wraps
import time

logger = logging.getLogger(__name__)

def retry_on_error(max_retries: int = 3, backoff_factor: float = 2.0):
    """Decorator for retry logic with exponential backoff"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            last_exception = None
            for attempt in range(max_retries):
                try:
                    return await func(*args, **kwargs)
                except (aiohttp.ClientError, asyncio.TimeoutError) as e:
                    last_exception = e
                    if attempt < max_retries - 1:
                        wait_time = backoff_factor ** attempt
                        logger.warning(f"Attempt {attempt + 1} failed, retrying in {wait_time}s...")
                        await asyncio.sleep(wait_time)
                    else:
                        logger.error(f"All {max_retries} attempts failed")
            raise last_exception
        return wrapper
    return decorator

class AdobeAPIClient:
    """Async Adobe User Management API client"""

    def __init__(
        self,
        org_id: str,
        client_id: str,
        client_secret: str,
        tech_account_id: str,
        private_key_path: str,
        api_base_url: str = "https://usermanagement.adobe.io"
    ):
        self.org_id = org_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.tech_account_id = tech_account_id
        self.private_key_path = private_key_path
        self.api_base_url = api_base_url
        self.session = None
        self.access_token = None
        self.token_expiry = None

    async def __aenter__(self):
        """Context manager entry"""
        self.session = aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(
                limit=100,
                limit_per_host=20,
                keepalive_timeout=30
            ),
            timeout=aiohttp.ClientTimeout(total=60)
        )
        await self.authenticate()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        if self.session:
            await self.session.close()

    async def authenticate(self):
        """Authenticate and get access token"""
        logger.info("Authenticating with Adobe API...")

        # Create JWT
        with open(self.private_key_path, 'r') as f:
            private_key = f.read()

        payload = {
            'exp': datetime.utcnow() + timedelta(hours=24),
            'iss': self.org_id,
            'sub': self.tech_account_id,
            'aud': f"https://ims-na1.adobelogin.com/c/{self.client_id}",
            'https://ims-na1.adobelogin.com/s/ent_user_sdk': True
        }

        encoded_jwt = jwt.encode(payload, private_key, algorithm='RS256')

        # Exchange for access token
        data = {
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'jwt_token': encoded_jwt
        }

        async with self.session.post(
            'https://ims-na1.adobelogin.com/ims/exchange/jwt',
            data=data
        ) as resp:
            if resp.status == 200:
                token_data = await resp.json()
                self.access_token = token_data['access_token']
                self.token_expiry = datetime.utcnow() + timedelta(hours=23)
                logger.info("Authentication successful")
            else:
                raise Exception(f"Authentication failed: {await resp.text()}")

    async def _ensure_authenticated(self):
        """Ensure we have a valid token"""
        if not self.access_token or datetime.utcnow() >= self.token_expiry:
            await self.authenticate()

    def _get_headers(self) -> Dict[str, str]:
        """Get API request headers"""
        return {
            'Authorization': f'Bearer {self.access_token}',
            'X-Api-Key': self.client_id,
            'Content-Type': 'application/json'
        }

    @retry_on_error(max_retries=3)
    async def create_user(
        self,
        email: str,
        first_name: str,
        last_name: str,
        country: str = "US",
        products: Optional[List[str]] = None,
        groups: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Create a new Adobe user"""
        await self._ensure_authenticated()

        payload = {
            "user": {
                "email": email,
                "firstname": first_name,
                "lastname": last_name,
                "country": country
            },
            "do": [{"addUser": {}}]
        }

        if products:
            payload["do"].append({"add": {"product": products}})

        if groups:
            payload["do"].append({"add": {"group": groups}})

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    @retry_on_error(max_retries=3)
    async def get_user(self, email: str) -> Optional[Dict[str, Any]]:
        """Get user information"""
        await self._ensure_authenticated()

        url = f"{self.api_base_url}/v2/usermanagement/users/{self.org_id}"
        params = {"email": email}

        async with self.session.get(
            url,
            headers=self._get_headers(),
            params=params
        ) as resp:
            data = await self._handle_response(resp)
            users = data.get("users", [])
            return users[0] if users else None

    @retry_on_error(max_retries=3)
    async def update_user(
        self,
        email: str,
        updates: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Update user information"""
        await self._ensure_authenticated()

        payload = {
            "user": {"email": email},
            "do": [{"update": updates}]
        }

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    @retry_on_error(max_retries=3)
    async def delete_user(self, email: str) -> Dict[str, Any]:
        """Remove user from organization"""
        await self._ensure_authenticated()

        payload = {
            "user": {"email": email},
            "do": [{"removeFromOrg": {}}]
        }

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    async def get_all_users(
        self,
        page_size: int = 100
    ) -> List[Dict[str, Any]]:
        """Get all users in the organization"""
        await self._ensure_authenticated()

        url = f"{self.api_base_url}/v2/usermanagement/users/{self.org_id}"
        users = []
        page = 0

        while True:
            params = {"page": page, "pageSize": page_size}

            async with self.session.get(
                url,
                headers=self._get_headers(),
                params=params
            ) as resp:
                data = await self._handle_response(resp)
                users.extend(data.get("users", []))

                if data.get("lastPage", True):
                    break
                page += 1

        return users

    async def assign_products(
        self,
        email: str,
        products: List[str]
    ) -> Dict[str, Any]:
        """Assign products to user"""
        await self._ensure_authenticated()

        payload = {
            "user": {"email": email},
            "do": [{"add": {"product": products}}]
        }

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    async def remove_products(
        self,
        email: str,
        products: List[str]
    ) -> Dict[str, Any]:
        """Remove products from user"""
        await self._ensure_authenticated()

        payload = {
            "user": {"email": email},
            "do": [{"remove": {"product": products}}]
        }

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    async def get_products(self) -> List[Dict[str, Any]]:
        """Get available products"""
        await self._ensure_authenticated()

        url = f"{self.api_base_url}/v2/usermanagement/products/{self.org_id}"

        async with self.session.get(
            url,
            headers=self._get_headers()
        ) as resp:
            data = await self._handle_response(resp)
            return data.get("products", [])

    async def get_groups(self) -> List[Dict[str, Any]]:
        """Get all user groups"""
        await self._ensure_authenticated()

        url = f"{self.api_base_url}/v2/usermanagement/groups/{self.org_id}"

        async with self.session.get(
            url,
            headers=self._get_headers()
        ) as resp:
            data = await self._handle_response(resp)
            return data.get("groups", [])

    async def create_group(
        self,
        name: str,
        description: str = ""
    ) -> Dict[str, Any]:
        """Create a new user group"""
        await self._ensure_authenticated()

        payload = {
            "do": [{
                "addUserGroup": {
                    "group": name,
                    "description": description
                }
            }]
        }

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    async def add_to_group(
        self,
        email: str,
        groups: List[str]
    ) -> Dict[str, Any]:
        """Add user to groups"""
        await self._ensure_authenticated()

        payload = {
            "user": {"email": email},
            "do": [{"add": {"group": groups}}]
        }

        url = f"{self.api_base_url}/v2/usermanagement/action/{self.org_id}"

        async with self.session.post(
            url,
            headers=self._get_headers(),
            json=payload
        ) as resp:
            return await self._handle_response(resp)

    async def _handle_response(self, response: aiohttp.ClientResponse) -> Dict[str, Any]:
        """Handle API response"""
        if response.status in [200, 201]:
            return await response.json()
        elif response.status == 429:
            # Rate limited
            retry_after = int(response.headers.get('Retry-After', 60))
            logger.warning(f"Rate limited, waiting {retry_after} seconds")
            await asyncio.sleep(retry_after)
            raise aiohttp.ClientError("Rate limited")
        else:
            error_text = await response.text()
            logger.error(f"API error {response.status}: {error_text}")
            raise aiohttp.ClientError(f"API error {response.status}: {error_text}")

# Example usage
async def example_usage():
    """Example of how to use the API client"""
    config = {
        "org_id": "YOUR_ORG_ID@AdobeOrg",
        "client_id": "YOUR_CLIENT_ID",
        "client_secret": "YOUR_CLIENT_SECRET",
        "tech_account_id": "YOUR_TECH_ID@techacct.adobe.com",
        "private_key_path": "private.key"
    }

    async with AdobeAPIClient(**config) as client:
        # Create a user
        user = await client.create_user(
            email="test@example.com",
            first_name="Test",
            last_name="User",
            products=["Creative Cloud"]
        )
        print(f"Created user: {user}")

        # Get all users
        all_users = await client.get_all_users()
        print(f"Total users: {len(all_users)}")

        # Get available products
        products = await client.get_products()
        print(f"Available products: {[p['name'] for p in products]}")

if __name__ == "__main__":
    # Run example
    asyncio.run(example_usage())