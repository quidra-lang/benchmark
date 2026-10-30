const KINDS = ["copy","bin","load","store","goto","if","param","call","return","read","print"]
const TACOperand = Union{Nothing,Int,String}
const TACExpression = Tuple{String,String,TACOperand,TACOperand}
Base.@kwdef struct TACInstruction
    kind::String
    destination::Union{Nothing,String} = nothing
    a::TACOperand = nothing
    b::TACOperand = nothing
    operation::String = ""
    name::String = ""
    count::Int = 0
end
const TACCode = Union{String,TACInstruction}
mutable struct TACFunction
    name::String
    parameters::Vector{String}
    code::Vector{TACCode}
    temporary_serial::Int
    preheader_serial::Int
end
TACFunction(name,parameters,code=TACCode[]) = TACFunction(name,parameters,code,0,0)
struct TACProgram
    arrays::Vector{Tuple{String,Int}}
    functions::Vector{TACFunction}
end
instructions(function_node) = TACInstruction[line for line in function_node.code if line isa TACInstruction]
function replace_instruction(entry;kind=entry.kind,destination=entry.destination,a=entry.a,b=entry.b,
                             operation=entry.operation,name=entry.name,count=entry.count)
    TACInstruction(kind=kind,destination=destination,a=a,b=b,operation=operation,name=name,count=count)
end
function operand_fields(entry)
    entry.kind in ("bin","if","store") && return (:a,:b)
    (entry.kind in ("copy","load","param","print") || (entry.kind == "return" && entry.a !== nothing)) && return (:a,)
    ()
end
used_variables(entry) = String[getproperty(entry,field) for field in operand_fields(entry) if getproperty(entry,field) isa String]
function expression(entry)
    entry.kind == "bin" && return ("bin",entry.operation,entry.a,entry.b)
    entry.kind == "load" && return ("load",entry.name,entry.a,nothing)
    nothing
end
operand(word) = word[1] == '-' || '0' <= word[1] <= '9' ? parse(Int,word) : String(word)
function array_operand(word)
    opening = findfirst('[',word)
    String(word[1:opening-1]),operand(word[opening+1:end-1])
end
function parse_instruction(words)
    first = words[1]
    first == "goto" && return TACInstruction(kind="goto",name=words[2])
    first == "if" && return TACInstruction(kind="if",a=operand(words[2]),b=operand(words[4]),operation=words[3],name=words[6])
    first in ("param","print") && return TACInstruction(kind=first,a=operand(words[2]))
    first == "return" && return TACInstruction(kind="return",a=length(words) == 2 ? operand(words[2]) : nothing)
    first == "read" && return TACInstruction(kind="read",destination=words[2])
    first == "call" && return TACInstruction(kind="call",name=words[2],count=parse(Int,words[3]))
    if '[' in first
        name,index = array_operand(first)
        return TACInstruction(kind="store",a=index,b=operand(words[3]),name=name)
    elseif words[3] == "call"
        return TACInstruction(kind="call",destination=first,name=words[4],count=parse(Int,words[5]))
    elseif length(words) == 5
        return TACInstruction(kind="bin",destination=first,a=operand(words[3]),b=operand(words[5]),operation=words[4])
    elseif '[' in words[3]
        name,index = array_operand(words[3])
        return TACInstruction(kind="load",destination=first,a=index,name=name)
    end
    TACInstruction(kind="copy",destination=first,a=operand(words[3]))
end
function read_program(path)
    arrays,functions = Tuple{String,Int}[],TACFunction[]
    current = nothing
    for line in readlines(path)
        words = split(line)
        (isempty(words) || startswith(words[1],"#")) && continue
        if words[1] == "array"
            push!(arrays,(words[2],parse(Int,words[3])))
        elseif words[1] == "func"
            current = TACFunction(words[2],String.(words[3:end]))
            push!(functions,current)
        elseif words[1] == "end"
            current = nothing
        elseif length(words) == 1 && endswith(words[1],":")
            push!(current.code,String(words[1][1:end-1]))
        else
            push!(current.code,parse_instruction(words))
        end
    end
    TACProgram(arrays,functions)
end
function calculate(operation,first,second)
    operation == "+" && return first+second
    operation == "-" && return first-second
    operation == "*" && return first*second
    operation == "/" && return div(first,second)
    operation == "%" && return rem(first,second)
    result = if operation == "<"
        first < second
    elseif operation == "<="
        first <= second
    elseif operation == ">"
        first > second
    elseif operation == ">="
        first >= second
    elseif operation == "=="
        first == second
    else
        first != second
    end
    Int(result)
end
expression_string(value) = value[1] == "load" ? "$(value[2])[$(value[3])]" : "$(value[3])$(value[2])$(value[4])"
function instruction_string(entry)
    kind = entry.kind
    kind == "copy" && return "$(entry.destination) = $(entry.a)"
    kind == "bin" && return "$(entry.destination) = $(entry.a) $(entry.operation) $(entry.b)"
    kind == "load" && return "$(entry.destination) = $(entry.name)[$(entry.a)]"
    kind == "store" && return "$(entry.name)[$(entry.a)] = $(entry.b)"
    kind == "goto" && return "goto $(entry.name)"
    kind == "if" && return "if $(entry.a) $(entry.operation) $(entry.b) goto $(entry.name)"
    if kind == "call"
        prefix = entry.destination === nothing ? "" : entry.destination * " = "
        return prefix * "call $(entry.name) $(entry.count)"
    end
    kind == "read" && return "read $(entry.destination)"
    kind == "return" && entry.a === nothing && return "return"
    "$kind $(entry.a)"
end
function function_lines(function_node)
    lines = [join(["func",function_node.name,function_node.parameters...]," ")]
    for line in function_node.code
        push!(lines,line isa String ? line * ":" : "    " * instruction_string(line))
    end
    push!(lines,"end")
    lines
end
function program_lines(program)
    sections = Vector{String}[]
    !isempty(program.arrays) && push!(sections,["array $name $size" for (name,size) in program.arrays])
    append!(sections,function_lines.(program.functions))
    lines = String[]
    for section in sections
        !isempty(lines) && push!(lines,"")
        append!(lines,section)
    end
    lines
end
