include("data_io.jl")
include("models.jl")
include("integrator.jl")
include("fitting.jl")
include("report.jl")

ordered_sum(values) = foldl(+,values;init=0.0)
function squared_errors(series,coefficient,observations)
    total = 0.0
    for (value,observed) in zip(series,observations)
        difference = coefficient*value-observed
        total += difference*difference
    end
    total
end
peak(series) = argmax(series)
line!(lines,words...) = push!(lines,join(string.(words)," "))
function multiplier_sequence(interventions,days)
    result,index = Float64[],1
    for day in 1:days
        while index<length(interventions) && interventions[index+1][1]<=day
            index += 1
        end
        push!(result,interventions[index][2])
    end
    result
end
function final_size(reproduction)
    reproduction<=1 && return 0.0
    lo,hi = 1-1/reproduction,1.0
    for _ in 1:20
        middle = (lo+hi)/2
        if 1-middle-exp(-reproduction*middle)>0
            lo = middle
        else
            hi = middle
        end
    end
    (lo+hi)/2
end
function power_method(matrix)
    n = size(matrix,1)
    vector = fill(1.0/n,n)
    eigenvalue = 0.0
    for _ in 1:200
        product = [ordered_sum(matrix[g,h]*vector[h] for h in 1:n) for g in 1:n]
        eigenvalue = ordered_sum(product)
        vector = product./eigenvalue
    end
    eigenvalue,vector
end
Base.@kwdef mutable struct EpidemicStudy
    cases::Vector{Int}
    deaths::Vector{Int}
    groups::Vector{NamedTuple}
    contacts::Matrix{Float64}
    interventions::Vector{Tuple{Int,Float64}}
    params::Dict{String,Any}
    days::Int
    populations::Vector{Int}
    fatalities::Vector{Float64}
    population::Int
    case_total::Int
    death_total::Int
    fatality::Float64
    sigma::Float64
    gamma0::Float64
    initial::Vector{Float64}
    sir_initial::Vector{Float64}
    age_initial::Vector{Float64}
    multipliers::Vector{Float64}
    week_ranges::Vector{Tuple{Int,Int}}
    cache::Dict{Tuple{Float64,Float64},Vector{Float64}} = Dict()
    fit_lines::Vector{String} = String[]
    reproduction_lines::Vector{String} = String[]
    age_lines::Vector{String} = String[]
    beta::Float64 = 0.0
    gamma::Float64 = 0.0
    rho::Float64 = 0.0
    r0::Float64 = 0.0
    delta_beta::Float64 = 0.0
    delta_rho::Float64 = 0.0
    sse_nm::Float64 = 0.0
    states::Vector{Vector{Float64}} = Vector{Float64}[]
    incidence::Vector{Float64} = Float64[]
    reported::Vector{Float64} = Float64[]
    residuals::Vector{Float64} = Float64[]
    model_deaths::Vector{Float64} = Float64[]
    rt::Vector{Float64} = Float64[]
    averages::Vector{Float64} = Float64[]
    cumulative_cases::Vector{Int} = Int[]
    cumulative_reported::Vector{Float64} = Float64[]
    reported_total::Float64 = 0.0
    standard_errors::Vector{Float64} = Float64[]
    normalized_contacts::Matrix{Float64} = zeros(0,0)
    age_states::Vector{Vector{Float64}} = Vector{Float64}[]
    age_incidence::Vector{Float64} = Float64[]
end
function prepare_study(data)
    populations = [group.population for group in data.groups]
    population = sum(populations)
    exposed,infectious = data.params["initial"]
    age_initial = Float64[]
    for n in populations
        e,i = exposed*n/population,infectious*n/population
        append!(age_initial,[n-e-i,e,i,0,0,0])
    end
    EpidemicStudy(;data...,days=length(data.cases),populations=populations,
        fatalities=[group.fatality for group in data.groups],population=population,
        case_total=sum(data.cases),death_total=sum(data.deaths),
        fatality=ordered_sum(group.population*group.fatality for group in data.groups)/population,
        sigma=data.params["sigma"],gamma0=data.params["gamma"],
        initial=[population-exposed-infectious,exposed,infectious,0,0,0],
        sir_initial=[population-exposed-infectious,exposed+infectious,0,0],age_initial=age_initial,
        multipliers=multiplier_sequence(data.interventions,length(data.cases)),
        week_ranges=[(first,min(first+6,length(data.cases))) for first in 1:7:length(data.cases)])
