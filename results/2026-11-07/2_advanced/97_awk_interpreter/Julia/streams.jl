valid_name(name) = !isempty(name) && (letter(name[1]) || name[1] == '_') && all(name_character,name)
valid_filename(name) = !isempty(name) && !startswith(name,".") && all(character->letter(character) || digit(character) || character in ('.','_','-'),name)
mutable struct AwkOperand
    kind::String
    name::String
    value::String
    records::Int
end
function parse_arguments(lines)
    options = Tuple{String,String}[]
    operands = AwkOperand[]
    for line in lines
        if startswith(line,"-F ")
            push!(options,("FS",line[4:end]))
        elseif startswith(line,"-v ")
            name,value = split(line[4:end],'=';limit=2)
            push!(options,(name,value))
        else
            parts = split(line,'=';limit=2)
            if length(parts) == 2 && valid_name(parts[1])
                push!(operands,AwkOperand("assignment",parts[1],parts[2],0))
            else
                push!(operands,AwkOperand("file",line,"",0))
            end
        end
    end
    options,operands
end
read_records(name) = readlines(joinpath("input",name))
mutable struct OutputStream
    parts::Vector{String}
    opened::Bool
    writes::Int
end
OutputStream() = OutputStream(String[],false,0)
content(output) = join(output.parts)
function append_output!(output,text)
    push!(output.parts,text)
    output.writes += 1
end
mutable struct GetlineInput
    opened::Bool
    ever_opened::Bool
    lines::Vector{String}
    position::Int
    reads::Int
end
GetlineInput() = GetlineInput(false,false,String[],1,0)
struct AwkStreams
    stdout::OutputStream
    outputs::Dict{String,OutputStream}
    output_order::Vector{String}
    inputs::Dict{String,GetlineInput}
    input_order::Vector{String}
end
AwkStreams() = AwkStreams(OutputStream(),Dict{String,OutputStream}(),String[],Dict{String,GetlineInput}(),String[])
function write_output!(streams,text,name=nothing,mode=nothing,position=nothing)
    if name === nothing
        append_output!(streams.stdout,text)
        return
    end
    (valid_filename(name) && !(name in ("stdout.txt","stats.txt"))) || throw(RuntimeIssue(position,"invalid output file name"))
    if !haskey(streams.outputs,name)
        streams.outputs[name] = OutputStream()
        push!(streams.output_order,name)
    end
    output = streams.outputs[name]
    if !output.opened
        output.opened = true
        mode == ">" && empty!(output.parts)
    end
    append_output!(output,text)
end
function getline_input!(streams,name)
    if !haskey(streams.inputs,name)
        streams.inputs[name] = GetlineInput()
        push!(streams.input_order,name)
    end
    source = streams.inputs[name]
    if !source.opened
        (!valid_filename(name) || !isfile(joinpath("input",name))) && return (-1,nothing)
        source.lines = read_records(name)
        source.position = 1
        source.opened = source.ever_opened = true
    end
    source.position > length(source.lines) && return (0,nothing)
    line = source.lines[source.position]
    source.position += 1
    source.reads += 1
    1,line
end
function close_streams!(streams,name)
    closed = false
    for table in (streams.outputs,streams.inputs)
        if haskey(table,name) && table[name].opened
            table[name].opened = false
            closed = true
        end
    end
    closed ? 0 : -1
end
function save_streams(streams)
    write("output/stdout.txt",content(streams.stdout))
    for name in streams.output_order
        write(joinpath("output",name),content(streams.outputs[name]))
    end
end
