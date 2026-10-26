include("tokenizer.jl")
include("vocabulary.jl")
include("naive_bayes.jl")
include("rocchio.jl")
include("evaluation.jl")

const MODEL_NAMES = ["multinomial", "bernoulli", "complement", "rocchio", "vote"]
const MODEL_PAIRS = [(1, 2), (1, 3), (1, 4), (2, 3), (2, 4), (3, 4)]
const FOLD_COUNT = 5
read_lines(name::String) = readlines(joinpath("input", name))
write_lines(name::String, lines::Vector{String}) = write(joinpath("output", name), join(lines, '\n') * "\n")
function join_parts(parts::Vector{Vector{String}})
    lines = String[]
    for part in parts
        isempty(lines) || push!(lines, "")
        append!(lines, part)
    end
    lines
end
function hundredths(text::AbstractString)
    fields = split(text, '.')
    parse(Int, fields[1]) * 100 + parse(Int, fields[2])
end
hundredths_text(value::Int) = string(value ÷ 100) * "." * lpad(string(value % 100), 2, '0')
class_counts_text(names::Vector{String}, counts::Vector{Int}) = join(["$name $value" for (name, value) in zip(names, counts)], ' ')
function ranked_ratios(entries::Vector{NTuple{3,Int}})
    sort(entries; lt = (a, b) -> begin
        left, right = a[1] * b[2], b[1] * a[2]
        left == right ? a[3] < b[3] : left > right
    end)
end
function majority_vote(labels::Vector{Int}, class_count::Int)
    votes = zeros(Int, class_count)
    for label in labels
        votes[label] += 1
    end
    winner = labels[1]
    for label in labels
        votes[label] > votes[winner] && (winner = label)
    end
    Prediction(winner, votes[winner] / length(labels), Int[], Float64[], Float64[], 0.0, 0.0)
end
struct Settings
    alphas::Vector{Int}
    min_df::Int
    features::Int
    bigrams::Bool
    top::Int
    curve::Vector{Int}
    sizes::Vector{Int}
    thresholds::Vector{Int}
    lengths::Vector{Int}
    iterations::Int
    weight::Int
    resamples::Int
    seed::Int
end
function Settings(lines::Vector{String})
    values = Dict{String,Vector{String}}()
    for line in lines
        fields = String.(split(line, ' '))
        values[fields[1]] = fields[2:end]
    end
    Settings(hundredths.(values["ALPHAS"]), parse(Int, values["MIN_DF"][1]), parse(Int, values["FEATURES"][1]),
        values["BIGRAMS"][1] == "yes", parse(Int, values["TOP"][1]), parse.(Int, values["CURVE"]),
        parse.(Int, values["SIZES"]), hundredths.(values["THRESHOLDS"]), parse.(Int, values["LENGTHS"]),
        parse(Int, values["EM_ITERATIONS"][1]), hundredths(values["EM_WEIGHT"][1]),
        parse(Int, values["BOOTSTRAP"][1]), parse(Int, values["BOOTSTRAP"][2]))
end
struct Document
    name::String
    label::Union{Nothing,Int}
    tokens::Tokens
end
struct FoldSummary
    train::Int
    validate::Int
    candidates::Int
    vocabulary::Int
end
struct CrossValidationRun
    predictions::Vector{Int}
    evaluation::Evaluation
    fold_correct::Vector{Int}
end
function CrossValidationRun(predictions::Vector{Int}, truths::Vector{Int}, classes::Int)
    fold_correct = zeros(Int, FOLD_COUNT)
    for index in eachindex(truths)
        truths[index] == predictions[index] && (fold_correct[(index - 1) % FOLD_COUNT + 1] += 1)
    end
    CrossValidationRun(predictions, Evaluation(classes, truths, predictions), fold_correct)
end
mutable struct Training
    bigrams::Bool
    vocabulary::Vocabulary
    counts::TrainingCounts
    rocchio::Rocchio
    models::Vector{NaiveBayes}
end
function Training(documents::Vector{Document}, bigrams::Bool, classes::Int, min_df::Int, size::Int)
    sequences = [terms(document.tokens, bigrams) for document in documents]
    labels = Int[document.label for document in documents]
    vocabulary = Vocabulary(sequences, labels, classes, min_df, size)
    encoded = [encode(vocabulary, sequence) for sequence in sequences]
    counts = TrainingCounts(encoded, labels, classes, vocabulary_size(vocabulary))
    rocchio = Rocchio(encoded, labels, classes, vocabulary.frequencies)
    Training(bigrams, vocabulary, counts, rocchio, NaiveBayes[])
