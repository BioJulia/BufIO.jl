Base.bytesavailable(x::AbstractBufReader) = length(get_buffer(x))

Base.eof(x::AbstractBufReader) = isnothing(get_nonempty_buffer(x))

Base.read(x::AbstractBufReader, ::Type{String}) = String(read(x))

function Base.read(x::AbstractBufReader)
    v = UInt8[]
    while true
        buf = get_nonempty_buffer(x)
        isnothing(buf) && return v
        append!(v, buf)
        consume(x, length(buf))
    end
    return v # unreachable
end

# NB: Only safety requirement is that p is a valid pointer with n bytes
# able to be written to it
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
        consume(x, L)
        n_total_read += L
        n -= L
        iszero(n) && return n_total_read
    end
    return n_total_read # unreachable
end

function Base.readavailable(x::AbstractBufReader)
    buf = get_nonempty_buffer(x)
    isnothing(buf) && return UInt8[]
    result = Vector(buf)
    consume(x, length(buf))
    return result
end

function Base.peek(x::AbstractBufReader, ::Type{UInt8})
    buffer = get_nonempty_buffer(x)
    if buffer === nothing
        throw(EOFError())
    end
    return first(buffer)
end

function Base.read(x::AbstractBufReader, ::Type{UInt8})
    res = peek(x, UInt8)
    consume(x, 1)
    return res
end

# One based indexing
# Read until EOF or nb
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
        consume(x, length(buffer))
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
        pos = buffer_until(from, delim)
        buffer = get_buffer(from)
        if pos === nothing
            write(out, buffer)
            consume(from, length(buffer))
            return out
        elseif pos === HitBufferLimit()
            write(out, buffer)
            consume(from, length(buffer))
        else
            buffer = if keep
                buffer[1:pos]
            else
                buffer[1:(pos - 1)]
            end
            write(out, buffer)
            consume(from, pos)
            return out
        end
    end
    return out # unreachable
end

function Base.copyline(out::IO, from::AbstractBufReader; keep::Bool = false)
    while true
        pos = buffer_until(from, 0x0a)
        buffer = get_buffer(from)
        if pos === nothing
            # EOF without newline - copy full buffer out
            write(out, buffer)
            consume(from, length(buffer))
            return out
        elseif pos === HitBufferLimit()
            # This would an implementation error in `from`
            @assert !isempty(buffer)
            # If we find an `\r`, the next byte could be `\n`. If it is, we can't copy it out if !keep,
            if !keep && last(buffer) == UInt8('\r')
                # If more than this \r byte, we copy those safe bytes out, and make rorom for more bytes.
                # Thereby, we check if the next byte is \n in the next iteration
                if length(buffer) > 1
                    buffer = buffer[1:(end - 1)]
                else
                    # If the buffer can't be filled, we can't do the right thing, and so we error!
                    throw(ArgumentError("Cannot copy line with !keep and fixed buffersize of 1"))
                end
            end
            # Copy the safe bytes out (not any trailing \r), which we checked above
            # is at least 1 safe byte, then re-fill buffer and continue
            write(out, buffer)
            consume(from, length(buffer))
        else
            # We found a byte!
            to_write = if keep
                buffer
            else
                _chomp(buffer)
            end
            write(out, to_write)
            consume(from, length(buffer))
            return out
        end
    end
    return out # unreachable
end


# Fill buffer of `x` until it contains a `byte`, then return the index
# in the buffer of that byte.
# If `x` doesn't contain `byte` until EOF, returned value is nothing.
function buffer_until(x::AbstractBufReader, byte::UInt8)::Union{Int, HitBufferLimit, Nothing}
    buffer = get_nonempty_buffer(x)
    isnothing(buffer) && return nothing
    buffer_length = length(buffer)
    scan_from = 1
    while true
        pos = findnext(==(byte), buffer, scan_from)
        pos === nothing || return pos
        n_filled = fill_buffer(x)
        if n_filled === nothing
            return HitBufferLimit()
        elseif iszero(n_filled)
            return nothing
        else
            buffer = get_buffer(x)
            scan_from = buffer_length + 1
            buffer_length = length(buffer)
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
        pos = buffer_until(x, 0x0a)
        buffer = get_buffer(x)
        if pos === nothing
            append!(v, buffer)
            consume(x, length(buffer))
            break
        elseif pos === HitBufferLimit()
            append!(v, buffer)
            consume(x, length(buffer))
        else
            buffer = buffer[1:pos]
            append!(v, buffer)
            consume(x, length(buffer))
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
    isempty(buffer) && error("Buffer not long enough, bad implementation of get_buffer")
    @inbounds buffer[1] = x
    @inbounds consume(io, 1)
    return 1
end
