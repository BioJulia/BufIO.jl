```@meta
CurrentModule = BufIO
DocTestSetup = quote
    using BufIO
end
```

# `AbstractBufWriter`
## Core, low-level interface
The core interface of `AbstractBufWriter` consists of the same three functions as `AbstractBufReader`, with analogous meaning. So, first familiarize yourself with that interface.

The main differences between the reader and writer interface are:
* `get_buffer(io)` returns a mutable view into the part of the buffer which is unused. Data is written to `io` by copying to the first bytes of the buffer, then calling `consume`.
* `grow_buffer(io)` may get more space by flushing comitted data from the buffer to the underlying IO. It cannot return `nothing`.
* `consume(io, n::Int)` signals that the first `n` bytes in the buffer are now "comitted" to `io`, and will not be returned from future calls to `get_buffer`.

## Example: Writing `v::Vector{UInt8}` to an `AbstractBufWriter`
There already is an existing method defined for `AbstractBufWriter` used when calling `write(io, v)`, but how would this be implemented in terms of the core primitives above?

First, let's define it in terms of `ImmutableMemoryView`, and then forward the `Vector` method to the memory one.

```julia
using MemoryViews

my_write(io::AbstractBufWriter, v::Vector{UInt8}) = my_write(io, ImmutableMemoryView(v))

function my_write(io::AbstractBufWriter, mem::ImmutableMemoryView{UInt8})::Int
    n_bytes = length(mem)
    while !isempty(mem)
        # Get mutable buffer with uninitialized data to write to
        buffer = get_buffer(io)::MutableMemoryView{UInt8}
        if isempty(buffer)
            # grow_buffer cannot return `nothing`, unlike for readers, but the writer
            # may still be unable to add more bytes (in which case grow_buffer returns
            # zero). A real implementation would use a better error
            iszero(grow_buffer(io)) && error("Could not flush")
            buffer = get_buffer(io)::MutableMemoryView{UInt8}
        end
        mn = min(length(mem), length(buffer))
        (to_write, mem) = @inbounds split_at(mem, mn + 1)
        @inbounds copyto!(@inbounds(buffer[1:mn]), to_write)
        # Mark the first `mn` bytes of the buffer as being committed, thereby
        # actually writing it to `io`
        @inbounds consume(io, mn)
    end
    return n_bytes
end
```

```@docs; canonical=false
get_buffer
grow_buffer
consume
```

## Notable `AbstractWriter` functions
```@docs; canonical=false
get_data
```