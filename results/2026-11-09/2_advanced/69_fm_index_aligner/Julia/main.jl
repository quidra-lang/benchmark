include("sequence_io.jl")
include("suffix_array.jl")
include("fm_index.jl")
include("search.jl")
include("sam_writer.jl")

words(parts...) = join(string.(parts)," ")
value(s,name) = s.params[name][1]
function reference_text(references)
    offsets,offset = Int[],0
    for reference in references
        push!(offsets,offset)
        offset += length(reference.bases)+1
    end
    text = join([r.bases for r in references],"#")*"\$"
    (references=references,offsets=offsets,text=text,reverse=reverse(text[1:end-1])*"\$")
end
function text_position(text,p)
    r = searchsortedlast(text.offsets,p)
    offset = p-text.offsets[r]
    offset<length(text.references[r].bases) ? (r,offset) : nothing
end
function position_label(text,p)
    located = text_position(text,p)
    isnothing(located) ? "*" : "$(text.references[located[1]].name):$(located[2]+1)"
end
function operation_runs(operations)
    result = Tuple{Char,Int}[]
    for op in operations
        if !isempty(result) && result[end][1]==op
            result[end] = (op,result[end][2]+1)
        else
            push!(result,(op,1))
        end
    end
    result
end
function describe(reference,position,strand,operations,core,trimmed,references)
    oriented = strand=='+' ? core : reverse_complement(core)
    sequence = references[reference].bases
    cigar,md,pairs = String[],String[],Tuple{Int,Int}[]
    i,j,matches,nm = 0,position,0,0
    for (op,n) in operation_runs(operations)
        push!(cigar,"$n$op")
        if op=='I'
            i += n
            nm += n
        elseif op=='D'
            push!(md,"$matches^$(sequence[j+1:j+n])")
            matches = 0
            j += n
            nm += n
        else
            for _ in 1:n
                push!(pairs,(i,j))
                if oriented[i+1]==sequence[j+1]
                    matches += 1
                else
                    push!(md,"$matches$(sequence[j+1])")
                    matches = 0
                    nm += 1
                end
                i,j = i+1,j+1
            end
        end
    end
    push!(md,string(matches))
    if trimmed>0
        strand=='+' ? push!(cigar,"$(trimmed)S") : pushfirst!(cigar,"$(trimmed)S")
    end
    (
        reference=reference,
        position=position,
        strand=strand,
        operations=operations,
        oriented=oriented,
        pairs=pairs,
        cigar=join(cigar),
        nm=nm,
        md=join(md)
    )
end
function banded_alignment(oriented,sequence,center,width,scores)
    match,mismatch,gap_open,gap_extend = scores
    l,m = length(oriented),length(sequence)
    lo,hi = max(0,center-width),min(m,l+center+width)
    lo>hi && return nothing
    unreachable = -1000000
    h,e,f = fill(unreachable,l+1,hi-lo+1),fill(unreachable,l+1,hi-lo+1),fill(unreachable,l+1,hi-lo+1)
    cell(matrix,i,j) = 0<=i<=l && lo<=j<=hi ? matrix[i+1,j-lo+1] : unreachable
    subtract(v,p) = v==unreachable ? unreachable : v-p
    for j in max(0,center-width):min(m,center+width)
        h[1,j-lo+1] = 0
    end
    for i in 1:l,j in max(0,i+center-width):min(m,i+center+width)
        column = j-lo+1
        f[i+1,column] = max(subtract(cell(h,i-1,j),gap_open+gap_extend),subtract(cell(f,i-1,j),gap_extend))
        diagonal = unreachable
        if j>=1
            e[i+1,column] = max(
                subtract(cell(h,i,j-1),gap_open+gap_extend),
                subtract(cell(e,i,j-1),gap_extend)
            )
            previous = cell(h,i-1,j-1)
            previous!=unreachable && (diagonal=previous+(oriented[i]==sequence[j] ? match : -mismatch))
        end
        h[i+1,column] = max(diagonal,e[i+1,column],f[i+1,column])
    end
    endpoints = [j for j in lo:hi if cell(h,l,j)!=unreachable]
    isempty(endpoints) && return nothing
    j = argmax(j->cell(h,l,j),endpoints)
    score,i,state,backward = cell(h,l,j),l,'H',Char[]
    while true
        if state=='H'
            i==0 && break
            previous = j>=1 ? cell(h,i-1,j-1) : unreachable
            if previous!=unreachable && cell(h,i,j)==previous+(oriented[i]==sequence[j] ? match : -mismatch)
                push!(backward,'M')
                i,j = i-1,j-1
                continue
            end
            state = cell(f,i,j)!=unreachable && cell(h,i,j)==cell(f,i,j) ? 'I' : 'D'
        elseif state=='I'
            push!(backward,'I')
            previous = cell(f,i-1,j)
            state = previous!=unreachable && cell(f,i,j)==previous-gap_extend ? 'I' : 'H'
            i -= 1
        else
            push!(backward,'D')
            previous = cell(e,i,j-1)
            state = previous!=unreachable && cell(e,i,j)==previous-gap_extend ? 'D' : 'H'
            j -= 1
        end
    end
    (score=score,position=j,operations=join(reverse(backward)))
