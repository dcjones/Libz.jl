"""
The `mode` type parameter must be either `:inflate` or `:deflate`.
"""
type Sink{mode,T<:BufferedOutputStream}
    output::T
    zstream::ZStream
    state::State
end


# inflate sink constructors
# -------------------------

function InflateSink{T<:BufferedOutputStream}(output::T, raw::Bool, gzip::Bool)
    zstream = init_inflate_zstream(raw, gzip)
    zstream.next_out = pointer(output)
    zstream.avail_out = BufferedStreams.available_bytes(output)
    return Sink{:inflate,T}(output, zstream, initialized)
end


function InflateSink(output::BufferedOutputStream, bufsize::Integer, raw::Bool,
                     gzip::Bool)
    return InflateSink(output, raw, gzip)
end


function InflateSink(output::IO, bufsize::Integer, raw::Bool, gzip::Bool)
    output_stream = BufferedOutputStream(output, bufsize)
    return InflateSink(output_stream, raw, gzip)
end


function InflateSink(output::Vector{UInt8}, bufsize::Integer, raw::Bool,
                     gzip::Bool)
    return InflateSink(BufferedOutputStream(output), raw, gzip)
end


"""
    ZlibInflateOutputStream(output[; <keyword arguments>])

Construct a zlib inflate output stream to decompress zlib data.

# Arguments
* `output`: a byte vector, IO object, or BufferedInputStream to which decompressed data should be written.
* `bufsize::Integer=8192`: input and output buffer size.
"""
function ZlibInflateOutputStream(output; bufsize::Integer=8192)
    return BufferedOutputStream(InflateSink(output, bufsize, false, false), bufsize)
end


"""
    GzipInflateOutputStream(output[; <keyword arguments>])

Construct a zlib inflate output stream to decompress gzip/zlib data.

# Arguments
* `output`: a byte vector, IO object, or BufferedInputStream to which decompressed data should be written.
* `bufsize::Integer=8192`: input and output buffer size.
"""
function GzipInflateOutputStream(output; bufsize::Integer=8192)
    return BufferedOutputStream(InflateSink(output, bufsize, false, true), bufsize)
end


"""
    RawInflateOutputStream(output[; <keyword arguments>])

Construct a zlib inflate output stream to decompress raw deflate data.

# Arguments
* `output`: a byte vector, IO object, or BufferedInputStream to which decompressed data should be written.
* `bufsize::Integer=8192`: input and output buffer size.
"""
function RawInflateOutputStream(output; bufsize::Integer=8192)
    return BufferedOutputStream(InflateSink(output, bufsize, true, false), bufsize)
end

# deflate sink constructors
# -------------------------

function DeflateSink{T<:BufferedOutputStream}(
        output::T, raw::Bool, gzip::Bool, level::Integer, mem_level::Integer,
        strategy)
    zstream = init_deflate_zstream(raw, gzip, level, mem_level, strategy)
    zstream.next_out = pointer(output)
    zstream.avail_out = BufferedStreams.available_bytes(output)
    return Sink{:deflate,T}(output, zstream, initialized)
end


function DeflateSink(output::BufferedOutputStream, bufsize::Integer, raw::Bool,
                     gzip::Bool, level::Integer, mem_level::Integer, strategy)
    return DeflateSink(output, raw, gzip, level, mem_level, strategy)
end


function DeflateSink(output::IO, bufsize::Integer, raw::Bool, gzip::Bool,
                     level::Integer, mem_level::Integer, strategy)
    output_stream = BufferedOutputStream(output, bufsize)
    return DeflateSink(output_stream, raw, gzip, level, mem_level, strategy)
end


function DeflateSink(output::Vector{UInt8}, bufsize::Integer, raw::Bool,
                     gzip::Bool, level::Integer, mem_level::Integer, strategy)
    return DeflateSink(BufferedOutputStream(output), raw, gzip, level, mem_level, strategy)
end


"""
    ZlibDeflateOutputStream(output[; <keyword arguments>])

Construct a zlib deflate output stream to compress zlib data.

# Arguments
* `output`: a byte vector, IO object, or BufferedInputStream to which compressed data should be written.
* `bufsize::Integer=8192`: input and output buffer size.
* `level::Integer=6`: compression level in 1-9.
* `mem_level::Integer=8`: memory to use for compression in 1-9.
* `strategy=Z_DEFAULT_STRATEGY`: compression strategy; see zlib documentation.
"""
function ZlibDeflateOutputStream(output;
                                 bufsize::Integer=8192,
                                 level::Integer=6,
                                 mem_level::Integer=8,
                                 strategy=Z_DEFAULT_STRATEGY)
    return BufferedOutputStream(
        DeflateSink(output, bufsize, false, false, level, mem_level, strategy),
        bufsize)
