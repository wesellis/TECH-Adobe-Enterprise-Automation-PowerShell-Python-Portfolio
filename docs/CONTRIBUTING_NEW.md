# Contributing to Adobe Enterprise Automation Suite

Thank you for your interest in contributing to the Adobe Enterprise Automation Suite! This document provides guidelines and instructions for contributing to this project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/0/code_of_conduct/). By participating, you are expected to uphold this code. Please report unacceptable behavior to wes@wesellis.com.

## Getting Started

1. **Fork the Repository**: Start by forking the repository to your GitHub account.
2. **Clone Your Fork**: Clone your forked repository to your local machine.
   ```bash
   git clone https://github.com/YOUR_USERNAME/adobe-enterprise-automation.git
   cd adobe-enterprise-automation
   ```
3. **Add Upstream Remote**: Add the original repository as an upstream remote.
   ```bash
   git remote add upstream https://github.com/wesellis/adobe-enterprise-automation.git
   ```

## How to Contribute

### Types of Contributions

- **Bug Fixes**: Help us squash bugs! Check the [Issues](https://github.com/wesellis/adobe-enterprise-automation/issues) page.
- **Feature Development**: Propose and implement new features.
- **Documentation**: Improve existing documentation or add new guides.
- **Testing**: Add or improve test coverage.
- **Performance**: Optimize existing code for better performance.
- **Security**: Report and fix security vulnerabilities.

### Before You Start

1. Check existing [Issues](https://github.com/wesellis/adobe-enterprise-automation/issues) and [Pull Requests](https://github.com/wesellis/adobe-enterprise-automation/pulls) to avoid duplication.
2. For major changes, open an issue first to discuss what you would like to change.
3. Ensure you have signed any required Contributor License Agreement (CLA).

## Development Setup

### Prerequisites

```bash
# Required versions
Node.js: 18.0.0+
Python: 3.9+
PowerShell: 7.0+
Docker: 20.10+
Git: 2.25+
```

### Installation

1. **Install Dependencies**
   ```bash
   # Node.js dependencies
   npm install

   # Python dependencies
   pip install -r requirements.txt
   pip install -r requirements-dev.txt

   # PowerShell modules
   Install-Module -Name Pester -Force
   ```

2. **Environment Configuration**
   ```bash
   # Copy environment template
   cp .env.example .env

   # Edit .env with your configuration
   # Note: Never commit real API credentials
   ```

3. **Verify Installation**
   ```bash
   # Run all tests
   npm test
   pytest
   Invoke-Pester

   # Start development server
   npm run dev
   ```

## Coding Standards

### JavaScript/Node.js

- Follow ESLint configuration (`.eslintrc.json`)
- Use Prettier for formatting (`.prettierrc.json`)
- Use async/await over promises when possible
- Write JSDoc comments for all functions
- Follow functional programming principles where applicable

```javascript
/**
 * Create a new Adobe user
 * @param {Object} userData - User information
 * @param {string} userData.email - User email address
 * @returns {Promise<Object>} Created user object
 */
async function createUser(userData) {
  // Implementation
}
```

### Python

- Follow PEP 8 style guide
- Use type hints for function parameters and returns
- Write docstrings for all functions and classes
- Use Black for formatting
- Keep functions small and focused

```python
def process_users(users: List[Dict[str, Any]]) -> Tuple[int, int]:
    """
    Process a list of users for provisioning.

    Args:
        users: List of user dictionaries

    Returns:
        Tuple of (successful_count, failed_count)
    """
    # Implementation
```

### PowerShell

- Use approved verbs for function names
- Follow PowerShell style guide
- Include comment-based help
- Use proper error handling

```powershell
function New-AdobeUser {
    <#
    .SYNOPSIS
        Creates a new Adobe Creative Cloud user

    .DESCRIPTION
        Provisions a new user in Adobe Admin Console

    .PARAMETER Email
        The user's email address
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email
    )
    # Implementation
}
```

## Testing Guidelines

### Unit Tests

- Write tests for all new functionality
- Maintain minimum 80% code coverage
- Use descriptive test names
- Follow AAA pattern (Arrange, Act, Assert)

### Test Structure

```
tests/
├── unit/           # Unit tests
├── integration/    # Integration tests
├── e2e/           # End-to-end tests
└── fixtures/      # Test data and mocks
```

### Running Tests

```bash
# JavaScript tests
npm test
npm run test:watch
npm run test:coverage

# Python tests
pytest
pytest --cov=python_automation
pytest tests/unit

# PowerShell tests
Invoke-Pester -Path tests
```

## Pull Request Process

1. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-number
   ```

2. **Make Your Changes**
   - Write clean, documented code
   - Add tests for new functionality
   - Update documentation as needed

3. **Commit Your Changes**
   ```bash
   # Use conventional commit format
   git commit -m "feat: add user bulk import feature"
   git commit -m "fix: resolve license calculation error"
   git commit -m "docs: update API documentation"
   ```

4. **Sync with Upstream**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

5. **Run Tests and Linting**
   ```bash
   npm run lint
   npm test
   pytest
   ```

6. **Push to Your Fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create Pull Request**
   - Go to the original repository on GitHub
   - Click "New Pull Request"
   - Select your fork and branch
   - Fill out the PR template completely
   - Link any related issues

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] No security vulnerabilities introduced
```

## Reporting Issues

### Bug Reports

When reporting bugs, please include:

1. **Environment Details**
   - OS and version
   - Node.js/Python/PowerShell version
   - Adobe API version (if applicable)

2. **Steps to Reproduce**
   - Detailed step-by-step instructions
   - Code snippets if applicable
   - Configuration files (sanitized)

3. **Expected vs Actual Behavior**
   - What you expected to happen
   - What actually happened
   - Error messages and logs

4. **Screenshots/Recordings** (if applicable)

### Feature Requests

For feature requests, please include:

1. **Use Case**: Describe the problem you're trying to solve
2. **Proposed Solution**: Your suggested implementation
3. **Alternatives**: Other solutions you've considered
4. **Additional Context**: Any other relevant information

## Code Review Process

All submissions require review before merging:

1. **Automated Checks**: CI/CD pipeline must pass
2. **Code Review**: At least one maintainer approval required
3. **Documentation**: All documentation must be updated
4. **Testing**: Adequate test coverage required

## Documentation

- Update README.md for user-facing changes
- Update API documentation for endpoint changes
- Add inline comments for complex logic
- Update CHANGELOG.md with your changes

## Security

- Never commit sensitive information (API keys, passwords, etc.)
- Report security vulnerabilities privately to wes@wesellis.com
- Follow OWASP guidelines for web security
- Use parameterized queries for database operations
- Validate and sanitize all user inputs

## Questions?

If you have questions, feel free to:

1. Check the [Documentation](docs/)
2. Search existing [Issues](https://github.com/wesellis/adobe-enterprise-automation/issues)
3. Join our [Discussions](https://github.com/wesellis/adobe-enterprise-automation/discussions)
4. Contact the maintainers at wes@wesellis.com

## Recognition

Contributors will be recognized in:
- CONTRIBUTORS.md file
- Release notes
- Project documentation

Thank you for contributing to Adobe Enterprise Automation Suite!