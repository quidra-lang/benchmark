include("dataset.jl")
include("layers.jl")
include("network.jl")
include("optimizers.jl")
include("evaluation.jl")
mean_value(values) = ordered_sum(values)/length(values)
weighted_l2(values) = sqrt(ordered_sum(value*value for value in values))
function network_catalog(data)
    Dict(architecture.name=>(
        architecture=architecture,
        layout=layout_for(architecture),
        initial=data.weights[architecture.name]
    ) for architecture in data.networks)
end
function check_network(name,network,training,settings)
    generator,order = MINSTD(settings["seed"]),collect(eachindex(training))
    shuffle_order!(generator,order)
    batch = training[order[1:min(settings["batch_size"],length(order))]]
    layout,theta = network.layout,copy(network.initial)
    analytic,_ = average_gradient(layout,theta,batch)
    checked = collect(1:settings["gradient_stride"]:layout.parameters)
    h,passed = 0.00001,true
    for p in checked
        original = theta[p]
        theta[p] = original+h
        higher = evaluate_network(layout,theta,batch).loss
        theta[p] = original-h
        lower = evaluate_network(layout,theta,batch).loss
        theta[p] = original
        derivative = (higher-lower)/(2h)
        error = abs(analytic[p]-derivative)/max(1,abs(analytic[p])+abs(derivative))
        error>=0.000001 && (passed=false)
    end
    lines = [
        "network $name",
        "parameters $(layout.parameters)",
        "batch "*join((image.id for image in batch)," ")
    ]
    selected = Set(checked)
    for (l,layer) in enumerate(layout.layers)
        weights = count(p->p in selected,layer.weight_start:layer.weight_end)
        biases = count(p->p in selected,layer.bias_start:layer.bias_end)
        push!(lines,"layer $l weights $weights biases $biases")
    end
    push!(lines,"checked $(length(checked))","result $(passed ? "PASS" : "FAIL")")
    lines
end
function gradient_check_lines(catalog,architectures,training,settings)
    lines = String[]
    for architecture in architectures
        isempty(lines) || push!(lines,"")
        append!(lines,check_network(architecture.name,catalog[architecture.name],training,settings))
    end
    lines
end
function train_run(definition,network,training,validation,settings)
    layout,theta = network.layout,copy(network.initial)
    state = initialize_optimizer(length(theta))
    generator,order = MINSTD(settings["seed"]),collect(eachindex(training))
    epochs,correctness = NamedTuple[],Vector{Bool}[]
    best_epoch,best_loss,saved_correct,wait,updates = 0,0.0,0,0,0
    best_theta,stop = Float64[],"max_epochs"
    for epoch in 1:settings["max_epochs"]
        rate = epoch_rate(definition,epoch,settings["lr_step"],settings["lr_gamma"])
        shuffle_order!(generator,order)
        norms = Float64[]
        for start in 1:settings["batch_size"]:length(order)
            batch = training[order[start:min(length(order),start+settings["batch_size"]-1)]]
            grad,_ = average_gradient(layout,theta,batch)
            for (p,is_weight) in enumerate(layout.is_weight)
                is_weight && (grad[p]+=definition.decay*theta[p])
            end
            push!(norms,weighted_l2(grad))
            update_parameters!(theta,grad,state,definition,rate)
            updates += 1
        end
        train_eval,val_eval = evaluate_network(layout,theta,training),evaluate_network(
            layout,
            theta,
            validation
        )
        push!(correctness,[item.predicted==item.label for item in train_eval.outcomes])
        improved = best_epoch==0 || val_eval.loss<best_loss
        if improved
            best_epoch,best_loss,saved_correct,best_theta,wait = epoch,val_eval.loss,val_eval.correct,copy(theta),0
        else
            wait += 1
        end
        push!(
            epochs,
            (
                epoch=epoch,
                lr=rate,
                grad_norm=mean_value(norms),
                train_loss=train_eval.loss,
                train_correct=train_eval.correct,
                val_loss=val_eval.loss,
                val_correct=val_eval.correct,
                improved=improved
            )
        )
        if wait>=settings["patience"]
            stop = "early"
            break
        end
    end
    (
        ;definition...,
        network_data=network,
        best_theta=best_theta,
        best_epoch=best_epoch,
        best_val_loss=best_loss,
        best_val_correct=saved_correct,
        epochs=epochs,
        updates=updates,
        stop=stop,
        correctness=correctness
    )