end
Base.@kwdef mutable struct MappingResult
    read::NamedTuple
    core::String
    qualities::Vector{Int}
    length::Int
    trimmed::Int
    mapped::Bool = false
    reason::String = "SHORT"
    primary::Union{Nothing,NamedTuple} = nothing
    others::Vector{NamedTuple} = NamedTuple[]
    method::String = ""
    score::Int = 0
    mapq::Int = 0
    x0::Int = 0
    x1::Int = 0
    targets::Vector{Int} = Int[]
end
function make_candidates(s,oriented)
    candidates = Set{NTuple{3,Int}}()
    seed_length = value(s,"SEED_LENGTH")
    for (strand,sequence) in enumerate(oriented),offset in 0:value(s,"SEED_STEP"):length(sequence)-seed_length
        s.seed_counts[2] += 1
        seed = sequence[offset+1:offset+seed_length]
        if 'N' in seed
            s.seed_counts[3] += 1
            continue
        end
        lower,upper = backward_search(s.forward,seed)
        if upper-lower>value(s,"MAX_SEED_HITS")
            s.seed_counts[4] += 1
        elseif lower>=upper
            s.seed_counts[5] += 1
        else
            for row in lower:upper-1
                position,_ = locate(s.forward,row)
                r,p = text_position(s.text,position)
                push!(candidates,(strand,r,p-offset))
            end
        end
    end
    s.seed_counts[6] += length(candidates)
    sort!(collect(candidates))
end
function seed_and_extend!(s,result,oriented)
    result.reason = "NOHIT"
    result.length<value(s,"SEED_LENGTH") && return
    s.seed_counts[1] += 1
    accepted = Dict{NTuple{3,Int},NamedTuple}()
    scores = s.params["SCORES"]
    threshold = value(s,"MIN_SCORE_PERCENT")*scores[1]*result.length
    for (strand,r,center) in make_candidates(s,oriented)
        alignment = banded_alignment(
            oriented[strand],
            s.references[r].bases,
            center,
            value(s,"BAND_WIDTH"),
            scores
        )
        (isnothing(alignment) || 100*alignment.score<threshold) && continue
        key = (r,alignment.position,strand)
        (!haskey(accepted,key) || alignment.score>accepted[key].score) && (accepted[key]=alignment)
    end
    s.seed_counts[7] += length(accepted)
    isempty(accepted) && return
    ordered = sort!([(
        score=a.score,
        reference=r,
        position=p,
        strand=strand,
        operations=a.operations
    ) for ((r,p,strand),a) in accepted];by=a->(-a.score,a.reference,a.position,a.strand))
    best = ordered[1].score
    best_count = count(a->a.score==best,ordered)
    second = maximum((a.score for a in ordered if a.score<best);init=0)
    alignments = [describe(
        a.reference,
        a.position,
        a.strand==1 ? '+' : '-',
        a.operations,
        result.core,
        result.trimmed,
        s.references
    ) for a in ordered]
    result.mapped,result.primary,result.others,result.method,result.score = true,alignments[1],alignments[2:end],"SEED",best
    result.mapq,result.x0,result.x1 = best_count>=2 ? 0 : 60*(best-second)÷best,best_count,length(ordered)-best_count
    result.targets = sort!(unique([a.reference for a in ordered if a.score==best]))
