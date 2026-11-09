include("alignment.jl")
include("distances.jl")
include("tree_building.jl")
include("parsimony.jl")
include("tree_io.jl")

const NJ_METHODS = ("NJ_P","NJ_JC","NJ_K2P")
const METHODS = (NJ_METHODS...,"ME","MP","CONSENSUS")
ordered_sum(values) = foldl(+,values;init=0.0)
square(value) = value*value
words(parts...) = join(string.(parts)," ")
function read_parameters()
    params = Dict{String,Any}()
    for line in readlines("input/params.txt")
        fields = String.(split(line))
        key = fields[1]
        params[key] = key in (
            "replicates",
            "seed",
            "max_missing_percent",
            "low_sites"
        ) ? parse(Int,fields[2]) : key=="saturation_distance" ? parse(
            Float64,
            fields[2]
        ) : key=="exhaustive_taxa" ? fields[2:end] : fields[2]
    end
    params
end
function check_records(records,maximum_missing)
    n = length(records[1].sequence)
    seen,accepted,rejected = Set{String}(),NamedTuple[],NamedTuple[]
    for record in records
        reason = record.name in seen ? "duplicate name" : ""
        push!(seen,record.name)
        if isempty(reason)
            index = findfirst(c->!haskey(BASE_SETS,c),record.sequence)
            !isnothing(index) && (reason="invalid character $(record.sequence[index]) at column $index")
        end
        isempty(reason) && length(record.sequence)!=n && (reason="length mismatch $(length(record.sequence))")
        if isempty(reason)
            missing = count(c->c in ('-','N'),record.sequence)
            100missing>maximum_missing*n && (reason="too many missing $missing")
        end
        if isempty(reason)
            push!(accepted,(name=record.name,sequence=record.sequence))
        else
            push!(rejected,(line=record.line,name=record.name,reason=reason))
        end
    end
    accepted,rejected,n
end
function summary_lines(records,rejected,names,sequences,patterns)
    n = length(sequences[1])
    lines = [words(
        "INPUT records",
        length(records),
        "accepted",
        length(names),
        "rejected",
        length(rejected),
        "columns",
        n
    )]
    for r in rejected
        push!(lines,words("REJECT line",r.line,r.name,r.reason))
    end
    columns = [[count(sequence->sequence[c]==base,sequences) for base in BASES] for c in 1:n]
    composition = zeros(Int,4)
    for (name,sequence) in zip(names,sequences)
        counts = [count(==(base),sequence) for base in BASES]
        bases = sum(counts)
        unique_count = count(
            c->sequence[c] in BASES && columns[c][findfirst(==(sequence[c]),BASES)]==1 && sum(columns[c])>1,
            1:n
        )
        push!(
            lines,
            words(
                "TAXON",
                name,
                "bases",
                bases,
                "ambiguous",
                count(c->c in AMBIGUOUS,sequence),
                "missing",
                count(c->c in ('-','N'),sequence),
                "unique",
                unique_count,
                "gc",
                real_text((counts[2]+counts[3])/bases,4)
            )
        )
        composition += counts
    end
    classes = classify_columns(sequences)
    push!(
        lines,
        "COLUMNS "*join(
            (words(kind,value) for (kind,value) in zip(
                ("constant","variable","informative","gapped","empty"),
                classes
            )),
            " "
        )
    )
    push!(lines,words("PATTERNS",length(patterns.patterns)))
    push!(
        lines,
        "COMPOSITION "*join(
            (words(base,real_text(value/sum(composition),4)) for (base,value) in zip(BASES,composition)),
            " "
        )
    )
    lines
end
function matrix_lines(names,matrix)
    width = maximum(length,names)
    [rpad(name,width)*" "*join(
        (real_text(value,5) for value in matrix[i,:]),
        " "
    ) for (i,name) in enumerate(names)]
