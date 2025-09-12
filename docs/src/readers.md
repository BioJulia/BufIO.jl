```@meta
CurrentModule = BufIO
DocTestSetup = quote
    using BufIO
end
```

# `AbstractBufReader`
## Core, low-level interface
The core interface of an `io::AbstractBufReader` consists of three functions, that are to be used together:
* `get_buffer(io)` returns a view into the internal buffer with data ready to read. You read from the io by copying.
* `fill_buffer(io)` attempts to append more bytes to the buffer returned by future calls to `get_buffer`
* `consume(io, n::Int)` removes the first `n` bytes of the buffer

While lots of higher-level convenience functions are also defined, nearly all functionality is defined in terms of these three core functions.
See the docstrings of these functions for details and edge cases.

Let's see two use cases to demonstrate how this core interface is used.

### Example: Reading N bytes
Suppose we want a function `read_exact(io::AbstractBufReader, n::Int)` which reads exactly `n` bytes to a new `Vector{UInt8}`, unless `io` hits end-of-file (EOF).

Since `io` itself controls how many bytes are filled with `fill_buffer` (typically whatever is the most efficient), we do this best by calling the functions above in a loop:

```julia
function read_exact(io::AbstractBufReader, n::Int)
    n > -1 || throw(ArgumentError("n must be non-negative"))
    result = sizehint!(UInt[], n)
    remaining = n
    while !iszero(remaining)
        # Get the buffer to copy bytes from in order to read from `io`
        buffer = get_buffer(io)
        if isempty(buffer)
            # Fill new bytes into the buffer. This returns `0` if `io` if EOF,
            # in which case we break to return the result
            iszero(something(fill_buffer(io))) && break
            buffer = get_buffer(io)
        end
        mn = min(remaining, length(buffer))
        append!(result, buffer[mn])
        # Signal to `io` that the first `mn` bytes have already been read,
        # so these should not be output in future calls to `get_buffer`
        consume(io, mn)
        remaining -= mn
    end
    result
end
```

The code above may be simplified by using the convenience function [`get_nonempty_buffer`](@ref)
or the higher level function [`read_all!`](@ref)

### Example: Reading a line without intermediate allocations
This example is different, because to avoid allocations, we need an entire line to be available
in the buffer of the io.
Therefore, this is one of the rare cases where we may need to force `io` to grow its buffer.

```julia
function get_line_view(io::AbstractBufReader)
    scan_from = 1
    while true
        buffer = get_buffer(io)
        pos = findnext(==(UInt8('\n')), buffer, scan_from)
        if pos === nothing
            scan_from = length(buffer) + 1
            n_filled = fill_buffer(io)
            if n_filled === nothing
                # fill_buffer may return nothing if the buffer is not empty,
                # and the buffer cannot be expanded further.
                error("io could not buffer an entire line")
            elseif iszero(n_filled)
                # This indicates EOF, so the line is defined as the rest of the
                # content of `io`
                return buffer
            end
        else
            return buffer[1:pos]
        end
    end
end
```

Functionality similar to the above is provided by the [`line_views`](@ref) iterator.

```@docs; canonical=false
get_buffer
fill_buffer
consume
```

## Notable `AbstractReader` functions
`AbstractBufReader` implements most of the `Base.IO` interface, see the section in the sidebar.
They also have a few special convenience functions:

```@docs; canonical=false
get_nonempty_buffer(::AbstractBufReader)
read_into!
read_all!
```
