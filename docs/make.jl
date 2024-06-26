# Run with: julia --startup-file=no make.jl
using Documenter, Gnuplot
using RDatasets, TestImages

makedocs(sitename="Gnuplot.jl",
         authors = "Giorgio Calderone",
         # format = Documenter.HTML(prettyurls = false),  # uncomment for local use, comment for deployment
         modules=[Gnuplot],
         checkdocs=:exports,
         pages = [
             "Home" => "index.md",
             "Installation" => "install.md",
             "Basic usage" => "basic.md",
             "Advanced usage" => "advanced.md",
             "Package options" => "options.md",
             "Style guide" => "style.md",
             "Gnuplot terminals" => "terminals.md",
             "Plot recipes" => "recipes.md",
             "Examples" => "examples.md",
             "API" => "api.md"
         ])
