using Printf
include("dataset.jl")
include("numerics.jl")
include("estimators.jl")
include("group_tests.jl")
include("cox.jl")
include("plot.jl")
function number(value,digits=4)
    isnothing(value) && return "NA"
    text = Printf.format(Printf.Format("%.$(digits)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
day(value) = isnothing(value) ? "NA" : string(value)
function percentile_time(rows,threshold,column=:survival)
    for row in rows
        value = row.survival==0 ? 0.0 : getproperty(row,column)
        !isnothing(value) && value<=threshold && return row.time
    end
    nothing
end
function restricted_mean(rows,tau)
    selected = [r for r in rows if r.time<=tau]
    times = vcat([0],[r.time for r in selected],[tau])
    survival = vcat([1.0],[r.survival for r in selected])
    rectangles = [s*(times[i+1]-times[i]) for (i,s) in enumerate(survival)]
    tails = zeros(length(rectangles))
    tails[end] = rectangles[end]
    for i in length(tails)-1:-1:1
        tails[i] = rectangles[i]+tails[i+1]
    end
    variance = 0.0
    for (i,row) in enumerate(selected)
        variance += tails[i+1]*tails[i+1]*(row.events/(row.risk*(row.risk-row.events)))
    end
    estimate,error = tails[1],sqrt(variance)
    (estimate,error,estimate-Z95*error,estimate+Z95*error)
end
function collection_summary(subjects,params)
    rows = kaplan_meier(subjects)
    life = life_table(subjects,params["LIFE_TABLE"]...)
    events = sum(s.event for s in subjects)
    person_days = sum(s.time for s in subjects)
    rate = 1000events/person_days
    eta = Z95/sqrt(events)
    reverse = [(;s...,event=1-s.event) for s in subjects]
    followup = percentile_time(kaplan_meier(reverse),0.5)
    life_median = nothing
    previous = 1.0
    for row in life
        if row.survival<=0.5
            life_median = row.start+params["LIFE_TABLE"][1]*(previous-0.5)/(previous-row.survival)
            break
        end
        previous = row.survival
    end
    percentiles = [(
        p,
        percentile_time(rows,q),
        percentile_time(rows,q,:lower),
        percentile_time(rows,q,:upper)
    ) for (p,q) in ((25,0.75),(50,0.5),(75,0.25))]
    (rows=rows,life=life,subjects=length(subjects),events=events,censored=length(subjects)-events,
     maximum=maximum(s.time for s in subjects),person_days=person_days,rate=rate,
     lower=exp(log(rate)-eta),upper=exp(log(rate)+eta),followup=followup,life_median=life_median,
     percentiles=percentiles,rmst=restricted_mean(rows,params["TAU"][1]))
end
function km_table_lines(name,subjects,summary,params)
    lines = ["group $name subjects $(summary.subjects) events $(summary.events) censored $(summary.censored) max_time $(summary.maximum)",
      "person_days $(summary.person_days) rate $(number(summary.rate)) lower $(number(summary.lower)) upper $(number(summary.upper))",
      "followup_median $(day(summary.followup))","life_table_median $(number(summary.life_median))"]
    for (p,time,lower,upper) in summary.percentiles
        push!(lines,"percentile $p time $(day(time)) lower $(day(lower)) upper $(day(upper))")
    end
    estimate,error,lower,upper = summary.rmst
    push!(
        lines,
        "rmst tau $(params["TAU"][1]) estimate $(number(estimate)) se $(number(error)) lower $(number(lower)) upper $(number(upper))"
    )
    for time in params["REPORT_TIMES"]
        row = row_at(summary.rows,time)
        risk = count(s->s.time>=time,subjects)
        events = count(s->s.time<=time && s.event==1,subjects)
        push!(
            lines,
            "at $time at_risk $risk events $events survival $(number(row.survival)) std_err $(number(row.se)) lower $(number(row.lower)) upper $(number(row.upper)) cum_hazard $(number(row.hazard)) hazard_se $(number(row.hazard_se))"
        )
    end
    push!(
        lines,
        join(lpad(c,9) for c in (
            "time",
            "at_risk",
            "events",
            "censored",
            "survival",
            "std_err",
            "lower",
            "upper",
            "cum_haz",
            "haz_se"
        ))
    )
    for row in summary.rows
        fields = vcat(string.([row.time,row.risk,row.events,row.censored]),
          number.([row.survival,row.se,row.lower,row.upper,row.hazard,row.hazard_se]))
        push!(lines,join(lpad(value,9) for value in fields))
    end
    lines
end
function life_table_lines(names,summaries)
    lines = ["group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"]
    for name in names,row in summaries[name].life
        push!(lines,join((name,"$(row.start)-$(row.stop)",row.risk,row.events,row.withdrawn,
          number(row.exposed,1),number(row.q),number(row.survival),number(row.se),number(row.hazard)),","))
    end
    lines
end
function baseline_lines(subjects,groups,collections,names)
    lines = ["baseline"]
    for name in names
        rows = collections[name]
        n = length(rows)
        mean_age = sum(s.age for s in rows)/n
        error = sqrt(total((s.age-mean_age)*(s.age-mean_age) for s in rows)/(n-1))
        ages = sort([s.age for s in rows])
        median = (ages[(n-1)÷2+1]+ages[n÷2+1])/2
        males = count(s->s.sex=="M",rows)
        stages = [count(s->s.stage==stage,rows) for stage in 1:4]
        push!(
            lines,
            "  group $name subjects $n age_mean $(number(mean_age)) age_sd $(number(error)) age_median $(number(median,1)) male $males stage $(join(stages," "))"
        )
    end
    ranked = sort(subjects;by=s->s.age)
    ranks = Dict{Int,Float64}()
    ties,position = 0,1
    while position<=length(ranked)
        stop = position
        while stop<=length(ranked) && ranked[stop].age==ranked[position].age
            stop += 1
        end
        rank = (position+stop-1)/2
        for i in position:stop-1
            ranks[ranked[i].id] = rank
        end
        t = stop-position
        ties += t*t*t-t
        position = stop
    end
    weighted = total(begin
        rank_sum = total(ranks[s.id] for s in collections[group])
        rank_sum*rank_sum/length(collections[group])
    end for group in groups)
    n,k = length(subjects),length(groups)
    raw = 12weighted/(n*(n+1))-3*(n+1)
    statistic = raw/(1-ties/(n*n*n-n))
    push!(
        lines,
        "  age kruskal_wallis chisq $(number(statistic)) df $(k-1) p $(number(chi_square_p(statistic,k-1)))"
    )
    for variable in (:sex,:stage)
        levels = sort(unique(getproperty(s,variable) for s in subjects))
        counts = [count(s->getproperty(s,variable)==level,subjects) for level in levels]
        statistic = 0.0
        for group in groups,(level,column_count) in zip(levels,counts)
            members = collections[group]
            observed = count(s->getproperty(s,variable)==level,members)
            expected = length(members)*column_count/n
            statistic += (observed-expected)*(observed-expected)/expected
        end
        df = (k-1)*(length(levels)-1)
        push!(lines,"  $variable chisq $(number(statistic)) df $df p $(number(chi_square_p(statistic,df)))")
    end
    lines
end
function group_lines(test)
    ["  group $group events $(test.events[h]) observed $(number(test.observed[h])) expected $(number(test.expected[h])) o_minus_e $(number(test.observed[h]-test.expected[h])) variance $(number(test.covariance[h,h]))" for (
        h,
        group
    ) in enumerate(test.groups)]
end
test_fields(test) = "chisq $(number(test.statistic)) df $(test.degrees) p $(number(test.p))"
function two_group(subjects,groups,population)
    test = weighted_test(subjects,groups,"logrank",population)
    ratio = (test.observed[2]/test.expected[2])/(test.observed[1]/test.expected[1])
    variance = 1/test.expected[1]+1/test.expected[2]
    logarithm = log(ratio)
    (;test...,ratio=ratio,variance=variance,log_ratio=logarithm,
     lower=exp(logarithm-Z95*sqrt(variance)),upper=exp(logarithm+Z95*sqrt(variance)))
end
function difference_fields(difference,error)
    statistic = difference/error
    "difference $(number(difference)) se $(number(error)) lower $(number(difference-Z95*error)) upper $(number(difference+Z95*error)) z $(number(statistic)) p $(number(chi_square_p(statistic*statistic,1)))"
end
function comparison_sections(subjects,params,collections,summaries,names)
    groups = params["GROUPS"]
    n,k = length(subjects),length(groups)
    sections = [baseline_lines(subjects,groups,collections,names)]
    lines = String[]
    tests = [weighted_test(subjects,groups,weight,n) for weight in WEIGHTS]
    for (weight,test) in zip(WEIGHTS,tests)
        push!(lines,"test $weight $(test_fields(test))")
        append!(lines,group_lines(test))
    end
    test = tests[1]
    trend = total(g*(test.observed[g]-test.expected[g]) for g in 1:k)
    variance = total(total((g*h)*test.covariance[g,h] for h in 1:k) for g in 1:k)
    statistic = trend*trend/variance
    push!(lines,"test logrank_trend chisq $(number(statistic)) df 1 p $(number(chi_square_p(statistic,1)))")
    push!(sections,lines)
    variable = Symbol(params["STRATA"][1])
    levels = sort(unique(getproperty(s,variable) for s in subjects))
    strata = [[s for s in subjects if getproperty(s,variable)==level] for level in levels]
    lines = String[]
    for weight in WEIGHTS
        tests = [weighted_test(rows,groups,weight,n) for rows in strata]
        combined = combine_strata(tests,groups)
        push!(lines,"stratified $weight by $variable $(test_fields(combined))")
        for (level,rows,test) in zip(levels,strata,tests)
            push!(
                lines,
                "  stratum $level subjects $(length(rows)) events $(sum(s.event for s in rows)) chisq $(number(test.statistic)) p $(number(test.p))"
            )
        end
        append!(lines,group_lines(combined))
    end
    push!(sections,lines)
    landmark = params["LANDMARK"][1]
    selected = [s for s in subjects if s.time>landmark]
    test = weighted_test(selected,groups,"logrank",n)
    push!(
        sections,
        vcat(["landmark $landmark subjects $(length(selected)) $(test_fields(test))"],group_lines(test))
    )
    pairs = [(groups[a],groups[b]) for a in 1:k-1 for b in a+1:k]
    tests = [two_group([s for s in subjects if s.group in pair],collect(pair),n) for pair in pairs]
    adjusted = zeros(length(pairs))
    order = sort(collect(eachindex(pairs));by=i->(tests[i].p,i))
    previous = 0.0
    for (rank,i) in enumerate(order)
        previous = max(previous,min(1.0,(length(pairs)-rank+1)*tests[i].p))
        adjusted[i] = previous
    end
    lines = ["pairwise logrank adjust holm"]
    for ((a,b),test,correction) in zip(pairs,tests,adjusted)
        push!(
            lines,
            "  $a $b chisq $(number(test.statistic)) p $(number(test.p)) p_holm $(number(correction)) hr $(number(test.ratio)) lower $(number(test.lower)) upper $(number(test.upper))"
        )
    end
    push!(sections,lines)
    lines = ["subgroups reference $(groups[1])"]
    for name in params["SUBGROUPS"]
        variable = Symbol(name)
        levels = sort(unique(getproperty(s,variable) for s in subjects))
        for group in groups[2:end]
            tests = []
            for level in levels
                selected = [s for s in subjects if getproperty(s,variable)==level && s.group in (
                    groups[1],
                    group
                )]
                test = two_group(selected,[groups[1],group],n)
                push!(tests,test)
                push!(
                    lines,
                    "  $name $level $group subjects $(length(selected)) events $(sum(s.event for s in selected)) hr $(number(test.ratio)) lower $(number(test.lower)) upper $(number(test.upper)) p $(number(test.p))"
                )
            end
            weights = [1/test.variance for test in tests]
            mean = total(weight*test.log_ratio for (weight,test) in zip(weights,tests))/total(weights)
            statistic = total(weight*(test.log_ratio-mean)*(test.log_ratio-mean) for (weight,test) in zip(
                weights,
                tests
            ))
            df = length(levels)-1
            push!(
                lines,
                "  $name $group heterogeneity chisq $(number(statistic)) df $df p $(number(chi_square_p(statistic,df)))"
            )
        end
    end
    push!(sections,lines)
    control = summaries[groups[1]]
    lines = ["rmst_difference tau $(params["TAU"][1]) reference $(groups[1])"]
    for group in groups[2:end]
        summary = summaries[group]
        error = sqrt(summary.rmst[2]^2+control.rmst[2]^2)
        push!(lines,"  $group "*difference_fields(summary.rmst[1]-control.rmst[1],error))
    end
    push!(sections,lines)
    lines = ["rate_ratio reference $(groups[1])"]
    for group in groups[2:end]
        summary = summaries[group]
        ratio = summary.rate/control.rate
        error = sqrt(1/summary.events+1/control.events)
        logarithm = log(ratio)
        statistic = logarithm/error
        push!(
            lines,
            "  $group ratio $(number(ratio)) lower $(number(exp(logarithm-Z95*error))) upper $(number(exp(logarithm+Z95*error))) z $(number(statistic)) p $(number(chi_square_p(statistic*statistic,1)))"
        )
    end
    push!(sections,lines)
    lines = ["survival_difference reference $(groups[1])"]
    for time in params["REPORT_TIMES"]
        baseline = row_at(control.rows,time)
        for group in groups[2:end]
            row = row_at(summaries[group].rows,time)
            error = sqrt(row.se*row.se+baseline.se*baseline.se)
            push!(lines,"  at $time $group "*difference_fields(row.survival-baseline.survival,error))
        end
    end
    push!(sections,lines)
    sections
end
function covariate_vectors(subjects,names)
    [[name=="age" ? s.age : name=="stage" ? s.stage : name=="male" ? Int(s.sex=="M") : Int(s.group==name) for name in names] for s in subjects]
end
function coefficient_fields(coefficient,error)
    statistic = coefficient/error
    "coef $(number(coefficient)) se $(number(error)) z $(number(statistic)) p $(number(chi_square_p(statistic*statistic,1))) hr $(number(exp(coefficient))) lower $(number(exp(coefficient-Z95*error))) upper $(number(exp(coefficient+Z95*error)))"
end
function hazard_at(rows,time)
    for (u,hazard) in Iterators.reverse(rows)
        u<=time && return hazard
    end
    0.0
end
function cox_lines(subjects,params)
    names = params["COX"]
    vectors = covariate_vectors(subjects,names)
    model = fit_cox(subjects,vectors)
    beta,final,null = model.beta,model.final,model.null
    covariance = inverse_matrix(final.information)
    n,p = length(subjects),length(names)
    events = sum(s.event for s in subjects)
    lines = ["cox covariates $(join(names," ")) subjects $n events $events event_times $(length(final.event_sums))"]
    for (iteration,likelihood,coefficients) in model.iterations
        push!(lines,"iter $iteration loglik $(number(likelihood)) beta "*join(number.(coefficients)," "))
    end
    push!(lines,"final loglik $(number(final.loglik)) null_loglik $(number(null.loglik))")
    for c in 1:p
        push!(lines,"term $(names[c]) "*coefficient_fields(beta[c],sqrt(covariance[c,c])))
    end
    group_indices = [i for i in 1:p if !(names[i] in ("age","male","stage"))]
    for i in 1:length(group_indices)-1,j in i+1:length(group_indices)
        a,b = group_indices[i],group_indices[j]
        error = sqrt(covariance[b,b]+covariance[a,a]-2covariance[a,b])
        push!(lines,"contrast $(names[b]) vs $(names[a]) "*coefficient_fields(beta[b]-beta[a],error))
    end
    likelihood_ratio = 2*(final.loglik-null.loglik)
    wald = total(beta[c]*total(final.information[c,d]*beta[d] for d in 1:p) for c in 1:p)
    solution = solve_system(null.information,null.score)
    score = total(null.score[c]*solution[c] for c in 1:p)
    for (label,statistic) in (("likelihood_ratio",likelihood_ratio),("wald",wald),("score",score))
        push!(lines,"$label chisq $(number(statistic)) df $p p $(number(chi_square_p(statistic,p)))")
    end
    for c in 1:p
        likelihood = p==1 ? null.loglik : fit_cox(
            subjects,
            [[x[d] for d in 1:p if d!=c] for x in vectors]
        ).final.loglik
        statistic = 2*(final.loglik-likelihood)
        push!(
            lines,
            "drop $(names[c]) loglik $(number(likelihood)) chisq $(number(statistic)) df 1 p $(number(chi_square_p(statistic,1)))"
        )
    end
    comparable = concordant = tied = 0
    for (i,a) in enumerate(subjects)
        a.event==1 || continue
        for (j,b) in enumerate(subjects)
            i==j && continue
            (a.time<b.time || a.time==b.time && b.event==0) || continue
            comparable += 1
            if vectors[i]==vectors[j]
                tied += 1
            elseif final.predictors[i]>final.predictors[j]
                concordant += 1
            end
        end
    end
    push!(
        lines,
        "concordance $(number((2concordant+tied)/(2comparable))) comparable $comparable concordant $concordant tied $tied"
    )
    event_indices = sort([i for i in 1:n if subjects[i].event==1];by=i->(subjects[i].time,subjects[i].id))
    count_events = length(event_indices)
    mean_time = sum(subjects[i].time for i in event_indices)/count_events
    for c in 1:p
        residuals = [vectors[i][c]-final.event_sums[subjects[i].time].s1[c]/final.event_sums[subjects[i].time].s0 for i in event_indices]
        mean_residual = total(residuals)/count_events
        sxy = sxx = syy = 0.0
        for (i,residual) in zip(event_indices,residuals)
            x,y = residual-mean_residual,subjects[i].time-mean_time
            sxy += x*y
            sxx += x*x
            syy += y*y
        end
        rho = sxy/sqrt(sxx*syy)
        statistic = 0.5*log((1+rho)/(1-rho))*sqrt(count_events-3)
        push!(
            lines,
            "ph_check $(names[c]) rho $(number(rho)) z $(number(statistic)) p $(number(chi_square_p(statistic*statistic,1)))"
        )
    end
    hazard = Tuple{Int,Float64}[]
    cumulative = 0.0
    for time in sort(collect(keys(final.event_sums)))
        sums = final.event_sums[time]
        cumulative += sums.events/sums.s0
        push!(hazard,(time,cumulative))
    end
    residuals = []
    for (i,s) in enumerate(subjects)
        martingale = s.event-hazard_at(hazard,s.time)*exp(final.predictors[i])
        deviance = s.event==1 ? sqrt(-2*(martingale+log(1-martingale))) : sqrt(-2martingale)
        martingale>0 || (deviance=-deviance)
        push!(residuals,(s,martingale,deviance))
    end
    sort!(residuals;by=r->(-abs(r[3]),r[1].id))
    r = params["RESIDUALS"][1]
    push!(lines,"residuals top $r")
    for (s,martingale,deviance) in residuals[1:r]
        push!(
            lines,
            "  id $(s.id) group $(s.group) time $(s.time) event $(s.event) martingale $(number(martingale)) deviance $(number(deviance))"
        )
    end
    means = Dict(names[c]=>sum(x[c] for x in vectors)/n for c in 1:p if names[c] in ("age","male","stage"))
    fields = ["$name $(number(means[name]))" for name in names if haskey(means,name)]
    push!(lines,"adjusted_survival mean "*(isempty(fields) ? "none" : join(fields," ")))
    groups = params["GROUPS"]
    risks = Dict(group=>exp(total(beta[c]*(haskey(
        means,
        names[c]
    ) ? means[names[c]] : Int(names[c]==group)) for c in 1:p)) for group in groups)
    for time in params["REPORT_TIMES"]
        cumulative = hazard_at(hazard,time)
        push!(
            lines,
            "  at $time "*join(["$group $(number(exp(-cumulative*risks[group])))" for group in groups]," ")
        )
    end
    medians = String[]
    for group in groups
        index = findfirst(row->exp(-row[2]*risks[group])<=0.5,hazard)
        push!(medians,"$group $(isnothing(index) ? "NA" : string(hazard[index][1]))")
    end
    push!(lines,"  median "*join(medians," "))
    lines
end
function plot_lines(params,collections,summaries)
    groups = params["GROUPS"]
    width,height,time_limit,divisions = params["PLOT"]
    estimates = Dict(group=>summaries[group].rows for group in groups)
    legend = join(["$(Char(Int('A')+i-1)) $group" for (i,group) in enumerate(groups)]," ")
    lines = ["km_plot width $width height $height time $time_limit","legend $legend"]
    append!(lines,curve_lines(groups,collections,estimates,width,height,time_limit))
    push!(lines,"time 0 to $time_limit days, $(time_limit÷width) days per column")
    times = [i*(time_limit÷divisions) for i in 0:divisions]
    push!(lines,"at_risk "*join(times," "))
    for group in groups
        counts = [count(s->s.time>=time,collections[group]) for time in times]
        push!(lines,group*" "*join(counts," "))
    end
    lines
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
    subjects,params = read_dataset()
    groups = params["GROUPS"]
    names = vcat(groups,["all"])
    collections = Dict(group=>[s for s in subjects if group=="all" || s.group==group] for group in names)
    summaries = Dict(name=>collection_summary(collections[name],params) for name in names)
    mkpath("output")
    write_lines(
        "km_tables.txt",
        join_sections([km_table_lines(name,collections[name],summaries[name],params) for name in names])
    )
    write_lines("life_table.csv",life_table_lines(names,summaries))
    write_lines("tests.txt",join_sections(comparison_sections(subjects,params,collections,summaries,names)))
    write_lines("cox.txt",cox_lines(subjects,params))
    write_lines("km_plot.txt",plot_lines(params,collections,summaries))
end
main()
