include("evaluation.jl")
include("kernels.jl")
include("dataset.jl")
include("smo.jl")
include("multiclass.jl")
function support_counts(model)
    total = count(>(0),model.alpha)
    bound = count(alpha->alpha>0 && alpha==model.C,model.alpha)
    total,bound,total-bound
end
function support_text(model)
    total,bound,free = support_counts(model)
    "support_vectors $total bound $bound free $free"
end
run_info(model) = "passes $(passes(model)) steps $(model.steps) converged $(model.converged ? "yes" : "no")"
function objectives(model,alpha=model.alpha)
    scores = Float64[]
    for i in eachindex(alpha)
        total = 0.0
        for (j,coefficient) in enumerate(alpha)
            coefficient>0 && (total+=coefficient*model.labels[j]*model.matrix[i,j])
        end
        push!(scores,total)
    end
    quadratic,total = 0.0,0.0
    for (i,coefficient) in enumerate(alpha)
        quadratic += coefficient*model.labels[i]*scores[i]
        total += coefficient
    end
    quadratic,total-quadratic/2
end
ranking_key(result) = (-result.correct,result.C,result.kernel_index)
function cross_validate(training,settings)
    points,labels = [example.point for example in training],[example.label for example in training]
    partitions = folds(length(training),settings["folds"])
    matrices,combinations,best = Matrix{Float64}[],NamedTuple[],NamedTuple[]
    for (ki,kernel) in enumerate(settings["kernels"])
        matrix = kernel_matrix(kernel,points)
        push!(matrices,matrix)
        candidates = NamedTuple[]
        for C in settings["c_grid"]
            values,fold_results = zeros(length(training)),NamedTuple[]
            correct,support,pass_count,steps = 0,0,0,0
            for (fitting,testing) in partitions
                model = train_model(
                    points[fitting],
                    labels[fitting],
                    kernel,
                    submatrix(matrix,fitting),
                    C,
                    settings
                )
                fold_correct = 0
                for i in testing
                    values[i] = decision(model,points[i])
                    fold_correct += svm_sign(values[i])==labels[i]
                end
                sv = support_counts(model)[1]
                push!(
                    fold_results,
                    (train=length(fitting),test=length(testing),correct=fold_correct,support=sv,model=model)
                )
                correct += fold_correct
                support += sv
                pass_count += passes(model)
                steps += model.steps
            end
            result = (
                kernel=kernel,
                kernel_index=ki,
                C=C,
                values=values,
                folds=fold_results,
                correct=correct,
                support=support,
                passes=pass_count,
                steps=steps
            )
            push!(candidates,result)
            push!(combinations,result)
        end
        push!(best,sort(candidates;by=ranking_key)[1])
    end
    matrices,combinations,best,sort(best;by=ranking_key)[1],sort(combinations;by=ranking_key)
end
function cross_validation_lines(n,k,best,selected,ranking)
    lines = ["cross_validation folds $k examples $n"]
    for result in best
        push!(
            lines,
            "best $(result.kernel.name) C $(fixed_text(result.C)) correct $(result.correct)/$n accuracy $(ratio(result.correct,n))"
        )
    end
    push!(lines,"selected $(selected.kernel.name) C $(fixed_text(selected.C))","ranking")
    for (rank,result) in enumerate(ranking)
        push!(lines,"$rank $(result.kernel.name) C $(fixed_text(result.C)) correct $(result.correct)/$n")
    end
    push!(lines,"cv_detail $(selected.kernel.name) C $(fixed_text(selected.C))")
    for (f,result) in enumerate(selected.folds)
        push!(
            lines,
            "fold $f train $(result.train) test $(result.test) correct $(result.correct) support_vectors $(result.support) $(run_info(result.model))"
        )
    end
    lines
end
function evaluate_final(model,training,testing,tolerance)
    n,m = length(training),length(testing)
    train_values,test_values = training_decisions(model),[decision(
        model,
        example.point
    ) for example in testing]
    test_labels = [example.label for example in testing]
    quadratic,dual = objectives(model)
    label_alignment,matrix_squares = 0.0,0.0
    for i in 1:n,j in 1:n
        value = model.matrix[i,j]
        label_alignment += model.labels[i]*model.labels[j]*value
        matrix_squares += value*value
    end
    alignment = label_alignment/(n*sqrt(matrix_squares))
    equality,w1,w2 = 0.0,0.0,0.0
    class_counts = zeros(Int,2,2)
    for (example,alpha) in zip(training,model.alpha)
        equality += alpha*example.label
        if model.kernel.kind=="linear"
            w1 += alpha*example.label*example.point[1]
            w2 += alpha*example.label*example.point[2]
        end
        alpha>0 && (class_counts[example.label==1 ? 1 : 2,alpha==model.C ? 1 : 2]+=1)
    end
    norm_value = sqrt(quadratic)
    radius = maximum(model.matrix[i,i] for i in 1:n)-minimum(model.matrix)
    hinge_total,largest = 0.0,0.0
    violations,estimated = 0,0
    for (alpha,label,value) in zip(model.alpha,model.labels,train_values)
        hinge = max(0.0,1-label*value)
        hinge_total += hinge
        residual = label*value-1
        violation = alpha==0 ? max(0.0,-residual) : alpha==model.C ? max(0.0,residual) : abs(residual)
        violations += violation>tolerance
        largest = max(largest,violation)
        estimated += 2alpha*radius+hinge>=1
    end
    primal = quadratic/2+model.C*hinge_total
    train_correct = correct_count(model.labels,train_values)
    tp,fp,tn,fn = binary_counts(test_labels,test_values)
    inside = count(value->abs(value)<1,test_values)
    positive = ordered_sum(value for (label,value) in zip(test_labels,test_values) if label==1)/(tp+fn)
    negative = ordered_sum(value for (label,value) in zip(test_labels,test_values) if label==-1)/(fp+tn)
    lines = ["model $(model.kernel.name)","kernel $(kernel_description(model.kernel))","C $(fixed_text(model.C))","alignment $(fixed_text(alignment,6))",
        "passes $(passes(model)) full $(model.full_passes) nonbound $(model.nonbound_passes) converged $(model.converged ? "yes" : "no")","examined $(model.examined) steps $(model.steps)",
        "choice heuristic $(model.choices[1]) nonbound_loop $(model.choices[2]) full_loop $(model.choices[3])","clipping none $(model.clipping[1]) lower $(model.clipping[2]) upper $(model.clipping[3])",
        support_text(model),"b $(fixed_text(model.b,6))","equality $(fixed_text(equality,6))"]
    model.kernel.kind=="linear" && push!(lines,"w $(fixed_text(w1,6)) $(fixed_text(w2,6))")
    append!(lines,["sv_by_class positive bound $(class_counts[1,1]) free $(class_counts[1,2]) negative bound $(class_counts[2,1]) free $(class_counts[2,2])",
        "norm $(fixed_text(norm_value,6)) margin $(fixed_text(2/norm_value,6))","dual_objective $(fixed_text(dual,6))","primal_objective $(fixed_text(primal,6))","duality_gap $(fixed_text(primal-dual,6))",
        "kkt_violations $violations max $(fixed_text(largest,6))","xi_alpha radius $(fixed_text(radius,6)) errors $estimated/$n accuracy $(ratio(n-estimated,n))",
        "train correct $train_correct/$n accuracy $(ratio(train_correct,n))","test correct $(tp+tn)/$m accuracy $(ratio(tp+tn,m)) tp $tp fp $fp tn $tn fn $fn",
        "test precision $(ratio(tp,tp+fp)) recall $(ratio(tp,tp+fn)) f1 $(ratio(2tp,2tp+fp+fn)) auc $(fixed_text(auc(test_labels,test_values)))",
        "test inside_margin $inside","test mean_decision positive $(fixed_text(positive)) negative $(fixed_text(negative))"])
    for (example,alpha,value) in zip(training,model.alpha,train_values)
        alpha>0 && push!(
            lines,
            "sv $(example.id) y $(example.label) alpha $(fixed_text(alpha,6)) f $(fixed_text(value)) $(alpha==model.C ? "bound" : "free")"
        )
    end
    (model=model,train_values=train_values,test_values=test_values,weights=(w1,w2),lines=lines)
end
function training_log(model)
    lines = ["training_log $(model.kernel.name)"]
    i = 1
    while i<=length(model.records)
        record = model.records[i]
        if record.full
            dual = objectives(model,record.alpha)[2]
            push!(
                lines,
                "pass $i full examined $(record.examined) changed $(record.changed) dual_objective $(fixed_text(dual,6))"
            )
            i += 1
        else
            first,examined,changed = i,0,0
            while i<=length(model.records) && !model.records[i].full
                examined += model.records[i].examined
                changed += model.records[i].changed
                i += 1
            end
            push!(lines,"passes $first-$(i-1) nonbound examined $examined changed $changed")
        end
    end
    lines
end
function additional_training_lines(training,testing,selected,matrix,settings,learning=false)
    kernel,C = selected.kernel,selected.C
    points,labels = [e.point for e in training],[e.label for e in training]
    test_labels = [e.label for e in testing]
    lines = [learning ? "learning_curve $(kernel.name) C $(fixed_text(C))" : "c_path $(kernel.name)"]
    candidates = learning ? settings["learning_curve"] : settings["c_grid"]
    for candidate in candidates
        size = learning ? length(training)*candidate÷100 : length(training)
        coefficient = learning ? C : candidate
        model = train_model(
            points[1:size],
            labels[1:size],
            kernel,
            submatrix(matrix,1:size),
            coefficient,
            settings
        )
        train_correct = correct_count(labels[1:size],training_decisions(model))
        test_correct = correct_count(test_labels,[decision(model,e.point) for e in testing])
        if learning
            push!(
                lines,
                "size $size support_vectors $(support_counts(model)[1]) train $train_correct/$size test $test_correct/$(length(testing)) $(run_info(model))"
            )
        else
            push!(
                lines,
                "C $(fixed_text(coefficient)) $(support_text(model)) dual_objective $(fixed_text(objectives(model)[2],6)) train $train_correct/$size test $test_correct/$(length(testing)) $(run_info(model))"
            )
        end
    end
    lines
end
probability(value,A,B) = 1/(1+exp(A*value+B))
negative_log_likelihood(
    values,
    targets,
    A,
    B
) = -ordered_sum(target*log(probability(value,A,B))+(1-target)*log(1-probability(value,A,B)) for (value,target) in zip(values,targets))
function calibrate(training,testing,selected,test_values,iterations)
    positive = count(e->e.label==1,training)
    negative = length(training)-positive
    targets = [e.label==1 ? (positive+1)/(positive+2) : 1/(negative+2) for e in training]
    values = selected.values
    A,B = 0.0,log((negative+1)/(positive+1))
    lines = [
        "calibration $(selected.kernel.name) C $(fixed_text(selected.C)) positives $positive negatives $negative",
        "start A $(fixed_text(A,6)) B $(fixed_text(B,6)) nll $(fixed_text(negative_log_likelihood(values,targets,A,B),6))"
    ]
    for iteration in 1:iterations
        g1,g2,h11,h21,h22 = 0.0,0.0,0.0,0.0,0.0
        for (value,target) in zip(values,targets)
            p = probability(value,A,B)
            g1 += value*(target-p)
            g2 += target-p
            h11 += value*value*p*(1-p)
            h21 += value*p*(1-p)
            h22 += p*(1-p)
        end
        determinant = h11*h22-h21*h21
        A -= (h22*g1-h21*g2)/determinant
        B -= (h11*g2-h21*g1)/determinant
        push!(
            lines,
            "iteration $iteration A $(fixed_text(A,6)) B $(fixed_text(B,6)) nll $(fixed_text(negative_log_likelihood(values,targets,A,B),6))"
        )
    end
    probabilities = [probability(value,A,B) for value in test_values]
    totals,counts,positives = zeros(5),zeros(Int,5),zeros(Int,5)
    log_total,brier = 0.0,0.0
    for (example,p) in zip(testing,probabilities)
        actual = example.label==1
        log_total += actual ? log(p) : log(1-p)
        difference = p-actual
        brier += difference*difference
        bin = min(4,floor(Int,5p))+1
        counts[bin] += 1
        totals[bin] += p
        positives[bin] += actual
    end
    push!(
        lines,
        "test log_loss $(fixed_text(-log_total/length(testing),6)) brier $(fixed_text(brier/length(testing),6))"
    )
    ranges = ("0.0-0.2","0.2-0.4","0.4-0.6","0.6-0.8","0.8-1.0")
    for bin in 1:5
        mean = counts[bin]==0 ? "-" : fixed_text(totals[bin]/counts[bin])
        push!(
            lines,
            "bin $(ranges[bin]) count $(counts[bin]) mean_probability $mean positive_rate $(ratio(positives[bin],counts[bin]))"
        )
    end
    closest = sort(collect(eachindex(testing));by=i->(abs(test_values[i]),i))[1:5]
    for i in closest
        push!(
            lines,
            "closest $(testing[i].id) label $(testing[i].label) decision $(fixed_text(test_values[i])) probability $(fixed_text(probabilities[i]))"
        )
    end
    A,B,probabilities,lines
end
linear_decision(weights,point) = weights[1]*point[1]+weights[2]*point[2]+weights[3]
function pegasos(training,testing,parameters,comparison)
    lambda,iterations,seed = parameters
    state,updates = seed,0
    w1,w2,bias,sum1,sum2,sum_bias = 0.0,0.0,0.0,0.0,0.0,0.0
    n,m = length(training),length(testing)
    labels,test_labels = [e.label for e in training],[e.label for e in testing]
    lines = ["pegasos lambda $(fixed_text(lambda)) iterations $iterations seed $seed"]
    for t in 1:iterations
        state = (48271state)%2147483647
        example = training[state%n+1]
        eta = 1/(lambda*t)
        sigma = 1-eta*lambda
        if example.label*linear_decision((w1,w2,bias),example.point)<1
            w1 = sigma*w1+eta*example.label*example.point[1]
            w2 = sigma*w2+eta*example.label*example.point[2]
            bias = sigma*bias+eta*example.label
            updates += 1
        else
            w1,w2,bias = sigma*w1,sigma*w2,sigma*bias
        end
        sum1 += w1
        sum2 += w2
        sum_bias += bias
        if t%(iterations÷10)==0
            values = [linear_decision((w1,w2,bias),e.point) for e in training]
            hinge = ordered_sum(max(0.0,1-label*value) for (label,value) in zip(labels,values))
            objective = lambda/2*(w1*w1+w2*w2+bias*bias)+hinge/n
            push!(
                lines,
                "checkpoint $t objective $(fixed_text(objective,6)) train $(correct_count(labels,values))/$n"
            )
        end
    end
    weights,average = (w1,w2,bias),(sum1/iterations,sum2/iterations,sum_bias/iterations)
    train_values = [linear_decision(weights,e.point) for e in training]
    test_values = [linear_decision(weights,e.point) for e in testing]
    average_values = [linear_decision(average,e.point) for e in testing]
    train_correct,test_correct,average_correct = correct_count(labels,train_values),correct_count(test_labels,test_values),correct_count(
        test_labels,
        average_values
    )
    v1,v2 = comparison.weights
    cosine = (w1*v1+w2*v2)/(sqrt(w1*w1+w2*w2)*sqrt(v1*v1+v2*v2))
    agreement = count(pair->svm_sign(pair[1])==svm_sign(pair[2]),zip(test_values,comparison.test_values))
    append!(lines,["updates $updates","w $(fixed_text(w1,6)) $(fixed_text(w2,6)) bias $(fixed_text(bias,6))","train correct $train_correct/$n accuracy $(ratio(train_correct,n))",
        "test correct $test_correct/$m accuracy $(ratio(test_correct,m))","average w $(fixed_text(average[1],6)) $(fixed_text(average[2],6)) bias $(fixed_text(average[3],6)) test correct $average_correct/$m",
        "compare $(comparison.model.kernel.name) cosine $(fixed_text(cosine,6)) test_agreement $agreement/$m"])
    test_values,lines
end
function mcnemar_lines(testing,results,pegasos_values)
    names = vcat([result.model.kernel.name for result in results],["pegasos"])
    values = vcat([result.test_values for result in results],[pegasos_values])
    correctness = [[svm_sign(value)==e.label for (value,e) in zip(decisions,testing)] for decisions in values]
    lines = ["mcnemar"]
    for a in eachindex(names),b in a+1:length(names)
        first = count(pair->pair[1] && !pair[2],zip(correctness[a],correctness[b]))
        second = count(pair->pair[2] && !pair[1],zip(correctness[a],correctness[b]))
        chi2 = first+second==0 ? "-" : fixed_text((abs(first-second)-1)^2/(first+second))
        push!(lines,"$(names[a]) $(names[b]) only_first $first only_second $second chi2 $chi2")
    end
    lines
end
function multiclass_summary(role,examples,results)
    rest = count(pair->pair[1].class_number==pair[2].ovr,zip(examples,results))
    pair = count(item->item[1].class_number==item[2].ovo,zip(examples,results))
    agreement,ties,n = count(r->r.ovr==r.ovo,results),count(r->r.tied,results),length(examples)
    "$role ovr $rest/$n $(ratio(rest,n)) ovo $pair/$n $(ratio(pair,n)) agreement $agreement/$n vote_ties $ties"
end
function multiclass_lines(training,testing,models)
    train_results,test_results = [classify(models,e.point) for e in training],[classify(
        models,
        e.point
    ) for e in testing]
    n,m = length(training),length(testing)
    lines = [
        "multiclass kernel $(models.kernel.name) C $(fixed_text(models.C)) classes 3 train $n test $m",
        "ovr"
    ]
    for (k,model) in enumerate(models.ovr)
        correct = count(
            item->svm_sign(item[2].ovr_values[k])==(item[1].class_number==k ? 1 : -1),
            zip(testing,test_results)
        )
        push!(
            lines,
            "model $k-rest examples $n positives $(count(==(1),model.labels)) $(support_text(model)) b $(fixed_text(model.b,6)) $(run_info(model)) test $correct/$m"
        )
    end
    push!(lines,"ovo")
    for (i,((first,second),model)) in enumerate(zip(CLASS_PAIRS,models.ovo))
        indices = [j for j in eachindex(testing) if testing[j].class_number in (first,second)]
        correct = count(
            j->svm_sign(test_results[j].ovo_values[i])==(testing[j].class_number==first ? 1 : -1),
            indices
        )
        push!(
            lines,
            "model $first-$second examples $(length(model.points)) positives $(count(==(1),model.labels)) $(support_text(model)) b $(fixed_text(model.b,6)) $(run_info(model)) test $correct/$(length(indices))"
        )
    end
    push!(lines,"predictions")
    for (e,r) in zip(testing,test_results)
        push!(
            lines,
            "$(e.id) class $(e.class_number) ovr $(join(fixed_text.(r.ovr_values)," ")) pred $(r.ovr) ovo $(join(fixed_text.(r.ovo_values)," ")) votes $(join(r.votes," ")) pred $(r.ovo)"
        )
    end
    push!(
        lines,
        multiclass_summary("train",training,train_results),
        multiclass_summary("test",testing,test_results)
    )
    classes = [e.class_number for e in testing]
    for decoder in (:ovr,:ovo)
        push!(lines,"confusion $decoder")
        append!(
            lines,
            confusion_lines(confusion_matrix(classes,[getproperty(r,decoder) for r in test_results]))
        )
    end
    lines
end
function framed_plot(cells,width,height)
    border = "+"*repeat("-",width)*"+"
    vcat([border],["|"*join(cells[r*width+1:(r+1)*width])*"|" for r in 0:height-1],[border])
end
function plot_cell(point,xmin,ymax,dx,dy,width,height)
    c,r = floor(Int,(point[1]-xmin)/dx),floor(Int,(ymax-point[2])/dy)
    0<=c<width && 0<=r<height ? r*width+c+1 : 0
end
function decision_plots(training,multi_training,results,selected,A,B,multi,settings)
    width,height = settings["plot_size"]
    xmin,xmax = settings["plot_x"]
    ymin,ymax = settings["plot_y"]
    dx,dy = (xmax-xmin)/width,(ymax-ymin)/height
    ncell = width*height
    model = results[selected.kernel_index].model
    binary,probabilities,multicells = Char[],Char[],Char[]
    signs,levels = zeros(Int,ncell,length(results)),zeros(Int,10)
    for r in 0:height-1,c in 0:width-1
        point = (xmin+(c+0.5)*dx,ymax-(r+0.5)*dy)
        values = [decision(result.model,point) for result in results]
        value = values[selected.kernel_index]
        push!(binary,value>=1 ? '+' : value>0 ? '.' : value>-1 ? '-' : ' ')
        level = min(9,floor(Int,10probability(value,A,B)))
        push!(probabilities,Char(Int('0')+level))
        levels[level+1] += 1
        signs[r*width+c+1,:] = svm_sign.(values)
        result = classify(multi,point)
        push!(multicells,result.ovr!=result.ovo ? '?' : (' ','.',':')[result.ovr])
    end
    assignments,outside = zeros(Int,ncell),0
    for (i,e) in enumerate(training)
        p = plot_cell(e.point,xmin,ymax,dx,dy,width,height)
        if p==0
            outside += 1
        elseif assignments[p]==0 || (model.alpha[i]>0 && model.alpha[assignments[p]]<=0)
            assignments[p] = i
        end
    end
    for (p,i) in enumerate(assignments)
        i==0 && continue
        support = model.alpha[i]>0
        binary[p] = training[i].label==1 ? (support ? 'X' : 'x') : (support ? 'O' : 'o')
    end
    multi_assignments,multi_outside = zeros(Int,ncell),0
    for (i,e) in enumerate(multi_training)
        p = plot_cell(e.point,xmin,ymax,dx,dy,width,height)
        if p==0
            multi_outside += 1
        elseif multi_assignments[p]==0
            multi_assignments[p] = i
        end
    end
    for (p,i) in enumerate(multi_assignments)
        i!=0 && (multicells[p]=Char(Int('0')+multi_training[i].class_number))
    end
    lines = [
        "binary $(model.kernel.name) C $(fixed_text(model.C))",
        "x $(fixed_text(xmin)) $(fixed_text(xmax)) y $(fixed_text(ymin)) $(fixed_text(ymax)) grid $(width)x$height"
    ]
    append!(lines,framed_plot(binary,width,height))
    push!(lines,"cells outer_positive $(count(==('+'),binary)) inner_positive $(count(==('.'),binary)) inner_negative $(count(==('-'),binary)) outer_negative $(count(==(' '),binary)) points $(count(!=(0),assignments)) outside $outside","",
        "probability $(model.kernel.name) A $(fixed_text(A,6)) B $(fixed_text(B,6))")
    append!(lines,framed_plot(probabilities,width,height))
    append!(lines,["levels "*join(levels," "),"","grid_agreement"])
    for a in eachindex(results),b in a+1:length(results)
        agreement = count(pair->pair[1]==pair[2],zip(signs[:,a],signs[:,b]))
        push!(
            lines,
            "$(results[a].model.kernel.name) $(results[b].model.kernel.name) $agreement/$ncell positive $(count(==(1),signs[:,a])) $(count(==(1),signs[:,b]))"
        )
    end
    push!(lines,"","multiclass $(multi.kernel.name) C $(fixed_text(multi.C))")
    append!(lines,framed_plot(multicells,width,height))
    push!(
        lines,
        "cells class1 $(count(==(' '),multicells)) class2 $(count(==('.'),multicells)) class3 $(count(==(':'),multicells)) disagree $(count(==('?'),multicells)) points $(count(!=(0),multi_assignments)) outside $multi_outside"
    )
    lines
end
function cv_grid_lines(combinations,k,n)
    header = vcat(
        ["kernel","C"],
        ["fold$f" for f in 1:k],
        ["correct","accuracy","support_vectors","passes","steps"]
    )
    lines = [join(header,",")]
    for result in combinations
        row = vcat(
            [result.kernel.name,fixed_text(result.C)],
            string.([fold.correct for fold in result.folds]),
            [
                string(result.correct),
                ratio(result.correct,n),
                string(result.support),
                string(result.passes),
                string(result.steps)
            ]
        )
        push!(lines,join(row,","))
    end
    lines
end
function prediction_lines(testing,results,selected,pegasos_values,probabilities)
    lines = [join(
        vcat(
            ["id","label"],
            [result.model.kernel.name for result in results],
            ["pegasos","predicted","probability"]
        ),
        ","
    )]
    selected_values = results[selected.kernel_index].test_values
    for (i,e) in enumerate(testing)
        row = vcat(
            [e.id,string(e.label)],
            [fixed_text(result.test_values[i]) for result in results],
            [fixed_text(pegasos_values[i]),string(svm_sign(selected_values[i])),fixed_text(probabilities[i])]
        )
        push!(lines,join(row,","))
    end
    lines
end
function main()
    training,testing,multi_training,multi_testing,settings = read_inputs()
    matrices,combinations,best,selected,ranking = cross_validate(training,settings)
    points,labels = [e.point for e in training],[e.label for e in training]
    results = NamedTuple[]
    for (i,result) in enumerate(best)
        model = train_model(points,labels,result.kernel,matrices[i],result.C,settings)
        push!(results,evaluate_final(model,training,testing,settings["tolerance"]))
    end
    chosen,matrix = results[selected.kernel_index],matrices[selected.kernel_index]
    sections = [cross_validation_lines(length(training),settings["folds"],best,selected,ranking)]
    append!(sections,[result.lines for result in results])
    push!(
        sections,
        training_log(chosen.model),
        additional_training_lines(training,testing,selected,matrix,settings),
        additional_training_lines(training,testing,selected,matrix,settings,true)
    )
    A,B,probabilities,calibration_lines = calibrate(
        training,
        testing,
        selected,
        chosen.test_values,
        settings["newton_iterations"]
    )
    push!(sections,calibration_lines)
    comparison = results[findfirst(result->result.model.kernel.kind=="linear",results)]
    pegasos_values,pegasos_report = pegasos(training,testing,settings["pegasos"],comparison)
    push!(sections,pegasos_report,mcnemar_lines(testing,results,pegasos_values))
    multi_name,multi_C = settings["multiclass"]
    multi_kernel = settings["kernels"][findfirst(kernel->kernel.name==multi_name,settings["kernels"])]
    multi = train_multiclass(multi_training,multi_kernel,multi_C,settings)
    model_lines = String[]
    for section in sections
        isempty(model_lines) || push!(model_lines,"")
        append!(model_lines,section)
    end
    write_lines("model.txt",model_lines)
    write_lines("cv_grid.csv",cv_grid_lines(combinations,settings["folds"],length(training)))
    write_lines("predictions.csv",prediction_lines(testing,results,selected,pegasos_values,probabilities))
    write_lines("multiclass.txt",multiclass_lines(multi_training,multi_testing,multi))
    write_lines(
        "decision_plot.txt",
        decision_plots(training,multi_training,results,selected,A,B,multi,settings)
    )
end
main()
