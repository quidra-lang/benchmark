include("dataset.jl")
include("logistic.jl")
include("optimizers.jl")
include("softmax.jl")
include("metrics.jl")

vector_length(values) = sqrt(ordered_sum(v*v for v in values))
final_weights(checkpoints) = checkpoints[end][2]
model_probabilities(w,x) = [probability(score(w,v)) for v in x]
predict(probabilities,threshold) = [Int(v >= threshold) for v in probabilities]
count_equal(a,b) = count(i->a[i] == b[i],eachindex(a))
softmax_correct(w,x,labels) = count_equal([predicted_class(softmax_probabilities(w,v)) for v in x],labels)
function make_data(names,train,test,settings)
    tuples = expansion_tuples(length(names),settings.degree)
    feature_names = expanded_names(names,tuples)
    feature_count = length(tuples)
    train_expanded = [expanded_values(tuples,row.values) for row in train]
    test_expanded = [expanded_values(tuples,row.values) for row in test]
    overall = compute_statistics(train_expanded,feature_count)
    train_vectors = [standardize(v,overall,feature_count) for v in train_expanded]
    test_vectors = [standardize(v,overall,feature_count) for v in test_expanded]
    train_labels,test_labels = [row.label for row in train],[row.label for row in test]
    (
        names=names,
        train=train,
        test=test,
        settings=settings,
        tuples=tuples,
        feature_names=feature_names,
        feature_count=feature_count,
        degree_counts=[count(t->length(t) <= degree,tuples) for degree in 1:settings.degree],
        classes=maximum(train_labels)+1,
        train_expanded=train_expanded,
        test_expanded=test_expanded,
        overall=overall,
        train_vectors=train_vectors,
        test_vectors=test_vectors,
        train_labels=train_labels,
        test_labels=test_labels,
        train_targets=Int.(train_labels .== settings.positive),
        test_targets=Int.(test_labels .== settings.positive),
        mean_values=overall.means[1:length(names)]
    )
end
data_vector(data,values) = standardize(expanded_values(data.tuples,values),data.overall,data.feature_count)
function evaluate(w,x,y,threshold)
    probabilities = model_probabilities(w,x)
    predictions = predict(probabilities,threshold)
    (
        probabilities=probabilities,
        predictions=predictions,
        loss=average_loss(w,x,y),
        correct=count_equal(predictions,y),
        auc=auc(probabilities,y)
    )
end
function binary_model(name,checkpoints,data)
    w = final_weights(checkpoints)
    train = evaluate(w,data.train_vectors,data.train_targets,data.settings.threshold)
    test = evaluate(w,data.test_vectors,data.test_targets,data.settings.threshold)
    (
        name=name,
        checkpoints=checkpoints,
        weights=w,
        train=train,
        test=test,
        roc=roc_points(test.probabilities,data.test_targets)
    )
end
function inverse_matrix(matrix)
    count = size(matrix,1)
    lower = cholesky_lower(matrix)
    result = zeros(count,count)
    for k in 1:count
        unit = zeros(count)
        unit[k] = 1.0
        result[:,k] = solve_lower(lower,unit)
    end
    result
end
function influence(w,x,y,lambda)
    dimension,n = length(w),length(x)
    matrix = inverse_matrix(hessian(w,x,lambda))
    probabilities,leverages,residuals,distances = Float64[],Float64[],Float64[],Float64[]
    for (v,target) in zip(x,y)
        pi = probability(score(w,v))
        variance = pi*(1-pi)
        quadratic = ordered_sum(v[j]*matrix[j,k]*v[k] for j in 1:dimension for k in 1:dimension)
        leverage = variance*quadratic/n
        pearson = (target-pi)/sqrt(variance)
        push!(probabilities,pi)
        push!(leverages,leverage)
        push!(residuals,pearson/sqrt(1-leverage))
        push!(distances,pearson*pearson*leverage/(dimension*((1-leverage)*(1-leverage))))
    end
    edf = ordered_sum(leverages)
    deviance = 2*n*average_loss(w,x,y)
    (
        matrix=matrix,
        probabilities=probabilities,
        leverages=leverages,
        residuals=residuals,
        distances=distances,
        edf=edf,
        deviance=deviance,
        aic=deviance+2*edf,
        bic=deviance+log(n)*edf
    )
end
function original_units(w,statistics)
    scaled = w[2:end] ./ statistics.deviations[1:(length(w)-1)]
    shift = ordered_sum(v*mu for (v,mu) in zip(scaled,statistics.means))
    vcat([w[1]-shift],scaled)
