struct LineViewIterator{T <: AbstractBufReader}
    reader::AbstractBufReader
    chomp::Bool
end

"""
    line_views(x::AbstractBufReader; chomp::Bool=true)

Create an efficient, stateful iterator of lines of `x`.

Lines are defined as all data up to and including a trailing newline (\\n, byte `0x0a`).
If there is data after the last `\\n`, this is considered the last line.

If the input is empty, this iterator is also empty.
Otherwise, if the input does not contain any newlines, this iterator
contains exactly one element, consisting of the entirety of the input data.

The lines are iterated as `ImmutableMemoryView{UInt8}`. Use the package StringViews.jl
to turn them into `AbstractString`s. The `chomp` keyword (default: true), controls whether
any trailing `\\r\\n` or `\\n` should be removed from the output.

The returned views are views into `x`, and are invalidated when the line iterator is
mutated.
If `x` had a limited buffer size, and an entire line cannot be kept in the buffer, an
`ArgumentError` is thrown.

The resulting iterator will not close `x` when done - `x` must be closed after
the iterator is used.
"""
function line_views(x::AbstractBufReader; chomp::Bool = true)
    return LineViewIterator{typeof(x)}(x, chomp)
end

Base.eltype(::Type{<:LineViewIterator}) = ImmutableMemoryView{UInt8}
Base.IteratorSize(::Type{<:LineViewIterator}) = Base.SizeUnknown()

function Base.iterate(x::LineViewIterator, state::Int = 0)
    # Consume data from previous line
    state > 0 && consume(x.reader, state)

    pos = buffer_until(x.reader, 0x0a)
    if pos isa HitBufferLimit
        throw(ArgumentError("Could not buffer a whole line!"))
    elseif pos === nothing
        # No more newlines until EOF. Close as we reached EOF
        buffer = get_buffer(x.reader)
        # If no bytes, do not emit
        return isempty(buffer) ? nothing : (buffer, length(buffer))
    else
        buffer = get_buffer(x.reader)
        line_view = buffer[1:pos]
        if x.chomp
            line_view = _chomp(line_view)
        end
        return (line_view, pos)
    end
end

struct EachLine{T <: AbstractBufReader}
    x::LineViewIterator{T}
end

Base.eltype(::Type{<:EachLine}) = String
Base.IteratorSize(::Type{<:EachLine}) = Base.SizeUnknown()

function Base.iterate(x::EachLine, _::Nothing = nothing)
    it = iterate(x.x)
    isnothing(it) && return nothing
    (view, state) = it
    consume(x.x.reader, state)
    return (String(view), nothing)
end

function Base.eachline(x::AbstractBufReader; keep::Bool = false)
    return EachLine{typeof(x)}(line_views(x; chomp = keep))
end
