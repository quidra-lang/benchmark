using Printf
include("dataset.jl")
include("matrix.jl")
include("eigen.jl")
include("pca.jl")
include("plot.jl")
const CRITERIA = ("kaiser","broken_stick","parallel","cumulative")
function real_text(value,digits=4)
    text = Printf.format(Printf.Format("%.$(digits)f"),value)
    parse(Float64,text)==0 && startswith(text,"-") ? text[2:end] : text
end
reals(values) = real_text.(collect(values))
component_names(prefix,n) = ["$prefix$k" for k in 1:n]
top_indices(values,n) = sort(collect(eachindex(values));by=i->(-values[i],i))[1:min(n,length(values))]
congruence(a,b) = dot_product(a,b)/sqrt(dot_product(a,a)*dot_product(b,b))
function cumulative_ratios(values)
    result = Float64[]
    running = 0.0
    for value in values
        running += value
        push!(result,running)
    end
    result
end
function analysis_data(table,strategy,observed_means)
    indices = [i for i in eachindex(table.ids) if strategy!="listwise" || all(
        value->!isnothing(value),
        table.values[i,:]
    )]
    values = [
        isnothing(table.values[i,j]) ? observed_means[j] : table.values[i,j] for i in indices,
        j in eachindex(table.names)
    ]
    (ids=table.ids[indices],values=Float64.(values))
end
function decompose(data,scaling)
    means = column_means(data.values)
    covariance = covariance_matrix(data.values,means)
    deviations = standard_deviations(covariance)
    correlation = correlation_matrix(covariance,deviations)
    matrix = scaling=="covariance" ? covariance : correlation
    scales = scaling=="covariance" ? ones(length(means)) : deviations
    (
        data=data,
        means=means,
        covariance=covariance,
        correlation=correlation,
        matrix=matrix,
        scales=scales,
        eigen=jacobi(matrix)
    )
end
function adequacy(correlation,n)
    p = size(correlation,1)
    inverse,determinant = gauss_jordan(correlation)
    partial = [j==k ? 0.0 : -inverse[j,k]/sqrt(inverse[j,j]*inverse[k,k]) for j in 1:p,k in 1:p]
    rr = [sequential_sum(correlation[j,k]*correlation[j,k] for k in 1:p if k!=j) for j in 1:p]
    pp = [sequential_sum(partial[j,k]*partial[j,k] for k in 1:p if k!=j) for j in 1:p]
    msa = rr./(rr.+pp)
    total_rr,total_pp = sequential_sum(rr),sequential_sum(pp)
    (msa=msa,kmo=total_rr/(total_rr+total_pp),determinant=determinant,
     bartlett=-(n-1-(2p+5)/6)*log(determinant),df=p*(p-1)÷2)
end
function parallel_analysis(n,p,iterations,seed)
    state = seed
    function uniform()
        state = (48271state)%2147483647
        state/2147483647
    end
    totals = zeros(p)
    for _ in 1:iterations
        values = zeros(n,p)
        for i in 1:n,j in 1:p
            values[i,j] = uniform()
        end
        covariance = covariance_matrix(values,column_means(values))
        eigenvalues = jacobi(correlation_matrix(covariance,standard_deviations(covariance))).values
        sum_values = sequential_sum(eigenvalues)
        for k in 1:p
            totals[k] += eigenvalues[k]/sum_values
        end
    end
    totals./iterations
end
function variance_table(values,n,parallel,target)
    p = length(values)
    total = sequential_sum(values)
    average = total/p
    ratios = values./total
    cumulative = cumulative_ratios(ratios)
    broken = [sequential_sum(1/i for i in k:p)/p for k in 1:p]
    errors = values.*sqrt(2/n)
    separated = [all(abs(values[k]-values[h])>errors[k] for h in (k-1,k+1) if 1<=h<=p) for k in 1:p]
    function crossing(thresholds)
        i = findfirst(k->ratios[k]<=thresholds[k],1:p)
        isnothing(i) ? p : i-1
    end
    retention = Dict("kaiser"=>count(>(average),values),"broken_stick"=>crossing(broken),
        "parallel"=>crossing(parallel),"cumulative"=>findfirst(>=(target),cumulative))
    (total=total,average=average,ratios=ratios,cumulative=cumulative,broken=broken,parallel=parallel,
     errors=errors,separated=separated,retention=retention)
