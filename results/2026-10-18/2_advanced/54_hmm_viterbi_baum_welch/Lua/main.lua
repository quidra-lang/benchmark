local model_io = require("model_io")
local inference = require("inference")
local training = require("training")
local evaluation = require("evaluation")
local sampler = require("sampler")
local real, fraction = model_io.real, evaluation.fraction
local initial, sequence_rows, labeled_rows, parameter_rows = model_io.read()
local parameters = {}
for _, row in ipairs(parameter_rows) do
    local values = {}
    for i = 2, #row do values[#values + 1] = row[i] end
    parameters[row[1]] = values
end
local function integer(key) return tonumber(parameters[key][1]) end
local iterations, pseudocount, folds = integer("iterations"), integer("pseudocount"), integer("folds")
local function index_of(values, target)
    for i, value in ipairs(values) do if value == target then return i end end
end
local segment_state = index_of(initial.states, parameters.segment_state[1])
local motif = {index_of(initial.symbols, parameters.motif[1]), index_of(initial.symbols, parameters.motif[2])}
local rich_symbols = {}
for _, symbol in ipairs(parameters.rich_symbols) do rich_symbols[index_of(initial.symbols, symbol)] = true end
local function append(target, source)
    for _, value in ipairs(source) do target[#target + 1] = value end
end
local function join_blocks(blocks)
    local result = {}
    for i, block in ipairs(blocks) do
        if i > 1 then result[#result + 1] = "" end
        append(result, block)
    end
    return result
end
local function rejection(name, text, labels, seen)
    if seen[name] then return "duplicate name" end
    seen[name] = true
    for t = 1, #text do
        local character = text:sub(t, t)
        if character ~= initial.missing and not index_of(initial.symbols, character) then
            return "invalid symbol " .. character .. " at position " .. t
        end
    end
    if labels then
        for t = 1, #labels do
            local character = labels:sub(t, t)
            if not index_of(initial.states, character) then return "invalid label " .. character .. " at position " .. t end
        end
        if #text ~= #labels then return "length mismatch " .. #text .. " " .. #labels end
    end
    if #text < integer("min_sequence_length") then return "too short " .. #text end
    local missing = 0
    for t = 1, #text do if text:sub(t, t) == initial.missing then missing = missing + 1 end end
    if 100 * missing > integer("max_missing_percent") * #text then return "too many missing " .. missing end
end
local function encode(text, alphabet, missing)
    local result = {}
    for t = 1, #text do
        local character = text:sub(t, t)
        result[t] = character == missing and -1 or index_of(alphabet, character)
    end
    return result
end
local sequences, train_records, test_records, rejections, seen = {}, {}, {}, {}, {}
for line, row in ipairs(sequence_rows) do
    local name, text = row[1], row[2]:upper()
    local reason = rejection(name, text, nil, seen)
    if reason then rejections[#rejections + 1] = "REJECT sequences.txt line " .. line .. " " .. name .. " " .. reason
    else sequences[#sequences + 1] = {name = name, observations = encode(text, initial.symbols, initial.missing)} end
end
seen = {}
for line = 1, #labeled_rows, 2 do
    local row, labels = labeled_rows[line], labeled_rows[line + 1][1]
    local name, text = row[1], row[3]:upper()
    local reason = rejection(name, text, labels, seen)
    if reason then rejections[#rejections + 1] = "REJECT labeled.txt line " .. line .. " " .. name .. " " .. reason
    else
        local target = row[2] == "TRAIN" and train_records or test_records
        target[#target + 1] = {name = name, observations = encode(text, initial.symbols, initial.missing), path = encode(labels, initial.states)}
    end
end
local function observations(records)
    local result = {}
    for _, record in ipairs(records) do result[#result + 1] = record.observations end
    return result
end
local function position_count(records)
    local total = 0
    for _, record in ipairs(records) do total = total + #record.observations end
    return total
end
local all_labeled = {table.unpack(train_records)}
append(all_labeled, test_records)
local unlabeled, heldout = observations(sequences), observations(all_labeled)
local baum = initial
local previous_loglik = training.total_loglik(baum, unlabeled)
local first_loglik = previous_loglik
local best_heldout, best_iteration = training.total_loglik(baum, heldout), 0
local baum_trace = {"iteration,loglik,heldout,change,max_change,status", "0," .. real(first_loglik) .. "," .. real(best_heldout) .. ",,,"}
local violations = 0
for iteration = 1, iterations do
    local updated = training.baum_welch_step(baum, unlabeled, pseudocount)
    local loglik, heldout_loglik = training.total_loglik(updated, unlabeled), training.total_loglik(updated, heldout)
    local max_change = 0.0
    local previous_rows, current_rows = {baum.initial}, {updated.initial}
    append(previous_rows, baum.transition)
    append(previous_rows, baum.emission)
    append(current_rows, updated.transition)
    append(current_rows, updated.emission)
    for i, row in ipairs(previous_rows) do
        for j, value in ipairs(row) do max_change = math.max(max_change, math.abs(current_rows[i][j] - value)) end
    end
    local violation = loglik < previous_loglik - 0.000001 * math.abs(previous_loglik)
    if violation then violations = violations + 1 end
    if heldout_loglik > best_heldout then best_heldout, best_iteration = heldout_loglik, iteration end
    baum_trace[#baum_trace + 1] = iteration .. "," .. real(loglik) .. "," .. real(heldout_loglik) .. ","
        .. real(loglik - previous_loglik) .. "," .. real(max_change, 6) .. "," .. (violation and "violation" or "ok")
    baum, previous_loglik = updated, loglik
end
local function viterbi_paths(model)
    local paths, total = {}, 0.0
    for i, obs in ipairs(unlabeled) do
        local path, logprob = inference.viterbi(model, obs)
        paths[i], total = path, total + logprob
    end
    return paths, total
end
local viterbi_model = initial
local paths, logprob = viterbi_paths(viterbi_model)
local viterbi_trace = {"iteration,logprob,loglik,changed", "0," .. real(logprob) .. "," .. real(first_loglik) .. ","}
local viterbi_iterations, converged = 0, false
for iteration = 1, iterations do
    local records = {}
    for i, obs in ipairs(unlabeled) do records[i] = {observations = obs, path = paths[i]} end
    viterbi_model = training.count(initial, records, pseudocount, "VITERBI_TRAINING")
    local next_paths, total_logprob = viterbi_paths(viterbi_model)
    local changed = 0
    for i, path in ipairs(paths) do changed = changed + #path - evaluation.correct(path, next_paths[i]) end
    viterbi_trace[#viterbi_trace + 1] = iteration .. "," .. real(total_logprob) .. ","
        .. real(training.total_loglik(viterbi_model, unlabeled)) .. "," .. changed
    paths, viterbi_iterations, converged = next_paths, iteration, changed == 0
    if converged then break end
end
local cv_results, selected_candidate = {}, nil
local train_positions, test_positions = position_count(train_records), position_count(test_records)
for _, candidate in ipairs(parameters.smoothing) do
    local matrix = evaluation.matrix(#initial.states)
    local fold_results, total_correct = {}, 0
    for fold = 1, folds do
        local fitting, validating = {}, {}
        for i, record in ipairs(train_records) do
            local target = (i - 1) % folds == fold - 1 and validating or fitting
            target[#target + 1] = record
        end
        local model = training.count(initial, fitting, tonumber(candidate))
        local positions, correct = 0, 0
        for _, record in ipairs(validating) do
            local path = inference.viterbi(model, record.observations)
            positions, correct = positions + #path, correct + evaluation.correct(record.path, path)
            evaluation.accumulate(matrix, record.path, path)
        end
        total_correct = total_correct + correct
        fold_results[fold] = {#validating, positions, correct}
    end
    local result = {candidate = candidate, correct = total_correct, folds = fold_results, matrix = matrix}
    cv_results[#cv_results + 1] = result
    if not selected_candidate or total_correct > selected_candidate.correct then selected_candidate = result end
end
local supervised = training.count(initial, train_records, tonumber(selected_candidate.candidate))
local cv_lines = {"CROSS_VALIDATION folds " .. folds}
for _, result in ipairs(cv_results) do
    cv_lines[#cv_lines + 1] = "SMOOTHING " .. result.candidate .. " positions " .. train_positions .. " correct "
        .. result.correct .. " accuracy " .. fraction(result.correct, train_positions)
end
cv_lines[#cv_lines + 1] = "SELECTED " .. selected_candidate.candidate
for fold, row in ipairs(selected_candidate.folds) do
    cv_lines[#cv_lines + 1] = "FOLD " .. fold .. " records " .. row[1] .. " positions " .. row[2]
        .. " correct " .. row[3] .. " accuracy " .. fraction(row[3], row[2])
end
append(cv_lines, evaluation.matrix_lines(initial.states, selected_candidate.matrix))
append(cv_lines, evaluation.metrics(initial.states, selected_candidate.matrix))
local learning_lines = {"LEARNING_CURVE"}
for count = 1, #train_records do
    local fitting = {}
    for i = 1, count do fitting[i] = train_records[i] end
    local model = training.count(initial, fitting, tonumber(selected_candidate.candidate))
    local correct = 0
    for _, record in ipairs(test_records) do
        local path = inference.viterbi(model, record.observations)
        correct = correct + evaluation.correct(record.path, path)
    end
    learning_lines[#learning_lines + 1] = "RECORDS " .. count .. " correct " .. correct .. " accuracy " .. fraction(correct, test_positions)
end
local function segments(path)
    local merged, result = {}, {}
    for _, run in ipairs(evaluation.runs(path)) do
        if run[1] == segment_state then
            if #merged > 0 and run[2] - merged[#merged][2] - 1 <= integer("merge_gap") then merged[#merged][2] = run[3]
            else merged[#merged + 1] = {run[2], run[3]} end
        end
    end
    for _, segment in ipairs(merged) do
        if segment[2] - segment[1] + 1 >= integer("min_segment_length") then result[#result + 1] = segment end
    end
    return result
end
local function composition(obs, segment)
    local observed, rich, first, second, pairs = 0, 0, 0, 0, 0
    for t = segment[1], segment[2] do
        local symbol = obs[t]
        if symbol ~= -1 then
            observed = observed + 1
            if rich_symbols[symbol] then rich = rich + 1 end
            if symbol == motif[1] then first = first + 1 end
            if symbol == motif[2] then second = second + 1 end
        end
        if t < segment[2] and symbol == motif[1] and obs[t + 1] == motif[2] then pairs = pairs + 1 end
    end
    local rich_fraction, pair_ratio
    if observed > 0 then rich_fraction = rich / observed end
    if first * second > 0 then pair_ratio = (pairs * observed) / (first * second) end
    local island = first * second > 0 and 100 * rich >= integer("min_rich_percent") * observed
        and 100 * pairs * observed >= integer("min_motif_percent") * first * second
    return rich_fraction, pair_ratio, island
end
local models = {initial, baum, viterbi_model, supervised}
local evaluation_blocks, scores, decoded = {}, {}, {}
for model_index, model in ipairs(models) do
    local results = {}
    for i, record in ipairs(test_records) do results[i] = inference.decode(model, record.observations) end
    scores[model_index] = {}
    for decoder = 1, 2 do
        local name = decoder == 1 and "VITERBI" or "POSTERIOR"
        local matrix, regions, boundaries, calibration, record_lines = evaluation.matrix(#model.states), {0, 0, 0, 0}, {0, 0, 0, 0}, {}, {}
        for bucket = 1, 10 do calibration[bucket] = {0, 0} end
        local total_correct = 0
        for i, record in ipairs(test_records) do
            local result = results[i]
            local path = decoder == 1 and result.viterbi or result.posterior
            local correct = evaluation.correct(record.path, path)
            total_correct = total_correct + correct
            evaluation.accumulate(matrix, record.path, path)
            local true_regions = {}
            for _, run in ipairs(evaluation.runs(record.path)) do if run[1] == segment_state then true_regions[#true_regions + 1] = {run[2], run[3]} end end
            local rc = evaluation.region_counts(segments(path), true_regions)
            local bc = evaluation.boundary_counts(path, record.path, integer("boundary_tolerance"))
            for j = 1, 4 do regions[j], boundaries[j] = regions[j] + rc[j], boundaries[j] + bc[j] end
            if decoder == 2 then
                for t, confidence in ipairs(result.confidence) do
                    local bucket = math.min(9, math.floor(10 * confidence)) + 1
                    calibration[bucket][1] = calibration[bucket][1] + 1
                    if path[t] == record.path[t] then calibration[bucket][2] = calibration[bucket][2] + 1 end
                end
            end
            record_lines[#record_lines + 1] = "RECORD " .. record.name .. " length " .. #path .. " correct " .. correct
        end
        local block = {"EVALUATION " .. model.name .. " " .. name}
        append(block, evaluation.matrix_lines(model.states, matrix))
        append(block, evaluation.metrics(model.states, matrix))
        block[#block + 1] = "REGIONS " .. model.states[segment_state] .. " predicted " .. regions[1] .. " true " .. regions[2]
            .. " precision " .. fraction(regions[3], regions[1]) .. " recall " .. fraction(regions[4], regions[2])
        block[#block + 1] = "BOUNDARIES predicted " .. boundaries[1] .. " true " .. boundaries[2] .. " precision "
            .. fraction(boundaries[3], boundaries[1]) .. " recall " .. fraction(boundaries[4], boundaries[2])
        if decoder == 2 then
            for bucket = 0, 9 do
                local row = calibration[bucket + 1]
                if row[1] > 0 then
                    local range = bucket == 9 and "0.9-1.0" or "0." .. bucket .. "-0." .. (bucket + 1)
                    block[#block + 1] = "CALIBRATION " .. range .. " positions " .. row[1] .. " correct " .. row[2] .. " accuracy " .. fraction(row[2], row[1])
                end
            end
        end
        append(block, record_lines)
        evaluation_blocks[#evaluation_blocks + 1], scores[model_index][decoder] = block, total_correct
    end
    decoded[model_index] = {}
    for i, record in ipairs(sequences) do decoded[model_index][i] = inference.decode(model, record.observations) end
end
append(evaluation_blocks, {cv_lines, learning_lines})
local function text(path, alphabet)
    local result = {}
    for i, index in ipairs(path) do result[i] = alphabet[index] end
    return table.concat(result)
end
local posterior_generator = sampler.generator(integer("posterior_seed"))
local decoding_lines, segment_lines = {}, {"sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"}
for i, record in ipairs(sequences) do
    local result = decoded[2][i]
    local samples, segment_count = {}, 0
    for _ = 1, integer("posterior_samples") do
        local path = sampler.posterior_path(baum, result.fb.forward, posterior_generator)
        samples[#samples + 1], segment_count = path, segment_count + #segments(path)
    end
    local uncertain, confident, imputed = 0, {}, {}
    for t, confidence in ipairs(result.confidence) do
        confident[t] = baum.states[result.posterior[t]]
        if confidence < integer("confidence") then uncertain, confident[t] = uncertain + 1, "." end
        local observation = record.observations[t]
        if observation ~= -1 then imputed[t] = baum.symbols[observation]
        else
            local probabilities = {}
            for c = 1, #baum.symbols do
                local total = 0.0
                for state = 1, #baum.states do total = total + result.fb.posterior[t][state] * baum.emission[state][c] end
                probabilities[c] = total
            end
            imputed[t] = baum.symbols[inference.maximum(probabilities)]:lower()
        end
    end
    append(decoding_lines, {"SEQUENCE " .. record.name .. " length " .. #record.observations .. " loglik " .. real(result.fb.loglik)
        .. " viterbi " .. real(result.logprob) .. " differences " .. (#record.observations - evaluation.correct(result.viterbi, result.posterior))
        .. " uncertain " .. uncertain .. " expected_segments " .. real(segment_count / integer("posterior_samples")),
        "VITERBI " .. text(result.viterbi, baum.states), "POSTERIOR " .. text(result.posterior, baum.states),
        "CONFIDENT " .. table.concat(confident), "IMPUTED " .. table.concat(imputed)})
    for decoder = 1, 2 do
        local path = decoder == 1 and result.viterbi or result.posterior
        for _, segment in ipairs(segments(path)) do
            local length, total, support = segment[2] - segment[1] + 1, 0.0, 0
            for t = segment[1], segment[2] do total = total + result.fb.posterior[t][segment_state] end
            for _, sample in ipairs(samples) do
                local count = 0
                for t = segment[1], segment[2] do if sample[t] == segment_state then count = count + 1 end end
                if 2 * count > length then support = support + 1 end
            end
            local rich, ratio, island = composition(record.observations, segment)
            segment_lines[#segment_lines + 1] = table.concat({record.name, decoder == 1 and "viterbi" or "posterior",
                segment[1], segment[2], length, real(total / length), support, real(rich), real(ratio), island and "yes" or "no"}, ",")
        end
    end
end
local sample_generator = sampler.generator(integer("sample_seed"))
local sample_lines, synthetic_positions, synthetic_viterbi, synthetic_posterior = {}, 0, 0, 0
for number = 1, integer("sample_count") do
    local truth, obs = sampler.synthetic(baum, integer("sample_length"), sample_generator)
    local result = inference.decode(baum, obs)
    local vc, pc = evaluation.correct(truth, result.viterbi), evaluation.correct(truth, result.posterior)
    synthetic_positions, synthetic_viterbi, synthetic_posterior = synthetic_positions + #truth, synthetic_viterbi + vc, synthetic_posterior + pc
    append(sample_lines, {"SAMPLE " .. number .. " loglik " .. real(result.fb.loglik) .. " viterbi " .. real(result.logprob)
        .. " viterbi_correct " .. vc .. " posterior_correct " .. pc, "STATES " .. text(truth, baum.states),
        "SYMBOLS " .. text(obs, baum.symbols), "VITERBI " .. text(result.viterbi, baum.states), "POSTERIOR " .. text(result.posterior, baum.states)})
end
sample_lines[#sample_lines + 1] = "TOTAL positions " .. synthetic_positions .. " viterbi_accuracy " .. fraction(synthetic_viterbi, synthetic_positions)
    .. " posterior_accuracy " .. fraction(synthetic_posterior, synthetic_positions)
local function path_statistics(paths)
    local counts, run_counts, total = {}, {}, 0
    for i = 1, #initial.states do counts[i], run_counts[i] = 0, 0 end
    for _, path in ipairs(paths) do
        total = total + #path
        for _, run in ipairs(evaluation.runs(path)) do
            counts[run[1]], run_counts[run[1]] = counts[run[1]] + run[3] - run[2] + 1, run_counts[run[1]] + 1
        end
    end
    return counts, run_counts, total
end
local function ratio_or_nil(numerator, denominator)
    if denominator > 0 then return numerator / denominator end
end
local function true_paths(records)
    local result = {}
    for i, record in ipairs(records) do result[i] = record.path end
    return result
end
local symbol_counts, unlabeled_missing, labeled_missing = {}, 0, 0
for c = 1, #initial.symbols do symbol_counts[c] = 0 end
for _, record in ipairs(sequences) do
    for _, c in ipairs(record.observations) do
        if c == -1 then unlabeled_missing = unlabeled_missing + 1 else symbol_counts[c] = symbol_counts[c] + 1 end
    end
end
for _, record in ipairs(all_labeled) do
    for _, c in ipairs(record.observations) do if c == -1 then labeled_missing = labeled_missing + 1 end end
end
local unlabeled_positions = position_count(sequences)
local input_block = {"INPUT", "SEQUENCES accepted " .. #sequences .. " rejected " .. (#sequence_rows - #sequences)
    .. " positions " .. unlabeled_positions .. " missing " .. unlabeled_missing,
    "LABELED train " .. #train_records .. " test " .. #test_records .. " rejected " .. (#labeled_rows // 2 - #all_labeled)
    .. " positions " .. (train_positions + test_positions) .. " missing " .. labeled_missing}
append(input_block, rejections)
local composition_fields = {"COMPOSITION"}
for c, symbol in ipairs(initial.symbols) do append(composition_fields, {symbol, real(symbol_counts[c] / (unlabeled_positions - unlabeled_missing))}) end
input_block[#input_block + 1] = table.concat(composition_fields, " ")
for _, item in ipairs({{"TRAIN", train_records}, {"TEST", test_records}}) do
    local counts, runs, total = path_statistics(true_paths(item[2]))
    for state, name in ipairs(initial.states) do
        input_block[#input_block + 1] = "TRUTH " .. item[1] .. " " .. name .. " occupancy " .. real(counts[state] / total)
            .. " mean_run " .. real(ratio_or_nil(counts[state], runs[state]))
    end
end
local training_block = {"TRAINING BAUM_WELCH iterations " .. iterations .. " initial_loglik " .. real(first_loglik)
    .. " final_loglik " .. real(previous_loglik) .. " violations " .. violations .. " best_heldout_iteration " .. best_iteration,
    "TRAINING VITERBI_TRAINING iterations " .. viterbi_iterations .. " converged " .. (converged and "yes" or "no"),
    "TRAINING SUPERVISED smoothing " .. selected_candidate.candidate}
local preferences = {0, 0, 0, 0}
for i = 1, #sequences do
    local likelihoods = {}
    for j = 1, #models do likelihoods[j] = decoded[j][i].fb.loglik end
    local chosen = inference.maximum(likelihoods)
    preferences[chosen] = preferences[chosen] + 1
end
local preference_fields = {"PREFERENCE"}
for i, model in ipairs(models) do append(preference_fields, {model.name, tostring(preferences[i])}) end
training_block[#training_block + 1] = table.concat(preference_fields, " ")
for a = 1, #models - 1 do
    for b = a + 1, #models do
        local correct = 0
        for i = 1, #sequences do correct = correct + evaluation.correct(decoded[a][i].viterbi, decoded[b][i].viterbi) end
        training_block[#training_block + 1] = "AGREEMENT " .. models[a].name .. " " .. models[b].name .. " " .. fraction(correct, unlabeled_positions)
    end
end
for decoder = 1, 2 do
    local totals = {}
    for i = 1, #models do totals[i] = scores[i][decoder] end
    local best = inference.maximum(totals)
    training_block[#training_block + 1] = "BEST " .. (decoder == 1 and "VITERBI" or "POSTERIOR") .. " " .. models[best].name
        .. " accuracy " .. fraction(totals[best], test_positions)
end
local function stationary(model)
    local count, matrix = #model.states, {}
    for equation = 1, count - 1 do
        local row = {}
        for state = 1, count do row[state] = model.transition[state][equation] - (state == equation and 1.0 or 0.0) end
        row[count + 1], matrix[equation] = 0.0, row
    end
    matrix[count] = {}
    for i = 1, count + 1 do matrix[count][i] = 1.0 end
    for column = 1, count do
        local pivot = column
        for row = column + 1, count do if math.abs(matrix[row][column]) > math.abs(matrix[pivot][column]) then pivot = row end end
        matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
        local divisor = matrix[column][column]
        for j = column, count + 1 do matrix[column][j] = matrix[column][j] / divisor end
        for row = 1, count do
            if row ~= column then
                local factor = matrix[row][column]
                for j = column, count + 1 do matrix[row][j] = matrix[row][j] - factor * matrix[column][j] end
            end
        end
    end
    local result = {}
    for i = 1, count do result[i] = matrix[i][count + 1] end
    return result
end
local function alignment(model)
    local matrix, permutation, used, best, best_correct = evaluation.matrix(#model.states), {}, {}, {}, -1
    for _, record in ipairs(train_records) do
        local path = inference.viterbi(model, record.observations)
        evaluation.accumulate(matrix, record.path, path)
    end
    local function visit()
        if #permutation == #model.states then
            local correct = 0
            for j, actual in ipairs(permutation) do correct = correct + matrix[actual][j] end
            if correct > best_correct then best, best_correct = {table.unpack(permutation)}, correct end
            return
        end
        for state = 1, #model.states do
            if not used[state] then
                used[state], permutation[#permutation + 1] = true, state
                visit()
                used[state], permutation[#permutation] = nil, nil
            end
        end
    end
    visit()
    local fields = {"ALIGNMENT"}
    for j, actual in ipairs(best) do fields[#fields + 1] = model.states[j] .. "=" .. model.states[actual] end
    append(fields, {"agreement", fraction(best_correct, train_positions)})
    return table.concat(fields, " ")
end
local report_blocks = {input_block, training_block}
for model_index, model in ipairs(models) do
    local loglik, observed, segment_count, segment_length, islands, model_paths = 0.0, 0, 0, 0, 0, {}
    for i, record in ipairs(sequences) do
        local result = decoded[model_index][i]
        loglik = loglik + result.fb.loglik
        model_paths[i] = result.viterbi
        for _, symbol in ipairs(record.observations) do if symbol ~= -1 then observed = observed + 1 end end
        for _, segment in ipairs(segments(result.viterbi)) do
            segment_count, segment_length = segment_count + 1, segment_length + segment[2] - segment[1] + 1
            local _, _, island = composition(record.observations, segment)
            if island then islands = islands + 1 end
        end
    end
    local counts, run_counts, total = path_statistics(model_paths)
    local phi = stationary(model)
    local block = {"MODEL " .. model.name, "LOGLIK unlabeled " .. real(loglik) .. " per_symbol " .. real(loglik / observed)
        .. " test " .. real(training.total_loglik(model, observations(test_records))),
        "SEGMENTS count " .. segment_count .. " mean_length " .. real(ratio_or_nil(segment_length, segment_count)) .. " islands " .. islands,
        alignment(model)}
    for state, name in ipairs(model.states) do
        block[#block + 1] = "STATE " .. name .. " stationary " .. real(phi[state]) .. " duration " .. real(1 / (1 - model.transition[state][state]))
            .. " occupancy " .. real(counts[state] / total) .. " mean_run " .. real(ratio_or_nil(counts[state], run_counts[state]))
    end
    report_blocks[#report_blocks + 1] = block
end
local trained_blocks = {}
for i = 2, #models do trained_blocks[#trained_blocks + 1] = model_io.model_lines(models[i]) end
model_io.write("trained_model.txt", join_blocks(trained_blocks))
model_io.write("loglik_trace.csv", baum_trace)
model_io.write("viterbi_trace.csv", viterbi_trace)
model_io.write("decodings.txt", decoding_lines)
model_io.write("segments.csv", segment_lines)
model_io.write("samples.txt", sample_lines)
model_io.write("evaluation.txt", join_blocks(evaluation_blocks))
model_io.write("report.txt", join_blocks(report_blocks))
