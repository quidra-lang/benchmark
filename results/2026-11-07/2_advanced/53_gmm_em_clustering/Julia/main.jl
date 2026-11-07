include("dataset.jl")
include("gaussian.jl")
include("em.jl")
include("kmeans.jl")
include("report.jl")
rounded_four(value) = parse(Float64,dec(value))
function parameter_count(k,type)
    type=="FULL" ? 6k-1 : type=="TIED" ? 3k+2 : type=="DIAG" ? 5k-1 : 4k-1
end
point_entropy(r) = -ordered_sum(value*log(value) for value in r if value>0)
function summarize_run(run,k,type,type_index,n,tolerance)
    p = parameter_count(k,type)
    bic,aic = -2run.loglik+p*log(n),-2run.loglik+2p
    assignment = [argmax(row.responsibilities) for row in run.records]
    entropy = ordered_sum(point_entropy(row.responsibilities) for row in run.records)
    trace = run.trace
    settled = findfirst(t->all(value->abs(value-trace[end])<=tolerance,trace[t+1:end]),0:length(trace)-1)-1
    increases = diff(trace)
    largest = argmax(increases)
    violations = [t for t in 1:length(trace)-1 if trace[t+1]<trace[t]-0.000001abs(trace[t])]
    (;run...,k=k,type=type,type_index=type_index,parameter_count=p,bic=bic,aic=aic,icl=bic+2entropy,entropy=entropy,mean_entropy=entropy/n,
        assignment=assignment,sizes=[count(
            ==(j),
            assignment
        ) for j in 1:k],settled_at=settled,largest_t=largest,largest_increase=increases[largest],violations=violations)
end
ranking(models,criterion) = sort(models;by=m->(
    rounded_four(getproperty(m,Symbol(criterion))),
    m.parameter_count,
    m.k,
    m.type_index
))
function contingency(left,right,rows,columns)
    table = zeros(Int,rows,columns)
    for (a,b) in zip(left,right)
        table[a,b] += 1
    end
    table
end
choose2(n) = n*(n-1)÷2
function adjusted_rand(left,right,rows,columns)
    table = contingency(left,right,rows,columns)
    shared = sum(choose2(v) for v in table)
    a,b = sum(choose2(sum(table[r,:])) for r in 1:rows),sum(choose2(sum(table[:,c])) for c in 1:columns)
    z = choose2(length(left))
    numerator,denominator = 2*(z*shared-a*b),z*(a+b)-2a*b
    denominator==0 && return (1,1)
    common = gcd(abs(numerator),abs(denominator))
    numerator,denominator = numerator÷common,denominator÷common
    denominator<0 ? (-numerator,-denominator) : (numerator,denominator)
end
ari_text(pair) = "$(pair[1])/$(pair[2]) $(dec(pair[1]/pair[2]))"
function partition_metrics(points,labels,k)
    n = length(points)
    clusters = [findall(==(j),labels) for j in 1:k]
    occupied = [j for j in 1:k if !isempty(clusters[j])]
    g = length(occupied)
    if g<2
        return (silhouette=nothing,cluster_silhouettes=Dict{Int,Float64}(),ch=nothing,db=nothing)
    end
    centers = Dict(j=>(
        ordered_sum(points[i].x for i in clusters[j])/length(clusters[j]),
        ordered_sum(points[i].y for i in clusters[j])/length(clusters[j])
    ) for j in occupied)
    distances = [distance(point_xy(points[i]),point_xy(points[j])) for i in 1:n,j in 1:n]
    silhouette = zeros(n)
    for i in 1:n
        members = clusters[labels[i]]
        length(members)==1 && continue
        own = ordered_sum(distances[i,j] for j in members if j!=i)/(length(members)-1)
        other = minimum(ordered_sum(distances[
            i,
            j
        ] for j in clusters[c])/length(clusters[c]) for c in occupied if c!=labels[i])
        silhouette[i] = (other-own)/max(own,other)
    end
    center = (ordered_sum(p.x for p in points)/n,ordered_sum(p.y for p in points)/n)
    between = ordered_sum(length(clusters[c])*squared_distance(centers[c],center) for c in occupied)
    within = ordered_sum(squared_distance(point_xy(p),centers[labels[i]]) for (i,p) in enumerate(points))
    ch = (between/(g-1))/(within/(n-g))
    scatter = Dict(c=>ordered_sum(distance(
        point_xy(points[i]),
        centers[c]
    ) for i in clusters[c])/length(clusters[c]) for c in occupied)
    db = ordered_sum(maximum((scatter[c]+scatter[d])/distance(
        centers[c],
        centers[d]
    ) for d in occupied if d!=c) for c in occupied)/g
    local_silhouette = Dict(c=>ordered_sum(silhouette[i] for i in clusters[c])/length(clusters[c]) for c in occupied)
    (silhouette=ordered_sum(silhouette)/n,cluster_silhouettes=local_silhouette,ch=ch,db=db)