end
function varimax_criterion(g)
    p,k = size(g)
    value = 0.0
    for c in 1:k
        q4 = sequential_sum((g[j,c]*g[j,c])*(g[j,c]*g[j,c]) for j in 1:p)
        q2 = sequential_sum(g[j,c]*g[j,c] for j in 1:p)
        value += q4/p-(q2/p)*(q2/p)
    end
    value
end
function varimax(loadings,k,cycles)
    p = size(loadings,1)
    eta = [sqrt(sequential_sum(loadings[j,c]*loadings[j,c] for c in 1:k)) for j in 1:p]
    g = [loadings[j,c]/eta[j] for j in 1:p,c in 1:k]
    criteria = [varimax_criterion(g)]
    for _ in 1:cycles
        for a in 1:k-1,b in a+1:k
            phi = [g[j,a]*g[j,a]-g[j,b]*g[j,b] for j in 1:p]
            psi = [2g[j,a]*g[j,b] for j in 1:p]
            sa,sb = sequential_sum(phi),sequential_sum(psi)
            sc = sequential_sum(phi[j]*phi[j]-psi[j]*psi[j] for j in 1:p)
            sd = sequential_sum(2phi[j]*psi[j] for j in 1:p)
            num,den = sd-2sa*sb/p,sc-(sa*sa-sb*sb)/p
            omega = sqrt(num*num+den*den)
            omega==0 && continue
            cos4,sin4 = den/omega,num/omega
            cos2 = sqrt((1+cos4)/2)
            sin2 = cos2==0 ? 1.0 : sin4/(2cos2)
            cos1 = sqrt((1+cos2)/2)
            sin1 = sin2/(2cos1)
            for j in 1:p
                first_value,second_value = g[j,a],g[j,b]
                g[j,a],g[j,b] = cos1*first_value+sin1*second_value,-sin1*first_value+cos1*second_value
            end
        end
        push!(criteria,varimax_criterion(g))
    end
    columns = [orient(g[:,c].*eta) for c in 1:k]
    squares = [dot_product(column,column) for column in columns]
    order = sort(collect(1:k);by=c->(-squares[c],c))
    columns,squares = columns[order],squares[order]
    closest,congruences = Int[],Float64[]
    for column in columns
        values = [abs(congruence(column,loadings[:,c])) for c in 1:k]
        best = argmax(values)
        push!(closest,best)
        push!(congruences,values[best])
    end
    (columns=columns,squares=squares,criteria=criteria,closest=closest,congruences=congruences)
end
function observation(id,values,fit,k,settings)
    z = standardize(values,fit.means,fit.scales)
    scores = component_scores(z,fit.eigen.vectors)
    t2 = hotelling_t2(scores,fit.eigen.values,k)
    errors = residuals(z,scores,fit.eigen.vectors,k)
    spe = dot_product(errors,errors)
    flag = (t2>settings["T2_LIMIT"][1] ? "T" : "")*(spe>settings["SPE_LIMIT"][1] ? "Q" : "")
    (id=id,z=z,scores=scores,t2=t2,errors=errors,spe=spe,flag=isempty(flag) ? "-" : flag)
