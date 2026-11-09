local M = {}

function M.first_occurrences(sequence)
    local seen, result = {}, {}
    for _, term in ipairs(sequence) do
        if not seen[term] then seen[term] = true result[#result + 1] = term end
    end
    return result
end

function M.chi_square(with_term, frequency, class_size, total)
    local b, c = frequency - with_term, class_size - with_term
    local e = total - class_size - b
    local difference = with_term * e - b * c
    local numerator = total * difference * difference
    local denominator = frequency * (total - frequency) * class_size * (total - class_size)
    return denominator == 0 and 0.0 or numerator / denominator
end

local Vocabulary = {}
Vocabulary.__index = Vocabulary
function Vocabulary.new(sequences, labels, class_count, min_frequency, size)
    local counts, class_sizes, terms = {}, {}, {}
    for label = 1, class_count do class_sizes[label] = 0 end
    for index, sequence in ipairs(sequences) do
        local label = labels[index]
        class_sizes[label] = class_sizes[label] + 1
        for _, term in ipairs(M.first_occurrences(sequence)) do
            if not counts[term] then
                counts[term] = {}
                for class = 1, class_count do counts[term][class] = 0 end
                terms[#terms + 1] = term
            end
            counts[term][label] = counts[term][label] + 1
        end
    end
    table.sort(terms)
    local self = setmetatable({term_count = #terms, ranking = {}, terms = {}, index = {}, frequencies = {}}, Vocabulary)
    for _, term in ipairs(terms) do
        local frequency = 0
        for _, count in ipairs(counts[term]) do frequency = frequency + count end
        if frequency >= min_frequency then
            local best_class, best_score = 1, M.chi_square(counts[term][1], frequency, class_sizes[1], #sequences)
            for label = 2, class_count do
                local score = M.chi_square(counts[term][label], frequency, class_sizes[label], #sequences)
                if score > best_score then best_class, best_score = label, score end
            end
            self.ranking[#self.ranking + 1] = {term = term, frequency = frequency, score = best_score, best_class = best_class}
        end
    end
    self.candidate_count = #self.ranking
    table.sort(self.ranking, function(a, b) return a.score > b.score or a.score == b.score and a.term < b.term end)
    if size > 0 then while #self.ranking > size do table.remove(self.ranking) end end
    local frequencies = {}
    for _, entry in ipairs(self.ranking) do self.terms[#self.terms + 1] = entry.term frequencies[entry.term] = entry.frequency end
    table.sort(self.terms)
    for position, term in ipairs(self.terms) do self.index[term], self.frequencies[position] = position, frequencies[term] end
    return self
end
function Vocabulary:size() return #self.terms end
function Vocabulary:encode(sequence)
    local result = {}
    for _, term in ipairs(sequence) do if self.index[term] then result[#result + 1] = self.index[term] end end
    return result
end
M.Vocabulary = Vocabulary
return M
