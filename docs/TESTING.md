# Testing Guide

## Overview
This project maintains comprehensive test coverage across JavaScript, Python, and PowerShell components.

## Test Coverage Requirements
- **Minimum Coverage**: 80% for critical paths
- **Target Coverage**: 90% overall
- **Required for PR**: All tests must pass

## JavaScript Testing

### Running Tests
```bash
# Run all tests with coverage
npm test

# Run tests in watch mode
npm run test:watch

# Run specific test file
npm test -- api/server.test.js

# Generate coverage report
npm test -- --coverage
```

### Test Structure
```
api/
├── server.js
└── server.test.js    # Main API tests
tests/
└── integration/      # Integration tests
```

### Key Test Areas
- Authentication endpoints
- User management CRUD operations
- License optimization logic
- Rate limiting
- Security headers
- Error handling

## Python Testing

### Running Tests
```bash
# Run all tests with coverage
pytest

# Run specific test file
pytest tests/test_adobe_api_client.py

# Run with verbose output
pytest -v

# Generate HTML coverage report
pytest --cov=python-automation --cov-report=html
```

### Test Structure
```
tests/
├── test_adobe_api_client.py      # API client tests
├── test_bulk_user_processor.py   # Bulk processing tests
└── conftest.py                   # Shared fixtures
```

### Test Categories
- `@pytest.mark.unit` - Unit tests
- `@pytest.mark.integration` - Integration tests
- `@pytest.mark.slow` - Long-running tests
- `@pytest.mark.adobe_api` - Requires Adobe API

## PowerShell Testing

### Running Tests
```powershell
# Run all Pester tests
Invoke-Pester

# Run with coverage
Invoke-Pester -CodeCoverage @("*.ps1")

# Run specific test file
Invoke-Pester -Path tests/Test-AdobeAutomation.ps1
```

### Test Structure
```
tests/
└── Test-AdobeAutomation.ps1    # PowerShell module tests
```

## CI/CD Integration

### GitHub Actions
All tests run automatically on:
- Push to main/develop branches
- Pull requests
- Scheduled weekly security scans

### Test Matrix
- **Node.js**: 16.x, 18.x, 20.x
- **Python**: 3.9, 3.10, 3.11
- **PowerShell**: 7.x on Windows

## Pre-commit Hooks

Tests run automatically before commits:
```bash
# Install pre-commit hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

## Coverage Reports

### Viewing Coverage
```bash
# JavaScript coverage
open coverage/lcov-report/index.html

# Python coverage
open htmlcov/index.html
```

### Coverage Targets
- API endpoints: 100%
- Core business logic: 90%+
- Utility functions: 80%+
- Error handling: 100%

## Mocking and Test Data

### JavaScript Mocks
```javascript
jest.mock('mssql');
jest.mock('redis');
```

### Python Mocks
```python
from unittest.mock import Mock, patch
with patch('module.function') as mock:
    mock.return_value = 'test'
```

## Best Practices

1. **Write tests first** (TDD approach)
2. **Test behavior, not implementation**
3. **Use descriptive test names**
4. **Keep tests isolated and independent**
5. **Mock external dependencies**
6. **Test edge cases and error conditions**

## Debugging Tests

### JavaScript
```bash
# Debug with Node inspector
node --inspect-brk ./node_modules/.bin/jest --runInBand
```

### Python
```bash
# Debug with pytest
pytest --pdb  # Drop into debugger on failure
pytest -s     # Show print statements
```

## Common Test Commands

```bash
# Quick test run (no coverage)
npm run test:quick
pytest --no-cov

# Full test suite
npm test && pytest && pwsh -Command "Invoke-Pester"

# Update snapshots
npm test -- -u
```

## Troubleshooting

### Test Failures
1. Check test environment variables
2. Verify mock configurations
3. Clear test cache: `jest --clearCache`
4. Reset database: `npm run db:reset`

### Coverage Issues
1. Ensure all source files are included
2. Check coverage configuration
3. Verify ignore patterns
4. Run with `--collectCoverageFrom`

## Resources
- [Jest Documentation](https://jestjs.io/docs/getting-started)
- [Pytest Documentation](https://docs.pytest.org/)
- [Pester Documentation](https://pester.dev/docs/quick-start)