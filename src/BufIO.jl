module BufIO

using MemoryViews: ImmutableMemoryView, MutableMemoryView, MemoryView

export AbstractBufReader,
    AbstractBufWriter,
    BufReader,
    BufWriter,
    VecWriter,
    IOReader,
    CursorReader,
    IOError,
    IOErrorKinds,
    get_buffer,
    get_nonempty_buffer,
    fill_buffer,
    consume,
    read_into!,
    read_all!,
    line_views,
    take,
    to_parts

public LineViewIterator

"""
    module IOErrorKinds

Used as a namespace for IOErrorKind.
"""
module IOErrorKinds
    """
        IOErrorKind

    Enum indicating what error was thrown. The current list is non-exhaustive, and
    more may be added in future releases.
    """
    @enum IOErrorKind::UInt8 begin
        ConsumeBufferError
        EmptyBuffer
        BadSeek
        EOF
    end

    public ConsumeBufferError, EmptyBuffer, BadSeek, EOF
end

using .IOErrorKinds: IOErrorKind

"""
    IOError

This type is thrown by errors of AbstractBufReader.
They contain the `.kind::IOErrorKind` public property.
"""
struct IOError <: Exception
    kind::IOErrorKind
end

# Internal type!
struct HitBufferLimit end

function _chomp(x::ImmutableMemoryView{UInt8})::ImmutableMemoryView{UInt8}
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


"""
    abstract type AbstractBufReader <: Any end

An `AbstractBufReader` is an IO type that exposes a buffer to the user, thereby
allowing efficient IO.

!!! warning
    By default, subtypes of `AbstractBufReader` are **not threadsafe**, so concurrent usage
    should protect the instance behind a lock.

Subtypes `T` of this type should implement at least:

* `get_buffer(io::T)`
* `fill_buffer(io::T)`
* `consume(io::T, n::Int)`
* `Base.close(io::T)`

# Extended help

* Methods of `Base.close` should make sure that calling `close` on an already-closed
  object has no visible effects. 

Subtypes `T` of this type have implementations for many Base IO methods, but with more precisely
specified semantics:

* `bytesavailable(::T)`
* `eof(::T)`
* `read(::T)` and `read(::T, String)`
* `unsafe_read(x::T, p::Ptr{UInt8}, n::UInt)` will read `n` bytes, or until `x` is EOF,
  whichever is first, returning the number of bytes read. This causes UB only if `p` is not
  a valid pointer with `n` bytes of space or more.
* `readavailable(x::T)` will do exactly one underlying IO call if the buffer is empty,
  zero calls if the buffer is nonempty, and will only return an empty vector if `x` is EOF.
* `read(x::T, UInt8)` and `peek(x::T, UInt8)` will throw an `EOFError` if `x` is EOF.
* `read!(x::T, A::AbstractArray)` requires that `eltype(A) === UInt8`, and that `A` implements
  `sizeof` and can be `unsafe_convert`ed to `Ptr{UInt8}`.
* `readbytes!(x::T, b, n)` requires that `b` is one-based indexed, and will read until `x` is
  EOF or `n` bytes has been read.
* `copyuntil(out::IO, x::T, delim; keep)`, requires that `delim::UInt8`. If `delim` is not found,
  the entire content of `x` it copied to `out`.
* `readuntil(x::T, delim)` requires that `delim::UInt8`
* `copyline`: Throws an `ArgumentError` if the buf reader has an ungrowable buffer size of 1 byte,
  and an `\\r` is encountered, since there is no way to know if this is part of an `\\r\\n` newline.
* `peek(x::T, ::Type{A})` requires that `A === UInt8`
* `eachline(x::T)` does not support `last`, or `Iterators.reverse` and is fully stateful
  (its iterator state is always `nothing`). It does not promise to free its underlying resource
  when being garbage collected.
* `seek(x::T, i::Integer)` will throw an `IOError` if `i` is out of bounds. `i` is zero-indexed.
"""
abstract type AbstractBufReader end

