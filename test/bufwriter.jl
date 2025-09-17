@testset "BufWriter construction" begin
    # Test basic construction
    io = IOBuffer()
    writer = BufWriter(io)
    @test writer isa BufWriter{IOBuffer}

    # Test custom buffer size
    writer2 = BufWriter(io, 1024)
    @test length(writer2.buffer) == 1024

    # Test minimum buffer size
    writer3 = BufWriter(io, 1)
    @test length(writer3.buffer) == 1

    # Test invalid buffer size
    @test_throws ArgumentError BufWriter(io, 0)
    @test_throws ArgumentError BufWriter(io, -1)
end

@testset "get_buffer" begin
    io = IOBuffer()
    writer = BufWriter(io, 10)

    # Initial buffer should be full size
    buffer = get_buffer(writer)
    @test buffer isa MutableMemoryView{UInt8}
    @test length(buffer) == 10

    # After consuming some bytes
    consume(writer, 3)
    buffer2 = get_buffer(writer)
    @test length(buffer2) == 7

    # After consuming all bytes
    consume(writer, 7)
    buffer3 = get_buffer(writer)
    @test length(buffer3) == 0
end

@testset "get_unflushed" begin
    io = IOBuffer()
    writer = BufWriter(io, 10)

    # Initially no data
    data = get_unflushed(writer)
    @test data isa MutableMemoryView{UInt8}
    @test length(data) == 0

    # After writing some bytes
    buffer = get_buffer(writer)
    copyto!(buffer[1:5], "abcde")
    consume(writer, 5)
    @test get_unflushed(writer) == b"abcde"

    # After flushing
    flush(writer)
    data3 = get_unflushed(writer)
    @test length(data3) == 0
end

@testset "consume" begin
    io = IOBuffer()
    writer = BufWriter(io, 10)

    # Valid consume
    buflen = length(get_buffer(writer))
    consume(writer, 3)
    @test buflen - length(get_buffer(writer)) == 3

    # Consume remaining
    consume(writer, 7)
    @test isempty(get_buffer(writer))
    @test length(get_unflushed(writer)) == 10

    # Test bounds checking - should error when consuming more than available
    writer2 = BufWriter(IOBuffer(), 5)
    @test_throws IOError consume(writer2, 6)
    @test_throws IOError consume(writer2, -1)
end

@testset "grow_buffer and shallow_flush" begin
    io = IOBuffer()
    writer = BufWriter(io, 5)

    # Fill buffer partially
    consume(writer, 3)

    # grow_buffer should flush when there's data
    n_grown = grow_buffer(writer)
    @test n_grown == 3  # bytes flushed
    @test isempty(get_unflushed(writer))
    @test length(get_buffer(writer)) == 5

    # grow_buffer on empty buffer should expand
    n_grown2 = grow_buffer(writer)
    @test n_grown2 > 0  # buffer expanded
    @test length(writer.buffer) > 5
end

@testset "flush and close" begin
    io = IOBuffer()
    writer = BufWriter(io, 10)

    # Write some data by consuming
    buffer = get_buffer(writer)
    buffer[1:5] .= b"hello"
    consume(writer, 5)

    # Data should not be in underlying IO yet
    seekstart(io)
    @test isempty(read(io))

    # Flush should write to underlying IO
    flush(writer)
    seekstart(io)
    @test read(io, String) == "hello"

    # Closing twice should be safe
    close(writer)
    close(writer)
end

@testset "write UInt8" begin
    io = IOBuffer()
    writer = BufWriter(io, 10)

    # Write single byte
    n = write(writer, 0x42)
    @test n == 1
    @test get_unflushed(writer) == [0x42]

    flush(writer)
    seekstart(io)
    @test read(io, UInt8) == 0x42
end

@testset "write with small buffer" begin
    io = IOBuffer()
    writer = BufWriter(io, 3)  # Very small buffer

    # Write data larger than buffer
    data = "Hello, world!"
    n = write(writer, data)
    @test n == length(data)

    # Should have automatically flushed
    flush(writer)
    seekstart(io)
    @test read(io, String) == data
end

@testset "get_nonempty_buffer" begin
    io = IOBuffer()
    writer = BufWriter(io, 5)

    # Should return non-empty buffer initially
    buffer = get_nonempty_buffer(writer)
    @test buffer !== nothing
    @test !isempty(buffer)
    @test length(buffer) == 5

    # After filling buffer
    consume(writer, 5)
    buffer2 = get_nonempty_buffer(writer)
    @test buffer2 !== nothing  # Should grow or flush
    @test !isempty(buffer2)
end

@testset "edge cases" begin
    # Test with buffer size 1
    io = IOBuffer()
    writer = BufWriter(io, 1)

    write(writer, "abc")  # Should handle automatic flushing
    flush(writer)
    seekstart(io)
    @test read(io, String) == "abc"

    # Test writing empty string
    io2 = IOBuffer()
    writer2 = BufWriter(io2)
    @test write(writer2, "") == 0
    seekstart((io2))
    @test isempty(take!(io2))

    # Test multiple flushes
    io3 = IOBuffer()
    writer3 = BufWriter(io3)
    write(writer3, "test")
    flush(writer3)
    flush(writer3)  # Should be safe
    seekstart(io3)
    @test read(io3, String) == "test"
end

@testset "error conditions" begin
    io = IOBuffer()
    writer = BufWriter(io, 5)

    # Test consuming more than buffer size
    @test_throws IOError consume(writer, 10)

    # Test consuming negative amount
    @test_throws IOError consume(writer, -1)

    # Test that errors have correct kind
    try
        consume(writer, 10)
        @test false  # Should not reach here
    catch e
        @test e isa IOError
        @test e.kind == IOErrorKinds.ConsumeBufferError
    end
end

@testset "Write numbers" begin
    io = IOBuffer()
    writer = BufWriter(io, 3)
    write(writer, 0x01)
    write(writer, htol(0x0302))
    write(writer, 0x07060504)
    write(writer, 0x0f0e0d0c0b0a0908)
    write(writer, 1.2443)
    shallow_flush(writer)
    data = take!(io)
    @test data[1:15] == 1:15
    @test reinterpret(Float64, data[16:23]) == [1.2443]
end
