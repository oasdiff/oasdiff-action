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
readonly include_path_params="$4"
readonly exclude_elements="$5"
readonly composed="$6"
readonly output_to_file="$7"

echo "running oasdiff changelog base: $base, revision: $revision, include_path_params: $include_path_params, exclude_elements: $exclude_elements, composed: $composed, output_to_file: $output_to_file"

# Build flags to pass in command
flags=""
if [ "$format" != "yaml" ]; then
    flags="$flags --format $format"
fi
if [ "$include_path_params" = "true" ]; then
    flags="$flags --include-path-params"
fi
if [ -n "$exclude_elements" ]; then
    flags="$flags --exclude-elements $exclude_elements"
fi
if [ "$composed" = "true" ]; then
    flags="$flags -c"
fi
echo "flags: $flags"

set -o pipefail

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

if [ -n "$output" ]; then
    write_output "$output"
else
    write_output "No changelog changes"
fi

echo "$delimiter" >>"$GITHUB_OUTPUT"

# *** github action step output ***

