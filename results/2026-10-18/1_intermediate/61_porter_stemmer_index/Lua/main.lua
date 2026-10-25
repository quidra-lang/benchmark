local OPERATORS = { AND = true, OR = true, NOT = true }
local PARENTHESES = { ["("] = true, [")"] = true }
local CONJUNCTION_CONTINUATIONS = {
  AND = true, NOT = true, ["("] = true, term = true, prefix = true,
}
local VOWELS = "aeiou"
local STEP_NAMES = { "1a", "1b", "1c", "2", "3", "4", "5a", "5b" }
local STEP_4_SUFFIXES = {
  "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
  "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
}
local KWIC_WIDTH = 30
local MAX_COUNT = 100
local MAX_DOCUMENT_NUMBER = 999
local MAX_LINE_NUMBER = 999

local function fail(message)
  error({ message = message }, 0)
end

local function starts_with(word, prefix)
  return word:sub(1, #prefix) == prefix
end

local function ends_with(word, suffix)
  return word:sub(-#suffix) == suffix
end

local function count_keys(set)
  local count = 0
  for _ in pairs(set) do
    count = count + 1
  end
  return count
end

local function sorted_keys(set)
  local keys = {}
  for key in pairs(set) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function union(first, second)
  local result = {}
  for key in pairs(first) do
    result[key] = true
  end
  for key in pairs(second) do
    result[key] = true
  end
  return result
end

local function intersection(first, second)
  local result = {}
  for key in pairs(first) do
    if second[key] then
      result[key] = true
    end
  end
  return result
end

local function difference(first, second)
  local result = {}
  for key in pairs(first) do
    if not second[key] then
      result[key] = true
    end
  end
  return result
end

local function split_words(text)
  local parts = {}
  for part in (text .. " "):gmatch("(.-) ") do
    parts[#parts + 1] = part
  end
  return parts
end

local function letter_pattern(word)
  local kinds = {}
  for index = 1, #word do
    local letter = word:sub(index, index)
    local consonant_before = index > 1 and kinds[index - 1] == "C"
    if VOWELS:find(letter, 1, true) or (letter == "y" and consonant_before) then
      kinds[index] = "V"
    else
      kinds[index] = "C"
    end
  end
  return table.concat(kinds)
end

local function measure(word)
  local _, count = letter_pattern(word):gsub("VC", "")
  return count
end

local function has_vowel(word)
  return letter_pattern(word):find("V", 1, true) ~= nil
end

local function ends_double(word)
  return ends_with(letter_pattern(word), "CC") and word:sub(-1) == word:sub(-2, -2)
end

local function ends_cvc(word)
  return ends_with(letter_pattern(word), "CVC") and not ("wxy"):find(word:sub(-1), 1, true)
end

local function always()
  return true
end

local function measure_above_zero(remainder)
  return measure(remainder) > 0
end

local function measure_above_one(remainder)
  return measure(remainder) > 1
end

local function ion_condition(remainder)
  return measure(remainder) > 1 and (ends_with(remainder, "s") or ends_with(remainder, "t"))
end

local function final_e_condition(remainder)
  local value = measure(remainder)
  return value > 1 or (value == 1 and not ends_cvc(remainder))
end

local function rule(suffix, replacement, condition)
  return { suffix = suffix, replacement = replacement, condition = condition }
end

local function rules_with(condition, replacements)
  local rules = {}
  for suffix, replacement in pairs(replacements) do
    rules[#rules + 1] = rule(suffix, replacement, condition)
  end
  return rules
end

local step_4_rules = {}
for _, suffix in ipairs(STEP_4_SUFFIXES) do
  local condition = suffix == "ion" and ion_condition or measure_above_one
  step_4_rules[#step_4_rules + 1] = rule(suffix, "", condition)
end

local RULE_TABLES = {
  ["1a"] = rules_with(always, { sses = "ss", ies = "i", ss = "ss", s = "" }),
  ["1b"] = {
    rule("eed", "ee", measure_above_zero), rule("ed", "", has_vowel), rule("ing", "", has_vowel),
  },
  ["1c"] = { rule("y", "i", has_vowel) },
  ["2"] = rules_with(measure_above_zero, {
    ational = "ate", tional = "tion", enci = "ence", anci = "ance",
    izer = "ize", abli = "able", alli = "al", entli = "ent", eli = "e",
    ousli = "ous", ization = "ize", ation = "ate", ator = "ate",
    alism = "al", iveness = "ive", fulness = "ful", ousness = "ous",
    aliti = "al", iviti = "ive", biliti = "ble",
  }),
  ["3"] = rules_with(measure_above_zero, {
    icate = "ic", ative = "", alize = "al", iciti = "ic",
    ical = "ic", ful = "", ness = "",
  }),
  ["4"] = step_4_rules,
  ["5a"] = { rule("e", "", final_e_condition) },
}

local function apply_rules(word, rules)
  local selected
  for _, candidate in ipairs(rules) do
    local longer = selected == nil or #candidate.suffix > #selected.suffix
    if longer and ends_with(word, candidate.suffix) then
      selected = candidate
    end
  end
  if selected == nil then
    return word, nil
  end
  local remainder = word:sub(1, #word - #selected.suffix)
  if not selected.condition(remainder) then
    return word, nil
  end
  return remainder .. selected.replacement, selected.suffix
end

local function tidy_step_1b(word)
  if ends_with(word, "at") or ends_with(word, "bl") or ends_with(word, "iz") then
    return word .. "e"
  end
  if ends_double(word) and not ("lsz"):find(word:sub(-1), 1, true) then
    return word:sub(1, -2)
  end
  if measure(word) == 1 and ends_cvc(word) then
    return word .. "e"
  end
  return word
end

local function apply_step(name, word)
  if name == "5b" then
    if measure(word) > 1 and ends_double(word) and ends_with(word, "l") then
      return word:sub(1, -2)
    end
    return word
  end
  local result, suffix = apply_rules(word, RULE_TABLES[name])
  if name == "1b" and (suffix == "ed" or suffix == "ing") then
    return tidy_step_1b(result)
  end
  return result
end

local function stemming_steps(word)
  local changes = {}
  if #word > 2 then
    for _, name in ipairs(STEP_NAMES) do
      local result = apply_step(name, word)
      if result ~= word then
        changes[#changes + 1] = name .. ":" .. result
      end
      word = result
    end
  end
  return word, changes
end

local stem_cache = {}

local function porter_stem(word)
  local stem = stem_cache[word]
  if stem == nil then
    stem = stemming_steps(word)
    stem_cache[word] = stem
  end
  return stem
end

local function yes_no(flag)
  return flag and "YES" or "NO"
end

local function is_word(text)
  return #text >= 1 and #text <= 30 and not text:find("[^A-Za-z]")
end

local function word_argument(text)
  if not is_word(text) then
    fail("BAD WORD " .. text)
  end
  return text:lower()
end

local function number_argument(text, minimum, maximum)
  if #text < 1 or #text > 7 or text:find("[^0-9]") then
    fail("BAD NUMBER " .. text)
  end
  local value = tonumber(text)
  if value < minimum or value > maximum then
    fail("BAD NUMBER " .. text)
  end
  return value
end

local function split_arguments(name, rest)
  if name == "SEARCH" then
    return { rest }
  end
  if name == "APPEND" then
    local first, second = rest:match("^(.-) (.*)$")
    if first == nil then
      return { rest }
    end
    return { first, second }
  end
  return split_words(rest)
end

local function sorted_by_count(counts)
  local entries = {}
  for stem, count in pairs(counts) do
    entries[#entries + 1] = { stem = stem, count = count }
  end
  table.sort(entries, function(first, second)
    if first.count ~= second.count then
      return first.count > second.count
    end
    return first.stem < second.stem
  end)
  return entries
end

local function document_count(occurrences)
  local numbers = {}
  for _, occurrence in ipairs(occurrences) do
    numbers[occurrence.document.number] = true
  end
  return count_keys(numbers)
end

local function closest_distance(positions, others, same_stem)
  local closest
  local function consider(gap)
    if closest == nil or gap < closest then
      closest = gap
    end
  end
  if same_stem then
    for index = 2, #positions do
      consider(positions[index] - positions[index - 1])
    end
  else
    local merged = {}
    for _, position in ipairs(positions) do
      merged[#merged + 1] = { position = position, side = 0 }
    end
    for _, other in ipairs(others) do
      merged[#merged + 1] = { position = other, side = 1 }
    end
    table.sort(merged, function(first, second)
      return first.position < second.position
    end)
    for index = 2, #merged do
      if merged[index].side ~= merged[index - 1].side then
        consider(merged[index].position - merged[index - 1].position)
      end
    end
  end
  return closest
end

local function reduced_fraction(numerator, denominator)
  local a, b = numerator, denominator
  while b ~= 0 do
    a, b = b, a % b
  end
  return numerator // a, denominator // a
end

local function classify(lexeme)
  if OPERATORS[lexeme] or PARENTHESES[lexeme] then
    return { kind = lexeme, spelling = lexeme }
  end
  if is_word(lexeme) then
    return { kind = "term", spelling = lexeme:lower() }
  end
  local letters = lexeme:sub(1, -2)
  if ends_with(lexeme, "*") and is_word(letters) then
    return { kind = "prefix", spelling = letters:lower() }
  end
  fail("BAD TERM " .. lexeme)
end

local Document = {}
Document.__index = Document

function Document.new(number)
  return setmetatable({ number = number, lines = {}, tokens = {} }, Document)
end

function Document:add_line(text)
  self.lines[#self.lines + 1] = text
  local added = {}
  for start, word in text:gmatch("()([A-Za-z]+)") do
    local token = {
      text = word,
      form = word:lower(),
      line = #self.lines,
      position = #self.tokens + 1,
      start = start,
    }
    self.tokens[#self.tokens + 1] = token
    added[#added + 1] = token
  end
  return added
end

function Document:line_tokens(line_number)
  local tokens = {}
  for _, token in ipairs(self.tokens) do
    if token.line == line_number then
      tokens[#tokens + 1] = token
    end
  end
  return tokens
end

function Document:reference(token)
  return self.number .. ":" .. token.line .. ":" .. token.position
end

local QueryParser = {}
QueryParser.__index = QueryParser

function QueryParser.new(items, stem_sets)
  return setmetatable({ items = items, position = 1, stem_sets = stem_sets }, QueryParser)
end

function QueryParser:peek()
  local item = self.items[self.position]
  return item and item.kind
end

function QueryParser:take()
  local item = self.items[self.position]
  if item == nil then
    fail("SYNTAX")
  end
  self.position = self.position + 1
  return item
end

function QueryParser:parse()
  local canonical, documents = self:expression()
  if self.position <= #self.items then
    fail("SYNTAX")
  end
  return canonical, documents
end

function QueryParser:expression()
  local canonical, documents = self:conjunction()
  while self:peek() == "OR" do
    self.position = self.position + 1
    local right, right_documents = self:conjunction()
    canonical = "(" .. canonical .. " OR " .. right .. ")"
    documents = union(documents, right_documents)
  end
  return canonical, documents
end

function QueryParser:conjunction()
  local canonical, documents = self:negation()
  while CONJUNCTION_CONTINUATIONS[self:peek()] do
    if self:peek() == "AND" then
      self.position = self.position + 1
    end
    local right, right_documents = self:negation()
    canonical = "(" .. canonical .. " AND " .. right .. ")"
    documents = intersection(documents, right_documents)
  end
  return canonical, documents
end

function QueryParser:negation()
  if self:peek() == "NOT" then
    self.position = self.position + 1
    local canonical, documents = self:negation()
    return "(NOT " .. canonical .. ")", difference(self.stem_sets, documents)
  end
  return self:element()
end

function QueryParser:matching(predicate)
  local documents = {}
  for number, stems in pairs(self.stem_sets) do
    if predicate(stems) then
      documents[number] = true
    end
  end
  return documents
end

function QueryParser:element()
  local item = self:take()
  if item.kind == "(" then
    local canonical, documents = self:expression()
    if self:take().kind ~= ")" then
      fail("SYNTAX")
    end
    return canonical, documents
  end
  if item.kind == "term" then
    local stem = porter_stem(item.spelling)
    return stem, self:matching(function(stems)
      return stems[stem]
    end)
  end
  if item.kind == "prefix" then
    return item.spelling .. "*", self:matching(function(stems)
      for stem in pairs(stems) do
        if starts_with(stem, item.spelling) then
          return true
        end
      end
      return false
    end)
  end
  fail("SYNTAX")
end

local SearchEngine = {}
SearchEngine.__index = SearchEngine

function SearchEngine.new(stopwords)
  return setmetatable({ stopwords = stopwords, documents = {}, output = {} }, SearchEngine)
end

function SearchEngine:emit(...)
  self.output[#self.output + 1] = table.concat({ ... }, " ")
end

function SearchEngine:add_document(number)
  local document = Document.new(number)
  self.documents[number] = document
  return document
end

function SearchEngine:ordered_documents()
  local documents = {}
  for index, number in ipairs(sorted_keys(self.documents)) do
    documents[index] = self.documents[number]
  end
  return documents
end

function SearchEngine:is_indexed(token)
  return not self.stopwords[token.form]
end

function SearchEngine:indexed_tokens(document)
  local tokens = {}
  for _, token in ipairs(document.tokens) do
    if self:is_indexed(token) then
      tokens[#tokens + 1] = token
    end
  end
  return tokens
end

function SearchEngine:term_frequencies(document)
  local counts = {}
  for _, token in ipairs(self:indexed_tokens(document)) do
    local stem = porter_stem(token.form)
    counts[stem] = (counts[stem] or 0) + 1
  end
  return counts
end

function SearchEngine:stem_set(document)
  local stems = {}
  for stem in pairs(self:term_frequencies(document)) do
    stems[stem] = true
  end
  return stems
end

function SearchEngine:total_frequencies()
  local totals = {}
  for _, document in pairs(self.documents) do
    for stem, count in pairs(self:term_frequencies(document)) do
      totals[stem] = (totals[stem] or 0) + count
    end
  end
  return totals
end

function SearchEngine:occurrence_map()
  local occurrences = {}
  for _, document in ipairs(self:ordered_documents()) do
    for _, token in ipairs(self:indexed_tokens(document)) do
      local stem = porter_stem(token.form)
      occurrences[stem] = occurrences[stem] or {}
      table.insert(occurrences[stem], { document = document, token = token })
    end
  end
  return occurrences
end

function SearchEngine:stem_positions(document, stem)
  local positions = {}
  for _, token in ipairs(self:indexed_tokens(document)) do
    if porter_stem(token.form) == stem then
      positions[#positions + 1] = token.position
    end
  end
  return positions
end

function SearchEngine:form_count(form)
  local count = 0
  for _, document in pairs(self.documents) do
    for _, token in ipairs(document.tokens) do
      if token.form == form then
        count = count + 1
      end
    end
  end
  return count
end

function SearchEngine:token_matches(token, target)
  return target == "?" or (self:is_indexed(token) and porter_stem(token.form) == target)
end

function SearchEngine:describe_token(token)
  if self:is_indexed(token) then
    return token.form .. "/" .. porter_stem(token.form)
  end
  return token.form .. "/-"
end

function SearchEngine:term_argument(text)
  local word = word_argument(text)
  if self.stopwords[word] then
    fail("STOPWORD " .. word)
  end
  return porter_stem(word)
end

function SearchEngine:document_argument(text)
  local number = number_argument(text, 1, MAX_DOCUMENT_NUMBER)
  local document = self.documents[number]
  if document == nil then
    fail("NO DOC " .. number)
  end
  return document
end

function SearchEngine:stem_words(arguments)
  local words = {}
  for index, argument in ipairs(arguments) do
    words[index] = word_argument(argument)
  end
  local items = {}
  for index, word in ipairs(words) do
    items[index] = word .. ":" .. porter_stem(word)
  end
  self:emit("STEM", table.unpack(items))
end

function SearchEngine:show_steps(arguments)
  local word = word_argument(arguments[1])
  local _, changes = stemming_steps(word)
  if #changes == 0 then
    self:emit("STEPS", word, "NONE")
  else
    self:emit("STEPS", word, table.unpack(changes))
  end
end

function SearchEngine:show_measure(arguments)
  local word = word_argument(arguments[1])
  self:emit(
    "MEASURE", word, letter_pattern(word), "m=" .. measure(word),
    "vowel=" .. yes_no(has_vowel(word)), "double=" .. yes_no(ends_double(word)),
    "cvc=" .. yes_no(ends_cvc(word))
  )
end

function SearchEngine:show_index(arguments)
  local prefix = #arguments > 0 and word_argument(arguments[1]) or ""
  local occurrences = self:occurrence_map()
  local stems = {}
  for stem in pairs(occurrences) do
    if starts_with(stem, prefix) then
      stems[#stems + 1] = stem
    end
  end
  table.sort(stems)
  self:emit("INDEX", "stems=" .. #stems)
  for _, stem in ipairs(stems) do
    local found = occurrences[stem]
    local references = {}
    for index, occurrence in ipairs(found) do
      references[index] = occurrence.document:reference(occurrence.token)
    end
    self:emit(stem, "df=" .. document_count(found), table.unpack(references))
  end
end

function SearchEngine:search(arguments)
  local items = {}
  for lexeme in arguments[1]:gsub("[()]", " %0 "):gmatch("[^ ]+") do
    items[#items + 1] = classify(lexeme)
  end
  local stem_sets = {}
  for number, document in pairs(self.documents) do
    stem_sets[number] = self:stem_set(document)
  end
  local canonical, matches = QueryParser.new(items, stem_sets):parse()
  for _, item in ipairs(items) do
    if item.kind == "term" and self.stopwords[item.spelling] then
      fail("STOPWORD " .. item.spelling)
    end
  end
  local numbers = sorted_keys(matches)
  self:emit("SEARCH", canonical, "count=" .. #numbers, table.unpack(numbers))
end

function SearchEngine:phrase(arguments)
  local words = {}
  for index, argument in ipairs(arguments) do
    words[index] = word_argument(argument)
  end
  local targets = {}
  local only_stopwords = true
  for index, word in ipairs(words) do
    if self.stopwords[word] then
      targets[index] = "?"
    else
      targets[index] = porter_stem(word)
      only_stopwords = false
    end
  end
  if only_stopwords then
    fail("STOPWORDS ONLY")
  end
  local matches = {}
  for _, document in ipairs(self:ordered_documents()) do
    local tokens = document.tokens
    for start = 1, #tokens - #targets + 1 do
      local matched = true
      for offset, target in ipairs(targets) do
        if not self:token_matches(tokens[start + offset - 1], target) then
          matched = false
          break
        end
      end
      if matched then
        matches[#matches + 1] = document:reference(tokens[start])
      end
    end
  end
  local phrase_text = table.concat(targets, " ")
  self:emit('PHRASE "' .. phrase_text .. '"', "matches=" .. #matches, table.unpack(matches))
end

function SearchEngine:near(arguments)
  local first = self:term_argument(arguments[1])
  local second = self:term_argument(arguments[2])
  local limit = number_argument(arguments[3], 1, MAX_COUNT)
  local found = {}
  for _, document in ipairs(self:ordered_documents()) do
    local distance = closest_distance(
      self:stem_positions(document, first),
      self:stem_positions(document, second),
      first == second
    )
    if distance ~= nil and distance <= limit then
      found[#found + 1] = document.number .. ":" .. distance
    end
  end
  self:emit("NEAR", first, second, limit, "count=" .. #found, table.unpack(found))
end

function SearchEngine:top(arguments)
  local limit = number_argument(arguments[1], 1, MAX_COUNT)
  local counts, header
  if #arguments == 2 then
    local document = self:document_argument(arguments[2])
    counts = self:term_frequencies(document)
    header = "TOP " .. limit .. " doc=" .. document.number
  else
    counts = self:total_frequencies()
    header = "TOP " .. limit
  end
  local ranked = sorted_by_count(counts)
  local items = {}
  for index = 1, math.min(limit, #ranked) do
    items[index] = ranked[index].stem .. ":" .. ranked[index].count
  end
  self:emit(header, table.unpack(items))
end

function SearchEngine:kwic(arguments)
  local stem = self:term_argument(arguments[1])
  local found = self:occurrence_map()[stem] or {}
  self:emit("KWIC", stem, "count=" .. #found)
  for _, occurrence in ipairs(found) do
    local document, token = occurrence.document, occurrence.token
    local text = document.lines[token.line]
    local finish = token.start + #token.text
    local before = text:sub(math.max(1, token.start - KWIC_WIDTH), token.start - 1)
    local after = text:sub(finish, finish + KWIC_WIDTH - 1)
    before = string.rep(" ", KWIC_WIDTH - #before) .. before
    after = after .. string.rep(" ", KWIC_WIDTH - #after)
    self:emit("|" .. before .. "[" .. token.text .. "]" .. after .. "|", document:reference(token))
  end
end

function SearchEngine:term_frequency(arguments)
  local document = self:document_argument(arguments[1])
  local stem = self:term_argument(arguments[2])
  self:emit("TF", document.number, stem, self:term_frequencies(document)[stem] or 0)
end

function SearchEngine:document_frequency(arguments)
  local stem = self:term_argument(arguments[1])
  local found = self:occurrence_map()[stem] or {}
  self:emit("DF", stem, document_count(found))
end

function SearchEngine:variants(arguments)
  local stem = self:term_argument(arguments[1])
  local found = self:occurrence_map()[stem] or {}
  local forms = {}
  for _, occurrence in ipairs(found) do
    local form = occurrence.token.form
    forms[form] = (forms[form] or 0) + 1
  end
  local items = {}
  for index, form in ipairs(sorted_keys(forms)) do
    items[index] = form .. ":" .. forms[form]
  end
  self:emit("VARIANTS", stem, "count=" .. #items, table.unpack(items))
end

function SearchEngine:similar(arguments)
  local document = self:document_argument(arguments[1])
  local limit = number_argument(arguments[2], 1, MAX_COUNT)
  local stems = self:stem_set(document)
  local scores = {}
  for _, other in pairs(self.documents) do
    if other ~= document then
      local other_stems = self:stem_set(other)
      local union_size = count_keys(union(stems, other_stems))
      local numerator, denominator = 0, 1
      if union_size > 0 then
        numerator, denominator = reduced_fraction(
          count_keys(intersection(stems, other_stems)), union_size
        )
      end
      scores[#scores + 1] = {
        numerator = numerator, denominator = denominator, number = other.number,
      }
    end
  end
  table.sort(scores, function(first, second)
    local left = first.numerator * second.denominator
    local right = second.numerator * first.denominator
    if left ~= right then
      return left > right
    end
    return first.number < second.number
  end)
  local items = {}
  for index = 1, math.min(limit, #scores) do
    local score = scores[index]
    items[index] = score.number .. ":" .. score.numerator .. "/" .. score.denominator
  end
  self:emit("SIMILAR", document.number, table.unpack(items))
end

function SearchEngine:rank(arguments)
  local limit = number_argument(arguments[1], 1, MAX_COUNT)
  local query = {}
  for index = 2, #arguments do
    query[self:term_argument(arguments[index])] = true
  end
  local ranked = {}
  for _, document in pairs(self.documents) do
    local counts = self:term_frequencies(document)
    local matched, total = 0, 0
    for stem in pairs(query) do
      local count = counts[stem] or 0
      if count > 0 then
        matched = matched + 1
      end
      total = total + count
    end
    if matched > 0 then
      ranked[#ranked + 1] = { matched = matched, total = total, number = document.number }
    end
  end
  table.sort(ranked, function(first, second)
    if first.matched ~= second.matched then
      return first.matched > second.matched
    end
    if first.total ~= second.total then
      return first.total > second.total
    end
    return first.number < second.number
  end)
  local items = {}
  for index = 1, math.min(limit, #ranked) do
    local entry = ranked[index]
    items[index] = entry.number .. ":" .. entry.matched .. ":" .. entry.total
  end
  self:emit("RANK count=" .. #ranked, table.unpack(items))
end

function SearchEngine:info(arguments)
  local document = self:document_argument(arguments[1])
  local ranked = sorted_by_count(self:term_frequencies(document))
  local top = "-"
  if #ranked > 0 then
    top = ranked[1].stem .. ":" .. ranked[1].count
  end
  self:emit(
    "INFO", document.number, "lines=" .. #document.lines, "tokens=" .. #document.tokens,
    "indexed=" .. #self:indexed_tokens(document), "stems=" .. #ranked, "top=" .. top
  )
end

function SearchEngine:show_line(arguments)
  local document = self:document_argument(arguments[1])
  local line_number = number_argument(arguments[2], 1, MAX_LINE_NUMBER)
  if line_number > #document.lines then
    fail("NO LINE " .. document.number .. ":" .. line_number)
  end
  local tokens = document:line_tokens(line_number)
  local items = {}
  for index, token in ipairs(tokens) do
    items[index] = self:describe_token(token)
  end
  local header = "LINE " .. document.number .. ":" .. line_number
  self:emit(header, "tokens=" .. #tokens, table.unpack(items))
end

function SearchEngine:stats()
  local documents, lines, tokens, indexed = 0, 0, 0, 0
  for _, document in pairs(self.documents) do
    documents = documents + 1
    lines = lines + #document.lines
    tokens = tokens + #document.tokens
    indexed = indexed + #self:indexed_tokens(document)
  end
  self:emit(
    "STATS", "docs=" .. documents, "lines=" .. lines, "tokens=" .. tokens, "indexed=" .. indexed,
    "stems=" .. count_keys(self:total_frequencies()), "stopwords=" .. count_keys(self.stopwords)
  )
end

function SearchEngine:stop(arguments)
  local word = word_argument(arguments[1])
  if self.stopwords[word] then
    fail("ALREADY STOPWORD " .. word)
  end
  self.stopwords[word] = true
  self:emit("STOP", word, "unindexed=" .. self:form_count(word))
end

function SearchEngine:unstop(arguments)
  local word = word_argument(arguments[1])
  if not self.stopwords[word] then
    fail("NOT STOPWORD " .. word)
  end
  self.stopwords[word] = nil
  self:emit("UNSTOP", word, "indexed=" .. self:form_count(word))
end

function SearchEngine:append(arguments)
  local number = number_argument(arguments[1], 1, MAX_DOCUMENT_NUMBER)
  local document = self.documents[number]
  local created = document == nil
  if created then
    document = self:add_document(number)
  end
  local tokens = document:add_line(arguments[2])
  local indexed = 0
  for _, token in ipairs(tokens) do
    if self:is_indexed(token) then
      indexed = indexed + 1
    end
  end
  self:emit(
    "APPEND", number, "line=" .. #document.lines, "tokens=" .. #tokens,
    "indexed=" .. indexed, "new=" .. yes_no(created)
  )
end

function SearchEngine:delete(arguments)
  local document = self:document_argument(arguments[1])
  self.documents[document.number] = nil
  self:emit(
    "DELETE", document.number, "lines=" .. #document.lines, "tokens=" .. #document.tokens
  )
end

local HANDLERS = {
  STEM = { 1, 10, SearchEngine.stem_words },
  STEPS = { 1, 1, SearchEngine.show_steps },
  MEASURE = { 1, 1, SearchEngine.show_measure },
  INDEX = { 0, 1, SearchEngine.show_index },
  SEARCH = { 1, 1, SearchEngine.search },
  PHRASE = { 2, 10, SearchEngine.phrase },
  NEAR = { 3, 3, SearchEngine.near },
  TOP = { 1, 2, SearchEngine.top },
  KWIC = { 1, 1, SearchEngine.kwic },
  TF = { 2, 2, SearchEngine.term_frequency },
  DF = { 1, 1, SearchEngine.document_frequency },
  VARIANTS = { 1, 1, SearchEngine.variants },
  SIMILAR = { 2, 2, SearchEngine.similar },
  RANK = { 2, 11, SearchEngine.rank },
  INFO = { 1, 1, SearchEngine.info },
  LINE = { 2, 2, SearchEngine.show_line },
  STATS = { 0, 0, SearchEngine.stats },
  STOP = { 1, 1, SearchEngine.stop },
  UNSTOP = { 1, 1, SearchEngine.unstop },
  APPEND = { 2, 2, SearchEngine.append },
  DELETE = { 1, 1, SearchEngine.delete },
}

function SearchEngine:execute(line)
  local name, rest = line:match("^(.-) (.*)$")
  if name == nil then
    name = line
  end
  local ok, problem = pcall(function()
    local handler = HANDLERS[name]
    if handler == nil then
      fail("UNKNOWN COMMAND " .. name)
    end
    local minimum, maximum, run = table.unpack(handler)
    local arguments = rest and split_arguments(name, rest) or {}
    if #arguments < minimum or #arguments > maximum then
      fail("BAD ARGUMENTS " .. name)
    end
    run(self, arguments)
  end)
  if not ok then
    if type(problem) ~= "table" then
      error(problem, 0)
    end
    self:emit("ERROR", problem.message)
  end
end

local function main()
  local lines = {}
  for line in io.lines() do
    lines[#lines + 1] = line
  end
  local stopwords = {}
  local header = split_words(lines[1])
  for index = 2, #header do
    stopwords[header[index]] = true
  end
  local engine = SearchEngine.new(stopwords)
  local index = 2
  while starts_with(lines[index], "DOC ") do
    local document = engine:add_document(tonumber(lines[index]:sub(5)))
    index = index + 1
    while lines[index] ~= "ENDDOC" do
      document:add_line(lines[index])
      index = index + 1
    end
    index = index + 1
  end
  while lines[index] ~= nil and lines[index] ~= "END" do
    engine:execute(lines[index])
    index = index + 1
  end
  io.write(table.concat(engine.output, "\n"), "\n")
end

main()
