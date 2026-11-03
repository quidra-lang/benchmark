using Printf
include("dataset.jl")
include("selection.jl")
include("kernels.jl")
include("loess.jl")
include("spline.jl")

estimate(model,position) = model.estimate(position)
weights(model,position) = model.weights(position)
residual_square(observed,fitted) = ordered_sum((y-fit)*(y-fit) for (y,fit) in zip(observed,fitted))
function linear_fit(points)
    x,y = first.(points)./100,last.(points)./100
    n = length(points)
    xbar,ybar = ordered_sum(x)/n,ordered_sum(y)/n
    sxx = ordered_sum((v-xbar)*(v-xbar) for v in x)
    sxy = ordered_sum((v-xbar)*(w-ybar) for (v,w) in zip(x,y))
    slope = sxy/sxx
    intercept = ybar-slope*xbar
    fitted = [intercept+slope*v for v in x]
    leverage = [1/n+(v-xbar)*(v-xbar)/sxx for v in x]
    (
        fitted=fitted,leverage=leverage,edf=2.0,
        estimate=position->intercept+slope*(position/100),
        weights=position->[1/n+(position/100-xbar)*(v-xbar)/sxx for v in x]
    )
end
function running_fit(points,width,use_median)
    positions = first.(points)
    n = length(points)
    half = (width-1)÷2
    windows = UnitRange{Int}[]
    fitted,diagonal = Float64[],Float64[]
    for i in 1:n
        radius = min(half,i-1,n-i)
        window = (i-radius):(i+radius)
        values = [points[j][2] for j in window]
        push!(windows,window)
        push!(fitted,use_median ? sort(values)[radius+1]/100 : sum(values)/(100*length(values)))
        push!(diagonal,1/length(values))
    end
    nearest(position) = argmin(abs.(positions.-position))
    (
        fitted=fitted,leverage=use_median ? nothing : diagonal,edf=use_median ? nothing : ordered_sum(diagonal),
        estimate=position->fitted[nearest(position)],
        weights=position->[i in windows[nearest(position)] ? 1/length(windows[nearest(position)]) : 0.0 for i in 1:n]
    )
end
function fit_direction(points,direction)
    blocks = Tuple{Int,Int,Int,Int}[]
    for (i,(_,value)) in enumerate(points)
        push!(blocks,(i,i,value,1))
        while length(blocks) >= 2
            left,right = blocks[end-1:end]
            a,b = left[3]*right[4],right[3]*left[4]
            violates = direction == "increasing" ? a > b : a < b
            violates || break
            pop!(blocks)
            pop!(blocks)
            push!(blocks,(left[1],right[2],left[3]+right[3],left[4]+right[4]))
        end
    end
    fitted = zeros(length(points))
    for (start,stop,total,count) in blocks
        fitted[start:stop] .= total/(100*count)
    end
    fitted,blocks
end
function isotonic_fit(points,mode)
    positions = first.(points)
    observed = last.(points)./100
    increasing,decreasing = fit_direction(points,"increasing"),fit_direction(points,"decreasing")
    rss_increasing,rss_decreasing = residual_square(observed,increasing[1]),residual_square(
        observed,
        decreasing[1]
    )
    direction = mode == "auto" ? (rss_increasing <= rss_decreasing ? "increasing" : "decreasing") : mode
    fitted,blocks = direction == "increasing" ? increasing : decreasing
    (
        positions=positions,mode=mode,direction=direction,fitted=fitted,blocks=blocks,leverage=nothing,edf=Float64(length(blocks)),
        rss_increasing=rss_increasing,rss_decreasing=rss_decreasing,
        estimate=position->fitted[max(1,searchsortedlast(positions,position))]
    )
end
function methods_in_order(settings)
    vcat(
        ["linear","running_mean","running_median"],
        ["nw_"*name for name in settings["KERNELS"]],
        ["ll_"*name for name in settings["KERNELS"]],
        ["loess"*degree for degree in settings["LOESS_DEGREES"]],
        ["spline","isotonic"]
    )
end
function parameters_for(method,settings)
    startswith(method,"running_") && return settings["WINDOWS"]
    (startswith(method,"nw_") || startswith(method,"ll_")) && return settings["BANDWIDTHS"]
    startswith(method,"loess") && return settings["SPANS"]
    method == "spline" ? settings["LAMBDAS"] : String[]
