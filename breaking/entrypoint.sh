#!/bin/sh
set -e

# The implementation behind both the breaking and the changelog actions.
# breaking/action.yml and changelog/action.yml run this script and differ in
# OASDIFF_ACTION_COMMAND and in the inputs they declare.

if [ -n "$GITHUB_WORKSPACE" ]; then
  git config --global --get-all safe.directory | grep -q "$GITHUB_WORKSPACE" || \
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi

# input reads an action input. GitHub passes each one to a Docker action as an
# environment variable named INPUT_<NAME>: upper-cased, hyphens kept. A name
# with a hyphen is not a shell identifier, so it is read through printenv. An
# input the action does not declare reads as empty.
input () {
    printenv "INPUT_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" || true
}

readonly oasdiff_command="${OASDIFF_ACTION_COMMAND:?}"

base=$(input base)
revision=$(input revision)
fail_on=$(input fail-on)
include_checks=$(input include-checks)
include_path_params=$(input include-path-params)
deprecation_days_beta=$(input deprecation-days-beta)
deprecation_days_stable=$(input deprecation-days-stable)
exclude_elements=$(input exclude-elements)
filter_extension=$(input filter-extension)
composed=$(input composed)
flatten_allof=$(input flatten-allof)
err_ignore=$(input err-ignore)
warn_ignore=$(input warn-ignore)
output_to_file=$(input output-to-file)
prefix_base=$(input prefix-base)
prefix_revision=$(input prefix-revision)
case_insensitive_headers=$(input case-insensitive-headers)
format=$(input format)
template=$(input template)
level=$(input level)
allow_external_refs=$(input allow-external-refs)
review=$(input review)
github_token=$(input github-token)
oasdiff_token=$(input oasdiff-token)
config=$(input config)
readonly base revision fail_on include_checks include_path_params \
    deprecation_days_beta deprecation_days_stable exclude_elements \
    filter_extension composed flatten_allof err_ignore warn_ignore \
    output_to_file prefix_base prefix_revision case_insensitive_headers \
    format template level allow_external_refs review github_token oasdiff_token config

# What the PR comment calls the changes this command reports.
case "$oasdiff_command" in
    breaking)
        comment_icon="⚠️"
        change_noun="breaking change"
        no_changes_comment="No breaking changes in the latest revision."
        ;;
    changelog)
        comment_icon="📋"
        change_noun="API change"
        no_changes_comment="No API changes in the latest revision."
        ;;
    *)
        echo "::error::oasdiff: unknown command '$oasdiff_command'"
        exit 2
        ;;
esac
readonly comment_icon change_noun no_changes_comment

# from_fork reports whether this run is a pull request from a fork. GitHub makes
# GITHUB_TOKEN read-only there, so a comment cannot post however the job is
# configured, and the job summary is the only place the link can go.
from_fork () {
    [ -n "${GITHUB_EVENT_PATH:-}" ] || return 1
    [ -f "$GITHUB_EVENT_PATH" ] || return 1
    head_repo=$(jq -r '.pull_request.head.repo.full_name // empty' < "$GITHUB_EVENT_PATH" 2>/dev/null) || return 1
    [ -n "$head_repo" ] || return 1
    [ "$head_repo" != "${GITHUB_REPOSITORY:-}" ]
}

