#!/bin/sh
set -e

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

readonly spec="$1"
readonly fail_on="$2"
readonly allow_external_refs="$3"

echo "running oasdiff validate... spec: $spec, fail_on: $fail_on, allow_external_refs: $allow_external_refs"

# Build flags. The action input allow-external-refs defaults to false (safe for
# CI on untrusted PRs); pass whatever it resolved to so the explicit input is
# authoritative over any oasdiff.yaml value. --fail-on defaults to ERR in oasdiff
# (errors fail the build; warnings and info are reported but don't), so only
# pass it when the input overrides the threshold.
flags=""
if [ -n "$allow_external_refs" ]; then
    flags="$flags --allow-external-refs=$allow_external_refs"
fi
if [ -n "$fail_on" ]; then
    flags="$flags --fail-on $fail_on"
fi
echo "flags: $flags"

# Run 1: render annotations to stdout via --format githubactions so GitHub
# parses them onto the PR's "Files changed" tab. This is the authoritative
# run: its exit code honours --fail-on (1 when a finding is at or above the
# threshold, 0 otherwise). Tolerate non-zero so we can still set the outputs
# below; the exit code is reapplied at the end.
exit_code=0
oasdiff validate $flags --format githubactions "$spec" || exit_code=$?

# Run 2: text format, captured for the finding count. Tolerate non-zero
# exit (the authoritative decision is already captured above).
findings_text=$(oasdiff validate $flags "$spec") || true

# *** GitHub Action step output ***

# Total finding count from the header "N findings: N error, N warning, N info".
# A valid spec prints nothing, so the count stays 0.
findings_count=0
if [ -n "$findings_text" ]; then
    header=$(printf '%s' "$findings_text" | head -n 1)
    n=$(printf '%s' "$header" | awk '{print $1}')
    if printf '%s' "$n" | grep -qE '^[0-9]+$'; then
        findings_count="$n"
    fi
fi
echo "findings=$findings_count" >>"$GITHUB_OUTPUT"

# The --format githubactions run above writes error_count/warning_count/
# info_count to GITHUB_OUTPUT, but only when there are findings. Emit zeros
# for a valid spec so those outputs are always present for callers.
if [ "$findings_count" -eq 0 ]; then
    {
        echo "error_count=0"
        echo "warning_count=0"
        echo "info_count=0"
    } >>"$GITHUB_OUTPUT"
fi

exit "$exit_code"