end
rmse(s,error,n=s.days) = sqrt(error/n)
function seird_states(s,beta,gamma; multipliers=s.multipliers,initial=s.initial,sigma=s.sigma)
    simulate(seird(s.population,sigma,s.fatality,beta,gamma),initial,multipliers,[6])
end
function incidence_for(s,beta,gamma)
    get!(s.cache,(beta,gamma)) do
        [state[6] for state in seird_states(s,beta,gamma)]
    end
end
fit_error(s,beta,gamma,rho) = squared_errors(incidence_for(s,beta,gamma),rho,s.cases)
function golden_records!(s,round_number,name,search)
    for (index,(a,b,c,d,fc,fd)) in enumerate(search.records)
        line!(
            s.fit_lines,
            "golden",
            round_number,
            name,
            index-1,
            "a",
            fmt(a,6),
            "b",
            fmt(b,6),
            "c",
            fmt(c,6),
            "d",
            fmt(d,6),
            "rmse",
            fmt(rmse(s,fc)),
            fmt(rmse(s,fd))
        )
    end
    line!(s.fit_lines,"golden_result",round_number,name,fmt(search.point,6),"sse",fmt(search.value,1))
end
function fit_model!(s)
    bmin,bmax,nb = s.params["beta_grid"]
    rmin,rmax,nr = s.params["rho_grid"]
    betas = [bmin+(bmax-bmin)*i/(nb-1) for i in 0:nb-1]
    rhos = [rmin+(rmax-rmin)*j/(nr-1) for j in 0:nr-1]
    s.delta_beta,s.delta_rho = (bmax-bmin)/(nb-1),(rmax-rmin)/(nr-1)
    line!(
        s.fit_lines,
        "data days",
        s.days,
        "cases",
        s.case_total,
        "deaths",
        s.death_total,
        "population",
        s.population,
        "fatality",
        fmt(s.fatality,6)
    )
    line!(s.fit_lines,"grid gamma",fmt(s.gamma0),"rho",join(fmt.(rhos)," "))
    best = (Inf,0,0)
    for (i,beta) in enumerate(betas)
        errors = Float64[]
        for (j,rho) in enumerate(rhos)
            value = fit_error(s,beta,s.gamma0,rho)
            push!(errors,value)
            best = min(best,(value,i,j))
        end
        line!(s.fit_lines,"grid beta",fmt(beta),"rmse",join((fmt(rmse(s,value),2) for value in errors)," "))
    end
    grid_sse,i,j = best
    grid_beta,grid_rho = betas[i],rhos[j]
    line!(
        s.fit_lines,
        "grid_best beta",
        fmt(grid_beta),
        "rho",
        fmt(grid_rho),
        "sse",
        fmt(grid_sse,1),
        "rmse",
        fmt(rmse(s,grid_sse))
    )
    beta,rho = grid_beta,grid_rho
    iterations,rounds = s.params["golden"]
    golden_sse = 0.0
    for round_number in 1:rounds
        search = golden(value->fit_error(s,value,s.gamma0,rho),beta-s.delta_beta,beta+s.delta_beta,iterations)
        golden_records!(s,round_number,"beta",search)
        beta = search.point
        search = golden(value->fit_error(s,beta,s.gamma0,value),rho-s.delta_rho,rho+s.delta_rho,iterations)
        golden_records!(s,round_number,"rho",search)
        rho,golden_sse = search.point,search.value
    end
    golden_beta = beta
    search = nelder_mead(
        (b,g)->fit_error(s,b,g,rho),
        beta,
        s.gamma0,
        s.params["simplex"]...,
        s.params["nelder_mead"]...
    )
    for vertex in search.initial
        line!(
            s.fit_lines,
            "simplex",
            vertex.number,
            "beta",
            fmt(vertex.beta,6),
            "gamma",
            fmt(vertex.gamma,6),
            "rmse",
            fmt(rmse(s,vertex.value))
        )
    end
    for (iteration,record) in enumerate(search.records)
        vertex = record.vertex
        line!(
            s.fit_lines,
            "nelder_mead",
            iteration,
            record.operation,
            "beta",
            fmt(vertex.beta,6),
            "gamma",
            fmt(vertex.gamma,6),
            "rmse",
            fmt(rmse(s,vertex.value))
        )
    end
    for (rank,vertex) in enumerate(search.vertices)
        line!(
            s.fit_lines,
            "final_simplex",
            rank,
            "beta",
            fmt(vertex.beta,6),
            "gamma",
            fmt(vertex.gamma,6),
            "rmse",
            fmt(rmse(s,vertex.value))
        )
    end
    vertex = search.vertices[1]
    s.beta,s.gamma,s.rho,s.sse_nm = vertex.beta,vertex.gamma,rho,vertex.value
    s.r0 = s.beta/s.gamma
    mean = s.case_total/s.days
    sst = ordered_sum((value-mean)*(value-mean) for value in s.cases)
    line!(
        s.fit_lines,
        "fitted beta",
        fmt(s.beta,6),
        "gamma",
        fmt(s.gamma,6),
        "rho",
        fmt(rho,6),
        "sigma",
        fmt(s.sigma,6),
        "r0",
        fmt(s.r0)
    )
    line!(
        s.fit_lines,
        "sse grid",
        fmt(grid_sse,1),
        "golden",
        fmt(golden_sse,1),
        "nelder_mead",
        fmt(s.sse_nm,1),
        "rmse",
        fmt(rmse(s,s.sse_nm)),
        "r2",
        fmt(1-s.sse_nm/sst)
    )
    for (name,b,g,r,error) in (
        ("grid",grid_beta,s.gamma0,grid_rho,grid_sse),
        ("golden",golden_beta,s.gamma0,rho,golden_sse),
        ("nelder_mead",s.beta,s.gamma,rho,s.sse_nm)
    )
        line!(
            s.fit_lines,
            "stage",
            name,
            "beta",
            fmt(b,6),
            "gamma",
            fmt(g,6),
            "rho",
            fmt(r,6),
            "r0",
            fmt(b/g),
            "rmse",
            fmt(rmse(s,error))
        )
    end
