const MODELS = ("P","JC","K2P")
const TRANSITIONS = Set([('A','G'),('G','A'),('C','T'),('T','C')])
function pair_counts(first,second,weights)
    sites,transitions,transversions = 0,0,0
    for (a,b,w) in zip(first,second,weights)
        (a in BASES && b in BASES) || continue
        sites += w
        if a!=b
            if (a,b) in TRANSITIONS
                transitions += w
            else
                transversions += w
            end
        end
    end
    (sites,transitions,transversions)
end
function all_pairs(sequences,weights)
    [(
        i,
        j,
        pair_counts(sequences[i],sequences[j],weights)...
    ) for i in 1:length(sequences)-1 for j in i+1:length(sequences)]
end
function corrected(model,n,s,v,replacement)
    saturated = n==0 || (model=="JC" && 4*(s+v)>=3n) || (model=="K2P" && (2s+v>=n || 2v>=n))
    saturated && return replacement,true
    value = model=="P" ? (s+v)/n : model=="JC" ? -(3/4)*log(1-(4*(s+v))/(3n)) : -(1/2)*log(1-(2s)/n-v/n)-(1/4)*log(1-(2v)/n)
    value,false
end
function build_matrix(pairs,n,model,replacement)
    matrix,saturated = zeros(n,n),NTuple{3,Int}[]
    for (i,j,sites,s,v) in pairs
        value,replaced = corrected(model,sites,s,v,replacement)
        matrix[i,j] = matrix[j,i] = value
        replaced && push!(saturated,(i,j,sites))
    end
    matrix,saturated
end
