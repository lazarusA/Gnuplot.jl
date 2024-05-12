# Run with: julia --startup-file=no make.jl
using Documenter, Gnuplot
using RDatasets, TestImages
using DocumenterVitepress

makedocs(sitename="Gnuplot.jl",
        authors = "Giorgio Calderone",
        format=DocumenterVitepress.MarkdownVitepress(;
        repo = "https://github.com/gcalderone/Gnuplot.jl", 
            devurl = "dev",
            devbranch = "master"
            ),
         # format = Documenter.HTML(prettyurls = false),  # uncomment for local use, comment for deployment
        modules=[Gnuplot],
        checkdocs=:exports,
        source="src", 
        build="build",
        warnonly = true,
        # pages = [
        #     "Home" => "index.md",
        #     "Installation" => "install.md",
        #     "Basic usage" => "basic.md",
        #     "Style guide" => "style.md",
        #     "Examples" => "examples.md",
        #     "Advanced usage" => [
        #         "Advanced" => "advanced.md",
        #         "Plot recipes" => "recipes.md",
        #         "Gnuplot terminals" => "terminals.md",
        #         "Package options" => "options.md",
        #         ],
        #     "API" => "api.md"
        #  ]
         )
