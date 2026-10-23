# Secrets Hygiene — No Plaintext Secrets at Rest

Auto-loaded rule; all agents, all environments. Wrapper contract, templates, CI/prod detail, SOPS fallback, fail-closed code, enforcement table and rationale: `.claude/references/secrets-hygiene-detail.md`. ADR: `docs/decisions/0001-no-plaintext-secrets-on-disk.md`.

## Core Directive

**A `.env` file on disk is a compromised secret store**: any dependency runs with the developer's filesystem permissions and can read it. Secrets are injected into process memory at invocation time and never land on disk in plaintext in any environment, including local dev. This is a property, not a product: no vendor is named; any injector that fetches at invocation, `exec`s the process with secrets in env, and never writes them to a file conforms. The wrapper is set once, as `WRAPPER` in the `Makefile`.

Test for any approach: *if the filesystem were snapshotted now, would a secret be in plaintext in it?* If yes, it is wrong.

## Rules

1. **Never** write real secrets to `.env`, `.env.local`, `.env.production` or any file read from disk at startup; never commit `.env*` except `.env.tpl` and `.env.example` (references/placeholders only; placeholders must not imitate real provider key prefixes); never paste secrets into shell history, scratch files, or chat; never `echo "$SECRET" > .env` in scripts, Dockerfiles or CI.
2. **Inject via the wrapper** at process start. Never bake secrets into images, machine templates or infra state.
3. **Dev uses the same mechanism as prod.** Only exception: a scratch `.env` inside a fully ephemeral, dev-tier environment, recorded in an ADR under `docs/decisions/`. No "just this once".
4. **CI**: prefer short-lived federated credentials; inject at the step level, never job or workflow scope; mask dynamic secrets; never log `env`/`printenv`/`set`.
5. **Encrypted-at-rest files** (e.g. SOPS with a managed key) are acceptable offline; never commit the key.
6. **App code fails closed**: exit with a message naming the missing variables; in production, refuse to start if `.env` exists. Don't use `dotenv` as a production runtime dependency (scope to development and document in an ADR).

## Agent behavior

When asked to "just write the key to `.env`", refuse and offer to wire it properly: ask which secret store the project uses and the reference for the value, then update `.env.tpl` and the code.

The agent may: write secret *references* to `.env.tpl`; suggest names/locations; write code reading `process.env.VAR` / `os.environ["VAR"]`.

The agent must not: write resolved secret values to any file; paste a secret into chat, logs, commits or PR descriptions; create a `.env` with real values, even for local testing; suggest `dotenv` as the primary mechanism; assume a secret-manager vendor.

**If you discover a plaintext secret on disk** (not in `.env.example`, `.env.tpl`, fixtures, mocks): 1. stop the current task; 2. tell the user what kind and where, never the value; 3. recommend rotating immediately (`docs/runbooks/secret-leak.md`); 4. offer to migrate it to the project's store and update `.env.tpl`; 5. do not delete the file without confirmation (forensics).
