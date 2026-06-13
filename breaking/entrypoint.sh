#!/bin/sh
set -e

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

readonly base="$1"
readonly revision="$2"
readonly fail_on="$3"
readonly include_checks="$4"
readonly include_path_params="$5"
readonly deprecation_days_beta="$6"
readonly deprecation_days_stable="$7"
readonly exclude_elements="$8"
readonly filter_extension="$9"
readonly composed="${10}"
readonly flatten_allof="${11}"
readonly err_ignore="${12}"
readonly warn_ignore="${13}"
readonly output_to_file="${14}"
readonly allow_external_refs="${15}"
readonly review="${16}"
readonly github_token="${17}"

# post_review_comment posts (or updates) a single pull-request comment with the
# free side-by-side review link, so reviewers see it on the PR rather than only
# in the job summary (a low-traffic page most users never open). Best-effort and
# never fatal: it needs a github-token with pull-requests:write and a
# pull_request event. On fork pull requests GITHUB_TOKEN is read-only, so the
# API call returns 403 and we fall back to the job summary, which is always
# written regardless.
#
# $1: the review URL, or empty to mark the PR as having no breaking changes
#     (in that case it only updates an existing comment, never creates one, so
#     a PR that never had changes stays comment-free).
post_review_comment () {
    review_url="$1"
    [ -z "$github_token" ] && return 0
    pr_number=$(echo "$GITHUB_REF" | sed -n 's|refs/pull/\([0-9]*\)/merge|\1|p')
    [ -z "$pr_number" ] && return 0
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY#*/}"
    api="${GITHUB_API_URL:-https://api.github.com}"
    marker="<!-- oasdiff-free-review -->"

    # Find an existing oasdiff comment to update so we don't post a fresh
    # comment on every push.
    existing_id=$(curl -s \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github+json" \
        "${api}/repos/${owner}/${repo}/issues/${pr_number}/comments?per_page=100" 2>/dev/null \
        | jq -r --arg m "$marker" 'map(select(.body | contains($m))) | .[0].id // empty' 2>/dev/null) || existing_id=""

    if [ -n "$review_url" ]; then
        body="${marker}
### 📋 [View the side-by-side API change review](${review_url})

See exactly what changed, in context. Share this link with your team: anyone can open the review, no install and no account needed. It expires in 7 days.

🔒 Your specs stay private. They're encrypted before upload, and only this link can unlock them. [How it works →](https://www.oasdiff.com/docs/free-review#privacy)"
    elif [ -n "$existing_id" ]; then
        body="${marker}
### ✅ No breaking changes in the latest revision."
    else
        return 0
    fi

    payload=$(jq -n --arg body "$body" '{body: $body}')
    if [ -n "$existing_id" ]; then
        endpoint="${api}/repos/${owner}/${repo}/issues/comments/${existing_id}"
        method="PATCH"
    else
        endpoint="${api}/repos/${owner}/${repo}/issues/${pr_number}/comments"
        method="POST"
    fi

    code=$(printf '%s' "$payload" | curl -s -o /dev/null -w "%{http_code}" -X "$method" \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github+json" \
        "$endpoint" --data-binary @- 2>/dev/null) || code="000"

    if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        echo "oasdiff: posted the side-by-side review link as a PR comment."
    else
        echo "::notice::oasdiff: couldn't post the review link as a PR comment (HTTP ${code}). On fork pull requests the token is read-only; otherwise grant 'permissions: pull-requests: write'. The link is still in the job summary."
    fi
}

write_output () {
    local output="$1"
    if [ -n "$output_to_file" ]; then
        local file_output="$2"
        if [ -z "$file_output" ]; then
            file_output=$output
        fi
        echo "$file_output" >> "$output_to_file"
    fi
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    size=$(echo "$output" | wc -c)
    if [ "$size" -ge "1000000" ]; then
        echo "WARN: diff exceeds the 1MB limit, truncating output..." >&2
        output=$(echo "$output" | head -c 1000000)
    fi
    echo "$output" >>"$GITHUB_OUTPUT"
}

echo "running oasdiff breaking... base: $base, revision: $revision, fail_on: $fail_on, include_checks: $include_checks, include_path_params: $include_path_params, deprecation_days_beta: $deprecation_days_beta, deprecation_days_stable: $deprecation_days_stable, exclude_elements: $exclude_elements, filter_extension: $filter_extension, composed: $composed, flatten_allof: $flatten_allof, err_ignore: $err_ignore, warn_ignore: $warn_ignore, output_to_file: $output_to_file"

# Build flags to pass in command
flags=""
# allow-external-refs defaults to false (safe for CI on untrusted PRs); pass
# whatever the input resolved to so the explicit action input is authoritative.
if [ -n "$allow_external_refs" ]; then
    flags="$flags --allow-external-refs=$allow_external_refs"
fi
if [ "$include_path_params" = "true" ]; then
    flags="$flags --include-path-params"
fi
if [ -n "$include_checks" ]; then
    flags="$flags --include-checks $include_checks"
fi
if [ -n "$deprecation_days_beta" ]; then
    flags="$flags --deprecation-days-beta $deprecation_days_beta"
fi
if [ -n "$deprecation_days_stable" ]; then
    flags="$flags --deprecation-days-stable $deprecation_days_stable"
fi
if [ -n "$exclude_elements" ]; then
    flags="$flags --exclude-elements $exclude_elements"
fi
if [ -n "$filter_extension" ]; then
    flags="$flags --filter-extension $filter_extension"
fi
if [ "$composed" = "true" ]; then
    flags="$flags -c"
fi
if [ "$flatten_allof" = "true" ]; then
    flags="$flags --flatten-allof"
fi
if [ -n "$err_ignore" ]; then
    flags="$flags --err-ignore $err_ignore"
fi
if [ -n "$warn_ignore" ]; then
    flags="$flags --warn-ignore $warn_ignore"
fi
echo "flags: $flags"

# Run 1: capture the default-format report and the exit code, applying
# --fail-on if the input requested it. Tolerate non-zero exit so we can
# still render the report and write GITHUB_OUTPUT below — the caller's
# fail-on (whether from the input or from oasdiff.yaml) is preserved
# via $exit_code at the end.
fail_on_flag=""
if [ -n "$fail_on" ]; then
    fail_on_flag="--fail-on $fail_on"
fi
exit_code=0
_err=$(mktemp)
breaking_changes=$(oasdiff breaking "$base" "$revision" $flags $fail_on_flag 2>"$_err") || exit_code=$?
[ -s "$_err" ] && cat "$_err" >&2
# Promote a genuine oasdiff failure to a Checks-tab annotation. Exit 0 is
# success and exit 1 is the intended "breaking changes found" / fail-on result;
# only codes >=2 (load/parse/etc.) are real errors worth surfacing here.
if [ "$exit_code" -ge 2 ] && [ -s "$_err" ]; then
    echo "::error::$(tr '\n' ' ' < "$_err")"
fi
# Exit code 123 = oasdiff refused a disallowed external $ref (stable contract,
# not message text). Surface the action-specific remedy.
if [ "$exit_code" -eq 123 ]; then
    echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
fi
rm -f "$_err"

# Run 2: render annotations to stdout via --format githubactions so
# GitHub parses them onto the PR's "Files changed" tab. Tolerate
# non-zero exit (could be triggered by oasdiff.yaml fail-on); the
# authoritative exit code is from Run 1.
oasdiff breaking "$base" "$revision" $flags --format githubactions || true

# *** GitHub Action step output ***

# Output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "breaking<<$delimiter" >>"$GITHUB_OUTPUT"

if [ -n "$breaking_changes" ] && ! echo "$breaking_changes" | head -n 1 | grep -q "^No "; then
    write_output "$(echo "$breaking_changes" | head -n 1)" "$breaking_changes"

    free_review_url=""
    # review (default true): upload the comparison to oasdiff.com and link
    # straight to the rendered side-by-side review. The upload is
    # zero-knowledge -- the oasdiff binary encrypts the two specs client-side
    # and the decryption key lives only in the URL #fragment, so the server
    # stores a blob it cannot read. Set review: false to skip the upload
    # entirely, so no spec ever leaves CI; the breaking-change detection and
    # the inline annotations are unaffected either way.
    if [ "$review" != "false" ]; then
        # Reuse the same semantic flags as the diff above so the uploaded
        # comparison matches. --open prints the review URL on stdout; in CI the
        # browser-open step soft-fails. We grep the /review/e/ URL out by its
        # stable path shape (not by surrounding prose). Tolerate a non-zero
        # exit / no match so `set -e` doesn't abort the run.
        free_review_url=$(oasdiff breaking "$base" "$revision" $flags --open 2>/dev/null \
            | grep -oE 'https://[^[:space:]]+/review/e/[^[:space:]]+' | head -n 1) || true
        if [ -n "$free_review_url" ]; then
            echo "### 📋 [View these breaking changes in a side-by-side review](${free_review_url})" >> "$GITHUB_STEP_SUMMARY"
            # Also surface the link on the PR itself (best-effort) so reviewers
            # don't have to find the job summary.
            post_review_comment "$free_review_url"
        else
            # review was requested but no link came back: an offline runner,
            # oasdiff.com unreachable, or an older oasdiff in the base image.
            # Warn rather than emit a link -- there's no useful local fallback
            # (if the upload failed because the host is unreachable, a manual
            # run would fail the same way), and the report above still stands.
            echo "::warning::oasdiff: couldn't upload the side-by-side review (the breaking-change report still ran). Re-run the job, or set 'review: false' to skip the upload."
        fi
    fi
else
    write_output "No breaking changes"
    # Keep an existing review comment honest when a later push fixes the
    # breaking changes; never create one for an always-clean PR.
    if [ "$review" != "false" ]; then
        post_review_comment ""
    fi
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"
# review_url is a single-line output, written after the multiline `breaking`
# block is closed so it doesn't get folded into that value. Empty when there
# are no breaking changes (the notice/URL only fire then).
echo "review_url=${free_review_url:-}" >> "$GITHUB_OUTPUT"

exit $exit_code