end
function all_permutations(k)
    result = Vector{Int}[]
    function visit(prefix)
        if length(prefix)==k
            push!(result,prefix)
        else
            for j in 1:k
                j in prefix || visit(vcat(prefix,[j]))
            end
        end
    end
    visit(Int[])
    result
end
function best_matching(left,right,k)
    table = contingency(left,right,k,k)
    permutations = all_permutations(k)
    counts = [sum(table[p[j],j] for j in 1:k) for p in permutations]
    best = argmax(counts)
    permutations[best],counts[best],table
end
function component_details(model,points,edges,metrics)
    result = NamedTuple[]
    mixture = model.model
    for k in 1:model.k
        members = findall(==(k),model.assignment)
        cov,mean = mixture.covariances[k],mixture.means[k]
        squared = [mahalanobis(point_xy(point),mean,cov) for point in points]
        distances = [sqrt(squared[i]) for i in members]
        boundaries = vcat([0.0],edges,[Inf])
        observed,expected = Int[],Float64[]
        for i in 1:length(boundaries)-1
            low,high = boundaries[i],boundaries[i+1]
            push!(observed,count(value->low<=value<high,distances))
            probability = exp(-low*low/2)-(isinf(high) ? 0.0 : exp(-high*high/2))
            push!(expected,length(members)*probability)
        end
        chi = ordered_sum((o-e)*(o-e)/e for (o,e) in zip(observed,expected))
        push!(result,(number=k,weight=mixture.weights[k],mean=mean,cov=cov,size=length(members),soft_size=ordered_sum(row.responsibilities[k] for row in model.records),
            inside_one=count(i->squared[i]<=1,members),inside_two=count(i->squared[i]<=4,members),silhouette=get(
                metrics.cluster_silhouettes,
                k,
                nothing
            ),
            observed=observed,expected=expected,chi=chi,geometry=eigen_data(cov)))
    end
    result
end
function cluster_entropy(clusters,records)
    total = 0.0
    for record in records
        probabilities = [ordered_sum(record.responsibilities[k] for k in cluster) for cluster in clusters]
        total += point_entropy(probabilities)
    end
    total
end
function merging_block(model)
    clusters = [[k] for k in 1:model.k]
    lines = ["merging","start entropy $(dec(cluster_entropy(clusters,model.records)))"]
    step = 0
    while length(clusters)>1
        candidates = NamedTuple[]
        for i in 1:length(clusters)-1,j in i+1:length(clusters)
            proposed = deepcopy(clusters)
            proposed[i] = sort(vcat(proposed[i],proposed[j]))
            deleteat!(proposed,j)
            sort!(proposed;by=first)
            entropy = cluster_entropy(proposed,model.records)
            push!(candidates,(i=i,j=j,entropy=entropy,clusters=proposed))
        end
        chosen = argmin(c->(rounded_four(c.entropy),c.i,c.j),candidates)
        assigned = [argmax([ordered_sum(row.responsibilities[k] for k in cluster) for cluster in chosen.clusters]) for row in model.records]
        sizes = [count(==(j),assigned) for j in eachindex(chosen.clusters)]
        step += 1
        push!(
            lines,
            "step $step merge $(join(clusters[chosen.i],"+")) $(join(clusters[chosen.j],"+")) entropy $(dec(chosen.entropy)) sizes $(integer_values(sizes))"
        )
        clusters = chosen.clusters
    end
    lines
