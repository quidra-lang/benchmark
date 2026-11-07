include("dataframe.jl")
include("formula.jl")
include("qr_solver.jl")
include("inference.jl")
include("diagnostics.jl")
function table(header,rows,marks=fill("",length(rows)))
    records = vcat([String.(header)],[string.(row) for row in rows])
    widths = [maximum(length(row[c]) for row in records if c<=length(row)) for c in eachindex(header)]
    lines = String[]
    for (row,mark) in zip(records,vcat([""],marks))
        line = rpad(row[1],widths[1])
        for c in 2:length(row)
            line *= "  "*lpad(row[c],widths[c])
        end
        isempty(mark) || (line*=" "*mark)
        push!(lines,rstrip(line))
    end
    lines
end
function data_summary(data)
    numeric = [name for name in data.columns if !data.kinds[name]]
    rows = []
    for name in numeric
        values = Float64[row[name] for row in data.rows if !isnothing(row[name])]
        n = length(values)
        mean = ordered_sum(values)/n
        sd = sqrt(ordered_sum((v-mean)*(v-mean) for v in values)/(n-1))
        push!(
            rows,
            [
                name,
                string(n),
                string(length(data.rows)-n),
                four(mean),
                four(sd),
                four(minimum(values)),
                four(maximum(values))
            ]
        )
    end
    lines = ["Data: $(length(data.rows)) rows, $(length(data.columns)) columns","","Numeric columns:"]
    append!(lines,table(["column","n","missing","Mean","SD","Min","Max"],rows))
    push!(lines,"","Categorical columns:")
    for name in data.columns
        data.kinds[name] || continue
        values = [row[name] for row in data.rows if !isnothing(row[name])]
        levels = sort(unique(values))
        counts = ["$level $(count(==(level),values))" for level in levels]
        push!(
            lines,
            "$name: $(length(values)) values, $(length(data.rows)-length(values)) missing, $(length(levels)) levels: "*join(
                counts,
                ", "
            )
        )
    end
    push!(lines,"","Correlations (pairwise complete observations):")
    rows = []
    for a in numeric
        fields = [a]
        for b in numeric
            pairs = [(row[a],row[b]) for row in data.rows if !isnothing(row[a]) && !isnothing(row[b])]
            mx,my = ordered_sum(x for (x,y) in pairs)/length(pairs),ordered_sum(y for (
                x,
                y
            ) in pairs)/length(pairs)
            cross = ordered_sum((x-mx)*(y-my) for (x,y) in pairs)
            sx = ordered_sum((x-mx)*(x-mx) for (x,y) in pairs)
            sy = ordered_sum((y-my)*(y-my) for (x,y) in pairs)
            push!(fields,four(cross/sqrt(sx*sy)))
        end
        push!(rows,fields)
    end
    append!(lines,table(vcat(["column"],numeric),rows))
    push!(lines,"")
    lines
end
function information_criteria(fit)
    n,r = fit.n,fit.rank
    likelihood = 0.5*(ordered_sum(log(w) for w in fit.weights)-n*(log(2pi)+1-log(n)+log(fit.rss)))
    (ll=likelihood,aic=-2likelihood+2*(r+1),bic=-2likelihood+log(n)*(r+1))
end
function residual_quantile(values,proportion)
    position = (length(values)-1)*proportion
    k = floor(Int,position)
    k+1<length(values) ? values[k+1]+(position-k)*(values[k+2]-values[k+1]) : values[k+1]
end
function model_statistics(fit,confidence)
    n,r = fit.n,fit.rank
    df = n-r
    sigma = sqrt(fit.rss/df)
    sw = ordered_sum(fit.weights)
    mean = ordered_sum(fit.weights[i]*fit.response[i] for i in 1:n)/sw
    tss = ordered_sum(fit.weights[i]*(fit.response[i]-mean)*(fit.response[i]-mean) for i in 1:n)
    r2 = 1-fit.rss/tss
    adjusted = 1-(1-r2)*(n-1)/df
    f = ((tss-fit.rss)/(r-1))/(fit.rss/df)
    criteria = information_criteria(fit)
    press = ordered_sum((fit.eps[i]/(1-fit.leverage[i]))*(fit.eps[i]/(1-fit.leverage[i])) for i in 1:n)
    residuals = sort(fit.eps)
    quantiles = [residual_quantile(residuals,p) for p in (0.0,0.25,0.5,0.75,1.0)]
    (df=df,sigma=sigma,weight_sum=sw,tss=tss,r2=r2,adjusted=adjusted,f=f,p=f_pvalue(f,r-1,df),
     ll=criteria.ll,aic=criteria.aic,bic=criteria.bic,press=press,predicted=1-press/tss,
     quantiles=quantiles,critical=t_quantile(confidence,df))
