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
    # Emit upgrade notice pointing to the free review page
    urlencode() { printf '%s' "$1" | jq -sRr @uri; }
    # Strip the git-ref prefix ("origin/main:openapi.yaml" -> "openapi.yaml")
    # but pass http(s):// URLs through unchanged. A naive `sed 's/.*://'` would
    # also eat "https:" and emit a broken "//host/..." that the /review page
    # can't fetch (it renders the misleading access-denied screen).
    strip_ref_prefix() {
        case "$1" in
            http://*|https://*) printf '%s' "$1" ;;
            *)                  printf '%s' "$1" | sed 's/.*://' ;;
        esac
    }
    base_path=$(strip_ref_prefix "$base")
    rev_path=$(strip_ref_prefix "$revision")
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY#*/}"
    head_sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
    if [ -z "$head_sha" ]; then head_sha="$GITHUB_SHA"; fi
    # base_sha must be an immutable commit SHA, not the branch name. Using
    # $GITHUB_BASE_REF (the branch) makes the URL decay whenever the branch
    # advances past the file's commit, e.g. someone merges a rename of the
    # spec file and every previously-emitted /review URL starts 404'ing
    # because raw.githubusercontent.com now resolves the branch to a newer
    # commit where the file lives at a different path.
    base_sha=$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
    if [ -z "$base_sha" ]; then base_sha=$(git rev-parse "origin/$GITHUB_BASE_REF" 2>/dev/null || echo "$GITHUB_BASE_REF"); fi
    free_review_url="https://www.oasdiff.com/review?owner=${owner}&repo=${repo}&base_sha=$(urlencode "$base_sha")&rev_sha=${head_sha}&base_file=$(urlencode "$base_path")&rev_file=$(urlencode "$rev_path")"
    echo "::notice::📋 Review & approve these breaking changes → ${free_review_url}"
    # The Step Summary surfaces both the link (for visitors who'd rather use
    # the web UI) and the CLI command itself (for visitors who recognize it
    # and want to skip the instruction-page detour). GitHub renders the
    # fenced code block with a built-in copy button, so the one-step path
    # for the familiar-visitor cohort is: scroll to the Checks tab, click
    # copy on the command, paste into a terminal in the local clone, run.
    # See enterprise/docs/cli-local-review.md (Phase 1, step 5).
    {
        echo "### 📋 [Review & approve these breaking changes](${free_review_url})"
        echo ""
        echo "Or run locally in your clone of \`${repo}\`:"
        echo ""
        echo '```bash'
        echo "oasdiff breaking ${base_sha}:${base_path} ${head_sha}:${rev_path} --open"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
else
    write_output "No breaking changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"
# review_url is a single-line output, written after the multiline `breaking`
# block is closed so it doesn't get folded into that value. Empty when there
# are no breaking changes (the notice/URL only fire then).
echo "review_url=${free_review_url:-}" >> "$GITHUB_OUTPUT"

exit $exit_code
