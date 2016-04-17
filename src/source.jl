"""
The `mode` type parameter should be either :inflate or :deflate.
"""
type Source{mode,T<:BufferedInputStream}
    input::T
    zstream::Base.RefValue{ZStream}
    state::State
    reset_on_end::Bool
end


# inflate source constructors
# ---------------------------

function InflateSource{T<:BufferedInputStream}(input::T, gzip::Bool,
                                               reset_on_end::Bool)
    return Source{:inflate,T}(
        input,
        init_inflate_zstream(gzip),
        initialized,
        reset_on_end)
end


function InflateSource(input::BufferedInputStream, bufsize::Int, gzip::Bool,
                       reset_on_end::Bool)
    return InflateSource(input, gzip, reset_on_end)
end


function InflateSource(input::IO, bufsize::Int, gzip::Bool, reset_on_end::Bool)
    input_stream = BufferedInputStream(input, bufsize)
    return InflateSource(input_stream, gzip, reset_on_end)
end


function InflateSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool,
                       reset_on_end::Bool)
    return InflateSource(BufferedInputStream(input), gzip, reset_on_end)
end


"""
Open a zlib inflate input stream.

# Args
  * `input`: A byte vector, IO object, or BufferedInputStream containing
            compressed data to inflate.

# Named Args
  * `bufsize`: size of buffer in bytes
  * `gzip`: if true, data is gzip compressed, if false plain zlib compression
  * `reset_on_end`: On stream end, try to find the start of another stream.

"""
function ZlibInflateInputStream(input; bufsize::Int=8192, gzip::Bool=true,
                                reset_on_end::Bool=true)
    return BufferedInputStream(
        InflateSource(input, bufsize, gzip, reset_on_end),
        bufsize)
end


# deflate source constructors
# ---------------------------

function DeflateSource{T<:BufferedInputStream}(
                    input::T, gzip::Bool, level::Int, mem_level::Int, strategy::Int)
    return Source{:deflate,T}(
        input,
        init_deflate_stream(gzip, level, mem_level, strategy),
        initialized,
        false)
end


function DeflateSource(input::BufferedInputStream, bufsize::Int, gzip::Bool,
                       level::Int, mem_level::Int, strategy::Int)
    return DeflateSource(input, gzip, level, mem_level, strategy)
end


function DeflateSource(input::IO, bufsize::Int, gzip::Bool, level::Int,
                       mem_level::Int, strategy::Int)
    input_stream = BufferedInputStream(input, bufsize)
    return DeflateSource(input_stream, gzip, level, mem_level, strategy)
end


function DeflateSource(input::Vector{UInt8}, bufsize::Int, gzip::Bool,
                       level::Int, mem_level::Int, strategy::Int)
    return DeflateSource(BufferedInputStream(input), gzip, level, mem_level, strategy)
end


"""
Construct a zlib deflate input stream to compress gzip/zlib data.

# Args
  * `input`: A byte vector, IO object, or BufferedInputStream containing
            data to compress.

# Named Args
  * `bufsize`: Input and output buffer size.
  * `gzip`: If true, write gzip header and trailer.
  * `level`: Compression level in 1-9
  * `mem_level`: Memory to use for compression in 1-9
  * `strategy`: Compression strategy. See zlib documentation.
"""
function ZlibDeflateInputStream(input; bufsize::Int=8192, gzip::Bool=true,
                                level=6, mem_level=8, strategy=Z_DEFAULT_STRATEGY)
    return BufferedInputStream(DeflateSource(input, bufsize, gzip, Int(level),
                                             Int(mem_level), Int(strategy)), bufsize)
end


"""
Read bytes from the zlib stream to a buffer. Satisfies the BufferedStreams source interface.
"""
function BufferedStreams.readbytes!{mode}(
        source::Source{mode},
        buffer::Vector{UInt8},
        from::Int, to::Int)
    if source.state == finalized
        return 0
    elseif source.state == finished && source.reset_on_end
        reset!(source)
    end

    @trans source (
        initialized => inprogress,
        inprogress  => inprogress
    )

    fillbuffer!(source.input)
    source.zstream[].next_out = pointer(buffer, from)
    source.zstream[].avail_out = to - from + 1
    _, n_out = process(
        source,
        mode == :deflate && eof(source.input) ? Z_FINISH : Z_NO_FLUSH)
    return n_out
end

function process{mode}(source::Source{mode}, flush)
    @assert source.state == inprogress
    # counter of processed input/output bytes
    n_in = n_out = 0
    input = source.input
    zstream = source.zstream[]

    #println("--- Source{", mode, "} ---")
    @label process
    zstream.next_in = pointer(input)
    zstream.avail_in = BufferedStreams.available_bytes(input)
    old_avail_in = zstream.avail_in
    old_avail_out = zstream.avail_out
    ret = ccall(
        (mode, _zlib),
        Cint,
        (Ptr{ZStream}, Cint),
        source.zstream, flush)
    n_in += old_avail_in - zstream.avail_in
    n_out += old_avail_out - zstream.avail_out
    input.position += old_avail_in - zstream.avail_in

    if ret == Z_OK
        if zstream.avail_in == 0
            if BufferedStreams.fillbuffer!(input) == 0
                flush = Z_FINISH
            end
            @goto process
        end
    elseif ret == Z_STREAM_END
        @trans source inprogress => finished
    elseif ret == Z_BUF_ERROR
        # could not consume more input or produce more output
    elseif ret < 0
        zerror(zstream, ret)
    else
        @assert false
    end

    return n_in, n_out
end


@inline function Base.eof{mode}(source::Source{mode})
    if source.state == initialized ||
        (mode == :inflate && source.state == finished && source.reset_on_end)
        return eof(source.input)
    end
    return source.state == finished || source.state == finalized
end


function Base.close{mode}(source::Source{mode})
    if source.state == finalized
        close(source.input)
        return
    end
    if mode == :inflate
        ret = ccall((:inflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    else
        @assert mode == :deflate
        ret = ccall((:deflateEnd, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    end
    if ret != Z_OK
        zerror(source.zstream[], ret)
    end
    @trans source (
        initialized => finalized,
        inprogress  => finalized,
        finished    => finalized
    )
    close(source.input)
    return
end


function reset!{mode}(source::Source{mode})
    if mode == :inflate
        ret = ccall((:inflateReset, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    else
        @assert mode == :deflate
        ret = ccall((:deflateReset, _zlib), Cint, (Ptr{ZStream},), source.zstream)
    end
    if ret != Z_OK
        zerror(source.zstream[], ret)
    end
    @trans source (
        initialized => initialized,
        inprogress  => initialized,
        finished    => initialized,
        finalized   => initialized
    )
    return source
end
