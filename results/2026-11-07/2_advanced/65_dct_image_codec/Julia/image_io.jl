function read_ppm(path)
    lines = readlines(path)
    width,height = parse.(Int,split(lines[2]))
    image = Matrix{NTuple{3,Int}}(undef,height,width)
    for y in 1:height
        values = parse.(Int,split(lines[y+3]))
        for x in 1:width
            image[y,x] = Tuple(values[3x-2:3x])
        end
    end
    image
end
function write_ppm(path,image)
    open(path,"w") do io
        println(io,"P3\n$(size(image,2)) $(size(image,1))\n255")
        for y in axes(image,1)
            println(io,join((value for x in axes(image,2) for value in image[y,x])," "))
        end
    end
end
function read_params(path)
    params = Dict{String,Any}()
    for line in readlines(path)
        words = String.(split(line))
        name = words[1]
        params[name] = name in ("sampling","huffman") ? words[2] : name in (
            "qualities",
            "truncate"
        ) ? parse.(Int,words[2:end]) : parse(Int,words[2])
    end
    params
end
function read_tables(path)
    lines = readlines(path)
    matrix_at(start) = [parse(Int,split(lines[start+row-1])[column]) for row in 1:8,column in 1:8]
    transform = matrix_at(2)
    basic = [matrix_at(11),matrix_at(20)]
    tables = Dict{Tuple{Int,Int},HuffmanTable}()
    for start in 28:3:37
        words = split(lines[start])
        key = (parse(Int,words[2]),parse(Int,words[3]))
        tables[key] = HuffmanTable(parse.(Int,split(lines[start+1])),parse.(Int,split(lines[start+2])))
    end
    (transform=transform,basic=basic,standard=tables)
end
function read_hex(path)
    text = join(readlines(path))
    [parse(Int,text[i:i+1];base=16) for i in 1:2:length(text)]
end
function write_hex(path,data)
    open(path,"w") do io
        for start in 1:32:length(data)
            println(io,join((string(value;base=16,pad=2) for value in data[start:min(start+31,end)])))
        end
    end
end