end
function map_read(s,read)
    qualities = [Int(c)-33 for c in read.quality]
    n = length(read.bases)
    while n>0 && qualities[n]<value(s,"TRIM_QUALITY")
        n -= 1
    end
    result = MappingResult(
        read=read,
        core=read.bases[1:n],
        qualities=qualities,
        length=n,
        trimmed=length(read.bases)-n
    )
    n<value(s,"MIN_READ_LENGTH") && return result
    oriented = (result.core,reverse_complement(result.core))
    exact = [backward_search(s.forward,sequence) for sequence in oriented]
    maximum_mismatches = any(interval->interval[1]<interval[2],exact) ? 1 : value(s,"MAX_MISMATCHES")
    hits = NTuple{4,Int}[]
    for (strand,sequence) in enumerate(oriented)
        search = backtrack(sequence,maximum_mismatches,s.forward,s.reverse)
        s.search_counts .+= [1,search.nodes,length(search.leaves),search.positions]
        for (lower,upper,mm) in search.leaves,row in lower:upper-1
            position,_ = locate(s.forward,row)
            r,p = text_position(s.text,position)
            push!(hits,(mm,r,p,strand))
        end
    end
    if isempty(hits)
        seed_and_extend!(s,result,oriented)
        return result
    end
    sort!(hits)
    best = hits[1][1]
    n1,n2 = count(h->h[1]==best,hits),count(h->h[1]==best+1,hits)
    alignments = [describe(
        r,
        p,
        strand==1 ? '+' : '-',
        repeat("M",n),
        result.core,
        result.trimmed,
        s.references
    ) for (mm,r,p,strand) in hits if mm<=best+1]
    result.mapped,result.primary,result.others = true,alignments[1],alignments[2:end]
    result.method,result.score = best==0 ? "EXACT" : "MISMATCH",(n-best)*s.params["SCORES"][1]-best*s.params["SCORES"][2]
    result.mapq = n1>=2 ? 0 : n2==0 ? 60-12best : max(30-12best-3n2,1)
    result.x0,result.x1 = n1,n2
    result.targets = sort!(unique([r for (mm,r,_,_) in hits if mm==best]))
    result
end
function index_statistics(text,suffixes,classes,forward,reverse_suffixes,reverse_classes,reverse_index,params)
    references,n = text.references,length(text.text)
    lines = [words("text length",n,"sequences",length(references))]
    for (i,r) in enumerate(references)
        push!(
            lines,
            words(
                "sequence",
                r.name,
                "length",
                length(r.bases),
                "offset",
                text.offsets[i],
                "gc",
                ratio(count(c->c in ('G','C'),r.bases),length(r.bases)),
                "masked",
                r.masked
            )
        )
    end
    push!(lines,"symbols "*join((words(symbol,count(==(symbol),text.text)) for symbol in SYMBOLS)," "))
    append!(lines,["","forward_index",words("suffix_array rounds",length(classes)-1)])
    for (i,nclasses) in enumerate(classes)
        push!(lines,words("round",i-1,"prefix_length",1<<(i-1),"classes",nclasses))
    end
    check = adjacent_check(text.text,suffixes)
    push!(
        lines,
        words(
            "sa_check pairs",
            n-1,
            "ordered",
            check.ordered,
            "lcp_sum",
            check.lcp_sum,
            "mean_lcp",
            ratio(check.lcp_sum,n-1),
            "max_lcp",
            check.longest
        )
    )
    push!(
        lines,
        words(
            "longest_repeat",
            check.longest,
            position_label(text,suffixes[check.row]),
            position_label(text,suffixes[check.row+1])
        )
    )
    seed_length = params["SEED_LENGTH"][1]
    kmers = Dict{String,Int}()
    for r in references,p in 0:length(r.bases)-seed_length
        kmer = r.bases[p+1:p+seed_length]
        kmers[kmer] = get(kmers,kmer,0)+1
    end
    occurrences,unique_count = sum(values(kmers)),count(==(1),values(kmers))
    push!(
        lines,
        words(
            "kmers length",
            seed_length,
            "occurrences",
            occurrences,
            "distinct",
            length(kmers),
            "unique",
            unique_count,
            "max_occurrence",
            maximum(values(kmers)),
            "unique_fraction",
            ratio(unique_count,occurrences)
        )
    )
    push!(lines,words("bwt runs",length(operation_runs(forward.bwt)),"head",join(forward.bwt[1:min(60,n)])))
    push!(lines,"c_array "*join((words(symbol,forward.c[symbol]) for symbol in SYMBOLS)," "))
    push!(lines,words("occ interval",forward.interval,"checkpoints",length(forward.checkpoints)))
    push!(lines,words("sa_sample interval",params["SA_SAMPLE_INTERVAL"][1],"samples",length(forward.samples)))
    correct,total_steps,max_steps = 0,0,0
    for (i,p) in enumerate(suffixes)
        located,steps = locate(forward,i-1)
        correct += located==p
        total_steps += steps
        max_steps = max(max_steps,steps)
    end
    push!(
        lines,
        words(
            "locate rows",
            n,
            "correct",
            correct,
            "total_steps",
            total_steps,
            "max_steps",
            max_steps,
            "mean_steps",
            ratio(total_steps,n)
        )
    )
    push!(lines,"inverse_bwt identical "*(inverse_bwt(forward)==text.text ? "yes" : "no"))
    append!(
        lines,
        [
            "",
            "reverse_index",
            words("suffix_array rounds",length(reverse_classes)-1),
            words("sa_check pairs",n-1,"ordered",adjacent_check(text.reverse,reverse_suffixes).ordered),
            words(
                "bwt runs",
                length(operation_runs(reverse_index.bwt)),
                "head",
                join(reverse_index.bwt[1:min(60,n)])
            ),
            "inverse_bwt identical "*(inverse_bwt(reverse_index)==text.reverse ? "yes" : "no"),
            "",
            "direct_sort"
        ]
    )
    checks = 0
    for r in references
        if length(r.bases)<=params["DIRECT_SORT_LIMIT"][1]
            sequence = r.bases*"\$"
            doubled,counts = build_suffix_array(sequence)
            push!(
                lines,
                words(
                    r.name,
                    "length",
                    length(sequence),
                    "rounds",
                    length(counts)-1,
                    "identical",
                    doubled==direct_sort(sequence) ? "yes" : "no"
                )
            )
            checks += 1
        end
    end
    checks==0 && push!(lines,"none")
    occurrence_bytes,sample_bytes,bitmap_bytes = 24length(forward.checkpoints),4length(forward.samples),(n+7)÷8
    total = n+occurrence_bytes+sample_bytes+bitmap_bytes
    append!(
        lines,
        [
            "",
            words(
                "index_size bwt_bytes",
                n,
                "occ_bytes",
                occurrence_bytes,
                "sample_bytes",
                sample_bytes,
                "bitmap_bytes",
                bitmap_bytes,
                "total_bytes",
                total,
                "full_bytes",
                5n,
                "ratio",
                ratio(total,5n)
            )
        ]
    )
    lines