end
function refit_from_kmeans(model,kmeans,points,settings)
    weights,means,covs = Float64[],Tuple{Float64,Float64}[],NTuple{3,Float64}[]
    for j in 1:model.k
        members = [p for (p,label) in zip(points,kmeans.assignment) if label==j]
        center = kmeans.centers[j]
        n = length(members)
        push!(weights,n/length(points))
        push!(means,center)
        a = ordered_sum((p.x-center[1])^2 for p in members)/n
        b = ordered_sum((p.x-center[1])*(p.y-center[2]) for p in members)/n
        c = ordered_sum((p.y-center[2])^2 for p in members)/n
        push!(covs,(a+settings.epsilon,b,c+settings.epsilon))
    end
    initial = Mixture(weights,means,covs,"")
    run = run_em(points,initial,model.type,settings.iterations,settings.epsilon)
    summarize_run(run,model.k,model.type,model.type_index,length(points),settings.settle)
end
function model_blocks(models)
    blocks = Vector{String}[]
    for m in models
        lines = ["model K=$(m.k) type=$(m.type)","parameters $(m.parameter_count)","loglik $(dec(m.loglik))","bic $(dec(m.bic))","aic $(dec(m.aic))","icl $(dec(m.icl))",
            "mean_entropy $(dec(m.mean_entropy))","settled_at $(m.settled_at)","largest_increase iteration $(m.largest_t) value $(dec(m.largest_increase))","violations $(length(m.violations))","sizes $(integer_values(m.sizes))"]
        for j in 1:m.k
            geometry = eigen_data(m.model.covariances[j])
            push!(
                lines,
                "component $j weight $(dec(m.model.weights[j])) mean $(real_values(m.model.means[j])) cov $(real_values(m.model.covariances[j])) axes $(real_values(geometry.axes)) angle $(dec(geometry.angle))"
            )
        end
        push!(blocks,lines)
    end
    blocks
