# Security Notice

## About Tokens in Git History

This repository's git history contains placeholder tokens such as `"actual_token_here"` which are **NOT real tokens or credentials**. These are:

- ✅ Placeholder strings for demonstration purposes
- ✅ Fixed in later commits with proper authentication methods
- ✅ Never contained actual API keys or secrets

## Security Best Practices

This project follows security best practices:

1. **Environment Variables** - All real credentials should be stored in `.env` files (not committed)
2. **Secrets Management** - Production deployments should use HashiCorp Vault or Azure Key Vault
3. **JWT Authentication** - API uses proper JWT token authentication
4. **Never Commit Secrets** - Real API keys, passwords, or tokens should never be committed

## If You Fork This Repository

1. Never add real credentials to any files
2. Use environment variables for all sensitive data
3. Add `.env` to your `.gitignore`
4. Use proper secrets management in production

## Reporting Security Issues

If you discover a security vulnerability, please email wes@wesellis.com directly rather than creating a public issue.