end
function parsimony_bounds(patterns)
    minima,maximal = Int[],0
    for (pattern,weight) in zip(patterns.encoded,patterns.weights)
        minimum_value = minimum(count_ones(mask) for mask in 1:15 if all(bases->mask&bases!=0,pattern))-1
        push!(minima,minimum_value)
        greatest = minimum(count(bases->bases&base==0,pattern) for base in (1,2,4,8))
        maximal += greatest*weight
    end
    columns = [minima[index] for index in patterns.columns]
    sum(columns),maximal,columns
end
function bme_length(tree,matrix)
    taxa,total = tree_taxa(tree),0.0
    for (i,a) in enumerate(taxa)
        steps = path_distances(tree,a;unit=true)
        for b in taxa[i+1:end]
            total += matrix[a,b]/(1<<(Int(steps[b])-1))
        end
    end
    total
end
function stepwise(taxa,n,patterns,outgroup)
    tree = star_tree(n,taxa[1:3])
    initial = parsimony_score(tree,patterns,outgroup)
    current,additions,evaluated = initial,NamedTuple[],0
    for taxon in taxa[4:end]
        best,chosen,selected_mask,ties = typemax(Int),nothing,0,0
        for (mask,a,b) in branches(tree,outgroup)
            candidate = insert_taxon(tree,a,b,taxon)
            value = parsimony_score(candidate,patterns,outgroup)
            evaluated += 1
            if value<best
                best,chosen,selected_mask,ties = value,candidate,mask,1
            elseif value==best
                ties += 1
            end
        end
        tree,current = chosen,best
        push!(additions,(taxon=taxon,mask=selected_mask,value=current,ties=ties))
    end
    (tree=tree,initial=initial,score=current,additions=additions,evaluated=evaluated,taxa=taxa)
end
function hill_climb(tree,objective,outgroup,value)
    tree = copy_tree(tree)
    evaluated,moves = 0,NamedTuple[]
    while true
        improved = false
        for (mask,swap,candidate) in nni_candidates(tree,outgroup)
            candidate_value = objective(candidate)
            evaluated += 1
            if candidate_value<value
                tree,value,improved = candidate,candidate_value,true
                push!(moves,(mask=mask,swap=swap,value=value))
                break
            end
        end
        improved || break
    end
    (tree=tree,value=value,moves=moves,evaluated=evaluated)
end
function consensus_tree(n,taxa,outgroup,clades)
    tree = PhyloTree(n,taxa)
    root = internal_node!(tree)
    nodes = Dict{Int,Int}()
    for mask in sort!(collect(clades))
        nodes[mask] = internal_node!(tree)
    end
    for mask in sort!(collect(keys(nodes)))
        containers = [other for other in keys(nodes) if other!=mask && other&mask==mask]
        parent = isempty(containers) ? root : nodes[argmin(count_ones,containers)]
        connect!(tree,parent,nodes[mask])
    end
    for taxon in taxa
        containers = [mask for mask in keys(nodes) if mask&(1<<(taxon-1))!=0]
        parent = isempty(containers) ? root : nodes[argmin(count_ones,containers)]
        connect!(tree,parent,taxon)
    end
    tree