end
function selection_blocks(models,selected,kmeans,points,initial,settings)
    ranked = Dict(key=>ranking(models,key) for key in ("bic","aic","icl"))
    ranks = Dict(key=>Dict((m.k,m.type)=>i for (i,m) in enumerate(ranked[key])) for key in keys(ranked))
    lines = ["ranking by bic","rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank"]
    for (rank,m) in enumerate(ranked["bic"])
        delta = rounded_four(m.bic)-rounded_four(selected.bic)
        push!(
            lines,
            "$rank $(m.k) $(m.type) $(m.parameter_count) $(dec(m.loglik)) $(dec(m.bic)) $(dec(delta)) $(dec(m.aic)) $(ranks["aic"][(m.k,m.type)]) $(dec(m.icl)) $(ranks["icl"][(m.k,m.type)])"
        )
    end
    for (label,key) in (("selected","bic"),("best_aic","aic"),("best_icl","icl"))
        m = ranked[key][1]
        push!(lines,"$label K=$(m.k) type=$(m.type)")
    end
    blocks = [lines]
    lines = ["best K per type"]
    for type in settings.types
        same = [m for m in models if m.type==type]
        push!(
            lines,
            "$type bic $(ranking(same,"bic")[1].k) aic $(ranking(same,"aic")[1].k) icl $(ranking(same,"icl")[1].k)"
        )
    end
    push!(blocks,lines)
    previous = nothing
    for k in settings.ks
        m = ranking([m for m in models if m.k==k],"bic")[1]
        km = kmeans[k]
        gm,ks = partition_metrics(points,m.assignment,k),partition_metrics(points,km.assignment,k)
        lines = ["K=$k type=$(m.type) bic $(dec(m.bic))","  kmeans iterations $(km.iterations) inertia $(dec(km.inertia))","  ari $(ari_text(adjusted_rand(m.assignment,km.assignment,k,k)))",
            "  silhouette gmm $(optional(gm.silhouette)) kmeans $(optional(ks.silhouette))","  calinski_harabasz gmm $(optional(gm.ch)) kmeans $(optional(ks.ch))","  davies_bouldin gmm $(optional(gm.db)) kmeans $(optional(ks.db))"]
        if !isnothing(previous)
            table = contingency(previous.assignment,m.assignment,previous.k,k)
            parents,shared = String[],Int[]
            for j in 1:k
                counts = table[:,j]
                parent = argmax(counts)
                push!(parents,sum(counts)==0 ? "-" : string(parent))
                push!(shared,sum(counts)==0 ? 0 : counts[parent])
            end
            push!(lines,"  parents K=$(previous.k) $(join(parents," ")) shared $(integer_values(shared))")
        end
        push!(blocks,lines)
        previous = m
    end
    lines = ["violations"]
    for m in models,t in m.violations
        push!(
            lines,
            "K=$(m.k) type=$(m.type) iteration $t previous $(dec(m.trace[t])) current $(dec(m.trace[t+1]))"
        )
    end
    length(lines)==1 && push!(lines,"none")
    push!(blocks,lines)
    metrics = partition_metrics(points,selected.assignment,selected.k)
    details = component_details(selected,points,settings.gof_edges,metrics)
    lines = ["selected components"]
    for c in details
        g = c.geometry
        sx,sy = g.axes
        push!(lines,"component $(c.number) weight $(dec(c.weight)) size $(c.size) soft_size $(dec(c.soft_size)) mean $(real_values(c.mean))",
            "  cov $(real_values(c.cov)) corr $(dec(g.correlation))","  eigen $(dec(g.leading)) $(dec(g.trailing)) direction $(real_values(g.direction)) angle $(dec(g.angle))",
            "  axes_1sigma $(dec(sx)) $(dec(sy)) axes_2sigma $(dec(2sx)) $(dec(2sy))","  inside_1sigma $(c.inside_one) inside_2sigma $(c.inside_two) area_1sigma $(dec(g.area))",
            "  silhouette $(optional(c.silhouette))","  gof observed $(integer_values(c.observed)) expected $(real_values(c.expected)) chi2 $(dec(c.chi))")
    end
    push!(blocks,lines)
    lines = ["overlap"]
    mixture,k = selected.model,selected.k
    for a in 1:k-1,b in a+1:k
        d,coefficient = bhattacharyya(
            mixture.means[a],
            mixture.covariances[a],
            mixture.means[b],
            mixture.covariances[b]
        )
        shared = ordered_sum(row.responsibilities[a]*row.responsibilities[b] for row in selected.records)
        push!(lines,"$a-$b bhattacharyya $(dec(d)) coefficient $(dec(coefficient)) shared $(dec(shared))")
    end
    length(lines)==1 && push!(lines,"none")
    push!(blocks,lines,merging_block(selected))
    km = kmeans[k]
    matching,agreement,table = best_matching(selected.assignment,km.assignment,k)
    lines = [
        "kmeans K=$k",
        "iterations $(km.iterations)",
        "inertia $(dec(km.inertia))",
        "sizes $(integer_values(km.sizes))"
    ]
    append!(lines,["center $j $(real_values(center))" for (j,center) in enumerate(km.centers)])
    push!(lines,"contingency")
    append!(lines,[integer_values(table[j,:]) for j in 1:k])
    push!(
        lines,
        "ari $(ari_text(adjusted_rand(selected.assignment,km.assignment,k,k)))",
        "matching $(integer_values(matching))",
        "agreement $agreement/$(length(points)) $(dec(agreement/length(points)))"
    )
    disagree = 0
    for (i,p) in enumerate(points)
        component,cluster = selected.assignment[i],km.assignment[i]
        if matching[cluster]!=component
            disagree += 1
            push!(
                lines,
                "disagree $(p.id) gmm $component kmeans $cluster max $(dec(maximum(selected.records[i].responsibilities)))"
            )
        end
    end
    push!(lines,"disagreements $disagree")
    push!(blocks,lines)
    refit = refit_from_kmeans(selected,km,points,settings)
    push!(blocks,["refit_from_kmeans K=$k type=$(selected.type)","loglik $(dec(refit.loglik)) bic $(dec(refit.bic)) settled_at $(refit.settled_at)",
        "sizes $(integer_values(refit.sizes))","ari_vs_selected $(ari_text(adjusted_rand(selected.assignment,refit.assignment,k,k)))"])
    folds = settings.cv_folds
    lines = ["cross_validation K=$k type=$(selected.type) folds $folds"]
    scores = Float64[]
    for f in 0:folds-1
        training = [p for (i,p) in enumerate(points) if (i-1)%folds!=f]
        testing = [p for (i,p) in enumerate(points) if (i-1)%folds==f]
        fitted = run_em(training,initial[k],selected.type,settings.iterations,settings.epsilon)
        _,test_loglik = responsibilities(testing,fitted.model)
        push!(scores,test_loglik/length(testing))
        push!(
            lines,
            "fold $(f+1) train $(length(training)) test $(length(testing)) train_loglik $(dec(fitted.loglik/length(training))) test_loglik $(dec(scores[end]))"
        )
    end
    push!(lines,"mean_test_loglik $(dec(ordered_sum(scores)/folds))")
    push!(blocks,lines)
    uncertain = [i for i in eachindex(points) if maximum(selected.records[i].responsibilities)<settings.uncertain]
    sort!(uncertain;by=i->(rounded_four(maximum(selected.records[i].responsibilities)),i))
    lines = ["uncertain threshold $(dec(settings.uncertain))"]
    for i in uncertain
        row = selected.records[i]
        push!(
            lines,
            "$(points[i].id) component $(selected.assignment[i]) max $(dec(maximum(row.responsibilities))) responsibilities $(real_values(row.responsibilities))"
        )
    end
    push!(lines,"count $(length(uncertain))")
    push!(blocks,lines)
    outliers = [i for i in eachindex(points) if selected.records[i].log_density<settings.low_density]
    sort!(outliers;by=i->(rounded_four(selected.records[i].log_density),i))
    lines = ["outliers threshold $(dec(settings.low_density))"]
    for i in outliers
        c = selected.assignment[i]
        q = mahalanobis(point_xy(points[i]),mixture.means[c],mixture.covariances[c])
        push!(
            lines,
            "$(points[i].id) component $c log_density $(dec(selected.records[i].log_density)) q $(dec(q))"
        )
    end
    push!(lines,"count $(length(outliers))")
    push!(blocks,lines)
    blocks