end
function noisy_data(test,settings)
    results = NamedTuple[]
    for percent in settings["noise"]
        generator,altered,flipped = MINSTD(settings["seed"]),NamedTuple[],0
        for image in test
            vector = copy(image.vector)
            for p in eachindex(vector)
                if draw!(generator)%100<percent
                    vector[p] = 1.0-vector[p]
                    flipped += 1
                end
            end
            push!(altered,(;image...,vector=vector))
        end
        push!(results,(percent=percent,images=altered,flipped=flipped))
    end
    results
end
function prepare_run_evaluation(run,training,test,settings,noise)
    network = run.network_data
    architecture,layout,theta = network.architecture,network.layout,run.best_theta
    evaluated = evaluate_network(layout,theta,test)
    outcomes = evaluated.outcomes
    top2 = count(item->item.label in best_two(item.scores),outcomes)
    correct_confidence = [item.confidence for item in outcomes if item.predicted==item.label]
    wrong_confidence = [item.confidence for item in outcomes if item.predicted!=item.label]
    confidence_correct = isempty(correct_confidence) ? nothing : mean_value(correct_confidence)
    confidence_wrong = isempty(wrong_confidence) ? nothing : mean_value(wrong_confidence)
    statuses = run.correctness
    events = [count(e->statuses[e-1][i] && !statuses[e][i],2:length(statuses)) for i in eachindex(training)]
    forgetting = (
        events=sum(events),
        rows=count(>(0),events),
        never=count(i->!any(status->status[i],statuses),eachindex(training))
    )
    weight_norms,weight_changes = Float64[],Float64[]
    for layer in layout.layers
        indices = layer.weight_start:layer.weight_end
        push!(weight_norms,weighted_l2(theta[indices]))
        push!(weight_changes,weighted_l2(theta[indices].-network.initial[indices]))
    end
    bins = [NamedTuple[] for _ in 1:settings["calibration_bins"]]
    for item in outcomes
        bin = min(length(bins)-1,floor(Int,item.confidence*length(bins)))+1
        push!(bins[bin],item)
    end
    ece = 0.0
    for bucket in bins
        isempty(bucket) && continue
        accurate = count(item->item.predicted==item.label,bucket)
        confidence = mean_value([item.confidence for item in bucket])
        ece += length(bucket)/length(test)*abs(accurate/length(bucket)-confidence)
    end
    hidden_summary = NamedTuple[]
    for (l,layer) in enumerate(layout.layers[1:end-1])
        means = Any[]
        for klass in 0:architecture.classes-1
            subset = [item.hidden[l] for item in outcomes if item.label==klass]
            push!(
                means,
                isempty(subset) ? nothing : [mean_value([values[j] for values in subset]) for j in 1:layer.outputs]
            )
        end
        available = [k for k in eachindex(means) if !isnothing(means[k])]
        preferred = [available[argmax([means[k][j] for k in available])]-1 for j in 1:layer.outputs]
        zero_counts = [count(item->item.hidden[l][j]==0,outcomes) for j in 1:layer.outputs]
        push!(hidden_summary,(means=means,preferred=preferred,zero_counts=zero_counts))
    end
    ordered_weights = sort(findall(layout.is_weight);by=p->(abs(theta[p]),p))
    pruning = NamedTuple[]
    for percent in settings["prune"]
        removed = percent*length(ordered_weights)÷100
        pruned = copy(theta)
        pruned[ordered_weights[1:removed]] .= 0.0
        result = evaluate_network(layout,pruned,test)
        push!(pruning,(percent=percent,removed=removed,correct=result.correct,loss=result.loss))
    end
    noise_results = [(
        percent=item.percent,
        flipped=item.flipped,
        correct=evaluate_network(layout,theta,item.images).correct
    ) for item in noise]
    (;run...,test=evaluated,confusion=confusion(outcomes,architecture.classes),top2=top2,confidence_correct=confidence_correct,confidence_wrong=confidence_wrong,
        forgetting=forgetting,weight_norms=weight_norms,weight_changes=weight_changes,calibration=bins,ece=ece,hidden_summary=hidden_summary,pruning=pruning,noise_results=noise_results,
        misclassified=[item for item in outcomes if item.predicted!=item.label])