end
function exhaustive_search(taxa,names,patterns,outgroup,matrix)
    trees = [star_tree(length(names),taxa[1:3])]
    for taxon in taxa[4:end]
        trees = [insert_taxon(tree,a,b,taxon) for tree in trees for (_,a,b) in branches(tree,outgroup)]
    end
    records,histogram = NamedTuple[],Dict{Int,Int}()
    for tree in trees
        value = parsimony_score(tree,patterns,outgroup)
        histogram[value] = get(histogram,value,0)+1
        push!(
            records,
            (
                tree=tree,
                score=value,
                bme=bme_length(tree,matrix),
                newick=newick(tree,names,outgroup),
                splits=split_set(root_tree(tree,outgroup))
            )
        )
    end
    best_score = minimum(keys(histogram))
    optimal = sort!(filter(r->r.score==best_score,records);by=r->r.newick)
    common = copy(optimal[1].splits)
    for record in optimal[2:end]
        intersect!(common,record.splits)
    end
    strict = consensus_tree(length(names),taxa,outgroup,common)
    best_index = argmin(i->(records[i].bme,records[i].newick),eachindex(records))
    second = minimum(records[i].bme for i in eachindex(records) if i!=best_index)
    initial = stepwise(taxa,length(names),patterns,outgroup)
    heuristic = hill_climb(initial.tree,t->parsimony_score(t,patterns,outgroup),outgroup,initial.score)
    (
        taxa=taxa,
        records=records,
        histogram=histogram,
        best_score=best_score,
        optimal=optimal,
        strict=strict,
        best_bme=records[best_index],
        second_bme=second,
        heuristic=heuristic.value
    )
end
function likelihood_sites(tree,names,patterns,outgroup)
    rooted = root_tree(tree,outgroup)
    children = child_order(rooted,names)
    transition = Dict{Int,Matrix{Float64}}()
    for node in rooted.order[2:end]
        branch_length = tree.adjacent[node][rooted.parents[node]]
        exponential = exp(-(4branch_length)/3)
        same,different = 1/4+(3/4)*exponential,1/4-(1/4)*exponential
        transition[node] = [a==b ? same : different for a in 1:4,b in 1:4]
    end
    pattern_values = Float64[]
    for pattern in patterns.encoded
        partial,upward = Dict{Int,Vector{Float64}}(),Dict{Int,Vector{Float64}}()
        for node in reverse(rooted.order)
            if node<=tree.size
                partial[node] = [pattern[node]&(1<<(base-1))!=0 ? 1.0 : 0.0 for base in 1:4]
            else
                values = ones(4)
                for child in children[node],base in 1:4
                    values[base] *= upward[child][base]
                end
                partial[node] = values
            end
            node!=rooted.root && (upward[node]=[ordered_sum(transition[node][
                a,
                b
            ]*partial[node][b] for b in 1:4) for a in 1:4])
        end
        push!(pattern_values,log(ordered_sum((1/4)*value for value in partial[rooted.root])))
    end
    [pattern_values[index] for index in patterns.columns]
end
function likelihood_lines(names,patterns,nj_trees,outgroup,main_method,low_count,site_logs)
    n = length(patterns.columns)
    lines = [words("LIKELIHOOD columns",n,"patterns",length(patterns.patterns))]
    for method in NJ_METHODS
        total = ordered_sum(site_logs[method])
        push!(lines,words("TREE",method,"loglik",real_text(total,4),"per_site",real_text(total/n,4)))
    end
    for i in 1:2,j in i+1:3
        a,b = NJ_METHODS[i],NJ_METHODS[j]
        deltas = site_logs[a]-site_logs[b]
        difference = ordered_sum(deltas)
        mean = difference/n
        se = sqrt((n/(n-1))*ordered_sum(square(delta-mean) for delta in deltas))
        push!(
            lines,
            words(
                "KH",
                a,
                b,
                "difference",
                real_text(difference,4),
                "se",
                real_text(se,4),
                "z",
                real_text(difference/se,4)
            )
        )
    end
    lowest = sort!(collect(1:n);by=c->(parse(Float64,real_text(site_logs[main_method][c],4)),c))
    changes = pattern_scores(nj_trees[main_method],patterns,outgroup)
    push!(lines,words("LOWEST",main_method,"sites",low_count))
    for c in lowest[1:low_count]
        index = patterns.columns[c]
        push!(
            lines,
            words(
                "SITE",
                c,
                "loglik",
                real_text(site_logs[main_method][c],4),
                "changes",
                changes[index],
                "pattern",
                patterns.patterns[index]
            )
        )
    end
    lines
