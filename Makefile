# Adobe Enterprise Automation Makefile

.PHONY: help install test build deploy clean docs monitor

# Default target
help:
	@echo "Adobe Enterprise Automation - Available Commands:"
	@echo "  make install    - Install all dependencies"
	@echo "  make test       - Run all tests"
	@echo "  make build      - Build Docker containers"
	@echo "  make deploy     - Deploy the system"
	@echo "  make monitor    - Start monitoring stack"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make docs       - Generate documentation"

# Install dependencies
install:
	@echo "Installing Python dependencies..."
	pip install -r requirements.txt
	@echo "Installing Node.js dependencies..."
	npm install
	@echo "Installing PowerShell modules..."
	pwsh -Command "Install-Module -Name Az,Pester,PSScriptAnalyzer -Force"

# Run tests
test:
	@echo "Running PowerShell tests..."
	pwsh -Command "Invoke-Pester -Path ./tests -OutputFormat NUnitXml -OutputFile ./test-results-ps.xml"
	@echo "Running Python tests..."
	python -m pytest python-automation/tests --junitxml=test-results-py.xml
	@echo "Running Node.js tests..."
	npm test

# Build Docker containers
build:
	@echo "Building Docker containers..."
	docker-compose build --parallel

# Deploy the system
deploy: build
	@echo "Starting deployment..."
	docker-compose up -d
	@echo "Waiting for services to be ready..."
	sleep 10
	@echo "Running health checks..."
	./scripts/health-check.sh
	@echo "Deployment complete!"

# Start monitoring
monitor:
	@echo "Starting monitoring stack..."
	docker-compose up -d prometheus grafana elasticsearch kibana
	@echo "Monitoring available at:"
	@echo "  Grafana: http://localhost:3000"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Kibana: http://localhost:5601"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf node_modules
	rm -rf __pycache__
	rm -rf .pytest_cache
	rm -rf logs/*
	rm -rf reports/*
	docker-compose down -v
	@echo "Clean complete!"

# Generate documentation
docs:
	@echo "Generating documentation..."
	python scripts/generate_docs.py
	@echo "Documentation generated in ./docs/"

# Development environment
dev:
	@echo "Starting development environment..."
	docker-compose -f docker-compose.dev.yml up

# Production deployment
prod:
	@echo "Deploying to production..."
	./scripts/deploy-production.sh

# Backup system
backup:
	@echo "Creating backup..."
	./scripts/backup.sh

# Restore from backup
restore:
	@echo "Restoring from backup..."
	./scripts/restore.sh

# Security scan
security:
	@echo "Running security scan..."
	npm audit
	pip-audit
	pwsh -Command "Invoke-ScriptAnalyzer -Path . -Recurse"

# Performance test
perf:
	@echo "Running performance tests..."
	python python-automation/tests/performance_test.py

# License optimization
optimize:
	@echo "Running license optimization..."
	pwsh -File ./creative-cloud/license-optimization/Optimize-Licenses.ps1

# User sync
sync:
	@echo "Syncing users..."
	pwsh -File ./creative-cloud/user-provisioning/Sync-Users.ps1

# Generate reports
reports:
	@echo "Generating reports..."
	pwsh -File ./creative-cloud/reporting/Generate-Reports.ps1
	python python-automation/reporting.py

# View logs
logs:
	docker-compose logs -f

# System status
status:
	@echo "System Status:"
	@docker-compose ps
	@echo ""
	@echo "Health Checks:"
	@curl -s http://localhost:8000/health | jq '.'

# Quick start
quickstart: install build deploy monitor
	@echo "Adobe Automation System is ready!"
	@echo "Access points:"
	@echo "  API: http://localhost:8000"
	@echo "  Grafana: http://localhost:3000"
	@echo "  Kibana: http://localhost:5601"