end
fit_subset(design,terms,tolerance) = fit_ols(
    subset_matrix(design,terms),
    design.response,
    design.weights,
    tolerance
)
function marginal_tests(design,fit,terms,tolerance)
    tests = NamedTuple[]
    for index in removable(design.model,terms)
        reduced = fit_subset(design,[t for t in terms if t!=index],tolerance)
        df = fit.rank-reduced.rank
        ss = reduced.rss-fit.rss
        f = df>0 ? (ss/df)/(fit.rss/(fit.n-fit.rank)) : nothing
        p = df>0 ? f_pvalue(f,df,fit.n-fit.rank) : nothing
        push!(tests,(index=index,name=design.model.terms[index].name,df=df,ss=ss,rss=reduced.rss,f=f,p=p))
    end
    tests
end
function coefficient_inference(fit,stats)
    results = []
    for (j,estimate) in enumerate(fit.beta)
        if isnothing(estimate)
            push!(
                results,
                (
                    estimate=nothing,
                    se=nothing,
                    t=nothing,
                    p=nothing,
                    lower=nothing,
                    upper=nothing,
                    robust_se=nothing,
                    robust_t=nothing,
                    robust_p=nothing
                )
            )
            continue
        end
        k = findfirst(==(j),fit.accepted)
        se = stats.sigma*sqrt(fit.variance[k])
        t = estimate/se
        robust = sqrt(ordered_sum(fit.eps[i]*fit.eps[i]/((1-fit.leverage[i])*(1-fit.leverage[i]))*fit.g[i,k]*fit.g[
            i,
            k
        ] for i in 1:fit.n))
        robust_t = estimate/robust
        push!(results,(estimate=estimate,se=se,t=t,p=t_pvalue(t,stats.df),lower=estimate-stats.critical*se,
                      upper=estimate+stats.critical*se,robust_se=robust,robust_t=robust_t,robust_p=t_pvalue(
                          robust_t,
                          stats.df
                      )))
    end
    results
end
function sequential_anova(design,fit)
    results = NamedTuple[]
    for (index,term) in enumerate(design.model.terms)
        effects = [k for (k,j) in enumerate(fit.accepted) if design.columns[j].term==index]
        df = length(effects)
        df==0 && continue
        ss = ordered_sum(fit.effects[k]*fit.effects[k] for k in effects)
        ms = ss/df
        f = ms/(fit.rss/(fit.n-fit.rank))
        push!(results,(name=term.name,df=df,ss=ss,ms=ms,f=f,p=f_pvalue(f,df,fit.n-fit.rank)))
    end
    results
end
function variance_inflation(design,fit,stats,params)
    results = []
    for column in fit.accepted[2:end]
        response = fit.matrix[:,column]
        others = [j for j in fit.accepted if j!=column]
        auxiliary = fit_ols(fit.matrix[:,others],response,fit.weights,params["RANK_TOL"][1])
        mean = ordered_sum(fit.weights[i]*response[i] for i in 1:fit.n)/stats.weight_sum
        tss = ordered_sum(fit.weights[i]*(response[i]-mean)*(response[i]-mean) for i in 1:fit.n)
        r2 = 1-auxiliary.rss/tss
        vif = 1/(1-r2)
        push!(results,(design.columns[column].name,vif,vif>params["VIF"][1]))
    end
    results
end
function reset_test(fit,tolerance)
    matrix = hcat(fit.matrix[:,fit.accepted],fit.fitted.*fit.fitted,fit.fitted.*fit.fitted.*fit.fitted)
    augmented = fit_ols(matrix,fit.response,fit.weights,tolerance)
    q,df = augmented.rank-fit.rank,fit.n-augmented.rank
    f = ((fit.rss-augmented.rss)/q)/(augmented.rss/df)
    (f,q,df,f_pvalue(f,q,df))
