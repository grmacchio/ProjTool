using Pkg
using TOML

isempty(ARGS) && error("Provide the selected Juliaup channel followed by project directories.")
channel = first(ARGS)
println("Preparing packages with Julia ", VERSION, " (Juliaup channel ", channel, ")")

for project in ARGS[2:end]
    project_file = joinpath(project, "Project.toml")
    configuration = TOML.parsefile(project_file)
    get!(configuration, "compat", Dict{String, Any}())["julia"] = string(VERSION)
    open(project_file, "w") do stream
        TOML.print(stream, configuration; sorted=true)
    end
    Pkg.activate(project)
    Pkg.update()
    Pkg.instantiate()
end
