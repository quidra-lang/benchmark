local vocabulary = require("vocabulary")
local M = {NB_MODELS = {"multinomial", "bernoulli", "complement"}}

function M.smoothed_log(count, total, alpha, outcomes)
    return math.log((100 * count + alpha) / (100 * total + alpha * outcomes))
end

local TrainingCounts = {}
TrainingCounts.__index = TrainingCounts
function TrainingCounts.new(sequences, labels, class_count, size)
    local self = setmetatable({class_count = class_count, vocabulary_size = size, document_total = #sequences,
        documents = {}, occurrences = {}, containing = {}, totals = {}, total = 0, term_totals = {}}, TrainingCounts)
    for label = 1, class_count do
        self.documents[label], self.occurrences[label], self.containing[label] = 0, {}, {}
        for term = 1, size do self.occurrences[label][term], self.containing[label][term] = 0, 0 end
    end
    for index, sequence in ipairs(sequences) do
        local label = labels[index]
        self.documents[label] = self.documents[label] + 1
        for _, term in ipairs(sequence) do self.occurrences[label][term] = self.occurrences[label][term] + 1 end
        for _, term in ipairs(vocabulary.first_occurrences(sequence)) do self.containing[label][term] = self.containing[label][term] + 1 end
    end
    for label, row in ipairs(self.occurrences) do
        local total = 0
        for _, count in ipairs(row) do total = total + count end
        self.totals[label], self.total = total, self.total + total
    end
    for term = 1, size do
        local total = 0
        for label = 1, class_count do total = total + self.occurrences[label][term] end
        self.term_totals[term] = total
    end
    return self
end
function TrainingCounts:log_priors()
    local priors = {}
    for label, count in ipairs(self.documents) do priors[label] = math.log(count / self.document_total) end
    return priors
end

local function posterior(scores)
    local ranking = {}
    for label = 1, #scores do ranking[label] = label end
    table.sort(ranking, function(a, b) return scores[a] > scores[b] or scores[a] == scores[b] and a < b end)
    local best, exponentials, normalizer = scores[ranking[1]], {}, 0.0
    for label, score in ipairs(scores) do exponentials[label] = math.exp(score - best) normalizer = normalizer + exponentials[label] end
    local probabilities = {}
    for label, value in ipairs(exponentials) do probabilities[label] = value / normalizer end
    return {scores = scores, ranking = ranking, label = ranking[1], runner_up = ranking[2], normalizer = normalizer,
        probabilities = probabilities, score = probabilities[ranking[1]], margin = best - scores[ranking[2]]}
end

local NaiveBayes = {}
NaiveBayes.__index = NaiveBayes
function NaiveBayes.new(kind, priors, base, weights)
    return setmetatable({kind = kind, priors = priors, base = base, weights = weights}, NaiveBayes)
end
function NaiveBayes:scores(sequence)
    local terms = self.kind == "bernoulli" and vocabulary.first_occurrences(sequence) or sequence
    local scores = {}
    for label, row in ipairs(self.weights) do
        local score = self.base[label]
        for _, term in ipairs(terms) do score = score + row[term] end
        scores[label] = score + self.priors[label]
    end
    return scores
end
function NaiveBayes:predict(sequence) return posterior(self:scores(sequence)) end

function M.train_model(kind, counts, alpha)
    local base, weights = {}, {}
    for label = 1, counts.class_count do
        local row, absent_sum = {}, 0.0
        for term = 1, counts.vocabulary_size do
            if kind == "multinomial" then
                row[term] = M.smoothed_log(counts.occurrences[label][term], counts.totals[label], alpha, counts.vocabulary_size)
            elseif kind == "bernoulli" then
                local present = M.smoothed_log(counts.containing[label][term], counts.documents[label], alpha, 2)
                local absent = M.smoothed_log(counts.documents[label] - counts.containing[label][term], counts.documents[label], alpha, 2)
                absent_sum, row[term] = absent_sum + absent, present - absent
            else
                row[term] = -M.smoothed_log(counts.term_totals[term] - counts.occurrences[label][term], counts.total - counts.totals[label], alpha, counts.vocabulary_size)
            end
        end
        weights[label], base[label] = row, absent_sum
    end
    return NaiveBayes.new(kind, counts:log_priors(), base, weights)
end
M.TrainingCounts, M.NaiveBayes = TrainingCounts, NaiveBayes
return M
