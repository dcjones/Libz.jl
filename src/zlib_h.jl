# general zlib constants, definitions

@unix_only    const _zlib = "libz"
@windows_only const _zlib = "zlib1"

# Constants

zlib_version = bytestring(ccall((:zlibVersion, _zlib), Ptr{UInt8}, ()))

# Flush values
const Z_NO_FLUSH       = Int32(0)
const Z_PARTIAL_FLUSH  = Int32(1)
const Z_SYNC_FLUSH     = Int32(2)
const Z_FULL_FLUSH     = Int32(3)
const Z_FINISH         = Int32(4)
const Z_BLOCK          = Int32(5)
const Z_TREES          = Int32(6)

# Return codes
const Z_OK             = Int32(0)
const Z_STREAM_END     = Int32(1)
const Z_NEED_DICT      = Int32(2)
const Z_ERRNO          = Int32(-1)
const Z_STREAM_ERROR   = Int32(-2)
const Z_DATA_ERROR     = Int32(-3)
const Z_MEM_ERROR      = Int32(-4)
const Z_BUF_ERROR      = Int32(-5)
const Z_VERSION_ERROR  = Int32(-6)

function code2str(code::Int32)
    if code == 0
        return "Z_OK"
    elseif code == 1
        return "Z_STREAM_END"
    elseif code == 2
        return "Z_NEED_DICT"
    elseif code == -1
        return "Z_ERRNO"
    elseif code == -2
        return "Z_STREAM_ERROR"
    elseif code == -3
        return "Z_DATA_ERROR"
    elseif code == -4
        return "Z_MEM_ERROR"
    elseif code == -5
        return "Z_BUF_ERROR"
    elseif code == -6
        return "Z_VERSION_ERROR"
    end
    error("unknown return code: ", code)
end

# Zlib errors as Exceptions
zerror(e::Integer) = bytestring(ccall((:zError, _zlib), Ptr{UInt8}, (Int32,), e))
type ZError <: Exception
    err::Int32
    err_str::AbstractString

    ZError(e::Integer) = (e == Z_ERRNO ? new(e, strerror()) : new(e, zerror(e)))
end

# Compression Levels
const Z_NO_COMPRESSION      = Int32(0)
const Z_BEST_SPEED          = Int32(1)
const Z_BEST_COMPRESSION    = Int32(9)
const Z_DEFAULT_COMPRESSION = Int32(-1)

# Compression Strategy
const Z_FILTERED             = Int32(1)
const Z_HUFFMAN_ONLY         = Int32(2)
const Z_RLE                  = Int32(3)
const Z_FIXED                = Int32(4)
const Z_DEFAULT_STRATEGY     = Int32(0)

# data_type field
const Z_BINARY    = Int32(0)
const Z_TEXT      = Int32(1)
const Z_ASCII     = Z_TEXT
const Z_UNKNOWN   = Int32(2)

# deflate compression method
const Z_DEFLATED    = Int32(8)

# misc
const Z_NULL   = C_NULL

# Constants for use with gzbuffer
const Z_DEFAULT_BUFSIZE = 8192
const Z_BIG_BUFSIZE = 131072

# Constants for use with gzseek
const SEEK_SET = Int32(0)
const SEEK_CUR = Int32(1)

# Create ZFileOffset alias
# Use 64bit if the *64 functions are available or zlib is compiles with 64bit
# file offset.

# Get compile-time option flags
const zlib_compile_flags = ccall((:zlibCompileFlags, _zlib), UInt, ())
const z_off_t_sz = 2 << ((zlib_compile_flags >> 6) & UInt(3))
if z_off_t_sz == 8 || Libdl.dlsym_e(Libdl.dlopen(_zlib), :gzopen64) != C_NULL
    typealias ZFileOffset Int64
elseif z_off_t_sz == 4      # 64-bit functions not available
    typealias ZFileOffset Int32
else
    error("Can't figure out what to do with ZFileOffset.  sizeof(z_off_t) = ", z_off_t_sz)
end


# The zlib z_stream structure.
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
        strm = new()
        strm.next_in   = C_NULL
        strm.avail_in  = 0
        strm.total_in  = 0
        strm.next_out  = C_NULL
        strm.avail_out = 0
        strm.total_out = 0
        strm.msg       = C_NULL
        strm.state     = C_NULL
        strm.zalloc    = C_NULL
        strm.zfree     = C_NULL
        strm.opaque    = C_NULL
        strm.data_type = 0
        strm.adler     = 0
        strm.reserved  = 0
        return strm
    end
end

# throw error exception based on ZStream and the return code
function zerror(zstream::ZStream, code::Cint)
    @assert code < 0
    if zstream.msg == C_NULL
        zerror(code)
    else
        error("zlib error: ", bytestring(zstream.msg), " (", code2str(code), ")")
    end
end

# throw error exception based on the return code
function zerror(code::Cint)
    @assert code < 0
    error("zlib error: ", code2str(code))
end

"""
Initialize a ZStream for inflation.
"""
function init_inflate_zstream(gzip::Bool)
    zstream = Ref(ZStream())
    ret = ccall((:inflateInit2_, _zlib),
                Cint, (Ptr{ZStream}, Cint, Ptr{Cchar}, Cint),
                zstream, gzip ? 32 + 15 : 15, zlib_version, sizeof(ZStream))
    if ret != Z_OK
        zerror(ret)
    end
    return zstream
end


"""
Initialize a ZStream for deflation.
"""
function init_deflate_stream(gzip::Bool, level::Int, mem_level::Int,
                             strategy::Int)
    if !(1 <= level <= 9)
        error("Invalid zlib compression level.")
    end

    if !(1 <= mem_level <= 9)
        error("Invalid zlib memory level.")
    end

    if strategy != Z_DEFAULT_STRATEGY &&
        strategy != Z_FILTERED &&
        strategy != Z_HUFFMAN_ONLY &&
        strategy != Z_RLE &&
        strategy != Z_FIXED
        error("Invalid zlib strategy.")
    end

   zstream = Ref(ZStream())
   window_bits = gzip ? 16 + 15 : 15
   # TODO: when gzip is true, it will write a "simple" gzip header/trailer that
   # doesn't include a filename, modification time, etc. We may want to support
   # that.
   ret = ccall((:deflateInit2_, _zlib),
               Cint, (Ptr{ZStream}, Cint, Cint, Cint, Cint, Cint, Ptr{Cchar}, Cint),
               zstream, level, Z_DEFLATED, window_bits, mem_level, strategy,
               zlib_version, sizeof(ZStream))
   if ret != Z_OK
       zerror(ret)
   end

   return zstream
end