end
function bootstrap(names,sequences,params,main_tree,main_matrix,outgroup)
    n,l = length(names),length(sequences[1])
    replicates,state,support = params["replicates"],params["seed"],Dict{Int,Int}()
    main_splits = split_set(root_tree(main_tree,outgroup))
    lines,identical = [words("BOOTSTRAP model",params["model"],"replicates",replicates,"seed",state)],0
    for replicate in 1:replicates
        weights = zeros(Int,l)
        for _ in 1:l
            state = mod(48271state,2147483647)
            weights[state%l+1] += 1
        end
        matrix,_ = build_matrix(all_pairs(sequences,weights),n,params["model"],params["saturation_distance"])
        tree = neighbor_joining(matrix,1:n)
        splits = split_set(root_tree(tree,outgroup))
        for mask in splits
            support[mask] = get(support,mask,0)+1
        end
        difference = length(symdiff(splits,main_splits))
        identical += difference==0
        push!(lines,words("REPLICATE",replicate,"distinct",count(>(0),weights),"rf",difference))
    end
    push!(lines,words("IDENTICAL",identical))
    for mask in sort!(collect(main_splits);by=mask->symbols(mask,n))
        push!(lines,words("SUPPORT",symbols(mask,n),get(support,mask,0)))
    end
    for mask in sort!(collect(keys(support));by=mask->(-support[mask],symbols(mask,n)))
        push!(lines,words("SPLIT",symbols(mask,n),support[mask]))
    end
    majority = Set(mask for (mask,value) in support if 2value>replicates)
    consensus = consensus_tree(n,1:n,outgroup,majority)
    push!(lines,"CONSENSUS "*newick(consensus,names,outgroup;support=support))
    for taxon in 1:n
        taxon==outgroup && continue
        tree = neighbor_joining(main_matrix,filter(!=(taxon),collect(1:n)))
        reduced = Set(mask& ~(1<<(taxon-1)) for mask in main_splits)
        filter!(mask->2<=count_ones(mask)<=n-3,reduced)
        push!(
            lines,
            words("JACKKNIFE",names[taxon],"rf",length(symdiff(split_set(root_tree(tree,outgroup)),reduced)))
        )
    end
    consensus,support,lines
end
function clock_lines(names,sequences,outgroup,main_method,tree)
    ingroup = filter(!=(outgroup),collect(eachindex(names)))
    pairs,rejected = String[],0
    for i in 1:length(ingroup)-1,j in i+1:length(ingroup)
        a,b = ingroup[i],ingroup[j]
        m1,m2 = 0,0
        for (x,y,o) in zip(sequences[a],sequences[b],sequences[outgroup])
            if x in BASES && y in BASES && o in BASES && x!=y
                m1 += y==o
                m2 += x==o
            end
        end
        reject = 1000square(m1-m2)>3841*(m1+m2)
        rejected += reject
        chi = m1+m2==0 ? "-" : real_text(square(m1-m2)/(m1+m2),4)
        push!(pairs,words("RRT",names[a],names[b],"m1",m1,"m2",m2,"chi2",chi,reject ? "reject" : "ok"))
    end
    lines = [words("RELATIVE_RATE outgroup",names[outgroup],"pairs",length(pairs),"rejected",rejected);pairs]
    paths = path_distances(tree,root_tree(tree,outgroup).root)
    mean = ordered_sum(paths[t] for t in ingroup)/length(ingroup)
    sd = sqrt(ordered_sum(square(paths[t]-mean) for t in ingroup)/(length(ingroup)-1))
    push!(
        lines,
        words(
            "ROOT_TO_TIP",
            main_method,
            "mean",
            real_text(mean,5),
            "sd",
            real_text(sd,5),
            "cv",
            real_text(sd/mean,4)
        )
    )
    append!(lines,[words("TIP",names[t],real_text(paths[t],5)) for t in ingroup])
    lines
