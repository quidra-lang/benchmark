struct TooManySteps <: Exception end

mutable struct BacktrackingVM
    program::Vector{RegexInstruction}
    flags::String
    groups::Int
    text::String
    full::Bool
    steps::Int
end

struct BacktrackState
    instruction::Int
    position::Int
    captures::Vector{Int}
    visited::BitSet
end

function execute!(vm::BacktrackingVM,initial_instruction,initial_position,initial_captures,partial)
    stack = [BacktrackState(initial_instruction,initial_position,copy(initial_captures),BitSet())]
    while !isempty(stack)
        state = pop!(stack)
        pc,position,captures,visited = state.instruction,state.position,state.captures,state.visited
        while true
            vm.steps += 1
            vm.steps > 200000 && throw(TooManySteps())
            instruction = vm.program[pc+1]
            op = instruction.op
            if op in ("CHAR","ANY","CLASS")
                matched = if op == "CHAR"
                    test_char(vm.text,position,instruction.character,vm.flags)
                elseif op == "ANY"
                    test_any(vm.text,position,vm.flags)
                else
                    test_class(vm.text,position,instruction.codes,instruction.negated,vm.flags)
                end
                matched || break
                position += 1
                pc += 1
                visited = BitSet()
            elseif op == "SPLIT"
                pc in visited && break
                visited = union(visited,BitSet([pc]))
                push!(stack,BacktrackState(instruction.y,position,copy(captures),copy(visited)))
                pc = instruction.x
            elseif op == "JMP"
                pc = instruction.x
            elseif op == "SAVE"
                captures[instruction.slot+1] = position
                pc += 1
            elseif op == "ASSERT"
                assertion(instruction.kind,vm.text,position,vm.flags) || break
                pc += 1
            elseif op == "BACKREF"
                beginning,finish = captures[2*instruction.group+1],captures[2*instruction.group+2]
                (beginning < 0 || finish < 0 || beginning > finish) && break
                distance = finish-beginning
                position+distance <= length(vm.text) || break
                all(characters_equal(vm.text[position+offset+1],vm.text[beginning+offset+1],vm.flags) for offset in 0:distance-1) || break
                position += distance
                pc += 1
                distance > 0 && (visited = BitSet())
            elseif op == "LOOK"
                result = execute!(vm,pc+1,position,captures,true)
                if instruction.kind == "NOT"
                    result === nothing || break
                else
                    result === nothing && break
                    captures,new_position = result
                    if instruction.kind == "ATOMIC"
                        new_position > position && (visited = BitSet())
                        position = new_position
                    end
                end
                pc = instruction.x
            elseif partial || !vm.full || position == length(vm.text)
                return captures,position
            else
                break
            end
        end
    end
    nothing
end
function search!(vm::BacktrackingVM,start)
    positions = vm.full ? (0:0) : (start:length(vm.text))
    for beginning in positions
        result = execute!(vm,0,beginning,fill(-1,2*(vm.groups+1)),false)
        result !== nothing && return result[1]
    end
    nothing
end
