using Documenter, BufferIO

DocMeta.setdocmeta!(BufferIO, :DocTestSetup, :(using BufferIO); recursive = true)

makedocs(;
    sitename = "BufferIO.jl",
    modules = [BufferIO],
    pages = [
        "BufferIO" => "index.md",
        "Readers" => "readers.md",
        "Writers" => "writers.md",
        "Types" => "types.md",
        "API reference" => "reference.md",
        "Examples" => "examples.md",
    ],
    authors = "Jakob Nybo Nissen",
    checkdocs = :public,
    remotes = nothing,
)

deploydocs(;
    repo = "github.com/BioJulia/BufferIO.jl.git",
    push_preview = true,
    deps = nothing,
    make = nothing,
)
