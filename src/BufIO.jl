module BufIO

using MemoryViews: MemoryViews, ImmutableMemoryView, MutableMemoryView, MemoryView

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
    get_data,
    get_nonempty_buffer,
    fill_buffer,
    grow_buffer,
    consume,
    read_into!,
    read_all!,
    line_views,
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
    The integral value of these enums are subject to change in minor versions.

    Current errors:
    * `ConsumeBufferError`: Occurs when calling `consume` with a negative amount of bytes,
      or with more bytes than `length(get_buffer(io))`
    * `EOF`: Occurs when trying a reading operation on a file that has reached end-of-file
    * `BufferTooShort`: Thrown by various functions that require a minimum buffer size, which
      the `io` cannot provide. This should only be thrown if the buffer is unable to grow to
      the required size, and not if e.g. the buffer does not expand because the io is EOF.
    * `BadSeek`: An out-of-bounds seek operation was attempted
    * `PermissionDenied`: Acces was denied to a system (filesystem, network, OS, etc.) resource
    * `NotFound`: Resource was not found, e.g. no such file or directory
    * `BrokenPipe`: The operation failed because a pipe was broken. This typically happens when
       writing to stdout or stderr, which then gets closed.
    * `AlreadyExists`: Resource (e.g. file) could not be created because it already exists
    * `NotADirectory`: Resource is unexpectedly not a directory. E.g. a path contained a non-directory
      file as an intermediate component.
    * `IsADirectory`: Resource is a directory when a non-directory was expected
    * `DirectoryNotEmpty`: Operation cannot succeed because it requires an empty directory
    * `InvalidFileName`: File name was invalid for platform, e.g. too long name, or invalid characters.
    """
    @enum IOErrorKind::UInt8 begin
        ConsumeBufferError
        BadSeek
        EOF
        BufferTooShort
        PermissionDenied
        NotFound
        BrokenPipe
        AlreadyExists
        NotADirectory
        IsADirectory
        DirectoryNotEmpty
        InvalidFileName
    end

    public ConsumeBufferError,
        BadSeek,
        EOF,
        BufferTooShort,
        PermissionDenied,
        NotFound,
        BrokenPipe,
        AlreadyExists,
        NotADirectory,
        IsADirectory,
        DirectoryNotEmpty,
        InvalidFileName
end

using .IOErrorKinds: IOErrorKind

"""
    IOError

This type is thrown by errors of AbstractBufReader.
They contain the `.kind::IOErrorKind` public property.

See also: [`IOErrorKinds.IOErrorKind`](@ref)

# Examples
```jldoctest
julia> rdr = CursorReader("some content");

julia> try
           seek(rdr, 500)
       catch error
           if error.kind == IOErrorKinds.BadSeek
               println(stderr, "Seeking operation out of bounds")
           else
               rethrow()
           end
        end
Seeking operation out of bounds
```
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
    abstract type AbstractBufReader end

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
Subtypes may optionally define the following methods. See their docstring for `BufReader` / `BufWriter`
for details of the implementation:

* `Base.seek`
* `Base.filesize`

Subtypes `T` of this type have implementations for many Base IO methods, but with more precisely
specified semantics. See docstrings of the specific functions of interest.
"""
abstract type AbstractBufReader end

"""
    abstract type AbstractBufWriter end

An `AbstractBufWriter` is an IO-like type which exposes mutable memory
to the user, which can be written to directly.
This can help avoiding intermediate allocations when writing.
For example, integers can usually be written to buffered writers without allocating. 

!!! warning
    By default, subtypes of `AbstractBufWriter` are **not threadsafe**, so concurrent usage
    should protect the instance behind a lock.

Subtypes of this type should not have a zero-sized buffer which cannot expand when calling
`grow_buffer`.

Subtypes `T` of this type should implement at least:

* `get_buffer(io::T)`
* `grow_buffer(io::T)`
* `Base.close(io::T)`
* `Base.flush(io::T)`
* `consume(io::T, n::Int)`

They may optionally implement
* `get_data`

# Extended help

* Methods of `Base.close` should make sure that calling `close` on an already-closed
  object has no visible effects.
* `flush(x::T)` should be implemented, but may simply return `nothing` if there is no
  underlying stream to flush to.
"""
abstract type AbstractBufWriter end

"""
    get_buffer(io::AbstractBufReader)::ImmutableMemoryView{UInt8}

Get the available bytes of `io`.

Calling this function when the buffer is empty should not attempt to fill the buffer.
To fill the buffer, call [`fill_buffer`](@ref).

    get_buffer(io::AbstractBufWriter)::MutableMemoryView{UInt8}

Get the available mutable buffer of `io` that can be written to.

Calling this function when the buffer is empty should not attempt to fill the buffer.
To increase the size of the buffer, call [`grow_buffer`](@ref).
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