end
function build_report(dataset)
    data,settings = dataset.data,dataset.settings
    p = length(data.names)
    summaries = NamedTuple[]
    for j in 1:p
        values = Float64[v for v in data.values[:,j] if !isnothing(v)]
        observed = length(values)
        mean = sequential_sum(values)/observed
        sd = sqrt(sequential_sum((x-mean)*(x-mean) for x in values)/(observed-1))
        push!(
            summaries,
            (
                observed=observed,
                missing=length(data.ids)-observed,
                mean=mean,
                sd=sd,
                minimum=minimum(values),
                maximum=maximum(values)
            )
        )
    end
    means = [s.mean for s in summaries]
    incomplete = [data.ids[i] for i in eachindex(data.ids) if any(isnothing,data.values[i,:])]
    main_data = analysis_data(data,settings["MISSING"],means)
    fit = decompose(main_data,settings["SCALING"])
    n = length(main_data.ids)
    parallel = parallel_analysis(n,p,Int(settings["PARALLEL"][1]),Int(settings["PARALLEL"][2]))
    variance = variance_table(fit.eigen.values,n,parallel,settings["CUMULATIVE_TARGET"][1])
    rule = settings["COMPONENTS"]
    k = rule in CRITERIA ? max(1,variance.retention[rule]) : parse(Int,rule)
    loadings = [fit.eigen.vectors[c][j]*sqrt(fit.eigen.values[c]) for j in 1:p,c in 1:p]
    communalities = [sequential_sum(loadings[j,c]*loadings[j,c] for c in 1:k)/fit.matrix[j,j] for j in 1:p]
    circle = [loadings[j,c]/sqrt(fit.matrix[j,j]) for j in 1:p,c in 1:2]
    observations = [observation(
        id,
        main_data.values[i,:],
        fit,
        k,
        settings
    ) for (i,id) in enumerate(main_data.ids)]
    projections = [observation(
        id,
        dataset.supplementary.values[i,:],
        fit,
        k,
        settings
    ) for (i,id) in enumerate(dataset.supplementary.ids)]
    sensitivities = NamedTuple[]
    for strategy in ("listwise","mean"),scaling in ("covariance","correlation")
        alternative = decompose(analysis_data(data,strategy,means),scaling)
        eigenvalues = alternative.eigen.values
        ratios = eigenvalues./sequential_sum(eigenvalues)
        agreement = [abs(dot_product(alternative.eigen.vectors[c],fit.eigen.vectors[c])) for c in 1:k]
        push!(sensitivities,(strategy=strategy,scaling=scaling,rows=length(alternative.data.ids),sweeps=alternative.eigen.sweeps,
                           eigenvalues=eigenvalues[1:k],cumulative=cumulative_ratios(ratios)[k],agreement=agreement))
    end
    (dataset=dataset,settings=settings,names=data.names,p=p,n=n,summaries=summaries,incomplete=incomplete,
     fit=fit,variance=variance,k=k,loadings=loadings,communalities=communalities,circle=circle,
     adequacy=adequacy(fit.correlation,n),power=power_iteration(fit.matrix,fit.eigen.vectors),
     varimax=varimax(
         loadings,
         k,
         Int(settings["VARIMAX_CYCLES"][1])
     ),observations=observations,projections=projections,sensitivity=sensitivities)
