# Application Integration Examples for Vault Keystore Management

This directory contains practical examples for integrating applications with Vault keystore management.

## Directory Structure

```
examples/
├── python/
│   ├── vault_client.py          # Python Vault client library
│   ├── django_integration.py    # Django framework integration
│   ├── flask_integration.py     # Flask framework integration
│   └── requirements.txt
├── nodejs/
│   ├── vault-client.js          # Node.js Vault client
│   ├── express-integration.js   # Express.js integration
│   └── package.json
├── go/
│   ├── vault_client.go          # Go Vault client
│   ├── gin_integration.go       # Gin framework integration
│   └── go.mod
├── docker/
│   ├── Dockerfile.vault-agent   # Vault Agent container
│   ├── docker-compose.yml       # Multi-service setup
│   └── vault-agent.hcl
└── kubernetes/
    ├── vault-injector.yaml      # Vault Agent Injector
    ├── app-deployment.yaml      # Application deployment
    └── secret-store-csi.yaml    # CSI Secret Store
```

## Quick Start Examples

### Python Integration

```python
# Basic usage
from vault_client import VaultClient

vault = VaultClient("https://vault.example.com:8200", "your-token")
db_config = vault.get_secret("secret/prod/webapp/database")

# Use with database connection
import psycopg2
conn = psycopg2.connect(
    host=db_config['host'],
    database=db_config['database'],
    user=db_config['username'],
    password=db_config['password']
)
```

### Node.js Integration

```javascript
// Basic usage
const VaultClient = require('./vault-client');

const vault = new VaultClient('https://vault.example.com:8200', 'your-token');
const apiKeys = await vault.getSecret('secret/prod/webapp/external-services');

// Use with Express.js
app.use(async (req, res, next) => {
    req.secrets = await vault.getSecret('secret/prod/webapp/config');
    next();
});
```

### Go Integration

```go
// Basic usage
package main

import "github.com/example/vault-client"

func main() {
    client := vaultclient.New("https://vault.example.com:8200", "your-token")
    secrets, err := client.GetSecret("secret/prod/webapp/database")
    if err != nil {
        log.Fatal(err)
    }
    
    // Use secrets for database connection
    db, err := sql.Open("postgres", buildConnectionString(secrets))
}
```

## Features Demonstrated

1. **Secret Retrieval**: Basic and advanced secret fetching patterns
2. **Error Handling**: Robust error handling and retry logic
3. **Caching**: Intelligent secret caching with TTL respect
4. **Renewal**: Automatic token and lease renewal
5. **Rotation**: Handling secret rotation gracefully
6. **Security**: Secure secret handling and memory management

## Security Best Practices

- Never log secrets or store them in plain text
- Use short-lived tokens when possible
- Implement proper error handling without exposing secrets
- Cache secrets appropriately (within lease duration)
- Use background renewal for long-running applications
- Implement circuit breakers for Vault connectivity

## Getting Started

1. Choose your language/framework
2. Copy the appropriate example
3. Install dependencies
4. Configure Vault connection details
5. Test with development secrets first
6. Deploy to production

Each example includes comprehensive error handling, security best practices, and production-ready patterns.