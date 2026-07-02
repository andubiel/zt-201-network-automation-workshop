# NetBox Environment Files

## Security Notice

This directory contains **template files** and **generated secrets**.

### Template Files (Committed to Git)
- `*.env.template` - Template files with placeholders for secrets
- These are safe to commit to version control

### Generated Files (NOT Committed)
- `*.env` - Actual environment files with real secrets
- These files are generated from templates and **must not be committed**
- They are excluded via `.gitignore`

## How It Works

1. **Template files** contain placeholders like `__REDIS_PASSWORD__`
2. During deployment, `generate-env-files.sh` creates real `.env` files
3. Random secrets are generated using `openssl rand`
4. The real `.env` files are used by docker-compose

## Manual Generation

If you need to regenerate the environment files locally:

```bash
cd /path/to/netbox-docker
./generate-env-files.sh
```

This will create:
- `env/redis.env`
- `env/redis-cache.env`
- `env/postgres.env`
- `env/netbox.env`

## Security Best Practices

✅ **DO:**
- Commit `*.env.template` files
- Generate secrets during deployment
- Use strong random passwords
- Keep `.env` files out of version control

❌ **DON'T:**
- Commit `*.env` files with real secrets
- Reuse the same secrets across environments
- Share production secrets in git

## Automated Deployment

The `setup-containerlab.sh` script automatically:
1. Generates fresh secrets from templates
2. Creates the `.env` files
3. Launches NetBox with docker-compose

No manual intervention needed for deployment!