# review_comment_changes writes the changes themselves into the comment, so a
# reviewer reads what broke on the pull request instead of following a link to
# find out. Severest first, so the rows above the fold are the ones that decide
# whether the pull request can merge; $comment_rows_shown of them stay open and
# the rest collapse, up to $comment_rows_listed, since a changelog can run to
# thousands of changes and a GitHub comment is limited to 65,536 characters.
# $1: the json render of the comparison (Run 3).
comment_rows_shown=5
comment_rows_listed=50
review_comment_changes () {
    changes_file="$1"
    [ -s "$changes_file" ] || return 0

    jq -r --argjson shown "$comment_rows_shown" --argjson listed "$comment_rows_listed" '
        def severity: if . == 3 then "error" elif . == 2 then "warning" else "info" end;
        def endpoint:
            if (.operation // "") == "" then (.section // "") else .operation + " " + .path end;
        # Property names and paths come from the spec, which the author of a
        # pull request controls, so nothing in them may act as markdown: no
        # mention, link, image, or break out of the table. Every character
        # markdown reads becomes an entity, which GitHub prints literally.
        def inert:
            gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
            | gsub("@"; "&#64;") | gsub("\\["; "&#91;") | gsub("\\]"; "&#93;")
            | gsub("`"; "&#96;") | gsub("\\|"; "&#124;") | gsub("\\*"; "&#42;")
            | gsub("_"; "&#95;") | gsub("://"; ":&#47;&#47;") | gsub("www\\."; "www&#46;")
            | gsub("[\r\n]+"; " ");
        def row: "| " + (.level | severity) + " | " + ((.text // "") | inert)
            + " [`" + .id + "`](https://www.oasdiff.com/checks/" + .id + ") | <code>" + (endpoint | inert) + "</code> |";
        def header: "| severity | change | endpoint |", "| --- | --- | --- |";
        sort_by([-.level, (.path // ""), (.operation // ""), .id]) as $all
        | ($all | length) as $total
        | header,
          ($all[:$shown][] | row),
          (if $total > $shown then
              "",
              "<details><summary>\([$total, $listed] | min - $shown) more</summary>",
              "",
              header,
              ($all[$shown:$listed][] | row),
              "</details>"
           else empty end),
          (if $total > $listed then "", "\($total - $listed) more in the review." else empty end)
    ' < "$changes_file" 2>/dev/null || true
}

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
# report_review_delivery sends oasdiff.com one anonymous event saying whether
# the review link was posted as a PR comment, fell back to the job summary,
# or failed to post. This tells the maintainers how often users end up on the
# summary fallback, which is what drives fixes to the defaults. It carries no
# repo, organization, or user identity; action_ref is the action's own
# version tag. Best-effort with a 5 second cap, a failure never affects the
# run, and it is skipped when OASDIFF_INTERNAL=1 (the marker the CLI also
# uses for internal test runs).
report_review_delivery () {
    delivery_mode="$1"
    [ "${OASDIFF_INTERNAL:-}" = "1" ] && return 0
    printf '{"event":"review_delivery","props":{"mode":"%s","platform":"github-action","action_ref":"%s"}}'         "$delivery_mode" "${GITHUB_ACTION_REF:-unknown}"         | curl -s -m 5 -o /dev/null -X POST -H "Content-Type: application/json"             "https://www.oasdiff.com/api/telemetry" --data-binary @- 2>/dev/null || true
}

post_review_comment () {
    review_url="$1"
    pr_number=$(echo "$GITHUB_REF" | sed -n 's|refs/pull/\([0-9]*\)/merge|\1|p')
    if [ -z "$github_token" ]; then
        # No token to comment with. If we produced a review link on a PR, nudge
        # the user to enable the PR comment rather than failing silently (the
        # link is still in the job summary). This is the default for anyone who
        # upgraded the action version without adding github-token + permissions.
        if [ -n "$review_url" ] && [ -n "$pr_number" ]; then
            report_review_delivery "summary"
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
        if [ "${change_count:-0}" -eq 1 ]; then
            heading="1 ${change_noun} in this pull request"
        else
            heading="${change_count:-0} ${change_noun}s in this pull request"
        fi
        body="${marker}
### ${comment_icon} ${heading}

$(review_comment_changes "${changes_json:-}")

[See them side by side, with the old and new spec](${review_url}) (the link expires in 7 days)

🔒 Your API specs are encrypted in CI before they're uploaded. The decryption key stays in this link's URL fragment (after the #), which browsers never send to a server, so oasdiff cannot read your specs. [How it works →](https://www.oasdiff.com/docs/free-review#privacy)

<sub>Posted automatically by the [oasdiff GitHub Action](https://www.oasdiff.com/docs/free-review#github-action). To approve or reject each change here, with a commit status that holds the merge until the team signs off, see [oasdiff Pro](https://www.oasdiff.com/pricing). To turn this comment off (no spec upload, no comment), set \`review: false\` on the action.</sub>"
    elif [ -n "$existing_id" ]; then
        body="${marker}
### ✅ ${no_changes_comment}"
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
        [ -n "$review_url" ] && report_review_delivery "comment"
        echo "oasdiff: posted the side-by-side review link as a PR comment."
    elif from_fork; then
        # Expected, not a misconfiguration: report it apart from the failures
        # the user can act on, and say it plainly rather than as a warning.
        [ -n "$review_url" ] && report_review_delivery "comment_fork"
        echo "oasdiff: this pull request comes from a fork, where GitHub makes the token read-only, so the review link is in the job summary instead of a comment."
    else
        [ -n "$review_url" ] && report_review_delivery "comment_failed"
        echo "::warning::oasdiff: couldn't post the review link as a PR comment (HTTP ${code}). Add 'permissions: pull-requests: write' to the job that runs this action. The link is in the job summary meanwhile."
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
    # shellcheck disable=SC2000 # bytes, not characters, deliberately; see the comment above
    size=$(echo "$output" | wc -c)
    if [ "$size" -ge "1000000" ]; then
        echo "WARN: diff exceeds the 1MB limit, truncating output..." >&2
        output=$(echo "$output" | head -c 1000000)
    fi
    echo "$output" >>"$GITHUB_OUTPUT"
}

# pro_review (oasdiff-token set): upload an authenticated review, post/update the
# Pro PR comment, and set the `oasdiff` commit-status gate. Best-effort and never
# fatal, like the free review. Needs a pull_request event; the comment and status
# need a github-token with pull-requests:write + statuses:write. Used instead of
# the free review when an oasdiff-token is provided (one review per PR).
pro_review () {
    pr_number=$(echo "$GITHUB_REF" | sed -n 's|refs/pull/\([0-9]*\)/merge|\1|p')
    if [ -z "$pr_number" ]; then
        echo "::notice::oasdiff: a Pro review needs a pull_request event; skipping (no PR to attach to)."
        return 0
    fi
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY#*/}"
    head_sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    [ -z "$head_sha" ] && head_sha="$GITHUB_SHA"

    # oasdiff encrypts {specs + changelog} with a one-time key, uploads only the
    # ciphertext to the token-authenticated endpoint, and prints the /review/ep
    # URL (key in the #fragment) plus "oasdiff: review status: <state>" to stderr.
    # Tolerate a non-zero exit; --open is additive. --review-meta carries the PR
    # context as an opaque bag the CLI forwards without interpreting.
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    pro_out=$(oasdiff "$oasdiff_command" "$base" "$revision" $flags --open --template= \
        --review-token "$oasdiff_token" \
        --review-meta owner="$owner" \
        --review-meta repo="$repo" \
        --review-meta pull_number="$pr_number" \
        --review-meta head_sha="$head_sha" 2>&1) || true
    review_url=$(printf '%s' "$pro_out" | grep -oE 'https://[^[:space:]]+/review/ep/[^[:space:]]+' | head -n 1) || true
    gate=$(printf '%s' "$pro_out" | sed -n 's/^oasdiff: review status: \([a-z][a-z]*\).*/\1/p' | head -n 1) || true
    # A lapsed trial/subscription returns HTTP 402 with a subscription_expired
    # body, which the CLI surfaces as "upload failed (HTTP 402): ...". Show a
    # clear renewal message instead of the generic "verify the oasdiff-token"
    # warning below, and don't fail the job.
    if printf '%s' "$pro_out" | grep -q 'subscription_expired'; then
        echo "::warning title=oasdiff trial or subscription expired::Your oasdiff plan has expired, so no Pro review was posted. Renew at https://www.oasdiff.com/pricing to continue using oasdiff Pro."
        {
            echo "### ⚠️ oasdiff trial or subscription expired"
            echo ""
            echo "Your oasdiff trial or subscription has expired, so no Pro review was posted for this pull request."
            echo ""
            echo "**To resume oasdiff Pro:** [renew your plan](https://www.oasdiff.com/pricing)."
        } >> "$GITHUB_STEP_SUMMARY"
        return 0
    fi
    if [ -z "$review_url" ]; then
        echo "::warning::oasdiff: couldn't upload the Pro review (the changelog still ran). Re-run the job, or verify the oasdiff-token."
        return 0
    fi

    pro_gate="$gate"
    echo "### 📋 [Review and approve the API changes](${review_url})" >> "$GITHUB_STEP_SUMMARY"
    pro_comment "$review_url"
    set_commit_status "$owner" "$repo" "$head_sha" "$gate" "$review_url"
}

# pro_comment posts or updates the Pro review comment (marker oasdiff-pro-review).
pro_comment () {
    review_url="$1"
    if [ -z "$github_token" ]; then
        echo "::notice::oasdiff: review uploaded; add 'github-token: \${{ github.token }}' and grant 'permissions: pull-requests: write, statuses: write' to post the review comment and set the \`oasdiff\` status check. The link is in the job summary."
        return 0
    fi
    api="${GITHUB_API_URL:-https://api.github.com}"
    marker="<!-- oasdiff-pro-review -->"
    # The comment does not say whether the changes are approved: it is written
    # when the job runs, and a decision made in the review afterwards reaches
    # the \`oasdiff\` status check, not the comment.
    status_line="Approve or reject each breaking change in the review. The \`oasdiff\` status check on this pull request shows whether they are all approved."

    existing_id=$(curl -s \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github+json" \
        "${api}/repos/${owner}/${repo}/issues/${pr_number}/comments?per_page=100" 2>/dev/null \
        | jq -r --arg m "$marker" 'map(select(.body | contains($m))) | .[0].id // empty' 2>/dev/null) || existing_id=""

    if [ "${change_count:-0}" -eq 1 ]; then
        heading="1 ${change_noun} in this pull request"
    else
        heading="${change_count:-0} ${change_noun}s in this pull request"
    fi
    body="${marker}
### ${comment_icon} ${heading}

${status_line}

$(review_comment_changes "${changes_json:-}")

[Review and approve the changes](${review_url})

🔒 The comparison is encrypted in CI before it's uploaded. The decryption key stays in this link's fragment (after the #), which browsers never send to a server, so oasdiff cannot read your specs.

<sub>Posted automatically by the [oasdiff GitHub Action](https://www.oasdiff.com/docs/setup). Make the \`oasdiff\` status check a required check to block merging until every breaking change is approved.</sub>"

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
        echo "oasdiff: posted the Pro review comment."
    else
        echo "::notice::oasdiff: couldn't post the Pro review comment (HTTP ${code}). On fork pull requests the token is read-only; otherwise grant 'permissions: pull-requests: write'. The link is in the job summary."
    fi
}

# set_commit_status sets the `oasdiff` commit-status gate from the review state.
set_commit_status () {
    s_owner="$1"
    s_repo="$2"
    s_sha="$3"
    s_gate="$4"
    s_target="$5"
    [ -z "$github_token" ] && return 0
    [ -z "$s_sha" ] && return 0
    api="${GITHUB_API_URL:-https://api.github.com}"
    case "$s_gate" in
        approved) state="success"; desc="All API changes approved" ;;
        rejected) state="failure"; desc="API changes were rejected" ;;
        *)        state="pending"; desc="API changes need review" ;;
    esac
    payload=$(jq -n --arg s "$state" --arg c "oasdiff" --arg d "$desc" --arg u "$s_target" \
        '{state: $s, context: $c, description: $d} + (if $u == "" then {} else {target_url: $u} end)')
    code=$(printf '%s' "$payload" | curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github+json" \
        "${api}/repos/${s_owner}/${s_repo}/statuses/${s_sha}" --data-binary @- 2>/dev/null) || code="000"
    if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        echo "oasdiff: set the 'oasdiff' commit status to '$state'."
    else
        echo "::notice::oasdiff: couldn't set the commit status (HTTP ${code}). On fork pull requests the token is read-only; otherwise grant 'permissions: statuses: write'."
    fi
}

# pro_review_clear handles the no-changes case: clear the gate (success) and, if a
# Pro comment already exists, update it to "no changes". Never creates a comment.
pro_review_clear () {
    pr_number=$(echo "$GITHUB_REF" | sed -n 's|refs/pull/\([0-9]*\)/merge|\1|p')
    [ -z "$pr_number" ] && return 0
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY#*/}"
    head_sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    [ -z "$head_sha" ] && head_sha="$GITHUB_SHA"
    set_commit_status "$owner" "$repo" "$head_sha" "approved" ""
    [ -z "$github_token" ] && return 0
    api="${GITHUB_API_URL:-https://api.github.com}"
    marker="<!-- oasdiff-pro-review -->"
    existing_id=$(curl -s \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github+json" \
        "${api}/repos/${owner}/${repo}/issues/${pr_number}/comments?per_page=100" 2>/dev/null \
        | jq -r --arg m "$marker" 'map(select(.body | contains($m))) | .[0].id // empty' 2>/dev/null) || existing_id=""
    [ -z "$existing_id" ] && return 0
    body="${marker}
### ✅ ${no_changes_comment}"
    payload=$(jq -n --arg body "$body" '{body: $body}')
    printf '%s' "$payload" | curl -s -o /dev/null -X PATCH \
        -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github+json" \
        "${api}/repos/${owner}/${repo}/issues/comments/${existing_id}" --data-binary @- 2>/dev/null || true
}

# finish exits the job. A Pro review makes a breaking change something a
# reviewer can approve, so once every breaking change is approved, a fail-on
# of ERR or WARN is satisfied and the job passes. Until then the job fails as
# it does without a token, so a job that is a required check keeps blocking
# the merge. INFO and MISSING-VERSION-BUMP are left alone: info changes are
# not part of the approval, and a missing version bump is a rule about the
# release, which approving the changes does not answer.
# $1: the exit code of the report run.
finish () {
    code="$1"
    if [ "$code" -eq 1 ] && [ -n "${pro_gate:-}" ]; then
        if [ "$pro_gate" != "approved" ]; then
            echo "::notice::oasdiff: fail-on fails this job until every breaking change is approved. Approve them in the review, then re-run the job."
        elif [ "$fail_on" != "INFO" ] && [ "$fail_on" != "MISSING-VERSION-BUMP" ] && [ -z "${version_policy_violated:-}" ]; then
            echo "oasdiff: every breaking change in this pull request is approved, so fail-on does not fail the job."
            code=0
        fi
    fi
    exit "$code"
}

run_breaking () {
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
        echo "::warning::oasdiff: 'include-checks' is ignored, the optional-checks mechanism it drove was retired. To make a check fail the build, add 'severity-levels: <file>' to .oasdiff.yaml, listing the check id with level 'err', and set 'fail-on: ERR'."
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
    if [ -n "$config" ]; then
        flags="$flags --config $config"
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
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    breaking_changes=$(oasdiff breaking "$base" "$revision" $flags $fail_on_flag 2>"$_err") || exit_code=$?
    version_policy_violated=""
    grep -q '^versioning policy: violated' "$_err" && version_policy_violated=1
    [ -s "$_err" ] && cat "$_err" >&2
    # Promote a genuine oasdiff failure to a Checks-tab annotation. Exit 0 is
    # success and exit 1 is the intended "breaking changes found" / fail-on result;
    # only codes >=2 (load/parse/etc.) are real errors worth surfacing here.
    # Stop here on a real failure: the comparison never ran, so there is nothing to
    # report about it. Falling through would report a clean result for a run that
    # failed. Matches the changelog action.
    if [ "$exit_code" -ge 2 ]; then
        [ -s "$_err" ] && echo "::error::$(tr '\n' ' ' < "$_err")"
        # Exit code 123 = oasdiff refused a disallowed external $ref (stable
        # contract, not message text). Surface the action-specific remedy.
        if [ "$exit_code" -eq 123 ]; then
            echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
        fi
        rm -f "$_err"
        exit "$exit_code"
    fi
    rm -f "$_err"

    # Run 2: render annotations to stdout via --format githubactions so
    # GitHub parses them onto the PR's "Files changed" tab. Tolerate
    # non-zero exit (could be triggered by oasdiff.yaml fail-on); the
    # authoritative exit code is from Run 1. --template= overrides a 'template'
    # set in .oasdiff.yaml, which is rejected for the githubactions format and
    # would (via || true) silently suppress the annotations.
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    oasdiff breaking "$base" "$revision" $flags --format githubactions --template= || true

    # *** GitHub Action step output ***

    # Output name should be in the syntax of multiple lines:
    # {name}<<{delimiter}
    # {value}
    # {delimiter}
    # see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
    delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
    echo "breaking<<$delimiter" >>"$GITHUB_OUTPUT"

    # Run 3: one json render answers two questions, how many breaking changes
    # there are and what they are, so the count below and the PR comment read the
    # same data. json is format-proof, where parsing $breaking_changes is not: its
    # shape follows any 'format' set in .oasdiff.yaml (json renders "[]", not
    # "No ..."). --format and --template= override that config for this render
    # only; Run 1's authoritative gate exit code is untouched. The render goes to a
    # file, never a variable, because a large changelog on a command line hits
    # ARG_MAX.
    changes_json=$(mktemp)
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    oasdiff breaking "$base" "$revision" $flags --format json --template= > "$changes_json" 2>/dev/null || true
    change_count=$(jq 'length' < "$changes_json" 2>/dev/null) || change_count=0
    case "$change_count" in
        ''|*[!0-9]*) change_count=0 ;;
    esac
    if [ "$change_count" -gt 0 ]; then
        write_output "$(echo "$breaking_changes" | head -n 1)" "$breaking_changes"

        free_review_url=""
        # review (default true): upload the comparison to oasdiff.com and link
        # straight to the rendered side-by-side review. The upload is
        # zero-knowledge -- the oasdiff binary encrypts the two specs client-side
        # and the decryption key lives only in the URL #fragment, so the server
        # stores a blob it cannot read. Set review: false to skip the upload
        # entirely, so no spec ever leaves CI; the breaking-change detection and
        # the inline annotations are unaffected either way.
        if [ -n "$oasdiff_token" ]; then
            # Pro: an authenticated review with an approval gate, posted instead
            # of the free one (one review per pull request).
            if [ "$composed" = "true" ]; then
                echo "::notice::oasdiff: the side-by-side review isn't available in composed mode (-c). The breaking-change report above is unaffected."
            else
                pro_review
            fi
        elif [ "$review" != "false" ]; then
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
                # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
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
        if [ -n "$oasdiff_token" ]; then
            pro_review_clear
        elif [ "$review" != "false" ]; then
            post_review_comment ""
        fi
    fi

    rm -f "$changes_json"

    echo "$delimiter" >>"$GITHUB_OUTPUT"
    # review_url is a single-line output, written after the multiline `breaking`
    # block is closed so it doesn't get folded into that value. Empty when there
    # are no breaking changes (the notice/URL only fire then).
    echo "review_url=${free_review_url:-${review_url:-}}" >> "$GITHUB_OUTPUT"

    finish "$exit_code"
}

run_changelog () {
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
    # Pin composed to the action input so a 'composed' setting in .oasdiff.yaml can't
    # desync oasdiff's mode from the action's logic (the --open guard and flag
    # building both key off this input). A cmd-line flag overrides config.
    flags="$flags --composed=$composed"
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
    # changes probe and the --open upload below run on the semantic flags only: the
    # probe doesn't need the user's format, and --open renders the changelog as json
    # internally where --template is rejected (it would error the upload). $fmt_flags
    # is applied only to the user-facing changelog render.
    fmt_flags=""
    if [ -n "$format" ]; then
        fmt_flags="$fmt_flags --format $format"
    fi
    if [ -n "$template" ]; then
        fmt_flags="$fmt_flags --template $template"
    fi
    if [ -n "$config" ]; then
        flags="$flags --config $config"
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
    fail_on_flag=""
    if [ -n "$fail_on" ]; then
        fail_on_flag="--fail-on $fail_on"
    fi
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    output=$(oasdiff changelog "$base" "$revision" $flags $fmt_flags $fail_on_flag 2>"$_err") || exit_code=$?
    version_policy_violated=""
    grep -q '^versioning policy: violated' "$_err" && version_policy_violated=1
    # Only codes >=2 are real errors. Exit 1 is a fail-on result (the changelog
    # action has no fail-on input, but .oasdiff.yaml can set one); the changelog
    # action doesn't gate, so don't let it abort the run or suppress the review below.
    if [ "$exit_code" -ge 2 ]; then
        [ -s "$_err" ] && cat "$_err" >&2
        # Promote a genuine failure to a Checks-tab annotation.
        [ -s "$_err" ] && echo "::error::$(tr '\n' ' ' < "$_err")"
        # Exit code 123 = oasdiff refused a disallowed external $ref (stable
        # contract, not message text). Surface the action-specific remedy.
        if [ "$exit_code" -eq 123 ]; then
            echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
        fi
        rm -f "$_err"
        exit "$exit_code"
    fi
    rm -f "$_err"

    # Inline annotations for the error and warning changes, on the lines they
    # are on, as the breaking action writes them. Info changes are filtered
    # out: a changelog can hold one per added property, and a notice for each
    # would bury the ones that matter. The format also writes error_count,
    # warning_count and info_count to GITHUB_OUTPUT, which this action does
    # not declare, so that is pointed away. --template= overrides a 'template'
    # set in .oasdiff.yaml, which this format rejects.
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    GITHUB_OUTPUT=/dev/null oasdiff changelog "$base" "$revision" $flags --format githubactions --template= 2>/dev/null \
        | grep -v '^::notice' || true

    # One json render answers two questions, how many changes there are and what
    # they are, so the count below and the PR comment read the same data. The
    # user-facing $output cannot be parsed for either: it varies by format
    # (json/yaml render "[]", markup adds a header line). --level stays in $flags so
    # this matches what the user sees, while --format and --template= override that
    # config for this render only and the rendered run above is untouched. The
    # render goes to a file, never a variable, because a large changelog on a
    # command line hits ARG_MAX.
    changes_json=$(mktemp)
    # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
    oasdiff changelog "$base" "$revision" $flags --format json --template= > "$changes_json" 2>/dev/null || true
    change_count=$(jq 'length' < "$changes_json" 2>/dev/null) || change_count=0
    case "$change_count" in
        ''|*[!0-9]*) change_count=0 ;;
    esac
    if [ "$change_count" -gt 0 ]; then
        write_output "$output"

        free_review_url=""
        if [ -n "$oasdiff_token" ]; then
            # Pro mode: an authenticated review with an approval gate, posted instead
            # of the free anonymous review (one review per PR). composed mode can't
            # build a two-spec side-by-side, same as the free path.
            if [ "$composed" = "true" ]; then
                echo "::notice::oasdiff: the side-by-side review isn't available in composed mode (-c). The changelog above is unaffected."
            else
                pro_review
            fi
        # review (default true): upload the comparison to oasdiff.com and link
        # straight to the rendered side-by-side review. The upload is
        # zero-knowledge -- the oasdiff binary encrypts the two specs client-side
        # and the decryption key lives only in the URL #fragment, so the server
        # stores a blob it cannot read. Set review: false to skip the upload
        # entirely, so no spec ever leaves CI; the changelog output and the inline
        # annotations are unaffected either way.
        elif [ "$review" != "false" ]; then
            if [ "$composed" = "true" ]; then
                # Composed mode (-c) diffs globs of many files; the side-by-side
                # review represents exactly two specs, so --open can't build it.
                # Say so once instead of running --open only to hit the generic
                # "couldn't upload" warning below.
                echo "::notice::oasdiff: the side-by-side review isn't available in composed mode (-c). The changelog above is unaffected."
            else
                # --open prints the review URL to stderr (oasdiff >= v1.19.1 moved it
                # off stdout so it can't corrupt piped --format output); in CI the
                # browser-open step soft-fails. Merge stderr into the pipe (2>&1) and
                # grep the /review/e/ URL out by its stable path shape (not by
                # surrounding prose). Tolerate a non-zero exit / no match so `set -e`
                # doesn't abort the run. --template= overrides a 'template' set in
                # .oasdiff.yaml, which would otherwise error this render (templates
                # are rejected for the default text format) and yield no URL.
                # shellcheck disable=SC2086 # the flags variables hold multiple arguments; splitting is intended
                free_review_url=$(oasdiff changelog "$base" "$revision" $flags --open --template= 2>&1 \
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
        if [ -n "$oasdiff_token" ]; then
            pro_review_clear
        elif [ "$review" != "false" ]; then
            post_review_comment ""
        fi
    fi

    rm -f "$changes_json"

    echo "$delimiter" >>"$GITHUB_OUTPUT"
    # review_url is a single-line output, written after the multiline `changelog`
    # block is closed so it doesn't get folded into that value. Empty when there
    # are no changes (the notice/URL only fire then).
    echo "review_url=${free_review_url:-${review_url:-}}" >> "$GITHUB_OUTPUT"

    # 1 when fail-on was reached, from the input or from .oasdiff.yaml.
    finish "$exit_code"
}

case "$oasdiff_command" in
    breaking) run_breaking ;;
    changelog) run_changelog ;;
esac