"""
    get_buffer(io::AbstractBufReader)::ImmutableMemoryView{UInt8}

Get the available bytes of `io`.

Calling this function when the buffer is empty should not attempt to fill the buffer.
To fill the buffer, call [`fill_buffer`](@ref).

    get_buffer(io::AbstractBufWriter)::MutableMemoryView{UInt8}

Get the available mutable buffer of `io` that can be written to.

Calling this function when the buffer is empty should not attempt to fill the buffer.
To fill the buffer, call `flush`.
"""
function get_buffer end

"""
    fill_buffer(io::AbstractBufReader)::Union{Int, Nothing}

Fill more bytes into the buffer from `io`'s underlying buffer, returning
the number of bytes added. After calling `fill_buffer` and getting `n`,
the buffer obtained by `get_buffer` should have `n` new bytes appended.

This function must fill at least one byte, except
* If the underlying io is EOF, or there is no underlying io to fill bytes from, return 0
* If the buffer is not empty, and cannot be expanded, return `nothing`.

Buffered readers which do not wrap another underlying IO, and therefore can't fill
its buffer should return 0 unconditionally.
This function should never return `nothing` if the buffer is empty.
"""
function fill_buffer end

"""
    consume(io::Union{AbstractBufReader, AbstractBufWriter}, n::Int)::Nothing

Remove the first `n` bytes of the buffer of `io`.
Consumed bytes will not be returned by future calls to `get_buffer`.
If n is negative, or larger than the current buffer size,
throw an `IOError` with `ConsumeBufferError` kind.
"""
function consume end

######################

"""
    get_nonempty_buffer(x::AbstractBufReader)::Union{Nothing, ImmutableMemoryView{UInt8}}

Get a buffer with at least one byte, if bytes are available.
Otherwise, fill the buffer, and return the newly filled buffer.
Returns `nothing` only if `x` is EOF. 
"""
function get_nonempty_buffer(x::AbstractBufReader)::Union{Nothing, ImmutableMemoryView{UInt8}}
    buf = get_buffer(x)
    isempty(buf) || return buf
    # Per the API, fill_buffer is not allowed to return nothing when the buffer
    # is empty, so calling something here is permitted.
    iszero(something(fill_buffer(x))) && return nothing
    buf = get_buffer(x)
    @assert !isempty(buf)
    return buf
end

