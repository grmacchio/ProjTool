natural_numbers = collect(1:10)
output_file = joinpath(@__DIR__, "_natural_numbers.tex")

open(output_file, "w") do file
    println(file, join(natural_numbers, ", "))
end