end
function fitted_diagnostics!(s)
    s.states = [[s.initial]; seird_states(s,s.beta,s.gamma)]
    s.incidence = [state[6] for state in s.states[2:end]]
    s.reported = s.rho.*s.incidence
    s.residuals = s.cases.-s.reported
    s.model_deaths = [s.states[d+1][5]-s.states[d][5] for d in 1:s.days]
    s.rt = [s.r0*s.multipliers[d]*s.states[d][1]/s.population for d in 1:s.days]
    s.averages = [sum(s.cases[max(1,d-6):d])/min(d,7) for d in 1:s.days]
    observed_total,reported_total = 0,0.0
    for (observed,fitted) in zip(s.cases,s.reported)
        observed_total += observed
        reported_total += fitted
        push!(s.cumulative_cases,observed_total)
        push!(s.cumulative_reported,reported_total)
    end
    s.reported_total = reported_total
    absolute = abs.(s.residuals)
    largest = peak(absolute)
    positive = count(>(0),s.residuals)
    runs = 1+count(d->(s.residuals[d]>0)!=(s.residuals[d-1]>0),2:s.days)
    square = ordered_sum(value*value for value in s.residuals)
    differences = [s.residuals[d]-s.residuals[d-1] for d in 2:s.days]
    dw = ordered_sum(value*value for value in differences)/square
    line!(
        s.fit_lines,
        "residuals sum",
        fmt(ordered_sum(s.residuals),1),
        "mae",
        fmt(ordered_sum(absolute)/s.days,1),
        "max",
        fmt(s.residuals[largest],1),
        "day",
        largest,
        "positive",
        positive,
        "runs",
        runs,
        "durbin_watson",
        fmt(dw)
    )
    correlations = [ordered_sum(s.residuals[d]*s.residuals[d+lag] for d in 1:s.days-lag)/square for lag in 1:7]
    line!(s.fit_lines,"autocorrelation",join(fmt.(correlations)," "))
    outliers = 0
    for d in 1:s.days
        z = s.residuals[d]/sqrt(s.reported[d])
        if abs(z)>s.params["outlier"]
            line!(s.fit_lines,"outlier",d,"observed",s.cases[d],"fitted",fmt(s.reported[d],1),"z",fmt(z))
            outliers += 1
        end
    end
    line!(s.fit_lines,"outliers",outliers)
    factors = Float64[]
    for weekday in 1:7
        observed = sum(s.cases[weekday:7:end])
        fitted = ordered_sum(s.reported[weekday:7:end])
        push!(factors,observed/fitted)
        line!(
            s.fit_lines,
            "weekday",
            weekday,
            "observed",
            observed,
            "fitted",
            fmt(fitted,1),
            "factor",
            fmt(factors[end])
        )
    end
    adjusted = [s.reported[d]*factors[mod1(d,7)] for d in 1:s.days]
    line!(s.fit_lines,"weekday_adjusted rmse",fmt(rmse(s,squared_errors(adjusted,1,s.cases))))
    infections = ordered_sum(s.incidence)
    line!(
        s.fit_lines,
        "burden infections",
        fmt(infections,1),
        "ascertainment",
        fmt(s.case_total/infections),
        "deaths_per_infection",
        fmt(s.death_total/infections,6)
    )
    numerator = ordered_sum(value*observed for (value,observed) in zip(s.model_deaths,s.deaths))
    scale = numerator/ordered_sum(value*value for value in s.model_deaths)
    line!(
        s.fit_lines,
        "deaths observed",
        s.death_total,
        "model",
        fmt(s.states[end][5],1),
        "rmse",
        fmt(rmse(s,squared_errors(s.model_deaths,1,s.deaths))),
        "scale",
        fmt(scale),
        "implied_fatality",
        fmt(s.fatality*scale,6),
        "cfr",
        fmt(s.death_total/s.case_total)
    )
    correlations = Float64[]
    for lag in 0:s.params["death_lag"]
        a = sum(s.cases[d]*s.deaths[d+lag] for d in 1:s.days-lag)
        b = sum(value*value for value in s.cases[1:s.days-lag])
        y = sum(value*value for value in s.deaths[lag+1:end])
        correlation = a/sqrt(Float64(b)*Float64(y))
        push!(correlations,correlation)
        line!(
            s.fit_lines,
            "death_lag",
            lag,
            "correlation",
            fmt(correlation),
            "cfr",
            fmt(sum(s.deaths[lag+1:end])/sum(s.cases[1:s.days-lag]))
        )
    end
    line!(s.fit_lines,"death_best_lag",peak(correlations)-1)
    previous = 0
    for (week,(first,last)) in enumerate(s.week_ranges)
        observed = sum(s.cases[first:last])
        growth = week==1 ? "-" : fmt(observed/previous)
        line!(
            s.fit_lines,
            "weekly",
            week,
            "days",
            first,
            last,
            "observed",
            observed,
            "fitted",
            fmt(ordered_sum(s.reported[first:last]),1),
            "deaths_observed",
            sum(s.deaths[first:last]),
            "deaths_model",
            fmt(ordered_sum(s.model_deaths[first:last]),1),
            "growth",
            growth
        )
        previous = observed
    end
