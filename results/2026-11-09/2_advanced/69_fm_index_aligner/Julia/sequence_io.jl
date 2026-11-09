const COMPLEMENT = Dict(zip(collect("ACGTN"),collect("TGCAN")))
reverse_complement(sequence) = join(COMPLEMENT[base] for base in reverse(sequence))
function read_inputs()
    references,name,parts,masked = NamedTuple[],"",String[],0
    for line in readlines("input/reference.fasta")
        if startswith(line,">")
            !isempty(name) && push!(references,(name=name,bases=join(parts),masked=masked))
            name,parts,masked = String(split(line[2:end],' ';limit=2)[1]),String[],0
        else
            masked += count(islowercase,line)
            push!(parts,uppercase(line))
        end
    end
    push!(references,(name=name,bases=join(parts),masked=masked))
    lines = readlines("input/reads.fastq")
    reads = [(name=lines[i][2:end],bases=lines[i+1],quality=lines[i+3]) for i in 1:4:length(lines)]
    params = Dict{String,Vector{Int}}()
    for line in readlines("input/params.txt")
        fields = split(line)
        params[fields[1]] = parse.(Int,fields[2:end])
    end
    references,reads,params
end
