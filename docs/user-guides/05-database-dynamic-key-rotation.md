# Database Dynamic Key Rotation with HashiCorp Vault

## Table of Contents

1. [Overview](#overview)
2. [Supported Databases](#supported-databases)
3. [Database Secrets Engine Setup](#database-secrets-engine-setup)
4. [Dynamic Credential Management](#dynamic-credential-management)
5. [Application Integration](#application-integration)
6. [Monitoring and Best Practices](#monitoring-and-best-practices)

## Overview

Database dynamic key rotation with HashiCorp Vault generates temporary database credentials on-demand, eliminating the need for static database passwords and significantly reducing security risks.

### Key Benefits
- **Short-lived Credentials**: Database access with time-limited credentials
- **Automatic Cleanup**: Credentials automatically revoked when expired
- **Granular Permissions**: Role-based database access control
- **Zero Static Secrets**: No database passwords stored in applications
- **Complete Audit Trail**: Full logging of database credential access

## Supported Databases

Vault supports dynamic secrets for various database engines:

- **PostgreSQL** - Full support with advanced features
- **MySQL/MariaDB** - Comprehensive support
- **MongoDB** - Document database support
- **Microsoft SQL Server** - Enterprise database support
- **Oracle Database** - Enterprise support
- **Cassandra** - NoSQL distributed database
- **Redis** - In-memory data structure store
- **Elasticsearch** - Search and analytics engine

## Database Secrets Engine Setup

### 1. Enable Database Secrets Engine

```bash
# Enable database secrets engine
vault secrets enable database

# Enable at custom path for multiple database types
vault secrets enable -path=postgres database
vault secrets enable -path=mysql database

# Verify secrets engines
vault secrets list
```

### 2. PostgreSQL Configuration

```bash
# Configure PostgreSQL connection
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres.example.com:5432/mydb?sslmode=require" \
    allowed_roles="readonly,readwrite,admin" \
    username="vault_admin" \
    password="admin_password"

# Create read-only role
vault write database/roles/readonly \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# Create read-write role
vault write database/roles/readwrite \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    revocation_statements="REASSIGN OWNED BY \"{{name}}\" TO postgres; DROP OWNED BY \"{{name}}\"; DROP ROLE IF EXISTS \"{{name}}\";" \
    default_ttl="2h" \
    max_ttl="8h"
```

### 3. MySQL Configuration

```bash
# Configure MySQL connection
vault write database/config/mysql \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(mysql.example.com:3306)/" \
    allowed_roles="app,readonly,analytics" \
    username="vault_admin" \
    password="admin_password"

# Create application role
vault write database/roles/app \
    db_name=mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO '{{name}}'@'%';" \
    revocation_statements="DROP USER '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="4h"

# Create analytics role with specific database access
vault write database/roles/analytics \
    db_name=mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; \
        GRANT SELECT ON analytics.* TO '{{name}}'@'%'; \
        GRANT SELECT ON logs.* TO '{{name}}'@'%';" \
    default_ttl="8h" \
    max_ttl="24h"
```

### 4. MongoDB Configuration

```bash
# Configure MongoDB connection
vault write database/config/mongodb \
    plugin_name=mongodb-database-plugin \
    connection_url="mongodb://{{username}}:{{password}}@mongo.example.com:27017/admin" \
    allowed_roles="app,readonly" \
    username="vault_admin" \
    password="admin_password"

# Create MongoDB application role
vault write database/roles/app \
    db_name=mongodb \
    creation_statements='{ 
        "db": "myapp", 
        "roles": [{"role": "readWrite", "db": "myapp"}] 
    }' \
    default_ttl="2h" \
    max_ttl="6h"

# Create read-only role
vault write database/roles/readonly \
    db_name=mongodb \
    creation_statements='{ 
        "db": "myapp", 
        "roles": [{"role": "read", "db": "myapp"}] 
    }' \
    default_ttl="4h" \
    max_ttl="12h"
```

### 5. Redis Configuration

```bash
# Configure Redis connection
vault write database/config/redis \
    plugin_name=redis-database-plugin \
    connection_url="redis://redis.example.com:6379" \
    allowed_roles="app,cache" \
    username="default" \
    password="redis_password"

# Create Redis application role
vault write database/roles/app \
    db_name=redis \
    creation_statements='["ACL SETUSER {{name}} on >{{password}} ~* +@all"]' \
    revocation_statements='["ACL DELUSER {{name}}"]' \
    default_ttl="30m" \
    max_ttl="2h"
```

## Dynamic Credential Management

### 1. Generate Database Credentials

```bash
# Generate PostgreSQL credentials
vault read database/creds/readonly

# Example output:
# Key                Value
# ---                -----
# lease_id           database/creds/readonly/abc123
# lease_duration     3600
# lease_renewable    true
# password           A1a-randompassword123
# username           v-token-readonly-xyz789

# Generate MySQL credentials
vault read database/creds/app

# Generate credentials for specific TTL
vault read database/creds/analytics
```

### 2. Credential Renewal and Revocation

```bash
# Store lease information
DB_CREDS=$(vault read -format=json database/creds/readonly)
LEASE_ID=$(echo $DB_CREDS | jq -r '.lease_id')
USERNAME=$(echo $DB_CREDS | jq -r '.data.username')
PASSWORD=$(echo $DB_CREDS | jq -r '.data.password')

# Renew lease
vault lease renew $LEASE_ID

# Renew with specific increment
vault lease renew -increment=3600 $LEASE_ID

# Revoke credentials early
vault lease revoke $LEASE_ID

# Force revoke all credentials for a role
vault lease revoke -prefix database/creds/readonly
```

### 3. Batch Operations

```bash
#!/bin/bash
# generate-db-creds.sh

ROLES=("readonly" "readwrite" "analytics")
CREDS_DIR="/tmp/db-credentials"
mkdir -p $CREDS_DIR

for ROLE in "${ROLES[@]}"; do
    echo "Generating credentials for role: $ROLE"
    
    CREDS=$(vault read -format=json database/creds/$ROLE)
    USERNAME=$(echo $CREDS | jq -r '.data.username')
    PASSWORD=$(echo $CREDS | jq -r '.data.password')
    LEASE_ID=$(echo $CREDS | jq -r '.lease_id')
    
    # Save to file
    cat > $CREDS_DIR/$ROLE.env << EOF
DB_USERNAME=$USERNAME
DB_PASSWORD=$PASSWORD
DB_LEASE_ID=$LEASE_ID
EOF
    
    echo "Credentials for $ROLE saved to $CREDS_DIR/$ROLE.env"
done
```

## Application Integration

### 1. Python Integration

```python
# database_vault_client.py
import hvac
import psycopg2
import pymongo
import mysql.connector
from contextlib import contextmanager

class DatabaseVaultClient:
    def __init__(self, vault_url, vault_token):
        self.vault_client = hvac.Client(url=vault_url, token=vault_token)
        self.active_leases = {}
        
    def get_database_credentials(self, role_name):
        """Get fresh database credentials from Vault"""
        try:
            response = self.vault_client.read(f'database/creds/{role_name}')
            if response:
                credentials = {
                    'username': response['data']['username'],
                    'password': response['data']['password'],
                    'lease_id': response['lease_id'],
                    'lease_duration': response['lease_duration']
                }
                self.active_leases[role_name] = credentials
                return credentials
            else:
                raise Exception(f"Failed to get credentials for role {role_name}")
        except Exception as e:
            print(f"Error getting database credentials: {e}")
            raise
    
    @contextmanager
    def get_postgres_connection(self, role_name, host, database, port=5432):
        """Get PostgreSQL connection with Vault credentials"""
        creds = self.get_database_credentials(role_name)
        
        conn = None
        try:
            conn = psycopg2.connect(
                host=host,
                database=database,
                user=creds['username'],
                password=creds['password'],
                port=port
            )
            yield conn
        finally:
            if conn:
                conn.close()
            # Optionally revoke credentials immediately
            self.revoke_credentials(role_name)
    
    @contextmanager
    def get_mysql_connection(self, role_name, host, database, port=3306):
        """Get MySQL connection with Vault credentials"""
        creds = self.get_database_credentials(role_name)
        
        conn = None
        try:
            conn = mysql.connector.connect(
                host=host,
                database=database,
                user=creds['username'],
                password=creds['password'],
                port=port
            )
            yield conn
        finally:
            if conn:
                conn.close()
            self.revoke_credentials(role_name)
    
    @contextmanager
    def get_mongodb_connection(self, role_name, host, database, port=27017):
        """Get MongoDB connection with Vault credentials"""
        creds = self.get_database_credentials(role_name)
        
        client = None
        try:
            client = pymongo.MongoClient(
                host=host,
                port=port,
                username=creds['username'],
                password=creds['password'],
                authSource=database
            )
            yield client[database]
        finally:
            if client:
                client.close()
            self.revoke_credentials(role_name)
    
    def renew_credentials(self, role_name):
        """Renew credentials lease"""
        if role_name in self.active_leases:
            lease_id = self.active_leases[role_name]['lease_id']
            try:
                self.vault_client.sys.renew_lease(lease_id)
                print(f"Renewed lease for {role_name}")
            except Exception as e:
                print(f"Failed to renew lease: {e}")
                # Get fresh credentials
                self.get_database_credentials(role_name)
    
    def revoke_credentials(self, role_name):
        """Revoke credentials early"""
        if role_name in self.active_leases:
            lease_id = self.active_leases[role_name]['lease_id']
            try:
                self.vault_client.sys.revoke_lease(lease_id)
                del self.active_leases[role_name]
                print(f"Revoked credentials for {role_name}")
            except Exception as e:
                print(f"Failed to revoke lease: {e}")

# Usage examples
def main():
    vault_client = DatabaseVaultClient(
        vault_url="https://vault.example.com:8200",
        vault_token="vault-token"
    )
    
    # PostgreSQL example
    with vault_client.get_postgres_connection('readonly', 'postgres.example.com', 'mydb') as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users LIMIT 10")
        results = cursor.fetchall()
        for row in results:
            print(row)
    
    # MySQL example
    with vault_client.get_mysql_connection('app', 'mysql.example.com', 'myapp') as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM orders")
        count = cursor.fetchone()[0]
        print(f"Total orders: {count}")
    
    # MongoDB example
    with vault_client.get_mongodb_connection('readonly', 'mongo.example.com', 'myapp') as db:
        users = db.users.find().limit(10)
        for user in users:
            print(user)

if __name__ == "__main__":
    main()
```

### 2. Go Integration

```go
// database_vault_client.go
package main

import (
    "database/sql"
    "fmt"
    "log"
    "time"
    
    vault "github.com/hashicorp/vault/api"
    _ "github.com/lib/pq"
    _ "github.com/go-sql-driver/mysql"
)

type DatabaseVaultClient struct {
    vaultClient *vault.Client
    credentials map[string]*DatabaseCredentials
}

type DatabaseCredentials struct {
    Username      string
    Password      string
    LeaseID       string
    LeaseDuration int
    ExpiresAt     time.Time
}

func NewDatabaseVaultClient(vaultAddr, vaultToken string) (*DatabaseVaultClient, error) {
    config := vault.DefaultConfig()
    config.Address = vaultAddr
    
    client, err := vault.NewClient(config)
    if err != nil {
        return nil, err
    }
    
    client.SetToken(vaultToken)
    
    return &DatabaseVaultClient{
        vaultClient: client,
        credentials: make(map[string]*DatabaseCredentials),
    }, nil
}

func (c *DatabaseVaultClient) GetDatabaseCredentials(roleName string) (*DatabaseCredentials, error) {
    secret, err := c.vaultClient.Logical().Read(fmt.Sprintf("database/creds/%s", roleName))
    if err != nil {
        return nil, err
    }
    
    if secret == nil {
        return nil, fmt.Errorf("no credentials found for role %s", roleName)
    }
    
    creds := &DatabaseCredentials{
        Username:      secret.Data["username"].(string),
        Password:      secret.Data["password"].(string),
        LeaseID:       secret.LeaseID,
        LeaseDuration: secret.LeaseDuration,
        ExpiresAt:     time.Now().Add(time.Duration(secret.LeaseDuration) * time.Second),
    }
    
    c.credentials[roleName] = creds
    return creds, nil
}

func (c *DatabaseVaultClient) GetPostgreSQLConnection(roleName, host, database string, port int) (*sql.DB, error) {
    creds, exists := c.credentials[roleName]
    if !exists || time.Now().After(creds.ExpiresAt.Add(-5*time.Minute)) {
        var err error
        creds, err = c.GetDatabaseCredentials(roleName)
        if err != nil {
            return nil, err
        }
    }
    
    connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=require",
        host, port, creds.Username, creds.Password, database)
    
    db, err := sql.Open("postgres", connStr)
    if err != nil {
        return nil, err
    }
    
    // Test connection
    if err = db.Ping(); err != nil {
        db.Close()
        return nil, err
    }
    
    return db, nil
}

func (c *DatabaseVaultClient) GetMySQLConnection(roleName, host, database string, port int) (*sql.DB, error) {
    creds, exists := c.credentials[roleName]
    if !exists || time.Now().After(creds.ExpiresAt.Add(-5*time.Minute)) {
        var err error
        creds, err = c.GetDatabaseCredentials(roleName)
        if err != nil {
            return nil, err
        }
    }
    
    connStr := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s",
        creds.Username, creds.Password, host, port, database)
    
    db, err := sql.Open("mysql", connStr)
    if err != nil {
        return nil, err
    }
    
    if err = db.Ping(); err != nil {
        db.Close()
        return nil, err
    }
    
    return db, nil
}

func (c *DatabaseVaultClient) RevokeCredentials(roleName string) error {
    creds, exists := c.credentials[roleName]
    if !exists {
        return fmt.Errorf("no credentials found for role %s", roleName)
    }
    
    err := c.vaultClient.Sys().Revoke(creds.LeaseID)
    if err != nil {
        return err
    }
    
    delete(c.credentials, roleName)
    return nil
}

func main() {
    client, err := NewDatabaseVaultClient(
        "https://vault.example.com:8200",
        "vault-token",
    )
    if err != nil {
        log.Fatal(err)
    }
    
    // PostgreSQL example
    db, err := client.GetPostgreSQLConnection("readonly", "postgres.example.com", "mydb", 5432)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()
    defer client.RevokeCredentials("readonly")
    
    rows, err := db.Query("SELECT name, email FROM users LIMIT 10")
    if err != nil {
        log.Fatal(err)
    }
    defer rows.Close()
    
    for rows.Next() {
        var name, email string
        if err := rows.Scan(&name, &email); err != nil {
            log.Fatal(err)
        }
        fmt.Printf("User: %s, Email: %s\n", name, email)
    }
}
```

### 3. Application Configuration Templates

```yaml
# docker-compose.yml with Vault integration
version: '3.8'
services:
  app:
    image: myapp:latest
    environment:
      - VAULT_ADDR=https://vault.example.com:8200
      - VAULT_ROLE=database-app
      - DB_HOST=postgres.example.com
      - DB_NAME=myapp
    volumes:
      - vault-secrets:/vault/secrets
    command: |
      sh -c '
        # Get database credentials from Vault
        export VAULT_TOKEN=$$(cat /vault/secrets/token)
        DB_CREDS=$$(vault read -format=json database/creds/app)
        export DB_USERNAME=$$(echo $$DB_CREDS | jq -r ".data.username")
        export DB_PASSWORD=$$(echo $$DB_CREDS | jq -r ".data.password")
        export DB_LEASE_ID=$$(echo $$DB_CREDS | jq -r ".lease_id")
        
        # Start application
        exec myapp
      '
      
  vault-agent:
    image: vault:latest
    volumes:
      - vault-secrets:/vault/secrets
      - ./vault-agent.hcl:/vault/config/agent.hcl
    command: vault agent -config=/vault/config/agent.hcl

volumes:
  vault-secrets:
```

### 4. Kubernetes Integration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-app
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "database-app"
        vault.hashicorp.com/agent-inject-secret-database: "database/creds/app"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "database/creds/app" -}}
          export DB_USERNAME="{{ .Data.username }}"
          export DB_PASSWORD="{{ .Data.password }}"
          {{- end }}
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
        - name: DB_HOST
          value: "postgres.example.com"
        - name: DB_NAME
          value: "myapp"
        command: ["/bin/sh"]
        args: ["-c", "source /vault/secrets/database && exec myapp"]
```

## Monitoring and Best Practices

### 1. Monitoring Database Credentials

```bash
# Monitor database credential generation
vault read sys/metrics | grep database

# Check active database leases
vault list sys/leases/lookup/database/creds

# Monitor specific role usage
vault list sys/leases/lookup/database/creds/readonly

# Check database connection configuration
vault read database/config/postgresql
```

### 2. Performance Optimization

```bash
# Configure connection pooling for better performance
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres.example.com:5432/mydb?sslmode=require&pool_max_conns=10" \
    allowed_roles="readonly,readwrite" \
    username="vault_admin" \
    password="admin_password" \
    max_open_connections=5 \
    max_idle_connections=2 \
    max_connection_lifetime="10m"

# Optimize role TTLs based on usage patterns
vault write database/roles/short-lived \
    db_name=postgresql \
    creation_statements="..." \
    default_ttl="15m" \
    max_ttl="1h"

vault write database/roles/long-running \
    db_name=postgresql \
    creation_statements="..." \
    default_ttl="4h" \
    max_ttl="12h"
```

### 3. Best Practices

#### Security
- **Use least privilege principle** for database roles
- **Set appropriate TTLs** based on application needs
- **Enable database audit logging** where possible
- **Use SSL/TLS** for all database connections
- **Rotate Vault database admin credentials** regularly

#### Operations
- **Monitor database performance** impact of dynamic users
- **Test credential cleanup** and user removal
- **Implement connection pooling** to reduce overhead
- **Plan for database maintenance** windows
- **Set up alerting** for credential generation failures

#### Application Design
- **Implement connection retry logic** for credential renewal
- **Cache connections appropriately** within lease duration
- **Handle database reconnection** gracefully
- **Use database migrations** carefully with dynamic users
- **Test application behavior** with short-lived credentials

### 4. Troubleshooting

```bash
# Common database secrets issues

# Test database connectivity
vault write database/config/test-connection \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://vault_admin:password@postgres.example.com:5432/mydb"

# Check role configuration
vault read database/roles/readonly

# Debug credential generation
export VAULT_LOG_LEVEL=debug
vault read database/creds/readonly

# Force cleanup of stuck credentials
vault lease revoke -prefix database/creds/readonly

# Check database user existence
# PostgreSQL
SELECT usename, valuntil FROM pg_user WHERE usename LIKE 'v-%';

# MySQL
SELECT user, host FROM mysql.user WHERE user LIKE 'v-%';

# Clean up orphaned users manually if needed
# PostgreSQL
DROP ROLE IF EXISTS "v-token-readonly-xyz789";

# MySQL
DROP USER 'v-token-readonly-xyz789'@'%';
```

---

*This guide provides comprehensive coverage of database dynamic key rotation with HashiCorp Vault. For specific database configurations and advanced use cases, refer to the HashiCorp Vault database secrets engine documentation.*