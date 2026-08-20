#!/usr/bin/env bash

script_path="${BASH_SOURCE[0]}"
if [[ -L "$script_path" ]]; then
    script_path="$(readlink "$script_path")"
fi
source_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"

julia --project="$source_dir/code" "$source_dir/code/code.jl"
