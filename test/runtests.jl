using BufIO
using Test
using MemoryViews

include("generic_types.jl")

@testset "Generic reader" begin
    include("generic_reader.jl")
end

@testset "Generic writer" begin
    include("generic_writer.jl")
end

@testset "BufReader" begin
    include("bufreader.jl")
end

@testset "BufReader" begin
    include("bufwriter.jl")
end

@testset "CursorReader" begin
    include("cursor.jl")
end

@testset "LineIterator" begin
    include("lineiterator.jl")
end
