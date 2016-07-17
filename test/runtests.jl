using Libz, BufferedStreams, Compat

if VERSION >= v"0.5-"
    using Base.Test
else
    using BaseTestNext
    const Test = BaseTestNext
end

srand(0x123456)

@testset "Source" begin
    function test_round_trip(data)
        return data == read(data |> ZlibDeflateInputStream |> ZlibInflateInputStream)
    end

    @test test_round_trip(UInt8[])
    @test test_round_trip(rand(UInt8, 1))
    @test test_round_trip(rand(UInt8, 1000000))
    @test test_round_trip(zeros(UInt8, 1000000))

    function test_round_trip2(data, bufsize, gzip, reset_on_end)
        return data == read(
            ZlibInflateInputStream(
                ZlibDeflateInputStream(data, bufsize=bufsize, gzip=gzip),
                bufsize=bufsize, gzip=gzip, reset_on_end=reset_on_end))
    end

    for bufsize in [1, 5, 10, 50, 128*2^10], gzip in [false, true], reset_on_end in [false, true]
        @test test_round_trip2(UInt8[], bufsize, gzip, reset_on_end)
        @test test_round_trip2(rand(UInt8, 1), bufsize, gzip, reset_on_end)
        @test test_round_trip2(rand(UInt8, 1000000), bufsize, gzip, reset_on_end)
        @test test_round_trip2(zeros(UInt8, 1000000), bufsize, gzip, reset_on_end)
    end

    @test_throws ArgumentError ZlibDeflateInputStream(UInt8[], bufsize=0)
    @test_throws ArgumentError ZlibDeflateInputStream(UInt8[], level=10)
    @test_throws ArgumentError ZlibInflateInputStream(UInt8[], bufsize=0)
    @test_throws ErrorException read(ZlibInflateInputStream([0x00, 0x01]))

    # check state transition
    stream = ZlibInflateInputStream(ZlibDeflateInputStream([0x00,0x00], bufsize=1), bufsize=1)
    @test stream.source.state === Libz.initialized
    # read 1 byte
    read(stream, UInt8)
    @test stream.source.state === Libz.inprogress
    # read the rest
    read(stream)
    @test stream.source.state === Libz.finished
    # close and release resources
    close(stream)
    @test stream.source.state === Libz.finalized
    # close again
    try
        close(stream)
        @test true
    catch
        @test false
    end
    @test stream.source.state === Libz.finalized
end

@testset "Sink" begin
    function test_round_trip(data)
        outbuf = IOBuffer()
        stream = outbuf |> ZlibInflateOutputStream |> ZlibDeflateOutputStream
        write(stream, data)
        flush(stream)
        actual = takebuf_array(outbuf)
        return actual == data
    end

    @test test_round_trip(UInt8[])
    @test test_round_trip(rand(UInt8, 1))
    @test test_round_trip(rand(UInt8, 1000000))

    function test_round_trip2(data, bufsize, gzip)
        outbuf = IOBuffer()
        stream = ZlibDeflateOutputStream(
            ZlibInflateOutputStream(outbuf, bufsize=bufsize, gzip=gzip),
            bufsize=bufsize, gzip=gzip)
        write(stream, data)
        flush(stream)
        actual = takebuf_array(outbuf)
        return actual == data
    end

    for bufsize in [1, 5, 10, 50, 128*2^10], gzip in [false, true]
        @test test_round_trip2(UInt8[], bufsize, gzip)
        @test test_round_trip2(rand(UInt8, 1), bufsize, gzip)
        @test test_round_trip2(rand(UInt8, 1000000), bufsize, gzip)
        @test test_round_trip2(zeros(UInt8, 1000000), bufsize, gzip)
    end

    @test_throws ArgumentError ZlibDeflateOutputStream(UInt8[], bufsize=0)
    @test_throws ArgumentError ZlibDeflateOutputStream(UInt8[], level=10)
    @test_throws ArgumentError ZlibInflateOutputStream(UInt8[], bufsize=0)

    deflated = read(ZlibDeflateInputStream("foo".data))
    buf = IOBuffer()
    out = ZlibInflateOutputStream(buf)
    BufferedStreams.writebytes(out, deflated, length(deflated), true)
    flush(out)
    @test takebuf_string(buf) == "foo"

    @testset "sink vector" begin
        # Python: zlib.compress(bytearray([0x40, 0x41, 0x42]))
        x = [0x40, 0x41, 0x42]
        y = b"x\x9cspt\x02\x00\x01\x87\x00\xc4"

        out = ZlibDeflateOutputStream(UInt8[], gzip=false)
        write(out, x)
        flush(out)
        @test takebuf_array(out.sink.output) == y

        out = ZlibInflateOutputStream(UInt8[], gzip=false)
        write(out, y)
        flush(out)
        @test takebuf_array(out.sink.output) == x
    end

    # check state transition
    buf = IOBuffer()
    stream = ZlibDeflateOutputStream(ZlibInflateOutputStream(buf, bufsize=1), bufsize=1)
    @test stream.sink.state === Libz.initialized
    # write 2 bytes
    write(stream, [0x00, 0x01])
    @test stream.sink.state === Libz.inprogress
    # flush data
    flush(stream)
    @test stream.sink.state === Libz.finished
    # close and release resources
    close(stream)
    @test stream.sink.state === Libz.finalized
    # close again
    try
        close(stream)
        @test true
    catch
        @test false
    end
    @test stream.sink.state === Libz.finalized
end

@testset "Inflate/Deflate" begin
    data = rand(UInt8, 100000)
    @test Libz.inflate(Libz.deflate(data)) == data
end

@testset "Checksums" begin
    # checking correctness isn't our job, just make sure they're usable
    data = rand(UInt8, 100000)

    c32 = crc32(data)
    @test isa(c32, UInt32)

    a32 = adler32(data)
    @test isa(a32, UInt32)

    @test crc32(BufferedInputStream(IOBuffer(data), 1024)) === c32
    @test adler32(BufferedInputStream(IOBuffer(data), 1024)) === a32
end

@testset "Concatenated gzip files" begin
    filepath = Pkg.dir("Libz", "test", "foobar.txt.gz")
    s = readstring(open(filepath) |> ZlibInflateInputStream)
    @test s == "foo\nbar\n"
end

@testset "Error" begin
    @test_throws ErrorException Libz.zerror(Libz.Z_ERRNO)
    @test_throws ErrorException Libz.zerror(Libz.Z_STREAM_ERROR)
    @test_throws ErrorException Libz.zerror(Libz.Z_DATA_ERROR)
    @test_throws ErrorException Libz.zerror(Libz.Z_MEM_ERROR)
    @test_throws ErrorException Libz.zerror(Libz.Z_BUF_ERROR)
    @test_throws ErrorException Libz.zerror(Libz.Z_VERSION_ERROR)
end

@testset "Low-level APIs" begin
    zstream = Libz.ZStream()
    ret = Libz.init_inflate!(zstream, 15)
    @test ret == Libz.Z_OK
    zstream = Libz.ZStream()
    @test_throws ErrorException (Libz.@zcheck Libz.init_inflate!(zstream, 100))
end
