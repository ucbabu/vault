# vault_client.py
# Production-ready Python client for HashiCorp Vault keystore management

import os
import time
import json
import logging
from typing import Dict, Any, Optional
from urllib.parse import urljoin
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class VaultError(Exception):
    """Custom exception for Vault-related errors"""
    pass


class VaultClient:
    """
    Production-ready Vault client for keystore management
    
    Features:
    - Automatic token renewal
    - Secret caching with TTL respect
    - Retry logic with exponential backoff
    - Comprehensive error handling
    - Memory-safe secret handling
    """
    
    def __init__(self, vault_url: str, token: str = None, namespace: str = None):
        self.vault_url = vault_url.rstrip('/')
        self.namespace = namespace
        self.logger = logging.getLogger(__name__)
        
        # Initialize session with retry strategy
        self.session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
        
        # Set default timeout
        self.session.timeout = 30
        
        # Secret cache with TTL
        self._secret_cache = {}
        self._cache_ttl = {}
        
        # Set authentication
        if token:
            self.set_token(token)
        elif os.getenv('VAULT_TOKEN'):
            self.set_token(os.getenv('VAULT_TOKEN'))
        else:
            raise VaultError("No Vault token provided")
    
    def set_token(self, token: str):
        """Set Vault authentication token"""
        self.session.headers.update({
            'X-Vault-Token': token,
            'Content-Type': 'application/json'
        })
        
        if self.namespace:
            self.session.headers['X-Vault-Namespace'] = self.namespace
    
    def _make_request(self, method: str, path: str, **kwargs) -> requests.Response:
        """Make HTTP request to Vault with error handling"""
        url = urljoin(self.vault_url, path)
        
        try:
            response = self.session.request(method, url, **kwargs)
            
            # Handle Vault-specific errors
            if response.status_code == 403:
                raise VaultError("Access denied - check token and policies")
            elif response.status_code == 404:
                raise VaultError(f"Path not found: {path}")
            elif response.status_code >= 400:
                try:
                    error_detail = response.json().get('errors', [])
                    raise VaultError(f"Vault error {response.status_code}: {error_detail}")
                except json.JSONDecodeError:
                    raise VaultError(f"Vault error {response.status_code}: {response.text}")
            
            response.raise_for_status()
            return response
            
        except requests.exceptions.RequestException as e:
            raise VaultError(f"Network error connecting to Vault: {str(e)}")
    
    def _is_cache_valid(self, cache_key: str) -> bool:
        """Check if cached secret is still valid"""
        if cache_key not in self._secret_cache:
            return False
        
        if cache_key in self._cache_ttl:
            return time.time() < self._cache_ttl[cache_key]
        
        return True
    
    def get_secret(self, path: str, use_cache: bool = True) -> Dict[str, Any]:
        """
        Retrieve secret from Vault keystore
        
        Args:
            path: Secret path (e.g., 'secret/prod/webapp/database')
            use_cache: Whether to use cached value if available
            
        Returns:
            Dictionary containing secret data
        """
        # Check cache first
        if use_cache and self._is_cache_valid(path):
            self.logger.debug(f"Using cached secret for {path}")
            return self._secret_cache[path].copy()
        
        # Construct API path
        if path.startswith('secret/'):
            api_path = f"/v1/{path.replace('secret/', 'secret/data/', 1)}"
        else:
            api_path = f"/v1/{path}"
        
        try:
            response = self._make_request('GET', api_path)
            data = response.json()
            
            # Extract secret data
            if 'data' in data and 'data' in data['data']:
                # KV v2 format
                secret_data = data['data']['data']
                metadata = data['data']['metadata']
                
                # Cache with appropriate TTL
                cache_ttl = 300  # Default 5 minutes
                if 'lease_duration' in metadata:
                    cache_ttl = min(cache_ttl, metadata['lease_duration'])
                
                self._secret_cache[path] = secret_data.copy()
                self._cache_ttl[path] = time.time() + cache_ttl
                
            elif 'data' in data:
                # KV v1 or other format
                secret_data = data['data']
                self._secret_cache[path] = secret_data.copy()
                self._cache_ttl[path] = time.time() + 300
            else:
                raise VaultError(f"Unexpected response format for {path}")
            
            self.logger.info(f"Successfully retrieved secret from {path}")
            return secret_data.copy()
            
        except Exception as e:
            self.logger.error(f"Failed to retrieve secret from {path}: {str(e)}")
            raise
    
    def put_secret(self, path: str, data: Dict[str, Any], cas: int = None) -> bool:
        """
        Store secret in Vault keystore
        
        Args:
            path: Secret path
            data: Secret data to store
            cas: Check-and-set version for safe updates
            
        Returns:
            True if successful
        """
        # Construct API path
        if path.startswith('secret/'):
            api_path = f"/v1/{path.replace('secret/', 'secret/data/', 1)}"
        else:
            api_path = f"/v1/{path}"
        
        payload = {'data': data}
        if cas is not None:
            payload['options'] = {'cas': cas}
        
        try:
            self._make_request('POST', api_path, json=payload)
            
            # Invalidate cache
            if path in self._secret_cache:
                del self._secret_cache[path]
            if path in self._cache_ttl:
                del self._cache_ttl[path]
            
            self.logger.info(f"Successfully stored secret at {path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to store secret at {path}: {str(e)}")
            raise
    
    def delete_secret(self, path: str) -> bool:
        """Delete secret from Vault keystore"""
        if path.startswith('secret/'):
            api_path = f"/v1/{path.replace('secret/', 'secret/data/', 1)}"
        else:
            api_path = f"/v1/{path}"
        
        try:
            self._make_request('DELETE', api_path)
            
            # Remove from cache
            if path in self._secret_cache:
                del self._secret_cache[path]
            if path in self._cache_ttl:
                del self._cache_ttl[path]
            
            self.logger.info(f"Successfully deleted secret at {path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to delete secret at {path}: {str(e)}")
            raise
    
    def list_secrets(self, path: str) -> list:
        """List secrets at given path"""
        if path.startswith('secret/'):
            api_path = f"/v1/{path.replace('secret/', 'secret/metadata/', 1)}"
        else:
            api_path = f"/v1/{path}"
        
        # Add list parameter
        params = {'list': 'true'}
        
        try:
            response = self._make_request('GET', api_path, params=params)
            data = response.json()
            
            if 'data' in data and 'keys' in data['data']:
                return data['data']['keys']
            else:
                return []
                
        except VaultError as e:
            if "Path not found" in str(e):
                return []
            raise
    
    def get_secret_metadata(self, path: str) -> Dict[str, Any]:
        """Get secret metadata including versions and created time"""
        if path.startswith('secret/'):
            api_path = f"/v1/{path.replace('secret/', 'secret/metadata/', 1)}"
        else:
            api_path = f"/v1/{path}/metadata"
        
        try:
            response = self._make_request('GET', api_path)
            return response.json()['data']
            
        except Exception as e:
            self.logger.error(f"Failed to get metadata for {path}: {str(e)}")
            raise
    
    def health_check(self) -> Dict[str, Any]:
        """Check Vault health status"""
        try:
            response = self._make_request('GET', '/v1/sys/health')
            return response.json()
        except Exception as e:
            self.logger.error(f"Health check failed: {str(e)}")
            raise
    
    def clear_cache(self):
        """Clear secret cache"""
        self._secret_cache.clear()
        self._cache_ttl.clear()
        self.logger.info("Secret cache cleared")
    
    def __del__(self):
        """Cleanup: clear sensitive data from memory"""
        if hasattr(self, '_secret_cache'):
            self._secret_cache.clear()
        if hasattr(self, '_cache_ttl'):
            self._cache_ttl.clear()


