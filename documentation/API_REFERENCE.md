# API Reference

## Adobe User Management API

### Authentication
```python
from adobe_auth import AdobeAuth

auth = AdobeAuth(
    org_id="YOUR_ORG@AdobeOrg",
    client_id="YOUR_CLIENT_ID",
    client_secret="YOUR_SECRET",
    tech_account_id="YOUR_TECH_ID@techacct.adobe.com"
)

token = auth.get_access_token()
```

### User Operations

#### Create User
```python
POST /v2/usermanagement/action/{orgId}

def create_user(email, first_name, last_name, country="US"):
    payload = {
        "user": {
            "email": email,
            "firstname": first_name,
            "lastname": last_name,
            "country": country
        },
        "do": [{
            "addUser": {
                "email": email,
                "firstname": first_name,
                "lastname": last_name
            }
        }]
    }
    return api_request("POST", endpoint, payload)
```

#### Get User
```python
GET /v2/usermanagement/users/{orgId}

def get_user(email):
    params = {"email": email}
    return api_request("GET", endpoint, params=params)
```

#### Update User
```python
POST /v2/usermanagement/action/{orgId}

def update_user(email, updates):
    payload = {
        "user": {"email": email},
        "do": [{
            "update": updates
        }]
    }
    return api_request("POST", endpoint, payload)
```

#### Delete User
```python
POST /v2/usermanagement/action/{orgId}

def delete_user(email):
    payload = {
        "user": {"email": email},
        "do": [{
            "removeFromOrg": {}
        }]
    }
    return api_request("POST", endpoint, payload)
```

### Product Operations

#### Assign Products
```python
def assign_products(email, products):
    payload = {
        "user": {"email": email},
        "do": [{
            "add": {
                "product": products
            }
        }]
    }
    return api_request("POST", endpoint, payload)
```

#### Remove Products
```python
def remove_products(email, products):
    payload = {
        "user": {"email": email},
        "do": [{
            "remove": {
                "product": products
            }
        }]
    }
    return api_request("POST", endpoint, payload)
```

### Group Operations

#### Create Group
```python
def create_group(group_name, description):
    payload = {
        "do": [{
            "addUserGroup": {
                "group": group_name,
                "description": description
            }
        }]
    }
    return api_request("POST", endpoint, payload)
```

#### Add User to Group
```python
def add_to_group(email, group_name):
    payload = {
        "user": {"email": email},
        "do": [{
            "add": {
                "group": [group_name]
            }
        }]
    }
    return api_request("POST", endpoint, payload)
```

## PowerShell Cmdlets

### User Management
```powershell
# Get user information
Get-AdobeUser -Email "user@company.com"

# Create new user
New-AdobeUser -Email "user@company.com" `
              -FirstName "John" `
              -LastName "Doe" `
              -Country "US"

# Update user
Set-AdobeUser -Email "user@company.com" `
              -FirstName "Jane"

# Remove user
Remove-AdobeUser -Email "user@company.com" -Confirm:$false
```

### License Management
```powershell
# Get license usage
Get-AdobeLicenseUsage -Product "Creative Cloud"

# Assign license
Add-AdobeLicense -Email "user@company.com" `
                 -Product "Photoshop"

# Remove license
Remove-AdobeLicense -Email "user@company.com" `
                    -Product "Photoshop"

# Optimize licenses
Optimize-AdobeLicenses -InactiveDays 30
```

### Group Management
```powershell
# Create group
New-AdobeGroup -Name "Designers" `
               -Description "Design Team"

# Add user to group
Add-AdobeGroupMember -Group "Designers" `
                     -Email "user@company.com"

# Get group members
Get-AdobeGroupMembers -Group "Designers"

# Remove from group
Remove-AdobeGroupMember -Group "Designers" `
                        -Email "user@company.com"
```

## Error Codes

| Code | Description | Resolution |
|------|-------------|------------|
| 400 | Bad Request | Check request format |
| 401 | Unauthorized | Verify API credentials |
| 403 | Forbidden | Check permissions |
| 404 | Not Found | Verify endpoint/resource |
| 429 | Rate Limited | Implement retry logic |
| 500 | Server Error | Retry with backoff |

## Rate Limits

- **User API**: 10 requests/second
- **Bulk Operations**: 100 users/request
- **Report API**: 5 requests/minute

## Pagination

```python
def get_all_users(page_size=100):
    users = []
    page = 0

    while True:
        response = api_request("GET", endpoint,
                              params={"page": page, "size": page_size})
        users.extend(response["users"])

        if not response.get("lastPage"):
            page += 1
        else:
            break

    return users
```

## Webhooks

```python
# Register webhook
def register_webhook(url, events):
    payload = {
        "webhook_url": url,
        "events": events,
        "client_id": CLIENT_ID
    }
    return api_request("POST", "/webhooks", payload)

# Webhook payload structure
{
    "event": "user.created",
    "timestamp": "2024-01-01T00:00:00Z",
    "data": {
        "email": "user@company.com",
        "products": ["Creative Cloud"]
    }
}
```

## Best Practices

1. **Authentication**
   - Cache access tokens (24hr validity)
   - Implement token refresh logic
   - Use certificate-based auth for production

2. **Error Handling**
   - Implement exponential backoff
   - Log all API interactions
   - Handle rate limits gracefully

3. **Performance**
   - Use bulk operations when possible
   - Implement connection pooling
   - Cache frequently accessed data

4. **Security**
   - Never log sensitive data
   - Encrypt stored credentials
   - Use least privilege principle