end
function plot_maps(model,points,settings)
    xmin,xmax = settings.map_x
    ymin,ymax = settings.map_y
    width,height = settings.map_size
    dx,dy = (xmax-xmin)/width,(ymax-ymin)/height
    coordinates = [(xmin+(c-0.5)*dx,ymax-(r-0.5)*dy) for r in 1:height,c in 1:width]
    mixture,k = model.model,model.k
    densities = zeros(height,width)
    regions,uncertainty,point_map = fill(' ',height,width),fill(' ',height,width),fill(' ',height,width)
    for r in 1:height,c in 1:width
        scores = [weighted_log_density(
            coordinates[r,c],
            mixture.weights[j],
            mixture.means[j],
            mixture.covariances[j]
        ) for j in 1:k]
        densities[r,c] = ordered_sum(exp(score) for score in scores)
        regions[r,c] = Char(Int('0')+argmax(scores))
        if k>1
            maximum_score = maximum(scores)
            exponentials = exp.(scores.-maximum_score)
            probabilities = exponentials./ordered_sum(exponentials)
            level = clamp(floor(Int,10point_entropy(probabilities)/log(k)),0,9)
            uncertainty[r,c] = LEVELS[level+1]
        end
    end
    maximum_density = maximum(densities)
    density_map = fill(' ',height,width)
    counts = zeros(Int,10)
    mass = 0.0
    for r in 1:height,c in 1:width
        level = min(9,floor(Int,10densities[r,c]/maximum_density))
        counts[level+1] += 1
        density_map[r,c] = LEVELS[level+1]
        mass += densities[r,c]
    end
    mass = mass*dx*dy
    cell(point) = (floor(Int,(point[1]-xmin)/dx)+1,floor(Int,(ymax-point[2])/dy)+1)
    for (j,mean) in enumerate(mixture.means)
        c,r = cell(mean)
        1<=c<=width && 1<=r<=height && (density_map[r,c]=Char(Int('0')+j))
    end
    bins = [Set{Int}() for r in 1:height,c in 1:width]
    outside = 0
    for (p,label) in zip(points,model.assignment)
        c,r = cell(point_xy(p))
        if 1<=c<=width && 1<=r<=height
            push!(bins[r,c],label)
        else
            outside += 1
        end
    end
    for r in 1:height,c in 1:width
        if !isempty(bins[r,c])
            point_map[r,c] = length(bins[r,c])==1 ? Char(Int('0')+only(bins[r,c])) : '*'
            continue
        end
        contour = false
        for j in 1:k
            mahalanobis(coordinates[r,c],mixture.means[j],mixture.covariances[j])>4 && continue
            for (rr,cc) in ((r-1,c),(r+1,c),(r,c-1),(r,c+1))
                if 1<=rr<=height && 1<=cc<=width && mahalanobis(
                    coordinates[rr,cc],
                    mixture.means[j],
                    mixture.covariances[j]
                )>4
                    contour = true
                    break
                end
            end
            contour && break
        end
        point_map[r,c] = contour ? '.' : ' '
    end
    lines = [
        "density K=$k type=$(model.type)",
        "x $(dec(xmin)) $(dec(xmax)) y $(dec(ymin)) $(dec(ymax)) grid $(width)x$height",
        "max_density $(dec(maximum_density,6)) mass_in_map $(dec(mass))"
    ]
    append!(lines,framed(density_map))
    append!(
        lines,
        ["level $level \"$(LEVELS[level+1])\" from $(dec(level*maximum_density/10,6)) cells $(counts[level+1])" for level in 0:9]
    )
    for (name,grid) in (("regions",regions),("uncertainty",uncertainty),("points",point_map))
        push!(lines,"",name)
        append!(lines,framed(grid))
    end
    push!(lines,"outside $outside")
    lines
