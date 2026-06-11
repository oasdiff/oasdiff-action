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
readonly service_url="${8:-https://api.oasdiff.com}"
readonly allow_external_refs="${9}"

echo "running oasdiff pr-comment base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements, composed: $composed"

# Build flags
flags=""
# allow-external-refs defaults to false (safe for CI on untrusted PRs); pass
# whatever the input resolved to so the explicit action input is authoritative.
if [ -n "$allow_external_refs" ]; then
    flags="$flags --allow-external-refs=$allow_external_refs"
fi
if [ "$include_path_params" = "true" ]; then
    flags="$flags --include-path-params"
fi
if [ -n "$exclude_elements" ]; then
    flags="$flags --exclude-elements $exclude_elements"
fi
if [ "$composed" = "true" ]; then
    flags="$flags -c"
fi

# Run oasdiff changelog with JSON output. Tolerate a non-zero exit so
# fail-on settings in oasdiff.yaml don't abort the script before we get
# the chance to post the PR comment — fail-on's job is to gate the
# workflow on the *result*, which the service determines, not to block
# us from collecting the JSON. Real failures (missing file, parse error)
# still abort because they leave $changelog empty.
oasdiff_exit=0
_err=$(mktemp)
changelog=$(oasdiff changelog "$base" "$revision" --format json $flags 2>"$_err") || oasdiff_exit=$?
if [ "$oasdiff_exit" -ne 0 ] && [ -z "$changelog" ]; then
    [ -s "$_err" ] && cat "$_err" >&2
    # Promote a genuine failure to a Checks-tab annotation. Exit 1 is the
    # intended fail-on result (not an error); only codes >=2 are real errors.
    if [ "$oasdiff_exit" -ge 2 ] && [ -s "$_err" ]; then
        echo "::error::$(tr '\n' ' ' < "$_err")"
    fi
    # Exit code 123 = oasdiff refused a disallowed external $ref (stable
    # contract, not message text). Surface the action-specific remedy.
    if [ "$oasdiff_exit" -eq 123 ]; then
        echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
    fi
    rm -f "$_err"
    echo "ERROR: oasdiff exited $oasdiff_exit with no output" >&2
    exit $oasdiff_exit
fi
rm -f "$_err"

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

# Use the PR head SHA (not GITHUB_SHA which is the merge commit on pull_request events)
head_sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")
if [ -z "$head_sha" ]; then
    head_sha="$GITHUB_SHA"
fi

# Capture the PR base SHA (the commit the PR is opened against). Pinning to
# the SHA gives the review page a stable base reference: if the base branch
# advances after the PR was opened, the review still shows the comparison
# against the original base. base_ref is still sent for backward compatibility
# with reports that don't yet have base_sha.
base_sha=$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH")

# Extract owner and repo from GITHUB_REPOSITORY
owner="${GITHUB_REPOSITORY%%/*}"
repo="${GITHUB_REPOSITORY#*/}"

# Build the JSON payload. The `changes` array can be very large for
# complex specs (one real-world report was observed at thousands of
# entries running into the megabytes), so it's piped via stdin rather
# than passed as a `--argjson` value. `--argjson` would put the entire
# JSON string on jq's command line, exceeding the OS argument-length
# limit (ARG_MAX, typically 128KB to 2MB depending on the kernel),
# which surfaces as a confusing "jq: Argument list too long" error
# that aborts the action right before the POST to oasdiff-service.
# `printf` is a shell builtin in POSIX sh / busybox ash so its
# arguments don't go through execve and aren't subject to ARG_MAX.
payload=$(printf '%s' "$changes" | jq \
    --arg token "$github_token" \
    --arg owner "$owner" \
    --arg repo "$repo" \
    --argjson pr "$pr_number" \
    --arg sha "$head_sha" \
    --arg base_ref "$GITHUB_BASE_REF" \
    --arg base_sha "$base_sha" \
    --arg base_file "$base" \
    --arg rev_file "$revision" \
    '{github: {token: $token, owner: $owner, repo: $repo, pull_number: $pr, head_sha: $sha, base_ref: $base_ref, base_sha: $base_sha}, base_file: $base_file, rev_file: $rev_file, changes: .}')