end
function cross_validate(data,lambda,count)
    n = length(data.train)
    losses,probabilities = zeros(n),zeros(n)
    fold_losses = Float64[]
    errors = 0
    for fold in 0:4
        fitting = [i for i in 1:n if (i-1)%5 != fold]
        checking = [i for i in 1:n if (i-1)%5 == fold]
        statistics = compute_statistics(data.train_expanded[fitting],count)
        x = [standardize(data.train_expanded[i],statistics,count) for i in fitting]
        w = final_weights(newton_method(x,data.train_targets[fitting],lambda))
        total = 0.0
        for i in checking
            u = score(w,standardize(data.train_expanded[i],statistics,count))
            losses[i] = logistic_loss(u,data.train_targets[i])
            probabilities[i] = probability(u)
            total += losses[i]
            errors += Int(probabilities[i] >= data.settings.threshold) != data.train_targets[i]
        end
        push!(fold_losses,total/length(checking))
    end
    (
        lambda=lambda,
        fold_losses=fold_losses,
        loss=ordered_sum(losses)/n,
        probabilities=probabilities,
        errors=errors
    )
end
function select_lambda(results)
    best = results[1]
    for result in results
        result.loss <= best.loss && (best=result)
    end
    mean = ordered_sum(best.fold_losses)/5
    se = sqrt(ordered_sum((v-mean)*(v-mean) for v in best.fold_losses)/4)/sqrt(5)
    (best=best,se=se,one_se=maximum(result.lambda for result in results if result.loss <= best.loss+se))
end
bin_index(value) = min(9,floor(Int,value*10))
bin_range(index) = "$(fixed(index/10,1))-$(fixed((index+1)/10,1))"
function fill_bins(values,hits)
    counts,totals,successes = zeros(Int,10),zeros(10),zeros(Int,10)
    for (value,hit) in zip(values,hits)
        i = bin_index(value)+1
        counts[i] += 1
        totals[i] += value
        successes[i] += hit
    end
    (counts=counts,totals=totals,hits=successes)
end
function bin_lines(bins,mean_label,rate_label)
    lines = String[]
    for i in 1:10
        mean = bins.counts[i] == 0 ? "-" : fixed(bins.totals[i]/bins.counts[i])
        push!(
            lines,
            "bin $(bin_range(i-1)) count $(bins.counts[i]) $mean_label $mean $rate_label $(ratio(bins.hits[i],bins.counts[i]))"
        )
    end
    lines
end
calibration_error(
    bins,
    n
) = ordered_sum(abs(bins.totals[i]-bins.hits[i]) for i in 1:10 if bins.counts[i] > 0)/n
function calibration_lines(probabilities,targets)
    bins = fill_bins(probabilities,targets)
    filled = findall(>(0),bins.counts)
    mce = maximum((abs(bins.totals[i]/bins.counts[i]-bins.hits[i]/bins.counts[i]) for i in filled);init=0.0)
    statistic = ordered_sum((bins.hits[i]-bins.totals[i])^2/(bins.totals[i]*(1-bins.totals[i]/bins.counts[i])) for i in filled)
    vcat(
        ["calibration"],
        bin_lines(bins,"mean_probability","positive_rate"),
        ["ece $(fixed(calibration_error(bins,length(targets)))) mce $(fixed(mce)) hosmer_lemeshow $(fixed(statistic)) groups $(length(filled))"]
    )
end
function gains_lines(probabilities,targets)
    n,pos = length(targets),sum(targets)
    order = sortperm(eachindex(probabilities),by=i->(-probabilities[i],i))
    lines = ["gains"]
    for decile in 1:10
        rows = decile*n÷10
        hits = sum(targets[order[1:rows]])
        push!(
            lines,
            "decile $decile rows $rows positives $hits gain $(ratio(hits,pos)) lift $(ratio(hits*n,rows*pos))"
        )
    end
    lines
end
function term_lines(data,w)
    original = original_units(w,data.overall)
    names = vcat(["intercept"],data.feature_names)
    ["term $(names[j]) standardized $(fixed(w[j])) original $(fixed(original[j]))" for j in eachindex(w)]
