include("dataset.jl")
include("scaling.jl")
include("neighbors.jl")
include("validation.jl")
include("report.jl")
using .Dataset
using .FeatureScaling
using .Neighbors
using .Validation
using .Report

struct Result
    model::Model
    predictions::Vector{Prediction}
    correct::Int
    rmse::Float64
end
notation(m) = "k=$(m.k) metric=$(m.metric) weighting=$(m.weighting) scaling=$(m.scaling)"
function correctcount(predictions,rows)
    total = 0
    for (prediction,row) in zip(predictions,rows)
        total += prediction.label == row.label
    end
    total
end
residuals(predictions,rows) = [p.estimate-row.target for (p,row) in zip(predictions,rows)]
function crossvalidate(models,rows,foldcount,features,classes)
    predictions = [Vector{Prediction}(undef,length(rows)) for _ in models]
    for fold in stratified(rows,foldcount)
        training = [row for (i,row) in enumerate(rows) if i ∉ fold]
        queries = rows[fold]
        cache = Dict{Tuple{Symbol,Symbol},Vector{Vector{Neighbor}}}()
        for (j,m) in enumerate(models)
            orders = get!(cache,(m.scaling,m.metric)) do
                neighbororders(training,queries,m.scaling,m.metric,features)
            end
            for (index,order) in zip(fold,orders)
                predictions[j][index] = prediction(order,m.k,m.weighting,classes)
            end
        end
    end
    [Result(m,p,correctcount(p,rows),rmse(residuals(p,rows))) for (m,p) in zip(models,predictions)]
end
function bestclassifier(results,indices=eachindex(results))
    best = first(indices)
    for i in indices
        results[i].correct > results[best].correct && (best = i)
    end
    best
end
function bestregressor(results,indices=eachindex(results))
    best = first(indices)
    for i in indices
        fourdecimal(results[i].rmse) < fourdecimal(results[best].rmse) && (best = i)
    end
    best
end
function leaveoneout(models,rows,features,classes)
    predictions = [Vector{Prediction}(undef,length(rows)) for _ in models]
    for i in eachindex(rows)
        training = [row for (j,row) in enumerate(rows) if i != j]
        cache = Dict{Tuple{Symbol,Symbol},Vector{Neighbor}}()
        for (j,m) in enumerate(models)
            order = get!(cache,(m.scaling,m.metric)) do
                only(neighbororders(training,[rows[i]],m.scaling,m.metric,features))
            end
            predictions[j][i] = prediction(order,m.k,m.weighting,classes)
        end
    end
    predictions
end
function labelcounts(rows,labels)
    counts = zeros(Int,length(labels))
    for row in rows
        counts[row.label] += 1
    end
    join(["$label $(counts[i])" for (i,label) in enumerate(labels)]," ")
end
function evaluation(pairs,labels)
    matrix = zeros(Int,length(labels),length(labels))
    for (truth,predicted) in pairs
        matrix[truth,predicted] += 1
    end
    lines = ["true\\predicted "*join(labels," ")]
    for (i,label) in enumerate(labels)
        push!(lines,"$label "*join(matrix[i,:]," "))
    end
    totals,valued = zeros(3),zeros(Int,3)
    for (i,label) in enumerate(labels)
        hits = matrix[i,i]
        predicted,actual = sum(matrix[:,i]),sum(matrix[i,:])
        for (j,(n,d)) in enumerate(((hits,predicted),(hits,actual),(2*hits,predicted+actual)))
            if d > 0
                totals[j] += n/d
                valued[j] += 1
            end
        end
        push!(lines,"class $label precision $(fraction(hits,predicted)) recall $(fraction(hits,actual)) f1 $(fraction(2*hits,predicted+actual)) support $actual")
    end
    average = [valued[j] == 0 ? "-" : fixed(totals[j]/valued[j]) for j in 1:3]
    push!(lines,"macro precision $(average[1]) recall $(average[2]) f1 $(average[3])")
    lines
end
function reliability(pairs,bounds)
    lowers = vcat(0.0,bounds)
    counts,hits,shares = zeros(Int,length(lowers)),zeros(Int,length(lowers)),zeros(length(lowers))
    for (prediction,truth) in pairs
        index = searchsortedlast(lowers,prediction.share)
        counts[index] += 1
        hits[index] += prediction.label == truth
        shares[index] += prediction.share
    end
    [counts[i] == 0 ? "bin $(fixed(lower,2)) rows 0" : "bin $(fixed(lower,2)) rows $(counts[i]) correct $(ratio(hits[i],counts[i])) share $(fixed(shares[i]/counts[i]))" for (i,lower) in enumerate(lowers)]
