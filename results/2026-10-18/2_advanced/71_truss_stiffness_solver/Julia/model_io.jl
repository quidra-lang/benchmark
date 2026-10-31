csv_rows(name) = split.(readlines("input/$name.csv")[2:end],',')
function read_model()
    nodes = [(id=parse(Int,r[1]),x=parse(Int,r[2]),y=parse(Int,r[3])) for r in csv_rows("nodes")]
    sections = [(
        name=String(r[1]),
        area=parse(Float64,r[2]),
        inertia=parse(Float64,r[3])
    ) for r in csv_rows("sections")]
    materials = [(
        name=String(r[1]),
        young=parse(Float64,r[2]),
        yield_stress=parse(Float64,r[3]),
        density=parse(Float64,r[4]),
        expansion=parse(Float64,r[5])
    ) for r in csv_rows("materials")]
    ni = Dict(n.id=>i for (i,n) in enumerate(nodes))
    si = Dict(s.name=>i for (i,s) in enumerate(sections))
    mi = Dict(m.name=>i for (i,m) in enumerate(materials))
    members = [(
        id=parse(Int,r[1]),
        start=ni[parse(Int,r[2])],
        finish=ni[parse(Int,r[3])],
        section=si[r[4]],
        material=mi[r[5]],
        group=String(r[6])
    ) for r in csv_rows("members")]
    ei = Dict(e.id=>i for (i,e) in enumerate(members))
    supports = [(
        node=ni[parse(Int,r[1])],
        fixed=parse.(Int,r[2:3]),
        prescribed=parse.(Float64,r[4:5])
    ) for r in csv_rows("supports")]
    cases,combinations,loads,name = NamedTuple[],NamedTuple[],Tuple[],""
    for line in readlines("input/loads.txt")
        f = split(line)
        kind = f[1]
        if kind=="LOADCASE"
            name,loads = String(f[2]),Tuple[]
        elseif kind=="END"
            push!(cases,(name=name,lines=loads))
        elseif kind=="COMBINATION"
            push!(
                combinations,
                (name=String(f[2]),terms=[(String(f[i]),parse(Float64,f[i+1])) for i in 3:2:length(f)])
            )
        elseif kind=="FORCE"
            push!(loads,("FORCE",ni[parse(Int,f[2])],parse(Float64,f[3]),parse(Float64,f[4])))
        elseif kind=="TEMPERATURE"
            push!(loads,("TEMPERATURE",ei[parse(Int,f[2])],parse(Float64,f[3])))
        else
            push!(loads,(String(kind),))
        end
    end
    settings = Dict{String,Any}("influence"=>Int[],"drawing"=>Tuple[])
    for line in readlines("input/params.txt")
        f = split(line)
        kind,v = String(f[1]),f[2:end]
        if kind=="deck"
            settings[kind] = [ni[parse(Int,x)] for x in v]
        elseif kind=="influence"
            push!(settings[kind],ei[parse(Int,v[1])])
        elseif kind=="vehicle"
            settings[kind] = (
                parse(Int,v[1]),
                [(parse(Int,v[i]),parse(Float64,v[i+1])) for i in 2:2:length(v)]
            )
        elseif kind=="rating"
            settings[kind] = (String(v[1]),parse(Float64,v[2]),parse(Float64,v[3]))
        elseif kind=="slenderness"
            settings[kind] = parse.(Float64,v)
        elseif kind=="deflection"
            settings[kind] = (String(v[1]),parse(Int,v[2]))
        elseif kind=="vibration"
            settings[kind] = (String(v[1]),parse(Int,v[2]),parse(Int,v[3]))
        elseif kind=="removal"
            settings[kind] = String(v[1])
        elseif kind=="drawing"
            push!(settings[kind],(String(v[1]),parse.(Int,v[2:end])...))
        else
            settings[kind] = parse.(Int,v)
        end
    end
    (;nodes,members,sections,materials,supports,cases,combinations,settings)
end
