"""
The `mode` type parameter must be either `:inflate` or `:deflate`.
"""
type Source{mode,T<:BufferedInputStream}
    input::T
    zstream::ZStream
    state::State
    reset_on_end::Bool
end


# inflate source constructors
# ---------------------------

function InflateSource{T<:BufferedInputStream}(input::T, raw::Bool, gzip::Bool,
                                               reset_on_end::Bool)
    return Source{:inflate,T}(
        input,
        init_inflate_zstream(raw, gzip),
        initialized,
        reset_on_end)
end


function InflateSource(input::BufferedInputStream, bufsize::Integer, raw::Bool,
                       gzip::Bool, reset_on_end::Bool)
    return InflateSource(input, raw, gzip, reset_on_end)
end


function InflateSource(input::IO, bufsize::Integer, raw::Bool, gzip::Bool,
                       reset_on_end::Bool)
    input_stream = BufferedInputStream(input, bufsize)
    return InflateSource(input_stream, raw, gzip, reset_on_end)
end


function InflateSource(input::Vector{UInt8}, bufsize::Integer, raw::Bool,
                       gzip::Bool, reset_on_end::Bool)
    return InflateSource(BufferedInputStream(input), raw, gzip, reset_on_end)
end


"""
    ZlibInflateInputStream(input[; <keyword arguments>])

Construct a zlib inflate input stream to decompress gzip data.

# Arguments
* `input`: a byte vector, IO object, or BufferedInputStream containing compressed data to inflate.
* `bufsize::Integer=8192`: input and output buffer size.
* `reset_on_end::Bool=true`: on stream end, try to find the start of another stream.
"""
function ZlibInflateInputStream(input; bufsize::Integer=8192, 
                                reset_on_end::Bool=true)
    return BufferedInputStream(
        InflateSource(input, bufsize, false, false, reset_on_end),
        bufsize)
end


"""
    GzipInflateInputStream(input[; <keyword arguments>])

Construct a zlib inflate input stream to decompress gzip data.

# Arguments
* `input`: a byte vector, IO object, or BufferedInputStream containing compressed data to inflate.
* `bufsize::Integer=8192`: input and output buffer size.
* `reset_on_end::Bool=true`: on stream end, try to find the start of another stream.
"""
function GzipInflateInputStream(input; bufsize::Integer=8192, 
                                reset_on_end::Bool=true)
    return BufferedInputStream(
        InflateSource(input, bufsize, false, true, reset_on_end), bufsize)
end


"""
    RawInflateInputStream(input[; <keyword arguments>])

Construct a zlib inflate input stream to decompress raw deflate data.

# Arguments
* `input`: a byte vector, IO object, or BufferedInputStream containing compressed data to inflate.
* `bufsize::Integer=8192`: input and output buffer size.
* `reset_on_end::Bool=true`: on stream end, try to find the start of another stream.
"""
function RawInflateInputStream(input; bufsize::Integer=8192, 
                               reset_on_end::Bool=true)
    return BufferedInputStream(
        InflateSource(input, bufsize, true, false, reset_on_end), bufsize)
end

# deflate source constructors
# ---------------------------

function DeflateSource{T<:BufferedInputStream}(
        input::T, raw::Bool, gzip::Bool, level::Integer, mem_level::Integer,
        strategy)
    return Source{:deflate,T}(
        input,
        init_deflate_zstream(raw, gzip, level, mem_level, strategy),
        initialized,
        false)
end


function DeflateSource(input::BufferedInputStream, bufsize::Integer, raw::Bool,
                       gzip::Bool, level::Integer, mem_level::Integer, strategy)
    return DeflateSource(input, raw, gzip, level, mem_level, strategy)
end


function DeflateSource(input::IO, bufsize::Integer, raw::Bool, gzip::Bool,
                       level::Integer,
                       mem_level::Integer, strategy)
    input_stream = BufferedInputStream(input, bufsize)
    return DeflateSource(input_stream, raw, gzip, level, mem_level, strategy)