end
function nestedpart(data,grid,features)
    train,settings = data.train,data.settings
    estimates = Vector{Float64}(undef,length(train))
    correct = 0
    lines = ["nested_cross_validation folds $(settings.folds)"]
    for (f,fold) in enumerate(stratified(train,settings.folds))
        training = [row for (i,row) in enumerate(train) if i ∉ fold]
        results = crossvalidate(grid,training,settings.folds,features,length(data.labels))
        classifier,regressor = results[bestclassifier(results)],results[bestregressor(results)]
        queries = train[fold]
        cp = predictrows(classifier.model,training,queries,features,length(data.labels))
        rp = predictrows(regressor.model,training,queries,features,length(data.labels))
        hits = correctcount(cp,queries)
        correct += hits
        for (i,p) in zip(fold,rp)
            estimates[i] = p.estimate
        end
        push!(lines,"fold $f classifier $(notation(classifier.model)) inner $(fixed(classifier.correct/length(training))) outer $(ratio(hits,length(fold)))")
        push!(lines,"fold $f regressor $(notation(regressor.model)) inner $(fixed(regressor.rmse)) outer $(fixed(rmse(residuals(rp,queries))))")
    end
    errors = [estimate-row.target for (estimate,row) in zip(estimates,train)]
    push!(lines,"nested accuracy $(ratio(correct,length(train))) rmse $(fixed(rmse(errors)))")
    lines
end
function featurepart(data,classifier,features)
    s,train = data.settings,data.train
    current,selected = copy(features),copy(features)
    best = classifier.correct
    lines = ["feature_selection $(notation(classifier.model))","start features $(join(data.features[current]," ")) correct $(ratio(best,length(train)))"]
    step = 0
    while length(current) >= 3
        step += 1
        candidates = Int[]
        for j in current
            used = [k for k in current if k != j]
            result = only(crossvalidate([classifier.model],train,s.folds,used,length(data.labels)))
            push!(candidates,result.correct)
        end
        winner = argmax(candidates)
        removed = current[winner]
        descriptions = join(["$(data.features[j]) $count" for (j,count) in zip(current,candidates)]," ")
        correct = candidates[winner]
        push!(lines,"step $step remove $(data.features[removed]) correct $(ratio(correct,length(train))) candidates $descriptions")
        deleteat!(current,winner)
        if correct >= best
            best = correct
            selected = copy(current)
        end
    end
    push!(lines,"selected features $(join(data.features[selected]," ")) correct $(ratio(best,length(train)))")
    labelled = [row for row in data.queries if row.label != 0]
    predictions = predictrows(classifier.model,train,labelled,selected,length(data.labels))
    push!(lines,"selected test $(ratio(correctcount(predictions,labelled),length(labelled)))")
    lines
end
function joinedparts(parts)
    lines = String[]
    for part in parts
        isempty(lines) || push!(lines,"")
        append!(lines,part)
    end
    lines
