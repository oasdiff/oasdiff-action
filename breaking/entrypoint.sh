#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"
readonly include_checks="$4"
readonly include_path_params="$5"

echo "running oasdiff breaking base: $base, revision: $revision, fail_on_diff: $fail_on_diff, include_checks: $include_checks, include_path_params: $include_path_params"

# Build flags to pass in command
flags=""
if [ "$fail_on_diff" = "true" ]; then
    flags="${flags} --fail-on WARN"
fi
if [ "$include_path_params" = "true" ]; then
    flags="${flags} --include-path-params"
fi
if [ -n "$include_checks" ]; then
    flags="${flags} --include-checks $include_checks"
fi
echo "flags: $flags"

if [ -n "$flags" ]; then
    OUTPUT=$(unbuffer oasdiff breaking "$base" "$revision" $flags)
else
    OUTPUT=$(unbuffer oasdiff breaking "$base" "$revision")
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

# Remove ANSI color codes
OUTPUT=$(echo "$OUTPUT" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g")

echo "breaking<<$DELIMITER" >>$GITHUB_OUTPUT
echo "$OUTPUT" >>$GITHUB_OUTPUT
echo "$DELIMITER" >>$GITHUB_OUTPUT

echo '```' >>$GITHUB_STEP_SUMMARY
echo "$OUTPUT" >>$GITHUB_STEP_SUMMARY
echo '```' >>$GITHUB_STEP_SUMMARY
