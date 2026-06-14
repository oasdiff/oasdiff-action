#!/bin/sh
set -e

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

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

readonly base="$1"
readonly revision="$2"
readonly include_path_params="$3"
readonly exclude_elements="$4"
readonly filter_extension="$5"
readonly composed="$6"
readonly flatten_allof="$7"
readonly output_to_file="$8"
readonly prefix_base="$9"
readonly prefix_revision="${10}"
readonly case_insensitive_headers="${11}"
readonly format="${12}"
readonly template="${13}"
readonly level="${14}"
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
# $1: the review URL, or empty to mark the PR as having no changes (in that case
#     it only updates an existing comment, never creates one, so a PR that never
#     had changes stays comment-free).
post_review_comment () {
    review_url="$1"
    pr_number=$(echo "$GITHUB_REF" | sed -n 's|refs/pull/\([0-9]*\)/merge|\1|p')
    if [ -z "$github_token" ]; then
        # No token to comment with. If we produced a review link on a PR, nudge
        # the user to enable the PR comment rather than failing silently (the
        # link is still in the job summary). This is the default for anyone who
        # upgraded the action version without adding github-token + permissions.
        if [ -n "$review_url" ] && [ -n "$pr_number" ]; then
            echo "::notice::oasdiff put the side-by-side review link in the job summary. To post it as a pull-request comment instead, pass 'github-token: \${{ github.token }}' to the action and grant the job 'permissions: pull-requests: write'. See https://www.oasdiff.com/docs/github-action"
        fi
        return 0
    fi
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
### ✅ No API changes in the latest revision."
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

echo "running oasdiff changelog base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements, filter_extension: $filter_extension, composed: $composed, flatten_allof: $flatten_allof, output_to_file: $output_to_file, prefix_base: $prefix_base, prefix_revision: $prefix_revision, case_insensitive_headers: $case_insensitive_headers, format: $format, template: $template, level: $level"

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
if [ -n "$prefix_base" ]; then
    flags="$flags --prefix-base $prefix_base"
fi
if [ -n "$prefix_revision" ]; then
    flags="$flags --prefix-revision $prefix_revision"
fi
if [ "$case_insensitive_headers" = "true" ]; then
    flags="$flags --case-insensitive-headers"
fi
if [ -n "$level" ]; then
    flags="$flags --level $level"
fi
# format and template are presentation-only. Keep them out of $flags so the
# json change-probe and the --open upload below run on the semantic flags only:
# the probe must render as json regardless of the user's format, and --template
# is rejected for json (it would error both). $fmt_flags is applied only to the
# user-facing changelog render.
fmt_flags=""
if [ -n "$format" ]; then
    fmt_flags="$fmt_flags --format $format"
fi
if [ -n "$template" ]; then
    fmt_flags="$fmt_flags --template $template"
fi
echo "flags: $flags, presentation flags: $fmt_flags"

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "changelog<<$delimiter" >>"$GITHUB_OUTPUT"

exit_code=0
_err=$(mktemp)
output=$(oasdiff changelog "$base" "$revision" $flags $fmt_flags 2>"$_err") || exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    [ -s "$_err" ] && cat "$_err" >&2
    # Promote a genuine failure to a Checks-tab annotation. Exit 1 is the
    # intended fail-on result (not an error); only codes >=2 are real errors.
    if [ "$exit_code" -ge 2 ] && [ -s "$_err" ]; then
        echo "::error::$(tr '\n' ' ' < "$_err")"
    fi
    # Exit code 123 = oasdiff refused a disallowed external $ref (stable
    # contract, not message text). Surface the action-specific remedy.
    if [ "$exit_code" -eq 123 ]; then
        echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
    fi
    rm -f "$_err"
    exit "$exit_code"
fi
rm -f "$_err"

# Decide whether there are changes independently of --format. The user-facing
# $output may be json/yaml ("[]") or markup (a header line then "No changes
# detected"), none of which the old first-line "^No " test caught, so a
# non-default format spammed clean PRs with a review link. A json render is
# unambiguous: an empty changelog is "[]". Probe with the semantic flags only
# (level included, so detection matches what the user sees). The probe is a
# local diff identical to the run above, so it fails only when that run would.
changes_json=$(oasdiff changelog "$base" "$revision" $flags --format json 2>/dev/null | tr -d '[:space:]') || changes_json=""
if [ -n "$changes_json" ] && [ "$changes_json" != "[]" ]; then
    write_output "$output"

    free_review_url=""
    # review (default true): upload the comparison to oasdiff.com and link
    # straight to the rendered side-by-side review. The upload is
    # zero-knowledge -- the oasdiff binary encrypts the two specs client-side
    # and the decryption key lives only in the URL #fragment, so the server
    # stores a blob it cannot read. Set review: false to skip the upload
    # entirely, so no spec ever leaves CI; the changelog output and the inline
    # annotations are unaffected either way.
    if [ "$review" != "false" ]; then
        if [ "$composed" = "true" ]; then
            # Composed mode (-c) diffs globs of many files; the side-by-side
            # review represents exactly two specs, so --open can't build it.
            # Say so once instead of running --open only to hit the generic
            # "couldn't upload" warning below.
            echo "::notice::oasdiff: the side-by-side review isn't available in composed mode (-c). The changelog above is unaffected."
        else
            # Reuse the same semantic flags as the diff above so the uploaded
            # comparison matches. --open prints the review URL on stdout; in CI
            # the browser-open step soft-fails. We grep the /review/e/ URL out by
            # its stable path shape (not by surrounding prose). Tolerate a
            # non-zero exit / no match so `set -e` doesn't abort the run.
            free_review_url=$(oasdiff changelog "$base" "$revision" $flags --open 2>/dev/null \
                | grep -oE 'https://[^[:space:]]+/review/e/[^[:space:]]+' | head -n 1) || true
            if [ -n "$free_review_url" ]; then
                echo "### 📋 [View these API changes in a side-by-side review](${free_review_url})" >> "$GITHUB_STEP_SUMMARY"
                # Also surface the link on the PR itself (best-effort) so
                # reviewers don't have to find the job summary.
                post_review_comment "$free_review_url"
            else
                # review was requested but no link came back: an offline runner,
                # oasdiff.com unreachable, or an older oasdiff in the base image.
                # Warn rather than emit a link -- there's no useful local
                # fallback (if the upload failed because the host is unreachable,
                # a manual run would fail the same way), and the changelog above
                # still stands.
                echo "::warning::oasdiff: couldn't upload the side-by-side review (the changelog still ran). Re-run the job, or set 'review: false' to skip the upload."
            fi
        fi
    fi
else
    write_output "No changelog changes"
    # Keep an existing review comment honest when a later push removes all
    # changes; never create one for an always-clean PR.
    if [ "$review" != "false" ]; then
        post_review_comment ""
    fi
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"
# review_url is a single-line output, written after the multiline `changelog`
# block is closed so it doesn't get folded into that value. Empty when there
# are no changes (the notice/URL only fire then).
echo "review_url=${free_review_url:-}" >> "$GITHUB_OUTPUT"

# *** github action step output ***

