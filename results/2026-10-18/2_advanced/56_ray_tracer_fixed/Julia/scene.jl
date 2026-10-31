mutable struct Material
    name::String
    color::NTuple{3,Int}
    kd::Int
    ks::Int
    n::Int
    kr::Int
    kt::Int
    ior::Int
    checker::Any
end
function read_scene()
    camera = Dict{String,Any}("fog"=>nothing)
    materials = Dict{String,Material}()
    objects,lights = NamedTuple[],NamedTuple[]
    for line in readlines(joinpath("input","scene.txt"))
        (isempty(line) || startswith(line,"#")) && continue
        words = String.(split(line))
        kind = words[1]
        if kind=="material"
            name = words[2]
            values = parse.(Int,words[3:end])
            materials[name] = Material(name,Tuple(values[1:3]),values[4:end]...,nothing)
        elseif kind=="checker"
            values = parse.(Int,words[3:end])
            materials[words[2]].checker = (Tuple(values[1:3]),values[4])
        elseif kind in ("sphere","plane","box")
            values = parse.(Int,words[4:end])
            details = kind=="sphere" ? (center=Tuple(values[1:3]),radius=values[4]) : kind=="plane" ? (
                point=Tuple(values[1:3]),
                normal=norm(values[4:6])
            ) : (lo=Tuple(values[1:3]),hi=Tuple(values[4:6]))
            push!(
                objects,
                (;number=length(objects)+1,kind=kind,label=words[2],material=materials[words[3]],details...)
            )
        elseif kind in ("point","spot","sun","area")
            values = parse.(Int,words[2:end])
            details = if kind=="sun"
                (direction=norm(neg(values[1:3])),samples=1)
            elseif kind=="spot"
                (
                    position=Tuple(values[1:3]),
                    direction=norm(values[4:6]),
                    outer=values[7],
                    inner=values[8],
                    samples=1
                )
            elseif kind=="area"
                (
                    position=Tuple(values[1:3]),
                    u=Tuple(values[4:6]),
                    v=Tuple(values[7:9]),
                    divisions=values[10],
                    samples=values[10]^2
                )
            else
                (position=Tuple(values[1:3]),samples=1)
            end
            push!(lights,(;number=length(lights)+1,kind=kind,intensity=values[end],details...))
        else
            values = parse.(Int,words[2:end])
            camera[kind] = kind=="ambient" ? values[1] : Tuple(values)
        end
    end
    (
        eye=camera["eye"],
        forward=camera["forward"],
        right=camera["right"],
        up=camera["up"],
        view=camera["view"],
        background=camera["background"],
        ambient=camera["ambient"],
        fog=camera["fog"],
        objects=objects,
        lights=lights
    )
end