end
function diagnostic_decisions(design,fit,diagnostic,params)
    rows = diagnostic.rows
    dw = diagnostic.dw
    dw_label = dw<params["DURBIN_WATSON"][1] ? "positive autocorrelation" : dw>4-params["DURBIN_WATSON"][1] ? "negative autocorrelation" : "no autocorrelation"
    bp_label = diagnostic.bp[3]<params["BREUSCH_PAGAN"][1] ? "heteroscedastic" : "homoscedastic"
    jb_label = diagnostic.jb[2]<params["NORMALITY"][1] ? "non-normal" : "normal"
    outlier = argmax([abs(row.studentized) for row in rows])
    unadjusted = t_pvalue(rows[outlier].studentized,fit.n-fit.rank-1)
    largest_cooks = sort(collect(1:fit.n);by=i->(-rows[i].cooks,i))[1:min(3,fit.n)]
    largest_dfbetas = []
    for (k,column) in enumerate(fit.accepted)
        i = argmax([abs(row.dfbetas[k]) for row in rows])
        push!(largest_dfbetas,(design.columns[column].name,design.numbers[i],rows[i].dfbetas[k]))
    end
    counts = Dict(flag=>count(row->occursin(flag,row.flags),rows) for flag in ("H","O","C","F"))
    counts["any"] = count(row->row.flags!="-",rows)
    (dw_label=dw_label,bp_label=bp_label,jb_label=jb_label,outlier=outlier,unadjusted=unadjusted,
     bonferroni=min(
         1.0,
         fit.n*unadjusted
     ),largest_cooks=largest_cooks,largest_dfbetas=largest_dfbetas,counts=counts)
end
function prediction_report(number,design,fit,stats,prediction_data)
    lines = String[]
    predicted_count = actual_count = covered_count = 0
    squared_errors = 0.0
    for (i,row) in enumerate(prediction_data.rows)
        fields = [string(number),string(i)]
        if !predictable(design,row)
            push!(lines,join(vcat(fields,fill("NA",9)),","))
            continue
        end
        predicted_count += 1
        values = design_values(design,row)
        predicted = ordered_sum(values[j]*fit.beta[j] for j in fit.accepted)
        u = [ordered_sum(values[fit.accepted[m]]*fit.inverse[m,k] for m in 1:fit.rank) for k in 1:fit.rank]
        se = stats.sigma*sqrt(ordered_sum(value*value for value in u))
        cw = stats.critical*se
        pw = stats.critical*sqrt(stats.sigma*stats.sigma+se*se)
        lower,upper = predicted-pw,predicted+pw
        append!(fields,four.([predicted,se,predicted-cw,predicted+cw,lower,upper]))
        actual = get(row,design.model.response,nothing)
        if isnothing(actual)
            append!(fields,fill("NA",3))
        else
            actual_count += 1
            error = actual-predicted
            squared_errors += error*error
            covered = lower<=actual<=upper
            covered_count += covered
            append!(fields,[four(actual),four(error),covered ? "yes" : "no"])
        end
        push!(lines,join(fields,","))
    end
    rmse = actual_count>0 ? sqrt(squared_errors/actual_count) : nothing
    lines,(predicted_count,actual_count,rmse,covered_count)
end
function analyze_model(number,design,params,prediction_data)
    fit = fit_ols(design.matrix,design.response,design.weights,params["RANK_TOL"][1])
    stats = model_statistics(fit,params["CONFIDENCE"][1])
    diagnostic = calculate_diagnostics(fit,params)
    predictions,check = prediction_report(number,design,fit,stats,prediction_data)
    (number=number,design=design,fit=fit,stats=stats,coefficients=coefficient_inference(fit,stats),
     anova=sequential_anova(design,fit),marginal=marginal_tests(
         design,
         fit,
         collect(eachindex(design.model.terms)),
         params["RANK_TOL"][1]
     ),
     vif=variance_inflation(design,fit,stats,params),diagnostics=diagnostic,
     decisions=diagnostic_decisions(
         design,
         fit,
         diagnostic,
         params
     ),reset=reset_test(fit,params["RANK_TOL"][1]),predictions=predictions,check=check)
