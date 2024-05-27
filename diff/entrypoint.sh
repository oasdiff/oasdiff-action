#!/bin/sh
set -e

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
readonly composed="$7"
readonly output_to_file="$8"
readonly max_circular_dep="$9"

echo "running oasdiff diff base: $base, revision: $revision, format: $format, fail_on_diff: $fail_on_diff, include_path_params: $include_path_params, exclude_elements: $exclude_elements, composed: $composed, output_to_file: $output_to_file", max_circular_dep: $max_circular_dep

# Build flags to pass in command
flags=""
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
if [ -n "$max_circular_dep" ]; then
    flags="$flags --max-circular-dep $max_circular_dep"
fi
if [ "$composed" = "true" ]; then
    flags="$flags -c"
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

set -o pipefail

if [ -n "$flags" ]; then
    output=$(oasdiff diff "$base" "$revision" $flags)
else
    output=$(oasdiff diff "$base" "$revision")
fi

if [ -n "$output" ]; then
    write_output "$output"
else
    write_output "No changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"