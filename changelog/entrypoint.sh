#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly include_path_params="$3"

echo "running oasdiff changelog base: $base, revision: $revision, include_path_params: $include_path_params"

# Build flags to pass in command
flags=""
if [ "$include_path_params" = "true" ]; then
    flags="${flags} --include-path-params"
fi
echo "flags: $flags"

set -o pipefail

if [ -n "$flags" ]; then
    OUTPUT=$(oasdiff changelog "$base" "$revision" $flags)
else
    OUTPUT=$(oasdiff changelog "$base" "$revision")
fi

echo "$OUTPUT"

# GitHub Actions limits output to 1MB
# We count bytes because unicode has multibyte characters
SIZE=$(echo "$OUTPUT" | wc -c)
if [ "$SIZE" -ge "1000000" ]; then
    echo "WARN: Diff exceeds the 1MB limit, truncating output..." >&2
    OUTPUT=$(echo "$OUTPUT" | head -c $LIMIT)
fi

DELIMITER=$(cat /proc/sys/kernel/random/uuid | tr -d '-')

echo "changelog<<$DELIMITER" >>$GITHUB_OUTPUT
echo "$OUTPUT" >>$GITHUB_OUTPUT
echo "$DELIMITER" >>$GITHUB_OUTPUT

echo '```' >>$GITHUB_STEP_SUMMARY
echo "$OUTPUT" >>$GITHUB_STEP_SUMMARY
echo '```' >>$GITHUB_STEP_SUMMARY