end
function weights_parts(data,models,softmax_model,inf,lambda)
    n,p = length(data.train),data.feature_count
    correlation = [ordered_sum(v[j+1]*v[k+1] for v in data.train_vectors)/(n-1) for j in 1:p,k in 1:p]
    inflation = inverse_matrix(correlation)
    lines = ["features $(length(data.names)) degree $(data.settings.degree) expanded $p","standardization"]
    for j in 1:p
        push!(
            lines,
            "$(data.feature_names[j]) mean $(fixed(data.overall.means[j],6)) sd $(fixed(data.overall.deviations[j],6)) vif $(fixed(inflation[j,j]))"
        )
    end
    push!(lines,"correlation")
    append!(lines,[join((fixed(correlation[j,k]) for k in 1:p),' ') for j in 1:p])
    parts = [lines]
    nw = models[3].weights
    for model in models
        lines = vcat(
            ["model $(model.name) lambda $(fixed(lambda))"],
            term_lines(data,model.weights),
            ["norm $(fixed(vector_length(model.weights[2:end])))"]
        )
        model.name != "newton" && push!(
            lines,
            "distance_to_newton $(fixed(vector_length(model.weights .- nw),6))"
        )
        push!(parts,lines)
    end
    lines = ["coefficients newton lambda $(fixed(lambda))"]
    for (j,name) in enumerate(vcat(["intercept"],data.feature_names))
        w = nw[j]
        se = sqrt(inf.matrix[j,j]/n)
        push!(
            lines,
            "$name weight $(fixed(w)) se $(fixed(se)) z $(fixed(w/se)) lower $(fixed(w-1.96*se)) upper $(fixed(w+1.96*se)) odds_ratio $(fixed(exp(w)))"
        )
    end
    push!(parts,lines)
    lines = ["model softmax lambda $(fixed(data.settings.softmax_lambda))"]
    for (k,w) in enumerate(softmax_model.weights)
        push!(lines,"class $(k-1)")
        append!(lines,term_lines(data,w))
    end
    push!(parts,lines)
    parts
end
function loss_trace_lines(data,models,multi,lambda)
    lines = ["optimizer,iteration,loss,gradient_norm,test_loss"]
    for model in models,(t,w) in model.checkpoints
        value = objective(w,data.train_vectors,data.train_targets,lambda)
        norm = vector_length(gradient(w,data.train_vectors,data.train_targets,lambda))
        test_loss = average_loss(w,data.test_vectors,data.test_targets)
        push!(lines,"$(model.name),$t,$(fixed(value,6)),$(fixed(norm,6)),$(fixed(test_loss,6))")
    end
    for (t,w) in multi.checkpoints
        value = softmax_objective(w,data.train_vectors,data.train_labels,data.settings.softmax_lambda)
        gradients = softmax_gradient(w,data.train_vectors,data.train_labels,data.settings.softmax_lambda)
        norm = vector_length(vcat(gradients...))
        test_loss = softmax_average_loss(w,data.test_vectors,data.test_labels)
        push!(lines,"softmax,$t,$(fixed(value,6)),$(fixed(norm,6)),$(fixed(test_loss,6))")
    end
    lines
end
function prediction_lines(data,models,multi)
    lines = ["id,model,probability,predicted,actual"]
    for model in models,(i,row) in enumerate(data.test)
        push!(
            lines,
            "$(row.id),$(model.name),$(fixed(model.test.probabilities[i],6)),$(model.test.predictions[i]),$(data.test_targets[i])"
        )
    end
    for (i,row) in enumerate(data.test)
        predicted = multi.test_predictions[i]
        push!(
            lines,
            "$(row.id),softmax,$(fixed(multi.test_probabilities[i][predicted+1],6)),$predicted,$(row.label)"
        )
    end
    lines
end
function roc_lines(data,models)
    pos = sum(data.test_targets)
    neg = length(data.test)-pos
    lines = ["model,threshold,tpr,fpr,precision"]
    for model in models
        push!(lines,"$(model.name),inf,0.0000,0.0000,-")
        for point in model.roc
            push!(
                lines,
                "$(model.name),$(fixed(point.threshold,6)),$(ratio(point.tp,pos)),$(ratio(point.fp,neg)),$(ratio(point.tp,point.tp+point.fp))"
            )
        end
    end
    lines
end
function data_part(data)
    n,m,d,k = length(data.train),length(data.test),length(data.names),data.classes
    train = join((count(==(c),data.train_labels) for c in 0:(k-1)),' ')
    test = join((count(==(c),data.test_labels) for c in 0:(k-1)),' ')
    [
        "data train $n test $m base_features $d degree $(data.settings.degree) features $(data.feature_count)",
        "binary positive_class $(data.settings.positive) train $(sum(data.train_targets))/$n test $(sum(data.test_targets))/$m",
        "classes $k train $train test $test"
    ]