end
function diagnostic_summary(report)
    design,fit,d,decisions = report.design,report.fit,report.diagnostics,report.decisions
    bp,bp_df,bp_p = d.bp
    jb,jb_p,skewness,kurtosis = d.jb
    reset,q,df,reset_p = report.reset
    i = decisions.outlier
    counts = decisions.counts
    lines = ["Diagnostics:","Durbin-Watson: $(four(d.dw)) ($(decisions.dw_label))",
      "Breusch-Pagan: $(four(bp)) on $bp_df DF, p-value: $(probability(bp_p)) ($(decisions.bp_label))",
      "Jarque-Bera: $(four(jb)) on 2 DF, p-value: $(probability(jb_p)), skewness $(four(skewness)), kurtosis $(four(kurtosis)) ($(decisions.jb_label))",
      "RESET (powers 2 and 3): F $(four(reset)) on $q and $df DF, p-value: $(probability(reset_p))",
      "Outlier test: row $(design.numbers[i]), studentized $(four(d.rows[i].studentized)), unadjusted p-value: $(probability(decisions.unadjusted)), Bonferroni p-value: $(probability(decisions.bonferroni))",
      "Flagged rows: leverage $(counts["H"]), outlier $(counts["O"]), cooks $(counts["C"]), dffits $(counts["F"]), any $(counts["any"])","Largest Cook's distances:"]
    for i in decisions.largest_cooks
        row = d.rows[i]
        push!(
            lines,
            "row $(design.numbers[i]): cooks_d $(four(row.cooks)), leverage $(four(fit.leverage[i])), studentized $(four(row.studentized)), flags $(row.flags)"
        )
    end
    push!(lines,"Largest absolute DFBETAS:")
    append!(
        lines,
        table(
            ["column","row","DFBETAS"],
            [[name,string(row),four(value)] for (name,row,value) in decisions.largest_dfbetas]
        )
    )
    lines
end
function model_summary(report,total_rows,confidence)
    design,fit,stats = report.design,report.fit,report.stats
    names = [column.name for column in design.columns]
    coefficients = report.coefficients
    aliases = isempty(fit.aliases) ? "none" : join(names[fit.aliases],", ")
    q = stats.quantiles
    lines = ["Model $(report.number): $(design.model.original)","Terms: "*join([t.name for t in design.model.terms],", "),
      "Weights: $(isnothing(design.model.weight) ? "none" : design.model.weight)","Observations: $(fit.n) used, $(total_rows-fit.n) dropped",
      "Columns: $(fit.p), rank $(fit.rank), aliased: $aliases","",
      "Residuals: Min $(four(q[1])), 1Q $(four(q[2])), Median $(four(q[3])), 3Q $(four(q[4])), Max $(four(q[5]))","","Coefficients:"]
    rows = [[
        name,
        four(c.estimate),
        four(c.se),
        four(c.t),
        probability(c.p)
    ] for (name,c) in zip(names,coefficients)]
    append!(
        lines,
        table(
            ["term","Estimate","Std. Error","t value","Pr(>|t|)"],
            rows,
            [significance(c.p) for c in coefficients]
        )
    )
    append!(lines,["---","Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1","",
      "Residual standard error: $(four(stats.sigma)) on $(stats.df) degrees of freedom",
      "Multiple R-squared: $(four(stats.r2)), Adjusted R-squared: $(four(stats.adjusted))",
      "F-statistic: $(four(stats.f)) on $(fit.rank-1) and $(stats.df) DF, p-value: $(probability(stats.p))",
      "Log-likelihood: $(four(stats.ll)), AIC: $(four(stats.aic)), BIC: $(four(stats.bic))",
      "PRESS: $(four(stats.press)), Predicted R-squared: $(four(stats.predicted))","",
      "Confidence intervals (level $(four(confidence)), t $(four(stats.critical))):"])
    append!(
        lines,
        table(
            ["term","Lower","Upper"],
            [[name,four(c.lower),four(c.upper)] for (name,c) in zip(names,coefficients)]
        )
    )
    push!(lines,"","Robust standard errors (HC3):")
    append!(
        lines,
        table(
            ["term","Std. Error","t value","Pr(>|t|)"],
            [[
                name,
                four(c.robust_se),
                four(c.robust_t),
                probability(c.robust_p)
            ] for (name,c) in zip(names,coefficients)],
            [significance(c.robust_p) for c in coefficients]
        )
    )
    push!(lines,"","Analysis of variance (sequential):")
    rows = [[t.name,string(t.df),four(t.ss),four(t.ms),four(t.f),probability(t.p)] for t in report.anova]
    push!(rows,["Residuals",string(stats.df),four(fit.rss),four(fit.rss/stats.df)])
    append!(
        lines,
        table(
            ["term","Df","Sum Sq","Mean Sq","F value","Pr(>F)"],
            rows,
            vcat([significance(t.p) for t in report.anova],[""])
        )
    )
    push!(lines,"","Marginal F tests (drop one term):")
    append!(
        lines,
        table(
            ["term","Df","Sum Sq","RSS","F value","Pr(>F)"],
            [[
                t.name,
                string(t.df),
                four(t.ss),
                four(t.rss),
                four(t.f),
                probability(t.p)
            ] for t in report.marginal],
            [significance(t.p) for t in report.marginal]
        )
    )
    push!(lines,"","Variance inflation factors:")
    append!(
        lines,
        table(
            ["column","VIF"],
            [[name,four(value)] for (name,value,high) in report.vif],
            [high ? "high" : "" for (name,value,high) in report.vif]
        )
    )
    push!(lines,"")
    append!(lines,diagnostic_summary(report))
    lines