end


"""
    GzipDeflateOutputStream(output[; <keyword arguments>])

Construct a zlib deflate output stream to compress gzip data.

# Arguments
* `output`: a byte vector, IO object, or BufferedInputStream to which compressed data should be written.
* `bufsize::Integer=8192`: input and output buffer size.
* `level::Integer=6`: compression level in 1-9.
* `mem_level::Integer=8`: memory to use for compression in 1-9.
* `strategy=Z_DEFAULT_STRATEGY`: compression strategy; see zlib documentation.
"""
function GzipDeflateOutputStream(output;
                                 bufsize::Integer=8192,
                                 level::Integer=6,
                                 mem_level::Integer=8,
                                 strategy=Z_DEFAULT_STRATEGY)
    return BufferedOutputStream(
        DeflateSink(output, bufsize, false, true, level, mem_level, strategy),
        bufsize)
end


"""
    RawDeflateOutputStream(output[; <keyword arguments>])

Construct a zlib deflate output stream to compress raw deflate data.

# Arguments
* `output`: a byte vector, IO object, or BufferedInputStream to which compressed data should be written.
* `bufsize::Integer=8192`: input and output buffer size.
* `level::Integer=6`: compression level in 1-9.
* `mem_level::Integer=8`: memory to use for compression in 1-9.
* `strategy=Z_DEFAULT_STRATEGY`: compression strategy; see zlib documentation.
"""
function RawDeflateOutputStream(output; 
                                bufsize::Integer=8192,
                                level::Integer=6, 
                                mem_level::Integer=8, 
                                strategy=Z_DEFAULT_STRATEGY)
    return BufferedOutputStream(
        DeflateSink(output, bufsize, true, false, level, mem_level, strategy),
        bufsize)
end


"""
    writebytes(sink, buffer, n, eof)

Write some bytes from a given buffer. Satisfies the BufferedStreams sink
interface.
"""
function BufferedStreams.writebytes{mode}(
        sink::Sink{mode},
        buffer::Vector{UInt8},
        n::Int, eof::Bool)
    if sink.state == finalized
        return 0
    elseif sink.state == finished
        reset!(sink)
    end

    @trans sink (
        initialized => inprogress,
        inprogress  => inprogress
    )

    BufferedStreams.flushbuffer!(sink.output)
    sink.zstream.next_in = pointer(buffer)
    sink.zstream.avail_in = n
    n_in, _ = process(sink, mode == :deflate && eof ? Z_FINISH : Z_NO_FLUSH)
    return n_in
end

function Base.flush(sink::Sink)
    if sink.state == finalized
        return
    elseif sink.state == inprogress
        process(sink, Z_FINISH)
    end
    flush(sink.output)
    return
end

function process{mode}(sink::Sink{mode}, flush)
    @assert sink.state == inprogress
    # counter of processed input/output bytes
    n_in = n_out = 0
    output = sink.output
    zstream = sink.zstream

    #println("--- Sink{", mode, "} ---")
    @label process
    zstream.next_out = pointer(output)
    zstream.avail_out = BufferedStreams.available_bytes(output)
    old_avail_in = zstream.avail_in
    old_avail_out = zstream.avail_out
    if mode == :inflate
        ret = inflate!(zstream, flush)
    else
        ret = deflate!(zstream, flush)
    end
    n_in += old_avail_in - zstream.avail_in
    n_out += old_avail_out - zstream.avail_out
    output.position += old_avail_out - zstream.avail_out

    if ret == Z_OK
        if zstream.avail_out == 0
            BufferedStreams.flushbuffer!(output)
            @goto process
        end
    elseif ret == Z_STREAM_END
        @trans sink inprogress => finished
    elseif ret == Z_BUF_ERROR
        # could not consume more input or produce more output
    elseif ret < 0
        zerror(zstream, ret)
    else
        @assert false
    end

    return n_in, n_out
end

function Base.close{mode}(sink::Sink{mode})
    if sink.state == finalized
        isopen(sink.output) && close(sink.output)
        return
    end
    if mode == :inflate
        @zcheck end_inflate!(sink.zstream)
    else
        @zcheck end_deflate!(sink.zstream)
    end
    @trans sink (
        initialized => finalized,
        inprogress  => finalized,
        finished    => finalized
    )
    close(sink.output)
    return
end

function reset!{mode}(sink::Sink{mode})
    if mode == :inflate
        @zcheck reset_inflate!(sink.zstream)
    else
        @zcheck reset_deflate!(sink.zstream)
    end
    @trans sink (
        initialized => initialized,
        inprogress  => initialized,
        finished    => initialized,
        finalized   => initialized
    )
    return sink
end