end
function profiles!(s)
    fitted = [s.beta,s.gamma,s.rho]
    variance = s.sse_nm/(s.days-3)
    for (index,name) in enumerate(("beta","gamma","rho"))
        value,errors = fitted[index],Dict{Int,Float64}()
        for offset in -5:5
            point = value*(1+offset/100)
            parameters = copy(fitted)
            parameters[index] = point
            error = fit_error(s,parameters...)
            errors[offset] = error
            line!(s.fit_lines,"profile",name,offset,"value",fmt(point,6),"rmse",fmt(rmse(s,error)))
        end
        h = value/100
        curvature = (errors[1]-2*errors[0]+errors[-1])/(h*h)
        standard_error = sqrt(2*variance/curvature)
        push!(s.standard_errors,standard_error)
        line!(s.fit_lines,"profile_se",name,fmt(standard_error,6))
    end
end
function backtest!(s)
    holdout = s.params["holdout"]
    training = s.days-holdout
    cache = Dict{Float64,Vector{Float64}}()
    function training_error(beta,rho)
        incidence = get!(cache,beta) do
            [state[6] for state in seird_states(s,beta,s.gamma;multipliers=s.multipliers[1:training])]
        end
        squared_errors(incidence,rho,s.cases[1:training])
    end
    iterations = s.params["golden"][1]
    beta = golden(value->training_error(value,s.rho),s.beta-s.delta_beta,s.beta+s.delta_beta,iterations).point
    search = golden(value->training_error(beta,value),s.rho-s.delta_rho,s.rho+s.delta_rho,iterations)
    rho = search.point
    forecasts = rho.*incidence_for(s,beta,s.gamma)[training+1:end]
    test_error = squared_errors(forecasts,1,s.cases[training+1:end])
    full_error = squared_errors(s.reported[training+1:end],1,s.cases[training+1:end])
    line!(
        s.fit_lines,
        "backtest train_days",
        training,
        "beta",
        fmt(beta,6),
        "rho",
        fmt(rho,6),
        "train_rmse",
        fmt(rmse(s,search.value,training)),
        "test_rmse",
        fmt(rmse(s,test_error,holdout)),
        "full_fit_test_rmse",
        fmt(rmse(s,full_error,holdout))
    )
    for (index,forecast) in enumerate(forecasts)
        d = training+index
        line!(
            s.fit_lines,
            "backtest_day",
            d,
            "observed",
            s.cases[d],
            "forecast",
            fmt(forecast,1),
            "error",
            fmt(s.cases[d]-forecast,1)
        )
    end
