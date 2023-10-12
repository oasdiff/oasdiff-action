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
    oasdiff breaking "$base" "$revision" $flags
else
    oasdiff breaking "$base" "$revision"
fi