end
function validation_part(data,results,selection)
    n = length(data.train)
    lines = ["cross_validation folds 5 newton_iterations 10"]
    for result in results
        folds = join((fixed(v,6) for v in result.fold_losses),' ')
        push!(
            lines,
            "lambda $(fixed(result.lambda)) fold_loss $folds cv_loss $(fixed(result.loss,6)) errors $(result.errors)/$n"
        )
    end
    best = selection.best
    push!(
        lines,
        "selected lambda $(fixed(best.lambda)) cv_loss $(fixed(best.loss,6)) se $(fixed(selection.se,6)) lambda_1se $(fixed(selection.one_se))"
    )
    c = confusion(predict(best.probabilities,data.settings.threshold),data.train_targets)
    push!(
        lines,
        "out_of_fold tp $(c.tp) fp $(c.fp) tn $(c.tn) fn $(c.fn) accuracy $(ratio(c.tp+c.tn,n)) auc $(fraction(auc(best.probabilities,data.train_targets)))"
    )
    lines
end
function lambda_path_part(data)
    lines = ["lambda_path"]
    for lambda in data.settings.lambdas
        w = final_weights(newton_method(data.train_vectors,data.train_targets,lambda))
        train = evaluate(w,data.train_vectors,data.train_targets,data.settings.threshold)
        test = evaluate(w,data.test_vectors,data.test_targets,data.settings.threshold)
        push!(
            lines,
            "lambda $(fixed(lambda)) objective $(fixed(objective(w,data.train_vectors,data.train_targets,lambda),6)) train_loss $(fixed(train.loss,6)) test_loss $(fixed(test.loss,6)) train_accuracy $(ratio(train.correct,length(data.train))) test_accuracy $(ratio(test.correct,length(data.test))) norm $(fixed(vector_length(w[2:end])))"
        )
    end
    lines
end
function degree_part(data,lambda)
    lines = ["degrees lambda $(fixed(lambda))"]
    for (degree,q) in enumerate(data.degree_counts)
        x,z = [v[1:(q+1)] for v in data.train_vectors],[v[1:(q+1)] for v in data.test_vectors]
        w = final_weights(newton_method(x,data.train_targets,lambda))
        cv = cross_validate(data,lambda,q)
        train = evaluate(w,x,data.train_targets,data.settings.threshold)
        test = evaluate(w,z,data.test_targets,data.settings.threshold)
        inf = influence(w,x,data.train_targets,lambda)
        push!(
            lines,
            "degree $degree features $q cv_loss $(fixed(cv.loss,6)) train_loss $(fixed(train.loss,6)) test_loss $(fixed(test.loss,6)) test_accuracy $(ratio(test.correct,length(data.test))) auc $(fraction(test.auc)) edf $(fixed(inf.edf)) aic $(fixed(inf.aic)) bic $(fixed(inf.bic))"
        )
    end
    lines
end
function learning_part(data,lambda)
    lines = ["learning_curve lambda $(fixed(lambda))"]
    for k in 1:4
        n = k*length(data.train)÷4
        stats = compute_statistics(data.train_expanded[1:n],data.feature_count)
        x = [standardize(v,stats,data.feature_count) for v in data.train_expanded[1:n]]
        z = [standardize(v,stats,data.feature_count) for v in data.test_expanded]
        y = data.train_targets[1:n]
        w = final_weights(newton_method(x,y,lambda))
        train,test = evaluate(w,x,y,data.settings.threshold),evaluate(
            w,
            z,
            data.test_targets,
            data.settings.threshold
        )
        push!(
            lines,
            "size $n train_loss $(fixed(train.loss,6)) test_loss $(fixed(test.loss,6)) test_accuracy $(ratio(test.correct,length(data.test))) auc $(fraction(test.auc))"
        )
    end
    lines
