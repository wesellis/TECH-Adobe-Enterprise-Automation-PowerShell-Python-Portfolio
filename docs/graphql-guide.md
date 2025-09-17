# GraphQL API Guide

## Overview

The Adobe Enterprise Automation platform provides a GraphQL API that offers a flexible and efficient way to query and manipulate data. GraphQL allows clients to request exactly the data they need, reducing over-fetching and improving performance.

## Endpoint

- **GraphQL Endpoint**: `http://localhost:4000/graphql`
- **WebSocket Endpoint** (for subscriptions): `ws://localhost:4000/graphql`
- **GraphQL Playground**: Available in development at `http://localhost:4000/graphql`

## Authentication

All GraphQL requests require authentication via JWT tokens in the Authorization header:

```http
Authorization: Bearer <your-jwt-token>
```

For WebSocket subscriptions, pass the token in connection params:

```javascript
const wsClient = new WebSocketClient({
  url: 'ws://localhost:4000/graphql',
  connectionParams: {
    authToken: 'your-jwt-token'
  }
});
```

## Schema Overview

### Core Types

#### User
Represents an Adobe Creative Cloud user in the system.

```graphql
type User {
  id: ID!
  email: String!
  firstName: String!
  lastName: String!
  department: String!
  products: [String!]!
  status: UserStatus!
  createdAt: Date!
  lastLogin: Date
  licenses: [License!]!
  usageStats: UserUsageStats
}
```

#### License
Represents a software license allocation.

```graphql
type License {
  id: ID!
  product: String!
  type: LicenseType!
  assignedTo: User
  assignedAt: Date
  expiresAt: Date
  status: LicenseStatus!
  cost: Float
}
```

#### Department
Represents an organizational department.

```graphql
type Department {
  name: String!
  userCount: Int!
  licenseCount: Int!
  totalCost: Float!
  users: [User!]!
  licenses: [License!]!
}
```

## Common Queries

### Get User by Email

```graphql
query GetUser($email: String!) {
  userByEmail(email: $email) {
    id
    email
    firstName
    lastName
    department
    products
    status
    licenses {
      id
      product
      status
      expiresAt
    }
  }
}
```

### List Users with Pagination

```graphql
query ListUsers($limit: Int, $offset: Int) {
  users(
    pagination: { limit: $limit, offset: $offset }
  ) {
    edges {
      node {
        id
        email
        firstName
        lastName
        department
        status
      }
      cursor
    }
    pageInfo {
      hasNextPage
      hasPreviousPage
      startCursor
      endCursor
    }
    totalCount
  }
}
```

### Search Users

```graphql
query SearchUsers($search: String!) {
  users(filter: { search: $search }) {
    edges {
      node {
        id
        email
        firstName
        lastName
        department
      }
    }
    totalCount
  }
}
```

### Get License Utilization

```graphql
query GetUtilization($product: String) {
  licenseUtilization(product: $product) {
    total
    used
    available
    utilizationPercentage
    byDepartment {
      department
      used
      total
      percentage
    }
    byProduct {
      product
      used
      total
      percentage
    }
  }
}
```

### Get License Predictions

```graphql
query GetPredictions($daysAhead: Int!) {
  licensePredictions(daysAhead: $daysAhead) {
    product
    department
    date
    predictedUsage
    confidenceLower
    confidenceUpper
    trend
  }
}
```

### Get Cost Analysis

```graphql
query GetCostAnalysis {
  costAnalysis {
    totalCost
    costByDepartment {
      department
      cost
      userCount
      averageCostPerUser
    }
    costByProduct {
      product
      cost
      licenseCount
      averageCostPerLicense
    }
    trend
    projectedCost
    savingsOpportunity
  }
}
```

## Common Mutations

### Create User

```graphql
mutation CreateUser($input: UserCreateInput!) {
  createUser(input: $input) {
    id
    email
    firstName
    lastName
    department
    products
    status
  }
}
```

Variables:
```json
{
  "input": {
    "email": "john.doe@company.com",
    "firstName": "John",
    "lastName": "Doe",
    "department": "Marketing",
    "products": ["Creative Cloud", "Acrobat Pro"]
  }
}
```

### Update User

```graphql
mutation UpdateUser($id: ID!, $input: UserUpdateInput!) {
  updateUser(id: $id, input: $input) {
    id
    email
    department
    status
  }
}
```

### Assign License

```graphql
mutation AssignLicense($userId: ID!, $product: String!) {
  assignLicense(userId: $userId, product: $product) {
    id
    product
    assignedTo {
      email
    }
    assignedAt
    status
  }
}
```

### Bulk Create Users

```graphql
mutation BulkCreateUsers($users: [UserCreateInput!]!) {
  bulkCreateUsers(users: $users) {
    created {
      id
      email
    }
    failed {
      email
      error
    }
    totalProcessed
    successCount
    failureCount
  }
}
```

### Run License Optimization

```graphql
mutation RunOptimization($dryRun: Boolean) {
  optimizeLicenses(dryRun: $dryRun) {
    optimized
    licensesReclaimed
    estimatedSavings
    recommendations
  }
}
```

