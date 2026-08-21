import Pkg

activation_output = get(ENV, "PROJTOOL_VERBOSE", "false") == "true" ? stderr : devnull
Pkg.activate(@__DIR__; io=activation_output)
ENV["GKSwstype"] = "nul"

using Plots

open("natural_numbers.tex", "w") do file
    print(file, join(1:10, ", "))
end

x = range(-1, 1; length=200)
plot(x, exp.(x); legend=false, xlabel="x", ylabel="e^x", linewidth=2)
savefig("image.png")