end
cost_of(p,pos,settings) = settings.cost_fp*p.fp+settings.cost_fn*(pos-p.tp)
function binary_part(data,model,lambda)
    y = data.test_targets
    m,pos = length(y),sum(y)
    neg = m-pos
    c = confusion(model.test.predictions,y)
    tp,fp,tn,fn = c.tp,c.fp,c.tn,c.fn
    brier = ordered_sum((v-t)*(v-t) for (v,t) in zip(model.test.probabilities,y))/m
    youden = model.roc[argmax([p.tp*neg-p.fp*pos for p in model.roc])]
    best_f1 = model.roc[1]
    for p in model.roc
        p.tp*(pos+best_f1.tp+best_f1.fp) > best_f1.tp*(pos+p.tp+p.fp) && (best_f1=p)
    end
    cheapest = model.roc[argmin([cost_of(p,pos,data.settings) for p in model.roc])]
    total,previous = 0.0,0
    for p in model.roc
        total += (p.tp-previous)*p.tp/(p.tp+p.fp)
        previous = p.tp
    end
    lines = [
        "model $(model.name) lambda $(fixed(lambda))",
        "train correct $(model.train.correct)/$(length(data.train)) accuracy $(ratio(model.train.correct,length(data.train)))",
        "test tp $tp fp $fp tn $tn fn $fn",
        "test accuracy $(ratio(tp+tn,m)) precision $(ratio(tp,tp+fp)) recall $(ratio(tp,tp+fn)) specificity $(ratio(tn,tn+fp)) f1 $(ratio(2tp,2tp+fp+fn))",
        "log_loss $(fixed(model.test.loss,6)) brier $(fixed(brier,6))",
        "auc $(fraction(model.test.auc)) average_precision $(fixed(total/pos))",
        "youden threshold $(fixed(youden.threshold,6)) tpr $(ratio(youden.tp,pos)) fpr $(ratio(youden.fp,neg)) j $(ratio(youden.tp*neg-youden.fp*pos,pos*neg))",
        "best_f1 threshold $(fixed(best_f1.threshold,6)) precision $(ratio(best_f1.tp,best_f1.tp+best_f1.fp)) recall $(ratio(best_f1.tp,pos)) f1 $(ratio(2*best_f1.tp,pos+best_f1.tp+best_f1.fp))",
        "min_cost threshold $(fixed(cheapest.threshold,6)) cost $(cost_of(cheapest,pos,data.settings)) fp $(cheapest.fp) fn $(pos-cheapest.tp)"
    ]
    append!(lines,calibration_lines(model.test.probabilities,y))
    append!(lines,gains_lines(model.test.probabilities,y))
    lines
end
function comparison_part(data,models)
    lines = String[]
    n = length(data.test)
    for (a,b) in ((1,2),(1,3),(2,3))
        first,second = models[a],models[b]
        only_first,only_second = 0,0
        for (x,z,y) in zip(first.test.predictions,second.test.predictions,data.test_targets)
            only_first += x == y && z != y
            only_second += z == y && x != y
        end
        gap = abs(only_first-only_second)-1
        push!(
            lines,
            "agreement $(first.name) $(second.name) same $(count_equal(first.test.predictions,second.test.predictions))/$n only_first $only_first only_second $only_second mcnemar $(ratio(gap*gap,only_first+only_second))"
        )
    end
    lines
end
function slope(tuples,original,values,base)
    total = 0.0
    for (j,indices) in enumerate(tuples)
        occurrences = count(==(base),indices)
        occurrences == 0 && continue
        remaining = copy(indices)
        deleteat!(remaining,findfirst(==(base),remaining))
        product = 1.0
        for index in remaining
            product *= values[index]
        end
        total += original[j+1]*(occurrences*product)
    end
    total