end
function eigen_sections(r)
    settings,fit,v = r.settings,r.fit,r.variance
    incomplete = isempty(r.incomplete) ? "0 -" : "$(length(r.incomplete)) "*join(r.incomplete," ")
    sections = [[
        "pca rows $(length(r.dataset.data.ids)) used $(r.n) variables $(r.p) missing $(settings["MISSING"]) scaling $(settings["SCALING"])",
        "incomplete $incomplete"
    ]]
    lines = ["variable observed missing mean sd min max msa"]
    for (j,name) in enumerate(r.names)
        summary = r.summaries[j]
        push!(
            lines,
            "$name $(summary.observed) $(summary.missing) "*join(
                reals([summary.mean,summary.sd,summary.minimum,summary.maximum,r.adequacy.msa[j]]),
                " "
            )
        )
    end
    a = r.adequacy
    push!(
        lines,
        "adequacy kmo $(real_text(a.kmo)) determinant $(real_text(a.determinant,6)) bartlett $(real_text(a.bartlett)) df $(a.df)"
    )
    push!(sections,lines)
    lines = ["matrix $(settings["SCALING"])"]
    append!(lines,["$name "*join(reals(fit.matrix[j,:])," ") for (j,name) in enumerate(r.names)])
    pairs = [(j,k) for j in 1:r.p-1 for k in j+1:r.p]
    strengths = [abs(fit.correlation[j,k]) for (j,k) in pairs]
    selected = top_indices(strengths,Int(settings["TOP_ROWS"][1]))
    push!(
        lines,
        "strongest "*join(
            ["$(r.names[pairs[i][1]]):$(r.names[pairs[i][2]]):$(real_text(fit.correlation[pairs[i]...]))" for i in selected],
            " "
        )
    )
    push!(sections,lines)
    lines = [
        "jacobi sweeps $(fit.eigen.sweeps)",
        "eigenvalues total $(real_text(v.total)) average $(real_text(v.average))",
        "k eigenvalue ratio cumulative broken_stick parallel se separated"
    ]
    for k in 1:r.p
        values = reals([
            fit.eigen.values[k],
            v.ratios[k],
            v.cumulative[k],
            v.broken[k],
            v.parallel[k],
            v.errors[k]
        ])
        push!(lines,"$k "*join(values," ")*" "*(v.separated[k] ? "yes" : "no"))
    end
    push!(
        lines,
        "retention "*join(
            ["$name $(v.retention[name])" for name in CRITERIA],
            " "
        )*" target $(real_text(settings["CUMULATIVE_TARGET"][1]))",
        "components $(r.k) rule $(settings["COMPONENTS"])"
    )
    push!(sections,lines)
    lines = ["eigenvectors",join(vcat(["variable"],component_names("pc",r.p))," ")]
    append!(
        lines,
        [name*" "*join(
            reals(vector[j] for vector in fit.eigen.vectors),
            " "
        ) for (j,name) in enumerate(r.names)]
    )
    push!(sections,lines)
    lines = ["power_iteration iterations 1000","k jacobi power agree_at match"]
    matches = 0
    for (k,c) in enumerate(r.power)
        match = abs(c.value-fit.eigen.values[k])<=1e-8*fit.eigen.values[1] && max_difference(
            c.vector,
            fit.eigen.vectors[k]
        )<=1e-6
        matches += match
        push!(
            lines,
            "$k $(real_text(fit.eigen.values[k])) $(real_text(c.value)) $(isnothing(c.agreement) ? "-" : string(c.agreement)) $(match ? "yes" : "no")"
        )
    end
    push!(lines,"cross_check $matches/$(r.p)")
    push!(sections,lines)
    lines = ["scores","component sd min min_id max max_id contributors"]
    for k in 1:r.k
        scores = [o.scores[k] for o in r.observations]
        sd = sqrt(sequential_sum(t*t for t in scores)/(r.n-1))
        low,high = argmin(scores),argmax(scores)
        contributions = [t*t/((r.n-1)*fit.eigen.values[k]) for t in scores]
        fields = [
            "pc$k",
            real_text(sd),
            real_text(scores[low]),
            fit.data.ids[low],
            real_text(scores[high]),
            fit.data.ids[high]
        ]
        append!(
            fields,
            ["$(fit.data.ids[i]):$(real_text(contributions[i]))" for i in top_indices(
                contributions,
                Int(settings["TOP_ROWS"][1])
            )]
        )
        push!(lines,join(fields," "))
    end
    push!(sections,lines)
    lines = ["varimax components $(r.k) cycles $(Int(settings["VARIMAX_CYCLES"][1]))"]
    append!(
        lines,
        ["cycle $(c-1) criterion $(real_text(value,6))" for (c,value) in enumerate(r.varimax.criteria)]
    )
    for k in 1:r.k
        push!(
            lines,
            "rc$k ss $(real_text(r.varimax.squares[k])) ratio $(real_text(r.varimax.squares[k]/v.total)) closest pc$(r.varimax.closest[k]) congruence $(real_text(r.varimax.congruences[k]))"
        )
    end
    push!(sections,lines)
    lines = ["sensitivity","missing scaling rows sweeps eigenvalues cumulative congruence"]
    for s in r.sensitivity
        push!(
            lines,
            "$(s.strategy) $(s.scaling) $(s.rows) $(s.sweeps) "*join(
                reals(vcat(s.eigenvalues,[s.cumulative],s.agreement)),
                " "
            )
        )
    end
    push!(sections,lines)
    sections
end
function csv_files(r)
    lines = [join(vcat(["variable"],component_names("pc",r.k),["communality"],component_names("rc",r.k)),",")]
    for (j,name) in enumerate(r.names)
        values = vcat(r.loadings[j,1:r.k],[r.communalities[j]],[column[j] for column in r.varimax.columns])
        push!(lines,name*","*join(reals(values),","))
    end
    scores = [join(vcat(["id","set"],component_names("pc",r.k)),",")]
    for (observations,set) in ((r.observations,"data"),(r.projections,"supplementary")),o in observations
        push!(scores,o.id*","*set*","*join(reals(o.scores[1:r.k]),","))
    end
    lines,scores
