#!/usr/bin/env bash
# =============================================================================
# Secret & PII Scanner
# =============================================================================
# Wrapper around gitleaks for secret and PII detection.
#
# Usage:
#   scripts/scan-secrets.sh --staged    # Pre-commit: scan staged files only
#   scripts/scan-secrets.sh --all       # Full repo scan
#   scripts/scan-secrets.sh             # Default: full repo scan
#
# Exit codes:
#   0 - No secrets found (or gitleaks not installed in pre-commit mode)
#   1 - Secrets/PII detected or error
# =============================================================================

set -euo pipefail

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

MODE="${1:---all}"
CONFIG=".gitleaks.toml"

# ─── Check gitleaks installation ─────────────────────────────────────────────

if ! command -v gitleaks &>/dev/null; then
    echo ""
    if [ "$MODE" = "--staged" ]; then
        # Pre-commit: warn but don't block
        echo -e "${YELLOW}Warning: gitleaks not installed — skipping secret scan${RESET}"
        echo -e "${CYAN}Install for automatic secret detection:${RESET}"
    else
        # Manual/CI: fail
        echo -e "${RED}Error: gitleaks is not installed${RESET}"
        echo -e "${CYAN}Install gitleaks:${RESET}"
    fi
    echo ""
    echo "  macOS:    brew install gitleaks"
    echo "  Linux:    wget -qO- https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_\$(uname -s)_\$(uname -m).tar.gz | tar xz -C /usr/local/bin"
    echo "  Windows:  scoop install gitleaks"
    echo "  Docker:   docker run --rm -v \$(pwd):/repo gitleaks/gitleaks:latest detect --source /repo"
    echo ""

    if [ "$MODE" = "--staged" ]; then
        exit 0
    else
        exit 1
    fi
fi

# ─── Config file ─────────────────────────────────────────────────────────────

CONFIG_FLAG=""
if [ -f "$CONFIG" ]; then
    CONFIG_FLAG="--config=$CONFIG"
fi

# ─── Run scan ────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Secret & PII Scanner${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$MODE" = "--staged" ]; then
    echo -e "${CYAN}Scanning staged files...${RESET}"
    echo ""
    # protect mode scans staged changes (for pre-commit)
    if gitleaks protect --staged $CONFIG_FLAG --verbose; then
        echo ""
        echo -e "${GREEN}No secrets or PII detected in staged files.${RESET}"
        exit 0
    else
        echo ""
        echo -e "${RED}Secrets or PII detected in staged files!${RESET}"
        echo -e "${YELLOW}Fix the issues above, or add 'pragma: allowlist secret' to suppress false positives.${RESET}"
        exit 1
    fi
else
    echo -e "${CYAN}Scanning full repository...${RESET}"
    echo ""
    # detect mode scans the full repo
    if gitleaks detect $CONFIG_FLAG --verbose; then
        echo ""
        echo -e "${GREEN}No secrets or PII detected.${RESET}"
        exit 0
    else
        echo ""
        echo -e "${RED}Secrets or PII detected!${RESET}"
        echo -e "${YELLOW}Fix the issues above, or add 'pragma: allowlist secret' to suppress false positives.${RESET}"
        exit 1
    fi
fi