end
function estimate_effects!(s)
    estimated,after = copy(s.interventions),s.sse_nm
    width = s.params["effect_width"]
    for index in 2:length(s.interventions)
        day,given = s.interventions[index]
        function objective(value)
            changed = copy(estimated)
            changed[index] = (day,value)
            states = seird_states(s,s.beta,s.gamma;multipliers=multiplier_sequence(changed,s.days))
            squared_errors([state[6] for state in states],s.rho,s.cases)
        end
        search = golden(objective,given-width,given+width,s.params["golden"][1])
        estimated[index],after = (day,search.point),search.value
        line!(
            s.fit_lines,
            "effect",
            index,
            "day",
            day,
            "given",
            fmt(given),
            "estimated",
            fmt(search.point,6),
            "sse",
            fmt(after,1)
        )
    end
    line!(s.fit_lines,"effect_sse before",fmt(s.sse_nm,1),"after",fmt(after,1),"rmse",fmt(rmse(s,after)))
end
function sensitivity!(s)
    fitted = [s.beta,s.gamma,s.sigma,s.rho]
    for (index,name) in enumerate(("beta","gamma","sigma","rho")), factor in (0.9,1.1)
        parameters = copy(fitted)
        parameters[index] *= factor
        beta,gamma,sigma,rho = parameters
        states = seird_states(s,beta,gamma;sigma=sigma)
        incidence = [state[6] for state in states]
        day = peak(incidence)
        line!(
            s.fit_lines,
            "sensitivity",
            name,
            fmt(factor,2),
            "r0",
            fmt(beta/gamma),
            "rmse",
            fmt(rmse(s,squared_errors(incidence,rho,s.cases))),
            "peak_day",
            day,
            "peak",
            fmt(rho*incidence[day],1),
            "attack",
            fmt((s.population-states[end][1])/s.population)
        )
    end
end
function age_states_for(s;contacts=s.normalized_contacts,multipliers=s.multipliers,initial=s.age_initial)
    simulate(
        age_seird(s.populations,s.fatalities,s.sigma,s.beta,s.gamma,contacts),
        initial,
        multipliers,
        6:6:length(s.age_initial)
    )
end
function next_generation(s,contacts)
    [
        s.r0*contacts[g,h]*s.populations[g]/s.populations[h] for g in eachindex(s.groups),
        h in eachindex(s.groups)
    ]
