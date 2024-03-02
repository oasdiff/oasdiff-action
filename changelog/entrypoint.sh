#!/bin/sh
set -e

source $GITHUB_WORKSPACE/common/common.sh

readonly base="$1"
readonly revision="$2"
readonly include_path_params="$3"
readonly exclude_elements="$4"
readonly output_to_file="$5"

echo "running oasdiff changelog base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements"

# Build flags to pass in command
flags=""
if [ "$include_path_params" = "true" ]; then
    flags="$flags --include-path-params"
fi
if [ -n "$exclude_elements" ]; then
    flags="$flags --exclude-elements $exclude_elements"
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
echo "changelog<<$delimiter" >>"$GITHUB_OUTPUT"

if [ -n "$flags" ]; then
    output=$(oasdiff changelog "$base" "$revision" $flags)
else
    output=$(oasdiff changelog "$base" "$revision")
fi

if [ -n "$output" ]; then
    write_output "$output"
else
    write_output "No changelog changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"

# *** github action step output ***