end
function training_log_lines(runs,m,nv)
    lines = ["run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"]
    for run in runs,record in run.epochs
        push!(
            lines,
            join(
                [
                    run.name,
                    string(record.epoch),
                    real_text(record.lr,6),
                    real_text(record.grad_norm,4),
                    real_text(record.train_loss,6),
                    ratio(record.train_correct,m),
                    real_text(record.val_loss,6),
                    ratio(record.val_correct,nv),
                    record.improved ? "1" : "0"
                ],
                ","
            )
        )
    end
    lines
end
function final_weight_lines(runs)
    lines = String[]
    for run in runs
        isempty(lines) || push!(lines,"")
        push!(lines,"RUN $(run.name) NETWORK $(run.network) EPOCH $(run.best_epoch)")
        for (l,layer) in enumerate(run.network_data.layout.layers)
            push!(lines,"LAYER $l $(layer.outputs) $(layer.inputs)")
            cursor = layer.weight_start
            for _ in 1:layer.outputs
                push!(
                    lines,
                    "W "*join((real_text(v,4) for v in run.best_theta[cursor:cursor+layer.inputs-1])," ")
                )
                cursor += layer.inputs
            end
            push!(
                lines,
                "B "*join((real_text(v,4) for v in run.best_theta[layer.bias_start:layer.bias_end])," ")
            )
        end
    end
    lines
end
function prediction_lines(runs)
    lines = ["run,id,label,predicted,confidence"]
    for run in runs,item in run.test.outcomes
        push!(lines,"$(run.name),$(item.id),$(item.label),$(item.predicted),$(real_text(item.confidence,4))")
    end
    lines
end
function data_summary_lines(training,validation,test,architecture)
    width,height,classes = architecture.width,architecture.height,architecture.classes
    pixels = width*height
    lines = [
        "data",
        "train $(length(training)) validation $(length(validation)) test $(length(test)) pixels $pixels"
    ]
    for klass in 0:classes-1
        group = [image for image in training if image.label==klass]
        val_count,test_count = count(
            image->image.label==klass,
            validation
        ),count(image->image.label==klass,test)
        ink = sum((count(==('1'),image.pixels) for image in group);init=0)
        push!(
            lines,
            "class $klass train $(length(group)) validation $val_count test $test_count ink $(ratio(ink,length(group)))"
        )
    end
    push!(lines,"mean_images "*join(0:classes-1," "))
    append!(lines,level_maps([binary_frequency(training,k,pixels) for k in 0:classes-1],width,height))
    lines
