# Lower-level interface to the zlib library.

if is_windows()
    const zlib = "zlib1"
else
    const zlib = "libz"
end


# Constants
# ---------

# Flush values
const Z_NO_FLUSH      = Cint(0)
const Z_PARTIAL_FLUSH = Cint(1)
const Z_SYNC_FLUSH    = Cint(2)
const Z_FULL_FLUSH    = Cint(3)
const Z_FINISH        = Cint(4)
const Z_BLOCK         = Cint(5)
const Z_TREES         = Cint(6)

# Return codes
const Z_OK            = Cint(0)
const Z_STREAM_END    = Cint(1)
const Z_NEED_DICT     = Cint(2)
const Z_ERRNO         = Cint(-1)
const Z_STREAM_ERROR  = Cint(-2)
const Z_DATA_ERROR    = Cint(-3)
const Z_MEM_ERROR     = Cint(-4)
const Z_BUF_ERROR     = Cint(-5)
const Z_VERSION_ERROR = Cint(-6)

# Compression levels
const Z_NO_COMPRESSION      = Cint(0)
const Z_BEST_SPEED          = Cint(1)
const Z_BEST_COMPRESSION    = Cint(9)
const Z_DEFAULT_COMPRESSION = Cint(-1)

# Compression strategy
const Z_FILTERED         = Cint(1)
const Z_HUFFMAN_ONLY     = Cint(2)
const Z_RLE              = Cint(3)
const Z_FIXED            = Cint(4)
const Z_DEFAULT_STRATEGY = Cint(0)

# Possible values of the data_type field
const Z_BINARY  = Cint(0)
const Z_TEXT    = Cint(1)
const Z_ASCII   = Z_TEXT
const Z_UNKNOWN = Cint(2)

# The deflate compression method
const Z_DEFLATED = Cint(8)

# For initializing zalloc, zfree, opaque
# const Z_NULL = C_NULL


# ZStream
# -------

type ZStream
    next_in::Ptr{UInt8}
    avail_in::Cuint
    total_in::Culong

    next_out::Ptr{UInt8}
    avail_out::Cuint
    total_out::Culong

    msg::Ptr{UInt8}
    state::Ptr{Void}

    zalloc::Ptr{Void}
    zfree::Ptr{Void}
    opaque::Ptr{Void}

    data_type::Cint
    adler::Culong
    reserved::Culong

    function ZStream()
        zstream = new()
        zstream.next_in   = C_NULL
        zstream.avail_in  = 0
        zstream.total_in  = 0
        zstream.next_out  = C_NULL
        zstream.avail_out = 0
        zstream.total_out = 0
        zstream.msg       = C_NULL
        zstream.state     = C_NULL
        zstream.zalloc    = C_NULL
        zstream.zfree     = C_NULL
        zstream.opaque    = C_NULL
        zstream.data_type = 0
        zstream.adler     = 0
        zstream.reserved  = 0
        return zstream
    end
end


# Functions
# ---------

function version()
    return unsafe_string(ccall((:zlibVersion, zlib), Ptr{UInt8}, ()))
end

const zlib_version = version()

const gzip_windowbit_offset = 16

function init_inflate!(zstream::ZStream, windowbits::Integer)
    return ccall(
        (:inflateInit2_, zlib),
        Cint,
        (Ref{ZStream}, Cint, Cstring, Cint),
        zstream, windowbits, zlib_version, sizeof(ZStream))
end

function init_inflate!(zstream::ZStream; windowbits::Integer=15 + 32)
    return init_inflate!(zstream, windowbits)
end

function reset_inflate!(zstream::ZStream)
    return ccall((:inflateReset, zlib), Cint, (Ref{ZStream},), zstream)
end

function end_inflate!(zstream::ZStream)
    return ccall((:inflateEnd, zlib), Cint, (Ref{ZStream},), zstream)
end

function inflate!(zstream::ZStream, flush::Integer)
    return ccall(
        (:inflate, zlib),
        Cint,
        (Ref{ZStream}, Cint),
        zstream, flush)
end

