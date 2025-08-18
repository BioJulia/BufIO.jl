module BufIO

using MemoryViews: ImmutableMemoryView, MutableMemoryView, MemoryView

export AbstractBufReader,
    BufReader,
    LineIterator,
    IOError,
    IOErrorKinds,
    get_buffer,
    fill_buffer,
    consume,
    read_into!,
    read_all!,
    line_views

public ConsumeBufferError, LineViewIterator

module IOErrorKinds
    """
        IOErrorKind

    Enum indicating what error was thrown. The current list is non-exhaustive, and
    more may be added in future releases.
    """
    @enum IOErrorKind::UInt8 begin
        ConsumeBufferError
    end
end

using .IOErrorKinds: IOErrorKind, ConsumeBufferError

"""
    IOError

This type is thrown by errors of AbstractBufReader.
They contain the `.kind::IOErrorKind` public property.
"""
struct IOError
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
    abstract type BufReader <: Any end

A `BufReader` is an IO type that exposes a buffer to the user, thereby
allowing efficient IO.

!!! warning
    By default, subtypes of `BufReader` are **not threadsafe**, so concurrent usage
    should protect the io behind a lock.

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
  whichever is first, returning the number of bytes read. This causes UB only if `p` is no
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
"""
abstract type AbstractBufReader end

"""
    get_buffer(io::AbstractBufReader)::ImmutableMemoryView{UInt8}

Get the available bytes of `io`.

Calling this function when the buffer is empty should not attempt to fill the buffer.
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
    consume(io::AbstractBufReader, n::Int)::Nothing

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
    iszero(fill_buffer(x)) && return nothing
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

function copyto_start!(dst::MutableMemoryView{T}, src::ImmutableMemoryView{T})::Int where {T}
    mn = min(length(dst), length(src))
    copyto!(dst[begin:mn], src[begin:mn])
    return mn
end

include("base.jl")
include("bufreader.jl")
include("lineiterator.jl")

end # module BufIO
