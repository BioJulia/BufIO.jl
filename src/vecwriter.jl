# TODO:
# This is probably useful to build strings. Yet there is no API to Base.StringMemory.
# Also, if we use to it build strings, isn't over overallocation overly wasteful?

"""
    VecWriter([len::Int]) <: AbstractBufWriter

Create an `AbstractBufWriter` backed by a growable `Memory{UInt8}`.

If passed, `len` is the initial buffer size, and must be at least 1 byte, else
an `ArgumentError` is thrown. It defaults to a small size.

Use the functions `get_data` or `to_parts` to obtain the data written to the
`VecWriter`. `grow_buffer` will always reallocate the buffer.

Functions `flush` and `close` do not affect the writer.

```jldoctest
julia> vw = VecWriter();

julia> write(vw, "Hello, world!")
13

julia> write(vw, 0xe1fa)
2

julia> mem = get_data(vw); print(typeof(mem))
MemoryViews.MutableMemoryView{UInt8}

julia> String(mem)
"Hello, world!\\xfa\\xe1"
```
"""
mutable struct VecWriter <: AbstractBufWriter
    mem::Memory{UInt8}
    idx::Int

    function VecWriter(len::Int)
        len < 1 && throw(ArgumentError("Must have a length of at least 1"))
        mem = Memory{UInt8}(undef, len)
        return new(mem, 1)
    end
end

const DEFAULT_VECWIRTER_SIZE = 32

VecWriter() = VecWriter(DEFAULT_VECWIRTER_SIZE)

get_buffer(x::VecWriter) = @inbounds MemoryView(x.mem)[x.idx:end]
get_data(x::VecWriter) = @inbounds MemoryView(x.mem)[1:(x.idx - 1)]

function consume(x::VecWriter, n::Int)
    @boundscheck if (x.idx % UInt) + (n % UInt) > (length(x.mem) + 1) % UInt
        throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    return x.idx += n
end

function grow_buffer(io::VecWriter)
    current_size = length(io.mem)
    new_size = overallocation_size(max(64, current_size) % UInt)
    _reallocate!(io, new_size)
    return new_size - current_size
end

Base.close(::VecWriter) = nothing
Base.flush(::VecWriter) = nothing

"""
    filesize(x::AbstractBufWriter)::Int

Get the total size, in bytes, of data written to `io`. This includes previously flushed data,
and data comitted by `consume` but not flushed.
Types implementing `filesize` should also implement `seek`.
"""
Base.filesize(x::VecWriter) = x.idx

"""
    seek(io::AbstractBufWriter, offset::Int) -> io

Seek `io` to the zero-based position `offset`.

Valid values for `offset` are in `0:filesize(io)`, if `filesize` is defined.
Seeking outside these bounds throws an `IOError` of kind `BadSeek`.

If seeking to before the current position (as defined by `position`), data between
the new and the previous position need not be changed, and the underlying file or IO
need not immediately be truncated. However, new write operations should write (or
overwrite) data at the new position.

This method is not generically defined for `AbstractBufReader`. Implementors of `seek`
should also define `filesize(io)` and `position(io)`
"""
function Base.seek(x::VecWriter, offset::Int)
    @boundscheck if !in(offset, 0:filesize(x))
        throw(IOError(IOErrorKinds.BadSeek))
    end
    x.idx = offset + 1
    return x
end

Base.position(x::VecWriter) = x.idx - 1

"""
    sizehint!(x::VecWriter, n::Integer; shrink::Bool=false, exact::Bool=false)

Set the total buffer size (written plus unwritten) to at least `n`.
If `shrink` is `false` (default) the existing size is larger than or equal to `n`,
do nothing. If `shrink` is true, and the buffer length equal `n`, or `n` or more
bytes has already be written to `x`, do nothing.

Otherwise, re-allocate the buffer of `x`. If `exact` is `true` or `shrink` is `true`,
resize the buffer to exactly `n`. Otherwise, possibly overallocate. 
"""
function Base.sizehint!(x::VecWriter, n::Integer; shrink::Bool = true, exact::Bool = false)
    n = Int(n)::Int
    mem = x.mem
    memsize = if !shrink
        length(mem) ≥ n && return x
        exact ? n : overallocation_size(n)
    else
        (length(mem) == n) || (x.idx - 1 ≥ n) && return x
        n
    end
    return @noinline _reallocate!(x, memsize)
end

function _reallocate!(x::VecWriter, memsize::Int)
    newmem = Memory{UInt8}(undef, memsize)
    unsafe_copyto!(newmem, 1, x.mem, 1, min(x.idx - 1, memsize))
    x.mem = newmem
    return x
end


"""
    to_parts(x::VecWriter)::Tuple{Memory{UInt8}, Int}

Return `(mem, i)`, the full memory backing `x`, and the number of bytes written to the memory.
The first `i` bytes of the memory `mem` is filled, and corresponds to `get_data(x)`.

Mutating `mem` may cause `x` to behave erratically, so this function should mostly be used
when `x` is not used anymore.

See also: [`get_data`](@ref)

# Examples
```jldoctest
julia> vw = VecWriter(7);

julia> write(vw, "abcde")
5

julia> (mem, i) = to_parts(vw);

julia> (typeof(mem), length(mem))
(Memory{UInt8}, 7)

julia> mem[1:i] |> print
UInt8[0x61, 0x62, 0x63, 0x64, 0x65]
```
"""
to_parts(x::VecWriter) = (x.mem, x.idx - 1)
