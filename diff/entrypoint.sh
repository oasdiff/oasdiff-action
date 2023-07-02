#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly format="$3"
readonly fail_on_diff="$4"

echo "running oasdiff... base: $base, revision: $revision, format: $format, fail_on_diff: $fail_on_diff"

set -o pipefail

if [[ $fail_on_diff" == "true" ]]; then
  oasdiff diff "$base" "$revision" --fail-on-diff --format "$format" 
else
  oasdiff diff "$base" "$revision" --format "$format"
fi