"""
    read_into!(x::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int

Read bytes into the beginning of `dst`, returning the number of bytes read.
This function will always read at least 1 bytes, except when `dst` is empty,
or `x` is EOF.

This function should do at most one read call to the underlying IO, if `x`
wraps such an `IO`.
"""
function read_into!(x::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int
    isempty(dst) && return 0
    src = get_nonempty_buffer(x)
    isnothing(src) && return 0
    n_read = copyto_start!(dst, src)
    consume(x, n_read)
    return n_read
end

"""
    read_all!(x::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int

Read bytes into `dst` until either `dst` is filled or `x` is EOF, returning
the number of bytes read.
"""
function read_all!(x::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int
    n_total_read = 0
    while !isempty(dst)
        buf = get_nonempty_buffer(x)
        isnothing(buf) && return n_total_read
        n_read_here = copyto_start!(dst, buf)
        n_total_read += n_read_here
        dst = dst[(n_read_here + 1):end]
        consume(x, n_read_here)
    end
    return n_total_read
end

#########################

"""
    abstract type AbstractBufWriter <: Any end

An `AbstractBufWriter` is an IO-like type which exposes mutable memory
to the user, which can be written to directly.
This can help avoiding intermediate allocations when writing.
For example, integers can usually be written to buffered writers without allocating. 

!!! warning
    By default, subtypes of `AbstractBufWriter` are **not threadsafe**, so concurrent usage
    should protect the instance behind a lock.

Subtypes of this type should have a buffer of at least 1 byte.
That implies that, after calling `flush` on `x::T`, `length(get_buffer(x))`
must return at least 1.

Subtypes `T` of this type should implement at least:

* `get_buffer(io::T)`
* `Base.close(io::T)`
* `Base.flush(io::T)`
* `consume(io::T, n::Int)`

Subtypes `T` of this type have implementations for many Base IO methods, but with more precisely
specified semantics:
* `seek(x::T, i::Integer)` will throw an `IOError` if `i` is out of bounds. `i` is zero-indexed.
"""
abstract type AbstractBufWriter end

# Types where write(io, x) is the same as copying x
const PLAIN_TYPES = (
    Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128,
    Bool,
    Float16, Float32, Float64,
)

const PlainTypes = Union{PLAIN_TYPES...}
const PlainMemory = Union{map(T -> MemoryView{T}, PLAIN_TYPES)...}

"""
    get_nonempty_buffer(x::AbstractBufWriter)::Union{Nothing, MutableMemoryView{UInt8}}

Get a buffer with at least one byte, if bytes are available.
Otherwise, call `flush`, then get the buffer again.
Returns `nothing` if the buffer gotten after flushing is still empty. 
"""
function get_nonempty_buffer(x::AbstractBufWriter)::Union{Nothing, MutableMemoryView{UInt8}}
    buffer = get_buffer(x)
    isempty(buffer) || return buffer
    flush(x)
    buffer = get_buffer(x)
    return isempty(buffer) ? nothing : buffer
end

function Base.write(io::AbstractBufWriter, mem::Union{String, SubString{String}, PlainMemory})
    so = sizeof(mem)
    offset = 0
    GC.@preserve mem begin
        src = Ptr{UInt8}(pointer(mem))
        while offset < so
            buffer = get_nonempty_buffer(io)
            isnothing(buffer) && throw(IOError(IOErrorKinds.EOF))
            isempty(buffer) && error("Invalid implementation of get_nonempty_buffer")
            mn = min(so - offset, length(buffer))
            GC.@preserve buffer unsafe_copyto!(pointer(buffer), src, mn % UInt)
            offset += mn
            src += mn
            consume(io, mn)
        end
    end
    return so
end

function Base.write(io::AbstractBufWriter, x::PlainTypes)
    buffer = get_buffer(io)
    # Get buffer at least the size of `x` to enable the fast path, if possible
    if length(buffer) < sizeof(x)
        flush(io)
        buffer = get_buffer(io)
        length(buffer) < sizeof(x) && return _write_slowpath(io, x)
    end
    # Copy the bits in directly
    GC.@preserve buffer begin
        p = Ptr{typeof(x)}(pointer(buffer))
        unsafe_store!(p, x)
    end
    @inbounds consume(io, sizeof(x))
    return sizeof(x)
end

@noinline function _write_slowpath(io::AbstractBufWriter, x::PlainTypes)
    # We serialize as little endian, so byteswap if machine is big endian
    u = htol(as_unsigned(x))
    n_written = 0
    while n_written < sizeof(u)
        buffer = get_nonempty_buffer(io)
        isnothing(buffer) && throw(IOError(IOErrorKinds.EOF))
        n_written_at_start = n_written
        for i in eachindex(buffer)
            buffer[i] = u % UInt8
            u >>>= 8
            n_written += 1
            n_written == sizeof(u) && break
        end
        consume(io, n_written - n_written_at_start)
    end
    return sizeof(u)
end

Base.@constprop :aggressive @inline function as_unsigned(x::PlainTypes)
    so = sizeof(x)
    return if so == 1
        reinterpret(UInt8, x)
    elseif so == 2
        reinterpret(UInt16, x)
    elseif so == 4
        reinterpret(UInt32, x)
    elseif so == 8
        reinterpret(UInt64, x)
    elseif so == 16
        reinterpret(UInt128, x)
    else
        error("unreachable")
    end
end

Base.seekstart(x::Union{AbstractBufReader, AbstractBufWriter}) = seek(x, 0)

##########################

function copyto_start!(dst::MutableMemoryView{T}, src::ImmutableMemoryView{T})::Int where {T}
    mn = min(length(dst), length(src))
    copyto!(dst[begin:mn], src[begin:mn])
    return mn
end

# Get the new size of a buffer grown from size `size`
# Copied from Base
function overallocation_size(size::UInt)
    exp2 = (8 * sizeof(size) - leading_zeros(size)) % UInt
    size += (1 << div(exp2 * 7, 8)) * 4 + div(size, 8)
    return size = max(64, size % Int)
end

include("base.jl")
include("bufreader.jl")
include("bufwriter.jl")
include("lineiterator.jl")
include("cursor.jl")
include("ioreader.jl")
include("vecwriter.jl")

end # module BufIO