end
function analyze_age!(s)
    n = length(s.groups)
    kbar = ordered_sum(s.populations[g]*ordered_sum(s.contacts[g,:]) for g in 1:n)/s.population
    s.normalized_contacts = s.contacts./kbar
    matrix = next_generation(s,s.normalized_contacts)
    reproduction,eigenvector = power_method(matrix)
    for g in 1:n
        line!(s.age_lines,"ngm",s.groups[g].name,join(fmt.(matrix[g,:])," "))
    end
    line!(
        s.age_lines,
        "r0_age",
        fmt(reproduction),
        "ratio",
        fmt(reproduction/s.r0),
        "kbar",
        fmt(kbar),
        "eigenvector",
        join(fmt.(eigenvector)," ")
    )
    final = ones(n)
    for _ in 1:100
        final = [1-exp(-ordered_sum(s.r0*s.normalized_contacts[g,h]*final[h] for h in 1:n)) for g in 1:n]
    end
    long_states = age_states_for(s;multipliers=ones(730))
    simulated = [(s.populations[g]-long_states[end][6g-5])/s.populations[g] for g in 1:n]
    for g in 1:n
        line!(
            s.age_lines,
            "final_size_age",
            s.groups[g].name,
            "equation",
            fmt(final[g]),
            "simulated",
            fmt(simulated[g])
        )
    end
    line!(
        s.age_lines,
        "final_size_age total equation",
        fmt(ordered_sum(s.populations[g]*final[g] for g in 1:n)/s.population),
        "simulated",
        fmt(ordered_sum(s.populations[g]*simulated[g] for g in 1:n)/s.population)
    )
    s.age_states = [[s.age_initial]; age_states_for(s)]
    s.age_incidence = [ordered_sum(state[6:6:end]) for state in s.age_states[2:end]]
    for day in 1:7:s.days
        previous = s.age_states[day]
        matrix = [
            s.multipliers[day]*s.r0*s.normalized_contacts[g,h]*previous[6g-5]/s.populations[h] for g in 1:n,
            h in 1:n
        ]
        reproduction,_ = power_method(matrix)
        line!(s.age_lines,"age_rt",day,fmt(reproduction),"homogeneous",fmt(s.rt[day]))
    end
    for (week,(first,last)) in enumerate(s.week_ranges)
        totals = [ordered_sum(s.age_states[d+1][6g] for d in first:last) for g in 1:n]
        line!(s.age_lines,"age_weekly",week,"days",first,last,join((fmt(value,1) for value in totals)," "))
    end
    infections = [ordered_sum(state[6g] for state in s.age_states[2:end]) for g in 1:n]
    infection_total = ordered_sum(infections)
    for g in 1:n
        incidence = [state[6g] for state in s.age_states[2:end]]
        day = peak(incidence)
        attack = (s.populations[g]-s.age_states[end][6g-5])/s.populations[g]
        line!(
            s.age_lines,
            "age",
            s.groups[g].name,
            "attack",
            fmt(attack),
            "infections",
            fmt(infections[g],1),
            "share",
            fmt(infections[g]/infection_total),
            "deaths",
            fmt(s.age_states[end][6g-1],1),
            "peak_day",
            day,
            "peak",
            fmt(incidence[day],1)
        )
    end
    for (name,target,factor) in s.params["contact_change"]
        tau = [group.name==target ? factor : 1.0 for group in s.groups]
        contacts = [s.normalized_contacts[g,h]*tau[g]*tau[h] for g in 1:n,h in 1:n]
        reproduction,_ = power_method(next_generation(s,contacts))
        states = age_states_for(s;contacts=contacts)
        infections = ordered_sum(ordered_sum(state[6:6:end]) for state in states)
        deaths = ordered_sum(states[end][5:6:end])
        attack = ordered_sum(s.populations[g]-states[end][6g-5] for g in 1:n)/s.population
        line!(
            s.age_lines,
            "contact_change",
            name,
            "group",
            target,
            "factor",
            fmt(factor),
            "r0_age",
            fmt(reproduction),
            "infections",
            fmt(infections,1),
            "deaths",
            fmt(deaths,1),
            "attack",
            fmt(attack)
        )
    end
end
function sir_incidence(s,beta)
    [state[4] for state in simulate(sir(s.population,beta,s.gamma),s.sir_initial,s.multipliers,[4])]
end
function compare_models!(s)
    for (name,incidence) in (("sir",sir_incidence(s,s.beta)),("seir",s.incidence),("age",s.age_incidence))
        numerator = ordered_sum(observed*value for (observed,value) in zip(s.cases,incidence))
        rho = numerator/ordered_sum(value*value for value in incidence)
        line!(
            s.fit_lines,
            "model",
            name,
            "rmse",
            fmt(rmse(s,squared_errors(incidence,s.rho,s.cases))),
            "peak_day",
            peak(incidence),
            "rho_opt",
            fmt(rho,6),
            "rmse_opt",
            fmt(rmse(s,squared_errors(incidence,rho,s.cases)))
        )
    end
    lower,upper,_ = s.params["beta_grid"]
    search = golden(
        value->squared_errors(sir_incidence(s,value),s.rho,s.cases),
        lower,
        upper,
        s.params["golden"][1]
    )
    line!(
        s.fit_lines,
        "model sir_fit beta",
        fmt(search.point,6),
        "rmse",
        fmt(rmse(s,search.value)),
        "peak_day",
        peak(sir_incidence(s,search.point))
    )
