#!/bin/sh

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"

echo "running oasdiff check for breaking-changes... base: $base, revision: $revision, fail_on_diff: $fail_on_diff"

set -o pipefail

if [[ $fail_on_diff = "true" ]]; then
  oasdiff breaking "$base" "$revision" --fail-on WARN
else
  oasdiff breaking "$base" "$revision"
fi