function init_deflate!(zstream::ZStream,
                       level::Integer,
                       method::Integer,
                       windowbits::Integer,
                       memlevel::Integer,
                       strategy::Integer)
    return ccall(
        (:deflateInit2_, zlib),
        Cint,
        (Ref{ZStream}, Cint, Cint, Cint, Cint, Cint, Cstring, Cint),
        zstream, level, method, windowbits, memlevel, strategy,
        zlib_version, sizeof(ZStream))
end

function init_deflate!(zstream::ZStream;
                       level::Integer=Z_DEFAULT_COMPRESSION,
                       method::Integer=Z_DEFLATED,
                       windowbits::Integer=15,
                       memlevel::Integer=8,
                       strategy::Integer=Z_DEFAULT_STRATEGY)
    return init_deflate!(zstream, level, method, windowbits, memlevel, strategy)
end

function reset_deflate!(zstream::ZStream)
    return ccall((:deflateReset, zlib), Cint, (Ref{ZStream},), zstream)
end

function end_deflate!(zstream::ZStream)
    return ccall((:deflateEnd, zlib), Cint, (Ref{ZStream},), zstream)
end

function deflate!(zstream::ZStream, flush::Integer)
    return ccall(
        (:deflate, zlib),
        Cint,
        (Ref{ZStream}, Cint),
        zstream, flush)
end

function _crc32(crc::UInt32, data::Ptr{UInt8}, n::Int)
    return ccall((:crc32, zlib), Culong, (Culong, Ptr{Cchar}, Cuint), crc, data, n) % UInt32
end

function _crc32()
    return _crc32(UInt32(0), convert(Ptr{UInt8}, C_NULL), 0)
end

function _adler32(adler::UInt32, data::Ptr{UInt8}, n::Int)
    return ccall((:adler32, zlib), Culong, (Culong, Ptr{Cchar}, Cuint), adler, data, n) % UInt32
end

function _adler32()
    return _adler32(UInt32(0), convert(Ptr{UInt8}, C_NULL), 0)
end


# Utils
# -----

# Convert the return code to a corresponding string.
function code2str(code::Cint)
    if code == Z_OK
        return "Z_OK"
    elseif code == Z_STREAM_END
        return "Z_STREAM_END"
    elseif code == Z_NEED_DICT
        return "Z_NEED_DICT"
    elseif code == Z_ERRNO
        return "Z_ERRNO"
    elseif code == Z_STREAM_ERROR
        return "Z_STREAM_ERROR"
    elseif code == Z_DATA_ERROR
        return "Z_DATA_ERROR"
    elseif code == Z_MEM_ERROR
        return "Z_MEM_ERROR"
    elseif code == Z_BUF_ERROR
        return "Z_BUF_ERROR"
    elseif code == Z_VERSION_ERROR
        return "Z_VERSION_ERROR"
    end
    throw(AssertionError("unknown return code: $(code)"))
end

# throw error exception based on ZStream and the return code
function zerror(zstream::ZStream, code::Cint)
    @assert code < 0
    if zstream.msg == C_NULL
        zerror(code)
    else
        error("zlib error: ", unsafe_string(zstream.msg), " (", code2str(code), ")")
    end
end

# throw error exception based on the return code
function zerror(code::Cint)
    @assert code < 0
    error("zlib error: ", code2str(code))
end

function init_inflate_zstream(gzip::Bool)
    zstream = ZStream()
    ret = init_inflate!(zstream, gzip ? 32 + 15 : 15)
    if ret != Z_OK
        zerror(ret)
    end
    return zstream
end

function init_deflate_zstream(gzip::Bool, level::Integer, mem_level::Integer, strategy)
    if !(0 <= level <= 9 || level == Z_DEFAULT_COMPRESSION)
        throw(ArgumentError("invalid zlib compression level"))
    end

    if !(1 <= mem_level <= 9)
        throw(ArgumentError("invalid zlib memory level"))
    end

    if strategy != Z_DEFAULT_STRATEGY &&
        strategy != Z_FILTERED &&
        strategy != Z_HUFFMAN_ONLY &&
        strategy != Z_RLE &&
        strategy != Z_FIXED
        throw(ArgumentError("invalid zlib strategy"))
    end

    zstream = ZStream()
    window_bits = gzip ? 16 + 15 : 15
    ret = init_deflate!(zstream, level, Z_DEFLATED, window_bits, mem_level, strategy)
    if ret != Z_OK
        zerror(ret)
    end
    return zstream
end
