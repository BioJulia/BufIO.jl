# BufIO.jl
[![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://biojulia.github.io/BufIO.jl/latest/)
[![Latest Release](https://img.shields.io/github/release/jakobnissen/BinBencherBackend.jl.svg)](https://github.com/BioJulia/BufIO.jl/releases/latest)


BufIO is an alternative IO interface in Julia inspired by Rust, designed around exposing buffers to users for them to explicitly copying to and from.
Compared to `Base.IO`, the interfaces in this package are generally:

* Lower level
* Faster
* Easier to reason about
* Better specified, with more well-defined semantics
* Free from slow fallback methods that trash your performance

This package also provides a basic set of types which allows easy interoperation between `Base.IO` types the new buffered interface.

## Comparison with other packages
#### BufferedStreams.jl
BufferedStreams.jl speeds up the existing `Base.IO` interface for unbuffered types by providing and internal buffer.
However, the package does not provide an interface for reading/writing from the buffer directly,
BufferedStreams also provide concrete types, but no abstract interface.
Finally, it does not attempt to improve on the interface of `Base.IO`.

#### TranscodingStreams.jl
TranscodingStreams.jl provides buffering, but does so through a specific `Buffer` type instead of through an interface.
It is also centered around *transcoding* and not IO in general. Its interface is both more complex and less documented than this package. Finally, it exposes the `Base.IO` interface instead of an alternative interface.

## Questions?
If you have a question about contributing or using BioJulia software, come on over and chat to us on [the Julia Slack workspace](https://julialang.org/slack/), or you can try the [Bio category of the Julia discourse site](https://discourse.julialang.org/c/domain/bio).