end
function train!(training::Training, alphas::Vector{Int})
    training.models = [train_model(kind, training.counts, alphas[kind]) for kind in 1:3]
end
encode(training::Training, document::Document) = encode(training.vocabulary, terms(document.tokens, training.bigrams))
classify(training::Training, model::Int, sequence::Vector{Int}) = model == 4 ? predict(training.rocchio, sequence) : predict(training.models[model], sequence)
struct Experiment
    settings::Settings
    classes::Vector{String}
    training::Vector{Document}
    tests::Vector{Document}
    unlabelled::Vector{Document}
    labelled::Vector{Int}
    truths::Vector{Int}
    folds::Vector{FoldSummary}
    cv_runs::Vector{Vector{CrossValidationRun}}
    selected_positions::Vector{Int}
    selected::Vector{Int}
    final_training::Training
    test_sequences::Vector{Vector{Int}}
    predictions::Vector{Vector{Prediction}}
    correct::Vector{Vector{Bool}}
end
function Experiment()
    settings = Settings(read_lines("params.txt"))
    stopwords = Set(read_lines("stopwords.txt"))
    rows = [String.(split(line, '\t')) for line in read_lines("train.txt")]
    classes = sort!(collect(Set(row[1] for row in rows)))
    positions = Dict(name => label for (label, name) in enumerate(classes))
    training = [Document(string(index), positions[row[1]], Tokens(row[2], stopwords)) for (index, row) in enumerate(rows)]
    tests = Document[]
    for line in read_lines("test.txt")
        fields = String.(split(line, '\t'))
        push!(tests, Document(fields[1], get(positions, fields[2], nothing), Tokens(fields[3], stopwords)))
    end
    unlabelled = [Document(string(index), nothing, Tokens(text, stopwords)) for (index, text) in enumerate(read_lines("unlabelled.txt"))]
    labelled = [index for index in eachindex(tests) if tests[index].label !== nothing]
    truths = Int[tests[index].label for index in labelled]
    training_truths = Int[document.label for document in training]
    nb_predictions = [[zeros(Int, length(training)) for _ in settings.alphas] for _ in 1:3]
    rocchio_predictions = zeros(Int, length(training))
    folds = FoldSummary[]
    for fold in 1:FOLD_COUNT
        members = [document for (index, document) in enumerate(training) if (index - 1) % FOLD_COUNT + 1 != fold]
        held_out = [index for index in eachindex(training) if (index - 1) % FOLD_COUNT + 1 == fold]
        fitted = Training(members, settings.bigrams, length(classes), settings.min_df, settings.features)
        push!(folds, FoldSummary(length(members), length(held_out), fitted.vocabulary.candidate_count, vocabulary_size(fitted.vocabulary)))
        sequences = [encode(fitted, training[index]) for index in held_out]
        for kind in 1:3, (a, alpha) in enumerate(settings.alphas)
            model = train_model(kind, fitted.counts, alpha)
            for (index, sequence) in zip(held_out, sequences)
                nb_predictions[kind][a][index] = predict(model, sequence).label
            end
        end
        for (index, sequence) in zip(held_out, sequences)
            rocchio_predictions[index] = predict(fitted.rocchio, sequence).label
        end
    end
    cv_runs = [[CrossValidationRun(labels, training_truths, length(classes)) for labels in runs] for runs in nb_predictions]
    push!(cv_runs, [CrossValidationRun(rocchio_predictions, training_truths, length(classes))])
    selected_positions = ones(Int, 3)
    for kind in 1:3, a in 2:length(settings.alphas)
        if rounded(cv_runs[kind][a].evaluation.macro_f1) > rounded(cv_runs[kind][selected_positions[kind]].evaluation.macro_f1)
            selected_positions[kind] = a
        end
    end
    selected = [settings.alphas[position] for position in selected_positions]
    final_training = Training(training, settings.bigrams, length(classes), settings.min_df, settings.features)
    train!(final_training, selected)
    test_sequences = [encode(final_training, document) for document in tests]
    predictions = [[classify(final_training, model, sequence) for sequence in test_sequences] for model in 1:4]
    votes = [majority_vote([predictions[model][index].label for model in 1:4], length(classes)) for index in eachindex(tests)]
    push!(predictions, votes)
    correct = [[predictions[model][index].label == tests[index].label for index in labelled] for model in 1:5]
    Experiment(settings, classes, training, tests, unlabelled, labelled, truths, folds, cv_runs, selected_positions,
        selected, final_training, test_sequences, predictions, correct)
end
alpha_text(experiment::Experiment, model::Int) = model <= 3 ? hundredths_text(experiment.selected[model]) : "-"
selected_run(experiment::Experiment, model::Int) = experiment.cv_runs[model][model <= 3 ? experiment.selected_positions[model] : 1]
function trained(experiment::Experiment, documents::Vector{Document}, bigrams::Bool, size::Int)
    fitted = Training(documents, bigrams, length(experiment.classes), experiment.settings.min_df, size)
    train!(fitted, experiment.selected)
    fitted
end
function test_evaluations(experiment::Experiment, fitted::Training)
    sequences = [encode(fitted, experiment.tests[index]) for index in experiment.labelled]
    [Evaluation(length(experiment.classes), experiment.truths, [classify(fitted, model, sequence).label for sequence in sequences]) for model in 1:4]
end
function vocabulary_lines(experiment::Experiment)
    vocabulary = experiment.final_training.vocabulary
    lines = ["documents $(length(experiment.training)) terms $(vocabulary.term_count) candidates $(vocabulary.candidate_count) vocabulary $(vocabulary_size(vocabulary))"]
    for (rank, entry) in enumerate(vocabulary.ranking)
        push!(lines, "$rank $(entry.term) $(entry.frequency) $(real_text(entry.score)) $(experiment.classes[entry.best_class])")
    end
    lines
end
function cv_lines(experiment::Experiment)
    lines = ["model,alpha,correct,accuracy,macro_f1,selected"]
    for kind in 1:3, (position, alpha) in enumerate(experiment.settings.alphas)
        chosen = alpha == experiment.selected[kind] ? "yes" : "no"
        push!(lines, "$(MODEL_NAMES[kind]),$(hundredths_text(alpha)),$(evaluation_fields(experiment.cv_runs[kind][position].evaluation)),$chosen")
    end
    push!(lines, "rocchio,-,$(evaluation_fields(experiment.cv_runs[4][1].evaluation)),yes")
    lines
end
function prediction_lines(experiment::Experiment)
    lines = ["id,model,label,score"]
    for (index, document) in enumerate(experiment.tests), model in 1:5
        prediction = experiment.predictions[model][index]
        push!(lines, "$(document.name),$(MODEL_NAMES[model]),$(experiment.classes[prediction.label]),$(real_text(prediction.score))")
    end
    lines
end
function curve_lines(experiment::Experiment)
    lines = ["size,vocabulary,model,correct,accuracy,macro_f1"]
    for size in experiment.settings.curve
        fitted = trained(experiment, experiment.training[1:size], experiment.settings.bigrams, experiment.settings.features)
        for (model, evaluation) in enumerate(test_evaluations(experiment, fitted))
            push!(lines, "$size,$(vocabulary_size(fitted.vocabulary)),$(MODEL_NAMES[model]),$(evaluation_fields(evaluation))")
        end
    end
    lines
end
function feature_lines(experiment::Experiment)
    lines = ["terms,features,vocabulary,model,correct,accuracy,macro_f1"]
    for (kind, bigrams) in [("unigrams", false), ("bigrams", true)], size in experiment.settings.sizes
        fitted = trained(experiment, experiment.training, bigrams, size)
        for (model, evaluation) in enumerate(test_evaluations(experiment, fitted))
            push!(lines, "$kind,$size,$(vocabulary_size(fitted.vocabulary)),$(MODEL_NAMES[model]),$(evaluation_fields(evaluation))")
        end
    end
    lines
end
function data_part(experiment::Experiment)
    vocabulary = experiment.final_training.vocabulary
    settings = experiment.settings
    lines = ["documents train $(length(experiment.training)) test $(length(experiment.tests)) labelled $(length(experiment.labelled)) unlabelled $(length(experiment.unlabelled)) classes $(length(experiment.classes))"]
    train_counts = zeros(Int, length(experiment.classes))
    test_counts = zeros(Int, length(experiment.classes))
    for document in experiment.training
        train_counts[document.label] += 1
    end
    for truth in experiment.truths
        test_counts[truth] += 1
    end
    for (label, name) in enumerate(experiment.classes)
        push!(lines, "class $name train $(train_counts[label]) test $(test_counts[label])")
    end
    raw = stopwords = short = kept = bigrams = 0
    distinct_terms = Set{String}()
    for document in experiment.training
        tokens = document.tokens
        raw += tokens.raw_count
        stopwords += tokens.stopword_count
        short += tokens.short_count
        kept += length(tokens.words)
        settings.bigrams && (bigrams += length(tokens.bigrams))
        union!(distinct_terms, terms(tokens, settings.bigrams))
    end
    distinct_bigrams = count(term -> occursin('_', term), distinct_terms)
    push!(lines, "train_tokens raw $raw stopwords $stopwords short $short unigrams $kept bigrams $bigrams")
    push!(lines, "train_terms unigrams $(length(distinct_terms) - distinct_bigrams) bigrams $distinct_bigrams candidates $(vocabulary.candidate_count) vocabulary $(vocabulary_size(vocabulary))")
    total = sum(length(terms(document.tokens, settings.bigrams)) for document in experiment.tests)
    in_vocabulary = sum(length(sequence) for sequence in experiment.test_sequences)
    push!(lines, "test_terms total $total in_vocabulary $in_vocabulary")
    occurrences = Dict{String,Int}()
    for document in experiment.tests, word in document.tokens.words
        if !haskey(vocabulary.index, word)
            occurrences[word] = get(occurrences, word, 0) + 1
        end
    end
    ranked = sort!(collect(occurrences); by = entry -> (-entry.second, entry.first))
    fields = ["test_oov"]
    for (word, frequency) in ranked[1:min(settings.top, length(ranked))]
        push!(fields, "$word $frequency")
    end
    push!(lines, join(fields, ' '))
    lines
end
function folds_part(experiment::Experiment)
    lines = ["folds $FOLD_COUNT"]
    for (fold, summary) in enumerate(experiment.folds)
        push!(lines, "fold $fold train $(summary.train) validate $(summary.validate) candidates $(summary.candidates) vocabulary $(summary.vocabulary)")
    end
    lines
end
function selection_part(experiment::Experiment)
    lines = ["selection"]
    for model in 1:4
        run = selected_run(experiment, model)
        evaluation = run.evaluation
        push!(lines, "$(MODEL_NAMES[model]) alpha $(alpha_text(experiment, model)) correct $(proportion_text(evaluation.correct, evaluation.total)) macro_f1 $(real_text(evaluation.macro_f1)) folds $(join(run.fold_correct, ' '))")
    end
    lines
end
function cross_validation_part(experiment::Experiment, model::Int)
    vcat(["cross_validation $(MODEL_NAMES[model]) alpha $(alpha_text(experiment, model))"], evaluation_lines(selected_run(experiment, model).evaluation, experiment.classes))
end
function test_part(experiment::Experiment, model::Int)
    predicted = [experiment.predictions[model][index].label for index in experiment.labelled]
    evaluation = Evaluation(length(experiment.classes), experiment.truths, predicted)
    lines = ["test $(MODEL_NAMES[model]) alpha $(alpha_text(experiment, model))", "labelled $(length(experiment.labelled)) correct $(proportion_text(evaluation.correct, evaluation.total))"]
    if model <= 4
        top_two = count(index -> experiment.tests[index].label in experiment.predictions[model][index].ranking[1:2], experiment.labelled)
        push!(lines, "top2 $(proportion_text(top_two, length(experiment.labelled)))")
    end
    append!(lines, evaluation_lines(evaluation, experiment.classes))
    lines
