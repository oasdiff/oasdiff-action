#!/bin/sh
set -e

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

readonly spec="$1"
readonly fail_on_finding="$2"
readonly allow_external_refs="$3"

echo "running oasdiff validate... spec: $spec, fail_on_finding: $fail_on_finding, allow_external_refs: $allow_external_refs"

# Build flags. --allow-external-refs defaults to true in oasdiff so we
# only pass --allow-external-refs=false when the input explicitly opts
# out; otherwise rely on the binary's default.
flags=""
if [ "$allow_external_refs" = "false" ]; then
    flags="$flags --allow-external-refs=false"
fi
echo "flags: $flags"

# Run 1: capture the text-format findings count for GITHUB_OUTPUT and
# the user-facing step log. Tolerate non-zero exit — oasdiff returns 1
# when any finding is reported, but we render annotations and the
# fail-on-finding decision below regardless.
validate_exit=0
findings_text=$(oasdiff validate $flags "$spec") || validate_exit=$?

# Run 2: render annotations to stdout via --format githubactions so
# GitHub parses them onto the PR's "Files changed" tab. Tolerate
# non-zero exit (same reason as Run 1).
oasdiff validate $flags --format githubactions "$spec" || true

# *** GitHub Action step output ***

# Extract the finding count from the first line of the text output:
# "N findings: N error, N warning, N info"
findings_count=0
if [ -n "$findings_text" ]; then
    header=$(printf '%s' "$findings_text" | head -n 1)
    findings_count=$(printf '%s' "$header" | awk '{print $1}')
    if ! printf '%s' "$findings_count" | grep -qE '^[0-9]+$'; then
        findings_count=0
    fi
fi
echo "findings=$findings_count" >>"$GITHUB_OUTPUT"

# Emit upgrade notice with a clickable summary link pointing at the
# free review surface. Same pattern as the breaking action: notice
# annotation + GITHUB_STEP_SUMMARY markdown link.
if [ "$findings_count" -gt 0 ]; then
    notice_url="https://www.oasdiff.com/review?owner=$(printf '%s' "${GITHUB_REPOSITORY%%/*}" | jq -sRr @uri)&repo=$(printf '%s' "${GITHUB_REPOSITORY#*/}" | jq -sRr @uri)"
    echo "::notice::🔎 ${findings_count} OpenAPI validation finding(s) — see annotations above. oasdiff.com → ${notice_url}"
    {
        echo "### 🔎 oasdiff validate found ${findings_count} OpenAPI spec issue(s)"
        echo ""
        echo "See annotations on the Files Changed tab for the precise line and column of each finding."
        echo ""
        echo "[Learn more about oasdiff →](${notice_url})"
    } >> "$GITHUB_STEP_SUMMARY"
fi

# Honour fail-on-finding (default true). When false, we report findings
# but the step still passes — useful for non-blocking visibility runs.
if [ "$fail_on_finding" = "false" ]; then
    exit 0
fi
exit "$validate_exit"
