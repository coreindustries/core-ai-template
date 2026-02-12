# Docker Development Rules

**These rules apply to projects using Docker** for development, CI/CD, and production deployment. Follow these practices for secure, efficient, and reproducible container builds.

## Quick Reference

- **Base Images**: Use specific tags (not `latest`), prefer minimal images (`-slim`, `-alpine`, `distroless`)
- **Multi-Stage Builds**: Always use for compiled languages and production images
- **Layer Caching**: Order instructions from least to most frequently changing
- **Security**: Run as non-root, no secrets in images, scan for vulnerabilities
- **Health Checks**: Define `HEALTHCHECK` for all service containers
- **Compose**: Use profiles for optional services, named volumes for persistence

## 1. Dockerfile Best Practices

### Use Multi-Stage Builds

Separate build dependencies from the runtime image to minimize size and attack surface.

```dockerfile
# Stage 1: Build
FROM node:22-slim AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:22-slim AS production
WORKDIR /app
RUN addgroup --system app && adduser --system --ingroup app app
COPY --from=builder --chown=app:app /app/dist ./dist
COPY --from=builder --chown=app:app /app/node_modules ./node_modules
COPY --from=builder --chown=app:app /app/package.json ./
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD node -e "fetch('http://localhost:3000/health').then(r => process.exit(r.ok ? 0 : 1))"
CMD ["node", "dist/main.js"]
```

### Python Multi-Stage

```dockerfile
FROM python:3.13-slim AS builder
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN pip install uv && uv sync --frozen --no-dev
COPY . .

FROM python:3.13-slim AS production
WORKDIR /app
RUN addgroup --system app && adduser --system --ingroup app app
COPY --from=builder --chown=app:app /app /app
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
CMD ["uv", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Layer Ordering for Cache Efficiency

```dockerfile
# CORRECT: Dependencies change less often than source code
COPY package.json package-lock.json ./
RUN npm ci
COPY . .

# WRONG: Busts cache on every source change
COPY . .
RUN npm ci
```

### Pin Base Image Versions

```dockerfile
# CORRECT: Specific version
FROM node:22.12-slim
FROM python:3.13.1-slim

# WRONG: Mutable tags
FROM node:latest
FROM python:3
```

## 2. Container Security

### Run as Non-Root

**ALWAYS** create and switch to a non-root user.

```dockerfile
RUN addgroup --system app && adduser --system --ingroup app app
USER app
```

### Never Store Secrets in Images

```dockerfile
# WRONG: Secret baked into image
ENV DATABASE_URL=postgres://user:password@db:5432/app
COPY .env /app/.env

# CORRECT: Inject at runtime
# Use environment variables, Docker secrets, or mounted files
CMD ["node", "dist/main.js"]
# Run with: docker run -e DATABASE_URL=... myapp
```

### Use .dockerignore

```
.git
.env
.env.*
node_modules
dist
coverage
.cache
*.md
!README.md
.claude
.vscode
.devcontainer
```

### Minimize Attack Surface

```dockerfile
# CORRECT: Minimal base
FROM node:22-slim        # ~200MB
FROM python:3.13-slim    # ~150MB
FROM gcr.io/distroless/nodejs22  # ~130MB, no shell

# AVOID: Full images unless needed for build stage
FROM node:22             # ~1GB
FROM python:3.13         # ~900MB
```

### Scan Images

```bash
# Docker Scout (built-in)
docker scout cves myapp:latest

# Trivy
trivy image myapp:latest

# Snyk
snyk container test myapp:latest
```

## 3. Health Checks

**DEFINE** health checks for all service containers.

```dockerfile
# HTTP health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# TCP health check (when curl not available)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('net').createConnection(3000, 'localhost').on('error', () => process.exit(1))"
```

### Docker Compose Health Checks

```yaml
services:
  api:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      start_period: 10s
      retries: 3

  db:
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER"]
      interval: 10s
      timeout: 3s
      retries: 5
```

## 4. Docker Compose Patterns

### Service Dependencies

```yaml
services:
  api:
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

### Profiles for Optional Services

```yaml
services:
  db:
    image: postgres:16
    # Always starts (no profile)

  redis:
    image: redis:7-alpine
    profiles: [cache]
    # Only starts with: docker compose --profile cache up

  mailhog:
    image: mailhog/mailhog
    profiles: [dev]
    # Only starts with: docker compose --profile dev up
```

### Named Volumes for Persistence

```yaml
volumes:
  postgres_data:     # Survives container recreation
  redis_data:

services:
  db:
    volumes:
      - postgres_data:/var/lib/postgresql/data
```

### Environment Variable Management

```yaml
services:
  api:
    env_file: .env
    environment:
      # Override specific vars
      NODE_ENV: development
      DATABASE_URL: postgres://dev:dev@db:5432/app
```

## 5. Development vs Production

### Development Compose

```yaml
# docker-compose.yml (development)
services:
  api:
    build:
      context: .
      target: builder          # Use build stage for dev
    volumes:
      - .:/app                 # Hot reload via bind mount
      - /app/node_modules      # Prevent overwriting node_modules
    command: npm run dev
    ports:
      - "3000:3000"
      - "9229:9229"            # Debug port
```

### Production Compose

```yaml
# docker-compose.prod.yml
services:
  api:
    build:
      context: .
      target: production       # Use production stage
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "0.5"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## 6. CI/CD Patterns

### Build and Push

```yaml
# GitHub Actions
- name: Build and push
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

### Use BuildKit Cache Mounts

```dockerfile
# Cache package manager downloads between builds
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Python
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen
```

## 7. Common Anti-Patterns

| Anti-Pattern | Fix |
|-------------|-----|
| `FROM node:latest` | Pin to specific version: `FROM node:22.12-slim` |
| Running as root | Add `USER app` after creating non-root user |
| `COPY . .` before `npm ci` | Copy lock files first, install, then copy source |
| Secrets in `ENV` or `COPY .env` | Inject at runtime via `-e` or Docker secrets |
| No `.dockerignore` | Create one to exclude `.git`, `node_modules`, `.env` |
| No `HEALTHCHECK` | Add health check for orchestrator compatibility |
| `apt-get install` without cleanup | Chain with `&& rm -rf /var/lib/apt/lists/*` |
| Giant images in production | Use multi-stage builds with slim/distroless base |

## See Also

- `.claude/rules/security-core.md` - Core security practices (always auto-loaded)
- `.claude/rules-available/security-owasp.md` - OWASP Top 10 standards
- [Docker Best Practices](https://docs.docker.com/build/building/best-practices/)
- [Dockerfile Reference](https://docs.docker.com/reference/dockerfile/)
