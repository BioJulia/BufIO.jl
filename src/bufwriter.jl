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

function get_buffer(x::BufWriter, min_size::Int)
    buffer = get_buffer(x)
    length(buffer) >= min_size && return buffer
    return get_buffer_slowpath(x, length(buffer), min_size)
end

@noinline function get_buffer_slowpath(x::BufWriter, bufferlen::Int, min_size::Int)
    expand_buffer(x, min_size - bufferlen)
    buffer = get_buffer(x)
    @assert length(buffer) >= min_size
    return buffer
end

function Base.flush(x::BufWriter)
    if x.first_unused_index > 1
        used = @inbounds ImmutableMemoryView(x.buffer)[1:(x.first_unused_index - 1)]
        write(x.io, used)
        x.first_unused_index = 1
    end
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

function expand_buffer(x::BufWriter, additional::Int)
    additional < 1 && return true
    n_used = x.first_unused_index - 1
    iszero(n_used) || flush(x)
    if additional > n_used
        x.buffer = Memory{UInt8}(undef, length(x.buffer) - n_used + additional)
    end
    return true
end

function consume(x::BufWriter, n::Int)
    if (n % UInt) > (length(x.buffer) - x.first_unused_index + 1) % UInt
        throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    x.first_unused_index += n
    return nothing
end

#### Base ops

function Base.write(io::BufWriter, mem::ImmutableMemoryView{UInt8})
    isempty(mem) && return 0
    remaining = mem
    while !isempty(remaining)
        buffer = get_buffer(io)
        if isempty(buffer)
            flush(io)
            buffer = get_buffer(io)
        end
        mn = min(length(buffer), length(remaining))
        @assert mn > 0
        copyto!(buffer, @inbounds remaining[1:mn])
        consume(io, mn)
        remaining = @inbounds remaining[(mn + 1):end]
    end
    return length(mem)
end

# Fallback method using a temporary buffer
function Base.write(io::BufWriter, x1, xs...)
    buf = IOBuffer()
    write(buf, x1)
    for x in xs
        write(buf, x)
    end
    return write(io, ImmutableMemoryView(take!(buf)))
end
