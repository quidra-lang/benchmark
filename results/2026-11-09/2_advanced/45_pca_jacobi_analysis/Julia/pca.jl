column_means(rows) = [sequential_sum(rows[i,j] for i in axes(rows,1))/size(rows,1) for j in axes(rows,2)]
function covariance_matrix(rows,means)
    n,p = size(rows)
    covariance = zeros(p,p)
    for j in 1:p,k in j:p
        value = sequential_sum((rows[i,j]-means[j])*(rows[i,k]-means[k]) for i in 1:n)/(n-1)
        covariance[j,k] = covariance[k,j] = value
    end
    covariance
end
standard_deviations(covariance) = [sqrt(covariance[j,j]) for j in axes(covariance,1)]
correlation_matrix(covariance,deviations) = [
    j==k ? 1.0 : covariance[j,k]/(deviations[j]*deviations[k]) for j in axes(covariance,1),
    k in axes(covariance,2)
]
standardize(values,means,scales) = [isnothing(value) ? 0.0 : (value-mean)/scale for (value,mean,scale) in zip(
    values,
    means,
    scales
)]
component_scores(z,vectors) = [dot_product(z,vector) for vector in vectors]
residuals(
    z,
    scores,
    vectors,
    n
) = [z[j]-sequential_sum(scores[k]*vectors[k][j] for k in 1:n) for j in eachindex(z)]
hotelling_t2(scores,values,n) = sequential_sum(scores[k]*scores[k]/values[k] for k in 1:n)
