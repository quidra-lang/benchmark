const MODEL_NAMES = ("NB","LDA","QDA")
function train_model(rows,features,class_count,name,prior_mode,epsilon,gamma)
    p,n = length(features),length(rows)
    groups = [[r.x[features] for r in rows if r.y==k] for k in 1:class_count]
    counts = length.(groups)
    means = [[ordered_sum(x[j] for x in group)/length(group) for j in 1:p] for group in groups]
    scatter = [[ordered_sum((x[a]-means[k][a])*(x[b]-means[k][b]) for x in groups[k])
                for a in 1:p,b in 1:p] for k in 1:class_count]
    center = [ordered_sum(r.x[features[j]] for r in rows)/n for j in 1:p]
    variances = [ordered_sum((r.x[features[j]]-center[j])^2 for r in rows)/n for j in 1:p]
    priors = prior_mode=="empirical" ? counts./n : fill(1/class_count,class_count)
    pooled = [ordered_sum(scatter[k][a,b] for k in 1:class_count)/(n-class_count) for a in 1:p,b in 1:p]
    max_variance = maximum(variances)
    added = epsilon*max_variance
    covariance = Matrix{Float64}[]
    for k in 1:class_count
        matrix = zeros(p,p)
        for a in 1:p,b in 1:p
            matrix[a,b] = name=="LDA" ? pooled[a,b] : name=="NB" ?
                (a==b ? scatter[k][a,b]/counts[k]+added : 0.0) :
                scatter[k][a,b]/(counts[k]-1)*(a==b ? 1.0 : 1-gamma)
        end
        push!(covariance,matrix)
    end
    factors = cholesky_factor.(covariance)
    determinants = log_determinant.(factors)
    (name=name,features=copy(features),counts=counts,means=means,scatter=scatter,center=center,
     variances=variances,priors=priors,pooled=pooled,max_variance=max_variance,added=added,
     covariance=covariance,factors=factors,determinants=determinants,epsilon=epsilon,gamma=gamma)
end
function distances_vector(model,vector)
    [quadratic_form(model.factors[k],vector.-model.means[k]) for k in eachindex(model.means)]
end
distances(model,values) = distances_vector(model,values[model.features])
function infer_vector(model,vector,costs=nothing)
    q = distances_vector(model,vector)
    normalizer = length(vector)*log(2pi)/2
    scores = [log(model.priors[k])-normalizer-model.determinants[k]/2-q[k]/2 for k in eachindex(q)]
    predicted = argmax(scores)
    maximum_score = scores[predicted]
    exponentials = exp.(scores.-maximum_score)
    total = ordered_sum(exponentials)
    posterior = exponentials./total
    log_posterior = [(value-maximum_score)-log(total) for value in scores]
    decision = isnothing(costs) ? predicted : argmin([ordered_sum(posterior[k]*costs[
        k,
        b
    ] for k in eachindex(q)) for b in eachindex(q)])
    (
        predicted=predicted,
        posterior=posterior,
        log_posterior=log_posterior,
        confidence=maximum(posterior),
        decision=decision
    )
end
infer(model,values,costs=nothing) = infer_vector(model,values[model.features],costs)
predict(model,values) = infer(model,values).predicted
