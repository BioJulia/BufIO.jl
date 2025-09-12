@testset "BufReader construction" begin
    # Test basic construction
    io = IOBuffer("hello world")
    reader = BufReader(io)
    @test reader isa BufReader
    @test reader.io === io
    
    # Test with custom buffer size
    io2 = IOBuffer("test")
    reader2 = BufReader(io2, 16)
    @test length(reader2.buffer) == 16
    
    # Test invalid buffer sizes
    io3 = IOBuffer("test")
    @test_throws ArgumentError BufReader(io3, 0)
    @test_throws ArgumentError BufReader(io3, -1)
    
    # Test that buffer starts empty
    @test isempty(get_buffer(reader))
end

@testset "get_buffer and fill_buffer" begin
    io = IOBuffer("hello world")
    reader = BufReader(io, 4)  # Small buffer
    
    # Initially empty
    @test isempty(get_buffer(reader))
    
    # Fill buffer
    n_filled = fill_buffer(reader)
    @test n_filled == 4  # Should fill to buffer capacity
    buffer = get_buffer(reader)
    @test length(buffer) == 4
    @test String(buffer) == "hell"
    
    # Fill again (should expand or move data)
    consume(reader, 2)  # Consume "he"
    n_filled2 = fill_buffer(reader)
    @test n_filled2 > 0
    buffer2 = get_buffer(reader)
    @test String(buffer2[1:2]) == "ll"  # Previous unconsumed data
    n_filled3 = fill_buffer(reader)
    @test n_filled3 == 5
    @test String(get_buffer(reader)) == "llo world"
    
    # Test EOF behavior
    io_eof = IOBuffer("")
    reader_eof = BufReader(io_eof)
    @test fill_buffer(reader_eof) == 0
end

@testset "Position tracking" begin
    io = IOBuffer("hello world test")
    reader = BufReader(io, 5)
    
    # Initial position
    @test position(reader) == 0
    
    # Read some data
    read(reader, 5)  # "hello"
    @test position(reader) == 5
    
    # Read more
    read(reader, 6)  # " world"
    @test position(reader) == 11
    
    # Fill buffer and check position consistency
    fill_buffer(reader)
    @test position(reader) == 11  # Should account for buffered data
    
    # Consume from buffer
    consume(reader, 2) # consume " t"
    @test position(reader) == 13
    
    # Read remaining
    remaining = read(reader)
    @test String(remaining) == "est"
    @test position(reader) == 16  # End of data
end

@testset "seek functionality" begin
    io = IOBuffer("0123456789")
    reader = BufReader(io, 4)
    
    # Test seeking to beginning
    seek(reader, 0)
    @test position(reader) == 0
    @test String(read(reader, 3)) == "012"
    
    # Test seeking forward
    seek(reader, 5)
    @test position(reader) == 5
    @test String(read(reader, 2)) == "56"
    
    # Test seeking backward
    seek(reader, 2)
    @test position(reader) == 2
    @test String(read(reader, 3)) == "234"
    
    # Test seeking to end
    seek(reader, 10)
    @test position(reader) == 10
    @test isempty(read(reader))
    @test eof(reader)
    
    # Test invalid seeks
    @test_throws IOError seek(reader, -1)
    @test_throws IOError seek(reader, 11)  # Beyond end
end

@testset "filesize compatibility" begin
    # Test that seek works with filesize bounds
    io = IOBuffer("test data")
    reader = BufReader(io)
    
    # filesize should work with IOBuffer
    @test filesize(io) == 9
    
    # Seeking within bounds
    seek(reader, 0)
    @test position(reader) == 0
    seek(reader, filesize(io))
    @test position(reader) == filesize(io)
    @test eof(reader)
    
    # Seeking beyond bounds should fail
    @test_throws IOError seek(reader, filesize(io) + 1)
end

# TODO: Write more tests
# Test buffer growth specifically