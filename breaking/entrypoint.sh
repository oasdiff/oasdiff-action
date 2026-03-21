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

write_output () {
    _write_output_output="$1"
    if [ -n "$output_to_file" ]; then
        _write_output_file_output="$2"
        if [ -z "$_write_output_file_output" ]; then
            _write_output_file_output=$_write_output_output

        fi
        echo "$_write_output_file_output" >> "$output_to_file"
    fi
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    size=$(echo "$_write_output_output" | wc -c)
    if [ "$size" -ge "1000000" ]; then
        echo "WARN: diff exceeds the 1MB limit, truncating output..." >&2
        _write_output_output=$(echo "$_write_output_output" | head -c 1000000)
    fi
    echo "$_write_output_output" >>"$GITHUB_OUTPUT"
}

echo "running oasdiff breaking... base: $base, revision: $revision, fail_on: $fail_on, include_checks: $include_checks, include_path_params: $include_path_params, deprecation_days_beta: $deprecation_days_beta, deprecation_days_stable: $deprecation_days_stable, exclude_elements: $exclude_elements, filter_extension: $filter_extension, composed: $composed, flatten_allof: $flatten_allof, err_ignore: $err_ignore, warn_ignore: $warn_ignore, output_to_file: $output_to_file"

# Build flags to pass in command
flags=""
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

# Check for breaking changes
if [ -n "$flags" ]; then
    breaking_changes=$(oasdiff breaking "$base" "$revision" $flags)
else
    breaking_changes=$(oasdiff breaking "$base" "$revision")
fi

# Updating GitHub Action summary with formatted output
flags_with_githubactions="$flags --format githubactions"
# Writes the summary to log and updates GitHub Action summary
oasdiff breaking "$base" "$revision" $flags_with_githubactions

# *** GitHub Action step output ***

# Output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "breaking<<$delimiter" >>"$GITHUB_OUTPUT"

if [ -n "$breaking_changes" ]; then
    write_output "$(echo "$breaking_changes" | head -n 1)" "$breaking_changes"
    # Emit upgrade notice pointing to the free review page
    urlencode() { printf '%s' "$1" | jq -sRr @uri; }
    base_path=$(echo "$base" | sed 's/.*://')
    rev_path=$(echo "$revision" | sed 's/.*://')
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY#*/}"
    head_sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
    if [ -z "$head_sha" ]; then head_sha="$GITHUB_SHA"; fi
    free_review_url="https://www.oasdiff.com/review?owner=${owner}&repo=${repo}&base_sha=$(urlencode "$GITHUB_BASE_REF")&rev_sha=${head_sha}&base_file=$(urlencode "$base_path")&rev_file=$(urlencode "$rev_path")"
    echo "::notice::📋 Review & approve these breaking changes → ${free_review_url}"
    echo "### 📋 [Review & approve these breaking changes](${free_review_url})" >> "$GITHUB_STEP_SUMMARY"
else
    write_output "No breaking changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"

# First output the changes (above) and then run oasdiff to check --fail-on
if [ -n "$fail_on" ]; then
    flags="$flags --fail-on $fail_on"
    oasdiff breaking "$base" "$revision" $flags > /dev/null
fi