end
function diagnostics_part(data,model,inf,lambda)
    n,m = length(data.train),length(data.test)
    base_rate = sum(data.train_targets)/n
    null_loss = -(base_rate*log(base_rate)+(1-base_rate)*log(1-base_rate))
    lines = [
        "diagnostics newton lambda $(fixed(lambda))",
        "fit null_loss $(fixed(null_loss,6)) train_loss $(fixed(model.train.loss,6)) mcfadden_r2 $(fixed(1-model.train.loss/null_loss)) deviance $(fixed(inf.deviance)) edf $(fixed(inf.edf)) aic $(fixed(inf.aic)) bic $(fixed(inf.bic))"
    ]
    order = sortperm(eachindex(inf.probabilities),by=i->(inf.probabilities[i],i))
    statistic = 0.0
    groups = String[]
    for group in 1:10
        members = order[((group-1)*n÷10+1):(group*n÷10)]
        observed = sum(data.train_targets[members])
        expected = ordered_sum(inf.probabilities[members])
        statistic += (observed-expected)*(observed-expected)/(expected*(1-expected/length(members)))
        push!(groups,"group $group rows $(length(members)) observed $observed expected $(fixed(expected))")
    end
    push!(lines,"hosmer_lemeshow_train groups 10 statistic $(fixed(statistic))")
    append!(lines,groups)
    push!(lines,"newton_iterations")
    for t in 1:10
        w = model.checkpoints[t][2]
        g,step = newton_direction(w,data.train_vectors,data.train_targets,lambda)
        decrease = ordered_sum(a*b for (a,b) in zip(g,step))/2
        push!(
            lines,
            "iteration $t objective $(fixed(objective(w,data.train_vectors,data.train_targets,lambda),6)) gradient_norm $(fixed(vector_length(g),6)) step_norm $(fixed(vector_length(step),6)) predicted_decrease $(fixed(decrease,6))"
        )
    end
    original = original_units(model.weights,data.overall)
    centre = probability(score(model.weights,data_vector(data,data.mean_values)))
    for (base,name) in enumerate(data.names)
        total = ordered_sum(pi*(1-pi)*slope(
            data.tuples,
            original,
            row.values,
            base
        ) for (row,pi) in zip(data.train,inf.probabilities))
        at_mean = centre*(1-centre)*slope(data.tuples,original,data.mean_values,base)
        push!(lines,"marginal $name average $(fixed(total/n)) at_mean $(fixed(at_mean))")
    end
    for cut in 1:9
        c = confusion(predict(model.test.probabilities,cut/10),data.test_targets)
        push!(
            lines,
            "cut 0.$cut positive $(c.tp+c.fp) tp $(c.tp) fp $(c.fp) precision $(ratio(c.tp,c.tp+c.fp)) recall $(ratio(c.tp,c.tp+c.fn)) accuracy $(ratio(c.tp+c.tn,m))"
        )
    end
    wrong = [i for i in 1:m if model.test.predictions[i] != data.test_targets[i]]
    sort!(wrong,by=i->(-abs(model.test.probabilities[i]-data.settings.threshold),i))
    for i in wrong[1:min(5,length(wrong))]
        push!(
            lines,
            "error $(data.test[i].id) actual $(data.test_targets[i]) probability $(fixed(model.test.probabilities[i],6))"
        )
    end
    rng = Minstd(data.settings.bootstrap_seed)
    samples = Tuple{Int,Int}[]
    resamples = data.settings.bootstrap_count
    for _ in 1:resamples
        picks = [draw!(rng)%m+1 for _ in 1:m]
        push!(samples,auc(model.test.probabilities[picks],data.test_targets[picks]))
    end
    values = [a/b for (a,b) in samples]
    mean = ordered_sum(values)/resamples
    sd = sqrt(ordered_sum((v-mean)*(v-mean) for v in values)/(resamples-1))
    ordered = sort(samples,by=pair->pair[1]//pair[2])
    tail = resamples÷40
    push!(
        lines,
        "bootstrap resamples $resamples seed $(data.settings.bootstrap_seed) auc_mean $(fixed(mean)) auc_sd $(fixed(sd)) lower $(fraction(ordered[tail+1])) upper $(fraction(ordered[resamples-tail]))"
    )
    push!(
        lines,
        "influence effective_parameters $(fixed(inf.edf)) large_residuals $(count(v->abs(v)>2,inf.residuals))"
    )
    order = sortperm(eachindex(inf.distances),by=i->(-inf.distances[i],i))
    for i in order[1:min(5,n)]
        push!(
            lines,
            "cook $(data.train[i].id) actual $(data.train_targets[i]) probability $(fixed(inf.probabilities[i])) leverage $(fixed(inf.leverages[i])) residual $(fixed(inf.residuals[i])) distance $(fixed(inf.distances[i]))"
        )
    end
    lines
end
function importance_part(data,model,multi)
    settings = data.settings
    m,repeats = length(data.test),settings.permutation_count
    base_auc,denominator = model.test.auc
    baseline_correct = count_equal(multi.test_predictions,data.test_labels)
    lines = [
        "importance repeats $repeats seed $(settings.permutation_seed)",
        "baseline log_loss $(fixed(model.test.loss,6)) auc $(fraction(base_auc,denominator)) softmax_accuracy $(ratio(baseline_correct,m))"
    ]
    rng = Minstd(settings.permutation_seed)
    for (base,name) in enumerate(data.names)
        losses = Float64[]
        auc_total,correct_total = 0,0
        for _ in 1:repeats
            order = shuffle_order!(collect(1:m),rng)
            vectors = Vector{Float64}[]
            for j in 1:m
                values = copy(data.test[j].values)
                values[base] = data.test[order[j]].values[base]
                push!(vectors,data_vector(data,values))
            end
            push!(losses,average_loss(model.weights,vectors,data.test_targets))
            auc_total += auc(model_probabilities(model.weights,vectors),data.test_targets)[1]
            correct_total += softmax_correct(multi.weights,vectors,data.test_labels)
        end
        increase = ordered_sum(losses)/repeats-model.test.loss
        push!(
            lines,
            "feature $name log_loss_increase $(fixed(increase,6)) auc $(fraction(auc_total,repeats*denominator)) softmax_accuracy $(ratio(correct_total,repeats*m))"
        )
    end
    lines
end
function profile_part(data,model,multi)
    lines = ["profiles"]
    for (base,name) in enumerate(data.names)
        column = [row.values[base] for row in data.train]
        lo,hi = minimum(column),maximum(column)
        for step in 0:4
            values = copy(data.mean_values)
            values[base] = lo+(hi-lo)*step/4
            vector = data_vector(data,values)
            pi = probability(score(model.weights,vector))
            listed = join((fixed(v) for v in softmax_probabilities(multi.weights,vector)),' ')
            push!(lines,"profile $name value $(fixed(values[base])) newton $(fixed(pi)) softmax $listed")
        end
    end
    lines
end
function softmax_part(data,multi,newton)
    settings = data.settings
    m,k = length(data.test),data.classes
    table = zeros(Int,k,k)
    for (actual,predicted) in zip(data.test_labels,multi.test_predictions)
        table[actual+1,predicted+1] += 1
    end
    rows,columns = [sum(table[i,:]) for i in 1:k],[sum(table[:,i]) for i in 1:k]
    lines = [
        "softmax classes $k lambda $(fixed(settings.softmax_lambda)) iterations $(settings.softmax_iterations)",
        "confusion"
    ]
    append!(lines,[join(table[i,:],' ') for i in 1:k])
    for c in 0:(k-1)
        scores = [v[c+1] for v in multi.test_probabilities]
        targets = Int.(data.test_labels .== c)
        hits = table[c+1,c+1]
        push!(
            lines,
            "class $c precision $(ratio(hits,columns[c+1])) recall $(ratio(hits,rows[c+1])) f1 $(ratio(2*hits,columns[c+1]+rows[c+1])) auc $(fraction(auc(scores,targets)))"
        )
    end
    diagonal = sum(table[i,i] for i in 1:k)
    chance = sum(rows[i]*columns[i] for i in 1:k)
    push!(lines,"accuracy $(ratio(diagonal,m)) kappa $(ratio(m*diagonal-chance,m*m-chance))")
    brier = ordered_sum(ordered_sum((v[c+1]-Int(c == label))^2 for c in 0:(k-1)) for (v,label) in zip(
        multi.test_probabilities,
        data.test_labels
    ))/m
    push!(
        lines,
        "log_loss $(fixed(softmax_average_loss(multi.weights,data.test_vectors,data.test_labels),6)) brier $(fixed(brier,6))"
    )
    scores = [v[settings.positive+1] for v in multi.test_probabilities]
    binary_loss = ordered_sum(-log(y == 1 ? v : 1-v) for (v,y) in zip(scores,data.test_targets))/m
    predictions = predict(scores,settings.threshold)
    push!(
        lines,
        "binary_view positive_class $(settings.positive) auc $(fraction(auc(scores,data.test_targets))) log_loss $(fixed(binary_loss,6)) accuracy $(ratio(count_equal(predictions,data.test_targets),m)) agreement_with_newton $(count_equal(predictions,newton.test.predictions))/$m"
    )
    confidences = [v[p+1] for (v,p) in zip(multi.test_probabilities,multi.test_predictions)]
    bins = fill_bins(confidences,Int.(multi.test_predictions .== data.test_labels))
    push!(lines,"confidence")
    append!(lines,bin_lines(bins,"mean_confidence","accuracy"))
    push!(lines,"ece $(fixed(calibration_error(bins,m)))")
    lines
end
function one_vs_rest_part(data,multi)
    lambda = data.settings.softmax_lambda
    m = length(data.test)
    lines = ["one_vs_rest lambda $(fixed(lambda)) newton_iterations 10"]
    probabilities = Vector{Float64}[]
    for k in 0:(data.classes-1)
        y,z = Int.(data.train_labels .== k),Int.(data.test_labels .== k)
        w = final_weights(newton_method(data.train_vectors,y,lambda))
        test = evaluate(w,data.test_vectors,z,data.settings.threshold)
        push!(
            lines,
            "class $k objective $(fixed(objective(w,data.train_vectors,y,lambda),6)) auc $(fraction(test.auc))"
        )
        push!(probabilities,test.probabilities)
    end
    predictions = [argmax([v[j] for v in probabilities])-1 for j in 1:m]
    push!(
        lines,
        "accuracy $(ratio(count_equal(predictions,data.test_labels),m)) agreement_with_softmax $(count_equal(predictions,multi.test_predictions))/$m"
    )
    lines
end
function map_part(data,model,multi)
    width,height = data.settings.map_width,data.settings.map_height
    x,y = [r.values[1] for r in data.train],[r.values[2] for r in data.train]
    lo_x,hi_x,lo_y,hi_y = minimum(x),maximum(x),minimum(y),maximum(y)
    cells = zeros(Int,data.classes)
    class_rows,probability_rows = String[],String[]
    for r in 0:(height-1)
        class_row,probability_row = String[],String[]
        for c in 0:(width-1)
            values = copy(data.mean_values)
            values[1] = lo_x+(c+0.5)*(hi_x-lo_x)/width
            values[2] = hi_y-(r+0.5)*(hi_y-lo_y)/height
            vector = data_vector(data,values)
            predicted = predicted_class(softmax_probabilities(multi.weights,vector))
            cells[predicted+1] += 1
            push!(class_row,string(predicted))
            push!(probability_row,string(bin_index(probability(score(model.weights,vector)))))
        end
        push!(class_rows,join(class_row))
        push!(probability_rows,join(probability_row))
    end
    vcat(
        ["map $(data.names[1]) $(data.names[2]) width $width height $height","softmax_classes"],
        class_rows,
        ["cells "*join(cells,' '),"newton_probability"],
        probability_rows
    )
end
function join_parts(parts)
    lines = String[]
    for part in parts
        !isempty(lines) && push!(lines,"")
        append!(lines,part)
    end
    lines
end
function main()
    data = make_data(read_inputs()...)
    settings = data.settings
    results = [cross_validate(data,lambda,data.feature_count) for lambda in settings.lambdas]
    selection = select_lambda(results)
    lambda = selection.best.lambda
    x,y = data.train_vectors,data.train_targets
    gd = gradient_descent(x,y,lambda,settings.gd_rate,settings.gd_iterations)
    sgd = stochastic_gradient_descent(
        x,
        y,
        lambda,
        settings.sgd_rate,
        settings.batch_size,
        settings.epochs,
        settings.sgd_seed
    )
    newton = binary_model("newton",newton_method(x,y,lambda),data)
    models = [binary_model("gd",gd,data),binary_model("sgd",sgd,data),newton]
    checkpoints = softmax_train(
        x,
        data.train_labels,
        data.classes,
        settings.softmax_lambda,
        settings.softmax_rate,
        settings.softmax_iterations
    )
    w = final_weights(checkpoints)
    probabilities = [softmax_probabilities(w,v) for v in data.test_vectors]
    multi = (
        weights=w,
        checkpoints=checkpoints,
        test_probabilities=probabilities,
        test_predictions=predicted_class.(probabilities)
    )
    inf = influence(newton.weights,x,y,lambda)
    parts = [
        data_part(data),
        validation_part(data,results,selection),
        lambda_path_part(data),
        degree_part(data,lambda),
        learning_part(data,lambda)
    ]
    append!(parts,[binary_part(data,model,lambda) for model in models])
    append!(
        parts,
        [
            comparison_part(data,models),
            diagnostics_part(data,newton,inf,lambda),
            importance_part(data,newton,multi),
            profile_part(data,newton,multi),
            softmax_part(data,multi,newton),
            one_vs_rest_part(data,multi),
            map_part(data,newton,multi)
        ]
    )
    outputs = (
        ("weights.txt",join_parts(weights_parts(data,models,multi,inf,lambda))),
        ("loss_trace.csv",loss_trace_lines(data,models,multi,lambda)),
        ("predictions.csv",prediction_lines(data,models,multi)),
        ("evaluation.txt",join_parts(parts)),
        ("roc.csv",roc_lines(data,models))
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do io
            foreach(line->println(io,line),lines)
        end
    end
end
main()
