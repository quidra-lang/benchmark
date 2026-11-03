include("model_io.jl")
include("inference.jl")
include("training.jl")
include("evaluation.jl")
include("sampler.jl")
struct SequenceRecord
    name::String
    observations::Vector{Int}
    path::Union{Nothing,Vector{Int}}
end
function interpret_parameters(rows,model)
    raw = Dict(row[1]=>row[2:end] for row in rows)
    integer(name) = parse(Int,raw[name][1])
    (iterations=integer("iterations"),folds=integer("folds"),min_sequence_length=integer("min_sequence_length"),max_missing_percent=integer("max_missing_percent"),
        merge_gap=integer("merge_gap"),min_segment_length=integer("min_segment_length"),min_rich_percent=integer("min_rich_percent"),min_motif_percent=integer("min_motif_percent"),
        boundary_tolerance=integer("boundary_tolerance"),posterior_seed=integer("posterior_seed"),posterior_samples=integer("posterior_samples"),sample_seed=integer("sample_seed"),
        sample_count=integer("sample_count"),sample_length=integer("sample_length"),pseudocount=parse(
            Float64,
            raw["pseudocount"][1]
        ),confidence=parse(Float64,raw["confidence"][1]),
        smoothing=[(text=text,value=parse(Float64,text)) for text in raw["smoothing"]],segment_state=findfirst(
            ==(only(raw["segment_state"][1])),
            model.states
        ),
        motif=[findfirst(==(only(symbol)),model.symbols) for symbol in raw["motif"]],rich_symbols=Set(findfirst(
            ==(only(symbol)),
            model.symbols
        ) for symbol in raw["rich_symbols"]))
end
function rejection_reason(name,observations,labels,seen,model,params)
    name in seen && return "duplicate name"
    push!(seen,name)
    for (i,char) in enumerate(observations)
        char in model.symbols || char==model.missing || return "invalid symbol $char at position $i"
    end
    if !isnothing(labels)
        for (i,char) in enumerate(labels)
            char in model.states || return "invalid label $char at position $i"
        end
        length(observations)==length(labels) || return "length mismatch $(length(observations)) $(length(labels))"
    end
    length(observations)>=params.min_sequence_length || return "too short $(length(observations))"
    missing = count(==(model.missing),observations)
    100missing<=params.max_missing_percent*length(observations) || return "too many missing $missing"
    nothing
end
encode_observations(text,model) = [char==model.missing ? 0 : something(findfirst(
    ==(char),
    model.symbols
)) for char in text]
function validate_inputs(sequence_rows,labeled_rows,model,params)
    sequences,training,testing = SequenceRecord[],SequenceRecord[],SequenceRecord[]
    rejections,seen = String[],Set{String}()
    for (line,(name,text)) in enumerate(sequence_rows)
        observations = collect(uppercase(text))
        reason = rejection_reason(name,observations,nothing,seen,model,params)
        if isnothing(reason)
            push!(sequences,SequenceRecord(name,encode_observations(observations,model),nothing))
        else
            push!(rejections,"REJECT sequences.txt line $line $name $reason")
        end
    end
    empty!(seen)
    for offset in 1:2:length(labeled_rows)
        name,role,text = labeled_rows[offset]
        observations,labels = collect(uppercase(text)),collect(labeled_rows[offset+1][1])
        reason = rejection_reason(name,observations,labels,seen,model,params)
        if isnothing(reason)
            path = [something(findfirst(==(char),model.states)) for char in labels]
            record = SequenceRecord(name,encode_observations(observations,model),path)
            push!(role=="TRAIN" ? training : testing,record)
        else
            push!(rejections,"REJECT labeled.txt line $offset $name $reason")
        end
    end
    sequences,training,testing,rejections
end
function maximum_change(previous,current)
    maximum((
        maximum(abs.(previous.initial.-current.initial)),
        maximum(abs.(previous.transition.-current.transition)),
        maximum(abs.(previous.emission.-current.emission))
    ))
