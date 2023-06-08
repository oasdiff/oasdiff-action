#!/bin/sh

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"

echo "running oasdiff check for breaking-changes... base: $base, revision: $revision, fail_on_diff: $fail_on_diff"
oasdiff -check-breaking -fail-on-diff -base "$base" -revision "$revision"
if [ $? != 0 ] && [ "$fail_on_diff" = "true"  ]; then
  exit 1
fi
