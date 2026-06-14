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
# Pin composed to the action input so a 'composed' setting in .oasdiff.yaml can't
# desync oasdiff's mode from the action's logic (the --open guard and flag
# building both key off this input). A cmd-line flag overrides config.
flags="$flags --composed=$composed"
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
# authoritative exit code is from Run 1. --template= overrides a 'template'
# set in .oasdiff.yaml, which is rejected for the githubactions format and
# would (via || true) silently suppress the annotations.
oasdiff breaking "$base" "$revision" $flags --format githubactions --template= || true

# *** GitHub Action step output ***

# Output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "breaking<<$delimiter" >>"$GITHUB_OUTPUT"

# Whether there are breaking changes is read off oasdiff's exit code with
# --fail-on=WARN (breaking renders WARN-and-above, and WARN is the lowest level
# it accepts for fail-on): exit 1 means at least one breaking change, 0 means
# none. This is format-proof; parsing $breaking_changes is not, because its shape
# follows any 'format' set in .oasdiff.yaml (e.g. json renders "[]", not "No ...").
# The explicit --fail-on overrides a config fail-on for this probe only; Run 1's
# authoritative gate exit code is untouched.
changes_exit=0
oasdiff breaking "$base" "$revision" $flags --fail-on=WARN --template= >/dev/null 2>&1 || changes_exit=$?
if [ "$changes_exit" -eq 1 ]; then
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
        if [ "$composed" = "true" ]; then
            # Composed mode (-c) diffs globs of many files; the side-by-side
            # review represents exactly two specs, so --open can't build it.
            # Say so once instead of running --open only to hit the generic
            # "couldn't upload" warning below.
            echo "::notice::oasdiff: the side-by-side review isn't available in composed mode (-c). The breaking-change report above is unaffected."
        else
            # --open prints the review URL to stderr (oasdiff >= v1.19.1 moved it
            # off stdout so it can't corrupt piped --format output); in CI the
            # browser-open step soft-fails. Merge stderr into the pipe (2>&1) and
            # grep the /review/e/ URL out by its stable path shape (not by
            # surrounding prose). Tolerate a non-zero exit / no match so `set -e`
            # doesn't abort the run. --template= overrides a 'template' set in
            # .oasdiff.yaml, which would otherwise error this render (templates
            # are rejected for the default text format) and yield no URL.
            free_review_url=$(oasdiff breaking "$base" "$revision" $flags --open --template= 2>&1 \
                | grep -oE 'https://[^[:space:]]+/review/e/[^[:space:]]+' | head -n 1) || true
            if [ -n "$free_review_url" ]; then
                echo "### 📋 [View these breaking changes in a side-by-side review](${free_review_url})" >> "$GITHUB_STEP_SUMMARY"
                # Also surface the link on the PR itself (best-effort) so
                # reviewers don't have to find the job summary.
                post_review_comment "$free_review_url"
            else
                # review was requested but no link came back: an offline runner,
                # oasdiff.com unreachable, or an older oasdiff in the base image.
                # Warn rather than emit a link -- there's no useful local
                # fallback (if the upload failed because the host is unreachable,
                # a manual run would fail the same way), and the report above
                # still stands.
                echo "::warning::oasdiff: couldn't upload the side-by-side review (the breaking-change report still ran). Re-run the job, or set 'review: false' to skip the upload."
            fi
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
