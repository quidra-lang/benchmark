point_xy(point) = (point.x,point.y)
function covariance_type_adjust(initial,type)
    weights,means,source = copy(initial.weights),copy(initial.means),initial.covariances
    if type=="FULL"
        covariances = copy(source)
    elseif type=="DIAG"
        covariances = [(a,0.0,c) for (a,b,c) in source]
    elseif type=="SPHERICAL"
        covariances = [((a+c)/2,0.0,(a+c)/2) for (a,b,c) in source]
    else
        shared = ntuple(j->ordered_sum(weights[k]*source[k][j] for k in eachindex(weights)),3)
        covariances = fill(shared,length(weights))
    end
    Mixture(weights,means,covariances,type)
end
function responsibilities(points,model)
    records = NamedTuple[]
    loglik = 0.0
    for point in points
        scores = [weighted_log_density(
            point_xy(point),
            model.weights[k],
            model.means[k],
            model.covariances[k]
        ) for k in eachindex(model.weights)]
        maximum_score = maximum(scores)
        exponentials = [exp(value-maximum_score) for value in scores]
        normalizer = ordered_sum(exponentials)
        normalized = exponentials./normalizer
        log_density = maximum_score+log(normalizer)
        push!(records,(responsibilities=normalized,log_density=log_density,scores=scores))
        loglik += log_density
    end
    records,loglik
end
function update_model(points,records,type,epsilon)
    n,k_count = length(points),length(records[1].responsibilities)
    counts = [ordered_sum(row.responsibilities[k] for row in records) for k in 1:k_count]
    weights = counts./n
    means = [(ordered_sum(row.responsibilities[k]*p.x for (p,row) in zip(points,records))/counts[k],
        ordered_sum(row.responsibilities[k]*p.y for (p,row) in zip(
            points,
            records
        ))/counts[k]) for k in 1:k_count]
    scatter = NTuple{3,Float64}[]
    for (k,(mx,my)) in enumerate(means)
        a = b = c = 0.0
        for (p,row) in zip(points,records)
            r = row.responsibilities[k]
            dx,dy = p.x-mx,p.y-my
            a += r*dx*dx
            b += r*dx*dy
            c += r*dy*dy
        end
        push!(scatter,(a,b,c))
    end
    covariances = NTuple{3,Float64}[]
    if type=="TIED"
        shared = ntuple(j->ordered_sum(row[j] for row in scatter)/n+(j==2 ? 0.0 : epsilon),3)
        covariances = fill(shared,k_count)
    else
        for (k,(a,b,c)) in enumerate(scatter)
            nk = counts[k]
            if type=="FULL"
                cov = (a/nk+epsilon,b/nk,c/nk+epsilon)
            elseif type=="DIAG"
                cov = (a/nk+epsilon,0.0,c/nk+epsilon)
            else
                variance = (a/nk+c/nk)/2+epsilon
                cov = (variance,0.0,variance)
            end
            push!(covariances,cov)
        end
    end
    Mixture(weights,means,covariances,type)
end
function run_em(points,initial,type,iterations,epsilon)
    model = covariance_type_adjust(initial,type)
    records,loglik = responsibilities(points,model)
    trace = [loglik]
    for _ in 1:iterations
        model = update_model(points,records,type,epsilon)
        records,loglik = responsibilities(points,model)
        push!(trace,loglik)
    end
    (model=model,records=records,trace=trace,loglik=loglik)
end
