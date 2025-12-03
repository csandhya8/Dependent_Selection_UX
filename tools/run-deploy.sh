
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REPO="${REPO:-}"                # Optionally set "org/repo"; auto-detect if empty
WORKFLOW_FILE="${WORKFLOW_FILE:-deploy.yml}"  # Must match your workflow file
MATRIX_FILE="${MATRIX_FILE:-config/deploy-matrix.json}"

# --- Requirements checks ---
command -v gh >/dev/null 2>&1 || { echo "ERROR: 'gh' CLI not found. Install: https://cli.github.com/"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: 'jq' not found. Install: https://stedolan.github.io/jq/"; exit 1; }
[[ -f "$MATRIX_FILE" ]] || { echo "ERROR: Mapping file '$MATRIX_FILE' not found."; exit 1; }

# --- Auth check ---
if ! gh auth status >/dev/null 2>&1; then
  echo "You are not authenticated. Run: gh auth login"
  exit 1
fi

# --- Repo detection (if not provided) ---
if [[ -z "${REPO}" ]]; then
  # Try to infer from current git remote
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote_url=$(git remote get-url origin 2>/dev/null || true)
    if [ "$remote_url" =~ github\.com[://(.+)(\.git)?$ ]]; then
      owner="${BASH_REMATCH[1]}"
      name="${BASH_REMATCH[2]}"
      REPO="${owner}/${name}"
    else
      echo "WARN: Could not parse repo from remote. You can set REPO=org/repo env var."
    fi
  fi
fi

# --- Load envs from JSON keys ---
mapfile -t ENVS < <(jq -r 'keys[]' "$MATRIX_FILE")
if [[ "${#ENVS[@]}" -eq 0 ]]; then
  echo "ERROR: No environments defined in $MATRIX_FILE"; exit 1;
fi

echo "Select environment:"
select ENV in "${ENVS[@]}"; do
  [[ -n "${ENV:-}" ]] && break
done

# --- Load dependent services ---
mapfile -t SERVICES < <(jq -r --arg env "$ENV" '.[$env][]' "$MATRIX_FILE")
if [[ "${#SERVICES[@]}" -eq 0 ]]; then
  echo "ERROR: No services defined for env '$ENV' in $MATRIX_FILE"; exit 1;
fi

echo "Available services for '$ENV': ${SERVICES[*]}"
echo "Select service:"
select SERVICE in "${SERVICES[@]}"; do
  [[ -n "${SERVICE:-}" ]] && break
done

# --- Version prompt ---
read -r -p "Version (e.g., 1.2.3 or v1.2.3): " VERSION
VERSION="${VERSION#v}"  # strip leading v

# --- Confirm selection ---
echo
echo "➡️  Dispatching:"
echo "   Repo:      ${REPO:-'(current context)'}"
echo "   Workflow:  ${WORKFLOW_FILE}"
echo "   Env:       ${ENV}"
echo "   Service:   ${SERVICE}"
echo "   Version:   ${VERSION}"
echo

# --- Trigger workflow_dispatch ---
# If REPO set: use -R org/repo ; else rely on current directory context
if [[ -n "${REPO:-}" ]]; then
  gh workflow run "$WORKFLOW_FILE" -R "$REPO" \
    -f env="$ENV" -f service="$SERVICE" -f version="$VERSION"
else
  gh workflow run "$WORKFLOW_FILE" \
    -f env="$ENV" -f service="$SERVICE" -f version="$VERSION"
fi

echo "✅ Triggered. Use 'gh run list' and 'gh run watch' to monitor."