end
function run_evaluation_lines(run,validation,test,settings)
    n,nv = length(test),length(validation)
    forgetting = run.forgetting
    lines = ["run $(run.name) network $(run.network) optimizer $(run.optimizer)","epochs $(length(run.epochs)) best_epoch $(run.best_epoch) stop $(run.stop) updates $(run.updates)",
        "best_val_loss $(real_text(run.best_val_loss,6)) best_val_acc $(ratio(run.best_val_correct,nv)) correct $(run.best_val_correct)/$nv",
        "test_loss $(real_text(run.test.loss,6)) test_acc $(ratio(run.test.correct,n)) correct $(run.test.correct)/$n","top2_acc $(ratio(run.top2,n)) correct $(run.top2)/$n",
        "confidence correct $(real_text(run.confidence_correct,4)) wrong $(real_text(run.confidence_wrong,4))","forgetting events $(forgetting.events) rows $(forgetting.rows) never_learned $(forgetting.never)",
        "weight_norms "*join((real_text(v,4) for v in run.weight_norms)," "),"weight_changes "*join(
            (real_text(v,4) for v in run.weight_changes),
            " "
        ),"curve"]
    largest = maximum(max(item.train_loss,item.val_loss) for item in run.epochs)
    for item in run.epochs
        canvas = fill(' ',40)
        ct,cv = floor(Int,39item.train_loss/largest+0.5),floor(Int,39item.val_loss/largest+0.5)
        canvas[ct+1] = 't'
        canvas[cv+1] = ct==cv ? '*' : 'v'
        push!(lines,lpad(item.epoch,2)*" |"*join(canvas)*"|"*(item.epoch==run.best_epoch ? " best" : ""))
    end
    push!(lines,"confusion")
    classes = run.network_data.architecture.classes
    for klass in 0:classes-1
        push!(lines,"$klass: "*join(run.confusion[klass+1,:]," "))
    end
    for klass in 0:classes-1
        measures = class_measures(run.confusion,klass)
        push!(
            lines,
            "class $klass support $(measures.support) predicted $(measures.predicted) precision $(measures.precision) recall $(measures.recall) f1 $(measures.f1)"
        )
    end
    push!(lines,"calibration")
    for (bin,bucket) in enumerate(run.calibration)
        accurate = count(item->item.predicted==item.label,bucket)
        confidence = isempty(bucket) ? nothing : mean_value([item.confidence for item in bucket])
        push!(
            lines,
            "bin $bin $(real_text((bin-1)/length(run.calibration),2)) $(real_text(bin/length(run.calibration),2)) count $(length(bucket)) accuracy $(ratio(accurate,length(bucket))) confidence $(real_text(confidence,4))"
        )
    end
    push!(lines,"ece $(real_text(run.ece,4))")
    for (l,layer) in enumerate(run.network_data.layout.layers[1:end-1])
        summary = run.hidden_summary[l]
        push!(lines,"hidden $l $(layer.activation) units $(layer.outputs)")
        for klass in 0:classes-1
            values = summary.means[klass+1]
            text = isnothing(values) ? "-" : join((real_text(value,4) for value in values)," ")
            push!(lines,"class $klass mean $text")
        end
        push!(lines,"preferred "*join(summary.preferred," "))
        layer.activation=="RELU" && push!(lines,"zero_counts "*join(summary.zero_counts," "))
    end
    push!(lines,"pruning")
    for item in run.pruning
        push!(
            lines,
            "prune $(item.percent) removed $(item.removed) correct $(item.correct) test_acc $(ratio(item.correct,n)) test_loss $(real_text(item.loss,6))"
        )
    end
    push!(lines,"noise")
    for item in run.noise_results
        push!(lines,"noise $(item.percent) correct $(item.correct) test_acc $(ratio(item.correct,n))")
    end
    ids = [item.id for item in run.misclassified]
    push!(lines,"misclassified $(length(ids))"*(isempty(ids) ? "" : " "*join(ids," ")))
    lines