end
function summary_report(data,reports,params)
    lines = data_summary(data)
    for (i,report) in enumerate(reports)
        i>1 && push!(lines,"")
        append!(lines,model_summary(report,length(data.rows),params["CONFIDENCE"][1]))
    end
    push!(lines,"","Model comparison:")
    rows = [[
        string(r.number),
        string(r.fit.n),
        string(r.fit.rank),
        four(r.stats.sigma),
        four(r.stats.r2),
        four(r.stats.adjusted),
        four(r.stats.predicted),
        four(r.stats.aic),
        four(r.stats.bic)
    ] for r in reports]
    append!(
        lines,
        table(["model","n","rank","sigma","R-squared","Adj. R-squared","Pred. R-squared","AIC","BIC"],rows)
    )
    push!(lines,"","Prediction check:")
    for report in reports
        predicted,actual,rmse,covered = report.check
        push!(
            lines,
            "model $(report.number): $predicted predicted, $actual with actual values, RMSE $(four(rmse)), inside prediction interval $covered"
        )
    end
    lines
end
function diagnostics_csv(reports)
    lines = ["model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"]
    for r in reports,(i,row) in enumerate(r.diagnostics.rows)
        fields = vcat(
            [string(r.number),string(r.design.numbers[i])],
            four.([r.fit.fitted[i],r.fit.residual[i],r.fit.leverage[i],row.studentized,row.cooks,row.dffits]),
            [row.flags]
        )
        push!(lines,join(fields,","))
    end
    lines
end
function selection_report(report,params)
    design,model = report.design,report.design.model
    tolerance,alpha = params["RANK_TOL"][1],params["ALPHA_REMOVE"][1]
    terms = collect(eachindex(model.terms))
    fit = report.fit
    lines = ["Backward elimination (model 1, alpha $(four(alpha)), rows $(fit.n))"]
    step = 1
    while true
        criteria = information_criteria(fit)
        df = fit.n-fit.rank
        push!(
            lines,
            "Step $step: $(format_formula(model,terms)) (RSS $(four(fit.rss)), df $df, AIC $(four(criteria.aic)))"
        )
        if isempty(terms)
            push!(lines,"  stop: no removable terms")
            break
        end
        tests = marginal_tests(design,fit,terms,tolerance)
        for t in tests
            push!(lines,"  - $(t.name): F $(four(t.f)) on $(t.df) and $df DF, p-value $(probability(t.p))")
        end
        largest = tests[argmax([t.p for t in tests])]
        if largest.p<=alpha
            push!(lines,"  stop: largest p-value $(probability(largest.p)) is not above $(four(alpha))")
            break
        end
        push!(lines,"  remove $(largest.name)")
        filter!(!=(largest.index),terms)
        fit = fit_subset(design,terms,tolerance)
        step += 1
    end
    push!(
        lines,
        "Final model: $(format_formula(model,terms))",
        "",
        "Forward selection by AIC (model 1, rows $(length(design.rows)))"
    )
    terms = Int[]
    step = 1
    while true
        fit = fit_subset(design,terms,tolerance)
        aic = information_criteria(fit).aic
        push!(lines,"Step $step: $(format_formula(model,terms)) (AIC $(four(aic)))")
        options = candidates(model,terms)
        if isempty(options)
            push!(lines,"  stop: no candidate terms remain")
            break
        end
        choices = []
        for index in options
            subset = sort(vcat(terms,index))
            candidate_aic = information_criteria(fit_subset(design,subset,tolerance)).aic
            push!(choices,(index,candidate_aic,subset))
            push!(lines,"  + $(model.terms[index].name): AIC $(four(candidate_aic))")
        end
        index,candidate_aic,subset = choices[argmin([c[2] for c in choices])]
        if candidate_aic>=aic
            push!(lines,"  stop: no candidate lowers the AIC")
            break
        end
        push!(lines,"  add $(model.terms[index].name)")
        terms = subset
        step += 1
    end
    push!(lines,"Final model: $(format_formula(model,terms))","")
    subsets = []
    for mask in 0:(1<<length(model.terms))-1
        subset = [i for i in eachindex(model.terms) if (mask>>(i-1))&1==1]
        hierarchical(model,subset) || continue
        fit = fit_subset(design,subset,tolerance)
        criteria = information_criteria(fit)
        push!(subsets,(criteria.bic,mask,criteria.aic,fit.rank,subset))
    end
    sort!(subsets;by=s->(s[1],s[2]))
    push!(lines,"Best subsets by BIC (model 1, rows $(length(design.rows)), subsets $(length(subsets)))")
    for (position,(bic,mask,aic,rank,subset)) in enumerate(subsets[1:min(
        Int(params["BEST_SUBSETS"][1]),
        length(subsets)
    )])
        push!(
            lines,
            "$position. BIC $(four(bic)), AIC $(four(aic)), rank $rank: $(format_formula(model,subset))"
        )
    end
    lines