end
function fit_model(method,parameter,points,settings,direction;robust=true,diagnostics=true)
    method == "linear" && return linear_fit(points)
    startswith(method,"running_") && return running_fit(
        points,
        parse(Int,parameter),
        method == "running_median"
    )
    method == "isotonic" && return isotonic_fit(points,direction)
    positions,values = first.(points),last.(points)./100
    if startswith(method,"nw_") || startswith(method,"ll_")
        return KernelFit(
            positions,
            values,
            hundredths(parameter),
            method[4:end],
            startswith(method,"ll_");diagnostics=diagnostics
        )
    elseif startswith(method,"loess")
        iterations = robust ? settings["ROBUST_ITERATIONS"] : 0
        return LoessFit(
            positions,
            values,
            hundredths(parameter),
            parse(Int,method[6:end]),
            iterations;diagnostics=diagnostics
        )
    end
    SplineFit(positions,values,parse(Float64,parameter);diagnostics=diagnostics)
end
function validation_predictions(method,parameter,points,settings,direction,folds)
    predictions = Any[nothing for _ in points]
    for group in 0:folds-1
        training = [point for (i,point) in enumerate(points) if (i-1)%folds != group]
        model = fit_model(method,parameter,training,settings,direction;robust=false,diagnostics=false)
        for i in (group+1):folds:length(points)
            predictions[i] = estimate(model,points[i][1])
        end
    end
    predictions
end
function select_models(points,settings,methods,mode)
    observed = last.(points)./100
    entries = Dict{String,Dict{Symbol,Any}}()
    for method in methods
        candidates = NamedTuple[]
        for parameter in parameters_for(method,settings)
            candidate = fit_model(method,parameter,points,settings,mode;robust=false)
            score = method == "spline" ? generalized_score(observed,candidate.fitted,candidate.edf) : cross_validation_score(
                observed,
                validation_predictions(method,parameter,points,settings,mode,length(points))
            )
            push!(candidates,(parameter=parameter,score=score,edf=candidate.edf))
        end
        best = isempty(candidates) ? 0 : choose_candidate(candidates)
        parameter = best == 0 ? (method == "linear" ? "-" : mode) : candidates[best].parameter
        model = fit_model(method,parameter,points,settings,mode)
        direction = method == "isotonic" ? model.direction : mode
        method == "isotonic" && (parameter=direction)
        loo = best != 0 && method != "spline" ? candidates[best].score : cross_validation_score(
            observed,
            validation_predictions(method,parameter,points,settings,direction,length(points))
        )
        kfold = cross_validation_score(
            observed,
            validation_predictions(method,parameter,points,settings,direction,settings["CV_FOLDS"])
        )
        entries[method] = Dict(
            :model=>model,
            :parameter=>parameter,
            :loo=>loo,
            :kfold=>kfold,
            :candidates=>candidates,
            :best=>best,
            :gcv=>method == "spline" ? candidates[best].score : nothing
        )
    end
    entries
end
function quantiles(residuals)
    ordered = sort(residuals)
    result = Float64[]
    for k in 0:4
        index,remainder = divrem((length(ordered)-1)*k,4)
        value = ordered[index+1]
        remainder != 0 && (value += remainder/4*(ordered[index+2]-ordered[index+1]))
        push!(result,value)
    end
    result
end
function residual_runs(residuals)
    signs = [value > 0 ? 1 : -1 for value in residuals if value != 0]
    positive,negative = count(==(1),signs),count(==(-1),signs)
    n = length(signs)
    runs = 1+sum(signs[i] != signs[i+1] for i in 1:n-1;init=0)
    product = 2*positive*negative
    mean = 1+product/n
    variance = product*(product-n)/(n*n*(n-1))
    runs,positive,negative,(runs-mean)/sqrt(variance)
end
function turning_count(grid_values)
    values = filter(value->!isnothing(value),grid_values)
    differences = [values[i+1]-values[i] for i in 1:length(values)-1 if values[i+1] != values[i]]
    sum((differences[i] > 0) != (differences[i+1] > 0) for i in 1:length(differences)-1;init=0)
