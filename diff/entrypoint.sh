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
readonly format="$3"
readonly fail_on_diff="$4"
readonly include_path_params="$5"
readonly exclude_elements="$6"
readonly filter_extension="$7"
readonly composed="$8"
readonly flatten_allof="$9"
readonly output_to_file="${10}"
readonly allow_external_refs="${11}"

echo "running oasdiff diff base: $base, revision: $revision, format: $format, fail_on_diff: $fail_on_diff, include_path_params: $include_path_params, exclude_elements: $exclude_elements, filter_extension: $filter_extension, composed: $composed, flatten_allof: $flatten_allof, output_to_file: $output_to_file"

# Build flags to pass in command
flags=""
# allow-external-refs defaults to false (safe for CI on untrusted PRs); pass
# whatever the input resolved to so the explicit action input is authoritative.
if [ -n "$allow_external_refs" ]; then
    flags="$flags --allow-external-refs=$allow_external_refs"
fi
if [ "$format" != "yaml" ]; then
    flags="$flags --format $format"
fi
if [ "$fail_on_diff" = "true" ]; then
    flags="$flags --fail-on-diff"
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
echo "flags: $flags"

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
echo "diff<<$delimiter" >>"$GITHUB_OUTPUT"

# Capture the exit code from oasdiff command while still getting the output
exit_code=0
_err=$(mktemp)
if [ -n "$flags" ]; then
    output=$(oasdiff diff "$base" "$revision" $flags 2>"$_err") || exit_code=$?
else
    output=$(oasdiff diff "$base" "$revision" 2>"$_err") || exit_code=$?
fi
[ -s "$_err" ] && cat "$_err" >&2
# Exit code 123 = oasdiff refused a disallowed external $ref (stable contract,
# not message text). Surface the action-specific remedy.
if [ "$exit_code" -eq 123 ]; then
    echo "::error::oasdiff: this spec resolves external \$refs, which are disabled by default to prevent SSRF on untrusted pull requests. If the spec is trusted, set 'allow-external-refs: true' on the oasdiff action step."
fi
rm -f "$_err"

if [ -n "$output" ]; then
    write_output "$output" 
else
    write_output "No changes"
fi

# Always close the multiline output format properly
echo "$delimiter" >>"$GITHUB_OUTPUT"

# Exit with the original exit code from oasdiff
exit $exit_code
