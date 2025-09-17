"""Tests for Adobe API Client module."""

import pytest
import asyncio
from unittest.mock import Mock, patch, AsyncMock
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from python_automation.adobe_api_client import AdobeAPIClient


class TestAdobeAPIClient:
    """Test suite for Adobe API Client."""

    @pytest.fixture
    def api_client(self):
        """Create API client instance for testing."""
        with patch.dict(os.environ, {
            'ADOBE_CLIENT_ID': 'test_client_id',
            'ADOBE_CLIENT_SECRET': 'test_secret',
            'ADOBE_ORG_ID': 'test_org_id',
            'ADOBE_API_KEY': 'test_api_key'
        }):
            return AdobeAPIClient()

    @pytest.fixture
    def mock_session(self):
        """Create mock aiohttp session."""
        session = AsyncMock()
        session.__aenter__ = AsyncMock(return_value=session)
        session.__aexit__ = AsyncMock(return_value=None)
        return session

    @pytest.mark.unit
    def test_initialization(self, api_client):
        """Test client initialization."""
        assert api_client is not None
        assert hasattr(api_client, 'base_url')
        assert hasattr(api_client, 'headers')

    @pytest.mark.unit
    def test_missing_credentials(self):
        """Test initialization with missing credentials."""
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ValueError, match="Missing required Adobe credentials"):
                AdobeAPIClient()

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_authenticate(self, api_client, mock_session):
        """Test authentication flow."""
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value={'access_token': 'test_token'})

        mock_session.post = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            token = await api_client.authenticate()
            assert token == 'test_token'

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_get_users(self, api_client, mock_session):
        """Test getting users from Adobe API."""
        api_client.access_token = 'test_token'

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value={
            'users': [
                {'email': 'user1@example.com', 'firstName': 'User', 'lastName': 'One'},
                {'email': 'user2@example.com', 'firstName': 'User', 'lastName': 'Two'}
            ]
        })

        mock_session.get = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            users = await api_client.get_users()
            assert len(users) == 2
            assert users[0]['email'] == 'user1@example.com'

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_create_user(self, api_client, mock_session):
        """Test creating a new user."""
        api_client.access_token = 'test_token'

        new_user = {
            'email': 'newuser@example.com',
            'firstName': 'New',
            'lastName': 'User',
            'products': ['Creative Cloud']
        }

        mock_response = AsyncMock()
        mock_response.status = 201
        mock_response.json = AsyncMock(return_value={
            'user': new_user,
            'status': 'created'
        })

        mock_session.post = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            result = await api_client.create_user(new_user)
            assert result['status'] == 'created'
            assert result['user']['email'] == new_user['email']

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_delete_user(self, api_client, mock_session):
        """Test deleting a user."""
        api_client.access_token = 'test_token'

        mock_response = AsyncMock()
        mock_response.status = 204

        mock_session.delete = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            result = await api_client.delete_user('user@example.com')
            assert result is True

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_get_licenses(self, api_client, mock_session):
        """Test getting license information."""
        api_client.access_token = 'test_token'

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value={
            'licenses': {
                'total': 100,
                'used': 75,
                'available': 25
            }
        })

        mock_session.get = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            licenses = await api_client.get_licenses()
            assert licenses['total'] == 100
            assert licenses['used'] == 75
            assert licenses['available'] == 25

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_rate_limiting(self, api_client, mock_session):
        """Test rate limiting handling."""
        api_client.access_token = 'test_token'

        # First response: rate limited
        rate_limited_response = AsyncMock()
        rate_limited_response.status = 429
        rate_limited_response.headers = {'Retry-After': '2'}

        # Second response: success
        success_response = AsyncMock()
        success_response.status = 200
        success_response.json = AsyncMock(return_value={'users': []})

        mock_session.get = AsyncMock(side_effect=[rate_limited_response, success_response])

        with patch('aiohttp.ClientSession', return_value=mock_session):
            with patch('asyncio.sleep', new_callable=AsyncMock):
                users = await api_client.get_users()
                assert users == []

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_error_handling(self, api_client, mock_session):
        """Test error handling for API failures."""
        api_client.access_token = 'test_token'

        mock_response = AsyncMock()
        mock_response.status = 500
        mock_response.json = AsyncMock(return_value={'error': 'Internal Server Error'})

        mock_session.get = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            with pytest.raises(Exception, match="API request failed"):
                await api_client.get_users()

    @pytest.mark.unit
    def test_validate_email(self, api_client):
        """Test email validation."""
        assert api_client.validate_email('user@example.com') is True
        assert api_client.validate_email('invalid-email') is False
        assert api_client.validate_email('user@') is False
        assert api_client.validate_email('@example.com') is False

    @pytest.mark.integration
    @pytest.mark.adobe_api
    @pytest.mark.asyncio
    async def test_full_user_lifecycle(self, api_client):
        """Integration test for complete user lifecycle."""
        # This test would run against actual Adobe API in integration environment
        pytest.skip("Requires Adobe API credentials and test environment")

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_batch_operations(self, api_client, mock_session):
        """Test batch user operations."""
        api_client.access_token = 'test_token'

        users = [
            {'email': f'user{i}@example.com', 'firstName': f'User{i}', 'lastName': 'Test'}
            for i in range(10)
        ]

        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json = AsyncMock(return_value={'processed': len(users)})

        mock_session.post = AsyncMock(return_value=mock_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            result = await api_client.batch_create_users(users)
            assert result['processed'] == 10

    @pytest.mark.unit
    def test_connection_pooling(self, api_client):
        """Test connection pool configuration."""
        assert hasattr(api_client, 'max_connections')
        assert api_client.max_connections > 0

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_token_refresh(self, api_client, mock_session):
        """Test automatic token refresh on expiry."""
        api_client.access_token = 'expired_token'

        # First call: unauthorized
        unauthorized_response = AsyncMock()
        unauthorized_response.status = 401

        # Auth response
        auth_response = AsyncMock()
        auth_response.status = 200
        auth_response.json = AsyncMock(return_value={'access_token': 'new_token'})

        # Second call: success
        success_response = AsyncMock()
        success_response.status = 200
        success_response.json = AsyncMock(return_value={'users': []})

        mock_session.get = AsyncMock(side_effect=[unauthorized_response, success_response])
        mock_session.post = AsyncMock(return_value=auth_response)

        with patch('aiohttp.ClientSession', return_value=mock_session):
            users = await api_client.get_users()
            assert users == []
            assert api_client.access_token == 'new_token'