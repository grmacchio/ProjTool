#!/usr/bin/env bash

julia ./code/julia/code.jl
jupyter execute --kernel_name=projtool ./code/python/code.ipynb
