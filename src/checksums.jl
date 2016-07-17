"""
    crc32(data)

Compute the CRC-32 checksum over the `data` input. `data` can be
`BufferedInputStream` or `Vector{UInt8}`.
"""
function crc32 end

function crc32(stream::BufferedInputStream)
    crc = _crc32()
    while !eof(stream)
        crc = _crc32(crc, pointer(stream.buffer), stream.available)
        stream.position = 1
        stream.available = 0
        BufferedStreams.fillbuffer!(stream)
    end
    return crc::UInt32
end

function crc32(data::Vector{UInt8})
    return _crc32(_crc32(), pointer(data), length(data))::UInt32
end


"""
    adler32(data)

Compute the Adler-32 checksum over the `data` input. `data` can be
`BufferedInputStream` or `Vector{UInt8}`.
"""
function adler32 end

function adler32(stream::BufferedInputStream)
    adler = _adler32()
    while !eof(stream)
        adler = _adler32(adler, pointer(stream.buffer), stream.available)
        stream.position = 1
        stream.available = 0
        BufferedStreams.fillbuffer!(stream)
    end
    return adler::UInt32
end

function adler32(data::Vector{UInt8})
    return _adler32(_adler32(), pointer(data), length(data))::UInt32
end