end
function train_baum_welch(initial,observations,heldout,params)
    current = initial
    previous_loglik = total_loglik(current,observations)
    initial_loglik = previous_loglik
    heldout_loglik = total_loglik(current,heldout)
    best_heldout,best_iteration,violations = heldout_loglik,0,0
    trace = [
        "iteration,loglik,heldout,change,max_change,status",
        "0,$(real_text(previous_loglik)),$(real_text(heldout_loglik)),,,"
    ]
    for iteration in 1:params.iterations
        updated = baum_welch_step(current,observations,params.pseudocount)
        loglik,heldout_loglik = total_loglik(updated,observations),total_loglik(updated,heldout)
        change,largest = loglik-previous_loglik,maximum_change(current,updated)
        violation = loglik<previous_loglik-0.000001abs(previous_loglik)
        violations += violation
        if heldout_loglik>best_heldout
            best_heldout,best_iteration = heldout_loglik,iteration
        end
        status = violation ? "violation" : "ok"
        push!(
            trace,
            "$iteration,$(real_text(loglik)),$(real_text(heldout_loglik)),$(real_text(change)),$(real_text(largest,6)),$status"
        )
        current,previous_loglik = updated,loglik
    end
    current,trace,(
        iterations=params.iterations,
        initial_loglik=initial_loglik,
        final_loglik=previous_loglik,
        violations=violations,
        best_heldout_iteration=best_iteration
    )
end
function viterbi_paths(model,observations)
    paths = Vector{Int}[]
    total = 0.0
    for sequence in observations
        path,logprob = viterbi(model,sequence)
        push!(paths,path)
        total += logprob
    end
    paths,total
end
function train_viterbi(initial,observations,params)
    current = initial
    paths,logprob = viterbi_paths(current,observations)
    loglik = total_loglik(current,observations)
    trace = ["iteration,logprob,loglik,changed","0,$(real_text(logprob)),$(real_text(loglik)),"]
    iterations,changed = 0,0
    for iteration in 1:params.iterations
        current = estimate_by_counting(initial,zip(observations,paths),params.pseudocount,"VITERBI_TRAINING")
        updated_paths,logprob = viterbi_paths(current,observations)
        changed = sum(length(a)-correct_count(a,b) for (a,b) in zip(paths,updated_paths))
        loglik = total_loglik(current,observations)
        push!(trace,"$iteration,$(real_text(logprob)),$(real_text(loglik)),$changed")
        paths,iterations = updated_paths,iteration
        changed==0 && break
    end
    current,trace,(iterations=iterations,converged=changed==0)
end
record_pairs(records) = [(record.observations,record.path) for record in records]
function cross_validate(initial,records,params)
    folds,k = params.folds,length(initial.states)
    positions = sum(length(record.observations) for record in records)
    results = NamedTuple[]
    for candidate in params.smoothing
        matrix = confusion_matrix(k)
        fold_results,total_correct = NamedTuple[],0
        for f in 0:folds-1
            fitting = [r for (i,r) in enumerate(records) if (i-1)%folds!=f]
            validation = [r for (i,r) in enumerate(records) if (i-1)%folds==f]
            model = estimate_by_counting(initial,record_pairs(fitting),candidate.value)
            fold_positions,fold_correct = 0,0
            for record in validation
                path,_ = viterbi(model,record.observations)
                fold_positions += length(path)
                fold_correct += correct_count(record.path,path)
                accumulate_confusion!(matrix,record.path,path)
            end
            total_correct += fold_correct
            push!(fold_results,(records=length(validation),positions=fold_positions,correct=fold_correct))
        end
        push!(
            results,
            (
                candidate=candidate.text,
                alpha=candidate.value,
                correct=total_correct,
                folds=fold_results,
                matrix=matrix
            )
        )
    end
    selected = results[argmax([r.correct for r in results])]
    lines = ["CROSS_VALIDATION folds $folds"]
    for r in results
        push!(
            lines,
            "SMOOTHING $(r.candidate) positions $positions correct $(r.correct) accuracy $(fraction(r.correct,positions))"
        )
    end
    push!(lines,"SELECTED $(selected.candidate)")
    for (f,r) in enumerate(selected.folds)
        push!(
            lines,
            "FOLD $f records $(r.records) positions $(r.positions) correct $(r.correct) accuracy $(fraction(r.correct,r.positions))"
        )
    end
    append!(lines,matrix_lines(initial.states,selected.matrix))
    append!(lines,metric_lines(initial.states,selected.matrix))
    estimate_by_counting(initial,record_pairs(records),selected.alpha),selected,lines
