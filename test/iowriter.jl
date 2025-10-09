@testset "IOWriter construction and type" begin
    # Test basic construction
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    @test io_writer isa IOWriter{VecWriter}
    @test io_writer isa IO

    # Test with BufWriter
    buf_writer = BufWriter(IOBuffer())
    io_writer2 = IOWriter(buf_writer)
    @test io_writer2 isa IOWriter{BufWriter{IOBuffer}}
    @test io_writer2 isa IO
end

@testset "Some basic methods" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test write
    @test write(io_writer, 0x61) == 1
    @test write(io_writer, 0x62) == 1
    @test vec_writer.vec == b"ab"

    # Test position and filesize
    @test position(io_writer) == position(vec_writer) == 2
    @test filesize(io_writer) == filesize(vec_writer) == 2

    # Test seek
    seek(io_writer, 0)
    @test position(io_writer) == position(vec_writer) == 0

    write(io_writer, b"xyz")
    @test vec_writer.vec == b"xyz"

    # Test close and flush (should forward)
    close(io_writer)  # VecWriter's close does nothing
    flush(io_writer)  # VecWriter's flush does nothing
end

@testset "Closing and flushing forwarding" begin
    io = IOBuffer()
    writer = IOWriter(BufWriter(io))

    @test write(writer, "abc") == 3
    @test isempty(take!(io))

    flush(writer)
    seekstart(io)
    @test read(io) == b"abc"

    seekstart(io)
    write(writer, "def")
    close(writer)
    @test !isopen(io)
end

@testset "IOWriter write methods" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test write(UInt8)
    @test write(io_writer, UInt8('H')) == 1
    @test position(io_writer) == 1

    # Test write with string
    n = write(io_writer, "ello")
    @test n == 4
    @test position(io_writer) == 5
    @test String(copy(vec_writer.vec)) == "Hello"

    # Test write with array
    data = b", World!"
    n = write(io_writer, data)
    @test n == 8
    @test String(copy(vec_writer.vec)) == "Hello, World!"

    # Test write with multiple arguments
    vec_writer2 = VecWriter()
    io_writer2 = IOWriter(vec_writer2)
    n = write(io_writer2, 0x41, 0x42, 0x43)
    @test n == 3
    @test vec_writer2.vec == b"ABC"

    # Test write with mixed types
    vec_writer3 = VecWriter()
    io_writer3 = IOWriter(vec_writer3)
    n = write(io_writer3, "Hi", 0x20, b"there")
    @test n == 8  # 2 + 1 + 5
    @test String(copy(vec_writer3.vec)) == "Hi there"
end

