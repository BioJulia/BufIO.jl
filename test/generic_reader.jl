@testset "read(::T, UInt8)" begin
    io = GenericBufReader("abcde")
    @test [read(io, UInt8) for i in 1:5] == b"abcde"
    @test_throws IOError read(io, UInt8)

    @test_throws IOError read(GenericBufReader(b""), UInt8)
end

@testset "read(::T)" begin
    io = GenericBufReader([0x01, 0x02, 0x03, 0x04, 0x05])
    v = read(io)
    @test v isa Vector{UInt8}
    @test v == b"\1\2\3\4\5"
    v = read(io)
    @test v isa Vector{UInt8}
    @test isempty(v)
end

@testset "read(::T, ::Integer)" begin
    v = view(b"abcdefghijklm", 3:10)
    io = GenericBufReader(v)
    @test read(io, 3) == b"cde"
    @test read(io, 1) == b"f"
    @test read(io, 5) == b"ghij"
    @test read(io, 1) == UInt8[]
    @test_throws ArgumentError read(io, -1)

    io = GenericBufReader("abcde")
    @test read(io, typemax(Int)) == b"abcde"
end

@testset "read(::T, String)" begin
    io = GenericBufReader([0x01 0x03; 0x02 0x04])
    @test read(io, String) === "\1\2\3\4"
    @test read(io, String) === ""
    @test read(GenericBufReader(UInt8[]), String) === ""
end


@testset "eof" begin
    io = GenericBufReader("abc")
    @test !eof(io)

    # Read all data
    read(io)
    @test eof(io)

    # Empty reader is EOF
    empty_io = GenericBufReader("")
    @test eof(empty_io)
end

@testset "unsafe_read(::T, ref, nbytes::UInt)" begin
    io = GenericBufReader("hello")

    # Test with array
    arr = Vector{UInt8}(undef, 3)
    n_read = unsafe_read(io, arr, UInt(3))
    @test n_read == 3
    @test arr == b"hel"

    # Test reading more than available
    arr2 = Vector{UInt8}(undef, 10)
    n_read2 = unsafe_read(io, arr2, UInt(10))
    @test n_read2 == 2  # Only "lo" remaining
    @test arr2[1:2] == b"lo"

    # Test with empty reader
    empty_io = GenericBufReader("")
    arr3 = Vector{UInt8}(undef, 5)
    n_read3 = unsafe_read(empty_io, arr3, UInt(5))
    @test n_read3 == 0
end

@testset "readavailable" begin
    io = GenericBufReader("hello")

    # First call should read all available data
    result = readavailable(io)
    @test result == b"hello"

    # Second call should return empty
    @test readavailable(io) == UInt8[]

    # Empty reader
    empty_io = GenericBufReader("")
    @test readavailable(empty_io) == UInt8[]
end

@testset "peek(::T, ::Type{UInt8})" begin
    io = GenericBufReader("abc")

    # Peek should not advance position
    @test peek(io, UInt8) == UInt8('a')
    @test peek(io, UInt8) == UInt8('a')  # Same byte

    # Now read and peek next
    read(io, UInt8)
    @test peek(io, UInt8) == UInt8('b')

    # Read remaining
    read(io, UInt8)
    read(io, UInt8)

    # Peek at EOF should throw
    @test_throws IOError peek(io, UInt8)

    # Empty reader should throw
    empty_io = GenericBufReader("")
    @test_throws IOError peek(empty_io, UInt8)
end

@testset "readbytes!" begin
    # Test basic functionality
    io = GenericBufReader("hello world")
    buf = Vector{UInt8}(undef, 5)
    n_read = readbytes!(io, buf, 5)
    @test n_read == 5
    @test buf == b"hello"
    @test readbytes!(io, buf) == 5
    @test buf == b" worl"

    # Test with nb > length(b) - should expand buffer
    io = GenericBufReader("hello world")
    buf = Vector{UInt8}(undef, 3)
    n_read = readbytes!(io, buf, 6)
    @test n_read == 6
    @test length(buf) == 6
    @test buf == b"hello "

    # Test reading more than available
    io = GenericBufReader("hi")
    buf = Vector{UInt8}(undef, 10)
    n_read = readbytes!(io, buf, 10)
    @test n_read == 2
    @test buf[1:2] == b"hi"

    # Test default nb parameter
    io = GenericBufReader("test")
    buf = Vector{UInt8}(undef, 2)
    n_read = readbytes!(io, buf)  # Should read length(buf) = 2
    @test n_read == 2
    @test buf == b"te"

    # Test with empty reader
    empty_io = GenericBufReader("")
    buf = Vector{UInt8}(undef, 5)
    n_read = readbytes!(empty_io, buf, 5)
    @test n_read == 0
end

