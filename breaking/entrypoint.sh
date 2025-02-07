#!/bin/sh
set -e

readonly base="$1"
readonly revision="$2"
readonly fail_on="$3"
readonly include_checks="$4"
readonly include_path_params="$5"
readonly deprecation_days_beta="$6"
readonly deprecation_days_stable="$7"
readonly exclude_elements="$8"
readonly filter_extension="$9"
readonly composed="$10"
readonly output_to_file="${11}"

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

echo "running oasdiff breaking... base: $base, revision: $revision, fail_on: $fail_on, include_checks: $include_checks, include_path_params: $include_path_params, deprecation_days_beta: $deprecation_days_beta, deprecation_days_stable: $deprecation_days_stable, exclude_elements: $exclude_elements, filter_extension: $filter_extension, composed: $composed, output_to_file: $output_to_file"

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
else
    write_output "No breaking changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"

# First output the changes (above) and then run oasdiff to check --fail-on
if [ -n "$fail_on" ]; then
    flags="$flags --fail-on $fail_on"
    oasdiff breaking "$base" "$revision" $flags > /dev/null
fi
