---
name: deploy
description: "Deploy the application to target platform."
---

# /deploy

Deploy the application to target platform.

## Usage

```
/deploy [environment] [--platform <platform>] [--dry-run]
```

## Arguments

- `environment`: `staging`, `production` (default: `staging`)
- `--platform`: Override auto-detected platform
- `--dry-run`: Preview deployment without executing

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Detect deployment platform from project configuration
- Run pre-deploy checks automatically
- Execute deployment end-to-end

**Safety:**
- Always deploy to staging first
- Require explicit confirmation for production
- Run all quality checks before deploying
- Never deploy from a dirty worktree

### Deploy Process

#### Phase 1: Pre-Deploy Checks

**Required before any deployment:**

1. **Clean worktree**:
   ```bash
   git status --porcelain
   ```

2. **On correct branch**:
   - Staging: `main` or feature branch
   - Production: `main` only

3. **All quality checks pass**:
   ```bash
   make quality  # or equivalent from prd/00_technology.md
   ```

4. **Up to date with remote**:
   ```bash
   git fetch origin
   git diff HEAD origin/main --stat
   ```

5. **Environment variables configured** for target environment

#### Phase 2: Detect Platform

Auto-detect from project files:

| File | Platform |
|------|----------|
| `vercel.json` or `.vercel/` | Vercel |
| `fly.toml` | Fly.io |
| `Dockerfile` + `docker-compose.yml` | Docker / container registry |
| `render.yaml` | Render |
| `railway.json` | Railway |
| `Procfile` | Heroku |
| `apprunner.yaml` | AWS App Runner |
| `Fastfile` (iOS) | TestFlight via Fastlane |
| `Fastfile` (Android) | Play Console via Fastlane |
| `app.json` (Expo) | EAS Build / Submit |

#### Phase 3: Deploy

##### Web — Vercel

```bash
# Staging (preview)
vercel --yes

# Production
vercel --prod --yes
```

##### Web — Docker

```bash
# Build and tag
docker build -t {registry}/{app}:{version} .

# Push to registry
docker push {registry}/{app}:{version}

# Deploy (platform-specific)
# Fly.io:
fly deploy --image {registry}/{app}:{version}
# Docker Compose (remote):
docker compose -f docker-compose.prod.yml up -d
```

##### Web — Fly.io

```bash
# Staging
fly deploy --config fly.staging.toml

# Production
fly deploy
```

##### iOS — TestFlight

```bash
# Build and upload
bundle exec fastlane beta
# This typically:
# 1. Increments build number
# 2. Builds archive
# 3. Uploads to App Store Connect
# 4. Submits to TestFlight
```

##### Android — Play Console

```bash
# Build and upload
bundle exec fastlane beta
# This typically:
# 1. Increments version code
# 2. Builds AAB
# 3. Uploads to Play Console
# 4. Submits to internal testing track
```

##### Mobile — Expo / EAS

```bash
# Build
eas build --platform all --profile {environment}

# Submit (after build)
eas submit --platform ios --profile {environment}
eas submit --platform android --profile {environment}
```

#### Phase 4: Post-Deploy Verification

1. **Health check**:
   ```bash
   curl -f https://{deploy_url}/health || echo "Health check failed"
   ```

2. **Smoke test** key endpoints or screens

3. **Monitor** logs for errors:
   ```bash
   # Platform-specific log tailing
   vercel logs --follow
   fly logs
   docker compose logs -f
   ```

4. **Tag deployment** (if not already tagged):
   ```bash
   git tag -a deploy/{environment}/$(date +%Y%m%d-%H%M) -m "Deployed to {environment}"
   ```

### Rollback

If issues are detected after deployment:

```bash
# Vercel
vercel rollback

# Fly.io
fly releases
fly deploy --image {previous_image}

# Docker
docker compose -f docker-compose.prod.yml up -d --force-recreate

# iOS — Cannot rollback TestFlight, submit new build
# Android — Rollback via Play Console halt rollout
```

### Deploy Checklist

- [ ] Worktree is clean
- [ ] On correct branch
- [ ] All tests pass
- [ ] Lint and type check pass
- [ ] Environment variables set for target
- [ ] Deployed to staging first
- [ ] Health check passes
- [ ] Smoke tests pass
- [ ] Deployment tagged in git

## Example Output

```
$ /deploy staging

Pre-deploy checks...
  Branch: main
  Worktree: clean
  Tests: passing (142/142)
  Lint: clean

Detected platform: Vercel

Deploying to staging...
  Building: 12s
  Deploying: 8s
  URL: https://my-app-staging-abc123.vercel.app

Post-deploy verification...
  Health check: 200 OK (45ms)
  API /users: 200 OK
  API /health: 200 OK

Staging deployment successful!
Preview: https://my-app-staging-abc123.vercel.app

To deploy to production:
  /deploy production
```
