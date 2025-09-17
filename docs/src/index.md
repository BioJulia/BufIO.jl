```@meta
CurrentModule = BufIO
DocTestSetup = quote
    using BufIO
end
```

# BufIO.jl
BufIO provides new and improved I/O interfaces for Julia inspired by Rust, and designed around exposing buffers to users in order to explicitly copy bytes to and from them. Compared to the `Base.IO` interface, the new interfaces in this package are:

* Lower level
* Faster
* Easier to reason about
* Better specified, with more well-defined semantics
* Free from slow fallback methods that silently trash your performance

Beside the new interfaces, BufIO also provides a small set of basic types to make use of the new interface, and/or allow easy interoperation between `Base.IO` types and the new buffered interfaces.

## Overview of content:
* `AbstractBufReader`: A reader type that exposes its internal data as an immutable memory view of bytes
* `AbstractBufWriter`: A writer type that allows writing to it by copying data to a mutable memory view of its internal buffer
* `BufReader <: AbstractBufReader`: A type that wraps a `Base.IO` to provide the `AbstractBufReader` interface
* `BufWriter <: AbstractBufWriter`: A type that wraps a `Base.IO` to provide the `AbstractBufWriter` interface
* `CursorReader <: AbstractBufReader`: Wrap any contiguous, memory of bytes into a stateful reader
* `IOReader <: Base.IO`: A type that wraps an `AbstractBufReader` and provides the `Base.IO` interface
* `VecWriter <: AbstractBufWriter`: A faster and simpler alternative to IOBuffer usable e.g. to build strings.

## Examples
See usage examples in the sidebar to the left

## Design notes and limitations
#### Requires Julia 1.11
BufIO relies heavily on the `Memory` type and associated types introduced in 1.11 for its buffers

#### **Not** threadsafe by default
Locks introduce unwelcome overhead and defeats the purpose of low-level control of your IO. Wrap your IO in a lock if you need thread safety.

#### Separate readers and writers
Unlike `Base.IO` which encompasses both readers and writers, this package has two distinct interfaces for `AbstractBufReader` and `AbstractBufWriter`. This simplifies the interface for most types.

In the unlikely case someone wants to create a type which is both, you can create a base type `T`, wrapper types `R <: AbstractBufReader` and `W <: AbstractBufWriter` and then implement `reader(::T)::R` and `writer(::T)::W`.

#### Limitations on working with strings
`String` is special-cased in Julia, which makes several important optimisations impossible in an external package. Hopefully, these will be removed in future versions of Julia:

* Currently, reading from a `String` allocates. This is because strings are currently not backed by `Memory` and therefore cannot present a `MemoryView`.
  Constructing a memory view from a string requires allocating a new `Memory` object.
  Fortunately, the allocation is small since string need not be copied, but can share storage with the `Memory`.

#### Julia compiler limitation
This package makes heavy use of union-typed return values. These currently [have no ABI support in Julia](https://github.com/JuliaLang/julia/issues/53584), which makes this package significantly less efficient. That limitation will almost certainly be lifted in a future release of Julia.