end
function outlier_sections(r)
    lines = [
        "diagnostics components $(r.k) t2_limit $(real_text(r.settings["T2_LIMIT"][1])) spe_limit $(real_text(r.settings["SPE_LIMIT"][1]))",
        "id t2 spe quality flag"
    ]
    for o in r.observations
        quality = dot_product(o.scores[1:r.k],o.scores[1:r.k])/dot_product(o.z,o.z)
        push!(lines,o.id*" "*join(reals([o.t2,o.spe,quality])," ")*" "*o.flag)
    end
    flags = [o.flag for o in r.observations]
    push!(
        lines,
        "flagged t2 $(count(f->occursin('T',f),flags)) spe $(count(f->occursin('Q',f),flags)) both $(count(==("TQ"),flags)) any $(count(!=("-"),flags))"
    )
    sections = [lines]
    for label in ("t2","spe")
        values = [label=="t2" ? o.t2 : o.spe for o in r.observations]
        contributions = label=="spe" ? [o.errors.*o.errors for o in r.observations] :
            [[o.z[j]*sequential_sum((o.scores[k]/r.fit.eigen.values[k])*r.fit.eigen.vectors[k][j] for k in 1:r.k) for j in 1:r.p] for o in r.observations]
        lines = ["top $label","rank id $label variable contribution"]
        for (rank,i) in enumerate(top_indices(values,Int(r.settings["TOP_ROWS"][1])))
            j = argmax(contributions[i])
            push!(
                lines,
                "$rank $(r.fit.data.ids[i]) $(real_text(values[i])) $(r.names[j]) $(real_text(contributions[i][j]))"
            )
        end
        push!(sections,lines)
    end
    lines = ["reconstruction","k mean_spe max_spe max_id"]
    for k in 1:r.p-1
        errors = [begin
            e = residuals(o.z,o.scores,r.fit.eigen.vectors,k)
            dot_product(e,e)
        end for o in r.observations]
        worst = argmax(errors)
        push!(
            lines,
            "$k $(real_text(sequential_sum(errors)/r.n)) $(real_text(errors[worst])) $(r.fit.data.ids[worst])"
        )
    end
    push!(sections,lines)
    lines = [
        "supplementary",
        join(vcat(["id"],component_names("pc",r.k),["t2","spe","flag","nearest","distance"])," ")
    ]
    for o in r.projections
        distances = [sequential_sum((o.scores[k]-a.scores[k])*(o.scores[k]-a.scores[k]) for k in 1:r.k) for a in r.observations]
        nearest = argmin(distances)
        push!(
            lines,
            o.id*" "*join(
                reals(vcat(o.scores[1:r.k],[o.t2,o.spe])),
                " "
            )*" $(o.flag) $(r.fit.data.ids[nearest]) $(real_text(sqrt(distances[nearest])))"
        )
    end
    push!(sections,lines)
    sections
end
function draw_axes!(grid,center)
    row,column = center
    grid[row+1,:] .= "-"
    grid[:,column+1] .= "|"
    grid[row+1,column+1] = "+"
end
function mark_cells!(grid,cells,character)
    for (row,column) in cells
        grid[row+1,column+1] = character
    end
end
function draw_points!(grid,cells)
    counts = zeros(Int,size(grid))
    for (row,column) in cells
        counts[row+1,column+1] += 1
    end
    for i in axes(grid,1),j in axes(grid,2)
        n = counts[i,j]
        n>0 && (grid[i,j]=n==1 ? "." : n<=3 ? "o" : "@")
    end
