#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"

echo "running oasdiff check for breaking-changes... base: $base, revision: $revision, fail_on_diff: $fail_on_diff"

if [ "$fail_on_diff" = "true"  ]
then
  oasdiff -check-breaking -fail-on-diff -base "$base" -revision "$revision"
else
  oasdiff -check-breaking -base "$base" -revision "$revision"
fi
