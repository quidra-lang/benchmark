const BASES = ['A','C','G','T']
const AMBIGUOUS = Set(collect("RYSWKMBDHV"))
const BASE_SETS = Dict(zip(collect("ACGTRYSWKMBDHVN-"),(1,2,4,8,5,10,6,9,12,3,14,13,11,7,15,15)))
function read_fasta()
    records,name,pieces,header = NamedTuple[],"",String[],0
    for (line_number,line) in enumerate(readlines("input/alignment.fasta"))
        if startswith(line,">")
            header!=0 && push!(records,(line=header,name=name,sequence=uppercase(join(pieces))))
            name,header,pieces = String(split(line[2:end],' ';limit=2)[1]),line_number,String[]
        else
            push!(pieces,line)
        end
    end
    push!(records,(line=header,name=name,sequence=uppercase(join(pieces))))
    records
end
function compress_patterns(sequences)
    patterns,columns,weights,numbers = String[],Int[],Int[],Dict{String,Int}()
    for c in eachindex(sequences[1])
        pattern = join(sequence[c] for sequence in sequences)
        if !haskey(numbers,pattern)
            push!(patterns,pattern)
            push!(weights,0)
            numbers[pattern] = length(patterns)
        end
        index = numbers[pattern]
        push!(columns,index)
        weights[index] += 1
    end
    (
        patterns=patterns,
        columns=columns,
        weights=weights,
        encoded=[[BASE_SETS[c] for c in pattern] for pattern in patterns]
    )
end
function classify_columns(sequences)
    totals = zeros(Int,5)
    for c in eachindex(sequences[1])
        characters = [sequence[c] for sequence in sequences]
        counts = [count(==(base),characters) for base in BASES]
        kinds = count(>(0),counts)
        totals[kinds==0 ? 5 : kinds==1 ? 1 : 2] += 1
        totals[3] += count(>=(2),counts)>=2
        totals[4] += '-' in characters
    end
    totals
end
