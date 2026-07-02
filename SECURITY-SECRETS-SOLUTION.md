# NetBox Secrets Management Solution

## Problem

GitHub security scanning detected hardcoded secrets in the following files:
- `netbox-docker/env/redis.env`
- `netbox-docker/env/redis-cache.env`
- `netbox-docker/env/postgres.env`
- `netbox-docker/env/netbox.env`

These files contained:
- Database passwords
- Redis passwords
- Django SECRET_KEY
- API token peppers

## Solution

Implemented a **template-based secret generation** approach that:

1. ✅ Removes all hardcoded secrets from git
2. ✅ Generates random secrets at deployment time
3. ✅ Maintains security best practices
4. ✅ Works seamlessly with existing deployment automation

## Implementation

### 1. Template Files (Safe to Commit)

Created template files with placeholders:
```
netbox-docker/env/
├── netbox.env.template      (uses __SECRET_KEY__, __POSTGRES_PASSWORD__, etc.)
├── postgres.env.template    (uses __POSTGRES_PASSWORD__)
├── redis.env.template       (uses __REDIS_PASSWORD__)
├── redis-cache.env.template (uses __REDIS_CACHE_PASSWORD__)
└── README.md
```

### 2. Generation Script

`netbox-docker/generate-env-files.sh`:
- Generates cryptographically random secrets using `openssl rand`
- Creates actual `.env` files from templates
- Sets restrictive permissions (600) on generated files
- Runs automatically during deployment

### 3. GitIgnore Protection

Updated `netbox-docker/.gitignore`:
```gitignore
# Ignore actual env files (secrets)
env/*.env
# But keep the templates
!env/*.env.template
```

### 4. Automated Deployment Integration

Updated `setup-automation/setup-containerlab.sh` to:
1. Check for `generate-env-files.sh`
2. Run it before `docker compose up`
3. Generate fresh secrets every deployment
4. Log the generation process

## Benefits

### Security
- ✅ No secrets in version control
- ✅ Random, strong passwords (16-32 chars)
- ✅ Unique secrets per deployment
- ✅ Passes GitHub secret scanning

### Developer Experience
- ✅ Zero manual steps
- ✅ Automatic secret generation
- ✅ Clear documentation
- ✅ Works with existing automation

### Maintainability
- ✅ Template-based approach is easy to update
- ✅ Single source of truth for env structure
- ✅ README documents the approach
- ✅ Scripts are version controlled

## Files Changed

### Added
- `netbox-docker/env/*.env.template` (4 template files)
- `netbox-docker/env/README.md`
- `netbox-docker/generate-env-files.sh`

### Modified
- `netbox-docker/.gitignore` (ignore *.env files)
- `setup-automation/setup-containerlab.sh` (call generation script)

### Removed from Git (but preserved locally)
- `netbox-docker/env/netbox.env`
- `netbox-docker/env/postgres.env`
- `netbox-docker/env/redis.env`
- `netbox-docker/env/redis-cache.env`

## Testing

To verify the solution works:

```bash
# 1. Remove existing env files
rm netbox-docker/env/*.env

# 2. Run generation script
./netbox-docker/generate-env-files.sh

# 3. Verify new files created
ls -la netbox-docker/env/*.env

# 4. Check secrets are random
grep "PASSWORD=" netbox-docker/env/*.env
```

## Deployment Flow

1. **Clone repository** - Templates come with the repo
2. **Run setup script** - Calls `generate-env-files.sh` automatically
3. **Secrets generated** - Random passwords created
4. **Docker Compose starts** - Uses generated `.env` files
5. **NetBox runs** - With unique, secure credentials

## Alternative Approaches Considered

1. ❌ **docker-compose.override.yml** - Still requires secrets somewhere
2. ❌ **Environment variables** - Difficult to manage multiple secrets
3. ❌ **External secret managers** - Overkill for workshop/demo environment
4. ✅ **Template + Generation** - Best balance of security and simplicity

## Next Steps

After committing these changes:
1. GitHub secret scanning will pass ✅
2. Secrets are generated at runtime ✅
3. No manual secret management needed ✅
4. Workshop automation continues to work ✅

## Commit Message

```
fix: remove hardcoded secrets from NetBox env files

- Replace .env files with .env.template files using placeholders
- Add generate-env-files.sh to create secrets at deployment time
- Update .gitignore to exclude actual .env files
- Integrate generation into setup-containerlab.sh automation
- Add documentation in env/README.md

This resolves GitHub secret scanning alerts by:
1. Removing all hardcoded passwords from version control
2. Generating random secrets during deployment
3. Maintaining zero-touch automation for workshop setup

Secrets are now generated using openssl rand with 16-32 character
random passwords, unique per deployment.
```
