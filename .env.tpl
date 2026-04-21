# =============================================================================
# .env.tpl — secret REFERENCES only, never values.
# =============================================================================
# This file is committed. Secrets are hydrated into process memory at runtime
# by the wrapper defined in the Makefile:
#
#   aws-vault exec <profile> -- chamber exec <service-name> -- <command>
#
# Plaintext secrets never touch disk in any environment (dev, CI, prod).
# See .claude/rules/secrets-hygiene.md for the full directive.
# =============================================================================

# -----------------------------------------------------------------------------
# Where values come from
# -----------------------------------------------------------------------------
# chamber reads from AWS SSM Parameter Store under a service prefix:
#   /<service-name>/database_url      → env var DATABASE_URL
#   /<service-name>/anthropic_api_key → env var ANTHROPIC_API_KEY
#
# To add a secret:
#   chamber write <service-name> database_url 'postgresql://...'
#
# To read what's there:
#   chamber list <service-name>
#   chamber export <service-name>   # (returns JSON, not values)
#
# For Secrets Manager JSON blobs (DB creds, multi-field secrets):
#   Use the ARN pattern with aws-env-cli or a custom wrapper.
# -----------------------------------------------------------------------------

# Required — application will fail fast at startup if missing
# DATABASE_URL                     # /<service-name>/database_url
# ANTHROPIC_API_KEY                # /<service-name>/anthropic_api_key

# Optional — uncomment and document as the project adds integrations
# OPENAI_API_KEY                   # /<service-name>/openai_api_key
# STRIPE_SECRET_KEY                # /<service-name>/stripe_secret_key
# SENTRY_DSN                       # /<service-name>/sentry_dsn

# Non-secret configuration — set by the wrapper, not from SSM
# APP_ENV                          # development | staging | production
# AWS_REGION                       # us-west-2
# LOG_LEVEL                        # info | debug | warn | error
