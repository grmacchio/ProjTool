using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using Plots

mkpath("./Output/Results/Julia")

open("./Output/Results/Julia/natural_numbers.tex", "w") do file
    print(file, join(1:10, ", "))
end

x = range(-1, 1; length=200)
plot(x, exp.(x); legend=false, xlabel="x", ylabel="e^x", linewidth=2)
savefig("./Output/Results/Julia/exp.png")
