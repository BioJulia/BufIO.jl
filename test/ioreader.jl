@testset "IOReader construction and type" begin
    # Test basic construction
    cursor = CursorReader("hello world")
    io_reader = IOReader(cursor)

    @test io_reader isa IOReader{CursorReader}
    @test io_reader isa IO

    # Test with empty data
    empty_cursor = CursorReader("")
    empty_io = IOReader(empty_cursor)
    @test empty_io isa IOReader{CursorReader}
    @test eof(empty_io)
end

@testset "Some forwarded methods" begin
    cursor = CursorReader("test data for forwarding")
    io_reader = IOReader(cursor)

    # Test bytesavailable
    @test bytesavailable(io_reader) == bytesavailable(cursor)

    # Test eof
    @test eof(io_reader) == eof(cursor)
    @test !eof(io_reader)

    # Read some data and test eof again
    v = read(io_reader, 5)
    @test v == b"test "
    @test eof(io_reader) == eof(cursor)
    @test !eof(io_reader)

    # Read all remaining data
    v = read(io_reader)
    @test v == b"data for forwarding"
    @test eof(io_reader) == eof(cursor)
    @test eof(io_reader)

    # Test position
    seek(io_reader, 5)
    @test position(io_reader) == position(cursor)
    @test position(io_reader) == 5

    # Test filesize
    @test filesize(io_reader) == filesize(cursor)

    # Test close
    close(io_reader)  # Should forward to cursor's close (which does nothing)
end

@testset "IOReader read methods" begin
    cursor = CursorReader("Hello, World!")
    io_reader = IOReader(cursor)

    # Test read(UInt8)
    @test read(io_reader, UInt8) == UInt8('H')
    @test position(io_reader) == 1

    # Test read(n::Integer)
    data_chunk = read(io_reader, 4)
    @test data_chunk == b"ello"
    @test position(io_reader) == 5

    # Test readavailable
    available = readavailable(io_reader)
    @test available == b", World!"
    @test eof(io_reader)

    # Test read() - all data
    cursor2 = CursorReader("all data")
    io_reader2 = IOReader(cursor2)
    data = read(io_reader2)
    @test data == b"all data"
    @test eof(io_reader2)

    # Test read(String)
    cursor3 = CursorReader("string test")
    io_reader3 = IOReader(cursor3)
    str = read(io_reader3, String)
    @test str == "string test"
    @test eof(io_reader3)

    # Test peek
    cursor4 = CursorReader("peek test")
    io_reader4 = IOReader(cursor4)
    @test peek(io_reader4) == UInt8('p')
    @test read(io_reader4, 3) == b"pee"
    @test peek(io_reader4) == UInt8('k')
    @test read(io_reader4) == b"k test"
    @test_throws EOFError peek(io_reader4)
end

@testset "IOReader unsafe_read" begin
    cursor = CursorReader("unsafe read test")
    io_reader = IOReader(cursor)

    # Test with array
    arr = Vector{UInt8}(undef, 6)
    GC.@preserve arr begin
        unsafe_read(io_reader, pointer(arr), UInt(6))
    end
    @test arr == b"unsafe"
    @test position(io_reader) == 6

    # Test reading more than available
    remaining_size = filesize(io_reader) - position(io_reader)
    arr2 = Vector{UInt8}(undef, 20)
    GC.@preserve arr2 begin
        @test_throws EOFError unsafe_read(io_reader, pointer(arr2), UInt(20))
    end

    # Test with empty reader
    empty_cursor = CursorReader("")
    empty_io = IOReader(empty_cursor)
    arr3 = fill!(Vector{UInt8}(undef, 5), 0xaa)
    GC.@preserve arr3 begin
        unsafe_read(empty_io, pointer(arr3), UInt(0))
    end
    @test all(==(0xaa), arr3)
end