end
function probability_part(experiment::Experiment, model::Int)
    thresholds = experiment.settings.thresholds
    limits = [value / 100 for value in thresholds]
    rows = zeros(Int, length(limits) + 1)
    hits = zeros(Int, length(rows))
    sums = zeros(length(rows))
    accepted = zeros(Int, length(limits))
    accepted_hits = zeros(Int, length(limits))
    loss = brier = 0.0
    for (position, index) in enumerate(experiment.labelled)
        prediction = experiment.predictions[model][index]
        truth = experiment.truths[position]
        gap = prediction.scores[truth] - prediction.scores[prediction.label]
        loss += log(prediction.normalizer) - gap
        squares = 0.0
        for (label, probability) in enumerate(prediction.probabilities)
            difference = probability - (label == truth ? 1.0 : 0.0)
            squares += difference * difference
        end
        brier += squares
        bucket = count(limit -> prediction.score >= limit, limits) + 1
        rows[bucket] += 1
        sums[bucket] += prediction.score
        experiment.correct[model][position] && (hits[bucket] += 1)
        for (t, limit) in enumerate(limits)
            if prediction.score >= limit
                accepted[t] += 1
                experiment.correct[model][position] && (accepted_hits[t] += 1)
            end
        end
    end
    labelled_count = length(experiment.labelled)
    lines = ["probability $(MODEL_NAMES[model]) alpha $(alpha_text(experiment, model))", "log_loss $(real_text(loss / labelled_count)) brier $(real_text(brier / labelled_count))"]
    for (bucket, bound) in enumerate(vcat(0, thresholds))
        line = "bin $(hundredths_text(bound)) rows $(rows[bucket])"
        if rows[bucket] > 0
            line *= " correct $(proportion_text(hits[bucket], rows[bucket])) mean $(real_text(sums[bucket] / rows[bucket]))"
        end
        push!(lines, line)
    end
    for (t, threshold) in enumerate(thresholds)
        precise = accepted[t] > 0 ? proportion_text(accepted_hits[t], accepted[t]) : "-"
        push!(lines, "threshold $(hundredths_text(threshold)) covered $(proportion_text(accepted[t], labelled_count)) correct $precise")
    end
    lines
end
function lengths_part(experiment::Experiment)
    boundaries = experiment.settings.lengths
    rows = zeros(Int, length(boundaries) + 1)
    hits = [zeros(Int, length(rows)) for _ in 1:5]
    for (position, index) in enumerate(experiment.labelled)
        bucket = count(bound -> length(experiment.test_sequences[index]) >= bound, boundaries) + 1
        rows[bucket] += 1
        for model in 1:5
            experiment.correct[model][position] && (hits[model][bucket] += 1)
        end
    end
    lines = ["lengths"]
    for (bucket, bound) in enumerate(vcat(0, boundaries))
        line = "length $bound rows $(rows[bucket])"
        if rows[bucket] > 0
            for model in 1:5
                line *= " $(MODEL_NAMES[model]) $(proportion_text(hits[model][bucket], rows[bucket]))"
            end
        end
        push!(lines, line)
    end
    lines
end
function comparison_part(experiment::Experiment)
    lines = ["comparison"]
    for (first, second) in MODEL_PAIRS
        agree = count(index -> experiment.predictions[first][index].label == experiment.predictions[second][index].label, eachindex(experiment.tests))
        b = count(position -> experiment.correct[first][position] && !experiment.correct[second][position], eachindex(experiment.labelled))
        c = count(position -> experiment.correct[second][position] && !experiment.correct[first][position], eachindex(experiment.labelled))
        difference = max(0, abs(b - c) - 1)
        statistic = b + c == 0 ? fraction_text(0, 1) : fraction_text(difference * difference, b + c)
        push!(lines, "$(MODEL_NAMES[first]) $(MODEL_NAMES[second]) agree $(proportion_text(agree, length(experiment.tests))) b $b c $c statistic $statistic")
    end
    errors = zeros(Int, 5)
    for position in eachindex(experiment.labelled)
        wrong = count(model -> !experiment.correct[model][position], 1:4)
        errors[wrong + 1] += 1
    end
    push!(lines, "errors " * join(["$(wrong - 1) $frequency" for (wrong, frequency) in enumerate(errors)], ' '))
    lines
end
function bootstrap_part(experiment::Experiment)
    settings = experiment.settings
    labelled_count = length(experiment.labelled)
    state = settings.seed
    totals = [Int[] for _ in 1:5]
    for _ in 1:settings.resamples
        chosen = Int[]
        for _ in 1:labelled_count
            state = 48271 * state % 2147483647
            push!(chosen, state % labelled_count + 1)
        end
        for model in 1:5
            push!(totals[model], count(position -> experiment.correct[model][position], chosen))
        end
    end
    rank = settings.resamples ÷ 40 + 1
    lines = ["bootstrap resamples $(settings.resamples) seed $(settings.seed)"]
    for model in 1:5
        ordered = sort(totals[model])
        mean_value = sum(ordered) / (settings.resamples * labelled_count)
        low, high = ordered[rank], ordered[length(ordered) + 1 - rank]
        push!(lines, "$(MODEL_NAMES[model]) mean $(real_text(mean_value)) low $(proportion_text(low, labelled_count)) high $(proportion_text(high, labelled_count))")
    end
    for (first, second) in MODEL_PAIRS
        wins = ties = losses = 0
        for (one, other) in zip(totals[first], totals[second])
            if one > other
                wins += 1
            elseif one == other
                ties += 1
            else
                losses += 1
            end
        end
        push!(lines, "pair $(MODEL_NAMES[first]) $(MODEL_NAMES[second]) wins $wins ties $ties losses $losses")
    end
    lines
