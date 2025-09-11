"""
    BufWriter{T <: IO} <: AbstractBufWriter
    BufWriter(io::IO, [buffer_size::Int])::BufWriter

Wrap an `IO` in a struct with a new buffer, giving it the `AbstractBufReader` interface.

The `BufWriter` has an infinitely growable buffer, and will expand the buffer if `grow_buffer`
is called on it while it does not contain any data (as shown by `get_data`).

Throw an `ArgumentError` if `buffer_size` is < 1.

```jldoctest
julia> io = IOBuffer(); wtr = BufWriter(io);

julia> print(wtr, "Hello!")

julia> write(wtr, [0x1234, 0x5678])
4

julia> read(io) # wtr not flushed
UInt8[]

julia> flush(wtr); seekstart(io); String(read(io))
"Hello!4\\x12xV"

julia> get_data(wtr)
0-element MemoryViews.MutableMemoryView{UInt8}
```
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

function get_data(x::BufWriter)::MutableMemoryView{UInt8}
    return @inbounds MemoryView(x.buffer)[1:(x.first_unused_index - 1)]
end

function grow_buffer(x::BufWriter)
    to_flush = x.first_unused_index - 1
    if !iszero(to_flush)
        used = @inbounds ImmutableMemoryView(x.buffer)[1:to_flush]
        write(x.io, used)
        x.first_unused_index = 1
    end
    return to_flush
end

function Base.flush(x::BufWriter)
    grow_buffer(x)
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