end
function diagnostics(method,model,observed,grid_values,linear_rss)
    residuals = observed.-model.fitted
    n = length(observed)
    rss = ordered_sum(value*value for value in residuals)
    mean = ordered_sum(observed)/n
    tss = ordered_sum((y-mean)*(y-mean) for y in observed)
    edf = model.edf
    df = isnothing(edf) ? nothing : n-edf
    rse = isnothing(edf) ? nothing : sqrt(rss/df)
    nonlinear = method != "linear" && !isnothing(edf) && edf > 2 ? ((linear_rss-rss)/(edf-2))/(rss/df) : nothing
    residual_mean = ordered_sum(residuals)/n
    centered = residuals.-residual_mean
    denominator = ordered_sum(value*value for value in centered)
    acf = [ordered_sum(centered[i]*centered[i+lag] for i in 1:n-lag)/denominator for lag in 1:5]
    dw = ordered_sum((residuals[i+1]-residuals[i])*(residuals[i+1]-residuals[i]) for i in 1:n-1)/rss
    (
        residuals=residuals,rss=rss,edf=edf,df=df,rse=rse,r2=1-rss/tss,f_nonlinear=nonlinear,
        acf=acf,dw=dw,runs=residual_runs(residuals),largest=argmax(abs.(residuals)),
        quantiles=quantiles(residuals),turning=turning_count(grid_values)
    )
end
function agreements(entries,methods,ranking,grid)
    best = entries[ranking[1]][:grid_values]
    result = Dict{String,Any}()
    for method in methods
        method == ranking[1] && continue
        own = entries[method][:grid_values]
        pairs = [(
            i,
            abs(value-target)
        ) for (i,(value,target)) in enumerate(zip(own,best)) if !isnothing(value) && !isnothing(target)]
        maximum_pair = pairs[argmax(last.(pairs))]
        result[method] = (
            length(pairs),
            sqrt(ordered_sum(d*d for (_,d) in pairs)/length(pairs)),
            maximum_pair[2],
            grid[maximum_pair[1]]
        )
    end
    result
end
function spline_slopes(values,grid)
    slopes = [(values[i+1]-values[i-1])/((grid[i+1]-grid[i-1])/100) for i in 2:length(grid)-1]
    hi,lo = argmax(slopes),argmin(slopes)
    slopes[hi],grid[hi+1],slopes[lo],grid[lo+1]
end
function outliers_and_influence(entries,ranking,threshold)
    method = first(name for name in ranking if !isnothing(entries[name][:model].leverage))
    model,stats = entries[method][:model],entries[method][:diagnostics]
    standardized,cooks = Dict{Int,Float64}(),Dict{Int,Float64}()
    for (i,leverage) in enumerate(model.leverage)
        if leverage < 1
            value = stats.residuals[i]/(stats.rse*sqrt(1-leverage))
            standardized[i] = value
            cooks[i] = value*value*leverage/((1-leverage)*model.edf)
        end
    end
    outliers = sort(
        [i for i in keys(standardized) if abs(standardized[i]) > threshold],
        by=i->(-abs(standardized[i]),i)
    )
    influential = sort(collect(keys(cooks)),by=i->(-cooks[i],i))[1:min(3,length(cooks))]
    (method=method,standardized=standardized,cooks=cooks,outliers=outliers,influential=influential)
end
function variability_bands(model,rse,grid,z)
    rows = Any[]
    for position in grid
        value = estimate(model,position)
        if isnothing(value)
            push!(rows,(nothing,nothing,nothing,nothing))
        else
            coefficients = weights(model,position)
            se = rse*sqrt(ordered_sum(weight*weight for weight in coefficients))
            push!(rows,(value,se,value-z*se,value+z*se))
        end
    end
    rows
end
function band_summary(entry,positions,bands,z)
    errors = [row[2] for row in bands if !isnothing(row[1])]
    stats = entry[:diagnostics]
    covered = 0
    for (position,residual) in zip(positions,stats.residuals)
        coefficients = weights(entry[:model],position)
        se = stats.rse*sqrt(ordered_sum(value*value for value in coefficients))
        covered += abs(residual) <= z*sqrt(stats.rse*stats.rse+se*se)
    end
    ordered_sum(errors)/length(errors),covered
end
mutable struct Minstd
    state::Int
end
function draw_index!(generator,count)
    generator.state = mod(48271*generator.state,2147483647)
    generator.state%count+1