end
function main()
    points,initial,settings = read_all()
    models = NamedTuple[]
    for k in settings.ks,(type_index,type) in enumerate(settings.types)
        run = run_em(points,initial[k],type,settings.iterations,settings.epsilon)
        push!(models,summarize_run(run,k,type,type_index,length(points),settings.settle))
    end
    selected = ranking(models,"bic")[1]
    kmeans = Dict(k=>run_kmeans(points,initial[k].means,settings.kmeans_iterations) for k in settings.ks)
    trace = ["K,type,iteration,loglik"]
    for m in models,(t,value) in enumerate(m.trace)
        push!(trace,"$(m.k),$(m.type),$(t-1),$(dec(value))")
    end
    assignments_text = ["id,component,max_responsibility,log_density,kmeans_cluster"]
    for (i,p) in enumerate(points)
        row = selected.records[i]
        push!(
            assignments_text,
            "$(p.id),$(selected.assignment[i]),$(dec(maximum(row.responsibilities))),$(dec(row.log_density)),$(kmeans[selected.k].assignment[i])"
        )
    end
    write_blocks("models.txt",model_blocks(models))
    write_lines("loglik_trace.csv",trace)
    write_lines("assignments.csv",assignments_text)
    write_blocks("selection.txt",selection_blocks(models,selected,kmeans,points,initial,settings))
    write_lines("density_map.txt",plot_maps(selected,points,settings))
end
main()
