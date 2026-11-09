local M = {}
local Tokens = {}
Tokens.__index = Tokens

function Tokens.new(text, stopwords)
    local self = setmetatable({raw_count = 0, stopword_count = 0, short_count = 0, words = {}, bigrams = {}, bigram_terms = {}}, Tokens)
    for word in text:lower():gmatch("[a-z0-9]+") do
        self.raw_count = self.raw_count + 1
        if stopwords[word] then
            self.stopword_count = self.stopword_count + 1
        elseif #word == 1 then
            self.short_count = self.short_count + 1
        else
            self.words[#self.words + 1] = word
        end
    end
    for _, word in ipairs(self.words) do self.bigram_terms[#self.bigram_terms + 1] = word end
    for index = 1, #self.words - 1 do
        local term = self.words[index] .. "_" .. self.words[index + 1]
        self.bigrams[#self.bigrams + 1] = term
        self.bigram_terms[#self.bigram_terms + 1] = term
    end
    return self
end

function Tokens:terms(use_bigrams) return use_bigrams and self.bigram_terms or self.words end
function M.is_bigram(term) return term:find("_", 1, true) ~= nil end
M.Tokens = Tokens
return M
