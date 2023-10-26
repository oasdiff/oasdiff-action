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
    output=$(unbuffer oasdiff changelog "$base" "$revision" $flags)
else
    output=$(unbuffer oasdiff changelog "$base" "$revision")
fi

echo "$output"

# GitHub Actions limits output to 1MB
# We count bytes because unicode has multibyte characters
size=$(echo "$output" | wc -c)
if [ "$size" -ge "1000000" ]; then
    echo "WARN: Diff exceeds the 1MB limit, truncating output..." >&2
    output=$(echo "$output" | head -c $1000000)
fi

delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')

# Remove ANSI color codes
output=$(echo "$output" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g")

echo "changelog<<$delimiter" >>$GITHUB_OUTPUT
if [ -n "$output" ]; then
    echo "$output" >>$GITHUB_OUTPUT
else
    echo "No changes in the OpenAPI spec" >>$GITHUB_OUTPUT
fi
echo "$delimiter" >>$GITHUB_OUTPUT

echo '```' >>$GITHUB_STEP_SUMMARY
if [ -n "$output" ]; then
    echo "$output" >>$GITHUB_STEP_SUMMARY
else
    echo "No changes in the OpenAPI spec" >>$GITHUB_STEP_SUMMARY
fi
echo '```' >>$GITHUB_STEP_SUMMARY
