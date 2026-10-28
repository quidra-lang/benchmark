function load_inputs()
    geometry = [split(line,',') for line in readlines("input/stations.csv")[2:end]]
    lines = readlines("input/waveforms.txt")
    blocks = Dict{String,Any}()
    cursor = 1
    while cursor<=length(lines)
        header = split(lines[cursor],' ')
        code,start,count = String(header[2]),parse(Int,header[3]),parse(Int,header[4])
        cursor += 1
        samples = Int[]
        while length(samples)<count
            append!(samples,parse.(Int,split(lines[cursor],' ')))
            cursor += 1
        end
        blocks[code] = (start=start,samples=samples)
    end
    stations = [(code=String(row[1]),x=parse(Int,row[2]),y=parse(Int,row[3]),elevation=parse(Int,row[4]),order=i,
        start=blocks[String(row[1])].start,samples=blocks[String(row[1])].samples) for (
            i,
            row
        ) in enumerate(geometry)]
    params = Dict{String,Vector{Float64}}()
    for line in readlines("input/params.txt")
        fields = split(line,' ')
        params[String(fields[1])] = parse.(Float64,fields[2:end])
    end
    stations,params
end
