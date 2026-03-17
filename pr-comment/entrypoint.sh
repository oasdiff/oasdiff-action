#!/bin/sh
set -e

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

readonly base="$1"
readonly revision="$2"
readonly include_path_params="$3"
readonly exclude_elements="$4"
readonly composed="$5"
readonly oasdiff_token="$6"
readonly github_token="$7"

echo "running oasdiff pr-comment base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements, composed: $composed"

# Build flags
flags=""
if [ "$include_path_params" = "true" ]; then
    flags="$flags --include-path-params"
fi
if [ -n "$exclude_elements" ]; then
    flags="$flags --exclude-elements $exclude_elements"
fi
if [ "$composed" = "true" ]; then
    flags="$flags -c"
fi

# Run oasdiff changelog with JSON output
if [ -n "$flags" ]; then
    changelog=$(oasdiff changelog "$base" "$revision" --format json $flags)
else
    changelog=$(oasdiff changelog "$base" "$revision" --format json)
fi

# If no changes, use empty array
if [ -z "$changelog" ] || [ "$changelog" = "null" ] || [ "$changelog" = "[]" ]; then
    changes='[]'
else
    # oasdiff changelog --format json returns a raw array, not {"changes": [...]}
    changes=$(echo "$changelog" | jq -c 'if type == "array" then . else .changes // [] end')
fi

# Extract PR number from GITHUB_REF (refs/pull/{number}/merge)
pr_number=$(echo "$GITHUB_REF" | sed -n 's|refs/pull/\([0-9]*\)/merge|\1|p')
if [ -z "$pr_number" ]; then
    echo "ERROR: Could not extract PR number from GITHUB_REF=$GITHUB_REF" >&2
    echo "This action must be run on pull_request events." >&2
    exit 1
fi

# Extract owner and repo from GITHUB_REPOSITORY
owner="${GITHUB_REPOSITORY%%/*}"
repo="${GITHUB_REPOSITORY#*/}"

# Build the JSON payload
payload=$(jq -n \
    --arg token "$github_token" \
    --arg owner "$owner" \
    --arg repo "$repo" \
    --argjson pr "$pr_number" \
    --arg sha "$GITHUB_SHA" \
    --arg base_ref "$GITHUB_BASE_REF" \
    --arg base_file "$base" \
    --arg rev_file "$revision" \
    --argjson changes "$changes" \
    '{github: {token: $token, owner: $owner, repo: $repo, pull_number: $pr, head_sha: $sha, base_ref: $base_ref}, base_file: $base_file, rev_file: $rev_file, changes: $changes}')

# POST to oasdiff-service
response=$(curl -s -w "\n%{http_code}" -X POST \
    "https://api.oasdiff.com/tenants/${oasdiff_token}/pr-comment" \
    -H "Content-Type: application/json" \
    -d "$payload")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    comment_url=$(echo "$body" | jq -r '.comment_url // empty')
    report_url=$(echo "$body" | jq -r '.report_url // empty')
    echo "PR comment posted: $comment_url"
    if [ -n "$report_url" ]; then
        echo "Review page: $report_url"
    fi
else
    echo "ERROR: oasdiff-service returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi
