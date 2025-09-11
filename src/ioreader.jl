"""
    IOReader{T <: AbstractBufReader} <: IO

Wrapper type to convert an `AbstractBufReader` to an `IO`.

`IOReader`s implement the same part of the `IO` interface as `AbstractBufReader`,
so this type is only used to satisfy type constraints.

# Examples
```jldoctest
julia> io = CursorReader("hello");

julia> f(x::IO) = String(read(x));

julia> f(io)
ERROR: MethodError: no method matching f(::CursorReader)
[...]

julia> f(IOReader(io))
"hello"
```
"""
struct IOReader{T <: AbstractBufReader} <: IO
    x::T
end

for f in [
        :bytesavailable,
        :eof,
        :read,
        :readavailable,
        :close,
        :position,
        :filesize,
    ]
    @eval Base.$(f)(x::IOReader) = $(f)(x.x)
end

Base.read(x::IOReader, ::Type{String}) = read(x.x, String)
Base.unsafe_read(x::IOReader, p::Ptr{UInt8}, n::UInt) = unsafe_read(x.x, p, n)
Base.peek(x::IOReader, ::Type{UInt8}) = peek(x.x, UInt8)
Base.read(x::IOReader, ::Type{UInt8}) = read(x.x, UInt8)
Base.read(x::IOReader, n::Integer) = read(x.x, n)
Base.read!(x::IOReader, A::AbstractArray{UInt8}) = read!(x.x, A)
Base.readline(x::IOReader; keep::Bool = false) = readline(x.x; keep)
Base.seek(x::IOReader, n::Integer) = seek(x.x, n)

function Base.readbytes!(x::IOReader, b::AbstractVector{UInt8}, nb::Integer = length(b))
    return readbytes!(x.x, b, nb)
end

function Base.copyuntil(out::IO, from::IOReader, delim::UInt8; keep::Bool = false)
    return copyuntil(out, from.x, delim; keep)
end

function Base.copyline(out::IO, from::IOReader; keep::Bool = false)
    return copyline(out, from.x; keep)
end

function Base.readuntil(x::IOReader, delim::UInt8; keep::Bool = false)
    return readuntil(x.x, delim; keep)
end
