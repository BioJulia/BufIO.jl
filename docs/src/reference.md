# Reference
```@autodocs
Modules = [BufferIO]
Private = false
Order   = [:type, :function]
```

```@docs
IOErrorKinds.IOErrorKind
IOErrorKinds
Base.unsafe_read(::AbstractBufReader, ::Any, ::UInt)
Base.readavailable(::AbstractBufReader)
Base.peek(x::AbstractBufReader, ::Type{UInt8})
Base.read(x::AbstractBufReader, ::Type{UInt8})
Base.readbytes!(x::AbstractBufReader, b::AbstractVector{UInt8}, nb::Integer = length(b))
Base.copyline(out::Union{IO, AbstractBufWriter}, from::AbstractBufReader; keep::Bool = false)
Base.filesize(::CursorReader)
Base.filesize(::VecWriter)
Base.seek(::BufReader, ::Int)
Base.seek(::VecWriter, ::Int)
Base.skip(::AbstractBufReader, ::Int)
```