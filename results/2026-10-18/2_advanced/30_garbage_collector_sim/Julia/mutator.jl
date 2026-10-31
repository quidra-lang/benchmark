const COMMAND_NAMES = ("ALLOC","PUSH","LOAD","POP","SET","OVERWRITE","CHECKPOINT")
const COMMAND_FORMS = Dict(
    "ALLOC"=>(:number,:number),
    "PUSH"=>(:source,),
    "LOAD"=>(:number,:number),
    "POP"=>(:number,),
    "SET"=>(:number,:number,:source),
    "OVERWRITE"=>(:number,:source),
    "CHECKPOINT"=>(:label,)
)
function read_config(path)
    size,width = 0,0
    collectors = NamedTuple[]
    maps = String[]
    windows = Int[]
    for line in readlines(path)
        tokens = String.(split(line))
        if tokens[1] == "HEAP"
            size = parse(Int,tokens[2])
        elseif tokens[1] == "COLLECTOR"
            push!(
                collectors,
                (
                    name=tokens[2],
                    kind=tokens[3],
                    young=length(tokens)>3 ? parse(Int,tokens[4]) : 0,
                    age=length(tokens)>4 ? parse(Int,tokens[5]) : 0
                )
            )
        elseif tokens[1] == "MAPS"
            maps = tokens[2:end]
        elseif tokens[1] == "MMU"
            windows = parse.(Int,tokens[2:end])
        else
            width = parse(Int,tokens[2])
        end
    end
    (heap_size=size,width=width,collectors=collectors,maps=maps,windows=windows)
end
is_number(token) = occursin(r"^(0|[1-9][0-9]{0,3})$",token)
is_label(token) = occursin(r"^[a-z0-9_]{1,16}$",token)
function parse_command(line,text)
    tokens = split(text,' ';keepempty=true)
    form = get(COMMAND_FORMS,tokens[1],nothing)
    (isnothing(form) || length(tokens) != length(form)+1) && return (nothing,"syntax")
    for (kind,token) in zip(form,tokens[2:end])
        valid = kind == :number ? is_number(token) : kind == :source ? token == "-" || is_number(token) : is_label(token)
        valid || return (nothing,"syntax")
    end
    name = String(tokens[1])
    p,d,slot,field,source,count = 0,0,0,0,-1,0
    label = ""
    source_value(token) = token == "-" ? -1 : parse(Int,token)
    if name == "ALLOC"
        p,d = parse.(Int,tokens[2:3])
    elseif name == "PUSH"
        source = source_value(tokens[2])
    elseif name == "LOAD"
        slot,field = parse.(Int,tokens[2:3])
    elseif name == "POP"
        count = parse(Int,tokens[2])
    elseif name == "SET"
        slot,field = parse.(Int,tokens[2:3])
        source = source_value(tokens[4])
    elseif name == "OVERWRITE"
        slot = parse(Int,tokens[2])
        source = source_value(tokens[3])
    else
        label = String(tokens[2])
    end
    (name == "ALLOC" && (p > 6 || d > 24) || name == "POP" && count == 0) && return (nothing,"range")
    (
        line=line,
        name=name,
        pointers=p,
        data=d,
        slot=slot,
        field=field,
        source=source,
        count=count,
        label=label
    ),nothing
end
read_script(path) = [parse_command(i,text) for (i,text) in enumerate(readlines(path))]
