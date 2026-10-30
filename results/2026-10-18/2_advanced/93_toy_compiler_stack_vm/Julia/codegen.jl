const BINARY = Dict("+"=>"ADD","-"=>"SUB","*"=>"MUL","/"=>"DIV","%"=>"MOD","<"=>"LT","<="=>"LE",">"=>"GT",">="=>"GE","=="=>"EQ","!="=>"NE")
const JUMPS = Set(["JUMP","JUMPF","JUMPT"])
const CONDITIONAL = Set(["JUMPF","JUMPT"])
const TRANSFERS = Set(["JUMP","RET","RETV","HALT"])
const NEGATED = Dict("LT"=>"GE","LE"=>"GT","GT"=>"LE","GE"=>"LT","EQ"=>"NE","NE"=>"EQ")
const INVERSE = Dict("JUMPF"=>"JUMPT","JUMPT"=>"JUMPF")
struct Instruction
    op::String
    args::Vector{Any}
    position::ToyPosition
end
instruction(op,position,args...) = Instruction(op,Any[args...],position)
mutable struct Label
    position::Int
end
Label() = Label(-1)
mutable struct CodeUnit
    name::String
    function_node::Union{Nothing,ToyNode}
    slots::Vector{ToyNode}
    before::Vector{Instruction}
    after::Vector{Instruction}
    blocks::Vector{Tuple{Int,Int,Vector{Int}}}
    depth::Int
    recursive::Bool
    before_start::Int
    after_start::Int
end
CodeUnit(name,function_node,slots,code) = CodeUnit(name,function_node,slots,code,Instruction[],Tuple{Int,Int,Vector{Int}}[],0,false,0,0)
mutable struct Generator
    code::Vector{Instruction}
    loops::Vector{Tuple{Label,Label}}
end
Generator() = Generator(Instruction[],Tuple{Label,Label}[])
emit!(generator,op,position,args...) = push!(generator.code,instruction(op,position,args...))
mark!(generator,label) = (label.position = length(generator.code))
function finish_code(generator)
    [entry.op in JUMPS ? instruction(entry.op,entry.position,entry.args[1].position) : entry for entry in generator.code]
end
function generate_expression!(generator,node)
    kind,position = node.kind,node.position
    if kind in ("integer","boolean")
        emit!(generator,"PUSH",position,Int64(node.value))
    elseif kind == "variable"
        referent = node.referent
        emit!(generator,referent.kind == "global" ? "LOADG" : "LOADL",position,referent.kind == "global" ? referent.address : referent.slot)
    elseif kind == "array"
        generate_expression!(generator,node.index)
        emit!(generator,"LOADA",position,node.referent.address,node.referent.size)
    elseif kind == "read"
        emit!(generator,"READ",position)
    elseif kind == "call"
        foreach(argument -> generate_expression!(generator,argument),node.arguments)
        emit!(generator,"CALL",position,node.referent.name,length(node.arguments))
    elseif kind == "unary"
        generate_expression!(generator,node.operand)
        emit!(generator,node.operator == "-" ? "NEG" : "NOT",position)
    elseif node.operator in ("&&","||")
        shortcut,last = Label(),Label()
        generate_expression!(generator,node.left)
        emit!(generator,node.operator == "&&" ? "JUMPF" : "JUMPT",position,shortcut)
        generate_expression!(generator,node.right)
        emit!(generator,"JUMP",position,last)
        mark!(generator,shortcut)
        emit!(generator,"PUSH",position,Int(node.operator == "||"))
        mark!(generator,last)
    else
        generate_expression!(generator,node.left)
        generate_expression!(generator,node.right)
        emit!(generator,BINARY[node.operator],position)
    end