!!! warning
    Idiomatically, users should not call `fill_buffer` when the buffer is not empty,
    because doing so forces growing the buffer instead of letting `io` choose an optimal
    buffer size. Calling `fill_buffer` with a nonempty buffer is only appropriate if, for
    algorithmic reasons you need `io` itself to buffer some minimum amount of data.
"""
function fill_buffer(::AbstractBufReader) end

# TODO: Bad name. Need to signal that it may clear or expand the buffer.
"""
    grow_buffer(io::AbstractBufWriter)::Int

Increase the amount of bytes in the writeable buffer of `io` if possible, returning
the number of bytes added. After calling `grow_buffer` and getting `n`,
the buffer obtained by `get_buffer` should have `n` more bytes.

* If there is data in the buffer of `io`, flush it to the underlying io if possible.
* Else, if `io`'s buffer can be expanded, do so.
* Else, return zero

!!! warning
    Idiomatically, users should not call `grow_buffer` when the buffer is not empty,
    because doing so forces growing the buffer instead of letting `io` choose an optimal
    buffer size. Calling `grow_buffer` with a nonempty buffer is only appropriate if, for
    algorithmic reasons you need `io` buffer to be able to hold some minimum amount of data
    before flushing.
"""
function grow_buffer(::AbstractBufWriter) end

"""
    get_data(io::AbstractBufWriter)::MutableMemoryView{UInt8}

Return a view into the buffered data already written to `io`, but not yet flushed
to its underlying IO.
Bytes not appearing in the buffer may not be entirely flushed (as in `Base.flush`)
if there are more layers of buffering in the IO wrapped by `io`, however, the length
of the buffer should give the number of bytes still stored in `io` itself.

Mutating the returned buffer is allowed and should not cause `io` to malfunction.

This function has no default implementation and methods are optionally added to subtypes
of `AbstractBufWriter`
"""
function get_data(::AbstractBufWriter) end

"""
    consume(io::Union{AbstractBufReader, AbstractBufWriter}, n::Int)::Nothing

Remove the first `n` bytes of the buffer of `io`.
Consumed bytes will not be returned by future calls to `get_buffer`.

If n is negative, or larger than the current buffer size,
throw an `IOError` with `ConsumeBufferError` kind.
This check is a boundscheck and may be elided with `@inbounds`.
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
    buf = get_buffer(x)::ImmutableMemoryView{UInt8}
    isempty(buf) || return buf
    # Per the API, fill_buffer is not allowed to return nothing when the buffer
    # is empty, so calling something here is permitted.
    fill_buffer(x)
    buf = get_buffer(x)
    isempty(buf) && return nothing
    return buf
end

"""
    read_into!(x::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int

Read bytes into the beginning of `dst`, returning the number of bytes read.
This function will always read at least 1 byte, except when `dst` is empty,
or `x` is EOF.

This function is defined generically for `AbstractBufReader`. New methods
should strive to do at most one read call to the underlying IO, if `x`
wraps such an `IO`.
"""
function read_into!(x::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int
    isempty(dst) && return 0
    src = get_nonempty_buffer(x)::Union{Nothing, ImmutableMemoryView{UInt8}}
    isnothing(src) && return 0
    n_read = copyto_start!(dst, src)
    @inbounds consume(x, n_read)
    return n_read
end

"""
    read_all!(io::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int

Read bytes into `dst` until either `dst` is filled or `io` is EOF, returning
the number of bytes read.
"""
function read_all!(io::AbstractBufReader, dst::MutableMemoryView{UInt8})::Int
    n_total_read = 0
    while !isempty(dst)
        buf = get_nonempty_buffer(io)::Union{Nothing, ImmutableMemoryView{UInt8}}
        isnothing(buf) && return n_total_read
        n_read_here = copyto_start!(dst, buf)
        n_total_read += n_read_here
        dst = dst[(n_read_here + 1):end]
        @inbounds consume(io, n_read_here)
    end
    return n_total_read
end

#########################

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
Otherwise, call `grow_buffer`, then get the buffer again.
Returns `nothing` if the buffer is still empty.
"""
function get_nonempty_buffer(x::AbstractBufWriter)::Union{Nothing, MutableMemoryView{UInt8}}
    buffer = get_buffer(x)::MutableMemoryView{UInt8}
    isempty(buffer) || return buffer
    grow_buffer(x)
    buffer = get_buffer(x)::MutableMemoryView{UInt8}
    return isempty(buffer) ? nothing : buffer
end

##########################

function copyto_start!(dst::MutableMemoryView{T}, src::ImmutableMemoryView{T})::Int where {T}
    mn = min(length(dst), length(src))
    @inbounds copyto!(@inbounds(dst[begin:mn]), @inbounds(src[begin:mn]))
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