# POST to oasdiff-service (requires token)
if [ -z "$oasdiff_token" ]; then
    echo "No oasdiff-token provided — skipping PR comment. Sign up at https://oasdiff.com to get a token."
    exit 0
fi

# POST the payload via stdin (`--data-binary @-`) rather than as a
# `-d` argv value. For specs whose changelog runs into the multi-MB
# range the assembled payload is also multi-MB; passing it via argv
# would exceed ARG_MAX and surface as `curl: Argument list too long`,
# aborting the action exactly like the analogous jq case did at line
# 89 before the previous fix. `printf` is a shell builtin so the
# variable never goes through execve.
response=$(printf '%s' "$payload" | curl -s -w "\n%{http_code}" -X POST \
    "${service_url}/tenants/${oasdiff_token}/pr-comment" \
    -H "Content-Type: application/json" \
    -H "User-Agent: oasdiff-action/${GITHUB_ACTION_REF:-unknown}" \
    --data-binary @-)

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    comment_url=$(echo "$body" | jq -r '.comment_url // empty')
    report_url=$(echo "$body" | jq -r '.report_url // empty')
    echo "PR comment posted: $comment_url"
    if [ -n "$report_url" ]; then
        echo "Review page: $report_url"
    fi
elif [ "$http_code" = "409" ] && [ "$(echo "$body" | jq -r '.code // empty' 2>/dev/null)" = "github_app_not_installed" ]; then
    # The service returns 409 with a structured JSON body when the customer's
    # repo does not have the oasdiff GitHub App installed. Surface a clear,
    # actionable error to the workflow log and step summary.
    err_owner=$(echo "$body" | jq -r '.owner')
    err_repo=$(echo "$body" | jq -r '.repo')
    install_url=$(echo "$body" | jq -r '.install_url')
    echo "::error title=oasdiff GitHub App not installed::Install the App at ${install_url} on ${err_owner}/${err_repo} and re-run this workflow."
    {
        echo "### ❌ oasdiff GitHub App not installed"
        echo ""
        echo "The oasdiff GitHub App is not installed on **${err_owner}/${err_repo}**, so this workflow cannot post a PR comment or set commit statuses."
        echo ""
        echo "**Fix:**"
        echo ""
        echo "1. Visit [${install_url}](${install_url})"
        echo "2. Click **Install** and select the \`${err_owner}/${err_repo}\` repository"
        echo "3. Re-run this workflow"
    } >> "$GITHUB_STEP_SUMMARY"
    exit 1
elif [ "$http_code" = "402" ] && [ "$(echo "$body" | jq -r '.code // empty' 2>/dev/null)" = "repo_limit_reached" ]; then
    # The service returns 402 with a structured JSON body when this PR's
    # repository is beyond the tenant's plan limit. This is a billing signal,
    # not a failure, so surface a clear annotation + step summary with the
    # upgrade link but do NOT fail the workflow (exit 0): a plan limit should
    # not break the customer's merge gate. Change the exit below to 1 if you
    # would rather hard-gate repositories beyond the plan.
    err_owner=$(echo "$body" | jq -r '.owner')
    err_repo=$(echo "$body" | jq -r '.repo')
    max_repos=$(echo "$body" | jq -r '.max_repos')
    upgrade_url=$(echo "$body" | jq -r '.upgrade_url')
    echo "::warning title=oasdiff plan limit reached::${err_owner}/${err_repo} is beyond your plan's ${max_repos}-repository limit, so no review comment was posted. Upgrade at ${upgrade_url} to add it."
    {
        echo "### ⚠️ oasdiff plan limit reached"
        echo ""
        echo "Your oasdiff plan covers **${max_repos} repositories**. **${err_owner}/${err_repo}** is beyond that limit, so no review comment was posted for this pull request."
        echo ""
        echo "**To cover this repository:** [upgrade your plan](${upgrade_url})."
        echo ""
        echo "_Repositories already counted toward your plan are unaffected._"
    } >> "$GITHUB_STEP_SUMMARY"
    exit 0
else
    echo "ERROR: oasdiff-service returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi
