include("dataset.jl")
include("stumps.jl")
include("adaboost.jl")
include("variants.jl")
include("evaluation.jl")
mutable struct Minstd
    state::Int
end
function draw!(generator)
    generator.state = (48271generator.state)%2147483647
end
function train_variant(variant,rows,params)
    rounds = Int(params["ROUNDS"][1])
    variant=="discrete" && return train_discrete(rows,rounds)
    variant=="real" && return train_real(
        rows,
        rounds,
        Int(params["BINS"][1]),
        params["SMOOTHING"][1],
        params["CONVERGENCE"][1]
    )
    variant=="gentle" && return train_gentle(rows,rounds)
    train_logit(rows,rounds,params["CLIP"][1])
end
row_score(rounds,values) = ordered_sum(stump_output(r.stump,values) for r in rounds)
score_rows(rounds,rows) = [row_score(rounds,row.x) for row in rows]
magnitude(record) = maximum(abs,record.stump.values)
total_magnitude(rounds) = ordered_sum(magnitude(record) for record in rounds)
count_errors(rows,scores) = count(pair->prediction(pair[2])!=pair[1].label,zip(rows,scores))
function add_round_scores!(record,rows,scores)
    for (i,row) in enumerate(rows)
        scores[i] += stump_output(record.stump,row.x)
    end
end
function contributions(rounds,values,n)
    result = zeros(n)
    for record in rounds
        result[record.stump.feature] += stump_output(record.stump,values)
    end
    result
end
function loss(rows,scores,variant)
    ordered_sum(variant=="logit" ? log(1+exp(-2row.label*score)) : exp(-row.label*score) for (row,score) in zip(
        rows,
        scores
    ))/length(rows)
end
function metrics_line(kind,variant,rounds,rows,scores)
    tp = fp = tn = fn = 0
    for (row,score) in zip(rows,scores)
        p = prediction(score)
        tp += p==1 && row.label==1
        fp += p==1 && row.label==-1
        tn += p==-1 && row.label==-1
        fn += p==-1 && row.label==1
    end
    a,b = auc(rows,scores)
    "$kind $variant rounds $rounds correct $(tp+tn)/$(length(rows)) accuracy $(ratio(tp+tn,length(rows))) tp $tp fp $fp tn $tn fn $fn precision $(ratio(tp,tp+fp)) recall $(ratio(tp,tp+fn)) f1 $(ratio(2tp,2tp+fp+fn)) auc $(ratio(a,b)) loss $(number(loss(rows,scores,variant)))"
end
function training_curve(rounds,training,testing,variant)
    train_scores,test_scores = zeros(length(training)),zeros(length(testing))
    scale = 0.0
    curve = NamedTuple[]
    for (t,record) in enumerate(rounds)
        add_round_scores!(record,training,train_scores)
        add_round_scores!(record,testing,test_scores)
        scale += magnitude(record)
        minimum_margin = minimum(row.label*score for (row,score) in zip(training,train_scores))/scale
        push!(curve,(round=t,train_errors=count_errors(training,train_scores),test_errors=count_errors(testing,test_scores),
            train_loss=loss(
                training,
                train_scores,
                variant
            ),test_loss=loss(testing,test_scores,variant),margin=minimum_margin))
    end
    curve
end
function cross_validate(rows,params)
    space = search_space(rows)
    max_rounds,k = Int(params["ROUNDS"][1]),Int(params["FOLDS"][1])
    folds = NamedTuple[]
    errors = zeros(Int,max_rounds)
    for fold in 0:k-1
        indices = [i for i in eachindex(rows) if (i-1)%k==fold]
        n = length(rows)-length(indices)
        weights = [(i-1)%k==fold ? 0.0 : 1/n for i in eachindex(rows)]
        model = train_discrete(rows,max_rounds;weights=weights,space=space)
        validation = rows[indices]
        scores = zeros(length(indices))
        fold_errors = Int[]
        for t in 1:max_rounds
            t<=length(model.rounds) && add_round_scores!(model.rounds[t],validation,scores)
            count = count_errors(validation,scores)
            push!(fold_errors,count)
            errors[t] += count
        end
        push!(folds,(indices=indices,train=n,model=model,errors=fold_errors))
    end
    selected = argmin(errors)
    scores = zeros(length(rows))
    for fold in folds
        rounds = fold.model.rounds[1:min(selected,length(fold.model.rounds))]
        for i in fold.indices
            scores[i] = row_score(rounds,rows[i].x)
        end
    end
    (folds=folds,errors=errors,selected=selected,scores=scores)
end
function magnitude_importance(rounds,n;samme=false)
    scores,counts = zeros(n),zeros(Int,n)
    for record in rounds
        j = record.stump.feature
        scores[j] += samme ? record.alpha : magnitude(record)
        counts[j] += 1
    end
    (scores=scores,counts=counts,total=ordered_sum(scores),order=sort(collect(1:n);by=j->(-scores[j],j)))
end
function importance_lines(importance,features)
    lines = ["importance"]
    for (rank,j) in enumerate(importance.order)
        push!(
            lines,
            "$rank $(features[j]) score $(number(importance.scores[j])) share $(ratio(importance.scores[j],importance.total)) rounds $(importance.counts[j])"
        )
    end
    lines
end
function analyze_variants(inputs,selected)
    analysis = Dict{String,Any}()
    for variant in inputs.params["VARIANTS"]
        model = train_variant(variant,inputs.train,inputs.params)
        rounds = variant=="discrete" ? model.rounds[1:min(selected,length(model.rounds))] : model.rounds
        analysis[variant] = (full=model,rounds=rounds,scale=total_magnitude(rounds),train=score_rows(rounds,inputs.train),
            test=score_rows(rounds,inputs.test),curve=training_curve(
                model.rounds,
                inputs.train,
                inputs.test,
                variant
            ),
            importance=magnitude_importance(rounds,length(inputs.features)))
    end
    analysis
end
function ensemble_lines(inputs,analysis,cv)
    params = inputs.params
    lines = String[]
    for variant in params["VARIANTS"]
        isempty(lines) || push!(lines,"")
        model = analysis[variant].full
        header = "variant $variant rounds $(length(model.rounds)) stop $(model.stop)"
        variant=="real" && (header*=" bins $(Int(params["BINS"][1])) smoothing $(number(params["SMOOTHING"][1])) convergence $(number(params["CONVERGENCE"][1],6))")
        variant=="logit" && (header*=" clip $(number(params["CLIP"][1]))")
        push!(lines,header)
        if variant=="real"
            for (name,cuts) in zip(inputs.features,model.cuts)
                push!(lines,"cuts $name "*join(number.(cuts)," "))
            end
        end
        for (t,record) in enumerate(model.rounds)
            stump = record.stump
            line = "round $t feature $(inputs.features[stump.feature])"
            if variant=="real"
                line *= " z $(number(record.z)) bound $(number(record.bound)) values "*join(
                    number.(stump.values),
                    " "
                )
            else
                line *= " threshold $(number(stump.thresholds[1]))"
                if variant=="discrete"
                    line *= " polarity $(record.polarity) error $(number(record.error)) alpha $(number(record.alpha)) z $(number(record.z)) bound $(number(record.bound))"
                else
                    line *= " left $(number(stump.values[1])) right $(number(stump.values[2])) error $(number(record.error))"
                    variant=="logit" && (line*=" loss $(number(record.loss))")
                end
            end
            push!(lines,line)
            if variant=="discrete"
                maximum_index = argmax(record.weights)
                ess = 1/ordered_sum(w*w for w in record.weights)
                push!(
                    lines,
                    "weights $t max $(number(record.weights[maximum_index],6)) id $(inputs.train[maximum_index].id) ess $(number(ess))"
                )
            end
        end
        if variant=="discrete"
            t = cv.selected
            push!(
                lines,
                "cv folds $(Int(params["FOLDS"][1])) selected $t errors $(cv.errors[t])/$(length(inputs.train))"
            )
            for (phi,fold) in enumerate(cv.folds)
                validation = length(fold.indices)
                push!(
                    lines,
                    "fold $phi train $(fold.train) validation $validation rounds $(length(fold.model.rounds)) stop $(fold.model.stop) selected $(fold.errors[t])/$validation final $(fold.errors[end])/$validation"
                )
            end
            push!(lines,"cv_errors "*join(cv.errors," "))
        end
    end
    lines
