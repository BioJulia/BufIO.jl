mutable struct CursorReader <: AbstractBufReader
    data::ImmutableMemoryView{UInt8}
    i::Int

    function CursorReader(x)
        mem = ImmutableMemoryView{UInt8}(x)::ImmutableMemoryView{UInt8}
        return new(mem, 1)
    end
end

fill_buffer(::CursorReader) = 0

get_buffer(x::CursorReader) = x.data[x.i:end]

function consume(x::CursorReader, n::Int)
    if (n % UInt) > (length(x.data) - x.i + 1) % UInt
        throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    x.i += n
    return nothing
end

Base.close(::CursorReader) = nothing

function Base.seek(x::CursorReader, offset::Integer)
    offset = Int(offset)::Int
    x.i = clamp(offset, 0, length(x.data)) + 1
    return x
end