end
function counterfactual_reported(s,interventions)
    states = seird_states(s,s.beta,s.gamma;multipliers=multiplier_sequence(interventions,s.days))
    [s.rho*state[6] for state in states]
end
function analyze_reproduction!(s)
    lines = s.reproduction_lines
    line!(lines,"r0",fmt(s.r0),"herd_immunity",fmt(1-1/s.r0))
    long_states = seird_states(s,s.beta,s.gamma;multipliers=ones(730))
    line!(
        lines,
        "final_size equation",
        fmt(final_size(s.r0)),
        "simulated",
        fmt((s.population-long_states[end][1])/s.population)
    )
    length_interval = s.params["generation"]
    states = simulate(generation(s.sigma,s.gamma),[1.0,0,0],ones(length_interval),[3])
    amounts = [state[3] for state in states]
    coverage = ordered_sum(amounts)
    weights = amounts./coverage
    mean = ordered_sum((day-0.5)*weight for (day,weight) in enumerate(weights))
    line!(lines,"generation mean",fmt(mean),"theory",fmt(1/s.sigma+1/s.gamma),"coverage",fmt(coverage))
    for (day,weight) in enumerate(weights)
        line!(lines,"generation_weight",day,fmt(weight,6))
    end
    pressures = [ordered_sum(weights[lag]*s.cases[d-lag] for lag in 1:min(
        length_interval,
        d-1
    )) for d in 1:s.days]
    incidence_day = peak(s.incidence)
    infectious = [state[3] for state in s.states[2:end]]
    infectious_day,observed_day,average_day = peak(infectious),peak(s.cases),peak(s.averages)
    line!(
        lines,
        "peak model day",
        incidence_day,
        "incidence",
        fmt(s.incidence[incidence_day],1),
        "reported",
        fmt(s.reported[incidence_day],1),
        "infectious_day",
        infectious_day,
        "infectious",
        fmt(infectious[infectious_day],1)
    )
    line!(
        lines,
        "peak observed day",
        observed_day,
        "cases",
        s.cases[observed_day],
        "average7_day",
        average_day,
        "average7",
        fmt(s.averages[average_day],2)
    )
    for (index,(first,multiplier)) in enumerate(s.interventions)
        last = index<length(s.interventions) ? s.interventions[index+1][1]-1 : s.days
        residuals = s.residuals[first:last]
        error = ordered_sum(value*value for value in residuals)
        n = last-first+1
        line!(
            lines,
            "period",
            index,
            "days",
            first,
            last,
            "multiplier",
            fmt(multiplier),
            "rt_start",
            fmt(s.rt[first]),
            "rt_end",
            fmt(s.rt[last]),
            "observed",
            sum(s.cases[first:last]),
            "fitted",
            fmt(ordered_sum(s.reported[first:last]),1),
            "rmse",
            fmt(rmse(s,error,n)),
            "bias",
            fmt(ordered_sum(residuals)/n,1)
        )
    end
    for target in s.params["milestones"]
        observed = findfirst(>=(target),s.cumulative_cases)
        fitted = findfirst(>=(target),s.cumulative_reported)
        line!(
            lines,
            "milestone",
            target,
            "observed",
            isnothing(observed) ? "never" : observed,
            "fitted",
            isnothing(fitted) ? "never" : fitted
        )
    end
    reported = counterfactual_reported(s,s.interventions[1:1])
    total,day = ordered_sum(reported),peak(reported)
    line!(
        lines,
        "counterfactual none reported",
        fmt(total,1),
        "peak_day",
        day,
        "peak",
        fmt(reported[day],1),
        "averted",
        fmt(total-s.reported_total,1)
    )
    for index in 2:length(s.interventions)
        changed = [entry for (i,entry) in enumerate(s.interventions) if i!=index]
        total = ordered_sum(counterfactual_reported(s,changed))
        line!(
            lines,
            "counterfactual without",
            index,
            "reported",
            fmt(total,1),
            "averted",
            fmt(total-s.reported_total,1)
        )
    end
    for index in 2:length(s.interventions), shift in (-7,7)
        changed = copy(s.interventions)
        day,multiplier = changed[index]
        changed[index] = (day+shift,multiplier)
        total = ordered_sum(counterfactual_reported(s,changed))
        line!(
            lines,
            "timing",
            index,
            "shift",
            shift,
            "reported",
            fmt(total,1),
            "change",
            fmt(total-s.reported_total,1)
        )
    end
    for d in 2:s.days
        if (s.rt[d]<1)!=(s.rt[d-1]<1)
            line!(lines,"rt_cross day",d,s.rt[d]<1 ? "down" : "up")
        end
    end
    for d in 1:s.days
        empirical = d<length_interval+7 ? "-" : fmt(sum(s.cases[d-6:d])/ordered_sum(pressures[d-6:d]))
        line!(lines,"rt",d,"model",fmt(s.rt[d]),"empirical",empirical)
    end
    append!(lines,s.age_lines)