end
function coverage_and_variants(results,references,params)
    depths,starts = [zeros(Int,length(r.bases)) for r in references],[zeros(
        Int,
        length(r.bases)
    ) for r in references]
    pileups = [zeros(Int,length(r.bases),4,2) for r in references]
    min_depth,min_quality,min_alt,hom_percent = params["VARIANTS"]
    minimum_mapq = params["COVERAGE_MIN_MAPQ"][1]
    for result in results
        result.mapped || continue
        a = result.primary
        r,strand = a.reference,a.strand=='+' ? 1 : 2
        result.mapq==0 && (starts[r][a.position+1]+=1)
        result.mapq<minimum_mapq && continue
        for (i,j) in a.pairs
            depths[r][j+1] += 1
            base = a.oriented[i+1]
            cycle = strand==1 ? i+1 : result.length-i
            if base!='N' && result.qualities[cycle]>=min_quality
                pileups[r][j+1,findfirst(==(base),BASES),strand] += 1
            end
        end
    end
    window = params["COVERAGE_WINDOW"][1]
    coverage = [words("window",window,"min_mapq",minimum_mapq)]
    variants = [words(
        "min_depth",
        min_depth,
        "min_base_quality",
        min_quality,
        "min_alt_percent",
        min_alt,
        "hom_percent",
        hom_percent
    )]
    callable_count,variant_count,heterozygous,homozygous = 0,0,0,0
    for (r,reference) in enumerate(references)
        n,depth = length(reference.bases),depths[r]
        covered = count(>(0),depth)
        push!(
            coverage,
            words(
                "reference",
                reference.name,
                "length",
                n,
                "covered",
                covered,
                "breadth",
                ratio(covered,n),
                "mean_depth",
                ratio(sum(depth),n),
                "max_depth",
                maximum(depth)
            )
        )
        push!(coverage,"depth_histogram "*join(("$d:$(count(==(d),depth))" for d in 0:maximum(depth))," "))
        for first in 0:window:n-1
            last = min(first+window,n)
            values = depth[first+1:last]
            sequence = reference.bases[first+1:last]
            total,size_window = sum(values),last-first
            push!(
                coverage,
                words(
                    reference.name,
                    first+1,
                    last,
                    "gc",
                    ratio(count(c->c in ('G','C'),sequence),size_window),
                    "sum",
                    total,
                    "mean",
                    ratio(total,size_window),
                    "max",
                    maximum(values),
                    "zero",
                    count(==(0),values),
                    "mapq0",
                    sum(starts[r][first+1:last]),
                    "|"*repeat("#",10total÷size_window)
                )
            )
        end
        for j in 1:n
            counts = [pileups[r][j,b,1]+pileups[r][j,b,2] for b in 1:4]
            dp = sum(counts)
            dp<min_depth && continue
            callable_count += 1
            ref_base = reference.bases[j]
            alternative = argmax(b->counts[b],[b for b in 1:4 if BASES[b]!=ref_base])
            alt_count = counts[alternative]
            (alt_count<2 || 100alt_count<min_alt*dp) && continue
            hom = 100alt_count>=hom_percent*dp
            homozygous += hom
            heterozygous += !hom
            variant_count += 1
            push!(
                variants,
                words(
                    reference.name,
                    j,
                    "$ref_base>$(BASES[alternative])",
                    "depth",
                    dp,
                    "alt",
                    alt_count,
                    "fraction",
                    ratio(alt_count,dp),
                    "genotype",
                    hom ? "1/1" : "0/1",
                    "strands",
                    pileups[r][j,alternative,1],
                    pileups[r][j,alternative,2],
                    "counts",
                    join(counts," ")
                )
            )
        end
    end
    push!(
        variants,
        words(
            "callable",
            callable_count,
            "variants",
            variant_count,
            "heterozygous",
            heterozygous,
            "homozygous",
            homozygous
        )
    )
    coverage,variants
