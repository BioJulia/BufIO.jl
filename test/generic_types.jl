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

    GenericBufReader(x) =  new(CursorReader(x))
end

BufIO.get_buffer(x::GenericBufReader) = get_buffer(x.x)
BufIO.consume(x::GenericBufReader, n::Int) = consume(x.x, n)
BufIO.fill_buffer(x::GenericBufReader) = fill_buffer(x.x)