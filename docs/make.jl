using Documenter, BufIO

DocMeta.setdocmeta!(BufIO, :DocTestSetup, :(using BufIO); recursive = true)

makedocs(;
    sitename = "BufIO.jl",
    modules = [BufIO],
    pages = [
        "BufIO" => "index.md",
        "Readers" => "readers.md",
        "Writers" => "writers.md",
        "Types" => "types.md",
        "API reference" => "reference.md",
    ],
    authors = "Jakob Nybo Nissen",
    checkdocs = :public,
    remotes = nothing,
)

deploydocs(;
    repo = "github.com/BioJulia/BufIO.jl.git",
    push_preview = true,
    deps = nothing,
    make = nothing,
)