end
function generate_statement!(generator,node)
    kind,position = node.kind,node.position
    if kind == "declaration"
        if node.initializer === nothing
            emit!(generator,"PUSH",node.name_position,0)
        else
            generate_expression!(generator,node.initializer)
        end
        emit!(generator,"STOREL",node.name_position,node.slot)
    elseif kind == "assignment"
        node.index === nothing || generate_expression!(generator,node.index)
        generate_expression!(generator,node.value)
        referent = node.referent
        if node.index !== nothing
            emit!(generator,"STOREA",position,referent.address,referent.size)
        else
            emit!(generator,referent.kind == "global" ? "STOREG" : "STOREL",position,referent.kind == "global" ? referent.address : referent.slot)
        end
    elseif kind == "call_statement"
        generate_expression!(generator,node.expression)
        node.expression.type == "void" || emit!(generator,"POP",position)
    elseif kind == "print"
        foreach(argument -> generate_expression!(generator,argument),node.arguments)
        emit!(generator,"PRINT",position,length(node.arguments))
    elseif kind == "if"
        alternative,last = Label(),Label()
        generate_expression!(generator,node.condition)
        emit!(generator,"JUMPF",position,alternative)
        generate_statement!(generator,node.then)
        if node.otherwise === nothing
            mark!(generator,alternative)
        else
            emit!(generator,"JUMP",position,last)
            mark!(generator,alternative)
            generate_statement!(generator,node.otherwise)
            mark!(generator,last)
        end
    elseif kind == "while"
        start,last = Label(),Label()
        mark!(generator,start)
        generate_expression!(generator,node.condition)
        emit!(generator,"JUMPF",position,last)
        push!(generator.loops,(last,start))
        generate_statement!(generator,node.body)
        pop!(generator.loops)
        emit!(generator,"JUMP",position,start)
        mark!(generator,last)
    elseif kind == "for"
        start,update,last = Label(),Label(),Label()
        node.initial === nothing || generate_statement!(generator,node.initial)
        mark!(generator,start)
        if node.condition !== nothing
            generate_expression!(generator,node.condition)
            emit!(generator,"JUMPF",position,last)
        end
        push!(generator.loops,(last,update))
        generate_statement!(generator,node.body)
        pop!(generator.loops)
        mark!(generator,update)
        node.update === nothing || generate_statement!(generator,node.update)
        emit!(generator,"JUMP",position,start)
        mark!(generator,last)
    elseif kind in ("break","continue")
        emit!(generator,"JUMP",position,generator.loops[end][kind == "continue" ? 2 : 1])
    elseif kind == "return"
        node.value === nothing || generate_expression!(generator,node.value)
        emit!(generator,node.value === nothing ? "RET" : "RETV",position)
    elseif kind == "block"
        foreach(child -> generate_statement!(generator,child),node.statements)
    end
end
function assign_slots!(function_node)
    declarations,pending = ToyNode[],[function_node.body]
    while !isempty(pending)
        node = pop!(pending)
        node.kind == "declaration" && push!(declarations,node)
        append!(pending,statement_children(node))
    end
    sort!(declarations;by=node -> node.name_position)
    slots = [function_node.parameters;declarations]
    for (index,declaration) in enumerate(slots)
        declaration.slot = index-1
    end
    slots
end
function generate(globals,functions,main)
    address = 0
    for variable in globals
        variable.address = address
        address += variable.size === nothing ? 1 : variable.size
    end
    initialization = Generator()
    for variable in globals
        variable.initializer === nothing && continue
        generate_expression!(initialization,variable.initializer)
        emit!(initialization,"STOREG",variable.name_position,variable.address)
    end
    emit!(initialization,"CALL",main.name_position,"main",0)
    emit!(initialization,"HALT",main.name_position)
    units = [CodeUnit("<init>",nothing,ToyNode[],finish_code(initialization))]
    for function_node in functions
        slots = assign_slots!(function_node)
        generator = Generator()
        emit!(generator,"ENTER",function_node.name_position,length(slots))
        generate_statement!(generator,function_node.body)
        function_node.type == "void" && emit!(generator,"RET",function_node.body.end_position)
        push!(units,CodeUnit(function_node.name,function_node,slots,finish_code(generator)))
    end
    units,address
end
