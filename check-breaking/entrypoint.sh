#!/bin/bash

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"
readonly include_checks="$4"

echo "running oasdiff breaking base: $base, revision: $revision, fail_on_diff: $fail_on_diff, include_checks: $include_checks"

set -o pipefail

# Build flags to pass in command
flags=""
if [[ $fail_on_diff = "true" ]]; then
  flags+="--fail-on WARN "
fi

if [[ -n $include_checks ]]; then
  flags+="--include-checks $include_checks "
fi
echo "flags: $flags"

# Run command
if [[ -n $flags ]]; then
  oasdiff breaking "$base" "$revision" $flags
else
  oasdiff breaking "$base" "$revision"
fi
