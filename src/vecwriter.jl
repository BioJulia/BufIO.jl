"""
    VecWriter([vec::Vector{UInt8}]) <: AbstractBufWriter

Create an `AbstractBufWriter` backed by a `Vector{UInt8}`.
Read the (public) property `.vec` to get the vector back.

This type is useful as an efficient string builder through `String(io.vec)`
or `takestring!(io)` (the latter in Julia 1.13+).

Functions `flush` and `close` do not affect the writer.

Mutating `io` will mutate `vec` and vice versa. Neither `vec` nor `io` will
be invalidated by mutating the other, but doing so may affect the
implicit (non-semantic) behaviour (e.g. memory reallocations or efficiency) of the other.
For example, repeated and interleaved `push!(vec)` and `write(io, x)`
may be less efficient, if one operation has memory allocation patterns
that is suboptimal for the other operation.

```jldoctest
julia> vw = VecWriter();

julia> write(vw, "Hello, world!", 0xe1fa)
15

julia> append!(vw.vec, b"More data");

julia> String(vw.vec)
"Hello, world!\\xfa\\xe1More data"
```
"""
struct VecWriter <: AbstractBufWriter
    vec::Vector{UInt8}

    # Suppress the default constructor that calls `convert`, since we don't
    # want to copy the input vector if the type is wrong
    VecWriter(vec::Vector{UInt8}) = new(vec)
end

get_ref(v::Vector) = Base.cconvert(Ptr, v)

if hasmethod(parent, Tuple{MemoryRef})
    get_memory(v::Vector) = parent(get_ref(v))
else
    get_memory(v::Vector) = get_ref(v).mem
end

# This is faster than Base's method because Base's doesn't
# special-case zero. Also, this method does not handle pointer-ful
# arrays, so is not fully generic over element type.
unsafe_set_length!(v::Vector{UInt8}, n::Int) = setfield!(v, :size, (n,))

# Note: memoryrefoffset is 1-based despite the name
first_unused_memindex(v::Vector{UInt8}) = (length(v) + Core.memoryrefoffset(get_ref(v)))

unused_space(v::Vector{UInt8}) = length(get_memory(v)) - first_unused_memindex(v) + 1

capacity(v::Vector) = length(get_memory(v)) - Core.memoryrefoffset(get_ref(v)) + 1

const DEFAULT_VECWIRTER_SIZE = 32

function VecWriter()
    vec = Vector{UInt8}(undef, DEFAULT_VECWIRTER_SIZE)
    unsafe_set_length!(vec, 0)
    return VecWriter(vec)
end

function get_buffer(x::VecWriter)
    vec = x.vec
    return @inbounds MemoryView(get_memory(vec))[first_unused_memindex(vec):end]
end

"""
    get_nonempty_buffer(
        io::AbstractBufWriter, min_size::Int
    )::Union{Nothing, MutableMemoryView{UInt8}}

Get a nonempty buffer of at least size `min_size`.

This function need not be implemented for subtypes of `AbstractBufWriter` that do not
flush their writes to an underlying IO.

!!! warning
    Use of this functions may cause excessive buffering without flushing,
    which is less efficient than calling the one-argument method in a loop.
    Authors should avoid implementing this method for types capable of flushing.
"""
function get_nonempty_buffer(x::VecWriter, min_size::Int)
    ensure_unused_space!(x.vec, max(min_size, 1) % UInt)
    mem = get_memory(x.vec)
    fst = first_unused_memindex(x.vec)
    memref = @inbounds memoryref(mem, fst)
    len = length(mem) - fst + 1
    return MemoryViews.unsafe_from_parts(memref, len)
end

get_nonempty_buffer(x::VecWriter) = get_nonempty_buffer(x, 1)

get_unflushed(x::VecWriter) = MemoryView(x.vec)

function consume(x::VecWriter, n::Int)
    vec = x.vec
    @boundscheck begin
        # Casting to unsigned handles negative n
        (n % UInt) > (unused_space(vec) % UInt) && throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    veclen = length(vec)
    unsafe_set_length!(vec, veclen + n)
    return nothing
end

function grow_buffer(io::VecWriter)
    initial_capacity = capacity(io.vec)
    @inline add_space_with_overallocation!(io.vec, UInt(1))
    return capacity(io.vec) - initial_capacity
end

# If C = Current capacity (get_unflushed + get_buffer)
# Then makes sure new capacity is overallocation(C + additional).
# Do this by zeroing offset and, if necessary, reallocating memory
function add_space_with_overallocation!(vec::Vector{UInt8}, additional::UInt)
    current_mem = get_memory(vec)
    new_size = overallocation_size(capacity(vec) % UInt + additional)
    new_mem = if length(current_mem) ≥ new_size
        current_mem
    else
        Memory{UInt8}(undef, new_size)
    end
    @inbounds copyto!(@inbounds(MemoryView(new_mem)[1:length(vec)]), MemoryView(vec))
    setfield!(vec, :ref, memoryref(new_mem))
    return nothing
end

# Ensure unused space is at least `space` bytes. Will overallocate
function ensure_unused_space!(v::Vector{UInt8}, space::UInt)
    us = unused_space(v)
    us % UInt ≥ space && return nothing
    space_to_add = space - us
    return @noinline add_space_with_overallocation!(v, space_to_add)
end

Base.close(::VecWriter) = nothing
Base.flush(::VecWriter) = nothing

"""
    filesize(x::AbstractBufWriter)::Int

Get the total size, in bytes, of data written to `io`. This includes previously flushed data,
and data comitted by `consume` but not flushed.
Types implementing `filesize` should also implement `seek`.
"""
Base.filesize(x::VecWriter) = length(x.vec)

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
    unsafe_set_length!(x.vec, offset)
    return x
end

Base.position(x::VecWriter) = filesize(x)

if isdefined(Base, :takestring!)
    Base.takestring!(io::VecWriter) = String(io.vec)
end

## Optimised write implementations
Base.write(io::VecWriter, x::UInt8) = push!(io.vec, x)

function Base.write(io::VecWriter, mem::Union{String, SubString{String}, PlainMemory})
    so = sizeof(mem)
    buffer = get_nonempty_buffer(io, so)
    GC.@preserve buffer mem begin
        unsafe_copyto!(pointer(buffer), Ptr{UInt8}(pointer(mem)), so)
    end
    @inbounds consume(io, so)
    return so
end
