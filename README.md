# BufIO.jl
This package implements the `AbstractBufReader`, readable IO objects with a better API than Base's `IO`, inspired by Rust's `BufRead` interface.

The package also provides the types `BufReader <: AbstractBufReader{T <: IO}` to wrap an `IO` in this new interface.

## Advantages of `AbstractBufReader` over `IO`
* The provided API is more thoroughly specified than `IO`, including edge case behaviour.
* It is more performant, enabling lower-level control by providing a view into the buffer.

## Current limitations
* `BufReader`s currently do not compose (i.e. you can't wrap one around another).
  This is because they provide the `AbstractBufReader` interface, but wraps an `IO`.
* Currently, there is no `AbstractBufWriter` interface
* Since these are supertypes, it is not possible for a type to be both an `AbstractBufReader` and `AbstractBufWriter`.