end
function plot_grid(horizontal,vertical,lo,hi,width,height,limit)
    grid = zeros(Int,height,width)
    for (x,y) in zip(horizontal,vertical)
        column = min(floor(Int,(x-lo)/(hi-lo)*width),width-1)
        row = clamp(floor(Int,(limit-y)/(2limit)*height),0,height-1)
        grid[row+1,column+1] += 1
    end
    grid
end
function plot_frame(grid)
    height,width = size(grid)
    border = "+"*repeat("-",width)*"+"
    lines = [border]
    for i in 1:height
        empty = i-1==height÷2 ? "-" : "."
        push!(lines,"|"*join(c>=10 ? "*" : c>0 ? string(c) : empty for c in grid[i,:])*"|")
    end
    push!(lines,border)
    lines
end
function residual_plot(report,params)
    width,height = Int.(params["PLOT"][1:2])
    limit = params["PLOT"][3]
    fit = report.fit
    studentized = [r.studentized for r in report.diagnostics.rows]
    lo,hi = extrema(fit.fitted)
    grid = plot_grid(fit.fitted,studentized,lo,hi,width,height,limit)
    lines = [
        "Model $(report.number): studentized residuals vs fitted values",
        "fitted $(four(lo)) to $(four(hi)), studentized $(four(-limit)) to $(four(limit))"
    ]
    append!(lines,plot_frame(grid))
    push!(
        lines,
        "points: $(fit.n), above +2: $(count(>(2),studentized)), below -2: $(count(<(-2),studentized)), outside range: $(count(t->abs(t)>limit,studentized))",
        "Histogram of studentized residuals:"
    )
    counts = vec(sum(grid;dims=2))
    maximum_count = maximum(counts)
    for (i,n) in enumerate(counts)
        lower,upper = limit-2limit*i/height,limit-2limit*(i-1)/height
        bar = fld(n*40+maximum_count-1,maximum_count)
        push!(lines,"$(four(lower)) to $(four(upper)): $n"*(bar>0 ? " "*repeat("#",bar) : ""))
    end
    hi = maximum(fit.leverage)
    push!(
        lines,
        "Model $(report.number): studentized residuals vs leverage",
        "leverage 0.0000 to $(four(hi)), studentized $(four(-limit)) to $(four(limit))"
    )
    append!(lines,plot_frame(plot_grid(fit.leverage,studentized,0.0,hi,width,height,limit)))
    lines
end
function main()
    data = read_table("input/data.csv")
    prediction_data = read_table("input/predict.csv",data.kinds)
    params = read_params()
    models = parse_model.(readlines("input/model.txt"))
    reports = [analyze_model(
        i,
        build_design(model,data),
        params,
        prediction_data
    ) for (i,model) in enumerate(models)]
    contents = Dict("summary.txt"=>summary_report(data,reports,params),"diagnostics.csv"=>diagnostics_csv(reports),
      "selection.txt"=>selection_report(reports[1],params),"predictions.csv"=>vcat(
          ["model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"],
          [line for r in reports for line in r.predictions]
      ))
    plots = String[]
    for (i,r) in enumerate(reports)
        i>1 && push!(plots,"")
        append!(plots,residual_plot(r,params))
    end
    contents["residual_plot.txt"] = plots
    for (name,lines) in contents
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