@testset "read!" begin
    # Test exact fill
    io = GenericBufReader("hello")
    arr = Vector{UInt8}(undef, 5)
    result = read!(io, arr)
    @test result === arr
    @test arr == b"hello"

    # Test EOF before filling - should throw
    io2 = GenericBufReader("hi")
    arr2 = Vector{UInt8}(undef, 5)
    @test_throws IOError read!(io2, arr2)

    # Test with empty array
    io3 = GenericBufReader("test")
    empty_arr = Vector{UInt8}(undef, 0)
    result3 = read!(io3, empty_arr)
    @test result3 === empty_arr
    @test isempty(empty_arr)

    # Test with matrix (should work with any AbstractArray)
    io4 = GenericBufReader("abcdef")
    mat = Matrix{UInt8}(undef, 2, 3)
    result4 = read!(io4, mat)
    @test result4 === mat
    @test vec(mat) == b"abcdef"
end

@testset "readline" begin
    # Test basic line reading
    io = GenericBufReader("hello\nworld\n")
    @test readline(io) == "hello"
    @test readline(io) == "world"
    @test readline(io) == ""  # EOF

    # Test with \r\n
    io2 = GenericBufReader("line1\r\nline2\r\n")
    @test readline(io2) == "line1"
    @test readline(io2) == "line2"

    # Test keep=true
    io3 = GenericBufReader("hello\nworld\r\n")
    @test readline(io3, keep = true) == "hello\n"
    @test readline(io3, keep = true) == "world\r\n"

    # Test no final newline
    io4 = GenericBufReader("hello\nworld")
    @test readline(io4) == "hello"
    @test readline(io4) == "world"

    # Test empty lines
    io5 = GenericBufReader("a\n\nb")
    @test readline(io5) == "a"
    @test readline(io5) == ""
    @test readline(io5) == "b"

    # Test empty input
    empty_io = GenericBufReader("")
    @test readline(empty_io) == ""
end

@testset "readuntil" begin
    # Test reading until delimiter
    io = GenericBufReader("hello,world,test")
    @test readuntil(io, UInt8(',')) == b"hello"
    @test readuntil(io, UInt8(',')) == b"world"
    @test readuntil(io, UInt8(',')) == b"test"  # No more delimiters

    # Test keep=true
    io2 = GenericBufReader("a;b;c")
    @test readuntil(io2, UInt8(';'), keep = true) == b"a;"
    @test readuntil(io2, UInt8(';'), keep = true) == b"b;"
    @test readuntil(io2, UInt8(';'), keep = true) == b"c"

    # Test delimiter not found
    io3 = GenericBufReader("no delimiter here")
    @test readuntil(io3, UInt8('|')) == b"no delimiter here"

    # Test empty input
    empty_io = GenericBufReader("")
    @test readuntil(empty_io, UInt8('x')) == b""
end

@testset "copyuntil" begin
    # Test basic copying until delimiter
    io_src = GenericBufReader("hello,world,test")
    io_dst = IOBuffer()

    result = copyuntil(io_dst, io_src, UInt8(','))
    @test result === io_dst
    seekstart(io_dst)
    @test String(read(io_dst)) == "hello"

    # Continue copying
    io_dst2 = IOBuffer()
    copyuntil(io_dst2, io_src, UInt8(','))
    seekstart(io_dst2)
    @test String(read(io_dst2)) == "world"

    # Copy remaining (no more delimiters)
    io_dst3 = IOBuffer()
    copyuntil(io_dst3, io_src, UInt8(','))
    seekstart(io_dst3)
    @test String(read(io_dst3)) == "test"

    # Test keep=true
    io_src2 = GenericBufReader("a;b;c")
    io_dst4 = IOBuffer()
    copyuntil(io_dst4, io_src2, UInt8(';'), keep = true)
    seekstart(io_dst4)
    @test String(read(io_dst4)) == "a;"

    # Test delimiter not found - should copy all remaining
    io_src3 = GenericBufReader("no delimiter")
    io_dst5 = IOBuffer()
    copyuntil(io_dst5, io_src3, UInt8('|'))
    seekstart(io_dst5)
    @test String(read(io_dst5)) == "no delimiter"

    # Test empty source
    empty_src = GenericBufReader("")
    io_dst6 = IOBuffer()
    copyuntil(io_dst6, empty_src, UInt8('x'))
    seekstart(io_dst6)
    @test String(read(io_dst6)) == ""

    # Test copying to VecWriter
    io_src4 = GenericBufReader("data|more")
    vec_dst = VecWriter()
    copyuntil(vec_dst, io_src4, UInt8('|'))
    @test String(vec_dst.vec) == "data"

    # Test with binary delimiter
    io_src5 = GenericBufReader([0x01, 0x02, 0xFF, 0x03, 0x04])
    io_dst7 = IOBuffer()
    copyuntil(io_dst7, io_src5, 0xFF)
    seekstart(io_dst7)
    @test read(io_dst7) == [0x01, 0x02]
end
