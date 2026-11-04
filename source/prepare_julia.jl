using Pkg
using TOML

for project in ARGS
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
