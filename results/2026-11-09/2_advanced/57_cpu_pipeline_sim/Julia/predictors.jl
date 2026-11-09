mutable struct BTB
    tags::Vector{Int}
    targets::Vector{Int}
end
BTB(entries::Int) = BTB(fill(-1,entries),zeros(Int,entries))
function lookup(table,pc)
    index = (pc÷4)%length(table.tags)+1
    table.tags[index]==pc ? table.targets[index] : nothing
end
function btb_insert!(table,pc,target)
    index = (pc÷4)%length(table.tags)+1
    table.tags[index],table.targets[index] = pc,target
end
mutable struct RAS
    depth::Int
    stack::Vector{Int}
end
RAS(depth::Int) = RAS(depth,Int[])
function ras_push!(ras,address)
    ras.depth==0 && return
    length(ras.stack)==ras.depth && popfirst!(ras.stack)
    push!(ras.stack,address)
end
ras_pop!(ras) = isempty(ras.stack) ? nothing : pop!(ras.stack)
updated(counter,taken) = taken ? min(3,counter+1) : max(0,counter-1)
mutable struct DirectionPredictor
    scheme::String
    parameters::Vector{Int}
    history::Int
    table::Vector{Int}
    local_table::Vector{Int}
    global_table::Vector{Int}
    chooser::Vector{Int}
end
function DirectionPredictor(scheme,parameters)
    table,local_table,global_table,chooser = Int[],Int[],Int[],Int[]
    if scheme in ("ONEBIT","TWOBIT","GSHARE")
        table = fill(scheme=="ONEBIT" ? 0 : 1,parameters[1])
    elseif scheme=="TOURNAMENT"
        local_table,global_table,chooser = ones(Int,parameters[1]),ones(Int,parameters[2]),ones(
            Int,
            parameters[4]
        )
    end
    DirectionPredictor(scheme,parameters,0,table,local_table,global_table,chooser)
end
function direction_prediction(predictor,pc,target)
    scheme = predictor.scheme
    scheme in ("STATIC_NT","PERFECT") && return false
    scheme=="BTFN" && return target<pc
    if scheme in ("ONEBIT","TWOBIT","GSHARE")
        index = (scheme=="GSHARE" ? xor(pc÷4,predictor.history) : pc÷4)%length(predictor.table)+1
        return scheme=="ONEBIT" ? predictor.table[index]==1 : predictor.table[index]>=2
    end
    local_prediction = predictor.local_table[(pc÷4)%length(predictor.local_table)+1]>=2
    global_prediction = predictor.global_table[xor(
        pc÷4,
        predictor.history
    )%length(predictor.global_table)+1]>=2
    predictor.chooser[(pc÷4)%length(predictor.chooser)+1]>=2 ? global_prediction : local_prediction
end
function direction_update!(predictor,pc,taken)
    scheme = predictor.scheme
    scheme in ("STATIC_NT","BTFN","PERFECT") && return
    if scheme=="TOURNAMENT"
        li = (pc÷4)%length(predictor.local_table)+1
        gi = xor(pc÷4,predictor.history)%length(predictor.global_table)+1
        ci = (pc÷4)%length(predictor.chooser)+1
        lp,gp = predictor.local_table[li]>=2,predictor.global_table[gi]>=2
        lp!=gp && (predictor.chooser[ci]=updated(predictor.chooser[ci],gp==taken))
        predictor.local_table[li] = updated(predictor.local_table[li],taken)
        predictor.global_table[gi] = updated(predictor.global_table[gi],taken)
        predictor.history = (2predictor.history+taken)%(1<<predictor.parameters[3])
    else
        index = (scheme=="GSHARE" ? xor(pc÷4,predictor.history) : pc÷4)%length(predictor.table)+1
        predictor.table[index] = scheme=="ONEBIT" ? Int(taken) : updated(predictor.table[index],taken)
        scheme=="GSHARE" && (predictor.history=(2predictor.history+taken)%(1<<predictor.parameters[2]))
    end
end
function storage_bits(predictor)
    scheme,p = predictor.scheme,predictor.parameters
    scheme in ("STATIC_NT","BTFN","PERFECT") && return 0
    scheme=="ONEBIT" && return p[1]
    scheme=="TWOBIT" && return 2p[1]
    scheme=="GSHARE" && return 2p[1]+p[2]
    2*(p[1]+p[2]+p[4])+p[3]
end
