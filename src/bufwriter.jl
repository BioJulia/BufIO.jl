"""
    BufWriter{T <: IO} <: AbstractBufWriter
    BufWriter(io::IO, [buffer_size::Int])::BufWriter

Wrap an `IO` in a struct with its own buffer, giving it the `AbstractBufReader` interface.
Errors when passed a buffer size of zero.

The `BufWriter` has an infinitely growable buffer, and will expand the buffer after flushing
if more bytes are requested only grow the buffer if
the buffer is full.
"""
mutable struct BufWriter{T <: IO} <: AbstractBufWriter
    io::T
    buffer::Memory{UInt8}
    first_unused_index::Int
    is_closed::Bool

    function BufWriter{T}(io::T, mem::Memory{UInt8}) where {T <: IO}
        if isempty(mem)
            throw(ArgumentError("BufReader cannot be created with empty buffer"))
        end
        return new{T}(io, mem, 1, false)
    end
end

function BufWriter(io::IO, buffer_size::Int = 4096)
    if buffer_size < 1
        throw(ArgumentError("BufWriter buffer size must be at least 1"))
    end
    mem = Memory{UInt8}(undef, buffer_size)
    return BufWriter{typeof(io)}(io, mem)
end

function get_buffer(x::BufWriter)::MutableMemoryView{UInt8}
    return @inbounds MemoryView(x.buffer)[x.first_unused_index:end]
end

function shallow_flush(x::BufWriter)
    if x.first_unused_index > 1
        used = @inbounds ImmutableMemoryView(x.buffer)[1:(x.first_unused_index - 1)]
        write(x.io, used)
        x.first_unused_index = 1
    end
    return nothing
end

function Base.flush(x::BufWriter)
    shallow_flush(x)
    flush(x.io)
    return nothing
end

function Base.close(x::BufWriter)
    x.is_closed && return nothing
    flush(x)
    close(x.io)
    x.is_closed = true
    return nothing
end

function consume(x::BufWriter, n::Int)
    @boundscheck if (n % UInt) > (length(x.buffer) - x.first_unused_index + 1) % UInt
        throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    x.first_unused_index += n
    return nothing
end

#### Base ops

function Base.write(io::BufWriter, mem::ImmutableMemoryView{UInt8})
    remaining = mem
    while !isempty(remaining)
        buffer = get_buffer(io)
        if isempty(buffer)
            shallow_flush(io)
            buffer = get_buffer(io)
        end
        copied = copyto_start!(buffer, remaining)
        @assert !iszero(copied)
        consume(io, copied)
        remaining = @inbounds remaining[(copied + 1):end]
    end
    return length(mem)
end