end
function error_statistics(results,references)
    maximum_cycle = maximum(length(r.read.bases) for r in results)
    cycles,substitutions = zeros(Int,maximum_cycle,2),zeros(Int,4,5)
    quality_counts,quality_sums,quality_bins = zeros(Int,2),zeros(Int,2),zeros(Int,5,2)
    operation_counts,events,indel_bases = Dict(c=>0 for c in "MIDS"),Dict(c=>0 for c in "ID"),Dict(c=>0 for c in "ID")
    for result in results
        result.mapped || continue
        a = result.primary
        for op in a.operations
            operation_counts[op] += 1
        end
        operation_counts['S'] += result.trimmed
        result.x0==1 || continue
        sequence = references[a.reference].bases
        for (i,j) in a.pairs
            observed,reference = a.oriented[i+1],sequence[j+1]
            mismatch = Int(observed!=reference)
            cycle = a.strand=='+' ? i+1 : result.length-i
            quality = result.qualities[cycle]
            cycles[cycle,1] += 1
            cycles[cycle,2] += mismatch
            substitutions[findfirst(==(reference),BASES),findfirst(==(observed),collect("ACGTN"))] += 1
            quality_counts[mismatch+1] += 1
            quality_sums[mismatch+1] += quality
            bin = min(quality÷10,4)+1
            quality_bins[bin,1] += 1
            quality_bins[bin,2] += mismatch
        end
        for (op,n) in operation_runs(a.operations)
            if op in "ID"
                events[op] += 1
                indel_bases[op] += n
            end
        end
    end
    aligned,mismatches = sum(quality_counts),quality_counts[2]
    lines = [
        words("error_profile aligned_bases",aligned,"mismatches",mismatches,"rate",ratio(mismatches,aligned)),
        "substitutions",
        "ref A C G T N"
    ]
    for (i,base) in enumerate(BASES)
        push!(lines,words(base,join(substitutions[i,:]," ")))
    end
    push!(lines,"mismatch_by_cycle")
    for cycle in 1:maximum_cycle
        n,errors = cycles[cycle,:]
        push!(lines,words("cycle",cycle,"aligned",n,"mismatches",errors,"rate",ratio(errors,n)))
    end
    push!(
        lines,
        words(
            "quality matched",
            quality_counts[1],
            "mean",
            ratio(quality_sums[1],quality_counts[1]),
            "mismatched",
            quality_counts[2],
            "mean",
            ratio(quality_sums[2],quality_counts[2])
        )
    )
    push!(lines,"quality_bins")
    for (i,name) in enumerate(("0-9","10-19","20-29","30-39","40-"))
        n,errors = quality_bins[i,:]
        push!(lines,words(name,"aligned",n,"mismatches",errors,"rate",ratio(errors,n)))
    end
    push!(lines,"cigar "*join((words(op,operation_counts[op]) for op in "MIDS")," "))
    push!(
        lines,
        words("indels insertions",events['I'],indel_bases['I'],"deletions",events['D'],indel_bases['D'])
    )
    lines
