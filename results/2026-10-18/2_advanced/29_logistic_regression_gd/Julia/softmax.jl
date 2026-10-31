function shifted_scores(weights,vector)
    scores = [score(row,vector) for row in weights]
    scores .- maximum(scores)
end
function softmax_probabilities(weights,vector)
    shifted = shifted_scores(weights,vector)
    total = ordered_sum(exp(v) for v in shifted)
    [exp(v)/total for v in shifted]
end
predicted_class(probabilities) = argmax(probabilities)-1
function softmax_loss(weights,vector,label)
    shifted = shifted_scores(weights,vector)
    log(ordered_sum(exp(v) for v in shifted))-shifted[label+1]
end
softmax_average_loss(w,x,labels) = ordered_sum(softmax_loss(w,v,k) for (v,k) in zip(x,labels))/length(x)
softmax_objective(
    w,
    x,
    labels,
    lambda
) = softmax_average_loss(w,x,labels)+lambda*ordered_sum(v*v for row in w for v in row[2:end])/2
function softmax_gradient(w,x,labels,lambda)
    totals = [zeros(length(w[1])) for _ in w]
    for (v,label) in zip(x,labels)
        probabilities = softmax_probabilities(w,v)
        for k in eachindex(w)
            error = probabilities[k]-(label == k-1 ? 1.0 : 0.0)
            for j in eachindex(w[k])
                totals[k][j] += error*v[j]
            end
        end
    end
    [[totals[k][j]/length(x)+(j == 1 ? 0.0 : lambda*w[k][j]) for j in eachindex(w[k])] for k in eachindex(w)]
end
function softmax_train(x,labels,classes,lambda,rate,iterations)
    w = [zeros(length(x[1])) for _ in 1:classes]
    checkpoints = [(0,deepcopy(w))]
    for t in 1:iterations
        g = softmax_gradient(w,x,labels,lambda)
        w = [row .- rate .* step for (row,step) in zip(w,g)]
        t%100 == 0 && push!(checkpoints,(t,deepcopy(w)))
    end
    checkpoints
end
