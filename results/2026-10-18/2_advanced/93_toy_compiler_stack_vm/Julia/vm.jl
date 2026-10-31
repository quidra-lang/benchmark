const MIN_INT = -2147483648
const MAX_INT = 2147483647
const BINARY_OPS = Set(["ADD","SUB","MUL","DIV","MOD","LT","LE","GT","GE","EQ","NE"])
struct RuntimeFault <: Exception
    message::String
end
struct CallFrame
    locals::Vector{Int64}
    return_address::Int
end
function calculate(op,a,b=0)
    op in ("DIV","MOD") && b == 0 && throw(RuntimeFault("division by zero"))
    result = if op == "ADD"
        a+b
    elseif op == "SUB"
        a-b
    elseif op == "MUL"
        a*b
    elseif op == "DIV"
        div(a,b)
    elseif op == "MOD"
        rem(a,b)
    elseif op == "NEG"
        -a
    elseif op == "NOT"
        Int64(a == 0)
    elseif op == "LT"
        Int64(a < b)
    elseif op == "LE"
        Int64(a <= b)
    elseif op == "GT"
        Int64(a > b)
    elseif op == "GE"
        Int64(a >= b)
    elseif op == "EQ"
        Int64(a == b)
    else
        Int64(a != b)
    end
    MIN_INT <= result <= MAX_INT || throw(RuntimeFault("integer overflow"))
    result
end
mutable struct Execution
    code::Vector{Instruction}
    owners::Vector{String}
    starts::Dict{Int,String}
    inputs::Vector{Int64}
    globals::Vector{Int64}
    stack::Vector{Int64}
    frames::Vector{CallFrame}
    read_position::Int
    pc::Int
    executed::Int
    counts::Vector{Int}
    calls::Dict{String,Int}
    pairs::Dict{Tuple{String,String},Int}
    max_stack::Int
    max_depth::Int
    output::Vector{String}
    error::Union{Nothing,String}
    error_pc::Int
end
function Execution(code,owners,starts,global_size,inputs)
    Execution(code,owners,starts,inputs,zeros(Int64,global_size),Int64[],CallFrame[],1,0,0,zeros(Int,length(code)),
        Dict{String,Int}(),Dict{Tuple{String,String},Int}(),0,0,String[],nothing,-1)
end
function vm_step!(execution)
    entry = execution.code[execution.pc+1]
    op,args,stack = entry.op,entry.args,execution.stack
    next_pc = execution.pc+1
    if op == "PUSH"
        push!(stack,args[1])
    elseif op == "POP"
        pop!(stack)
    elseif op == "LOADG"
        push!(stack,execution.globals[args[1]+1])
    elseif op == "STOREG"
        execution.globals[args[1]+1] = pop!(stack)
    elseif op == "LOADL"
        push!(stack,execution.frames[end].locals[args[1]+1])
    elseif op == "STOREL"
        execution.frames[end].locals[args[1]+1] = pop!(stack)
    elseif op in ("LOADA","STOREA")
        value = op == "STOREA" ? pop!(stack) : 0
        index = pop!(stack)
        address,size = args
        0 <= index < size || throw(RuntimeFault("index $index out of bounds for array of size $size"))
        if op == "LOADA"
            push!(stack,execution.globals[address+index+1])
        else
            execution.globals[address+index+1] = value
        end
    elseif op in BINARY_OPS
        b,a = pop!(stack),pop!(stack)
        push!(stack,calculate(op,a,b))
    elseif op in ("NEG","NOT")
        push!(stack,calculate(op,pop!(stack)))
    elseif op == "JUMP"
        next_pc = args[1]
    elseif op in CONDITIONAL
        value = pop!(stack)
        (value == 0) == (op == "JUMPF") && (next_pc = args[1])
    elseif op == "CALL"
        length(execution.frames) == 100 && throw(RuntimeFault("call depth limit exceeded"))
        target,argument_count = args
        values = argument_count == 0 ? Int64[] : copy(stack[end-argument_count+1:end])
        resize!(stack,length(stack)-argument_count)
        push!(execution.frames,CallFrame(values,next_pc))
        callee = execution.starts[target]
        execution.calls[callee] = get(execution.calls,callee,0)+1
        pair = (execution.owners[execution.pc+1],callee)
        execution.pairs[pair] = get(execution.pairs,pair,0)+1
        next_pc = target
    elseif op == "ENTER"
        local_area = execution.frames[end].locals
        append!(local_area,zeros(Int64,args[1]-length(local_area)))
    elseif op in ("RET","RETV")
        next_pc = pop!(execution.frames).return_address
    elseif op == "READ"
        execution.read_position > length(execution.inputs) && throw(RuntimeFault("read past end of input"))
        push!(stack,execution.inputs[execution.read_position])
        execution.read_position += 1
    elseif op == "PRINT"
        argument_count = args[1]
        values = stack[end-argument_count+1:end]
        resize!(stack,length(stack)-argument_count)
        push!(execution.output,join(values," "))
    end
    execution.max_stack = max(execution.max_stack,length(stack))
    execution.max_depth = max(execution.max_depth,length(execution.frames))
    execution.pc = next_pc
    op != "HALT"
end
function run_vm!(execution)
    while true
        if execution.executed == 100000
            execution.error,execution.error_pc = "instruction limit exceeded",execution.pc
            break
        end
        execution.executed += 1
        execution.counts[execution.pc+1] += 1
        try
            vm_step!(execution) || break
        catch error
            error isa RuntimeFault || rethrow()
            execution.error,execution.error_pc = error.message,execution.pc
            break
        end
    end
    execution
end
