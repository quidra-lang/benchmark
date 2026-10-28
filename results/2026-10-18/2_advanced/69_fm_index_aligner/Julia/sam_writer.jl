using Printf
ratio(a,b) = b==0 ? "-" : @sprintf("%.4f",a/b)
function sam_header(references)
    ["@HD\tVN:1.6\tSO:unsorted";["@SQ\tSN:$(r.name)\tLN:$(length(r.bases))" for r in references];"@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0"]
end
function sam_record(result,references,maximum_alternatives)
    read = result.read
    if !result.mapped
        return join((read.name,4,"*",0,0,"*","*",0,0,read.bases,read.quality,"YM:Z:"*result.reason),'\t')
    end
    alignment = result.primary
    reverse = alignment.strand=='-'
    fields = [
        read.name,
        reverse ? "16" : "0",
        references[alignment.reference].name,
        string(alignment.position+1),
        string(result.mapq),
        alignment.cigar,
        "*",
        "0",
        "0",
        reverse ? reverse_complement(read.bases) : read.bases,
        reverse ? Base.reverse(read.quality) : read.quality,
        "NM:i:$(alignment.nm)",
        "MD:Z:$(alignment.md)",
        "AS:i:$(result.score)",
        "X0:i:$(result.x0)",
        "X1:i:$(result.x1)",
        "YM:Z:$(result.method)"
    ]
    if 1<=length(result.others)<=maximum_alternatives
        alternative = join("$(references[item.reference].name),$(item.strand)$(item.position+1),$(item.cigar),$(item.nm);" for item in result.others)
        push!(fields,"XA:Z:"*alternative)
    end
    join(fields,'\t')
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
