local M = {}
local function vector_length(vector)
    local total = 0.0
    for _, value in ipairs(vector) do total = total + value * value end
    return math.sqrt(total)
end

local Rocchio = {}
Rocchio.__index = Rocchio
function Rocchio.new(sequences, labels, class_count, frequencies)
    local self = setmetatable({idf = {}, centroids = {}, lengths = {}}, Rocchio)
    for term, frequency in ipairs(frequencies) do self.idf[term] = math.log(#sequences / frequency) end
    local documents = {}
    for label = 1, class_count do
        documents[label], self.centroids[label] = 0, {}
        for term = 1, #frequencies do self.centroids[label][term] = 0.0 end
    end
    for index, sequence in ipairs(sequences) do
        local label = labels[index]
        documents[label] = documents[label] + 1
        local vector = self:vector(sequence)
        local length = vector_length(vector)
        if length > 0 then for term, value in ipairs(vector) do self.centroids[label][term] = self.centroids[label][term] + value / length end end
    end
    for label, row in ipairs(self.centroids) do
        for term, value in ipairs(row) do row[term] = value / documents[label] end
        self.lengths[label] = vector_length(row)
    end
    return self
end
function Rocchio:vector(sequence)
    local frequencies, vector = {}, {}
    for _, term in ipairs(sequence) do frequencies[term] = (frequencies[term] or 0) + 1 end
    for term, idf in ipairs(self.idf) do vector[term] = (frequencies[term] or 0) * idf end
    return vector
end
function Rocchio:predict(sequence)
    local vector, similarities, ranking = self:vector(sequence), {}, {}
    local length = vector_length(vector)
    for label, centroid in ipairs(self.centroids) do
        local similarity = 0.0
        if length > 0 and self.lengths[label] > 0 then
            local product = 0.0
            for term, value in ipairs(vector) do product = product + value * centroid[term] end
            similarity = product / (length * self.lengths[label])
        end
        similarities[label], ranking[label] = similarity, label
    end
    table.sort(ranking, function(a, b) return similarities[a] > similarities[b] or similarities[a] == similarities[b] and a < b end)
    return {ranking = ranking, label = ranking[1], score = similarities[ranking[1]]}
end
M.Rocchio = Rocchio
return M