end
function bootstrap_intervals(entry,grid,count,trim,generator)
    model = entry[:model]
    residuals = entry[:diagnostics].residuals
    mean = ordered_sum(residuals)/length(residuals)
    centered = residuals.-mean
    estimates = [Float64[] for _ in grid]
    for _ in 1:count
        response = [value+centered[draw_index!(generator,length(centered))] for value in model.fitted]
        fit = fit_values(model,response)
        for (position,values) in zip(grid,estimates)
            push!(values,evaluate_fit(model,fit,position))
        end
    end
    result = Any[]
    for (position,values) in zip(grid,estimates)
        average = ordered_sum(values)/count
        se = sqrt(ordered_sum((value-average)*(value-average) for value in values)/(count-1))
        ordered = sort(values)
        push!(result,(estimate(model,position),se,ordered[trim+1],ordered[count-trim]))
    end
    result
end
function analyze_series(points,settings,methods,mode,generator)
    positions,values = first.(points),last.(points)./100
    count = settings["GRID_POINTS"]
    grid = [positions[1]+k*(positions[end]-positions[1])÷(count-1) for k in 0:count-1]
    entries = select_models(points,settings,methods,mode)
    linear_rss = residual_square(values,entries["linear"][:model].fitted)
    for method in methods
        entry = entries[method]
        entry[:grid_values] = [estimate(entry[:model],position) for position in grid]
        entry[:diagnostics] = diagnostics(method,entry[:model],values,entry[:grid_values],linear_rss)
    end
    ranking = sort(copy(methods),by=method->(entries[method][:loo],findfirst(==(method),methods)))
    bands,summaries = Dict{String,Any}(),Dict{String,Any}()
    for method in settings["BAND_METHODS"]
        entry = entries[method]
        bands[method] = variability_bands(entry[:model],entry[:diagnostics].rse,grid,settings["BAND_Z"])
        summaries[method] = band_summary(entry,positions,bands[method],settings["BAND_Z"])
    end
    repetitions,trim,_ = settings["BOOTSTRAP"]
    bands["spline_bootstrap"] = bootstrap_intervals(entries["spline"],grid,repetitions,trim,generator)
    (
        points=points,grid=grid,entries=entries,ranking=ranking,agreement=agreements(
            entries,
            methods,
            ranking,
            grid
        ),
        slope=spline_slopes(entries["spline"][:grid_values],grid),outlier=outliers_and_influence(
            entries,
            ranking,
            settings["OUTLIER_THRESHOLD"]
        ),
        bands=bands,band_summary=summaries
    )
end
function real_text(value,places=4)
    isnothing(value) && return "NA"
    result = Printf.format(Printf.Format("%.$(places)f"),value)
    zero = Printf.format(Printf.Format("%.$(places)f"),0.0)
    result == "-"*zero ? zero : result
end
position_text(value) = (value < 0 ? "-" : "")*"$(abs(value)÷100).$(lpad(abs(value)%100,2,'0'))"
real_list(values) = join(real_text.(values),' ')
function join_blocks(blocks)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines,"")
        append!(lines,block)
    end
    lines
end
function method_diagnostic_lines(method,entry,points)
    stats = entry[:diagnostics]
    first_line = "method $method parameter $(entry[:parameter]) loo $(real_text(entry[:loo]))"
    method == "spline" && (first_line *= " gcv $(real_text(entry[:gcv]))")
    runs,positive,negative,z = stats.runs
    largest = stats.largest
    lines = [
        first_line,
        "  rss $(real_text(stats.rss)) edf $(real_text(stats.edf)) df $(real_text(stats.df)) rse $(real_text(stats.rse)) r2 $(real_text(stats.r2)) f_nonlinear $(real_text(stats.f_nonlinear))",
        "  acf $(real_list(stats.acf)) dw $(real_text(stats.dw))",
        "  runs $runs positive $positive negative $negative z $(real_text(z))",
        "  max_residual $(real_text(stats.residuals[largest])) at $(position_text(points[largest][1])) turning $(stats.turning)",
        "  quantiles "*real_list(stats.quantiles)
    ]
    if startswith(method,"loess")
        model = entry[:model]
        for (iteration,scale,zero_count,change) in model.records
            push!(
                lines,
                "  robust $iteration scale $(real_text(scale)) zero_weight $zero_count max_change $(real_text(change))"
            )
        end
        zero_points = [position_text(points[i][1]) for (i,weight) in enumerate(model.rho) if weight == 0]
        push!(lines,"  zero_weight_points "*(isempty(zero_points) ? "none" : join(zero_points,' ')))
    end
    lines
