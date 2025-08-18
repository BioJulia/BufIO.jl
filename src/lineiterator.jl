mutable struct LineViewIterator{T <: AbstractBufReader}
    const reader::AbstractBufReader
    const chomp::Bool
    closed::Bool
end

"""
    line_views(x::AbstractBufReader; chomp::Bool=true)

Create an efficient, stateful iterator of lines of `x`.

Lines are defined as all data up to and including a trailing newline (\\n, byte `0x0a`).
Any nonempty data after the last `\\n` is considered the last newline.

If the input data does not contain any newlines, including if the input is empty, this iterator
contains exactly one element, consisting of the entirety of the input data.
Therefore, this iterator always has at least one element.

The lines are iterated as `ImmutableMemoryView{UInt8}`. Use the package StringViews.jl
to turn them into `AbstractString`s. The `chomp` keyword (default: true), controls whether
any trailing `\\r\\n` or `\\n` should be removed from the output.

The returned views are views into `x`, and are invalidated when the line iterator is
mutated.
If `x` had a limited buffer size, and an entire line cannot be kept in the buffer, an
`ArgumentError` is thrown.

A the resulting iterator takes ownership of `x`, and so `x` should not be mutated after the construction
of the iterator. Use `close(it)` on the iterator to close the underlying reader.
"""
function line_views(x::AbstractBufReader; chomp::Bool = true)
    return LineViewIterator{typeof(x)}(x, chomp, false)
end

Base.eltype(::Type{<:LineViewIterator}) = ImmutableMemoryView{UInt8}
Base.IteratorSize(::Type{<:LineViewIterator}) = Base.SizeUnknown()

function Base.close(x::LineViewIterator)
    x.closed && return nothing
    close(x.reader)
    x.closed = true
    return nothing
end

function Base.iterate(x::LineViewIterator, state::Int = 0)
    # Closed readers cannot be restarted - this prevents a reader that previously
    # reached EOF from iterating an empty line.
    x.closed && return nothing

    # Consume data from previous line
    state > 0 && consume(x.reader, state)

    pos = buffer_until(x.reader, 0x0a)
    if pos isa HitBufferLimit
        throw(ArgumentError("Could not buffer a whole line!"))
    elseif pos === nothing
        # No more newlines until EOF. Close as we reached EOF
        buffer = get_buffer(x.reader)
        close(x)
        # If no bytes, we emit it only if this is first iteration (state is zero)
        # else we hit the last newline in the previous iteration
        return if isempty(buffer)
            iszero(state) ? (buffer, 0) : nothing
        else
            # Else, we emit the rest of the buffer
            (buffer, length(buffer))
        end
    else
        buffer = get_buffer(x.reader)
        line_view = buffer[1:pos]
        if x.chomp
            line_view = _chomp(line_view)
        end
        return (line_view, pos)
    end
end
