"""
    CursorReader(x) <: AbstractBufReader

A stateful reader of the content of any object `x` which implements
`MemoryView(x)::MemoryView{UInt8}`.

A `CursorReader` supports seeking, but not writing. Closing it does nothing.

```jldoctest
julia> rdr = CursorReader("some\\ncontent\\nhere");

julia> readline(rdr)
"some"

julia> read(rdr, String)
"content\\nhere"

julia> seek(rdr, 8);

julia> read(rdr, String)
"tent\\nhere"
```
"""
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

Base.position(x::CursorReader) = x.i - 1

"""
    filesize(io::AbstractBufReader)::Int

Get the total size, in bytes, which can be read by `io`, and the span in which
`io` can be seeked. Types implementing `filesize` should also implement `seek`.

The filesize does not depend on the current reading state of the `io`, i.e.
reading bytes should not change the filesize.
"""
Base.filesize(x::CursorReader) = length(x.data)

function consume(x::CursorReader, n::Int)
    @boundscheck if (n % UInt) > (length(x.data) - x.i + 1) % UInt
        throw(IOError(IOErrorKinds.ConsumeBufferError))
    end
    x.i += n
    return nothing
end

Base.close(::CursorReader) = nothing

function Base.seek(x::CursorReader, offset::Integer)
    offset = Int(offset)::Int
    in(offset, 0:filesize(x)) || throw(IOError(IOErrorKinds.BadSeek))
    x.i = clamp(offset, 0, length(x.data)) + 1
    return x
end
