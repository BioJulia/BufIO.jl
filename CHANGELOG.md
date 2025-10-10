# 0.2.0
Major breaking change.

## Breaking changes
* `VecWriter` no longer wraps a `Vector{UInt8}`, but instead the new, exported type
  `ByteVector`. This is so the code no longer relies on Base internals.
  `ByteVector` is largely backwards compatible with `Vector{UInt8}`, and is
  guaranteed forward compatible. It may be aliased to `Vector{UInt8}` in the future.

## New features
* On Julia 1.11 and 1.12, a new function `takestring!` has been added

# 0.1.1
* Add ClosedIO IOErrorKind
* Document existing method `unsafe_read(::AbstractBufReader, ::Ptr{UInt8}, ::UInt)`
* Fix bug in generic write method