end
inside_circle(row,column,center,radius) = (column-center[2])^2+(2*(row-center[1]))^2<=radius*radius
function plot_sections(r)
    settings = r.settings
    eigenvalues = r.fit.eigen.values
    width = Int(settings["SCREE_WIDTH"][1])
    kaiser = rounded_position(r.variance.average/eigenvalues[1],width)
    lines = ["scree width $width kaiser_column $kaiser"]
    for (k,value) in enumerate(eigenvalues)
        n = rounded_position(value/eigenvalues[1],width)
        broken = rounded_position(r.variance.broken[k]*r.variance.total/eigenvalues[1],width)
        push!(lines,scree_line(n,kaiser,broken,width)*" pc$k $(real_text(value))")
    end
    sections = [lines]
    width,height = Int.(settings["BIPLOT_SIZE"])
    points = vcat(r.observations,r.projections)
    x_limit = maximum(abs(o.scores[1]) for o in points)
    y_limit = maximum(abs(o.scores[2]) for o in points)
    arrow_scale = 0.9*min(x_limit/maximum(abs,r.loadings[:,1]),y_limit/maximum(abs,r.loadings[:,2]))
    origin = biplot_cell(0.0,0.0,x_limit,y_limit,width,height)
    tips = [biplot_cell(
        arrow_scale*r.loadings[j,1],
        arrow_scale*r.loadings[j,2],
        x_limit,
        y_limit,
        width,
        height
    ) for j in 1:r.p]
    cells = [biplot_cell(o.scores[1],o.scores[2],x_limit,y_limit,width,height) for o in points]
    grid = new_grid(height,width)
    draw_axes!(grid,origin)
    for tip in tips
        mark_cells!(grid,shaft_cells(origin,tip),shaft_character(origin,tip))
    end
    draw_points!(grid,cells[1:r.n])
    mark_cells!(grid,[cells[i] for i in 1:r.n if r.observations[i].flag!="-"],"X")
    mark_cells!(grid,cells[r.n+1:end],"*")
    for (j,tip) in enumerate(tips)
        mark_cells!(grid,[tip],string(Char(Int('A')+j-1)))
    end
    lines = [
        "biplot pc1 pc2 width $width height $height",
        "x $(real_text(-x_limit)) $(real_text(x_limit)) y $(real_text(-y_limit)) $(real_text(y_limit)) arrow_scale $(real_text(arrow_scale))"
    ]
    append!(lines,framed(grid))
    append!(
        lines,
        ["$(Char(Int('A')+j-1)) $(r.names[j]) $(real_text(r.loadings[j,1])) $(real_text(r.loadings[j,2]))" for j in 1:r.p]
    )
    push!(sections,lines)
    radius = Int(settings["CIRCLE_RADIUS"][1])
    center = (radius÷2+1,radius+1)
    grid = new_grid(radius+3,2radius+3)
    draw_axes!(grid,center)
    for row in 0:size(grid,1)-1,column in 0:size(grid,2)-1
        inside_circle(row,column,center,radius) || continue
        if any(!inside_circle(row+dr,column+dc,center,radius) for (dr,dc) in ((-1,0),(1,0),(0,-1),(0,1)))
            grid[row+1,column+1] = "."
        end
    end
    for j in 1:r.p
        mark_cells!(grid,[circle_cell(r.circle[j,1],r.circle[j,2],radius)],string(Char(Int('A')+j-1)))
    end
    lines = vcat(["circle radius $radius"],framed(grid))
    for j in 1:r.p
        a,b = r.circle[j,:]
        push!(lines,"$(Char(Int('A')+j-1)) $(r.names[j]) "*join(reals([a,b,a*a+b*b])," "))
    end
    push!(sections,lines)
    width,height = Int.(settings["DIAGNOSTIC_SIZE"])
    x,y = 2settings["T2_LIMIT"][1],2settings["SPE_LIMIT"][1]
    grid = new_grid(height,width)
    draw_axes!(grid,diagnostic_cell(x/2,y/2,x,y,width,height))
    draw_points!(grid,[diagnostic_cell(o.t2,o.spe,x,y,width,height) for o in r.observations])
    mark_cells!(grid,[diagnostic_cell(o.t2,o.spe,x,y,width,height) for o in r.projections],"*")
    push!(
        sections,
        vcat(
            ["diagnostic width $width height $height t2_max $(real_text(x)) spe_max $(real_text(y))"],
            framed(grid)
        )
    )
    sections
end
function join_sections(sections)
    lines = String[]
    for section in sections
        isempty(lines) || push!(lines,"")
        append!(lines,section)
    end
    lines
end
function write_lines(name,lines)
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function main()
    report = build_report(load_dataset())
    loadings,scores = csv_files(report)
    mkpath("output")
    write_lines("eigen.txt",join_sections(eigen_sections(report)))
    write_lines("loadings.csv",loadings)
    write_lines("scores.csv",scores)
    write_lines("outliers.txt",join_sections(outlier_sections(report)))
    write_lines("plots.txt",join_sections(plot_sections(report)))
end
main()