end
function ensembles(runs,ranking,test)
    classes = runs[1].network_data.architecture.classes
    soft_runs = [run for run in runs if run.network_data.architecture.layers[end].activation=="SOFTMAX"]
    majority,soft = Int[],Int[]
    for i in eachindex(test)
        votes = zeros(Int,classes)
        for run in runs
            votes[run.test.outcomes[i].predicted+1] += 1
        end
        highest = maximum(votes)
        winner = findfirst(index->votes[runs[index].test.outcomes[i].predicted+1]==highest,ranking)
        push!(majority,runs[ranking[winner]].test.outcomes[i].predicted)
        if !isempty(soft_runs)
            means = [ordered_sum(run.test.outcomes[i].scores[k] for run in soft_runs)/length(soft_runs) for k in 1:classes]
            push!(soft,argmax(means)-1)
        end
    end
    majority,soft,length(soft_runs)
end
function saliency_lines(top,test)
    network = top.network_data
    architecture = network.architecture
    size = architecture.width*architecture.height
    maps = Vector{Int}[]
    for klass in 0:architecture.classes-1
        chosen = [image for image in test if image.label==klass]
        values = zeros(size)
        for image in chosen
            inputs = gradient(network.layout,top.best_theta,image,true).input_gradient
            for (i,derivative) in enumerate(inputs)
                values[i] += abs(derivative)
            end
        end
        if !isempty(chosen)
            values ./= length(chosen)
        end
        largest = maximum(values)
        push!(maps,largest>0 ? [min(9,floor(Int,10value/largest)) for value in values] : zeros(Int,size))
    end
    vcat(
        ["saliency $(top.name)","classes "*join(0:architecture.classes-1," ")],
        level_maps(maps,architecture.width,architecture.height)
    )
end
function hardest_examples_lines(top,training)
    outcomes = evaluate_network(top.network_data.layout,top.best_theta,training).outcomes
    order = sort(collect(eachindex(training));by=i->(-outcomes[i].loss,i))
    lines = ["hardest_training_examples $(top.name)"]
    for i in order[1:min(5,length(order))]
        push!(
            lines,
            "$(training[i].id) label $(training[i].label) predicted $(outcomes[i].predicted) loss $(real_text(outcomes[i].loss,6))"
        )
    end
    lines
end
function misclassified_examples_lines(top,runs,test,all_train,majority)
    width = top.network_data.architecture.width
    lines = ["misclassified_examples $(top.name)"]
    for (i,(image,outcome)) in enumerate(zip(test,top.test.outcomes))
        outcome.predicted==image.label && continue
        predictions = [run.test.outcomes[i].predicted for run in runs]
        distances = [count(
            pair->pair[1]!=pair[2],
            zip(image.pixels,candidate.pixels)
        ) for candidate in all_train]
        nearest_index = argmin(distances)
        nearest = all_train[nearest_index]
        push!(lines,"$(image.id) label $(image.label) predicted $(outcome.predicted) confidence $(real_text(outcome.confidence,4)) true_score $(real_text(outcome.scores[image.label+1],4)) runs $(join(predictions," ")) ensemble $(majority[i])",
            "nearest $(nearest.id) label $(nearest.label) distance $(distances[nearest_index])")
        append!(lines,ascii_image(image.pixels,width))
    end
    lines
end
function comparison_lines(runs,training,all_train,test,settings)
    ranking = sort(collect(eachindex(runs));by=i->(-runs[i].test.correct,runs[i].best_val_loss,i))
    top = runs[ranking[1]]
    n = length(test)
    majority,soft,soft_count = ensembles(runs,ranking,test)
    lines = ["comparison"]
    for (rank,index) in enumerate(ranking)
        run = runs[index]
        push!(
            lines,
            "rank $rank $(run.name) correct $(run.test.correct) test_acc $(ratio(run.test.correct,n)) best_val_loss $(real_text(run.best_val_loss,6)) test_loss $(real_text(run.test.loss,6)) best_epoch $(run.best_epoch) epochs $(length(run.epochs)) updates $(run.updates)"
        )
    end
    push!(lines,"agreement")
    for a in runs
        agreement = [count(
            pair->pair[1].predicted==pair[2].predicted,
            zip(a.test.outcomes,b.test.outcomes)
        ) for b in runs]
        push!(lines,a.name*" "*join(agreement," "))
    end
    push!(lines,"mcnemar $(top.name)")
    for index in ranking[2:end]
        run = runs[index]
        b = count(
            pair->pair[1].predicted==pair[1].label && pair[2].predicted!=pair[2].label,
            zip(top.test.outcomes,run.test.outcomes)
        )
        c = count(
            pair->pair[1].predicted!=pair[1].label && pair[2].predicted==pair[2].label,
            zip(top.test.outcomes,run.test.outcomes)
        )
        numerator,denominator = max(abs(b-c)-1,0)^2,b+c
        chi = denominator==0 ? "0.0000" : ratio(numerator,denominator)
        push!(
            lines,
            "vs $(run.name) b $b c $c chi2 $chi significant $(numerator*1000>3841denominator ? "yes" : "no")"
        )
    end
    correct = count(i->majority[i]==test[i].label,eachindex(test))
    fixed = count(
        i->majority[i]==test[i].label && top.test.outcomes[i].predicted!=test[i].label,
        eachindex(test)
    )
    broken = count(
        i->majority[i]!=test[i].label && top.test.outcomes[i].predicted==test[i].label,
        eachindex(test)
    )
    push!(lines,"ensemble correct $correct/$n test_acc $(ratio(correct,n)) fixed $fixed broken $broken")
    if soft_count>0
        correct = count(i->soft[i]==test[i].label,eachindex(test))
        push!(lines,"soft_ensemble runs $soft_count correct $correct/$n test_acc $(ratio(correct,n))")
    else
        push!(lines,"soft_ensemble none")
    end
    for item in runs[1].noise_results
        push!(lines,"noise $(item.percent) flipped $(item.flipped)")
    end
    classes = top.network_data.architecture.classes
    total = zeros(Int,classes,classes)
    for run in runs
        total .+= run.confusion
    end
    pairs = [(y,p) for y in 0:classes-1 for p in 0:classes-1 if y!=p && total[y+1,p+1]>0]
    sort!(pairs;by=pair->(-total[pair[1]+1,pair[2]+1],pair...))
    push!(lines,"confused_pairs")
    append!(lines,["$y as $p count $(total[y+1,p+1])" for (y,p) in pairs[1:min(5,length(pairs))]])
    push!(lines,"")
    append!(lines,saliency_lines(top,test))
    push!(lines,"")
    append!(lines,hardest_examples_lines(top,training))
    push!(lines,"")
    append!(lines,misclassified_examples_lines(top,runs,test,all_train,majority))
    lines
end
function evaluation_lines(runs,training,validation,test,data)
    lines = data_summary_lines(training,validation,test,data.networks[1])
    push!(lines,"")
    for run in runs
        append!(lines,run_evaluation_lines(run,validation,test,data.settings))
        push!(lines,"")
    end
    append!(lines,comparison_lines(runs,training,data.train,test,data.settings))
    lines
end
function write_output(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function main()
    data = load_inputs()
    nv = length(data.train)÷5
    split = length(data.train)-nv
    training,validation = data.train[1:split],data.train[split+1:end]
    catalog = network_catalog(data)
    checks = gradient_check_lines(catalog,data.networks,training,data.settings)
    noise = noisy_data(data.test,data.settings)
    runs = NamedTuple[]
    for definition in data.settings["runs"]
        run = train_run(definition,catalog[definition.network],training,validation,data.settings)
        push!(runs,prepare_run_evaluation(run,training,data.test,data.settings,noise))
    end
    write_output("gradient_check.txt",checks)
    write_output("training_log.csv",training_log_lines(runs,length(training),length(validation)))
    write_output("final_weights.txt",final_weight_lines(runs))
    write_output("predictions.csv",prediction_lines(runs))
    write_output("evaluation.txt",evaluation_lines(runs,training,validation,data.test,data))
end
main()