end
function hard_part(experiment::Experiment)
    hard = Tuple{Document,Vector{Int}}[]
    counts = zeros(Int, length(experiment.classes))
    for (index, document) in enumerate(experiment.training)
        predicted = [selected_run(experiment, model).predictions[index] for model in 1:4]
        if all(label -> label != document.label, predicted)
            counts[document.label] += 1
            push!(hard, (document, predicted))
        end
    end
    lines = ["hard_documents $(length(hard)) $(class_counts_text(experiment.classes, counts))"]
    for (document, predicted) in hard[1:min(experiment.settings.top, length(hard))]
        names = join(experiment.classes[predicted], ' ')
        push!(lines, "$(document.name) true $(experiment.classes[document.label]) predicted $names")
    end
    lines
end
function uncertain_part(experiment::Experiment)
    order = sort!(collect(eachindex(experiment.tests)); by = index -> (rounded(experiment.predictions[1][index].margin), index))
    shown = order[1:min(experiment.settings.top, length(order))]
    lines = ["uncertain multinomial $(length(shown))"]
    for index in shown
        document = experiment.tests[index]
        prediction = experiment.predictions[1][index]
        truth = document.label === nothing ? "?" : experiment.classes[document.label]
        push!(lines, "$(document.name) predicted $(experiment.classes[prediction.label]) runner_up $(experiment.classes[prediction.ranking[2]]) margin $(real_text(prediction.margin)) posterior $(real_text(prediction.score)) true $truth")
    end
    lines
end
function misclassified_part(experiment::Experiment)
    indices = [index for index in experiment.labelled if experiment.predictions[1][index].label != experiment.tests[index].label]
    lines = ["misclassified multinomial $(length(indices))"]
    counts = experiment.final_training.counts
    weights = experiment.final_training.models[1].weights
    alpha = experiment.selected[1]
    for index in indices
        document = experiment.tests[index]
        prediction = experiment.predictions[1][index]
        truth, predicted = document.label, prediction.label
        push!(lines, "$(document.name) true $(experiment.classes[truth]) predicted $(experiment.classes[predicted]) posterior $(real_text(prediction.score))")
        sequence = experiment.test_sequences[index]
        entries = [(100 * counts.occurrences[predicted][term] + alpha, 100 * counts.occurrences[truth][term] + alpha, term) for term in first_occurrences(sequence)]
        ranked = ranked_ratios(entries)
        for (_, _, term) in ranked[1:min(3, length(ranked))]
            frequency = count(==(term), sequence)
            evidence = weights[predicted][term] - weights[truth][term]
            push!(lines, "  $(experiment.final_training.vocabulary.terms[term]) count $frequency evidence $(real_text(evidence))")
        end
    end
    lines
end
function maximization(experiment::Experiment, posteriors::Vector{Prediction}, sequences::Vector{Vector{Int}})
    counts = experiment.final_training.counts
    weight = experiment.settings.weight / 100
    occurrences = [Float64.(row) for row in counts.occurrences]
    documents = Float64.(counts.documents)
    for (prediction, sequence) in zip(posteriors, sequences)
        frequencies = zeros(Int, counts.vocabulary_size)
        for term in sequence
            frequencies[term] += 1
        end
        selected_terms = first_occurrences(sequence)
        for label in eachindex(experiment.classes)
            share = weight * prediction.probabilities[label]
            documents[label] += share
            for term in selected_terms
                occurrences[label][term] += share * frequencies[term]
            end
        end
    end
    alpha = experiment.selected[1]
    weights = Vector{Float64}[]
    for row in occurrences
        total = 0.0
        for value in row
            total += value
        end
        push!(weights, [log((100.0 * value + alpha) / (100.0 * total + alpha * counts.vocabulary_size)) for value in row])
    end
    scale = length(experiment.training) + (experiment.settings.weight * length(experiment.unlabelled)) / 100
    priors = [log(value / scale) for value in documents]
    NaiveBayes(1, priors, zeros(length(experiment.classes)), weights)
