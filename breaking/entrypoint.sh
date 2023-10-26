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
    output=$(unbuffer oasdiff breaking "$base" "$revision" $flags)
else
    output=$(unbuffer oasdiff breaking "$base" "$revision")
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

echo "breaking<<$delimiter" >>$GITHUB_OUTPUT
if [ -n "$output" ]; then
    echo "$output" >>$GITHUB_OUTPUT
else
    echo "No breaking changes" >>$GITHUB_OUTPUT
fi
echo "$delimiter" >>$GITHUB_OUTPUT

echo '```' >>$GITHUB_STEP_SUMMARY
if [ -n "$output" ]; then
    echo "$output" >>$GITHUB_STEP_SUMMARY
else
    echo "No breaking changes" >>$GITHUB_STEP_SUMMARY
fi
echo '```' >>$GITHUB_STEP_SUMMARY
