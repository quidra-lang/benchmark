const SAFETY_PROPERTIES = (
    "ELECTION_SAFETY",
    "LEADER_COMPLETENESS",
    "LOG_MATCHING",
    "STATE_MACHINE_SAFETY",
    "COMMITTED_KEPT"
)
Base.@kwdef mutable struct SafetyChecker
    violations::Vector{Int} = zeros(Int,5)
    leaders::Dict{Int,Int} = Dict{Int,Int}()
    committed::Dict{Int,Tuple{Int,Int}} = Dict{Int,Tuple{Int,Int}}()
    applied::Dict{Int,Tuple{LogEntry,Union{Nothing,Int,String}}} = Dict{Int,Tuple{LogEntry,Union{Nothing,Int,String}}}()
    elected::Int = 0
    log_checks::Int = 0
    pair_checks::Int = 0
    applies::Int = 0
    truncations::Int = 0
    removed::Int = 0
end
function check_leader!(checker,node)
    checker.elected += 1
    if !haskey(checker.leaders,node.term)
        checker.leaders[node.term] = node.number
    elseif checker.leaders[node.term]!=node.number
        checker.violations[1] += 1
    end
    any(i>last_index(node) || term_at(node,i)!=record[1] for (
        i,
        record
    ) in checker.committed) && (checker.violations[2]+=1)
end
record_commit!(checker,index,term,time) = get!(checker.committed,index,(term,time))
function record_apply!(checker,index,entry,result)
    checker.applies += 1
    if !haskey(checker.applied,index)
        checker.applied[index] = (entry,result)
    elseif checker.applied[index][1]!=entry
        checker.violations[4] += 1
    end
end
function check_truncate!(checker,first,entries)
    checker.truncations += 1
    checker.removed += length(entries)
    for (offset,entry) in enumerate(entries)
        index = first+offset-1
        haskey(
            checker.committed,
            index
        ) && checker.committed[index][1]==entry.term && (checker.violations[5]+=1)
    end
end
function check_logs!(checker,nodes)
    checker.log_checks += 1
    for a in eachindex(nodes),b in a+1:length(nodes)
        checker.pair_checks += 1
        first,second = nodes[a],nodes[b]
        limit = min(last_index(first),last_index(second))
        greatest = 0
        for i in limit:-1:1
            if term_at(first,i)==term_at(second,i)
                greatest = i
                break
            end
        end
        any(first.log[i]!=second.log[i] for i in 1:greatest) && (checker.violations[3]+=1)
    end
end
function checker_lines(c,maximum_term)
    details = ["terms $maximum_term leaders $(length(c.leaders)) elected $(c.elected)",
        "checks $(c.elected) committed $(length(c.committed))","checks $(c.log_checks) pairs $(c.pair_checks)",
        "applies $(c.applies) indices $(length(c.applied))","truncations $(c.truncations) removed $(c.removed)"]
    ["$(SAFETY_PROPERTIES[i]) $(c.violations[i]==0 ? "OK" : "FAIL") violations $(c.violations[i]) $(details[i])" for i in 1:5]
end
