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
    return
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
    return
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

#=
read!
readeach
peek (buffered readers only)
copyline (buffered readers only)
readline (buffered readers only)
readlines (buffered readers only)
eachline (buffered readers only)
readuntil (buffered readers only)
copyuntil (buffered readers only)
=#
