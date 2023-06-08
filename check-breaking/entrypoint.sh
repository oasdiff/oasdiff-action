#!/bin/sh

readonly base="$1"
readonly revision="$2"
readonly fail_on_diff="$3"
readonly fail_on_warns="$4"

echo "running oasdiff check for breaking-changes... base: $base, revision: $revision, fail_on_diff: $fail_on_diff, fail_on_warns: $fail_on_warns"

readonly fail_on_warns_argument=$(if [ "$fail_on_warns" = "true" ]; then echo "-fail-on-warns"; fi)

oasdiff -check-breaking -fail-on-diff -base "$base" -revision "$revision" "$fail_on_warns_argument"
if [ $? != 0 ] && [ "$fail_on_diff" = "true"  ]; then
  exit 1
fi