end
function diagnostics_block(name,analysis,methods,settings)
    points,entries,ranking = analysis.points,analysis.entries,analysis.ranking
    ys = last.(points)
    lines = ["series $name n $(length(points)) x $(position_text(points[1][1])) $(position_text(points[end][1])) y $(position_text(minimum(ys))) $(position_text(maximum(ys)))"]
    for method in methods
        append!(lines,method_diagnostic_lines(method,entries[method],points))
    end
    push!(lines,"ranking")
    for (rank,method) in enumerate(ranking)
        push!(
            lines,
            "  $rank $method $(real_text(entries[method][:loo])) kfold $(real_text(entries[method][:kfold]))"
        )
    end
    push!(lines,"agreement with "*ranking[1])
    for method in methods
        method == ranking[1] && continue
        count,rms,maximum_value,position = analysis.agreement[method]
        push!(
            lines,
            "  $method points $count rms $(real_text(rms)) max $(real_text(maximum_value)) at $(position_text(position))"
        )
    end
    maximum_value,at_max,minimum_value,at_min = analysis.slope
    push!(
        lines,
        "slope spline max $(real_text(maximum_value)) at $(position_text(at_max)) min $(real_text(minimum_value)) at $(position_text(at_min))"
    )
    data = analysis.outlier
    entry = entries[data.method]
    model,residuals = entry[:model],entry[:diagnostics].residuals
    push!(lines,"outliers method $(data.method) threshold $(real_text(settings["OUTLIER_THRESHOLD"],2))")
    for i in data.outliers
        push!(
            lines,
            "  x $(position_text(points[i][1])) y $(position_text(points[i][2])) fit $(real_text(model.fitted[i])) residual $(real_text(residuals[i])) standardized $(real_text(data.standardized[i]))"
        )
    end
    isempty(data.outliers) && push!(lines,"  none")
    push!(lines,"influence method "*data.method)
    for i in data.influential
        push!(
            lines,
            "  x $(position_text(points[i][1])) lev $(real_text(model.leverage[i])) cook $(real_text(data.cooks[i]))"
        )
    end
    push!(lines,"bands")
    for method in settings["BAND_METHODS"]
        mean_se,covered = analysis.band_summary[method]
        push!(lines,"  $method mean_se $(real_text(mean_se)) coverage $covered of $(length(points))")
    end
    lines
end
function isotonic_block(name,analysis)
    entry = analysis.entries["isotonic"]
    model = entry[:model]
    first_line = "series $name direction $(model.direction) mode $(model.mode)"
    model.mode == "auto" && (first_line *= " rss_increasing $(real_text(model.rss_increasing)) rss_decreasing $(real_text(model.rss_decreasing))")
    lines = [
        first_line,
        "blocks $(length(model.blocks)) rss $(real_text(entry[:diagnostics].rss)) loo $(real_text(entry[:loo]))"
    ]
    for (number,(start,stop,total,count)) in enumerate(model.blocks)
        push!(
            lines,
            "block $number x $(position_text(model.positions[start])) $(position_text(model.positions[stop])) count $count value $(real_text(total/(100*count)))"
        )
    end
    lines
end
function framed(grid)
    border = "+"*repeat("-",size(grid,2))*"+"
    vcat([border],["|"*join(grid[row,:])*"|" for row in axes(grid,1)],[border])
end
function histogram_lines(standardized)
    counts = zeros(Int,14)
    for value in values(standardized)
        index = value < -3 ? 1 : value >= 3 ? 14 : 2+floor(Int,(value+3)/0.5)
        counts[index] += 1
    end
    lines = String[]
    for (i,count) in enumerate(counts)
        lower = i == 1 ? "-inf" : real_text(-3+0.5*(i-2),2)
        upper = i == 14 ? "inf" : real_text(-3+0.5*(i-1),2)
        push!(lines,"$lower $upper $count |"*repeat("#",count))
    end
    lines
