"""
    BufReader{T <: IO} <: AbstractBufReader
    BufReader(io::IO, [buffer_size::Int])

Wrap an `IO` in a struct with its own buffer, giving it the `AbstractBufReader` interface.
Errors when passed a buffer size of zero.

The `BufReader` has an infinitely growable buffer, and will only grow the buffer if
the buffer is full.
"""
mutable struct BufReader{T <: IO} <: AbstractBufReader
    const io::T
    buffer::Memory{UInt8}
    start::Int
    stop::Int

    function BufReader{T}(io::T, mem::Memory{UInt8}) where {T <: IO}
        if isempty(mem)
            throw(ArgumentError("BufReader cannot be created with empty buffer"))
        end
        return new{T}(io, mem, 1, 0)
    end
end

function BufReader(io::IO, buffer_size::Int = 8192)
    if buffer_size < 1
        throw(ArgumentError("BufReader buffer size must be at least 1"))
    end
    mem = Memory{UInt8}(undef, buffer_size)
    return BufReader{typeof(io)}(io, mem)
end

function get_buffer(x::BufReader)::ImmutableMemoryView{UInt8}
    return ImmutableMemoryView(x.buffer)[x.start:x.stop]
end

function fill_buffer(x::BufReader)::Int
    eof(x.io) && return 0

    # If buffer is exhausted, we reset start and stop
    if x.start > x.stop
        x.start = 1
        x.stop = 0
    end

    # Add more bytes at the end, if possible
    if x.stop < length(x.buffer)
        n_added = 0
        while n_added == 0
            n_added = readbytes!(x.io, MemoryView(x.buffer)[(x.stop + 1):length(x.buffer)])
        end
        x.stop += n_added
        return n_added
    else
        return fill_buffer_slowpath(x)
    end
end

@noinline function fill_buffer_slowpath(x::BufReader)::Int
    # We now know underlying IO is not EOF, and there is no more room at the end,
    # and the buffer contains at least 1 byte.

    # If we can move bytes and avoid an allocation, do that
    n_filled = x.stop - x.start + 1
    if x.start > 1
        copyto!(x.buffer, 1, x.buffer, x.start, n_filled)
    else
        # Allocate new buffer.
        # Overallocation scheme copied from Base.
        size = length(x.buffer) % UInt
        exp2 = (8 * sizeof(size) - leading_zeros(size)) % UInt
        size += (1 << div(exp2 * 7, 8)) * 4 + div(size, 8)
        size = max(64, size % Int)
        mem = Memory{UInt8}(undef, size)
        copyto!(mem, 1, x.buffer, x.start, n_filled)
        x.buffer = mem
    end
    # Now fill in the newly freed bytes
    view = MemoryView(x.buffer)[(n_filled + 1):length(x.buffer)]
    @assert !isempty(view)
    n_added = 0
    while n_added == 0
        n_added = readbytes!(x.io, view)
    end
    x.start = 1
    x.stop = n_added + n_filled
    return n_added
end

function consume(x::BufReader, n::Int)
    existing_bytes = x.stop - x.start + 1
    if (existing_bytes % UInt) < (n % UInt)
        throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    x.start += n
    return nothing
end

Base.close(x::BufReader) = close(x.io)

function Base.position(x::BufReader)
    res = Int(position(x.io))::Int - length(get_buffer(x))
    @assert res >= 0
    return res
end

function Base.seek(x::BufReader, position::Int)
    x.start = 1
    x.stop = 0
    return seek(x.io, position)
end
