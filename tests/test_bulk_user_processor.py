"""Tests for Bulk User Processor module."""

import pytest
import asyncio
from unittest.mock import Mock, patch, AsyncMock, MagicMock
import pandas as pd
import sys
import os
from datetime import datetime, timedelta

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from python_automation.bulk_user_processor import BulkUserProcessor


class TestBulkUserProcessor:
    """Test suite for Bulk User Processor."""

    @pytest.fixture
    def processor(self):
        """Create processor instance for testing."""
        with patch('python_automation.adobe_api_client.AdobeAPIClient'):
            return BulkUserProcessor()

    @pytest.fixture
    def sample_csv_data(self, tmp_path):
        """Create sample CSV file for testing."""
        csv_file = tmp_path / "users.csv"
        data = pd.DataFrame({
            'email': ['user1@example.com', 'user2@example.com', 'user3@example.com'],
            'firstName': ['John', 'Jane', 'Bob'],
            'lastName': ['Doe', 'Smith', 'Johnson'],
            'department': ['Marketing', 'Design', 'Engineering'],
            'products': ['Creative Cloud', 'Acrobat Pro', 'Creative Cloud']
        })
        data.to_csv(csv_file, index=False)
        return str(csv_file)

    @pytest.mark.unit
    def test_initialization(self, processor):
        """Test processor initialization."""
        assert processor is not None
        assert hasattr(processor, 'batch_size')
        assert hasattr(processor, 'max_workers')

    @pytest.mark.unit
    def test_load_csv(self, processor, sample_csv_data):
        """Test loading users from CSV."""
        users = processor.load_users_from_csv(sample_csv_data)
        assert len(users) == 3
        assert users[0]['email'] == 'user1@example.com'
        assert users[1]['firstName'] == 'Jane'

    @pytest.mark.unit
    def test_validate_users(self, processor):
        """Test user validation."""
        valid_users = [
            {'email': 'valid@example.com', 'firstName': 'Valid', 'lastName': 'User'},
            {'email': 'another@example.com', 'firstName': 'Another', 'lastName': 'User'}
        ]
        invalid_users = [
            {'email': 'invalid-email', 'firstName': 'Invalid', 'lastName': 'User'},
            {'email': 'missing@example.com', 'firstName': '', 'lastName': 'User'},
            {'email': '', 'firstName': 'No', 'lastName': 'Email'}
        ]

        valid, invalid = processor.validate_users(valid_users + invalid_users)
        assert len(valid) == 2
        assert len(invalid) == 3

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_process_batch(self, processor):
        """Test processing a batch of users."""
        batch = [
            {'email': f'user{i}@example.com', 'firstName': f'User{i}', 'lastName': 'Test'}
            for i in range(5)
        ]

        with patch.object(processor.api_client, 'create_user', new_callable=AsyncMock) as mock_create:
            mock_create.return_value = {'status': 'created'}
            results = await processor.process_batch(batch)
            assert len(results) == 5
            assert all(r['status'] == 'created' for r in results)
            assert mock_create.call_count == 5

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_process_all_users(self, processor):
        """Test processing all users with batching."""
        users = [
            {'email': f'user{i}@example.com', 'firstName': f'User{i}', 'lastName': 'Test'}
            for i in range(25)
        ]
        processor.batch_size = 10

        with patch.object(processor, 'process_batch', new_callable=AsyncMock) as mock_batch:
            mock_batch.return_value = [{'status': 'created'}] * 10
            results = await processor.process_all_users(users)
            assert len(results) == 25
            assert mock_batch.call_count == 3  # 10 + 10 + 5

    @pytest.mark.unit
    def test_generate_report(self, processor, tmp_path):
        """Test report generation."""
        results = [
            {'email': 'user1@example.com', 'status': 'created'},
            {'email': 'user2@example.com', 'status': 'created'},
            {'email': 'user3@example.com', 'status': 'failed', 'error': 'Already exists'}
        ]

        report_file = tmp_path / "report.json"
        processor.generate_report(results, str(report_file))

        assert report_file.exists()
        with open(report_file) as f:
            report = eval(f.read())  # Using eval for simplicity in test
            assert report['total'] == 3
            assert report['successful'] == 2
            assert report['failed'] == 1

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_retry_logic(self, processor):
        """Test retry logic for failed operations."""
        user = {'email': 'user@example.com', 'firstName': 'Test', 'lastName': 'User'}

        with patch.object(processor.api_client, 'create_user', new_callable=AsyncMock) as mock_create:
            # First two calls fail, third succeeds
            mock_create.side_effect = [
                Exception("Temporary failure"),
                Exception("Another failure"),
                {'status': 'created'}
            ]

            result = await processor.create_user_with_retry(user, max_retries=3)
            assert result['status'] == 'created'
            assert mock_create.call_count == 3

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_concurrent_processing(self, processor):
        """Test concurrent processing with worker pool."""
        users = [
            {'email': f'user{i}@example.com', 'firstName': f'User{i}', 'lastName': 'Test'}
            for i in range(20)
        ]
        processor.max_workers = 5

        start_time = datetime.now()

        with patch.object(processor.api_client, 'create_user', new_callable=AsyncMock) as mock_create:
            async def slow_create(user):
                await asyncio.sleep(0.1)
                return {'status': 'created'}

            mock_create.side_effect = slow_create
            results = await processor.process_concurrent(users)

            elapsed = (datetime.now() - start_time).total_seconds()
            # Should take ~0.4 seconds with 5 workers (20 users / 5 workers * 0.1 sec)
            # Not ~2 seconds if processed sequentially
            assert elapsed < 1.0
            assert len(results) == 20

    @pytest.mark.unit
    def test_duplicate_detection(self, processor):
        """Test duplicate user detection."""
        users = [
            {'email': 'user1@example.com', 'firstName': 'User', 'lastName': 'One'},
            {'email': 'user2@example.com', 'firstName': 'User', 'lastName': 'Two'},
            {'email': 'user1@example.com', 'firstName': 'Duplicate', 'lastName': 'User'},
            {'email': 'user3@example.com', 'firstName': 'User', 'lastName': 'Three'},
            {'email': 'user2@example.com', 'firstName': 'Another', 'lastName': 'Duplicate'}
        ]

        unique_users, duplicates = processor.remove_duplicates(users)
        assert len(unique_users) == 3
        assert len(duplicates) == 2
        assert duplicates[0]['email'] == 'user1@example.com'

    @pytest.mark.unit
    def test_license_assignment(self, processor):
        """Test license assignment based on department."""
        users = [
            {'email': 'user1@example.com', 'department': 'Marketing'},
            {'email': 'user2@example.com', 'department': 'Design'},
            {'email': 'user3@example.com', 'department': 'Engineering'}
        ]

        license_rules = {
            'Marketing': ['Creative Cloud', 'Analytics'],
            'Design': ['Creative Cloud', 'XD', 'Photoshop'],
            'Engineering': ['Acrobat Pro']
        }

        assigned_users = processor.assign_licenses_by_department(users, license_rules)
        assert assigned_users[0]['products'] == ['Creative Cloud', 'Analytics']
        assert assigned_users[1]['products'] == ['Creative Cloud', 'XD', 'Photoshop']
        assert assigned_users[2]['products'] == ['Acrobat Pro']

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_error_handling(self, processor):
        """Test comprehensive error handling."""
        users = [
            {'email': 'valid@example.com', 'firstName': 'Valid', 'lastName': 'User'},
            {'email': 'error@example.com', 'firstName': 'Error', 'lastName': 'User'},
            {'email': 'another@example.com', 'firstName': 'Another', 'lastName': 'User'}
        ]

        with patch.object(processor.api_client, 'create_user', new_callable=AsyncMock) as mock_create:
            async def create_with_error(user):
                if user['email'] == 'error@example.com':
                    raise Exception("API Error")
                return {'status': 'created'}

            mock_create.side_effect = create_with_error
            results = await processor.process_all_users(users)

            success = [r for r in results if r.get('status') == 'created']
            failures = [r for r in results if r.get('status') == 'failed']

            assert len(success) == 2
            assert len(failures) == 1
            assert failures[0]['email'] == 'error@example.com'

    @pytest.mark.integration
    @pytest.mark.requires_db
    def test_database_sync(self, processor):
        """Test syncing processed users with database."""
        pytest.skip("Requires database connection")

    @pytest.mark.unit
    def test_progress_tracking(self, processor):
        """Test progress tracking during bulk operations."""
        total_users = 100
        processor.start_progress_tracking(total_users)

        for i in range(total_users):
            processor.update_progress(i + 1)
            progress = processor.get_progress()
            assert progress['processed'] == i + 1
            assert progress['total'] == total_users
            assert progress['percentage'] == ((i + 1) / total_users) * 100

    @pytest.mark.unit
    @pytest.mark.asyncio
    async def test_circuit_breaker(self, processor):
        """Test circuit breaker pattern for API failures."""
        processor.circuit_breaker_threshold = 3
        processor.circuit_breaker_timeout = 1

        with patch.object(processor.api_client, 'create_user', new_callable=AsyncMock) as mock_create:
            mock_create.side_effect = Exception("API Down")

            # Should open circuit after 3 failures
            for i in range(5):
                user = {'email': f'user{i}@example.com', 'firstName': 'Test', 'lastName': 'User'}
                result = await processor.create_user_with_circuit_breaker(user)
                if i >= 3:
                    assert result['status'] == 'circuit_open'
                else:
                    assert result['status'] == 'failed'