end
function scenario_projections!(s)
    horizon,threshold = s.params["horizon"],s.params["threshold"]
    rows,baseline = ["scenario,day,incidence,reported"],nothing
    for (name,multiplier) in s.params["scenario"]
        future = fill(multiplier,horizon)
        states = seird_states(s,s.beta,s.gamma;multipliers=future,initial=s.states[end])
        incidence = [state[6] for state in states]
        reported = s.rho.*incidence
        for day in 1:horizon
            push!(rows,join((name,s.days+day,fmt(incidence[day],1),fmt(reported[day],1)),","))
        end
        reproduction = s.r0*multiplier*s.states[end][1]/s.population
        total = ordered_sum(reported)
        isnothing(baseline) && (baseline=total)
        day = peak(reported)
        below = findfirst(<(threshold),reported)
        line!(
            s.reproduction_lines,
            "scenario",
            name,
            "multiplier",
            fmt(multiplier),
            "rt",
            fmt(reproduction),
            "reported",
            fmt(total,1),
            "peak_day",
            s.days+day,
            "peak",
            fmt(reported[day],1),
            "attack",
            fmt((s.population-states[end][1])/s.population),
            "final_size",
            fmt(final_size(s.r0*multiplier)),
            "averted",
            fmt(baseline-total,1),
            "below",
            isnothing(below) ? "never" : s.days+below,
            "days_above",
            count(>=(threshold),reported)
        )
        beta_low,beta_high = s.beta-2*s.standard_errors[1],s.beta+2*s.standard_errors[1]
        band = Float64[]
        for beta in (beta_low,beta_high)
            full = seird_states(s,beta,s.gamma;multipliers=[s.multipliers;future])
            push!(band,ordered_sum(s.rho*state[6] for state in full[s.days+1:end]))
        end
        line!(
            s.reproduction_lines,
            "scenario_band",
            name,
            "beta_low",
            fmt(beta_low,6),
            "reported_low",
            fmt(band[1],1),
            "beta_high",
            fmt(beta_high,6),
            "reported_high",
            fmt(band[2],1)
        )
        age_states = age_states_for(s;multipliers=future,initial=s.age_states[end])
        attacks = [(population-age_states[end][6g-5])/population for (
            g,
            population
        ) in enumerate(s.populations)]
        line!(
            s.reproduction_lines,
            "scenario_age",
            name,
            "attack",
            join(fmt.(attacks)," "),
            "deaths",
            fmt(ordered_sum(age_states[end][5:6:end]),1)
        )
    end
    rows
end
function trajectories(s)
    lines = ["day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported"]
    for d in 1:s.days
        values = [string(d);[fmt(value,1) for value in s.states[d+1]]]
        append!(
            values,
            [
                fmt(s.reported[d],1),
                string(s.cases[d]),
                fmt(s.averages[d],2),
                string(s.cumulative_cases[d]),
                fmt(s.cumulative_reported[d],1)
            ]
        )
        push!(lines,join(values,","))
    end
    lines
end
function main()
    s = prepare_study(read_inputs())
    fit_model!(s)
    fitted_diagnostics!(s)
    profiles!(s)
    backtest!(s)
    estimate_effects!(s)
    sensitivity!(s)
    analyze_age!(s)
    compare_models!(s)
    analyze_reproduction!(s)
    scenarios = scenario_projections!(s)
    write_outputs([
        "fit.txt"=>s.fit_lines,
        "trajectories.csv"=>trajectories(s),
        "scenarios.csv"=>scenarios,
        "reproduction.txt"=>s.reproduction_lines,
        "curve_plot.txt"=>curve_plot(s.cases,s.reported)
    ])
end
main()
