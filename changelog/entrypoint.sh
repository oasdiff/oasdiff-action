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

if [ -n "$flags" ]; then
    oasdiff changelog "$base" "$revision" $flags
else
    oasdiff changelog "$base" "$revision"
fi
