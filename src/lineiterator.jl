struct LineIterator{T <: AbstractBufReader}
    reader::AbstractBufReader
    chomp::Bool
end

"""
    LineIterator(x::AbstractBufReader; chomp::Bool=true)

Create an efficient iterator of lines of `x`.

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

A `LineIterator` takes ownership of `x`, and so `x` should not be mutated after the construction
of the `LineIterator`. Use `close(::LineIterator)` to close the underlying reader.
"""
function LineIterator(x::AbstractBufReader; chomp::Bool = true)
    return LineIterator{typeof(x)}(x, chomp)
end

Base.IteratorEltype(::Type{<:LineIterator}) = ImmutableMemoryView{UInt8}
Base.IteratorSize(::Type{<:LineIterator}) = Base.SizeUnknown()

Base.close(x::LineIterator) = close(x.reader)

function chomp(x::ImmutableMemoryView{UInt8})::ImmutableMemoryView{UInt8}
    len = if isempty(x)
        0
    else
        has_lf = x[end] == 0x0a
        two_bytes = length(x) > 1
        has_cr = has_lf & two_bytes & (x[length(x) - two_bytes] == 0x0d)
        length(x) - (has_lf + has_cr)
    end
    return x[1:len]
end


# TODO: If end at newline, do NOT emit next line!
function Base.iterate(x::LineIterator, state::Int = -1)
    # Consume data from previous line
    state > 0 && consume(x.reader, state)

    buffer = get_nonempty_buffer(x.reader)
    # If the reader has no data:
    if isnothing(buffer)
        # If this is the first element, return an empty buffer
        if state == -1
            return (get_buffer(x), 0)
        else
            # Else, return nothing
            return nothing
        end
    end

    scan_from = 1
    while true
        # Find the next newline in the buffer
        pos = findnext(==(0x0a), buffer, scan_from)
        if pos === nothing
            # If no newline...
            n_filled = fill_buffer(x)
            if n_filled === nothing
                # ... if we can't add more bytes to the buffer, we can't emit a line
                # so error!
                throw(ArgumentError("Could not buffer a whole line!"))
            elseif iszero(n_filled)
                # Else, if no more bytes to read in, we've reached the end without finding a newline,
                # emit the rest of the data
                return (buffer, length(buffer))
            else
                # Else, if more bytes to get, get them.
                # Do not search from the beginning again for newline
                buffer = get_buffer(x)
                scan_from += n_filled
            end
        else
            # If found a newline, emit it, and chomp it if necessary
            line_view = buffer[1:pos]
            if x.chomp
                line_view = chomp(line_view)
            end
            return (line_view, pos)
        end
    end

    return
end