end
function semi_supervised_part(experiment::Experiment)
    sequences = [encode(experiment.final_training, document) for document in experiment.unlabelled]
    model = experiment.final_training.models[1]
    previous = nothing
    lines = ["semi_supervised multinomial alpha $(alpha_text(experiment, 1)) weight $(hundredths_text(experiment.settings.weight)) unlabelled $(length(experiment.unlabelled))"]
    for iteration in 0:experiment.settings.iterations
        posteriors = [predict(model, sequence) for sequence in sequences]
        assignments = [prediction.label for prediction in posteriors]
        predicted = [predict(model, experiment.test_sequences[index]).label for index in experiment.labelled]
        evaluation = Evaluation(length(experiment.classes), experiment.truths, predicted)
        changed = previous === nothing ? "-" : string(count(pair -> pair[1] != pair[2], zip(previous, assignments)))
        assigned = zeros(Int, length(experiment.classes))
        for label in assignments
            assigned[label] += 1
        end
        push!(lines, "iteration $iteration correct $(proportion_text(evaluation.correct, evaluation.total)) macro_f1 $(real_text(evaluation.macro_f1)) changed $changed assigned $(class_counts_text(experiment.classes, assigned))")
        iteration < experiment.settings.iterations && (model = maximization(experiment, posteriors, sequences))
        previous = assignments
    end
    lines
end
function metrics_parts(experiment::Experiment)
    parts = [data_part(experiment), folds_part(experiment), selection_part(experiment)]
    append!(parts, [cross_validation_part(experiment, model) for model in 1:4])
    append!(parts, [test_part(experiment, model) for model in 1:5])
    append!(parts, [probability_part(experiment, model) for model in 1:3])
    append!(parts, [lengths_part(experiment), comparison_part(experiment), bootstrap_part(experiment), hard_part(experiment),
        uncertain_part(experiment), misclassified_part(experiment), semi_supervised_part(experiment)])
    parts
end
function top_feature_parts(experiment::Experiment)
    counts = experiment.final_training.counts
    size = counts.vocabulary_size
    parts = Vector{String}[]
    for kind in 1:2
        alpha = experiment.selected[kind]
        table = kind == 1 ? counts.occurrences : counts.containing
        totals = kind == 1 ? counts.totals : counts.documents
        overall = kind == 1 ? counts.total : counts.document_total
        outcomes = kind == 1 ? size : 2
        term_totals = [sum(row[term] for row in table) for term in 1:size]
        push!(parts, ["model $(MODEL_NAMES[kind]) alpha $(hundredths_text(alpha)) vocabulary $size top $(experiment.settings.top)"])
        for (label, name) in enumerate(experiment.classes)
            total = totals[label]
            other = overall - total
            lines = ["class $name total $total other $other"]
            entries = [(100 * table[label][term] + alpha, 100 * (term_totals[term] - table[label][term]) + alpha, term) for term in 1:size]
            ranked = ranked_ratios(entries)
            for (rank, (_, _, term)) in enumerate(ranked[1:min(experiment.settings.top, length(ranked))])
                frequency = table[label][term]
                other_count = term_totals[term] - frequency
                odds = smoothed_log(frequency, total, alpha, outcomes) - smoothed_log(other_count, other, alpha, outcomes)
                push!(lines, "$rank $(experiment.final_training.vocabulary.terms[term]) $frequency $other_count $(real_text(odds))")
            end
            push!(parts, lines)
        end
    end
    parts
end
function main()
    experiment = Experiment()
    mkpath("output")
    write_lines("vocabulary.txt", vocabulary_lines(experiment))
    write_lines("cv_results.csv", cv_lines(experiment))
    write_lines("predictions.csv", prediction_lines(experiment))
    write_lines("learning_curve.csv", curve_lines(experiment))
    write_lines("feature_study.csv", feature_lines(experiment))
    write_lines("metrics.txt", join_parts(metrics_parts(experiment)))
    write_lines("top_features.txt", join_parts(top_feature_parts(experiment)))
end

main()
