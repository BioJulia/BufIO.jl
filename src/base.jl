Base.bytesavailable(x::AbstractBufReader) = length(get_buffer(x))

Base.eof(x::AbstractBufReader) = isnothing(get_nonempty_buffer(x))

Base.read(x::AbstractBufReader, ::Type{String}) = String(read(x))

function Base.read(x::AbstractBufReader)
    v = UInt8[]
    while true
        buf = get_nonempty_buffer(x)
        isnothing(buf) && return v
        append!(v, buf)
        @inbounds consume(x, length(buf))
    end
    return v # unreachable
end

"""
    read(io::AbstractBufReader, nb::Integer)

Read at exactly `nb` bytes from `io`, or until end of file, and return the
bytes read as a `Vector{UInt8}`.

Throw an `ArgumentError` if `nb` is negative.
"""
function Base.read(x::AbstractBufReader, nb::Integer)
    nb = Int(nb)::Int
    nb < 0 && throw(ArgumentError("nb cannot be negative"))
    v = UInt8[]
    remaining = nb
    while !iszero(remaining)
        buf = get_nonempty_buffer(x)::Union{Nothing, ImmutableMemoryView{UInt8}}
        isnothing(buf) && return v
        mn = min(length(buf), remaining)
        buf = @inbounds buf[1:mn]
        append!(v, buf)
        @inbounds consume(x, mn)
        remaining -= mn
    end
    return v
end

"""
    unsafe_read(io::AbstractBufReader, ref, nbytes::UInt)::Int

Copy `nbytes` from `io` into `ref`, returning the number of bytes copied.
If `io` reached end of file, stop at EOF.
`ref` is converted to a pointer using `Base.cconvert(Ptr, ref)`

Safety: The user must ensure that the resulting pointer from the `cconvert` is valid,
and points to at least `nbytes` of memory.
"""
function Base.unsafe_read(x::AbstractBufReader, ref, n::UInt)::Int
    GC.@preserve ref begin
        ptr = Ptr{UInt8}(Base.cconvert(Ptr, ref)::Ptr)
        result = unsafe_read(x, ptr, n)
    end
    return result
end

function Base.unsafe_read(x::AbstractBufReader, p::Ptr{UInt8}, n::UInt)::Int
    n_total_read = 0
    while true
        buf = get_nonempty_buffer(x)
        isnothing(buf) && return n_total_read
        L = min(length(buf), n % Int)
        GC.@preserve buf begin
            unsafe_copyto!(p, pointer(buf), L)
        end
        p += L
        @inbounds consume(x, L)
        n_total_read += L
        n -= L
        iszero(n) && return n_total_read
    end
    return n_total_read # unreachable
end

"""
    readavailable(io::AbstractBufReader)::Vector{UInt8}

Read the available bytes of `io` to a new `Vector{UInt8}`, except if zero bytes
are available. In that case, it will attempt to get more bytes exactly once.
If still no bytes are available, `io` is EOF, and the resulting vector is empty.
"""
function Base.readavailable(x::AbstractBufReader)
    buf = get_nonempty_buffer(x)
    isnothing(buf) && return UInt8[]
    result = Vector(buf)
    @inbounds consume(x, length(buf))
    return result
end

"""
    peek(io::AbstractBufReader)::UInt8

Get the next `UInt8` in `io`, without advancing `io`, or throw an `IOError`
containing `IOErrorKinds.EOF` if `io` is EOF.
"""
function Base.peek(x::AbstractBufReader, ::Type{UInt8})
    buffer = get_nonempty_buffer(x)
    if buffer === nothing
        throw(IOError(IOErrorKinds.EOF))
    end
    return first(buffer)
end

"""
    read(io::AbstractBufReader, UInt8)::UInt8

Get the next `UInt8` in `io`, or throw an `IOError` containing `IOErrorKinds.EOF`
if `io` is EOF.
"""
function Base.read(x::AbstractBufReader, ::Type{UInt8})
    res = peek(x, UInt8)
    @inbounds consume(x, 1)
    return res
end

# One based indexing
# Read until EOF or nb
"""
    readbytes!(io::AbstractBufReader, b::AbstractVector{UInt8}, nb::Integer=length(b))::Int

Read at most `nb` bytes from `io` into `b`, returning the number of bytes read.
This function will read zero bytes if and only if `io` is EOF.

`b` must use one-based indexing. The size of `b` will be increased if needed (i.e. if nb is greater than
length(b) and enough bytes could be read), but it will never be decreased.

It is generally preferred to use `read_into!` instead of this method.
"""
function Base.readbytes!(x::AbstractBufReader, b::AbstractVector{UInt8}, nb::Integer = length(b))
    Base.require_one_based_indexing(b)
    nb = Int(nb)::Int
    n_read = 0
    while n_read < nb
        buffer = get_nonempty_buffer(x)
        buffer === nothing && break
        buffer = buffer[1:min(length(buffer), nb - n_read)]
        if n_read >= length(b)
            append!(b, buffer)
        else
            copyto!(b, n_read + 1, buffer, 1, length(buffer))
        end
        n_read += length(buffer)
        @inbounds consume(x, length(buffer))
    end
    return n_read
end

function Base.read!(x::AbstractBufReader, A::AbstractArray{UInt8})
    GC.@preserve A begin
        p = Base.unsafe_convert(Ptr{UInt8}, A)
        unsafe_read(x, p, UInt(sizeof(A)))
    end
    return A
end

