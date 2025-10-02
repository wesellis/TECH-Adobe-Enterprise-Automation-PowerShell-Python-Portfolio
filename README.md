# Adobe Enterprise Automation Suite

Automation toolkit for Adobe Creative Cloud administration using PowerShell, Python, and Node.js.

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat-square&logo=powershell&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat-square&logo=node.js&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

## Overview

This project provides automation scripts and tools to help manage Adobe Creative Cloud users and licenses. It includes PowerShell modules, Python async services, a REST API, and deployment configurations for enterprise environments.

## Features

### User Provisioning
- PowerShell scripts for creating and updating Adobe users
- Python async processing for bulk operations
- Role-based license assignment
- Web dashboard for monitoring

### License Management
- Usage tracking and reporting
- Scripts to identify unused licenses
- ML-based prediction for future license needs (scikit-learn)
- Audit logging for compliance

### REST API
- Express.js server with JWT authentication
- GraphQL API with Apollo Server
- Rate limiting and security middleware
- OpenAPI/Swagger documentation

### Integrations
- **PDF Processing**: Adobe PDF Services API integration for merge, split, OCR, compression
- **ServiceNow**: Bi-directional sync with incident management
- **JIRA**: Automated ticket creation
- **Active Directory**: User synchronization
- **HashiCorp Vault**: Secrets management

### Deployment
- Docker containers and Compose files
- Kubernetes deployment manifests
- Terraform modules for Azure infrastructure
- GitHub Actions CI/CD pipeline

## Requirements

- **PowerShell**: 7.0 or higher
- **Python**: 3.9 or higher
- **Node.js**: 16 or higher
- **Docker**: 20.10+ (for containerized deployment)
- **Kubernetes**: 1.20+ (for K8s deployment)
- **Terraform**: 1.0+ (for Azure IaC)

## Installation

### Using Docker Compose (Recommended)

```bash
git clone https://github.com/yourusername/adobe-enterprise-automation.git
cd adobe-enterprise-automation

# Configure environment
cp .env.example .env
# Edit .env with your Adobe API credentials

# Launch services
cd infrastructure && docker-compose up -d

# Access services
# API: http://localhost:8000
# Dashboard: http://localhost:8000/dashboard
```

### Manual Installation

```bash
# Install Node.js dependencies
npm install

# Install Python dependencies
pip install -r requirements.txt

# Run tests
npm test
pytest
```

## Usage

### PowerShell Module

```powershell
# Import module
Import-Module ./modules/AdobeAutomation/AdobeAutomation.psd1

# Connect to Adobe API
Connect-AdobeAPI -ConfigPath "./config/adobe.json"

# Create user
New-AdobeUser -Email "user@company.com" `
              -FirstName "John" `
              -LastName "Doe" `
              -Products @("Creative Cloud") `
              -Department "Design"

# Generate usage report
Get-AdobeLicenseReport -OutputPath "./reports/usage.csv"
```

### REST API

```javascript
const axios = require('axios');

// Authenticate
const { data: auth } = await axios.post('http://localhost:8000/api/auth/login', {
  username: 'admin@company.com',
  password: 'your_password'
});

// Create user
await axios.post('http://localhost:8000/api/users', {
  email: 'newuser@company.com',
  firstName: 'New',
  lastName: 'User',
  products: ['Creative Cloud']
}, {
  headers: { 'Authorization': `Bearer ${auth.token}` }
});

// Get license utilization
const { data } = await axios.get('http://localhost:8000/api/licenses/utilization', {
  headers: { 'Authorization': `Bearer ${auth.token}` }
});
```

## Project Structure

```
adobe-enterprise-automation/
├── api/                    # Express.js REST API
│   ├── routes/            # API routes
│   ├── middleware/        # Auth & validation
│   └── graphql-*.js       # GraphQL implementation
├── creative-cloud/        # PowerShell automation scripts
├── python-automation/     # Python async services
│   └── ml_license_predictor.py  # ML prediction model
├── pdf-processing/        # PDF manipulation services
├── workers/               # Background job processors
├── database/              # SQL schemas and migrations
├── modules/               # PowerShell modules
├── tests/                 # Test suites
├── examples/              # Sample scripts
│   ├── 01-basic/         # Basic examples
│   ├── 02-intermediate/  # Intermediate examples
│   └── 03-advanced/      # Advanced examples
├── infrastructure/        # Deployment configs
│   ├── kubernetes/       # K8s manifests
│   ├── terraform/        # Azure IaC
│   └── docker-compose.yml
├── docs/                  # Documentation
├── config/                # Configuration files
└── requirements.txt       # Python dependencies
```

## Documentation

- [API Reference](docs/API_REFERENCE.md) - REST API endpoints
- [GraphQL Guide](docs/graphql-guide.md) - GraphQL API documentation
- [Architecture Overview](docs/ARCHITECTURE.md) - System design
- [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) - Production deployment
- [Security Guidelines](docs/SECURITY.md) - Security best practices
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues

## Technology Stack

| Component | Technology |
|-----------|------------|
| Backend API | Node.js + Express |
| GraphQL | Apollo Server |
| Automation | PowerShell 7 |
| Processing | Python 3.11 + AsyncIO |
| ML | scikit-learn |
| Database | SQL Server |
| Cache | Redis |
| Containers | Docker + Kubernetes |
| Cloud | Microsoft Azure |
| IaC | Terraform |
| CI/CD | GitHub Actions |

## Use Cases

- **Bulk User Provisioning**: Import users from CSV files
- **License Optimization**: Identify and reclaim unused licenses
- **Automated Reporting**: Generate monthly usage reports
- **PDF Workflows**: Automate document processing tasks
- **Service Desk Integration**: Connect Adobe provisioning with ServiceNow/JIRA
- **Active Directory Sync**: Keep Adobe users in sync with AD

## Testing

```bash
# Run JavaScript tests
npm test

# Run Python tests
pytest

# Run PowerShell tests
Invoke-Pester

# Check test coverage
npm run coverage
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Clone repository
git clone https://github.com/yourusername/adobe-enterprise-automation.git
cd adobe-enterprise-automation

# Install dependencies
npm install
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Run development server
npm run dev

# Run tests
npm test
pytest
```

## Security

- JWT authentication for API access
- Role-based access control (RBAC)
- Audit logging for all operations
- Integration with HashiCorp Vault for secrets
- TLS encryption for API communication

See [docs/SECURITY.md](docs/SECURITY.md) for detailed security information.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- Adobe for their comprehensive APIs
- Microsoft for Azure AD and Graph API
- Open source community for the tools and libraries used in this project

---

## Project Status & Roadmap

**Completion: ~40%**

### What Works
- ✅ Project structure with organized directories
- ✅ Configuration files (package.json, pyproject.toml, requirements.txt)
- ✅ Docker and infrastructure setup
- ✅ Documentation framework
- ✅ Some scripts exist (71 files found, though many may be stubs)
- ✅ GitHub Actions workflow
- ✅ Makefile for automation

### Known Limitations & Missing Features

**Many Features Described But Not Implemented:**
- ⚠️ **PowerShell Modules**: Only 2 .ps1 files in scripts/ directory
- ⚠️ **Python Automation**: Limited Python scripts despite extensive README claims
- ⚠️ **REST API**: Express.js/GraphQL mentioned but implementation unclear
- ⚠️ **ML Predictions**: scikit-learn mentioned but no ML models found
- ⚠️ **Dashboard**: dashboard/ directory exists but completeness unknown
- ⚠️ **Integrations**: ServiceNow, JIRA, AD sync described but implementation status unclear

**This Appears to Be:**
- ⚠️ **Project Template**: Well-structured skeleton with excellent organization
- ⚠️ **Aspirational README**: README describes enterprise-grade features not fully built
- ⚠️ **Portfolio Piece**: Demonstrates knowledge of enterprise architecture patterns

**Missing/Incomplete:**
- ❌ **User Provisioning Scripts**: Limited PowerShell automation despite claims
- ❌ **License Management**: Analytics and reporting not verified
- ❌ **PDF Processing**: Integration mentioned but unclear if functional
- ❌ **Testing**: tests/ directory exists but coverage unknown
- ❌ **Deployment Ready**: Docker/K8s configs present but not production-tested

### What Needs Work

1. **Implement Core Scripts** - Build out PowerShell user provisioning
2. **Complete Python Automation** - Add async processing for bulk operations
3. **Build REST API** - Implement Express.js/GraphQL server
4. **Add ML Models** - Implement license prediction with scikit-learn
5. **Complete Dashboard** - Finish React/Node.js monitoring dashboard
6. **Integration Testing** - Verify all integrations actually work
7. **Documentation** - Match README to actual implementation
8. **Production Hardening** - Security audit and performance testing

### Current Status

This is a **well-architected project skeleton** that demonstrates understanding of enterprise automation patterns. The directory structure, configuration files, and infrastructure setup show professional organization.

However, the README describes a fully-featured enterprise automation suite, while the actual implementation appears to be in early stages. Only ~2 PowerShell scripts exist despite extensive claims about automation capabilities.

This is valuable as a **reference architecture** or **starting template**, but should not be presented as a complete, production-ready enterprise solution.

### Recommendation

Either:
1. **Update README** to reflect actual implementation status
2. **Build out features** to match the current README description
3. **Clearly label** as "Architecture Template" rather than complete solution

### Contributing

If you'd like to help implement the described features, contributions are welcome. Priority areas:
1. Building PowerShell user provisioning automation
2. Implementing Python async processing
3. Creating functional REST API
4. Adding comprehensive tests

---

**Note**: This is a portfolio/demonstration project showing enterprise automation architecture. README describes aspirational features - actual implementation is a foundation/template. Modify and test thoroughly before using in production environments.

