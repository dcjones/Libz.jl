__precompile__()

module Libz

export GzipInflateInputStream, GzipDeflateInputStream,
       RawInflateInputStream, RawDeflateInputStream,
       ZlibInflateInputStream, ZlibDeflateInputStream,
       GzipInflateOutputStream, GzipDeflateOutputStream,
       ZlibInflateOutputStream, ZlibDeflateOutputStream,
       RawInflateOutputStream, RawDeflateOutputStream,
       adler32, crc32

using BufferedStreams, Compat

include("lowlevel.jl")
include("state.jl")
include("source.jl")
include("sink.jl")
include("checksums.jl")

function deflate(data::Vector{UInt8})
    return read(ZlibDeflateInputStream(data))
end

const compress = deflate

function inflate(data::Vector{UInt8})
    return read(ZlibInflateInputStream(data))
end

const decompress = inflate

end # module Libz
