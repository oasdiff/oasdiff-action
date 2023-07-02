#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"

echo "running oasdiff changelog base: $base, revision: $revision"

set -o pipefail

oasdiff changelog "$base" "$revision"