end
function quartet_topologies(splits,n)
    result = Int[]
    for a in 1:n-3,b in a+1:n-2,c in b+1:n-1,d in c+1:n
        quartet = (1<<(a-1))|(1<<(b-1))|(1<<(c-1))|(1<<(d-1))
        topology = 0
        for (number,other) in enumerate((b,c,d))
            side = (1<<(a-1))|(1<<(other-1))
            if any(mask->(mask&quartet) in (side,xor(quartet,side)),splits)
                topology = number
                break
            end
        end
        push!(result,topology)
    end
    result
end
function comparison_lines(
    names,
    patterns,
    trees,
    matrices,
    main_matrix,
    main_method,
    outgroup,
    support,
    replicates,
    nj_scores,
    mp_score,
    mp_changes,
    site_logs,
    patristic
)
    n = length(names)
    splits = Dict(method=>split_set(root_tree(trees[method],outgroup)) for method in METHODS)
    lines = String[]
    for method in METHODS
        tree = trees[method]
        supported = count(mask->2get(support,mask,0)>replicates,splits[method])
        score,bme,branch_length,negative,residual,likelihood = "-","-","-","-","-","-"
        if method!="CONSENSUS"
            value = method in NJ_METHODS ? nj_scores[method] : method=="MP" ? mp_score : parsimony_score(
                tree,
                patterns,
                outgroup
            )
            score,bme = string(value),real_text(bme_length(tree,main_matrix),5)
        end
        if method in NJ_METHODS
            branch_length = real_text(
                ordered_sum(tree.adjacent[a][b] for (_,a,b) in branches(tree,outgroup)),
                5
            )
            negative = string(tree.negative)
            matrix = matrices[method[4:end]]
            residual = real_text(
                ordered_sum(square(matrix[a,b]-patristic[method][a,b]) for a in 1:n-1 for b in a+1:n),
                6
            )
            likelihood = real_text(ordered_sum(site_logs[method]),4)
        elseif method=="MP"
            branch_length = real_text(mp_score/length(patterns.columns),5)
        end
        push!(
            lines,
            words(
                "TREE",
                method,
                "splits",
                length(splits[method]),
                "supported",
                supported,
                "parsimony",
                score,
                "bme",
                bme,
                "length",
                branch_length,
                "negative",
                negative,
                "sse",
                residual,
                "loglik",
                likelihood
            )
        )
    end
    push!(lines,"RF "*join(METHODS," "))
    for first in METHODS
        push!(
            lines,
            words(first,join([length(symdiff(splits[first],splits[second])) for second in METHODS]," "))
        )
    end
    quartets = Dict(method=>quartet_topologies(splits[method],n) for method in METHODS)
    push!(lines,"QUARTET "*join(METHODS," "))
    for first in METHODS
        push!(
            lines,
            words(
                first,
                join(
                    [count(
                        pair->pair[1]!=pair[2],
                        zip(quartets[first],quartets[second])
                    ) for second in METHODS],
                    " "
                )
            )
        )
    end
    all_clades = union(values(splits)...)
    lengths = branch_lengths(root_tree(trees[main_method],outgroup))
    changes = Dict(mask=>mp_changes[minmax(a,b)] for (mask,a,b) in branches(trees["MP"],outgroup))
    for mask in sort!(collect(all_clades);by=mask->symbols(mask,n))
        marks = join(mask in splits[method] ? '+' : '-' for method in METHODS)
        length_text = haskey(lengths,mask) ? real_text(lengths[mask],5) : "-"
        change = haskey(changes,mask) ? string(changes[mask]) : "-"
        push!(
            lines,
            words(
                "CLADE",
                symbols(mask,n),
                "support",
                get(support,mask,0),
                "trees",
                marks,
                "length",
                length_text,
                "changes",
                change
            )
        )
    end
    lines
