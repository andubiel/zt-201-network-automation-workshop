#!/bin/bash
# Generate environment files from templates with random secrets
# This script should be run during deployment, not committed with secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/env"

# Function to generate a random password
generate_password() {
  local length=${1:-20}
  openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
}

# Function to generate Django SECRET_KEY (50 chars, special characters allowed)
generate_secret_key() {
  openssl rand -base64 60 | tr -d "\n" | head -c 50
}

# Function to generate API token pepper (32 chars)
generate_api_token_pepper() {
  openssl rand -base64 32 | tr -d "=+/\n" | head -c 32
}

echo "Generating NetBox environment files from templates..."

# Generate random secrets
REDIS_PASSWORD=$(generate_password 20)
REDIS_CACHE_PASSWORD=$(generate_password 20)
POSTGRES_PASSWORD=$(generate_password 16)
SECRET_KEY=$(generate_secret_key)
API_TOKEN_PEPPER=$(generate_api_token_pepper)

# Generate redis.env
if [[ -f "${ENV_DIR}/redis.env.template" ]]; then
  echo "Generating redis.env..."
  sed "s|__REDIS_PASSWORD__|${REDIS_PASSWORD}|g" \
    "${ENV_DIR}/redis.env.template" > "${ENV_DIR}/redis.env"
  chmod 600 "${ENV_DIR}/redis.env"
fi

# Generate redis-cache.env
if [[ -f "${ENV_DIR}/redis-cache.env.template" ]]; then
  echo "Generating redis-cache.env..."
  sed "s|__REDIS_CACHE_PASSWORD__|${REDIS_CACHE_PASSWORD}|g" \
    "${ENV_DIR}/redis-cache.env.template" > "${ENV_DIR}/redis-cache.env"
  chmod 600 "${ENV_DIR}/redis-cache.env"
fi

# Generate postgres.env
if [[ -f "${ENV_DIR}/postgres.env.template" ]]; then
  echo "Generating postgres.env..."
  sed "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD}|g" \
    "${ENV_DIR}/postgres.env.template" > "${ENV_DIR}/postgres.env"
  chmod 600 "${ENV_DIR}/postgres.env"
fi

# Generate netbox.env (multiple replacements)
if [[ -f "${ENV_DIR}/netbox.env.template" ]]; then
  echo "Generating netbox.env..."
  sed -e "s|__REDIS_PASSWORD__|${REDIS_PASSWORD}|g" \
      -e "s|__REDIS_CACHE_PASSWORD__|${REDIS_CACHE_PASSWORD}|g" \
      -e "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD}|g" \
      -e "s|__SECRET_KEY__|${SECRET_KEY}|g" \
      -e "s|__API_TOKEN_PEPPERS__|[\"${API_TOKEN_PEPPER}\"]|g" \
    "${ENV_DIR}/netbox.env.template" > "${ENV_DIR}/netbox.env"
  chmod 600 "${ENV_DIR}/netbox.env"
fi

echo "✓ Environment files generated successfully"
echo "✓ All .env files have been created with random secrets"
echo ""
echo "IMPORTANT: The generated .env files contain secrets and should NOT be committed to git"