end
function prediction_lines(inputs,analysis)
    lines = ["id,variant,score,label,"*join(inputs.features,",")]
    for (i,row) in enumerate(inputs.test),variant in inputs.params["VARIANTS"]
        result = analysis[variant]
        score = result.test[i]
        parts = contributions(result.rounds,row.x,length(inputs.features))
        push!(lines,"$(row.id),$variant,$(number(score)),$(prediction(score)),"*join(number.(parts),","))
    end
    lines
end
function roc_lines(inputs,analysis)
    lines = ["variant,threshold,tp,fp"]
    for variant in inputs.params["VARIANTS"]
        scores = analysis[variant].test
        for threshold in sort(unique(scores);rev=true)
            tp = count(i->scores[i]>=threshold && inputs.test[i].label==1,eachindex(scores))
            fp = count(i->scores[i]>=threshold && inputs.test[i].label==-1,eachindex(scores))
            push!(lines,"$variant,$(number(threshold)),$tp,$fp")
        end
    end
    lines
end
function permutation_importance(rounds,rows,n,repeats,generator)
    base = length(rows)-count_errors(rows,score_rows(rounds,rows))
    results = []
    for j in 1:n
        counts = Int[]
        for _ in 1:repeats
            permutation = collect(eachindex(rows))
            for i in length(rows):-1:2
                other = draw!(generator)%i+1
                permutation[i],permutation[other] = permutation[other],permutation[i]
            end
            correct = 0
            for (i,row) in enumerate(rows)
                values = copy(row.x)
                values[j] = rows[permutation[i]].x[j]
                correct += prediction(row_score(rounds,values))==row.label
            end
            push!(counts,correct)
        end
        push!(results,(j,sum(base-c for c in counts),minimum(counts),maximum(counts)))
    end
    sort!(results;by=result->(-result[2],result[1]))
    base,results
end
function margin_lines(inputs,analysis)
    lines = String[]
    repeats,seed = Int.(inputs.params["PERMUTATION"])
    generator = Minstd(seed)
    n,m = length(inputs.train),length(inputs.test)
    for variant in inputs.params["VARIANTS"]
        isempty(lines) || push!(lines,"")
        r = analysis[variant]
        train_margins = [row.label*score/r.scale for (row,score) in zip(inputs.train,r.train)]
        test_margins = [row.label*score/r.scale for (row,score) in zip(inputs.test,r.test)]
        push!(lines,"variant $variant rounds $(length(r.rounds)) scale $(number(r.scale))",
            "train min $(number(minimum(train_margins))) mean $(number(ordered_sum(train_margins)/n))")
        for theta in inputs.params["MARGINS"]
            c = count_at_most(train_margins,theta)
            push!(lines,"train le $(number(theta)) $c/$n $(ratio(c,n))")
        end
        histogram = zeros(Int,20)
        for margin in train_margins
            histogram[min(19,floor(Int,(margin+1)*10))+1] += 1
        end
        push!(lines,"histogram "*join(histogram," "))
        hardest = sort(collect(1:n);by=i->(train_margins[i],i))[1:min(5,n)]
        for i in hardest
            row = inputs.train[i]
            push!(lines,"hardest $(row.id) label $(row.label) margin $(number(train_margins[i]))")
        end
        push!(lines,"test min $(number(minimum(test_margins))) mean $(number(ordered_sum(test_margins)/m))")
        for theta in inputs.params["MARGINS"]
            c = count_at_most(test_margins,theta)
            push!(lines,"test le $(number(theta)) $c/$m $(ratio(c,m))")
        end
        for theta in inputs.params["MARGINS"]
            confident = [i for i in 1:m if abs(test_margins[i])>theta]
            c = count(i->prediction(r.test[i])==inputs.test[i].label,confident)
            push!(
                lines,
                "test confident $(number(theta)) $(length(confident))/$m correct $c/$(length(confident)) $(ratio(c,length(confident)))"
            )
        end
        append!(lines,importance_lines(r.importance,inputs.features))
        base,permutation = permutation_importance(
            r.rounds,
            inputs.test,
            length(inputs.features),
            repeats,
            generator
        )
        push!(lines,"permutation repeats $repeats base $base/$m")
        for (rank,(j,drop,lo,hi)) in enumerate(permutation)
            push!(lines,"$rank $(inputs.features[j]) drop $(ratio(drop,repeats*m)) min $lo/$m max $hi/$m")
        end
    end
    lines
end
function shape_lines(inputs,analysis)
    lines = String[]
    for variant in inputs.params["VARIANTS"]
        isempty(lines) || push!(lines,"")
        rounds = analysis[variant].rounds
        push!(lines,"variant $variant rounds $(length(rounds))")
        for (j,name) in enumerate(inputs.features)
            collected = [record for record in rounds if record.stump.feature==j]
            cuts = sort(unique([cut for record in collected for cut in record.stump.thresholds]))
            values = [ordered_sum(record.stump.values[1] for record in collected)]
            for cut in cuts
                push!(
                    values,
                    ordered_sum(record.stump.values[count(
                        <=(cut),
                        record.stump.thresholds
                    )+1] for record in collected)
                )
            end
            push!(
                lines,
                "feature $name rounds $(length(collected)) cuts $(length(cuts)) range $(number(maximum(values)-minimum(values)))"
            )
            for (i,value) in enumerate(values)
                lower,upper = i==1 ? "-inf" : number(cuts[i-1]),i>length(cuts) ? "inf" : number(cuts[i])
                push!(lines,"interval $lower $upper value $(number(value))")
            end
        end
    end
    lines
end
function calibration_lines(variant,rows,scores)
    counts,positive,totals = zeros(Int,5),zeros(Int,5),zeros(5)
    brier = 0.0
    for (row,score) in zip(rows,scores)
        p = 1/(1+exp(-2score))
        target = row.label==1 ? 1 : 0
        brier += (p-target)*(p-target)
        i = min(4,floor(Int,p*5))+1
        counts[i] += 1
        totals[i] += p
        positive[i] += target
    end
    lines = ["calibration $variant brier $(number(brier/length(rows)))"]
    ranges = ("0.0-0.2","0.2-0.4","0.4-0.6","0.6-0.8","0.8-1.0")
    append!(
        lines,
        ["bin $(ranges[i]) count $(counts[i]) mean $(ratio(totals[i],counts[i])) positives $(positive[i])" for i in 1:5]
    )
    lines
end
function bootstrap_lines(inputs,analysis)
    samples,seed = Int.(inputs.params["BOOTSTRAP"])
    generator = Minstd(seed)
    variants = inputs.params["VARIANTS"]
    m = length(inputs.test)
    counts = Dict(v=>Int[] for v in variants)
    correct = Dict(v=>[prediction(analysis[v].test[i])==inputs.test[i].label for i in 1:m] for v in variants)
    for _ in 1:samples
        selected = [draw!(generator)%m+1 for _ in 1:m]
        for variant in variants
            push!(counts[variant],sum(correct[variant][selected]))
        end
    end
    lines = ["bootstrap samples $samples seed $seed"]
    trim = samples÷40
    for variant in variants
        ordered = sort(counts[variant])
        push!(
            lines,
            "$variant mean $(ratio(sum(counts[variant]),samples*m)) low $(ratio(ordered[trim+1],m)) high $(ratio(ordered[end-trim],m))"
        )
    end
    for a in 1:length(variants)-1,b in a+1:length(variants)
        first,second = variants[a],variants[b]
        wins = count(counts[first].>counts[second])
        ties = count(counts[first].==counts[second])
        push!(lines,"$first $second first $wins tie $ties second $(samples-wins-ties)")
    end
    lines
end
function feature_summary(rows,j)
    values = [row.x[j] for row in rows]
    "$(number(minimum(values))) $(number(maximum(values))) $(number(ordered_sum(values)/length(values))) $(length(unique(values)))"
end
function summary_lines(inputs,analysis,cv)
    training,testing,params = inputs.train,inputs.test,inputs.params
    n,m = length(training),length(testing)
    variants = params["VARIANTS"]
    lines = ["data train $n test $m features $(length(inputs.features)) positives $(count(row->row.label==1,training)) $(count(row->row.label==1,testing))"]
    append!(
        lines,
        ["feature $name train $(feature_summary(training,j)) test $(feature_summary(testing,j))" for (
            j,
            name
        ) in enumerate(inputs.features)]
    )
    t = cv.selected
    push!(
        lines,
        "cv selected $t errors $(cv.errors[t])/$n rate $(ratio(cv.errors[t],n))",
        metrics_line("oof","discrete",t,training,cv.scores)
    )
    committee_train,committee_test = zeros(n),zeros(m)
    committee_rounds = 0
    for variant in variants
        r = analysis[variant]
        rounds = length(r.rounds)
        push!(
            lines,
            metrics_line("train",variant,rounds,training,r.train),
            metrics_line("test",variant,rounds,testing,r.test)
        )
        committee_rounds += rounds
        committee_train .+= r.train./r.scale
        committee_test .+= r.test./r.scale
    end
    push!(
        lines,
        metrics_line("train","committee",committee_rounds,training,committee_train),
        metrics_line("test","committee",committee_rounds,testing,committee_test)
    )
    for variant in variants
        curve = analysis[variant].curve
        a = curve[argmin([point.train_errors for point in curve])]
        b = curve[argmin([point.test_errors for point in curve])]
        push!(
            lines,
            "curve $variant rounds $(length(curve)) train_min $(a.train_errors)/$n at $(a.round) test_min $(b.test_errors)/$m at $(b.round)"
        )
    end
    predictions = Dict(v=>prediction.(analysis[v].test) for v in variants)
    wrong = [testing[i].id for i in 1:m if all(predictions[v][i]!=testing[i].label for v in variants)]
    push!(lines,"all_wrong $(length(wrong))"*(isempty(wrong) ? "" : " "*join(wrong," ")),"agreement")
    for a in 1:length(variants)-1,b in a+1:length(variants)
        first,second = variants[a],variants[b]
        agree = count(predictions[first].==predictions[second])
        only_first = count(
            i->predictions[first][i]==testing[i].label && predictions[second][i]!=testing[i].label,
            1:m
        )
        only_second = count(
            i->predictions[second][i]==testing[i].label && predictions[first][i]!=testing[i].label,
            1:m
        )
        difference = abs(only_first-only_second)-1
        push!(
            lines,
            "$first $second agree $agree/$m only_first $only_first only_second $only_second chi2 $(ratio(difference*difference,only_first+only_second))"
        )
    end
    append!(lines,bootstrap_lines(inputs,analysis))
    for variant in variants
        append!(lines,calibration_lines(variant,testing,analysis[variant].test))
    end
    lines
end
class_errors(rows,predictions) = count(pair->pair[1].label!=pair[2],zip(rows,predictions))
function confusion_lines(rows,predictions,classes)
    matrix = confusion(rows,predictions,classes)
    lines = ["confusion"]
    append!(lines,[join(matrix[i,:]," ") for i in 1:classes])
    for i in 1:classes
        push!(
            lines,
            "class $i precision $(ratio(matrix[i,i],sum(matrix[:,i]))) recall $(ratio(matrix[i,i],sum(matrix[i,:])))"
        )
    end
    lines