end
function plot_block(name,analysis,settings)
    points = analysis.points
    width,height = settings["PLOT_SIZE"]
    xa,xb = points[1][1],points[end][1]
    ya,yb = minimum(last.(points)),maximum(last.(points))
    columns = [min(width-1,width*(x-xa)÷(xb-xa))+1 for (x,_) in points]
    grid = fill(' ',height,width)
    for (column,(_,y)) in zip(columns,points)
        row = min(height-1,height*(yb-y)÷(yb-ya))+1
        grid[row,column] = '.'
    end
    for (number,method) in enumerate(settings["PLOT_METHODS"]), column in 0:width-1
        position = xa+(2*column+1)*(xb-xa)÷(2*width)
        value = estimate(analysis.entries[method][:model],position)
        isnothing(value) && continue
        pi = height*(yb/100-value)/(yb/100-ya/100)
        row = clamp(floor(Int,pi),0,height-1)+1
        digit = Char(Int('0')+number)
        grid[row,column+1] = grid[row,column+1] in (' ','.',digit) ? digit : '*'
    end
    legend = join(("$i $method" for (i,method) in enumerate(settings["PLOT_METHODS"])), ' ')
    lines = [
        "plot $name size $(width)x$height x $(position_text(xa)) $(position_text(xb)) y $(position_text(ya)) $(position_text(yb))",
        "legend . data "*legend
    ]
    append!(lines,framed(grid))
    push!(
        lines,
        "cells data $(count(==('.'),grid)) curve $(count(c->'0' <= c <= '9',grid)) overlap $(count(==('*'),grid))"
    )
    method = analysis.ranking[1]
    residuals = analysis.entries[method][:diagnostics].residuals
    limit = maximum(abs.(residuals))
    grid = fill(' ',height,width)
    grid[height÷2+1,:] .= '-'
    for (column,residual) in zip(columns,residuals)
        row = clamp(floor(Int,height*((limit-residual)/(2*limit))),0,height-1)+1
        grid[row,column] = 'o'
    end
    append!(lines,["","residuals $name method $method limit $(real_text(limit))"])
    append!(lines,framed(grid))
    append!(lines,["","histogram $name method $(analysis.outlier.method)"])
    append!(lines,histogram_lines(analysis.outlier.standardized))
    lines
end
function main()
    names,series,tests,settings = read_dataset()
    methods = methods_in_order(settings)
    generator = Minstd(settings["BOOTSTRAP"][3])
    analyses = Dict{String,Any}()
    for (name,mode) in zip(names,settings["ISOTONIC"])
        analyses[name] = analyze_series(series[name],settings,methods,mode,generator)
    end
    selection = ["series,method,parameter,score,edf,selected"]
    fits,predictions = ["series,x,"*join(methods,',')],["series,x,"*join(methods,',')]
    bands = ["series,method,x,fit,se,lower,upper"]
    for name in names
        analysis = analyses[name]
        for method in methods, (i,candidate) in enumerate(analysis.entries[method][:candidates])
            push!(
                selection,
                join(
                    (
                        name,
                        method,
                        candidate.parameter,
                        real_text(candidate.score),
                        real_text(candidate.edf),
                        i == analysis.entries[method][:best] ? "1" : "0"
                    ),
                    ','
                )
            )
        end
        for (i,position) in enumerate(analysis.grid)
            row = vcat(
                [name,position_text(position)],
                [real_text(analysis.entries[method][:grid_values][i]) for method in methods]
            )
            push!(fits,join(row,','))
        end
        for method in vcat(
            settings["BAND_METHODS"],
            ["spline_bootstrap"]
        ), (position,row) in zip(analysis.grid,analysis.bands[method])
            push!(bands,join(vcat([name,method,position_text(position)],real_text.(collect(row))),','))
        end
    end
    for (name,position) in tests
        row = vcat(
            [name,position_text(position)],
            [real_text(estimate(analyses[name].entries[method][:model],position)) for method in methods]
        )
        push!(predictions,join(row,','))
    end
    outputs = (
        "selection.csv"=>selection,"fits.csv"=>fits,"predictions.csv"=>predictions,"bands.csv"=>bands,
        "diagnostics.txt"=>join_blocks(diagnostics_block(
            name,
            analyses[name],
            methods,
            settings
        ) for name in names),
        "isotonic.txt"=>join_blocks(isotonic_block(name,analyses[name]) for name in names),
        "plots.txt"=>join_blocks(plot_block(name,analyses[name],settings) for name in settings["PLOT_SERIES"])
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do handle
            foreach(line->println(handle,line),lines)
        end
    end
end
main()
