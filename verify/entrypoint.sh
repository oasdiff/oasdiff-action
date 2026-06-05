#!/bin/sh
set -e

# oasdiff "verify installation" run.
#
# A read-only setup check: it posts NO PR comment and sets NO commit status.
# Meant to be triggered manually (workflow_dispatch) from the GitHub Actions UI.
# It renders a progressive checklist in the workflow Step Summary:
#
#   1. Workflow runs        (implicit: this run is executing)
#   2. Connected to oasdiff (the OASDIFF_TOKEN secret authenticated)
#   3. App installed        (the oasdiff GitHub App is installed on this repo)
#   4. Spec found           (oasdiff resolved base + revision and ran the diff)
#
# Reviewer access (signing in on oasdiff.com) is verified separately on the
# setup page, not here.

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

readonly base="$1"
readonly revision="$2"
readonly oasdiff_token="$3"
readonly service_url="${4:-https://api.oasdiff.com}"
readonly allow_external_refs="$5"

echo "Verifying oasdiff setup — base: $base, revision: $revision (no comment will be posted)"

flags=""
if [ -n "$allow_external_refs" ]; then
    flags="$flags --allow-external-refs=$allow_external_refs"
fi

# Check 4 (spec found): can oasdiff resolve base + revision (including any
# in-repo / relative $refs, which load via git show when the spec path uses
# the git-revision format "<git-ref>:<path>") and run the diff? We don't need
# the output, only the exit code. Tolerate a non-zero exit (set -e) so we can
# report the failure rather than abort.
#
# Exit 123 is the dedicated "external $ref refused" code (oasdiff v1.18.1): the
# spec loaded but an external $ref was blocked because allow-external-refs is
# false (the safe default). That's a distinct case from "spec not found" — the
# fix is to allow external refs for a trusted spec, not to fix the path.
_err=$(mktemp)
specs_found=false
external_ref_blocked=false
set +e
oasdiff changelog "$base" "$revision" --format json $flags >/dev/null 2>"$_err"
oasdiff_exit=$?
set -e
if [ "$oasdiff_exit" -eq 0 ]; then
    specs_found=true
elif [ "$oasdiff_exit" -eq 123 ]; then
    external_ref_blocked=true
fi

owner="${GITHUB_REPOSITORY%%/*}"
repo="${GITHUB_REPOSITORY#*/}"

if [ -z "$oasdiff_token" ]; then
    echo "::error title=oasdiff verify::No oasdiff-token provided. Add your OASDIFF_TOKEN as a repository secret, then re-run."
    exit 1
fi

# POST the outcome to the service. Reaching a 2xx proves the token authenticated
# (check 2); the response carries the App-installation result (check 3).
payload=$(jq -nc \
    --arg owner "$owner" \
    --arg repo "$repo" \
    --argjson specs_found "$specs_found" \
    --arg base_file "$base" \
    --arg revision_file "$revision" \
    '{owner: $owner, repo: $repo, specs_found: $specs_found, base_file: $base_file, revision_file: $revision_file}')

response=$(printf '%s' "$payload" | curl -s -w "\n%{http_code}" -X POST \
    "${service_url}/tenants/${oasdiff_token}/verify" \
    -H "Content-Type: application/json" \
    -H "User-Agent: oasdiff-action/${GITHUB_ACTION_REF:-unknown}" \
    --data-binary @-)
http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')
[ -z "$http_code" ] && http_code=0

# Resolve each check from the response. token_ok is true on any 2xx (the request
# authenticated); 401/403 means the secret is wrong/missing or the tenant is
# inactive. app_installed comes from the service probe.
if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] 2>/dev/null; then
    token_ok=true
    app_installed=$(echo "$body" | jq -r '.app_installed // false' 2>/dev/null)
    # specs_found / external_ref_blocked stay as determined locally above; the
    # service only echoes specs_found, and it can't see the external-ref case.
elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
    token_ok=false
    app_installed=unknown
else
    echo "::error title=oasdiff verify::the oasdiff service returned HTTP $http_code"
    echo "$body" >&2
    token_ok=unknown
    app_installed=unknown
fi

# Render the progressive checklist.
mark() { # $1 = true|false|unknown, $2 = label
    case "$1" in
        true)  echo "- ✅ $2" ;;
        false) echo "- ❌ $2" ;;
        *)     echo "- ⬜ $2 (could not determine)" ;;
    esac
}

{
    echo "## oasdiff setup verification"
    echo ""
    mark true "GitHub Actions workflow is running"
    mark "$token_ok" "Connected to oasdiff (OASDIFF_TOKEN secret)"
    mark "$app_installed" "oasdiff GitHub App installed on ${owner}/${repo}"
    if [ "$specs_found" = "true" ]; then
        echo "- ✅ OpenAPI spec found and compared"
    elif [ "$external_ref_blocked" = "true" ]; then
        echo "- ❌ OpenAPI spec found, but an external \$ref was blocked"
    else
        echo "- ❌ OpenAPI spec found and compared"
    fi
    echo ""
    if [ "$token_ok" = "false" ]; then
        echo "> **Connect to oasdiff:** the \`OASDIFF_TOKEN\` repository secret is missing or wrong. Copy it from your oasdiff setup page into repo Settings → Secrets and variables → Actions."
    fi
    if [ "$app_installed" = "false" ]; then
        echo "> **Install the App:** the oasdiff GitHub App is not installed on \`${owner}/${repo}\`. Install it at https://github.com/apps/oasdiff/installations/new (an org owner may need to approve it)."
    fi
    if [ "$external_ref_blocked" = "true" ]; then
        echo "> **External \$ref blocked:** your spec resolves an external \`\$ref\`, disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set \`allow-external-refs: true\` on the action step."
    elif [ "$specs_found" = "false" ]; then
        echo "> **Spec not found:** oasdiff could not resolve \`$base\` / \`$revision\`. Check the \`base\`/\`revision\` paths (multi-file specs need their referenced files present — use the \`origin/<base>:<path>\` git-revision spec path format so in-repo \$refs resolve via git)."
        [ -s "$_err" ] && echo "> \`\`\`" && tr '\n' ' ' < "$_err" | cut -c1-500 && echo "" && echo "> \`\`\`"
    fi
    echo ""
    echo "_Reviewer access (signing in on oasdiff.com) is verified separately on your setup page._"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Surface a one-line annotation for each red check.
[ "$token_ok" = "false" ] && echo "::error title=oasdiff verify::OASDIFF_TOKEN secret is missing or invalid."
[ "$app_installed" = "false" ] && echo "::error title=oasdiff verify::oasdiff GitHub App is not installed on ${owner}/${repo}."
[ "$external_ref_blocked" = "true" ] && echo "::error title=oasdiff verify::Spec uses an external \$ref, blocked by default. Set allow-external-refs: true if the spec is trusted."
[ "$specs_found" = "false" ] && [ "$external_ref_blocked" = "false" ] && echo "::error title=oasdiff verify::OpenAPI spec not found at the configured base/revision path."

# Exit non-zero if any bot-chain check is not green, so the verify run is a
# clear red/green signal. token_ok unknown (transient service error) also fails.
if [ "$token_ok" = "true" ] && [ "$app_installed" = "true" ] && [ "$specs_found" = "true" ]; then
    echo "✅ oasdiff setup verified — comments will post on every PR."
    exit 0
fi
echo "Setup not complete yet — see the checklist in the run summary."
exit 1
