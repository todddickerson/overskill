# OverSkill API Documentation

## Overview

The OverSkill API provides programmatic access to app generation, marketplace, and analytics features. All API endpoints require authentication via JWT tokens.

## Base URL

```
https://api.overskill.app/v1
```

## Authentication

Include your API token in the Authorization header:

```
Authorization: Bearer YOUR_API_TOKEN
```

## Endpoints

### Apps

#### Generate App
```http
POST /apps/generate
Content-Type: application/json

{
  "prompt": "Create a todo list app with local storage",
  "options": {
    "framework": "react",
    "type": "tool"
  }
}
```

#### Get App
```http
GET /apps/:id
```

#### List Apps
```http
GET /apps
```

### Marketplace

#### Search Apps
```http
GET /marketplace/search?q=todo
```

#### Purchase App
```http
POST /marketplace/purchase
Content-Type: application/json

{
  "app_id": "123",
  "price_id": "price_abc"
}
```

### Analytics

#### App Analytics
```http
GET /apps/:id/analytics
```

## Rate Limits

- 100 requests per minute for authenticated users
- 10 app generations per hour

## SDKs

Coming soon:
- JavaScript/TypeScript
- Python
- Ruby

## Webhooks

Configure webhooks in your dashboard to receive events:
- `app.generated`
- `app.published`
- `purchase.completed`

## Examples

See our [GitHub repository](https://github.com/overskill/api-examples) for complete examples.
