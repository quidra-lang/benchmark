function read_inputs()
    lines = readlines("input/image.pgm")
    width,height = parse.(Int,split(lines[2],' '))
    image = zeros(Int,height,width)
    for y in 1:height
        image[y,:] = parse.(Int,split(lines[y+3],' '))
    end
    trig = [Tuple(parse.(Int,split(line,' '))[2:3]) for line in readlines("input/trig.txt")]
    params = Dict{String,Vector{Int}}()
    for line in readlines("input/params.txt")
        fields = split(line,' ')
        params[String(fields[1])] = parse.(Int,fields[2:end])
    end
    image,trig,params
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function write_pgm(name,image)
    height,width = size(image)
    write_lines(name,vcat(["P2","$width $height","255"],[join(image[y,:]," ") for y in 1:height]))
end
