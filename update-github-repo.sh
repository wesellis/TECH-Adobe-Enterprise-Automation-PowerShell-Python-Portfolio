#!/bin/bash

# Update GitHub Repository Settings Script
# This script updates your GitHub repository description and topics using GitHub CLI

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Updating GitHub Repository Settings${NC}\n"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠️  GitHub CLI (gh) is not installed.${NC}"
    echo "Please install it first:"
    echo "  macOS: brew install gh"
    echo "  Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    echo "  Windows: winget install --id GitHub.cli"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not authenticated with GitHub CLI.${NC}"
    echo "Please run: gh auth login"
    exit 1
fi

# Get repository name (you may need to adjust this based on your actual repo name)
REPO_OWNER=$(gh repo view --json owner -q .owner.login 2>/dev/null)
REPO_NAME=$(gh repo view --json name -q .name 2>/dev/null)

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ]; then
    echo -e "${YELLOW}⚠️  Could not detect repository. Please run this script from the repository root.${NC}"
    echo "Or set manually:"
    echo "  REPO_OWNER=your-username"
    echo "  REPO_NAME=TECH-Adobe-Enterprise-Automation-PowerShell-Python-Portfolio"

    # Fallback - ask for input
    read -p "Enter your GitHub username: " REPO_OWNER
    read -p "Enter repository name [TECH-Adobe-Enterprise-Automation-PowerShell-Python-Portfolio]: " REPO_NAME
    REPO_NAME=${REPO_NAME:-TECH-Adobe-Enterprise-Automation-PowerShell-Python-Portfolio}
fi

echo -e "Repository: ${GREEN}$REPO_OWNER/$REPO_NAME${NC}\n"

# Update repository description
echo -e "${BLUE}📝 Updating repository description...${NC}"
gh repo edit "$REPO_OWNER/$REPO_NAME" \
    --description "🚀 Enterprise-grade Adobe Creative Cloud automation toolkit with PowerShell/Python scripts, REST/GraphQL APIs, ML predictions, JIRA integration, and Azure deployment via Terraform" \
    --homepage "https://github.com/$REPO_OWNER/$REPO_NAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Description updated successfully!${NC}\n"
else
    echo -e "${YELLOW}⚠️  Failed to update description${NC}\n"
fi

# Update repository topics
echo -e "${BLUE}🏷️  Updating repository topics...${NC}"
gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO_OWNER/$REPO_NAME/topics" \
    -f names='["adobe-creative-cloud","powershell","python","automation","enterprise","rest-api","graphql","machine-learning","terraform","azure","docker","kubernetes","jira-integration","hashicorp-vault","license-management"]' \
    > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Topics updated successfully!${NC}\n"
else
    echo -e "${YELLOW}⚠️  Failed to update topics${NC}\n"
fi

# Enable useful features
echo -e "${BLUE}⚙️  Configuring repository features...${NC}"

# Enable issues
gh api \
    --method PATCH \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO_OWNER/$REPO_NAME" \
    -f has_issues=true \
    -f has_wiki=true \
    -f has_projects=true \
    > /dev/null 2>&1

echo -e "${GREEN}✅ Issues, Wiki, and Projects enabled${NC}"

# Try to enable discussions (may require higher permissions)
gh api \
    --method PATCH \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO_OWNER/$REPO_NAME" \
    -f has_discussions=true \
    > /dev/null 2>&1 && echo -e "${GREEN}✅ Discussions enabled${NC}" || echo -e "${YELLOW}⚠️  Could not enable Discussions (may need to be done manually)${NC}"

# Add custom properties if the feature is available
echo -e "\n${BLUE}📊 Setting custom properties...${NC}"
gh api \
    --method PATCH \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO_OWNER/$REPO_NAME" \
    -f allow_squash_merge=true \
    -f allow_merge_commit=true \
    -f allow_rebase_merge=true \
    -f delete_branch_on_merge=true \
    -f allow_auto_merge=true \
    > /dev/null 2>&1

echo -e "${GREEN}✅ Repository settings configured${NC}"

# Display current repository info
echo -e "\n${BLUE}📋 Current Repository Information:${NC}"
gh repo view "$REPO_OWNER/$REPO_NAME" --json description,topics,homepageUrl | jq '.'

echo -e "\n${GREEN}🎉 Repository update complete!${NC}"
echo -e "\nTo view your repository: ${BLUE}https://github.com/$REPO_OWNER/$REPO_NAME${NC}"
echo -e "\nAdditional manual steps recommended:"
echo "  1. Add a social preview image (Settings → Options → Social preview)"
echo "  2. Configure branch protection rules (Settings → Branches)"
echo "  3. Set up environments (Settings → Environments)"
echo "  4. Enable Dependabot (Settings → Security & analysis)"
echo "  5. Add issue and PR templates (.github/ISSUE_TEMPLATE/)"

# Create a Python alternative if preferred
cat > update-github-repo.py << 'EOF'
#!/usr/bin/env python3
"""
Alternative Python script to update GitHub repository settings
Requires: pip install PyGithub
"""

import os
import sys
from github import Github

# Configuration
REPO_NAME = "TECH-Adobe-Enterprise-Automation-PowerShell-Python-Portfolio"
DESCRIPTION = "🚀 Enterprise-grade Adobe Creative Cloud automation toolkit with PowerShell/Python scripts, REST/GraphQL APIs, ML predictions, JIRA integration, and Azure deployment via Terraform"
HOMEPAGE = f"https://github.com/{{username}}/{REPO_NAME}"
TOPICS = [
    "adobe-creative-cloud", "powershell", "python", "automation", "enterprise",
    "rest-api", "graphql", "machine-learning", "terraform", "azure",
    "docker", "kubernetes", "jira-integration", "hashicorp-vault", "license-management"
]

def update_repo():
    # Get token from environment or prompt
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        print("Please set GITHUB_TOKEN environment variable or")
        print("Get a token from: https://github.com/settings/tokens")
        token = input("Enter your GitHub personal access token: ").strip()

    # Initialize GitHub client
    g = Github(token)
    user = g.get_user()

    # Get repository
    try:
        repo = user.get_repo(REPO_NAME)
        print(f"✅ Found repository: {repo.full_name}")
    except:
        print(f"❌ Repository {REPO_NAME} not found")
        return

    # Update description
    repo.edit(
        description=DESCRIPTION,
        homepage=HOMEPAGE.format(username=user.login),
        has_issues=True,
        has_wiki=True,
        has_projects=True
    )
    print("✅ Updated description and settings")

    # Update topics
    repo.replace_topics(TOPICS)
    print(f"✅ Updated topics: {', '.join(TOPICS)}")

    print(f"\n🎉 Repository updated successfully!")
    print(f"View at: https://github.com/{repo.full_name}")

if __name__ == "__main__":
    update_repo()
EOF

echo -e "\n${YELLOW}Note: Also created update-github-repo.py as an alternative Python script${NC}"

# Make Python script executable
chmod +x update-github-repo.py