---
name: api
description: "Design REST or GraphQL API endpoints with schemas and validation."
---

# /api

Design REST or GraphQL API endpoints with schemas and validation.

## Usage

```
/api <action> [resource] [--type <type>] [--methods <methods>]
```

## Arguments

- `action`: `design`, `scaffold`, `document`, `validate`
- `resource`: Resource name (e.g., `users`, `orders`)
- `--type`: API type (`rest`, `graphql`) (default: rest)
- `--methods`: HTTP methods to include (default: all CRUD)

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete API design/scaffold end-to-end
- Follow REST/GraphQL best practices
- Generate OpenAPI/GraphQL schema

**Quality:**
- Consistent naming conventions
- Proper HTTP status codes
- Comprehensive validation
- Security considerations

### Actions

#### Design (`/api design <resource>`)

Create API specification without code:

1. **Analyze resource requirements**:
   - Identify fields and types
   - Determine relationships
   - Note business rules

2. **Generate specification**:
   - Endpoint definitions
   - Request/response schemas
   - Error responses
   - Authentication requirements

3. **Output OpenAPI spec** or design document

#### Scaffold (`/api scaffold <resource>`)

Generate code for API endpoints:

1. **Read `prd/00_technology.md`** for framework patterns
2. **Create route handler**
3. **Create request/response models**
4. **Create service layer**
5. **Create basic tests**

#### Document (`/api document`)

Generate API documentation:

1. **Scan existing endpoints**
2. **Generate OpenAPI/Swagger spec**
3. **Create markdown documentation**

#### Validate (`/api validate`)

Check API against best practices:

1. **Check naming conventions**
2. **Verify HTTP methods used correctly**
3. **Check response codes**
4. **Validate schema consistency**

### REST Design Principles

#### URL Structure

```
GET    /resources          # List all
GET    /resources/:id      # Get one
POST   /resources          # Create
PATCH  /resources/:id      # Partial update
PUT    /resources/:id      # Full replace
DELETE /resources/:id      # Delete

# Nested resources
GET    /users/:id/orders   # User's orders
POST   /users/:id/orders   # Create order for user

# Actions (when CRUD doesn't fit)
POST   /orders/:id/cancel  # Cancel order
POST   /users/:id/verify   # Verify user
```

#### Naming Conventions

- Use plural nouns for resources: `/users` not `/user`
- Use kebab-case for multi-word: `/order-items`
- Use lowercase: `/users` not `/Users`
- Avoid verbs in URLs (use HTTP methods)

#### HTTP Status Codes

| Code | Meaning | When to Use |
|------|---------|-------------|
| 200 | OK | Successful GET, PATCH, PUT |
| 201 | Created | Successful POST |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Validation error |
| 401 | Unauthorized | Missing/invalid auth |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate resource |
| 422 | Unprocessable | Business rule violation |
| 500 | Server Error | Unexpected error |

#### Response Format

```json
// Success (single resource)
{
  "data": {
    "id": "123",
    "type": "user",
    "attributes": { ... }
  }
}

// Success (collection)
{
  "data": [ ... ],
  "meta": {
    "total": 100,
    "page": 1,
    "per_page": 20
  }
}

// Error
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid email format",
    "details": [
      { "field": "email", "message": "Must be valid email" }
    ]
  }
}
```

### API Specification Template

```yaml
openapi: 3.0.3
info:
  title: Resource API
  version: 1.0.0

paths:
  /resources:
    get:
      summary: List resources
      parameters:
        - name: page
          in: query
          schema:
            type: integer
            default: 1
        - name: limit
          in: query
          schema:
            type: integer
            default: 20
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ResourceList'

    post:
      summary: Create resource
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateResource'
      responses:
        '201':
          description: Created
        '400':
          description: Validation error

  /resources/{id}:
    get:
      summary: Get resource
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Success
        '404':
          description: Not found
```

### Security Considerations

- [ ] Authentication required on protected endpoints
- [ ] Authorization checks for resource access
- [ ] Input validation on all endpoints
- [ ] Rate limiting configured
- [ ] Sensitive data not exposed in responses
- [ ] Audit logging for mutations

## Example Output

```
$ /api design orders --type rest

Designing REST API for: orders

Resource Analysis:
- Primary entity: Order
- Related: User (owner), Items (children), Payment
- Operations: CRUD + cancel, refund

API Specification:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Endpoints
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GET    /orders              List orders (with filters)
GET    /orders/:id          Get order details
POST   /orders              Create new order
PATCH  /orders/:id          Update order
DELETE /orders/:id          Delete order (soft delete)

POST   /orders/:id/cancel   Cancel order
POST   /orders/:id/refund   Request refund

GET    /orders/:id/items    List order items
POST   /orders/:id/items    Add item to order

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 Schemas
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Order:
  id: string (uuid)
  user_id: string (uuid)
  status: enum [draft, pending, confirmed, shipped, delivered, cancelled]
  total: number (decimal)
  currency: string (ISO 4217)
  items: OrderItem[]
  created_at: datetime
  updated_at: datetime

CreateOrder:
  items: CreateOrderItem[] (required, min: 1)
  shipping_address_id: string (required)
  payment_method_id: string (required)

OrderItem:
  id: string
  product_id: string
  quantity: integer (min: 1)
  unit_price: number
  total: number

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 Security
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- All endpoints require authentication
- Users can only access their own orders
- Admin role can access all orders
- Cancel/refund have time-based restrictions

Generated: openapi/orders.yaml

Next steps:
1. Review specification
2. Run `/api scaffold orders` to generate code
3. Run `/api document` to generate docs
```