end
function mapping_statistics(results,references,search_counts,seed_counts)
    total,mapped = length(results),filter(r->r.mapped,results)
    unique_count = count(r->r.x0==1,mapped)
    short,nohit = count(r->!r.mapped && r.reason=="SHORT",results),count(
        r->!r.mapped && r.reason=="NOHIT",
        results
    )
    lines = [
        words(
            "reads total",
            total,
            "trimmed",
            count(r->r.trimmed>0,results),
            "trimmed_bases",
            sum(r.trimmed for r in results),
            "short",
            short
        ),
        words(
            "mapped",
            length(mapped),
            "rate",
            ratio(length(mapped),total),
            "unique",
            unique_count,
            "multi",
            length(mapped)-unique_count,
            "unmapped",
            total-length(mapped)
        ),
        words("unmapped short",short,"nohit",nohit),
        words(
            "method exact",
            count(r->r.method=="EXACT",mapped),
            "mismatch",
            count(r->r.method=="MISMATCH",mapped),
            "seed",
            count(r->r.method=="SEED",mapped)
        ),
        words(
            "strand forward",
            count(r->r.primary.strand=='+',mapped),
            "reverse",
            count(r->r.primary.strand=='-',mapped)
        )
    ]
    for (i,reference) in enumerate(references)
        on_reference = filter(r->r.primary.reference==i,mapped)
        forward = count(r->r.primary.strand=='+',on_reference)
        push!(
            lines,
            words(
                "reference",
                reference.name,
                "mapped",
                length(on_reference),
                "unique",
                count(r->r.x0==1,on_reference),
                "forward",
                forward,
                "reverse",
                length(on_reference)-forward
            )
        )
    end
    push!(lines,"length_bins")
    lengths = [r.length for r in results]
    for lower in minimum(lengths)÷10*10:10:maximum(lengths)÷10*10
        in_bin = filter(r->lower<=r.length<=lower+9,results)
        mapped_bin = filter(r->r.mapped,in_bin)
        push!(
            lines,
            words(
                "$lower-$(lower+9)",
                "reads",
                length(in_bin),
                "mapped",
                length(mapped_bin),
                "unique",
                count(r->r.x0==1,mapped_bin)
            )
        )
    end
    with_n = filter(r->'N' in r.read.bases,results)
    push!(
        lines,
        words(
            "n_reads",
            length(with_n),
            "n_bases",
            sum((count(==('N'),r.read.bases) for r in with_n);init=0),
            "mapped",
            count(r->r.mapped,with_n)
        )
    )
    target_counts = Dict{String,Int}()
    for r in mapped
        if r.x0>=2
            key = join([references[i].name for i in r.targets],"+")
            target_counts[key] = get(target_counts,key,0)+1
        end
    end
    push!(lines,"multi_targets")
    isempty(target_counts) && push!(lines,"none")
    for key in sort!(collect(keys(target_counts)))
        push!(lines,words(key,target_counts[key]))
    end
    push!(lines,"mapq_histogram")
    for mapq in sort!(unique([r.mapq for r in mapped]);rev=true)
        push!(lines,words(mapq,count(r->r.mapq==mapq,mapped)))
    end
    push!(lines,"nm_histogram")
    for nm in sort!(unique([r.primary.nm for r in mapped]))
        push!(lines,words(nm,count(r->r.primary.nm==nm,mapped)))
    end
    append!(lines,error_statistics(results,references))
    push!(
        lines,
        words(
            "search dfs_calls",
            search_counts[1],
            "dfs_nodes",
            search_counts[2],
            "dfs_leaves",
            search_counts[3],
            "dfs_positions",
            search_counts[4]
        )
    )
    push!(
        lines,
        "seeds "*join(
            (words(name,n) for (name,n) in zip(
                ("reads","seeds","with_n","repetitive","without_hit","candidates","passing"),
                seed_counts
            )),
            " "
        )
    )
    lines
end
function main()
    references,reads,params = read_inputs()
    text = reference_text(references)
    suffixes,classes = build_suffix_array(text.text)
    reverse_suffixes,reverse_classes = build_suffix_array(text.reverse)
    interval = params["OCC_INTERVAL"][1]
    forward = FMIndex(text.text,suffixes,interval,params["SA_SAMPLE_INTERVAL"][1])
    reverse_index = FMIndex(text.reverse,reverse_suffixes,interval)
    index_lines = index_statistics(
        text,
        suffixes,
        classes,
        forward,
        reverse_suffixes,
        reverse_classes,
        reverse_index,
        params
    )
    s = (
        text=text,
        references=references,
        forward=forward,
        reverse=reverse_index,
        params=params,
        search_counts=zeros(Int,4),
        seed_counts=zeros(Int,7)
    )
    results = [map_read(s,read) for read in reads]
    sam = sam_header(references)
    append!(sam,[sam_record(r,references,params["MAX_ALT_HITS"][1]) for r in results])
    coverage,variants = coverage_and_variants(results,references,params)
    for (name,lines) in [
        "alignments.sam"=>sam,
        "coverage.txt"=>coverage,
        "variants.txt"=>variants,
        "index_stats.txt"=>index_lines,
        "summary.txt"=>mapping_statistics(results,references,s.search_counts,s.seed_counts)
    ]
        write_lines(name,lines)
    end
end
main()
