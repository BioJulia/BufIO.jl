@testset "Construction" begin
    vw = VecWriter()
    @test vw isa VecWriter
    vw = VecWriter([0x01, 0x02])
    @test vw isa VecWriter

    @test_throws MethodError VecWriter(UInt16[])
end

@testset "Basic methods" begin
    vw = VecWriter([0x61, 0x62, 0x63])
    @test get_unflushed(vw) == b"abc"

    # These do nothing
    close(vw)
    flush(vw)

    write(vw, htol(0x0102))
    @test get_unflushed(vw) == b"abc\2\1"

    # Test overallocation
    @test !isempty(get_buffer(vw))

    data = get_buffer(vw)
    fill!(get_buffer(vw), 0xaa)
    consume(vw, length(data))
    written = get_unflushed(vw)
    @test written[1:5] == b"abc\2\1"
    @test all(==(0xaa), written[6:end])

    nonempty = get_nonempty_buffer(vw)
    @test !isempty(nonempty)

    # Remove vector content
    s = String(vw.vec)
    @test isempty(vw.vec)
    @test isempty(get_buffer(vw))
    @test isempty(get_unflushed(vw))

    if isdefined(Base, :takestring!)
        vw = VecWriter(collect(b"abcde"))
        @test takestring!(vw) == "abcde"
        @test isempty(vw.vec)
    end
end

@testset "specialized methods" begin
    io = VecWriter()
    @test isempty(get_unflushed(io))
    write(io, 0xaa)
    write(io, 0x61)
    write(io, 0x63)
    @test String(io.vec) == "\xaaac"
end

@testset "position" begin
    io = VecWriter()
    @test position(io) == filesize(io) == 0

    # These do nothing
    close(io)
    flush(io)

    write(io, "hello")
    @test position(io) == filesize(io) == 5
    seek(io, 3)
    @test position(io) == filesize(io) == 3

    @test_throws IOError seek(io, 6)
    @test_throws IOError seek(io, -1)
    @test_throws IOError seek(io, 5)

    @test get_unflushed(io) == b"hel"
end

@testset "Nonzero offset" begin
    v = UInt8[0x01, 0x02]
    pushfirst!(v, 0xff)
    vw = VecWriter(v)
    @test get_unflushed(vw) == [0xff, 0x01, 0x02]
end
