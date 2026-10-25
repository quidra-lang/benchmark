module Validation
using ..FeatureScaling
using ..Neighbors
export Model, stratified, neighbororders, predictrows, rmse, mae, rsquared
struct Model
    k::Int
    metric::Symbol
    weighting::Symbol
    scaling::Symbol
end
function stratified(rows,count)
    ordered = sortperm(rows,by=row -> (row.label,row.id))
    folds = [Int[] for _ in 1:count]
    for (i,index) in enumerate(ordered)
        push!(folds[mod(i-1,count)+1],index)
    end
    sort!.(folds)
end
function neighbororders(training,queries,method,metric,features)
    scaling = computescaling(training,method)
    vectors = [transform(scaling,row.values,features) for row in training]
    [neighbororder(transform(scaling,row.values,features),training,vectors,metric) for row in queries]
end
predictrows(model,training,queries,features,classes) = [prediction(order,model.k,model.weighting,classes) for order in neighbororders(training,queries,model.scaling,model.metric,features)]
function rmse(errors)
    isempty(errors) && return nothing
    total = 0.0
    for error in errors
        total += error*error
    end
    sqrt(total/length(errors))
end
function mae(errors)
    total = 0.0
    for error in errors
        total += abs(error)
    end
    total/length(errors)
end
function rsquared(errors,targets)
    total = 0.0
    for target in targets
        total += target
    end
    mean = total/length(targets)
    residual,spread = 0.0,0.0
    for error in errors
        residual += error*error
    end
    for target in targets
        delta = target-mean
        spread += delta*delta
    end
    1-residual/spread
end
end