end


function DeflateSource(input::Vector{UInt8}, bufsize::Integer, raw::Bool,
                       gzip::Bool, level::Integer, mem_level::Integer, strategy)
    return DeflateSource(BufferedInputStream(input), raw, gzip, level, mem_level, strategy)
end


"""
    ZlibDeflateInputStream(input[; <keyword arguments>])

Construct a zlib deflate input stream to compress zlib data.

# Arguments
* `input`: a byte vector, IO object, or BufferedInputStream containing data to compress.
* `bufsize::Integer=8192`: input and output buffer size.
* `level::Integer=6`: compression level in 1-9.
* `mem_level::Integer=8`: memory to use for compression in 1-9.
* `strategy=Z_DEFAULT_STRATEGY`: compression strategy; see zlib documentation.
"""
function ZlibDeflateInputStream(input;
                                bufsize::Integer=8192,
                                level::Integer=6,
                                mem_level::Integer=8,
                                strategy=Z_DEFAULT_STRATEGY)
    return BufferedInputStream(
        DeflateSource(input, bufsize, false, false, level, mem_level, strategy),
        bufsize)
end


"""
    GzipDeflateInputStream(input[; <keyword arguments>])

Construct a zlib deflate input stream to compress gzip data.

# Arguments
* `input`: a byte vector, IO object, or BufferedInputStream containing data to compress.
* `bufsize::Integer=8192`: input and output buffer size.
* `level::Integer=6`: compression level in 1-9.
* `mem_level::Integer=8`: memory to use for compression in 1-9.
* `strategy=Z_DEFAULT_STRATEGY`: compression strategy; see zlib documentation.
"""
function GzipDeflateInputStream(input;
                                bufsize::Integer=8192,
                                level::Integer=6,
                                mem_level::Integer=8,
                                strategy=Z_DEFAULT_STRATEGY)
    return BufferedInputStream(
        DeflateSource(input, bufsize, false, true, level, mem_level, strategy),
        bufsize)
end


"""
    RawDeflateInputStream(input[; <keyword arguments>])

Construct a zlib deflate input stream to compress raw deflate data.

# Arguments
* `input`: a byte vector, IO object, or BufferedInputStream containing data to compress.
* `bufsize::Integer=8192`: input and output buffer size.
* `level::Integer=6`: compression level in 1-9.
* `mem_level::Integer=8`: memory to use for compression in 1-9.
* `strategy=Z_DEFAULT_STRATEGY`: compression strategy; see zlib documentation.
"""
function RawDeflateInputStream(input; bufsize::Integer=8192, 
                               level::Integer=6,
                               mem_level::Integer=8, 
                               strategy=Z_DEFAULT_STRATEGY)
    return BufferedInputStream(
        DeflateSource(input, bufsize, true, false, level, mem_level, strategy),
        bufsize)
end


"""
    readbytes!(source, buffer, from, to)

Read bytes from the zlib stream to a buffer. Satisfies the BufferedStreams
source interface.
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
    source.zstream.next_out = pointer(buffer, from)
    source.zstream.avail_out = to - from + 1
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
    zstream = source.zstream

    #println("--- Source{", mode, "} ---")
    @label process
    zstream.next_in = pointer(input)
    zstream.avail_in = BufferedStreams.available_bytes(input)
    old_avail_in = zstream.avail_in
    old_avail_out = zstream.avail_out
    if mode == :inflate
        ret = inflate!(zstream, flush)
    else
        ret = deflate!(zstream, flush)
    end
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
        isopen(source.input) && close(source.input)
        return
    end
    if mode == :inflate
        @zcheck end_inflate!(source.zstream)
    else
        @zcheck end_deflate!(source.zstream)
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
        @zcheck reset_inflate!(source.zstream)
    else
        @zcheck reset_deflate!(source.zstream)
    end
    @trans source (
        initialized => initialized,
        inprogress  => initialized,
        finished    => initialized,
        finalized   => initialized
    )
    return source
end
