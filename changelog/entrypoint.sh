#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly include_path_params="$3"
readonly exclude_elements="$4"

echo "running oasdiff changelog base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements"

# Build flags to pass in command
flags=""
if [ "$include_path_params" = "true" ]; then
    flags="${flags} --include-path-params"
fi
if [ "$exclude_elements" != "" ]; then
    flags="${flags} --exclude-elements ${exclude_elements}"
fi
echo "flags: $flags"

set -o pipefail

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "changelog<<$delimiter" >>$GITHUB_OUTPUT

set +e
if [ -n "$flags" ]; then
    output=$(oasdiff changelog "$base" "$revision" $flags 2>&1)
else
    output=$(oasdiff changelog "$base" "$revision" 2>&1)
fi
set -e

if [[ "$output" == Error* ]]; then
    echo "$output"
    exit 1
fi

if [ -n "$output" ]; then
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    size=$(echo "$output" | wc -c)
    if [ "$size" -ge "1000000" ]; then
        echo "WARN: changelog exceeds the 1MB limit, truncating output..." >&2
        output=$(echo "$output" | head -c 1000000)
    fi
    echo "$output" >>$GITHUB_OUTPUT
else
    echo "No changelog changes" >>$GITHUB_OUTPUT
fi

echo "$delimiter" >>$GITHUB_OUTPUT

# *** github action step output ***

