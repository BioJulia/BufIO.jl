```@meta
CurrentModule = BufIO
DocTestSetup = quote
    using BufIO
end
```

# BufIO.jl
BufIO is an alternative IO interface in Julia inspired by Rust, designed around explicitly copying bytes between buffers. Compared to `Base.IO`, the interfaces in this package are generally:

* Lower level
* Lower overhead (i.e, faster)
* Easier to reason about
* Better specified, with more well-defined semantics
* Free of slow fallback methods that trash your performance

This package also provides types for interfacing between the new buffered IO types, and `Base.IO` types.

## Example
* Low-level example:
```jldoctest
io = IOBuffer("Hello,\nworld!\n") # some IO value
reader = BufReader(io)
fill_buffer(reader)

# Access the buffer in a zero-copy fashion
buffer = get_buffer(reader)
data = UInt8[]

# Copy data from buffer
copy!(data, view(buffer, 1:5))
println(String(data))

# Data is still present in buffer
println(read(reader, String))
close(reader)

# output

Hello
Hello,
world!
```

* Higher level example:

```jldoctest
io = IOBuffer("Hello,\nworld!\n") # some IO value
reader = BufReader(io)
foreach(println, eachline(reader))
close(reader)

# output

Hello,
world!
```

## Overview of content:
* `AbstractBufReader`: A reader type that exposes its internal data as an immutable memory view of bytes
* `AbstractBufWriter`: A writer type that allows writing to it by copying data to a mutable memory view of its internal buffer
* `BufReader <: AbstractBufReader`: A type that wraps a `Base.IO` and a buffer
* `BufWriter <: AbstractBufWriter`: A type that wraps a `Base.IO` and a buffer
* `CursorReader <: AbstractBufReader`: Turn any byte memory into a stateful reader
* `IOReader <: Base.IO`: A type that wraps an `AbstractBufReader` but provdes the `Base.IO` interface
* `VecWriter <: AbstractBufReader`: A lower level, faster and simpler analogue of `IOBuffer` used to construct data (e.g. strings) by writing to it

## Design notes and limitations
#### Requires Julia 1.11
BufIO relies heavily on the `Memory` type and associated types introduced in 1.11 for its buffers

#### **Not** threadsafe by default
Locks introduce unwelcome overhead and defeats the purpose of low-level control of your IO. Wrap your IO in a lock if you need thread safety.

#### Separate readers and writers
Unlike `Base.IO` which encompasses both readers and writers, this package has two distinct interfaces for `AbstractBufReader` and `AbstractBufWriter`. This simplifies the interface for most types.

In the unlikely case someone wants to create a type which is both, you can create a base type `T`, wrapper types `R <: AbstractBufReader` and `W <: AbstractBufWriter` and then implement `reader(::T)::R` and `writer(::T)::W`.