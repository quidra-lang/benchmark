function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
hidden_activation(
    kind,
    value
) = kind=="TANH" ? tanh(value) : kind=="SIGMOID" ? 1/(1+exp(-value)) : value>0 ? value : 0.0
hidden_derivative(
    kind,
    z,
    activated
) = kind=="TANH" ? 1-activated*activated : kind=="SIGMOID" ? activated*(1-activated) : z>0 ? 1.0 : 0.0
function output_scores(kind,z,label)
    n = length(z)
    if kind=="SOFTMAX"
        largest = maximum(z)
        terms = exp.(z.-largest)
        total = ordered_sum(terms)
        scores = terms./total
        return scores,log(total)-(z[label+1]-largest),[scores[k]-(k==label+1 ? 1.0 : 0.0) for k in 1:n]
    end
    scores = [1/(1+exp(-value)) for value in z]
    errors,loss = Float64[],0.0
    for (k,value) in enumerate(scores)
        residual = value-(k==label+1 ? 1.0 : 0.0)
        loss += residual*residual
        push!(errors,2*residual*value*(1-value)/n)
    end
    scores,loss/n,errors
end
function weighted_pre_activation(weights,biases,activation)
    [ordered_sum(weights[
        j,
        i
    ]*activation[i] for i in eachindex(activation))+biases[j] for j in eachindex(biases)]
end
backward_sum(
    weights,
    error
) = [ordered_sum(weights[j,i]*error[j] for j in eachindex(error)) for i in axes(weights,2)]
