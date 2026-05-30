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
if [ -n "$format" ]; then
    flags="$flags --format $format"
fi
if [ -n "$template" ]; then
    flags="$flags --template $template"
fi
if [ -n "$level" ]; then
    flags="$flags --level $level"
fi
echo "flags: $flags"

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "changelog<<$delimiter" >>"$GITHUB_OUTPUT"

if [ -n "$flags" ]; then
    output=$(oasdiff changelog "$base" "$revision" $flags)
else
    output=$(oasdiff changelog "$base" "$revision")
fi

if [ -n "$output" ] && ! echo "$output" | head -n 1 | grep -q "^No "; then
    write_output "$output"
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
    echo "::notice::📋 Review & approve these API changes → ${free_review_url}"
    # The Step Summary surfaces both the link (for visitors who'd rather use
    # the web UI) and the CLI command itself (for visitors who recognize it
    # and want to skip the instruction-page detour). GitHub renders the
    # fenced code block with a built-in copy button. See
    # enterprise/docs/cli-local-review.md (Phase 1, step 5).
    {
        echo "### 📋 [Review & approve these API changes](${free_review_url})"
        echo ""
        echo "Or run locally in your clone of \`${repo}\`:"
        echo ""
        echo '```bash'
        echo "oasdiff changelog ${base_sha}:${base_path} ${head_sha}:${rev_path} --open"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
else
    write_output "No changelog changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"
# review_url is a single-line output, written after the multiline `changelog`
# block is closed so it doesn't get folded into that value. Empty when there
# are no changes (the notice/URL only fire then).
echo "review_url=${free_review_url:-}" >> "$GITHUB_OUTPUT"

# *** github action step output ***

