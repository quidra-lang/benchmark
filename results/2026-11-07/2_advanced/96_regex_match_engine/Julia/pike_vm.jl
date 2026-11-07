mutable struct PikeVM
    program::Vector{RegexInstruction}
    flags::String
    groups::Int
    text::String
    full::Bool
    steps::Int
end

struct PikeThread
    instruction::Int
    captures::Vector{Int}
end

struct ThreadList
    threads::Vector{PikeThread}
    marks::BitSet
end
ThreadList() = ThreadList(PikeThread[],BitSet())

function add_thread!(vm,list,instruction,captures,position)
    pending = [PikeThread(instruction,captures)]
    while !isempty(pending)
        thread = pop!(pending)
        pc,current_captures = thread.instruction,thread.captures
        pc in list.marks && continue
        push!(list.marks,pc)
        vm.steps += 1
        entry = vm.program[pc+1]
        if entry.op == "JMP"
            push!(pending,PikeThread(entry.x,current_captures))
        elseif entry.op == "SPLIT"
            push!(pending,PikeThread(entry.y,current_captures),PikeThread(entry.x,current_captures))
        elseif entry.op == "SAVE"
            updated = copy(current_captures)
            updated[entry.slot+1] = position
            push!(pending,PikeThread(pc+1,updated))
        elseif entry.op == "ASSERT"
            assertion(entry.kind,vm.text,position,vm.flags) && push!(pending,PikeThread(pc+1,current_captures))
        else
            push!(list.threads,PikeThread(pc,copy(current_captures)))
        end
    end
end
function search!(vm::PikeVM,start)
    current = ThreadList()
    position = start
    matched = nothing
    while true
        if matched === nothing && (!vm.full || position == start)
            add_thread!(vm,current,0,fill(-1,2*(vm.groups+1)),position)
        end
        following = ThreadList()
        for thread in current.threads
            vm.steps += 1
            entry = vm.program[thread.instruction+1]
            if entry.op == "MATCH"
                if !vm.full || position == length(vm.text)
                    matched = copy(thread.captures)
                    break
                end
                continue
            end
            accepts = if entry.op == "CHAR"
                test_char(vm.text,position,entry.character,vm.flags)
            elseif entry.op == "ANY"
                test_any(vm.text,position,vm.flags)
            else
                test_class(vm.text,position,entry.codes,entry.negated,vm.flags)
            end
            accepts && add_thread!(vm,following,thread.instruction+1,thread.captures,position+1)
        end
        position == length(vm.text) && return matched
        isempty(following.threads) && (matched !== nothing || vm.full) && return matched
        current = following
        position += 1
    end
end
