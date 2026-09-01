#!/usr/bin/env bash

julia ./code/julia/code.jl
if [[ "${PROJTOOL_VERBOSE:-false}" == "true" ]]; then
    jupyter execute ./code/python/code.ipynb
else
    jupyter execute --NbClientApp.log_level=ERROR ./code/python/code.ipynb
fi
