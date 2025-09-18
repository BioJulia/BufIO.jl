struct GenericBufWriter <: AbstractBufWriter
    x::VecWriter
end

GenericBufWriter() = GenericBufWriter(VecWriter())
GenericBufWriter(v::Vector{UInt8}) = GenericBufWriter(VecWriter(v))

BufIO.get_buffer(x::GenericBufWriter) = get_buffer(x.x)
BufIO.consume(x::GenericBufWriter, n::Int) = consume(x.x, n)
BufIO.grow_buffer(x::GenericBufWriter) = grow_buffer(x.x)

Base.flush(x::GenericBufWriter) = flush(x.x)
Base.close(x::GenericBufWriter) = close(x.x)

struct GenericBufReader <: AbstractBufReader
    x::CursorReader

    GenericBufReader(x) = new(CursorReader(x))
end

BufIO.get_buffer(x::GenericBufReader) = get_buffer(x.x)
BufIO.consume(x::GenericBufReader, n::Int) = consume(x.x, n)
BufIO.fill_buffer(x::GenericBufReader) = fill_buffer(x.x)

# This type has a max buffer size so we can check the code paths
# where the buffer size is restricted.
mutable struct BoundedReader <: AbstractBufReader
    x::CursorReader
    buffer_size::Int
    max_size::Int
end

function BoundedReader(mem, max_size::Int)
    max_size < 1 && error("Bad parameterization")
    return BoundedReader(CursorReader(mem), 0, max_size)
end

function BufIO.fill_buffer(x::BoundedReader)
    x.buffer_size == x.max_size && return nothing
    buffer = get_buffer(x.x)
    old = x.buffer_size
    x.buffer_size = min(length(buffer), x.max_size)
    return x.buffer_size - old
end

function BufIO.get_buffer(x::BoundedReader)
    buffer = get_buffer(x.x)
    return buffer[1:min(length(buffer), x.buffer_size)]
end

function BufIO.consume(x::BoundedReader, n::Int)
    in(n, 0:x.buffer_size) || throw(IOError(IOErrors.ConsumeBufferError))
    consume(x.x, n)
    x.buffer_size -= n
    return nothing
end