## Subscriptions

### Real-time User Updates

```graphql
subscription OnUserUpdated($userId: ID) {
  userUpdated(userId: $userId) {
    id
    email
    status
    department
  }
}
```

### License Assignment Notifications

```graphql
subscription OnLicenseAssigned {
  licenseAssigned {
    id
    product
    assignedTo {
      email
    }
    assignedAt
  }
}
```

### Optimization Completion

```graphql
subscription OnOptimizationCompleted {
  optimizationCompleted {
    optimized
    licensesReclaimed
    estimatedSavings
  }
}
```

## Error Handling

GraphQL errors follow a standard format:

```json
{
  "errors": [
    {
      "message": "User not found",
      "extensions": {
        "code": "NOT_FOUND",
        "stacktrace": "..." // Only in development
      },
      "path": ["user"],
      "locations": [{"line": 2, "column": 3}]
    }
  ]
}
```

### Common Error Codes

- `UNAUTHENTICATED`: Missing or invalid authentication
- `FORBIDDEN`: Insufficient permissions
- `NOT_FOUND`: Requested resource not found
- `BAD_USER_INPUT`: Invalid input data
- `INTERNAL_SERVER_ERROR`: Server-side error

## Pagination

The API uses cursor-based pagination for large result sets:

```graphql
query PaginatedUsers($cursor: String, $limit: Int) {
  users(
    pagination: {
      limit: $limit
      offset: 0
      sortBy: "email"
      sortOrder: ASC
    }
  ) {
    edges {
      node { ... }
      cursor
    }
    pageInfo {
      hasNextPage
      hasPreviousPage
      startCursor
      endCursor
    }
    totalCount
  }
}
```

## Filtering and Sorting

### Filter Options

```graphql
input UserFilterInput {
  email: String
  department: String
  status: UserStatus
  product: String
  search: String
}
```

### Sort Options

```graphql
input PaginationInput {
  limit: Int
  offset: Int
  sortBy: String
  sortOrder: SortOrder
}

enum SortOrder {
  ASC
  DESC
}
```

## Best Practices

1. **Request Only What You Need**: GraphQL allows you to specify exactly which fields you want.

2. **Use Fragments for Reusable Fields**:
```graphql
fragment UserBasicInfo on User {
  id
  email
  firstName
  lastName
}

query GetUsers {
  users {
    edges {
      node {
        ...UserBasicInfo
        department
      }
    }
  }
}
```

3. **Batch Similar Queries**: Combine multiple queries in a single request.

4. **Handle Errors Gracefully**: Always check for errors in responses.

5. **Use Variables**: Don't hardcode values in queries.

6. **Implement Caching**: Take advantage of GraphQL's predictable responses.

## Rate Limiting

The GraphQL API implements rate limiting:
- **Anonymous**: 100 requests per hour
- **Authenticated**: 5000 requests per hour
- **Admin**: 10000 requests per hour

## Testing with GraphQL Playground

1. Navigate to `http://localhost:4000/graphql`
2. Add your JWT token in HTTP headers:
```json
{
  "Authorization": "Bearer your-jwt-token"
}
```
3. Use the documentation explorer to browse the schema
4. Test queries in the editor with auto-completion
5. View real-time results and errors

## Client Libraries

### JavaScript/TypeScript

```javascript
import { ApolloClient, InMemoryCache, gql } from '@apollo/client';

const client = new ApolloClient({
  uri: 'http://localhost:4000/graphql',
  cache: new InMemoryCache(),
  headers: {
    authorization: `Bearer ${token}`
  }
});

// Query example
const GET_USERS = gql`
  query GetUsers {
    users {
      edges {
        node {
          id
          email
        }
      }
    }
  }
`;

client.query({ query: GET_USERS })
  .then(result => console.log(result));
```

### Python

```python
from gql import gql, Client
from gql.transport.aiohttp import AIOHTTPTransport

transport = AIOHTTPTransport(
    url="http://localhost:4000/graphql",
    headers={"Authorization": f"Bearer {token}"}
)

client = Client(transport=transport, fetch_schema_from_transport=True)

query = gql("""
    query GetUsers {
        users {
            edges {
                node {
                    id
                    email
                }
            }
        }
    }
""")

result = client.execute(query)
```

## Performance Tips

1. **Use DataLoader**: Batch and cache database requests
2. **Implement Field-Level Caching**: Cache expensive computations
3. **Optimize N+1 Queries**: Use batch loading for related data
4. **Limit Query Depth**: Prevent deeply nested queries
5. **Use Persisted Queries**: Store frequently used queries

## Security Considerations

1. **Query Depth Limiting**: Maximum query depth is limited to 10
2. **Query Complexity Analysis**: Complex queries may be rejected
3. **Rate Limiting**: Prevents abuse and ensures fair usage
4. **Field-Level Authorization**: Some fields require specific permissions
5. **Input Validation**: All inputs are validated and sanitized

## Support

For issues or questions about the GraphQL API:
- Check the schema documentation in GraphQL Playground
- Review error messages and codes
- Contact the development team
- Submit issues to the project repository