end
function learning_curve(initial,training,testing,alpha)
    positions = sum(length(r.observations) for r in testing)
    lines = ["LEARNING_CURVE"]
    for n in eachindex(training)
        model = estimate_by_counting(initial,record_pairs(training[1:n]),alpha)
        correct = sum(correct_count(r.path,viterbi(model,r.observations)[1]) for r in testing)
        push!(lines,"RECORDS $n correct $correct accuracy $(fraction(correct,positions))")
    end
    lines
end
function extract_segments(path,params)
    segments = Tuple{Int,Int}[]
    for (state,start,ending) in runs(path)
        state==params.segment_state || continue
        if !isempty(segments) && start-segments[end][2]-1<=params.merge_gap
            segments[end] = (segments[end][1],ending)
        else
            push!(segments,(start,ending))
        end
    end
    [segment for segment in segments if segment[2]-segment[1]+1>=params.min_segment_length]
end
function composition(observations,segment,params)
    start,ending = segment
    first,second = params.motif
    observed = rich = first_count = second_count = pairs = 0
    for t in start:ending
        symbol = observations[t]
        if symbol!=0
            observed += 1
            rich += symbol in params.rich_symbols
            first_count += symbol==first
            second_count += symbol==second
        end
        t<ending && symbol==first && observations[t+1]==second && (pairs+=1)
    end
    denominator = first_count*second_count
    island = denominator>0 && 100rich>=params.min_rich_percent*observed && 100pairs*observed>=params.min_motif_percent*denominator
    (
        rich=observed==0 ? nothing : rich/observed,
        pair=denominator==0 ? nothing : pairs*observed/denominator,
        island=island
    )
end
function evaluate_model(model,records,params)
    decoded = [decode(model,r.observations) for r in records]
    blocks,correct_totals = Vector{String}[],Int[]
    for decoder in ("VITERBI","POSTERIOR")
        matrix = confusion_matrix(length(model.states))
        regions,bounds,calibration = zeros(Int,4),zeros(Int,4),zeros(Int,10,2)
        record_lines,total_correct = String[],0
        for (record,result) in zip(records,decoded)
            path = decoder=="VITERBI" ? result.viterbi : result.posterior
            correct = correct_count(record.path,path)
            total_correct += correct
            accumulate_confusion!(matrix,record.path,path)
            predicted = extract_segments(path,params)
            truth = [(s,e) for (state,s,e) in runs(record.path) if state==params.segment_state]
            regions .+= region_counts(predicted,truth)
            bounds .+= boundary_counts(path,record.path,params.boundary_tolerance)
            if decoder=="POSTERIOR"
                for (confidence,prediction,actual) in zip(result.confidence,path,record.path)
                    bin = min(floor(Int,10confidence),9)+1
                    calibration[bin,1] += 1
                    calibration[bin,2] += prediction==actual
                end
            end
            push!(record_lines,"RECORD $(record.name) length $(length(path)) correct $correct")
        end
        lines = vcat(
            ["EVALUATION $(model.name) $decoder"],
            matrix_lines(model.states,matrix),
            metric_lines(model.states,matrix)
        )
        push!(lines,"REGIONS $(model.states[params.segment_state]) predicted $(regions[1]) true $(regions[2]) precision $(fraction(regions[3],regions[1])) recall $(fraction(regions[4],regions[2]))",
            "BOUNDARIES predicted $(bounds[1]) true $(bounds[2]) precision $(fraction(bounds[3],bounds[1])) recall $(fraction(bounds[4],bounds[2]))")
        if decoder=="POSTERIOR"
            for b in 0:9
                positions,correct = calibration[b+1,:]
                positions==0 && continue
                interval = b==9 ? "0.9-1.0" : "0.$b-0.$(b+1)"
                push!(
                    lines,
                    "CALIBRATION $interval positions $positions correct $correct accuracy $(fraction(correct,positions))"
                )
            end
        end
        append!(lines,record_lines)
        push!(blocks,lines)
        push!(correct_totals,total_correct)
    end
    blocks,correct_totals
end
state_string(model,path) = join(model.states[path])
function imputed_string(model,observations,posterior)
    symbols = Char[]
    for (t,observation) in enumerate(observations)
        if observation!=0
            push!(symbols,model.symbols[observation])
        else
            probabilities = [ordered_sum(posterior[t,i]*model.emission[
                i,
                c
            ] for i in eachindex(model.states)) for c in eachindex(model.symbols)]
            push!(symbols,lowercase(model.symbols[maximum_index(probabilities)]))
        end
    end
    join(symbols)
end
function annotate_sequences(model,records,decoded,params)
    generator = MINSTD(params.posterior_seed)
    decoding_lines = String[]
    segment_lines = ["sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"]
    for (record,result) in zip(records,decoded)
        samples = [posterior_path(model,result.fb.forward,generator) for _ in 1:params.posterior_samples]
        expected_segments = sum(length(extract_segments(
            path,
            params
        )) for path in samples)/params.posterior_samples
        n = length(record.observations)
        differences,uncertain = n-correct_count(result.viterbi,result.posterior),count(
            <(params.confidence),
            result.confidence
        )
        confident = join(confidence<params.confidence ? '.' : model.states[state] for (state,confidence) in zip(
            result.posterior,
            result.confidence
        ))
        push!(decoding_lines,"SEQUENCE $(record.name) length $n loglik $(real_text(result.fb.loglik)) viterbi $(real_text(result.viterbi_logprob)) differences $differences uncertain $uncertain expected_segments $(real_text(expected_segments))",
            "VITERBI "*state_string(model,result.viterbi),"POSTERIOR "*state_string(model,result.posterior),"CONFIDENT "*confident,"IMPUTED "*imputed_string(
                model,
                record.observations,
                result.fb.posterior
            ))
        for (decoder,path) in (
            ("viterbi",result.viterbi),
            ("posterior",result.posterior)
        ),segment in extract_segments(path,params)
            start,ending = segment
            n = ending-start+1
            mean = ordered_sum(result.fb.posterior[t,params.segment_state] for t in start:ending)/n
            support = count(path->2count(==(params.segment_state),path[start:ending])>n,samples)
            data = composition(record.observations,segment,params)
            push!(
                segment_lines,
                "$(record.name),$decoder,$start,$ending,$n,$(real_text(mean)),$support,$(real_text(data.rich)),$(real_text(data.pair)),$(data.island ? "yes" : "no")"
            )
        end
    end
    decoding_lines,segment_lines
end
function synthetic_output(model,params)
    generator = MINSTD(params.sample_seed)
    lines = String[]
    viterbi_total = posterior_total = positions = 0
    for number in 1:params.sample_count
        truth,observations = synthetic_sequence(model,params.sample_length,generator)
        result = decode(model,observations)
        a,b = correct_count(truth,result.viterbi),correct_count(truth,result.posterior)
        viterbi_total += a
        posterior_total += b
        positions += length(truth)
        push!(lines,"SAMPLE $number loglik $(real_text(result.fb.loglik)) viterbi $(real_text(result.viterbi_logprob)) viterbi_correct $a posterior_correct $b",
            "STATES "*state_string(model,truth),"SYMBOLS "*join(model.symbols[observations]),"VITERBI "*state_string(model,result.viterbi),"POSTERIOR "*state_string(
                model,
                result.posterior
            ))
    end
    push!(
        lines,
        "TOTAL positions $positions viterbi_accuracy $(fraction(viterbi_total,positions)) posterior_accuracy $(fraction(posterior_total,positions))"
    )
    lines
end
function path_statistics(paths,k)
    counts,run_counts,total = zeros(Int,k),zeros(Int,k),0
    for path in paths
        total += length(path)
        for (state,start,ending) in runs(path)
            counts[state] += ending-start+1
            run_counts[state] += 1
        end
    end
    (counts=counts,runs=run_counts,total=total)
