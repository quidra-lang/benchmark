const Point3 = NTuple{3,Int}
record(;items...) = Dict{Symbol,Any}(items)
integer_word(word) = occursin(r"^-?[0-9]+$",word)
mutable struct Face
    triangle::Int
    polygon::Int
    line::Int
    group::String
    vertices::Point3
end
function read_obj(path=joinpath("input","model.obj"))
    lines = readlines(path)
    vertices,polygons,errors = Point3[],Dict{Symbol,Any}[],Tuple{Int,String}[]
    ignored = 0
    group = "default"
    for (number,text) in enumerate(lines)
        (isempty(text) || startswith(text,"#")) && continue
        words = split(text,' ')
        command,args = words[1],words[2:end]
        if command == "v"
            if length(args) != 3 || !all(integer_word,args)
                push!(errors,(number,"bad_vertex"))
            else
                push!(vertices,Tuple(parse.(Int,args)))
            end
        elseif command == "f"
            if length(args) < 3
                push!(errors,(number,"short_face"))
                continue
            end
            resolved = Int[]
            error = nothing
            for argument in args
                part = split(argument,'/';limit=2,keepempty=true)[1]
                if !integer_word(part) || parse(Int,part) == 0
                    error = "bad_index"
                    break
                end
                value = parse(Int,part)
                value < 0 && (value=length(vertices)+1+value)
                if !(1 <= value <= length(vertices))
                    error = "out_of_range"
                    break
                end
                push!(resolved,value)
            end
            if isnothing(error)
                push!(polygons,record(number=length(polygons)+1,line=number,group=group,vertices=resolved))
            else
                push!(errors,(number,error))
            end
        elseif command == "g"
            group = isempty(args) ? "default" : String(args[1])
        elseif command in ("vt","vn","s","o","usemtl","mtllib")
            ignored += 1
        else
            push!(errors,(number,"unknown_keyword"))
        end
    end
    (lines=length(lines),vertices=vertices,polygons=polygons,errors=errors,ignored=ignored)
end
function write_repaired_obj(vertices,faces)
    lines = ["# vertices $(length(vertices)) faces $(length(faces))"]
    append!(lines,["v "*join(point,' ') for point in vertices])
    previous = nothing
    for face in faces
        if face.group != previous
            push!(lines,"g "*face.group)
            previous = face.group
        end
        push!(lines,"f "*join(face.vertices,' '))
    end
    lines
end
