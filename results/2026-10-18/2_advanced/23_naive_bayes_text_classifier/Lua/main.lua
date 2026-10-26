local source_directory = arg[0]:match("^(.*[/\\])") or "./"
package.path = source_directory .. "?.lua;" .. package.path
local tokenizer = require("tokenizer")
local vocabulary = require("vocabulary")
local nb = require("naive_bayes")
local Rocchio = require("rocchio").Rocchio
local evaluation = require("evaluation")
local Evaluation = evaluation.Evaluation
local real_text, proportion_text, fraction_text = evaluation.real_text, evaluation.proportion_text, evaluation.fraction_text
local nb_models = nb.NB_MODELS
local base_models = {"multinomial", "bernoulli", "complement", "rocchio"}
local models = {"multinomial", "bernoulli", "complement", "rocchio", "vote"}
local model_pairs = {}
for first = 1, #base_models do
    for second = first + 1, #base_models do model_pairs[#model_pairs + 1] = {base_models[first], base_models[second]} end
end

local function zeros(count, value)
    local result = {}
    for index = 1, count do result[index] = value or 0 end
    return result
end
local function map(values, fn)
    local result = {}
    for index, value in ipairs(values) do result[index] = fn(value, index) end
    return result
end
local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function sum(values) local total = 0 for _, value in ipairs(values) do total = total + value end return total end
local function csv(values) return table.concat(map(values, function(value) return tostring(value) end), ",") end
local function read_lines(name)
    local lines = {}
    for line in io.lines("input/" .. name) do lines[#lines + 1] = line end
    return lines
end
local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end
local function join_parts(parts)
    local lines = {}
    for _, part in ipairs(parts) do if #lines > 0 then lines[#lines + 1] = "" end extend(lines, part) end
    return lines
end
local function hundredths(text)
    local whole, fraction = text:match("^(%d+)%.(%d%d)$")
    return tonumber(whole) * 100 + tonumber(fraction)
end
local function hundredths_text(value) return string.format("%d.%02d", value // 100, value % 100) end
local function class_counts_text(names, counts)
    local fields = {}
    for label, name in ipairs(names) do fields[#fields + 1] = name .. " " .. counts[label] end
    return table.concat(fields, " ")
end
local function bucket_of(value, boundaries)
    local bucket = 1
    for _, boundary in ipairs(boundaries) do if value >= boundary then bucket = bucket + 1 end end
    return bucket
end
local function rounded4(value) return math.floor(value * 10000 + 0.5) end
local function ranked_by_ratio(entries)
    table.sort(entries, function(a, b)
        local left, right = a.n * b.d, b.n * a.d
        return left > right or left == right and a.term < b.term
    end)
    return entries
end
local function evaluation_fields(value) return {value.correct, real_text(value.micro_f1), real_text(value.macro_f1)} end

local function read_settings()
    local values = {}
    for _, line in ipairs(read_lines("params.txt")) do
        local fields = {}
        for field in line:gmatch("[^ ]+") do fields[#fields + 1] = field end
        local key = table.remove(fields, 1)
        values[key] = fields
    end
    local function integers(key) return map(values[key], function(text) return tonumber(text) end) end
    return {alphas = map(values.ALPHAS, hundredths), min_df = tonumber(values.MIN_DF[1]), features = tonumber(values.FEATURES[1]),
        bigrams = values.BIGRAMS[1] == "yes", top = tonumber(values.TOP[1]), curve = integers("CURVE"), sizes = integers("SIZES"),
        thresholds = map(values.THRESHOLDS, hundredths), lengths = integers("LENGTHS"), iterations = tonumber(values.EM_ITERATIONS[1]),
        weight = hundredths(values.EM_WEIGHT[1]), resamples = tonumber(values.BOOTSTRAP[1]), seed = tonumber(values.BOOTSTRAP[2])}
end

local function majority_vote(labels, class_count)
    local votes, winner = zeros(class_count), labels[1]
    for _, label in ipairs(labels) do votes[label] = votes[label] + 1 end
    for _, label in ipairs(labels) do if votes[label] > votes[winner] then winner = label end end
    return {label = winner, score = votes[winner] / #labels}
end

local Training = {}
Training.__index = Training
function Training.new(documents, use_bigrams, class_count, min_df, size)
    local sequences = map(documents, function(document) return document.tokens:terms(use_bigrams) end)
    local labels = map(documents, function(document) return document.label end)
    local terms = vocabulary.Vocabulary.new(sequences, labels, class_count, min_df, size)
    local encoded = map(sequences, function(sequence) return terms:encode(sequence) end)
    return setmetatable({use_bigrams = use_bigrams, vocabulary = terms,
        counts = nb.TrainingCounts.new(encoded, labels, class_count, terms:size()),
        rocchio = Rocchio.new(encoded, labels, class_count, terms.frequencies), models = {}}, Training)
end
function Training:train(alphas)
    for _, kind in ipairs(nb_models) do self.models[kind] = nb.train_model(kind, self.counts, alphas[kind]) end
end
function Training:encode(document) return self.vocabulary:encode(document.tokens:terms(self.use_bigrams)) end
function Training:classify(model, sequence)
    return (model == "rocchio" and self.rocchio or self.models[model]):predict(sequence)
end

local Experiment = {}
Experiment.__index = Experiment
function Experiment.new()
    local self = setmetatable({settings = read_settings(), classes = {}, training = {}, tests = {}, unlabelled = {}, labelled = {}, truths = {}}, Experiment)
    local stopwords, rows, seen, positions = {}, {}, {}, {}
    for _, word in ipairs(read_lines("stopwords.txt")) do stopwords[word] = true end
    for _, line in ipairs(read_lines("train.txt")) do
        local label, text = line:match("^([^\t]+)\t(.*)$")
        rows[#rows + 1] = {label, text}
        if not seen[label] then seen[label] = true self.classes[#self.classes + 1] = label end
    end
    table.sort(self.classes)
    self.class_count = #self.classes
    for label, name in ipairs(self.classes) do positions[name] = label end
    for number, row in ipairs(rows) do self.training[number] = {name = tostring(number), label = positions[row[1]], tokens = tokenizer.Tokens.new(row[2], stopwords)} end
    for _, line in ipairs(read_lines("test.txt")) do
        local name, label, text = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
        local truth = label ~= "?" and positions[label] or false
        self.tests[#self.tests + 1] = {name = name, label = truth, tokens = tokenizer.Tokens.new(text, stopwords)}
        if truth then self.labelled[#self.labelled + 1], self.truths[#self.truths + 1] = #self.tests, truth end
    end
    for number, text in ipairs(read_lines("unlabelled.txt")) do self.unlabelled[number] = {name = tostring(number), label = false, tokens = tokenizer.Tokens.new(text, stopwords)} end
    return self
end
function Experiment:trained(documents, use_bigrams, size)
    local training = Training.new(documents, use_bigrams, self.class_count, self.settings.min_df, size)
    training:train(self.selected)
    return training
end
function Experiment:alpha_text(model) return self.selected[model] and hundredths_text(self.selected[model]) or "-" end
function Experiment:cross_validation_run(predictions)
    local truths = map(self.training, function(document) return document.label end)
    local fold_correct = zeros(5)
    for index, truth in ipairs(truths) do
        if truth == predictions[index] then local fold = (index - 1) % 5 + 1 fold_correct[fold] = fold_correct[fold] + 1 end
    end
    return {predictions = predictions, evaluation = Evaluation.new(self.class_count, truths, predictions), fold_correct = fold_correct}
end
function Experiment:cross_validate()
    local settings, count, predictions, rocchio_predictions = self.settings, #self.training, {}, zeros(#self.training, 1)
    for _, kind in ipairs(nb_models) do
        predictions[kind] = {}
        for alpha = 1, #settings.alphas do predictions[kind][alpha] = zeros(count, 1) end
    end
    self.folds = {}
    for fold = 1, 5 do
        local members, held_out = {}, {}
        for index, document in ipairs(self.training) do
            if (index - 1) % 5 + 1 == fold then held_out[#held_out + 1] = index else members[#members + 1] = document end
        end
        local training = Training.new(members, settings.bigrams, self.class_count, settings.min_df, settings.features)
        self.folds[fold] = {train_count = #members, validate_count = #held_out, candidate_count = training.vocabulary.candidate_count, vocabulary_size = training.vocabulary:size()}
        local sequences = map(held_out, function(index) return training:encode(self.training[index]) end)
        for _, kind in ipairs(nb_models) do
            for position, alpha in ipairs(settings.alphas) do
                local model = nb.train_model(kind, training.counts, alpha)
                for item, index in ipairs(held_out) do predictions[kind][position][index] = model:predict(sequences[item]).label end
            end
        end
        for item, index in ipairs(held_out) do rocchio_predictions[index] = training.rocchio:predict(sequences[item]).label end
    end
    self.cv_runs = {}
    for _, kind in ipairs(nb_models) do self.cv_runs[kind] = map(predictions[kind], function(labels) return self:cross_validation_run(labels) end) end
    self.cv_runs.rocchio = {self:cross_validation_run(rocchio_predictions)}
end
function Experiment:select_alphas()
    self.selected, self.selected_runs = {}, {}
    for _, kind in ipairs(nb_models) do
        local runs, best = self.cv_runs[kind], 1
        for position = 2, #runs do
            if rounded4(runs[position].evaluation.macro_f1) > rounded4(runs[best].evaluation.macro_f1) then best = position end
        end
        self.selected[kind], self.selected_runs[kind] = self.settings.alphas[best], runs[best]
    end
    self.selected_runs.rocchio = self.cv_runs.rocchio[1]
end
function Experiment:train_final()
    self.final = self:trained(self.training, self.settings.bigrams, self.settings.features)
    self.test_sequences = map(self.tests, function(document) return self.final:encode(document) end)
    self.predictions, self.correct = {}, {}
    for _, model in ipairs(base_models) do self.predictions[model] = map(self.test_sequences, function(sequence) return self.final:classify(model, sequence) end) end
    self.predictions.vote = map(self.tests, function(_, index)
        return majority_vote(map(base_models, function(model) return self.predictions[model][index].label end), self.class_count)
    end)
    for _, model in ipairs(models) do self.correct[model] = map(self.labelled, function(index) return self.predictions[model][index].label == self.tests[index].label end) end
end
function Experiment:test_evaluations(training)
    local sequences = map(self.labelled, function(index) return training:encode(self.tests[index]) end)
    return map(base_models, function(model)
        local predicted = map(sequences, function(sequence) return training:classify(model, sequence).label end)
        return Evaluation.new(self.class_count, self.truths, predicted)
    end)
end

function Experiment:vocabulary_lines()
    local terms = self.final.vocabulary
    local lines = {"documents " .. #self.training .. " terms " .. terms.term_count .. " candidates " .. terms.candidate_count .. " vocabulary " .. terms:size()}
    for rank, entry in ipairs(terms.ranking) do lines[#lines + 1] = rank .. " " .. entry.term .. " " .. entry.frequency .. " " .. real_text(entry.score) .. " " .. self.classes[entry.best_class] end
    return lines
end
function Experiment:cv_lines()
    local lines = {"model,alpha,correct,accuracy,macro_f1,selected"}
    for _, kind in ipairs(nb_models) do
        for position, alpha in ipairs(self.settings.alphas) do
            local fields = {kind, hundredths_text(alpha)}
            extend(fields, evaluation_fields(self.cv_runs[kind][position].evaluation))
            fields[#fields + 1] = alpha == self.selected[kind] and "yes" or "no"
            lines[#lines + 1] = csv(fields)
        end
    end
    local fields = {"rocchio", "-"}
    extend(fields, evaluation_fields(self.cv_runs.rocchio[1].evaluation))
    fields[#fields + 1] = "yes"
    lines[#lines + 1] = csv(fields)
    return lines
end
function Experiment:prediction_lines()
    local lines = {"id,model,label,score"}
    for index, document in ipairs(self.tests) do
        for _, model in ipairs(models) do local prediction = self.predictions[model][index] lines[#lines + 1] = csv({document.name, model, self.classes[prediction.label], real_text(prediction.score)}) end
    end
    return lines
end
function Experiment:curve_lines()
    local lines = {"size,vocabulary,model,correct,accuracy,macro_f1"}
    for _, size in ipairs(self.settings.curve) do
        local documents = {} for index = 1, size do documents[index] = self.training[index] end
        local training = self:trained(documents, self.settings.bigrams, self.settings.features)
        for position, result in ipairs(self:test_evaluations(training)) do
            local fields = {size, training.vocabulary:size(), base_models[position]}
            extend(fields, evaluation_fields(result))
            lines[#lines + 1] = csv(fields)
        end
    end
    return lines
end
function Experiment:feature_lines()
    local lines = {"terms,features,vocabulary,model,correct,accuracy,macro_f1"}
    for _, kind in ipairs({{"unigrams", false}, {"bigrams", true}}) do
        for _, size in ipairs(self.settings.sizes) do
            local training = self:trained(self.training, kind[2], size)
            for position, result in ipairs(self:test_evaluations(training)) do
                local fields = {kind[1], size, training.vocabulary:size(), base_models[position]}
                extend(fields, evaluation_fields(result))
                lines[#lines + 1] = csv(fields)
            end
        end
    end
    return lines
end

function Experiment:data_part()
    local settings, terms = self.settings, self.final.vocabulary
    local lines = {"documents train " .. #self.training .. " test " .. #self.tests .. " labelled " .. #self.labelled .. " unlabelled " .. #self.unlabelled .. " classes " .. self.class_count}
    local train_counts, test_counts = zeros(self.class_count), zeros(self.class_count)
    for _, document in ipairs(self.training) do train_counts[document.label] = train_counts[document.label] + 1 end
    for _, truth in ipairs(self.truths) do test_counts[truth] = test_counts[truth] + 1 end
    for label, name in ipairs(self.classes) do lines[#lines + 1] = "class " .. name .. " train " .. train_counts[label] .. " test " .. test_counts[label] end
    local raw, stopwords, short, kept, bigrams, unique = 0, 0, 0, 0, 0, {}
    for _, document in ipairs(self.training) do
        local tokens = document.tokens
        raw, stopwords, short, kept = raw + tokens.raw_count, stopwords + tokens.stopword_count, short + tokens.short_count, kept + #tokens.words
        if settings.bigrams then bigrams = bigrams + #tokens.bigrams end
        for _, term in ipairs(tokens:terms(settings.bigrams)) do unique[term] = true end
    end
    local distinct, distinct_bigrams = 0, 0
    for term in pairs(unique) do distinct = distinct + 1 if tokenizer.is_bigram(term) then distinct_bigrams = distinct_bigrams + 1 end end
    lines[#lines + 1] = "train_tokens raw " .. raw .. " stopwords " .. stopwords .. " short " .. short .. " unigrams " .. kept .. " bigrams " .. bigrams
    lines[#lines + 1] = "train_terms unigrams " .. (distinct - distinct_bigrams) .. " bigrams " .. distinct_bigrams .. " candidates " .. terms.candidate_count .. " vocabulary " .. terms:size()
    local total, in_vocabulary, occurrences, ranked = 0, 0, {}, {}
    for index, document in ipairs(self.tests) do
        total, in_vocabulary = total + #document.tokens:terms(settings.bigrams), in_vocabulary + #self.test_sequences[index]
        for _, word in ipairs(document.tokens.words) do
            if not terms.index[word] then
                if not occurrences[word] then ranked[#ranked + 1] = word occurrences[word] = 0 end
                occurrences[word] = occurrences[word] + 1
            end
        end
    end
    lines[#lines + 1] = "test_terms total " .. total .. " in_vocabulary " .. in_vocabulary
    table.sort(ranked, function(a, b) return occurrences[a] > occurrences[b] or occurrences[a] == occurrences[b] and a < b end)
    local parts = {"test_oov"}
    for index = 1, math.min(settings.top, #ranked) do local word = ranked[index] parts[#parts + 1] = word .. " " .. occurrences[word] end
    lines[#lines + 1] = table.concat(parts, " ")
    return lines
end
function Experiment:folds_part()
    local lines = {"folds 5"}
    for fold, summary in ipairs(self.folds) do lines[#lines + 1] = "fold " .. fold .. " train " .. summary.train_count .. " validate " .. summary.validate_count .. " candidates " .. summary.candidate_count .. " vocabulary " .. summary.vocabulary_size end
    return lines
end
function Experiment:selection_part()
    local lines = {"selection"}
    for _, model in ipairs(base_models) do
        local run = self.selected_runs[model] local result = run.evaluation
        lines[#lines + 1] = model .. " alpha " .. self:alpha_text(model) .. " correct " .. proportion_text(result.correct, result.total) .. " macro_f1 " .. real_text(result.macro_f1) .. " folds " .. table.concat(run.fold_correct, " ")
    end
    return lines
end
function Experiment:cross_validation_part(model)
    local lines = {"cross_validation " .. model .. " alpha " .. self:alpha_text(model)}
    extend(lines, self.selected_runs[model].evaluation:lines(self.classes))
    return lines
end
function Experiment:test_part(model)
    local predictions = map(self.labelled, function(index) return self.predictions[model][index] end)
    local result = Evaluation.new(self.class_count, self.truths, map(predictions, function(prediction) return prediction.label end))
    local lines = {"test " .. model .. " alpha " .. self:alpha_text(model), "labelled " .. #predictions .. " correct " .. proportion_text(result.correct, #predictions)}
    if model ~= "vote" then
        local top_two = 0
        for index, prediction in ipairs(predictions) do if self.truths[index] == prediction.ranking[1] or self.truths[index] == prediction.ranking[2] then top_two = top_two + 1 end end
        lines[#lines + 1] = "top2 " .. proportion_text(top_two, #predictions)
    end
    extend(lines, result:lines(self.classes))
    return lines
end

function Experiment:probability_part(kind)
    local thresholds = self.settings.thresholds
    local limits = map(thresholds, function(value) return value / 100 end)
    local bin_rows, bin_correct, bin_sums = zeros(#limits + 1), zeros(#limits + 1), zeros(#limits + 1, 0.0)
    local accepted, accepted_correct, loss, brier = zeros(#limits), zeros(#limits), 0.0, 0.0
    for position, index in ipairs(self.labelled) do
        local prediction, truth, correct = self.predictions[kind][index], self.truths[position], self.correct[kind][position]
        local gap = prediction.scores[truth] - prediction.scores[prediction.label]
        loss = loss + (math.log(prediction.normalizer) - gap)
        local squares = 0.0
        for label, probability in ipairs(prediction.probabilities) do local difference = probability - (label == truth and 1.0 or 0.0) squares = squares + difference * difference end
        brier = brier + squares
        local bucket = bucket_of(prediction.score, limits)
        bin_rows[bucket], bin_sums[bucket] = bin_rows[bucket] + 1, bin_sums[bucket] + prediction.score
        if correct then bin_correct[bucket] = bin_correct[bucket] + 1 end
        for threshold, limit in ipairs(limits) do
            if prediction.score >= limit then accepted[threshold] = accepted[threshold] + 1 if correct then accepted_correct[threshold] = accepted_correct[threshold] + 1 end end
        end
    end
    local lines = {"probability " .. kind .. " alpha " .. self:alpha_text(kind), "log_loss " .. real_text(loss / #self.labelled) .. " brier " .. real_text(brier / #self.labelled)}
    local bounds = {0} extend(bounds, thresholds)
    for bucket, bound in ipairs(bounds) do
        local rows = bin_rows[bucket]
        local line = "bin " .. hundredths_text(bound) .. " rows " .. rows
        if rows > 0 then line = line .. " correct " .. proportion_text(bin_correct[bucket], rows) .. " mean " .. real_text(bin_sums[bucket] / rows) end
        lines[#lines + 1] = line
    end
    for position, threshold in ipairs(thresholds) do
        local precise = accepted[position] > 0 and proportion_text(accepted_correct[position], accepted[position]) or "-"
        lines[#lines + 1] = "threshold " .. hundredths_text(threshold) .. " covered " .. proportion_text(accepted[position], #self.labelled) .. " correct " .. precise
    end
    return lines
end

function Experiment:lengths_part()
    local boundaries, rows, correct = self.settings.lengths, zeros(#self.settings.lengths + 1), {}
    for _, model in ipairs(models) do correct[model] = zeros(#boundaries + 1) end
    for position, index in ipairs(self.labelled) do
        local bucket = bucket_of(#self.test_sequences[index], boundaries)
        rows[bucket] = rows[bucket] + 1
        for _, model in ipairs(models) do if self.correct[model][position] then correct[model][bucket] = correct[model][bucket] + 1 end end
    end
    local bounds, lines = {0}, {"lengths"}
    extend(bounds, boundaries)
    for bucket, bound in ipairs(bounds) do
        local parts = {"length " .. bound .. " rows " .. rows[bucket]}
        if rows[bucket] > 0 then for _, model in ipairs(models) do parts[#parts + 1] = model .. " " .. proportion_text(correct[model][bucket], rows[bucket]) end end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return lines
end
function Experiment:comparison_part()
    local lines = {"comparison"}
    for _, pair in ipairs(model_pairs) do
        local first, second, agree, b, c = pair[1], pair[2], 0, 0, 0
        for index = 1, #self.tests do if self.predictions[first][index].label == self.predictions[second][index].label then agree = agree + 1 end end
        for position = 1, #self.labelled do
            local one, other = self.correct[first][position], self.correct[second][position]
            if one and not other then b = b + 1 elseif other and not one then c = c + 1 end
        end
        local difference = math.max(0, math.abs(b - c) - 1)
        local statistic = b + c > 0 and fraction_text(difference * difference, b + c) or fraction_text(0, 1)
        lines[#lines + 1] = first .. " " .. second .. " agree " .. proportion_text(agree, #self.tests) .. " b " .. b .. " c " .. c .. " statistic " .. statistic
    end
    local errors = zeros(5)
    for position = 1, #self.labelled do
        local wrong = 0
        for _, model in ipairs(base_models) do if not self.correct[model][position] then wrong = wrong + 1 end end
        errors[wrong + 1] = errors[wrong + 1] + 1
    end
    local fields = {"errors"}
    for index, count in ipairs(errors) do fields[#fields + 1] = (index - 1) .. " " .. count end
    lines[#lines + 1] = table.concat(fields, " ")
    return lines
end
function Experiment:bootstrap_part()
    local settings, count, totals = self.settings, #self.labelled, {}
    local state = settings.seed
    for _, model in ipairs(models) do totals[model] = {} end
    for repetition = 1, settings.resamples do
        local chosen = {}
        for selection = 1, count do state = 48271 * state % 2147483647 chosen[selection] = state % count + 1 end
        for _, model in ipairs(models) do
            local correct = 0
            for _, position in ipairs(chosen) do if self.correct[model][position] then correct = correct + 1 end end
            totals[model][repetition] = correct
        end
    end
    local rank, lines = settings.resamples // 40 + 1, {"bootstrap resamples " .. settings.resamples .. " seed " .. settings.seed}
    for _, model in ipairs(models) do
        local ordered = map(totals[model], function(value) return value end)
        table.sort(ordered)
        local average = sum(ordered) / (settings.resamples * count)
        lines[#lines + 1] = model .. " mean " .. real_text(average) .. " low " .. proportion_text(ordered[rank], count) .. " high " .. proportion_text(ordered[#ordered + 1 - rank], count)
    end
    for _, pair in ipairs(model_pairs) do
        local first, second, wins, ties, losses = pair[1], pair[2], 0, 0, 0
        for index, one in ipairs(totals[first]) do
            local other = totals[second][index]
            if one > other then wins = wins + 1 elseif one == other then ties = ties + 1 else losses = losses + 1 end
        end
        lines[#lines + 1] = "pair " .. first .. " " .. second .. " wins " .. wins .. " ties " .. ties .. " losses " .. losses
    end
    return lines
end
function Experiment:hard_part()
    local hard, counts = {}, zeros(self.class_count)
    for index, document in ipairs(self.training) do
        local predicted, all_wrong = {}, true
        for _, model in ipairs(base_models) do
            local label = self.selected_runs[model].predictions[index]
            predicted[#predicted + 1] = label
            if label == document.label then all_wrong = false end
        end
        if all_wrong then hard[#hard + 1] = {document = document, predicted = predicted} counts[document.label] = counts[document.label] + 1 end
    end
    local lines = {"hard_documents " .. #hard .. " " .. class_counts_text(self.classes, counts)}
    for index = 1, math.min(self.settings.top, #hard) do
        local item = hard[index]
        local names = map(item.predicted, function(label) return self.classes[label] end)
        lines[#lines + 1] = item.document.name .. " true " .. self.classes[item.document.label] .. " predicted " .. table.concat(names, " ")
    end
    return lines
end
function Experiment:uncertain_part()
    local predictions, order = self.predictions.multinomial, {}
    for index = 1, #self.tests do order[index] = index end
    table.sort(order, function(a, b)
        local one, other = rounded4(predictions[a].margin), rounded4(predictions[b].margin)
        return one < other or one == other and a < b
    end)
    local shown = math.min(self.settings.top, #order)
    local lines = {"uncertain multinomial " .. shown}
    for position = 1, shown do
        local index = order[position]
        local document, prediction = self.tests[index], predictions[index]
        local truth = document.label and self.classes[document.label] or "?"
        lines[#lines + 1] = document.name .. " predicted " .. self.classes[prediction.label] .. " runner_up " .. self.classes[prediction.runner_up]
            .. " margin " .. real_text(prediction.margin) .. " posterior " .. real_text(prediction.score) .. " true " .. truth
    end
    return lines
end
function Experiment:evidence_lines(sequence, predicted, truth)
    local alpha, occurrences = self.selected.multinomial, self.final.counts.occurrences
    local weights, entries, frequencies = self.final.models.multinomial.weights, {}, {}
    for _, term in ipairs(sequence) do frequencies[term] = (frequencies[term] or 0) + 1 end
    for _, term in ipairs(vocabulary.first_occurrences(sequence)) do entries[#entries + 1] = {n = 100 * occurrences[predicted][term] + alpha, d = 100 * occurrences[truth][term] + alpha, term = term} end
    ranked_by_ratio(entries)
    local lines = {}
    for rank = 1, math.min(3, #entries) do
        local term = entries[rank].term
        lines[#lines + 1] = "  " .. self.final.vocabulary.terms[term] .. " count " .. frequencies[term] .. " evidence " .. real_text(weights[predicted][term] - weights[truth][term])
    end
    return lines
end
function Experiment:misclassified_part()
    local predictions, misclassified = self.predictions.multinomial, {}
    for _, index in ipairs(self.labelled) do if predictions[index].label ~= self.tests[index].label then misclassified[#misclassified + 1] = index end end
    local lines = {"misclassified multinomial " .. #misclassified}
    for _, index in ipairs(misclassified) do
        local document, prediction = self.tests[index], predictions[index]
        lines[#lines + 1] = document.name .. " true " .. self.classes[document.label] .. " predicted " .. self.classes[prediction.label] .. " posterior " .. real_text(prediction.score)
        extend(lines, self:evidence_lines(self.test_sequences[index], prediction.label, document.label))
    end
    return lines
end
function Experiment:maximization(posteriors, sequences)
    local settings, counts = self.settings, self.final.counts
    local weight = settings.weight / 100
    local occurrences = map(counts.occurrences, function(row) return map(row, function(count) return count + 0.0 end) end)
    local documents = map(counts.documents, function(count) return count + 0.0 end)
    for index, posterior in ipairs(posteriors) do
        local sequence, frequencies = sequences[index], {}
        for _, term in ipairs(sequence) do frequencies[term] = (frequencies[term] or 0) + 1 end
        local terms = vocabulary.first_occurrences(sequence)
        for label = 1, self.class_count do
            local share = weight * posterior.probabilities[label]
            documents[label] = documents[label] + share
            for _, term in ipairs(terms) do occurrences[label][term] = occurrences[label][term] + share * frequencies[term] end
        end
    end
    local alpha, size, weights = self.selected.multinomial, self.final.vocabulary:size(), {}
    for label, row in ipairs(occurrences) do
        local total = 0.0
        for _, value in ipairs(row) do total = total + value end
        weights[label] = map(row, function(value) return nb.smoothed_log(value, total, alpha, size) end)
    end
    local scale = #self.training + (settings.weight * #self.unlabelled) / 100
    local priors = map(documents, function(value) return math.log(value / scale) end)
    return nb.NaiveBayes.new("multinomial", priors, zeros(self.class_count, 0.0), weights)
end
function Experiment:semi_supervised_part()
    local settings = self.settings
    local sequences = map(self.unlabelled, function(document) return self.final:encode(document) end)
    local labelled_sequences = map(self.labelled, function(index) return self.test_sequences[index] end)
    local model, previous = self.final.models.multinomial, nil
    local lines = {"semi_supervised multinomial alpha " .. self:alpha_text("multinomial") .. " weight " .. hundredths_text(settings.weight) .. " unlabelled " .. #self.unlabelled}
    for iteration = 0, settings.iterations do
        local posteriors = map(sequences, function(sequence) return model:predict(sequence) end)
        local assignments = map(posteriors, function(posterior) return posterior.label end)
        local predicted = map(labelled_sequences, function(sequence) return model:predict(sequence).label end)
        local result = Evaluation.new(self.class_count, self.truths, predicted)
        local changed = "-"
        if previous then
            local count = 0
            for index, old in ipairs(previous) do if old ~= assignments[index] then count = count + 1 end end
            changed = tostring(count)
        end
        local assigned = zeros(self.class_count)
        for _, label in ipairs(assignments) do assigned[label] = assigned[label] + 1 end
        lines[#lines + 1] = "iteration " .. iteration .. " correct " .. proportion_text(result.correct, result.total) .. " macro_f1 " .. real_text(result.macro_f1)
            .. " changed " .. changed .. " assigned " .. class_counts_text(self.classes, assigned)
        if iteration < settings.iterations then model = self:maximization(posteriors, sequences) end
        previous = assignments
    end
    return lines
end
function Experiment:metrics_parts()
    local parts = {self:data_part(), self:folds_part(), self:selection_part()}
    for _, model in ipairs(base_models) do parts[#parts + 1] = self:cross_validation_part(model) end
    for _, model in ipairs(models) do parts[#parts + 1] = self:test_part(model) end
    for _, model in ipairs(nb_models) do parts[#parts + 1] = self:probability_part(model) end
    extend(parts, {self:lengths_part(), self:comparison_part(), self:bootstrap_part(), self:hard_part(), self:uncertain_part(), self:misclassified_part(), self:semi_supervised_part()})
    return parts
end
function Experiment:characteristic_parts(kind)
    local counts, terms = self.final.counts, self.final.vocabulary.terms
    local size, alpha = #terms, self.selected[kind]
    local counts_table, totals, overall, outcomes
    if kind == "multinomial" then counts_table, totals, overall, outcomes = counts.occurrences, counts.totals, counts.total, size
    else counts_table, totals, overall, outcomes = counts.containing, counts.documents, counts.document_total, 2 end
    local term_totals = zeros(size)
    for _, row in ipairs(counts_table) do for term, count in ipairs(row) do term_totals[term] = term_totals[term] + count end end
    local parts = {{"model " .. kind .. " alpha " .. hundredths_text(alpha) .. " vocabulary " .. size .. " top " .. self.settings.top}}
    for label, name in ipairs(self.classes) do
        local total, other = totals[label], overall - totals[label]
        local lines, entries = {"class " .. name .. " total " .. total .. " other " .. other}, {}
        for term, count in ipairs(counts_table[label]) do entries[#entries + 1] = {n = 100 * count + alpha, d = 100 * (term_totals[term] - count) + alpha, term = term} end
        ranked_by_ratio(entries)
        for rank = 1, math.min(self.settings.top, #entries) do
            local term = entries[rank].term
            local count, other_count = counts_table[label][term], term_totals[term] - counts_table[label][term]
            local log_odds = nb.smoothed_log(count, total, alpha, outcomes) - nb.smoothed_log(other_count, other, alpha, outcomes)
            lines[#lines + 1] = rank .. " " .. terms[term] .. " " .. count .. " " .. other_count .. " " .. real_text(log_odds)
        end
        parts[#parts + 1] = lines
    end
    return parts
end
function Experiment:top_feature_parts()
    local parts = {}
    for _, kind in ipairs({"multinomial", "bernoulli"}) do extend(parts, self:characteristic_parts(kind)) end
    return parts
end

local function main()
    local experiment = Experiment.new()
    experiment:cross_validate()
    experiment:select_alphas()
    experiment:train_final()
    os.execute("mkdir -p output")
    write_lines("vocabulary.txt", experiment:vocabulary_lines())
    write_lines("cv_results.csv", experiment:cv_lines())
    write_lines("predictions.csv", experiment:prediction_lines())
    write_lines("learning_curve.csv", experiment:curve_lines())
    write_lines("feature_study.csv", experiment:feature_lines())
    write_lines("metrics.txt", join_parts(experiment:metrics_parts()))
    write_lines("top_features.txt", join_parts(experiment:top_feature_parts()))
end

main()