end
function hypothesis_lines(names,trees,outgroup,support,exhaustive)
    numbers = Dict(name=>i for (i,name) in enumerate(names))
    ingroup = xor((1<<length(names))-1,1<<(outgroup-1))
    exhaustive_ingroup = sum(1<<(t-1) for t in exhaustive.taxa if t!=outgroup)
    splits = Dict(method=>split_set(root_tree(trees[method],outgroup)) for method in METHODS)
    lines = String[]
    for line in readlines("input/clades.txt")
        fields = String.(split(line))
        hypothesis,members = fields[1],fields[2:end]
        unknown = findfirst(name->!haskey(numbers,name),members)
        if !isnothing(unknown)
            push!(lines,words("INVALID",hypothesis,"unknown taxon",members[unknown]))
            continue
        elseif names[outgroup] in members
            push!(lines,words("INVALID",hypothesis,"contains outgroup"))
            continue
        end
        mask = sum(1<<(numbers[name]-1) for name in members)
        push!(lines,words("CLADE",hypothesis,"taxa",count_ones(mask),"support",get(support,mask,0)))
        for method in METHODS
            containers = [clade for clade in union(splits[method],Set([ingroup])) if clade&mask==mask]
            common = argmin(count_ones,containers)
            intruders = [name for (i,name) in enumerate(names) if common& ~mask&(1<<(i-1))!=0]
            push!(
                lines,
                words(
                    "TEST",
                    hypothesis,
                    method,
                    "monophyletic",
                    common==mask ? "yes" : "no",
                    "mrca",
                    count_ones(common),
                    "intruders",
                    isempty(intruders) ? "-" : join(intruders,",")
                )
            )
        end
        subset = mask&exhaustive_ingroup
        if !(2<=count_ones(subset)<count_ones(exhaustive_ingroup))
            push!(lines,words("SUBSET",hypothesis,"untestable"))
            continue
        end
        included = filter(r->subset in r.splits,exhaustive.records)
        excluded = filter(r->!(subset in r.splits),exhaustive.records)
        push!(
            lines,
            words(
                "SUBSET",
                hypothesis,
                "taxa",
                count_ones(subset),
                "with",
                minimum(r.score for r in included),
                "without",
                minimum(r.score for r in excluded),
                "bme_with",
                real_text(minimum(r.bme for r in included),5),
                "bme_without",
                real_text(minimum(r.bme for r in excluded),5)
            )
        )
    end
    lines
end
function distance_lines(names,pairs,matrices,saturated,main_method,patristic,me_start,me,exhaustive)
    totals,pair_block = zeros(Int,3),String[]
    for (a,b,n,s,v) in pairs
        push!(pair_block,words("PAIR",names[a],names[b],"sites",n,"transitions",s,"transversions",v))
        totals += [n,s,v]
    end
    push!(pair_block,words("TOTAL sites",totals[1],"transitions",totals[2],"transversions",totals[3]))
    blocks = [pair_block]
    for model in MODELS
        block = ["MODEL $model";matrix_lines(names,matrices[model])]
        append!(block,[words("SATURATED",names[a],names[b],"sites",n) for (a,b,n) in saturated[model]])
        push!(blocks,block)
    end
    push!(blocks,["PATRISTIC $main_method";matrix_lines(names,patristic[main_method])])
    evolution = [words("ME start",main_method,"length",real_text(me_start,5))]
    for move in me.moves
        push!(
            evolution,
            words(
                "NNI edge",
                symbols(move.mask,length(names)),
                "swap",
                move.swap,
                "length",
                real_text(move.value,5)
            )
        )
    end
    push!(
        evolution,
        words("ME moves",length(me.moves),"evaluated",me.evaluated,"length",real_text(me.value,5))
    )
    best = exhaustive.best_bme
    push!(
        evolution,
        words(
            "EXHAUSTIVE taxa",
            length(exhaustive.taxa),
            "trees",
            length(exhaustive.records),
            "best",
            real_text(best.bme,5),
            "second",
            real_text(exhaustive.second_bme,5)
        )
    )
    push!(evolution,words("BEST",best.newick,"parsimony",best.score))
    push!(blocks,evolution)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines,"")
        append!(lines,block)
    end
    lines