end
function stationary_distribution(model)
    k = length(model.states)
    matrix = zeros(k,k+1)
    for equation in 1:k-1,state in 1:k
        matrix[equation,state] = model.transition[state,equation]-(state==equation ? 1.0 : 0.0)
    end
    matrix[k,:] .= 1.0
    for column in 1:k
        pivot = argmax(abs.(matrix[column:k,column]))+column-1
        matrix[column,:],matrix[pivot,:] = copy(matrix[pivot,:]),copy(matrix[column,:])
        divisor = matrix[column,column]
        for j in column:k+1
            matrix[column,j] /= divisor
        end
        for row in 1:k
            row==column && continue
            factor = matrix[row,column]
            for j in column:k+1
                matrix[row,j] -= factor*matrix[column,j]
            end
        end
    end
    matrix[:,k+1]
end
function state_permutations(k)
    result = Vector{Int}[]
    function visit(prefix)
        if length(prefix)==k
            push!(result,prefix)
        else
            for j in 1:k
                j in prefix || visit(vcat(prefix,[j]))
            end
        end
    end
    visit(Int[])
    result
end
function state_alignment(model,records)
    k = length(model.states)
    matrix,positions = confusion_matrix(k),0
    for record in records
        path,_ = viterbi(model,record.observations)
        accumulate_confusion!(matrix,record.path,path)
        positions += length(path)
    end
    permutations = state_permutations(k)
    counts = [sum(matrix[p[j],j] for j in 1:k) for p in permutations]
    best = argmax(counts)
    mapping = join(("$(model.states[j])=$(model.states[permutations[best][j]])" for j in 1:k)," ")
    "ALIGNMENT $mapping agreement $(fraction(counts[best],positions))"
end
function model_diagnostics(model,records,decoded,training,testing,params)
    loglik = 0.0
    observed = segment_count = segment_length = islands = 0
    for (record,result) in zip(records,decoded)
        loglik += result.fb.loglik
        observed += count(!=(0),record.observations)
        for segment in extract_segments(result.viterbi,params)
            segment_count += 1
            segment_length += segment[2]-segment[1]+1
            islands += composition(record.observations,segment,params).island
        end
    end
    test_loglik = total_loglik(model,[r.observations for r in testing])
    stats = path_statistics([r.viterbi for r in decoded],length(model.states))
    stationary = stationary_distribution(model)
    mean_length = segment_count==0 ? nothing : segment_length/segment_count
    lines = ["MODEL $(model.name)","LOGLIK unlabeled $(real_text(loglik)) per_symbol $(real_text(loglik/observed)) test $(real_text(test_loglik))",
        "SEGMENTS count $segment_count mean_length $(real_text(mean_length)) islands $islands",state_alignment(
            model,
            training
        )]
    for (i,state) in enumerate(model.states)
        duration,occupancy = 1/(1-model.transition[i,i]),stats.counts[i]/stats.total
        mean_run = stats.runs[i]==0 ? nothing : stats.counts[i]/stats.runs[i]
        push!(
            lines,
            "STATE $state stationary $(real_text(stationary[i])) duration $(real_text(duration)) occupancy $(real_text(occupancy)) mean_run $(real_text(mean_run))"
        )
    end
    lines
end
function input_report(model,sequences,training,testing,rejections,sequence_count,labeled_count)
    positions = sum(length(r.observations) for r in sequences)
    missing = sum(count(==(0),r.observations) for r in sequences)
    labeled = vcat(training,testing)
    labeled_positions = sum(length(r.observations) for r in labeled)
    labeled_missing = sum(count(==(0),r.observations) for r in labeled)
    lines = ["INPUT","SEQUENCES accepted $(length(sequences)) rejected $(sequence_count-length(sequences)) positions $positions missing $missing",
        "LABELED train $(length(training)) test $(length(testing)) rejected $(labeled_count-length(labeled)) positions $labeled_positions missing $labeled_missing"]
    append!(lines,rejections)
    counts = zeros(Int,length(model.symbols))
    for record in sequences,symbol in record.observations
        symbol!=0 && (counts[symbol]+=1)
    end
    push!(
        lines,
        "COMPOSITION "*join(
            ("$symbol $(real_text(count/(positions-missing)))" for (symbol,count) in zip(
                model.symbols,
                counts
            )),
            " "
        )
    )
    for (role,records) in (("TRAIN",training),("TEST",testing))
        stats = path_statistics([r.path for r in records],length(model.states))
        for (i,state) in enumerate(model.states)
            mean_run = stats.runs[i]==0 ? nothing : stats.counts[i]/stats.runs[i]
            push!(
                lines,
                "TRUTH $role $state occupancy $(real_text(stats.counts[i]/stats.total)) mean_run $(real_text(mean_run))"
            )
        end
    end
    lines
