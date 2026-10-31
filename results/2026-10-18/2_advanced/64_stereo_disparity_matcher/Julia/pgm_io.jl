function read_pgm(path)
    lines = readlines(path)
    width,height = parse.(Int,split(lines[2]))
    (width=width,height=height,pixels=[parse(Int,value) for line in lines[4:end] for value in split(line)])
end
function read_parameters()
    params = Dict{String,Any}("sample_pixels"=>Tuple{Int,Int}[])
    for line in readlines("input/params.txt")
        words = String.(split(line))
        name = words[1]
        if name=="sample"
            push!(params["sample_pixels"],Tuple(parse.(Int,words[2:3])))
        elseif name in ("wta_cost","sgm_cost")
            params[name] = words[2]
        elseif endswith(name,"_windows")
            params[name] = parse.(Int,words[2:end])
        else
            params[name] = parse(Int,words[2])
        end
    end
    params
end
function write_pgm(path,width,height,pixels)
    open(path,"w") do io
        println(io,"P2\n$width $height\n255")
        for y in 0:height-1
            println(io,join(pixels[y*width+1:(y+1)*width]," "))
        end
    end
end