end
score_line(method,score,minimum_value,maximum_value) = words(
    "TREE",
    method,
    "score",
    score,
    "ci",
    real_text(minimum_value/score,4),
    "ri",
    real_text((maximum_value-score)/(maximum_value-minimum_value),4)
)
function parsimony_lines(
    names,
    outgroup,
    minimum_value,
    maximum_value,
    minima,
    nj_scores,
    initial,
    search,
    ancestors,
    changes,
    exhaustive
)
    lines = [words("BOUNDS minimum",minimum_value,"maximum",maximum_value)]
    append!(lines,[score_line(method,nj_scores[method],minimum_value,maximum_value) for method in NJ_METHODS])
    push!(lines,words("START",join(names[initial.taxa[1:3]]," "),"score",initial.initial))
    for addition in initial.additions
        push!(
            lines,
            words(
                "ADD",
                names[addition.taxon],
                "edge",
                symbols(addition.mask,length(names)),
                "score",
                addition.value,
                "ties",
                addition.ties
            )
        )
    end
    push!(lines,words("STEPWISE score",initial.score,"evaluated",initial.evaluated))
    for move in search.moves
        push!(lines,words("NNI edge",symbols(move.mask,length(names)),"swap",move.swap,"score",move.value))
    end
    push!(lines,words("SEARCH moves",length(search.moves),"evaluated",search.evaluated,"score",search.value))
    push!(lines,score_line("MP",search.value,minimum_value,maximum_value))
    push!(lines,"MP "*newick(search.tree,names,outgroup;lengths=true))
    for value in 0:maximum(changes)
        push!(lines,words("CHANGES",value,"columns",count(==(value),changes)))
    end
    push!(
        lines,
        words(
            "HOMOPLASY columns",
            count(pair->pair[1]>pair[2],zip(changes,minima)),
            "extra",
            search.value-minimum_value
        )
    )
    rooted = root_tree(search.tree,outgroup)
    records = [(
        symbols(node==rooted.root ? rooted.ingroup : rooted.masks[node],length(names)),
        sequence
    ) for (node,sequence) in ancestors]
    for (symbol,sequence) in sort!(records)
        push!(lines,words("ANCESTOR",symbol,sequence))
    end
    push!(lines,"")
    push!(
        lines,
        words(
            "EXHAUSTIVE taxa",
            length(exhaustive.taxa),
            "trees",
            length(exhaustive.records),
            "best",
            exhaustive.best_score,
            "optimal",
            length(exhaustive.optimal)
        )
    )
    for value in sort!(collect(keys(exhaustive.histogram)))
        push!(lines,words("SCORE",value,"trees",exhaustive.histogram[value]))
    end
    for record in exhaustive.optimal
        push!(lines,words("OPTIMAL",record.newick,"bme",real_text(record.bme,5)))
    end
    push!(lines,"STRICT "*newick(exhaustive.strict,names,outgroup))
    push!(
        lines,
        words(
            "HEURISTIC score",
            exhaustive.heuristic,
            "optimal",
            exhaustive.heuristic==exhaustive.best_score ? "yes" : "no"
        )
    )
    lines