end
function multiclass_report(inputs)
    training,testing,params = inputs.multi_train,inputs.multi_test,inputs.params
    classes,max_rounds = Int(params["CLASSES"][1]),Int(params["SAMME_ROUNDS"][1])
    model = train_samme(training,max_rounds,classes)
    train_scores,test_scores = zeros(length(training),classes),zeros(length(testing),classes)
    curve = Tuple{Int,Int,Int}[]
    for (t,record) in enumerate(model.rounds)
        for (rows,scores) in ((training,train_scores),(testing,test_scores))
            for (i,row) in enumerate(rows)
                scores[i,Int(stump_output(record.stump,row.x))] += record.alpha
            end
        end
        push!(
            curve,
            (
                t,
                class_errors(training,[argmax(train_scores[i,:]) for i in eachindex(training)]),
                class_errors(testing,[argmax(test_scores[i,:]) for i in eachindex(testing)])
            )
        )
    end
    train_predictions = [argmax(train_scores[i,:]) for i in eachindex(training)]
    test_predictions = [argmax(test_scores[i,:]) for i in eachindex(testing)]
    lines = ["samme classes $classes train $(length(training)) test $(length(testing)) rounds $(length(model.rounds)) stop $(model.stop)"]
    for (t,record) in enumerate(model.rounds)
        stump = record.stump
        push!(
            lines,
            "round $t feature $(inputs.multi_features[stump.feature]) threshold $(number(stump.thresholds[1])) left $(Int(stump.values[1])) right $(Int(stump.values[2])) error $(number(record.error)) alpha $(number(record.alpha))"
        )
    end
    for (kind,rows,predictions) in (("train",training,train_predictions),("test",testing,test_predictions))
        errors = class_errors(rows,predictions)
        push!(lines,"$kind errors $errors/$(length(rows)) rate $(ratio(errors,length(rows)))")
    end
    append!(lines,confusion_lines(testing,test_predictions,classes))
    append!(
        lines,
        importance_lines(
            magnitude_importance(model.rounds,length(inputs.multi_features);samme=true),
            inputs.multi_features
        )
    )
    push!(lines,"","ovr classes $classes rounds $max_rounds")
    ovr_train,ovr_test = zeros(length(training),classes),zeros(length(testing),classes)
    for c in 1:classes
        binary_train = [(;row...,label=row.label==c ? 1 : -1) for row in training]
        binary_test = [(;row...,label=row.label==c ? 1 : -1) for row in testing]
        binary = train_discrete(binary_train,max_rounds)
        a,b = score_rows(binary.rounds,binary_train),score_rows(binary.rounds,binary_test)
        ovr_train[:,c],ovr_test[:,c] = a,b
        positives = count(row->row.label==c,training)
        push!(
            lines,
            "class $c rounds $(length(binary.rounds)) stop $(binary.stop) positives $positives train_errors $(count_errors(binary_train,a))/$(length(training)) test_errors $(count_errors(binary_test,b))/$(length(testing))"
        )
    end
    ovr_train_predictions = [argmax(ovr_train[i,:]) for i in eachindex(training)]
    ovr_test_predictions = [argmax(ovr_test[i,:]) for i in eachindex(testing)]
    for (kind,rows,predictions) in (
        ("train",training,ovr_train_predictions),
        ("test",testing,ovr_test_predictions)
    )
        errors = class_errors(rows,predictions)
        push!(lines,"$kind errors $errors/$(length(rows)) rate $(ratio(errors,length(rows)))")
    end
    append!(lines,confusion_lines(testing,ovr_test_predictions,classes))
    push!(
        lines,
        "agreement $(count(test_predictions.==ovr_test_predictions))/$(length(testing))",
        "",
        "predictions"
    )
    for (i,row) in enumerate(testing)
        push!(
            lines,
            "$(row.id) class $(row.label) samme $(test_predictions[i]) ovr $(ovr_test_predictions[i]) scores "*join(
                number.(test_scores[i,:]),
                " "
            )
        )
    end
    lines,curve
end
function test_minimum(rounds,testing)
    scores = zeros(length(testing))
    counts = Int[]
    for record in rounds
        add_round_scores!(record,testing,scores)
        push!(counts,count_errors(testing,scores))
    end
    index = argmin(counts)
    counts[index],index
