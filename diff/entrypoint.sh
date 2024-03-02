#!/bin/sh
set -e

write_output () {
    local output="$1"
    local truncate_if_needed="$2"
    if [ -n "$output_to_file" ]; then
        echo "$output" >> "$output_to_file"
    fi
    # github-action limits output to 1MB
    # we count bytes because unicode has multibyte characters
    if [ "$truncate_if_needed" = "true" ]; then
        size=$(echo "$output" | wc -c)
        if [ "$size" -ge "1000000" ]; then
            echo "WARN: diff exceeds the 1MB limit, truncating output..." >&2
            output=$(echo "$output" | head -c 1000000)
        fi
    fi 
    echo "$output" >>"$GITHUB_OUTPUT"
}

readonly base="$1"
readonly revision="$2"
readonly format="$3"
readonly fail_on_diff="$4"
readonly include_path_params="$5"
readonly exclude_elements="$6"
readonly output_to_file="$7"

echo "running oasdiff diff base: $base, revision: $revision, format: $format, fail_on_diff: $fail_on_diff, include_path_params: $include_path_params, exclude_elements: $exclude_elements"

# Build flags to pass in command
flags=""
if [ "$format" != "yaml" ]; then
    flags="${flags} --format ${format}"
fi
if [ "$fail_on_diff" = "true" ]; then
    flags="${flags} --fail-on-diff"
fi
if [ "$include_path_params" = "true" ]; then
    flags="${flags} --include-path-params"
fi
if [ "$exclude_elements" != "" ]; then
    flags="${flags} --exclude-elements ${exclude_elements}"
fi
echo "flags: $flags"

# *** github action step output ***

# output name should be in the syntax of multiple lines:
# {name}<<{delimiter}
# {value}
# {delimiter}
# see: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings
delimiter=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
write_output "diff<<$delimiter"

set -o pipefail

if [ -n "$flags" ]; then
    output=$(oasdiff diff "$base" "$revision" "$flags")
else
    output=$(oasdiff diff "$base" "$revision")
fi

if [ -n "$output" ]; then
    write_output "$output" "true"
else
    write_output "No changes"
fi

write_output "$delimiter"