end
function main()
    params,records = read_parameters(),read_fasta()
    accepted,rejected,l = check_records(records,params["max_missing_percent"])
    names,sequences = [r.name for r in accepted],[r.sequence for r in accepted]
    n,outgroup = length(names),findfirst(==(params["outgroup"]),names)
    patterns = compress_patterns(sequences)
    pairs = all_pairs(sequences,ones(Int,l))
    matrices,saturated,nj_trees = Dict{String,Matrix{Float64}}(),Dict{String,Vector{NTuple{3,Int}}}(),Dict{String,PhyloTree}()
    for (model,method) in zip(MODELS,NJ_METHODS)
        matrices[model],saturated[model] = build_matrix(pairs,n,model,params["saturation_distance"])
        nj_trees[method] = neighbor_joining(matrices[model],1:n)
    end
    main_method = "NJ_"*params["model"]
    main_tree,main_matrix = nj_trees[main_method],matrices[params["model"]]
    me_start = bme_length(main_tree,main_matrix)
    me = hill_climb(main_tree,t->bme_length(t,main_matrix),outgroup,me_start)
    addition_order = [outgroup;filter(!=(outgroup),collect(1:n))]
    initial = stepwise(addition_order,n,patterns,outgroup)
    mp = hill_climb(initial.tree,t->parsimony_score(t,patterns,outgroup),outgroup,initial.score)
    ancestors,branch_changes,column_changes = reconstruct(mp.tree,patterns,outgroup)
    for ((a,b),changes) in branch_changes
        connect!(mp.tree,a,b,changes/l)
    end
    minimum_value,maximum_value,minima = parsimony_bounds(patterns)
    nj_scores = Dict(method=>parsimony_score(nj_trees[method],patterns,outgroup) for method in NJ_METHODS)
    exhaustive_taxa = [outgroup;[i for (
        i,
        name
    ) in enumerate(names) if i!=outgroup && name in params["exhaustive_taxa"]]]
    exhaustive = exhaustive_search(exhaustive_taxa,names,patterns,outgroup,main_matrix)
    site_logs = Dict(method=>likelihood_sites(
        nj_trees[method],
        names,
        patterns,
        outgroup
    ) for method in NJ_METHODS)
    consensus,support,bootstrap_report = bootstrap(names,sequences,params,main_tree,main_matrix,outgroup)
    trees = merge(nj_trees,Dict("ME"=>me.tree,"MP"=>mp.tree,"CONSENSUS"=>consensus))
    patristic = Dict(method=>patristic_matrix(nj_trees[method]) for method in NJ_METHODS)
    newicks,diagrams = String[],String[]
    for method in METHODS
        tree = trees[method]
        push!(
            newicks,
            method*" "*newick(
                tree,
                names,
                outgroup;lengths=method in NJ_METHODS || method=="MP",
                support=method=="CONSENSUS" ? support : nothing
            )
        )
        !isempty(diagrams) && push!(diagrams,"")
        push!(diagrams,"TREE $method")
        append!(diagrams,cladogram(tree,names,outgroup,support))
    end
    outputs = [
        "summary.txt"=>summary_lines(records,rejected,names,sequences,patterns),
        "distances.txt"=>distance_lines(
            names,
            pairs,
            matrices,
            saturated,
            main_method,
            patristic,
            me_start,
            me,
            exhaustive
        ),
        "trees.nwk"=>newicks,
        "cladograms.txt"=>diagrams,
        "parsimony.txt"=>parsimony_lines(
            names,
            outgroup,
            minimum_value,
            maximum_value,
            minima,
            nj_scores,
            initial,
            mp,
            ancestors,
            column_changes,
            exhaustive
        ),
        "likelihood.txt"=>likelihood_lines(
            names,
            patterns,
            nj_trees,
            outgroup,
            main_method,
            params["low_sites"],
            site_logs
        ),
        "bootstrap.txt"=>bootstrap_report,
        "clock.txt"=>clock_lines(names,sequences,outgroup,main_method,main_tree),
        "comparison.txt"=>comparison_lines(
            names,
            patterns,
            trees,
            matrices,
            main_matrix,
            main_method,
            outgroup,
            support,
            params["replicates"],
            nj_scores,
            mp.value,
            branch_changes,
            site_logs,
            patristic
        ),
        "hypotheses.txt"=>hypothesis_lines(names,trees,outgroup,support,exhaustive)
    ]
    for (filename,lines) in outputs
        write_lines(filename,lines)
    end
end
main()
