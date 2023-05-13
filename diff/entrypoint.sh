#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly format="$3"
readonly fail_on_diff="$4"

echo "running oasdiff... base: $base, revision: $revision, format: $format, fail_on_diff: $fail_on_diff"

if [ "$fail_on_diff" = "true"  ]
then
  oasdiff -fail-on-diff -format "$format" -base "$base" -revision "$revision"
else
  oasdiff -format "$format" -base "$base" -revision "$revision"
fi