# delim is UInt8, if delimiter is not found, copies to end
function Base.copyuntil(out::IO, from::AbstractBufReader, delim::UInt8; keep::Bool = false)
    while true
        buffer = get_nonempty_buffer(from)
        buffer === nothing && return out
        pos = findfirst(==(delim), buffer)
        if pos === nothing
            write(out, buffer)
            @inbounds consume(from, length(buffer))
        else
            write(out, buffer[1:(pos - (!keep))])
            @inbounds consume(from, pos)
            return out
        end
    end
    return out # unreachable
end

"""
    copyline(
        out::Union{IO, AbstractBufWriter},
        from::AbstractBufReader;
        keep::Bool = false
    ) -> out

Copy one line from `from` to `out`, returning `out`.
A line is defined as data up to and including \\n (byte 0x0a), or all remaining data in `from` if no such
byte is present.

If `keep` is `false`, as it is by default, the trailing `\\r\\n` (encoded as 0x0d 0x0a) or `\\n` will not be copied to `out`,
but it will be consumed from `from`.

This function may throw an `IOerror` with `IOErrorKinds.BufferTooShort`, if all the following occurs:
* `keep` is `false`
* The reader has a buffer size of 1
* The reader cannot expand its buffer
* The only byte in the buffer is `\\r` (0x0d). 
"""
function Base.copyline(out::Union{IO, AbstractBufWriter}, from::AbstractBufReader; keep::Bool = false)
    while true
        buffer = get_nonempty_buffer(from)
        buffer === nothing && return out
        # We can't copy over a buffer only containing \r, if !keep,
        # because we can't tell if the next byte is \n and we therefore
        # should remove the \r.
        # So, we fill extra bytes in, and error if we can't
        if length(buffer) == 1 && !keep && first(buffer) == 0x0d
            n_filled = fill_buffer(from)
            if n_filled === nothing
                throw(IOError(IOErrorKinds.BufferTooShort))
            end
            buffer = get_buffer(from)
        end
        pos = findfirst(==(0x0a), buffer)
        if pos === nothing
            write(out, buffer)
            @inbounds consume(from, length(buffer))
        else
            buf = buffer[1:pos]
            buf = keep ? buf : _chomp(buf)
            write(out, buf)
            @inbounds consume(from, pos)
            return out
        end
    end
    return out # unreachable
end


# Fill buffer of `x` until it contains a `byte`, then return the index
# in the buffer of that byte.
# If `x` doesn't contain `byte` until EOF, returned value is nothing.
function buffer_until(x::AbstractBufReader, byte::UInt8)::Union{Int, HitBufferLimit, Nothing}
    scan_from = 1
    buffer = get_nonempty_buffer(x)
    isnothing(buffer) && return nothing
    while true
        pos = findnext(==(byte), buffer, scan_from)
        pos === nothing || return pos
        scan_from = length(buffer) + 1
        n_filled = fill_buffer(x)
        if n_filled === nothing
            return HitBufferLimit()
        elseif iszero(n_filled)
            return nothing
        else
            buffer = get_buffer(x)
        end
    end
    return # unreachable
end

# Different logic than `copyline`, because the destination vector is owned by
# this function, and therefore we can better handle the case where a 1-byte buffer
# ends with \r.
function Base.readline(x::AbstractBufReader; keep::Bool = false)
    v = UInt8[]
    while true
        buffer = get_nonempty_buffer(x)
        buffer === nothing && return String(v)
        pos = findfirst(==(0x0a), buffer)
        if pos === nothing
            append!(v, buffer)
            @inbounds consume(x, length(buffer))
        else
            append!(v, @inbounds buffer[1:pos])
            @inbounds consume(x, pos)
            break
        end
    end
    if !keep
        removed = false
        if !isempty(v) && last(v) == 0x0a
            removed = true
            pop!(v)
        end
        if removed && !isempty(v) && last(v) == 0x0d
            pop!(v)
        end
    end
    return String(v)
end

function Base.readuntil(x::AbstractBufReader, delim::UInt8; keep::Bool = false)
    io = IOBuffer()
    copyuntil(io, x, delim; keep)
    return take!(io)
end

function Base.write(io::AbstractBufWriter, x::UInt8)
    buffer = get_nonempty_buffer(io)
    isnothing(buffer) && throw(IOError(IOErrorKinds.EOF))
    buffer[1] = x
    @inbounds consume(io, 1)
    return 1
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
            @inbounds consume(io, mn)
        end
    end
    return so
end

function Base.write(io::AbstractBufWriter, x::PlainTypes)
    buffer = get_buffer(io)
    # Get buffer at least the size of `x` to enable the fast path, if possible
    if length(buffer) < sizeof(x)
        if !iszero(grow_buffer(io))
            buffer = get_buffer(io)
        end
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

Base.write(io::AbstractBufWriter, v::Union{Memory, Array}) = write(io, ImmutableMemoryView(v))

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
        @inbounds consume(io, n_written - n_written_at_start)
    end
    return sizeof(u)
end

as_unsigned(x::PlainTypes) = as_unsigned(x, Val{sizeof(x)}())
as_unsigned(x, ::Val{1}) = reinterpret(UInt8, x)
as_unsigned(x, ::Val{2}) = reinterpret(UInt16, x)
as_unsigned(x, ::Val{4}) = reinterpret(UInt32, x)
as_unsigned(x, ::Val{8}) = reinterpret(UInt64, x)
as_unsigned(x, ::Val{16}) = reinterpret(UInt128, x)

Base.seekstart(x::Union{AbstractBufReader, AbstractBufWriter}) = seek(x, 0)
Base.seekend(x::Union{AbstractBufReader, AbstractBufWriter}) = seek(x, filesize(x))

Base.print(io::AbstractBufWriter, x) = show(io, x)
Base.print(io::AbstractBufWriter, s::Union{String, SubString{String}}) = (write(io, s); nothing)