end
function experiment_lines(inputs,analysis,selected)
    training,testing,params = inputs.train,inputs.test,inputs.params
    n,m = length(training),length(testing)
    lines = String[]
    for q in Int.(params["SIZES"])
        size = fld(n*q,100)
        subset = training[1:size]
        push!(lines,"size $q rows $size")
        for variant in params["VARIANTS"]
            model = train_variant(variant,subset,params)
            a,b = count_errors(subset,score_rows(model.rounds,subset)),count_errors(
                testing,
                score_rows(model.rounds,testing)
            )
            push!(
                lines,
                "$variant rounds $(length(model.rounds)) stop $(model.stop) train_errors $a/$size test_errors $b/$m"
            )
        end
    end
    for nu in params["SHRINKAGE"]
        model = train_discrete(training,Int(params["ROUNDS"][1]);shrinkage=nu)
        a,b = count_errors(
            training,
            score_rows(model.rounds,training)
        ),count_errors(testing,score_rows(model.rounds,testing))
        minimum_error,at = test_minimum(model.rounds,testing)
        push!(
            lines,
            "shrinkage $(number(nu)) rounds $(length(model.rounds)) stop $(model.stop) train_errors $a/$n test_errors $b/$m test_min $minimum_error/$m at $at"
        )
    end
    ranked = analysis["discrete"].importance.order
    for k in eachindex(inputs.features)
        features = sort(ranked[1:k])
        a = [(;row...,x=row.x[features]) for row in training]
        b = [(;row...,x=row.x[features]) for row in testing]
        model = train_discrete(a,selected)
        train_errors,test_errors = count_errors(a,score_rows(model.rounds,a)),count_errors(
            b,
            score_rows(model.rounds,b)
        )
        push!(
            lines,
            "top $k features $(join(inputs.features[features]," ")) rounds $(length(model.rounds)) train_errors $train_errors/$n test_errors $test_errors/$m"
        )
    end
    for q in Int.(params["NOISE"][2:end])
        f = fld(n*q,100)
        generator = Minstd(Int(params["NOISE"][1]))
        permutation = collect(1:n)
        for i in 1:f
            other = draw!(generator)%(n-i+1)+i
            permutation[i],permutation[other] = permutation[other],permutation[i]
        end
        flipped = Set(permutation[1:f])
        noisy = [(;row...,label=i in flipped ? -row.label : row.label) for (i,row) in enumerate(training)]
        push!(lines,"noise $q flipped $f")
        for variant in params["VARIANTS"]
            model = train_variant(variant,noisy,params)
            a,b = count_errors(noisy,score_rows(model.rounds,noisy)),count_errors(
                testing,
                score_rows(model.rounds,testing)
            )
            minimum_error,at = test_minimum(model.rounds,testing)
            flipped_weight = ordered_sum(model.rounds[end].weights[i] for i in 1:n if i in flipped)
            push!(
                lines,
                "$variant rounds $(length(model.rounds)) stop $(model.stop) train_errors $a/$n test_errors $b/$m test_min $minimum_error/$m at $at flipped_weight $(number(flipped_weight))"
            )
        end
    end
    lines
end
function error_curve_lines(inputs,analysis,samme_curve)
    lines = ["variant,round,train_error,test_error,train_loss,test_loss,min_margin"]
    for variant in inputs.params["VARIANTS"],point in analysis[variant].curve
        push!(
            lines,
            "$variant,$(point.round),$(ratio(point.train_errors,length(inputs.train))),$(ratio(point.test_errors,length(inputs.test))),$(number(point.train_loss)),$(number(point.test_loss)),$(number(point.margin))"
        )
    end
    for (t,a,b) in samme_curve
        push!(
            lines,
            "samme,$t,$(ratio(a,length(inputs.multi_train))),$(ratio(b,length(inputs.multi_test))),-,-,-"
        )
    end
    lines
end
function main()
    inputs = read_inputs()
    cv = cross_validate(inputs.train,inputs.params)
    analysis = analyze_variants(inputs,cv.selected)
    samme,samme_curve = multiclass_report(inputs)
    reports = Dict("ensemble.txt"=>ensemble_lines(inputs,analysis,cv),"error_curve.csv"=>error_curve_lines(inputs,analysis,samme_curve),
        "predictions.csv"=>prediction_lines(inputs,analysis),"roc.csv"=>roc_lines(inputs,analysis),"margins.txt"=>margin_lines(
            inputs,
            analysis
        ),
        "shapes.txt"=>shape_lines(inputs,analysis),"samme.txt"=>samme,"summary.txt"=>summary_lines(
            inputs,
            analysis,
            cv
        ),
        "experiments.txt"=>experiment_lines(inputs,analysis,cv.selected))
    for (name,lines) in reports
        write_lines(name,lines)
    end
end
main()