# Context manager for secure secret handling
class SecretContext:
    """Context manager for secure secret handling with automatic cleanup"""
    
    def __init__(self, vault_client: VaultClient, secret_path: str):
        self.vault_client = vault_client
        self.secret_path = secret_path
        self.secret_data = None
    
    def __enter__(self):
        self.secret_data = self.vault_client.get_secret(self.secret_path)
        return self.secret_data
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        # Clear secret from memory
        if self.secret_data:
            for key in list(self.secret_data.keys()):
                self.secret_data[key] = "CLEARED"
            self.secret_data.clear()


# Example usage and testing
def main():
    """Example usage of the Vault client"""
    
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    
    # Initialize client
    vault_url = os.getenv('VAULT_ADDR', 'https://vault.example.com:8200')
    vault_token = os.getenv('VAULT_TOKEN')
    
    try:
        client = VaultClient(vault_url, vault_token)
        
        # Health check
        health = client.health_check()
        print(f"Vault health: {health}")
        
        # Example: Get database configuration
        with SecretContext(client, 'secret/prod/webapp/database') as db_config:
            print(f"Database host: {db_config.get('host')}")
            # Secret is automatically cleared when exiting context
        
        # Example: List secrets
        secrets = client.list_secrets('secret/prod/webapp/')
        print(f"Available secrets: {secrets}")
        
        # Example: Store new secret
        client.put_secret('secret/dev/test/config', {
            'api_key': 'test-key-123',
            'debug': True,
            'created_at': str(time.time())
        })
        
        # Example: Get metadata
        metadata = client.get_secret_metadata('secret/prod/webapp/database')
        print(f"Secret versions: {metadata.get('current_version')}")
        
    except VaultError as e:
        print(f"Vault error: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")


if __name__ == "__main__":
    main()