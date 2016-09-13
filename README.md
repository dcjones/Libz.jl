[![Build Status](https://travis-ci.org/BioJulia/Libz.jl.svg?branch=master)](https://travis-ci.org/BioJulia/Libz.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/g3qixt97g6uua5d6?svg=true)](https://ci.appveyor.com/project/Ward9250/libz-jl)
[![codecov.io](http://codecov.io/github/BioJulia/Libz.jl/coverage.svg?branch=master)](http://codecov.io/github/BioJulia/Libz.jl?branch=master)

This is yet another zlib interface for Julia. It's intended to replace the two
prior zlib packages.

  * [GZip.jl](https://github.com/JuliaLang/GZip.jl)
  * [Zlib.jl](https://github.com/dcjones/Zlib.jl)

Both have shortcomings that this package aims to address, specifically:

  * Zlib.jl is very slow.
  * GZip.jl is not as slow as Zlib.jl, but still slower than it could to be.
  * GZip.jl only supports file I/O.
  * GZip.jl doesn't support reading/writing plain zlib data.


## API

This library exports four stream types:

 Type | Description
------| ---------------
 `ZlibInflateOutputStream` | write and decompress data
 `ZlibDeflateOutputStream` | write and compress data
 `ZlibInflateInputStream`  | read and decompress data
 `ZlibDeflateInputStream`  | read and compress data

These work like regular `IO` objects. Each takes as a parameter either in input
or output source.


### Examples

```julia
# read lines from a compressed file
for line in eachline(open("data.txt.gz") |> ZlibInflateInputStream)
    # do something...
end

# write compressed data to a file
io = open("data.txt.gz", "w")
stream = ZlibDeflateOutputStream(io)
for c in rand(UInt8, 10000)
    write(stream, c)
end
close(stream)  # this closes not only `stream` but also `io`

# pointlessly compress and decompress some data (use `read` on v0.5)
readbytes(rand(UInt8, 10000) |> ZlibDeflateInputStream |> ZlibInflateInputStream)
```


## Other functions

There are convenience `Libz.inflate(::Vector{UInt8})` and `Libz.deflate(::Vector{UInt8})`
functions that take a byte array and return another compressed or decompressed
byte array.

Checksum functions are exposed as `Libz.crc32(::Vector{UInt8})` and
`Libz.adler32(::Vector{UInt8})`.

See [BufferedStreams.jl](https://github.com/dcjones/BufferedStreams.jl) for
benchmarks of this library.

Low-level APIs are defined in [src/lowlevel.jl](/src/lowlevel.jl). These
constants and functions are not exported but available if necessary. At the
moment, function wrappers are minimal but feel free to add and send functions
you need as pull requests.