end
function training_report(models,bw,vt,selected,decoded,scores,test_positions)
    lines = ["TRAINING BAUM_WELCH iterations $(bw.iterations) initial_loglik $(real_text(bw.initial_loglik)) final_loglik $(real_text(bw.final_loglik)) violations $(bw.violations) best_heldout_iteration $(bw.best_heldout_iteration)",
        "TRAINING VITERBI_TRAINING iterations $(vt.iterations) converged $(vt.converged ? "yes" : "no")","TRAINING SUPERVISED smoothing $(selected.candidate)"]
    preferences = zeros(Int,length(models))
    for i in eachindex(decoded[1])
        preferences[argmax([results[i].fb.loglik for results in decoded])] += 1
    end
    push!(lines,"PREFERENCE "*join(("$(model.name) $count" for (model,count) in zip(models,preferences))," "))
    positions = sum(length(result.viterbi) for result in decoded[1])
    for a in 1:length(models)-1,b in a+1:length(models)
        correct = sum(correct_count(
            left.viterbi,
            right.viterbi
        ) for (left,right) in zip(decoded[a],decoded[b]))
        push!(lines,"AGREEMENT $(models[a].name) $(models[b].name) $(fraction(correct,positions))")
    end
    for (i,name) in enumerate(("VITERBI","POSTERIOR"))
        best = argmax([row[i] for row in scores])
        push!(lines,"BEST $name $(models[best].name) accuracy $(fraction(scores[best][i],test_positions))")
    end
    lines
end
function join_blocks(blocks)
    lines = String[]
    for block in blocks
        isempty(lines) || push!(lines,"")
        append!(lines,block)
    end
    lines
end
function main()
    initial,sequence_rows,labeled_rows,parameter_rows = read_inputs()
    params = interpret_parameters(parameter_rows,initial)
    sequences,training,testing,rejections = validate_inputs(sequence_rows,labeled_rows,initial,params)
    observations = [r.observations for r in sequences]
    heldout = [r.observations for r in vcat(training,testing)]
    bw,bw_trace,bw_summary = train_baum_welch(initial,observations,heldout,params)
    vt,vt_trace,vt_summary = train_viterbi(initial,observations,params)
    supervised,selected,cv_lines = cross_validate(initial,training,params)
    learning_lines = learning_curve(initial,training,testing,selected.alpha)
    models = [initial,bw,vt,supervised]
    evaluation_blocks,scores = Vector{String}[],Vector{Int}[]
    for model in models
        blocks,correct = evaluate_model(model,testing,params)
        append!(evaluation_blocks,blocks)
        push!(scores,correct)
    end
    push!(evaluation_blocks,cv_lines,learning_lines)
    decoded = [[decode(model,r.observations) for r in sequences] for model in models]
    decoding_lines,segment_lines = annotate_sequences(bw,sequences,decoded[2],params)
    sample_lines = synthetic_output(bw,params)
    report_blocks = [input_report(
        initial,
        sequences,
        training,
        testing,
        rejections,
        length(sequence_rows),
        length(labeled_rows)÷2
    )]
    test_positions = sum(length(r.observations) for r in testing)
    push!(report_blocks,training_report(models,bw_summary,vt_summary,selected,decoded,scores,test_positions))
    for (model,results) in zip(models,decoded)
        push!(report_blocks,model_diagnostics(model,sequences,results,training,testing,params))
    end
    reports = [("trained_model.txt",join_blocks(model_lines.(models[2:end]))),("loglik_trace.csv",bw_trace),("viterbi_trace.csv",vt_trace),
        ("decodings.txt",decoding_lines),("segments.csv",segment_lines),("samples.txt",sample_lines),(
            "evaluation.txt",
            join_blocks(evaluation_blocks)
        ),("report.txt",join_blocks(report_blocks))]
    for (name,lines) in reports
        write_lines(name,lines)
    end
end
main()