end
function prototypes(data,model,features,classorders,classpredictions)
    train,queries,s = data.train,data.queries,data.settings
    n,classes = length(train),length(data.labels)
    fullorders = neighbororders(train,train,model.scaling,model.metric,features)
    idorder = sortperm(train,by=row -> row.id)
    filtered(i,mask) = [neighbor for neighbor in fullorders[i] if neighbor.row.index != i && mask[neighbor.row.index]]
    edited = copy(idorder)
    editing = ["editing k=$(s.edit)"]
    pass = 0
    while true
        pass += 1
        present = falses(n)
        present[edited] .= true
        removals = Tuple{Int,Prediction}[]
        for i in edited
            vote = prediction(filtered(i,present),s.edit,model.weighting,classes)
            vote.label == train[i].label || push!(removals,(i,vote))
        end
        push!(editing,"pass $pass removed $(length(removals))")
        for (i,vote) in removals
            push!(editing,"  $(train[i].id) true $(data.labels[train[i].label]) predicted $(data.labels[vote.label]) share $(fixed(vote.share))")
        end
        isempty(removals) && break
        removed = Set(first.(removals))
        filter!(i -> i ∉ removed,edited)
    end
    push!(editing,"edited size $(length(edited)) removed $(n-length(edited))")
    function condense(rows)
        store = [rows[1]]
        present = falses(n)
        present[rows[1]] = true
        scans = 0
        while true
            scans += 1
            added = false
            for i in rows
                present[i] && continue
                nearest = findfirst(neighbor -> present[neighbor.row.index],fullorders[i])
                if fullorders[i][nearest].row.label != train[i].label
                    present[i] = true
                    push!(store,i)
                    added = true
                end
            end
            added || break
        end
        sort!(store,by=i -> train[i].id),scans
    end
    condensed,originalscans = condense(idorder)
    editedcondensed,editedscans = condense(edited)
    parts = [["space $(notation(model))"],editing,["condensing original scans $originalscans size $(length(condensed))","condensing edited scans $editedscans size $(length(editedcondensed))"]]
    sets = String[]
    labelled = count(row -> row.label != 0,queries)
    for (name,rows) in (("original",idorder),("edited",edited),("condensed",condensed),("edited_condensed",editedcondensed))
        present = falses(n)
        present[rows] .= true
        knn,one = 0,0
        for (query,order) in zip(queries,classorders)
            query.label == 0 && continue
            nearest = [neighbor for neighbor in order if present[neighbor.row.index]]
            vote = prediction(nearest,model.k,model.weighting,classes)
            knn += vote.label == query.label
            one += nearest[1].row.label == query.label
        end
        push!(sets,"set $name size $(length(rows)) $(labelcounts(train[rows],data.labels)) knn $(ratio(knn,labelled)) 1nn $(ratio(one,labelled))")
    end
    push!(parts,sets)
    for (name,rows) in (("condensed",condensed),("edited_condensed",editedcondensed))
        lines = ["prototypes $name"]
        for start in 1:10:length(rows)
            push!(lines,join([train[i].id for i in rows[start:min(start+9,length(rows))]]," "))
        end
        push!(parts,lines)
    end
    borders = ["borders"]
    totalborder = 0
    for (c,label) in enumerate(data.labels)
        rows = [i for i in idorder if train[i].label == c]
        border = 0
        same,other = 0.0,0.0
        for i in rows
            order = [neighbor for neighbor in fullorders[i] if neighbor.row.index != i]
            border += order[1].row.label != c
            same += order[findfirst(neighbor -> neighbor.row.label == c,order)].distance
            other += order[findfirst(neighbor -> neighbor.row.label != c,order)].distance
        end
        totalborder += border
        push!(borders,"class $label size $(length(rows)) border $border same $(fixed(same/length(rows))) other $(fixed(other/length(rows)))")
    end
    push!(borders,"border total $(ratio(totalborder,n))")
    push!(parts,borders)
    occurrences = zeros(Int,n)
    for p in classpredictions, neighbor in p.nearest
        occurrences[neighbor.row.index] += 1
    end
    ranked = sortperm(train,by=row -> (-occurrences[row.index],row.id))
    hubs = ["hubs k=$(model.k) queries $(length(queries))"]
    for i in ranked[1:min(s.top,n)]
        push!(hubs,"$(train[i].id) $(data.labels[train[i].label]) $(occurrences[i])")
    end
    push!(hubs,"anti_hubs $(count(iszero,occurrences))")
    push!(parts,hubs)
    joinedparts(parts)
