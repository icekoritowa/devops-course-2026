#!/usr/bin/env bash
set -euo pipefail
fail() { echo "$*" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${DEPLOY_REMOTE:-devops}"
REMOTE_DIR=/var/www/devops-site
SITE_URL="${DEPLOY_URL:-https://devops.local}"
CA_CERT="${DEPLOY_CA_CERT:-${HOME}/devops.crt}"
DRY=()
case "${1:-}" in
 '') [[ $# -eq 0 ]] || fail 'Unexpected arguments' ;;
 --dry-run) [[ $# -eq 1 ]] || fail 'Unexpected arguments'; DRY=(--dry-run) ;;
 *) fail 'Usage: deploy.sh [--dry-run]' ;;
esac
[[ -f "$ROOT/site/index.html" ]] || fail 'Missing site/index.html'
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || fail 'Uncommitted changes'
HASH=$(git -C "$ROOT" rev-parse --short HEAD)
rsync -avz --delete --chmod=D755,F644 "${DRY[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' "$ROOT/site/" "$REMOTE:$REMOTE_DIR/" || fail 'Synchronization failed'
if [[ ${#DRY[@]} -gt 0 ]]; then echo "Dry run: $HASH"; exit 0; fi
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --cacert "$CA_CERT" "$SITE_URL/" > /dev/null || fail 'HTTPS check failed'
echo "Deployed: $HASH"
