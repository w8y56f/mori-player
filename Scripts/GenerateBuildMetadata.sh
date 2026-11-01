#!/bin/sh
# Usage: sh Scripts/GenerateBuildMetadata.sh <repository-root> <output-json>
# Outputs only to the build directory; never rewrites tracked source files.
set -eu
source_directory=$(cd "$1" && pwd -P)
output_file=$2
commit_id=unknown
dirty=null
repository_root=$(/usr/bin/git -C "$source_directory" rev-parse --show-toplevel 2>/dev/null || true)
if [ "$repository_root" = "$source_directory" ]; then
    if commit_id=$(/usr/bin/git -C "$source_directory" rev-parse --short=7 --verify HEAD 2>/dev/null); then
        if status=$(/usr/bin/git -C "$source_directory" status --porcelain=v1 --untracked-files=normal); then
            if [ -n "$status" ]; then dirty=true; else dirty=false; fi
        else
            commit_id=unknown
            dirty=null
        fi
    else
        commit_id=no-commit
        dirty=true
    fi
fi
mkdir -p "$(dirname "$output_file")"
temporary_file="$output_file.tmp.$$"
trap 'rm -f "$temporary_file"' EXIT
printf '{"commit":"%s","dirty":%s}\n' "$commit_id" "$dirty" > "$temporary_file"
# Keep the resource timestamp stable if the build identity has not changed.
if [ ! -f "$output_file" ] || ! cmp -s "$temporary_file" "$output_file"; then
    mv "$temporary_file" "$output_file"
fi
