function read_inputs()
    lines = filter(line->!isempty(line) && !startswith(line,"#"),readlines("input/network.txt"))
    names,states,parents,expert = String[],Vector{String}[],Vector{Int}[],Dict{Int,Matrix{Float64}}()
    index = Dict{String,Int}()
    position = 1
    while position<=length(lines)
        fields = split(lines[position])
        position += 1
        if fields[1]=="VARIABLE"
            push!(names,fields[2])
            index[fields[2]] = length(names)
            push!(states,String.(fields[3:end]))
            push!(parents,Int[])
        elseif fields[1]=="PARENTS"
            parents[index[fields[2]]] = [index[name] for name in fields[3:end]]
        else
            v = index[fields[2]]
            rows = prod((length(states[p]) for p in parents[v]);init=1)
            cpt = zeros(rows,length(states[v]))
            for row in 1:rows
                cpt[row,:] = parse.(Float64,split(lines[position]))
                position += 1
            end
            expert[v] = cpt
        end
    end
    csv = readlines("input/samples.csv")
    columns = [index[name] for name in split(csv[1],',')]
    samples = Vector{Int}[]
    for line in csv[2:end]
        sample = zeros(Int,length(names))
        for (v,state) in zip(columns,split(line,','))
            sample[v] = findfirst(==(state),states[v])
        end
        push!(samples,sample)
    end
    settings = split.(readlines("input/params.txt"))
    params = (alpha=parse(Float64,settings[1][2]),method=String(settings[2][2]),
        order=[index[name] for name in settings[3][2:end]],limit=parse(Int,settings[4][2]),
        seed=parse(Int,settings[5][2]),sources=[String(fields[3]) for fields in settings[6:end]])
    (names=names,states=states,parents=parents,expert=expert,samples=samples,
        queries=readlines("input/queries.txt"),params=params)
end
