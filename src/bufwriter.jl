"""
    BufWriter{T <: IO} <: AbstractBufWriter
    BufWriter(io::IO, [buffer_size::Int])::BufWriter

Wrap an `IO` in a struct with a new buffer, giving it the `AbstractBufWriter` interface.

The `BufWriter` has an infinitely growable buffer, and will only expand the buffer if `grow_buffer`
is called on it while it does not contain any data (as shown by `get_unflushed`).

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

julia> get_unflushed(wtr)
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

function get_nonempty_buffer(x::BufWriter, min_size::Int)
    n_avail = length(x.buffer) - x.first_unused_index + 1
    n_avail ≥ min_size && return get_buffer(x)
    return _get_nonempty_buffer(x, min_size)
end

@noinline function _get_nonempty_buffer(x::BufWriter, min_size::Int)
    shallow_flush(x)
    length(x.buffer) ≥ min_size && return get_buffer(x)
    # Note: If min_size is negative, we would have taken the branch above
    # so this cast is safe
    new_size = overallocation_size(min_size % UInt)
    x.buffer = Memory{UInt8}(undef, new_size)
    return get_buffer(x)
end

function get_unflushed(x::BufWriter)::MutableMemoryView{UInt8}
    return @inbounds MemoryView(x.buffer)[1:(x.first_unused_index - 1)]
end

"""
    shallow_flush(io::AbstractBufWriter)::Int

Clear the buffer(s) of `io` by writing to the underlying I/O, but do not
flush the underlying I/O.
Return the number of bytes flushed.

```jldoctest
julia> io = IOBuffer();

julia> wtr = BufWriter(io);

julia> write(wtr, "hello!");

julia> take!(io)
UInt8[]

julia> shallow_flush(wtr)
6

julia> String(take!(io))
"hello!"
```
"""
function shallow_flush(x::BufWriter)::Int
    to_flush = x.first_unused_index - 1
    if !iszero(to_flush)
        used = @inbounds ImmutableMemoryView(x.buffer)[1:to_flush]
        write(x.io, used)
        x.first_unused_index = 1
    end
    return to_flush
end

function grow_buffer(x::BufWriter)
    flushed = @inline shallow_flush(x)
    return iszero(flushed) ? grow_buffer_slowpath(x) : flushed
end

@noinline function grow_buffer_slowpath(x::BufWriter)
    # We know we have no data to flush
    old_size = length(x.buffer)
    new_size = overallocation_size(old_size % UInt)
    new_memory = Memory{UInt8}(undef, new_size)
    x.buffer = new_memory
    return new_size - old_size
end

"""
    resize_buffer(io::Union{BufWriter, BufReader}, n::Int) -> io

Resize the internal buffer of `io` to exactly `n` bytes.

Throw an `ArgumentError` if `n` is less than 1, or lower than the currently
number of buffered bytes (length of `get_unflushed` for `BufWriter`, length of
`get_buffer` for `BufReader`).

```jldoctest
julia> w = BufWriter(IOBuffer());

julia> write(w, "abc")
3

julia> length(get_buffer(resize_buffer(w, 5)))
2

julia> resize_buffer(w, 2)
ERROR: ArgumentError: Buffer size smaller than current number of buffered bytes
[...]

julia> shallow_flush(w)
3

julia> resize_buffer(w, 2) === w
true
```
"""
function resize_buffer(x::BufWriter, n::Int)
    length(x.buffer) == n && return x
    n < 1 && throw(ArgumentError("Buffer size must be at least 1"))
    n_buffered = x.first_unused_index - 1
    if n < n_buffered
        throw(ArgumentError("Buffer size smaller than current number of buffered bytes"))
    end
    new_buffer = Memory{UInt8}(undef, n)
    if !iszero(n_buffered)
        dst = @inbounds MemoryView(new_buffer)[1:n_buffered]
        src = @inbounds MemoryView(x.buffer)[1:n_buffered]
        @inbounds copyto!(dst, src)
    end
    x.buffer = new_buffer
    return x
end

"""
    flush(io::AbstractBufWriter)::Nothing

Ensure that all intermediate buffered writes in `io` reaches their final destination.

For writers with an underlying I/O, the underlying I/O should also be flushed.

For writers without an underlying I/O, where the final writing destination is `io`
ifself, the implementation may be simply `return nothing`.
"""
function Base.flush(x::BufWriter)
    @inline shallow_flush(x)
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
