#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly format="$3"
readonly fail_on_diff="$4"
readonly include_path_params="$5"

echo "running oasdiff diff base: $base, revision: $revision, format: $format, fail_on_diff: $fail_on_diff, include_path_params: $include_path_params"

# Build flags to pass in command
flags=""
if [ "$format" != "yaml" ]; then
    flags="${flags} --format ${format}"
fi
if [ "$fail_on_diff" = "true" ]; then
    flags="${flags} --fail-on-diff"
fi
if [ "$include_path_params" = "true" ]; then
    flags="${flags} --include-path-params"
fi
echo "flags: $flags"

set -o pipefail

if [ -n "$flags" ]; then
    oasdiff diff "$base" "$revision" $flags
else
    oasdiff diff "$base" "$revision"
fi
