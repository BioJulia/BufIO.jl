@testset "IOWriter construction and type" begin
    # Test basic construction with VecWriter
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    @test io_writer isa IOWriter{VecWriter}
    @test io_writer isa IO

    # Test with BufWriter
    buf_writer = BufWriter(IOBuffer())
    io_buf = IOWriter(buf_writer)
    @test io_buf isa IOWriter{BufWriter{IOBuffer}}

    # Test with GenericBufWriter
    generic_writer = GenericBufWriter()
    io_generic = IOWriter(generic_writer)
    @test io_generic isa IOWriter{GenericBufWriter}
end

@testset "IOWriter forwarded methods" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test close (VecWriter's close does nothing)
    close(io_writer)
    # Should be able to close multiple times
    close(io_writer)

    # Test flush (VecWriter's flush does nothing)
    flush(io_writer)
    flush(io_writer)

    # Test position and filesize with BufWriter (which implements them)
    inner_io = IOBuffer()
    buf_writer = BufWriter(inner_io)
    io_buf = IOWriter(buf_writer)

    @test position(io_buf) == 0
    @test filesize(io_buf) == 0

    write(io_buf, "test")
    @test position(io_buf) == 4
    @test filesize(io_buf) == 0  # Not flushed yet

    flush(io_buf)
    @test position(io_buf) == 4
    @test filesize(io_buf) == 4
end

@testset "IOWriter write UInt8" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test writing single bytes
    @test write(io_writer, 0x41) == 1  # 'A'
    @test write(io_writer, 0x42) == 1  # 'B'
    @test write(io_writer, 0x43) == 1  # 'C'

    @test vec_writer.vec == b"ABC"

    # Test writing to BufWriter
    inner_io = IOBuffer()
    buf_writer = BufWriter(inner_io, 10)
    io_buf = IOWriter(buf_writer)

    @test write(io_buf, 0xFF) == 1
    flush(io_buf)
    seekstart(inner_io)
    @test read(inner_io, UInt8) == 0xFF
end

@testset "IOWriter write data" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test writing array
    arr = UInt8[1, 2, 3, 4, 5]
    @test write(io_writer, arr) == 5
    @test vec_writer.vec[(end - 4):end] == arr

    # Test writing integers
    @test write(io_writer, htol(UInt16(0x1234))) == 2
    @test vec_writer.vec[(end - 1):end] == [0x34, 0x12]

    @test write(io_writer, htol(UInt32(0xABCDEF12))) == 4
    @test vec_writer.vec[(end - 3):end] == [0x12, 0xEF, 0xCD, 0xAB]

    # Test writing float
    @test write(io_writer, Float64(3.14)) == 8
    @test reinterpret(Float64, vec_writer.vec[(end - 7):end])[1] == 3.14
end

@testset "IOWriter write String" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test basic string
    @test write(io_writer, "hello") == 5
    @test String(copy(vec_writer.vec)) == "hello"

    # Test more strings
    @test write(io_writer, " world") == 6
    @test String(copy(vec_writer.vec)) == "hello world"

    # Test empty string
    prev_len = length(vec_writer.vec)
    @test write(io_writer, "") == 0
    @test length(vec_writer.vec) == prev_len

    # Test SubString
    str = "Hello, World!"
    substr = SubString(str, 8, 12)  # "World"
    vec_writer2 = VecWriter()
    io_writer2 = IOWriter(vec_writer2)
    @test write(io_writer2, substr) == 5
    @test String(vec_writer2.vec) == "World"

    # Test Unicode string
    vec_writer3 = VecWriter()
    io_writer3 = IOWriter(vec_writer3)
    unicode_str = "Hello 世界"
    n = write(io_writer3, unicode_str)
    @test n == sizeof(unicode_str)
    @test String(vec_writer3.vec) == unicode_str
end

@testset "IOWriter write CodeUnits" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test writing codeunits
    str = "test string"
    units = codeunits(str)
    @test write(io_writer, units) == sizeof(str)
    @test String(vec_writer.vec) == str

    # Test with substring's codeunits
    vec_writer2 = VecWriter()
    io_writer2 = IOWriter(vec_writer2)
    substr = SubString("Hello, World!", 1, 5)
    units2 = codeunits(substr)
    @test write(io_writer2, units2) == 5
    @test String(vec_writer2.vec) == "Hello"
end

@testset "IOWriter write multiple arguments" begin
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    # Test writing multiple items at once
    n = write(io_writer, 0x41, 0x42, 0x43)
    @test n == 3
    @test vec_writer.vec[(end - 2):end] == b"ABC"

    # Test writing mixed types
    vec_writer2 = VecWriter()
    io_writer2 = IOWriter(vec_writer2)
    n2 = write(io_writer2, "Hello", 0x20, "World")
    @test n2 == 11  # 5 + 1 + 5
    @test String(vec_writer2.vec) == "Hello World"

    # Test with numbers and strings
    vec_writer3 = VecWriter()
    io_writer3 = IOWriter(vec_writer3)
    n3 = write(io_writer3, UInt8(1), UInt8(2), UInt8(3), UInt8(4))
    @test n3 == 4
    @test vec_writer3.vec == [1, 2, 3, 4]
end

@testset "IOWriter edge cases" begin
    # Test writing empty data
    vec_writer = VecWriter()
    io_writer = IOWriter(vec_writer)

    @test write(io_writer, UInt8[]) == 0
    @test isempty(vec_writer.vec)

    @test write(io_writer, "") == 0
    @test isempty(vec_writer.vec)

    # Test print with no arguments
    print(io_writer)  # Should do nothing
    @test isempty(vec_writer.vec)

    # Test multiple close/flush calls
    close(io_writer)
    close(io_writer)
    flush(io_writer)
    flush(io_writer)

    # Write after close (VecWriter allows this)
    write(io_writer, "still works")
    @test String(vec_writer.vec) == "still works"
end
