const CLASS_PAIRS = ((1,2),(1,3),(2,3))
function train_multiclass(examples,kernel,C,settings)
    points = [example.point for example in examples]
    classes = [example.class_number for example in examples]
    matrix = kernel_matrix(kernel,points)
    ovr = [train_model(points,[value==k ? 1 : -1 for value in classes],kernel,matrix,C,settings) for k in 1:3]
    ovo = SMOModel[]
    for (first,second) in CLASS_PAIRS
        indices = [i for i in eachindex(classes) if classes[i] in (first,second)]
        labels = [classes[i]==first ? 1 : -1 for i in indices]
        push!(ovo,train_model(points[indices],labels,kernel,submatrix(matrix,indices),C,settings))
    end
    (kernel=kernel,C=C,ovr=ovr,ovo=ovo)
end
function classify(models,point)
    rest = [decision(model,point) for model in models.ovr]
    pairs = [decision(model,point) for model in models.ovo]
    votes,scores = zeros(Int,3),zeros(3)
    for ((first,second),value) in zip(CLASS_PAIRS,pairs)
        votes[value>0 ? first : second] += 1
        scores[first] += value
        scores[second] -= value
    end
    candidates = findall(==(maximum(votes)),votes)
    chosen = candidates[argmax(scores[candidates])]
    (ovr_values=rest,ovo_values=pairs,ovr=argmax(rest),ovo=chosen,votes=votes,tied=length(candidates)>1)
end