end
function main()
    data = readdataset()
    train,queries,s,labels = data.train,data.queries,data.settings,data.labels
    n,classes = length(train),length(labels)
    features = collect(eachindex(data.features))
    grid = [Model(k,metric,weighting,scaling) for k in s.ks for metric in s.metrics for weighting in s.weightings for scaling in s.scalings]
    results = crossvalidate(grid,train,s.folds,features,classes)
    classifier,regressor = results[bestclassifier(results)],results[bestregressor(results)]
    classorders = neighbororders(train,queries,classifier.model.scaling,classifier.model.metric,features)
    cp = [prediction(order,classifier.model.k,classifier.model.weighting,classes) for order in classorders]
    regorders = classifier.model.scaling == regressor.model.scaling && classifier.model.metric == regressor.model.metric ? classorders : neighbororders(train,queries,regressor.model.scaling,regressor.model.metric,features)
    rp = [prediction(order,regressor.model.k,regressor.model.weighting,classes) for order in regorders]
    labelled = findall(row -> row.label != 0,queries)
    targets = findall(row -> row.target !== nothing,queries)
    folds = stratified(train,s.folds)
    parts = Vector{String}[]
    push!(parts,["data train $n test $(length(queries)) labelled $(length(labelled)) targets $(length(targets)) features $(length(features)) classes $classes","classes "*labelcounts(train,labels)])
    for method in s.scalings
        scaling = computescaling(train,method)
        lines = ["scaling $method"]
        for (name,center,scale) in zip(data.features,scaling.centers,scaling.scales)
            push!(lines,"$name center $(fixed(center,6)) scale $(fixed(scale,6))")
        end
        push!(parts,lines)
    end
    push!(parts,vcat(["folds $(s.folds)"],["fold $f size $(length(fold)) $(labelcounts(train[fold],labels))" for (f,fold) in enumerate(folds)]))
    push!(parts,["grid $(length(grid))","best_classifier $(notation(classifier.model)) correct $(ratio(classifier.correct,n)) rmse $(fixed(classifier.rmse))","best_regressor $(notation(regressor.model)) rmse $(fixed(regressor.rmse)) correct $(ratio(regressor.correct,n))"])
    accuracy = sort!(collect(eachindex(results)),by=i -> (-results[i].correct,i))
    regression = sort!(collect(eachindex(results)),by=i -> (fourdecimal(results[i].rmse),i))
    for (name,order) in (("accuracy",accuracy),("rmse",regression))
        lines = ["top $(s.top) by $name"]
        for (rank,i) in enumerate(order[1:min(s.top,length(grid))])
            result = results[i]
            tail = name == "accuracy" ? "correct $(ratio(result.correct,n)) rmse $(fixed(result.rmse))" : "rmse $(fixed(result.rmse)) correct $(ratio(result.correct,n))"
            push!(lines,"$rank $(notation(result.model)) $tail")
        end
        push!(parts,lines)
    end
    for (item,values) in ((:k,s.ks),(:metric,s.metrics),(:weighting,s.weightings),(:scaling,s.scalings))
        lines = ["best per $item"]
        for value in values
            matching = findall(model -> getproperty(model,item) == value,grid)
            c,r = results[bestclassifier(results,matching)],results[bestregressor(results,matching)]
            push!(lines,"$item=$value classifier $(notation(c.model)) accuracy $(fixed(c.correct/n)) regressor $(notation(r.model)) rmse $(fixed(r.rmse))")
        end
        push!(parts,lines)
    end
    push!(parts,vcat(["classifier folds"],["fold $f correct $(ratio(correctcount(classifier.predictions[fold],train[fold]),length(fold)))" for (f,fold) in enumerate(folds)]))
    push!(parts,vcat(["regressor folds"],["fold $f size $(length(fold)) rmse $(fixed(rmse(residuals(regressor.predictions[fold],train[fold]))))" for (f,fold) in enumerate(folds)]))
    push!(parts,vcat(["cross_validation classes"],evaluation([(row.label,p.label) for (row,p) in zip(train,classifier.predictions)],labels)))
    push!(parts,vcat(["cross_validation reliability"],reliability([(p,row.label) for (row,p) in zip(train,classifier.predictions)],s.bins)))
    mcnemar = ["mcnemar"]
    for metric in s.metrics
        comparison = results[bestclassifier(results,findall(m -> m.metric == metric,grid))]
        b,c = 0,0
        for (row,p,q) in zip(train,classifier.predictions,comparison.predictions)
            b += p.label == row.label && q.label != row.label
            c += p.label != row.label && q.label == row.label
        end
        u = max(0,abs(b-c)-1)
        u *= u
        statistic = b+c == 0 ? fraction(0,1) : fraction(u,b+c)
        significant = 1000*u > 3841*(b+c) ? "yes" : "no"
        push!(mcnemar,"$(notation(comparison.model)) b $b c $c statistic $statistic significant $significant")
    end
    push!(parts,mcnemar)
    variants = [Model(k,classifier.model.metric,classifier.model.weighting,classifier.model.scaling) for k in s.ks]
    loo = leaveoneout(vcat(variants,[regressor.model]),train,features,classes)
    lc = loo[findfirst(==(classifier.model.k),s.ks)]
    lr = loo[end]
    errors = findall(i -> lc[i].label != train[i].label,eachindex(train))
    sort!(errors,by=i -> train[i].id)
    classerrors = [count(i -> train[i].label == c,errors) for c in 1:classes]
    lines = ["leave_one_out classifier $(notation(classifier.model))","errors $(ratio(length(errors),n))","class_errors "*join(["$label $(classerrors[c])" for (c,label) in enumerate(labels)]," ")]
    for i in errors
        push!(lines,"$(train[i].id) true $(labels[train[i].label]) predicted $(labels[lc[i].label]) share $(fixed(lc[i].share))")
    end
    push!(parts,lines)
    residual = residuals(lr,train)
    largest = sort!(collect(eachindex(train)),by=i -> (-fourdecimal(abs(residual[i])),train[i].id))
    lines = ["leave_one_out regressor $(notation(regressor.model))","rmse $(fixed(rmse(residual))) mae $(fixed(mae(residual)))","largest $(s.top) residuals"]
    for i in largest[1:min(s.top,n)]
        push!(lines,"$(train[i].id) target $(fixed(train[i].target)) estimate $(fixed(lr[i].estimate)) residual $(fixed(residual[i]))")
    end
    push!(parts,lines)
    lines = ["leave_one_out by k metric=$(classifier.model.metric) weighting=$(classifier.model.weighting) scaling=$(classifier.model.scaling)"]
    for (k,predictions) in zip(s.ks,loo[1:length(variants)])
        push!(lines,"k=$k correct $(ratio(correctcount(predictions,train),n)) rmse $(fixed(rmse(residuals(predictions,train))))")
    end
    push!(parts,lines)
    push!(parts,nestedpart(data,grid,features))
    push!(parts,featurepart(data,classifier,features))
    testcorrect = correctcount(cp[labelled],queries[labelled])
    push!(parts,vcat(["test classification $(notation(classifier.model))","labelled $(length(labelled)) correct $(ratio(testcorrect,length(labelled)))"],evaluation([(queries[i].label,cp[i].label) for i in labelled],labels)))
    push!(parts,vcat(["test reliability"],reliability([(cp[i],queries[i].label) for i in labelled],s.bins)))
    uncertain = sort!(collect(eachindex(queries)),by=i -> (fourdecimal(cp[i].share-cp[i].runner_share),i))
    lines = ["uncertain $(s.top) test rows"]
    for i in uncertain[1:min(s.top,length(queries))]
        p,row = cp[i],queries[i]
        runner = p.runner == 0 ? "-" : labels[p.runner]
        truth = row.label == 0 ? "-" : labels[row.label]
        push!(lines,"$(row.id) predicted $(labels[p.label]) share $(fixed(p.share)) runner_up $runner share $(fixed(p.runner_share)) margin $(fixed(p.share-p.runner_share)) true $truth")
    end
    push!(parts,lines)
    testerrors = [rp[i].estimate-queries[i].target for i in targets]
    targetvalues = [queries[i].target for i in targets]
    lines = ["test regression $(notation(regressor.model))","targets $(length(targets)) rmse $(fixed(rmse(testerrors))) mae $(fixed(mae(testerrors))) r2 $(fixed(rsquared(testerrors,targetvalues)))"]
    for (c,label) in enumerate(labels)
        chosen = [i for i in targets if queries[i].label == c]
        errors = [rp[i].estimate-queries[i].target for i in chosen]
        push!(lines,"class $label targets $(length(chosen)) rmse $(fixed(rmse(errors)))")
    end
    push!(parts,lines)
    lines = ["misclassified test rows"]
    countmisclassified = 0
    for i in labelled
        p,row = cp[i],queries[i]
        p.label == row.label && continue
        countmisclassified += 1
        push!(lines,"$(row.id) true $(labels[row.label]) predicted $(labels[p.label]) share $(fixed(p.share))")
        for neighbor in p.nearest
            push!(lines,"  $(neighbor.row.id) $(labels[neighbor.row.label]) $(fixed(neighbor.distance))")
        end
    end
    push!(lines,"count $countmisclassified")
    push!(parts,lines)
    curve = ["n,train_size,correct,accuracy,rmse"]
    for limit in s.curve
        taken = zeros(Int,classes)
        selected = Row[]
        for row in train
            if taken[row.label] < limit
                taken[row.label] += 1
                push!(selected,row)
            end
        end
        predictions = predictrows(classifier.model,selected,queries,features,classes)
        regressionpredictions = predictrows(regressor.model,selected,queries,features,classes)
        correct = correctcount(predictions[labelled],queries[labelled])
        errors = [regressionpredictions[i].estimate-queries[i].target for i in targets]
        push!(curve,"$limit,$(length(selected)),$correct,$(fixed(correct/length(labelled))),$(fixed(rmse(errors)))")
    end
    gridlines = ["k,metric,weighting,scaling,correct,accuracy,rmse"]
    for result in results
        m = result.model
        push!(gridlines,"$(m.k),$(m.metric),$(m.weighting),$(m.scaling),$(result.correct),$(fixed(result.correct/n)),$(fixed(result.rmse))")
    end
    predictionlines = ["id,label,vote_share,estimate"]
    for (row,p,q) in zip(queries,cp,rp)
        push!(predictionlines,"$(row.id),$(labels[p.label]),$(fixed(p.share)),$(fixed(q.estimate))")
    end
    prototype_lines = prototypes(data,classifier.model,features,classorders,cp)
    mkpath("output")
    for (name,lines) in (("cv_grid.csv",gridlines),("predictions.csv",predictionlines),("metrics.txt",joinedparts(parts)),("learning_curve.csv",curve),("prototypes.txt",prototype_lines))
        writelines(name,lines)
    end
end
main()
