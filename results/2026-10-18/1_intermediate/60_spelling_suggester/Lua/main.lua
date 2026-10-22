local ADJACENT_KEYS = {
    a = "qswz", b = "ghnv", c = "dfvx", d = "cefrsx", e = "drsw",
    f = "cdgrtv", g = "bfhtvy", h = "bgjnuy", i = "jkou", j = "hikmnu",
    k = "ijlmo", l = "kop", m = "jkn", n = "bhjm", o = "iklp",
    p = "lo", q = "aw", r = "deft", s = "adewxz", t = "fgry",
    u = "hijy", v = "bcfg", w = "aeqs", x = "cdsz", y = "ghtu",
    z = "asx",
}
local SOUNDEX_GROUPS = {
    bfpv = "1", cgjkqsxz = "2", dt = "3", l = "4", mn = "5", r = "6", aeiouy = "0",
}
local SOUNDEX_DIGITS = {}
for letters, digit in pairs(SOUNDEX_GROUPS) do
    for letter in letters:gmatch(".") do
        SOUNDEX_DIGITS[letter] = digit
    end
end
local FINDING_KINDS = {"unknown", "case", "capital", "repeats"}
local COUNTER_NAMES = {"checked", "unknown", "case", "capital", "repeats", "corrected"}
local OPTION_MAXIMUMS = {LIMIT = 3, SUGGESTIONS = 10}
local KEYBOARD_MODES = {ON = true, OFF = false}
local MAX_WORD_LENGTH = 30
local MAX_FREQUENCY = 1000000
local MAX_LISTED = 20
local REPORT_SIZE = 10

local CommandError = {}

local function fail(message)
    error(setmetatable({message = message}, CommandError))
end

local function emit(...)
    print(table.concat({...}, " "))
end

local function take(list, count, describe)
    local items = {}
    for index = 1, math.min(count, #list) do
        local item = list[index]
        items[index] = describe and describe(item) or item
    end
    return items
end

local function copy(map)
    local result = {}
    for key, value in pairs(map) do
        result[key] = value
    end
    return result
end

local function count_keys(map)
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

local function sorted_keys(map, less)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys, less)
    return keys
end

local function split_spaces(text)
    local parts = {}
    for part in (text .. " "):gmatch("(.-) ") do
        parts[#parts + 1] = part
    end
    return parts
end

local function word_argument(text)
    if #text > MAX_WORD_LENGTH or not text:find("^[A-Za-z]+$") then
        fail("BAD WORD " .. text)
    end
    return text:lower()
end

local function number_argument(text, minimum, maximum)
    local value = #text <= 7 and text:find("^%d+$") and tonumber(text)
    if not value or value < minimum or value > maximum then
        fail("BAD NUMBER " .. text)
    end
    return value
end

local function decimal_text(numerator, denominator, digits)
    local scale = math.tointeger(10 ^ digits)
    local value = (2 * numerator * scale + denominator) // (2 * denominator)
    return string.format("%d.%0" .. digits .. "d", value // scale, value % scale)
end

local function capitalize_first(word)
    return word:sub(1, 1):upper() .. word:sub(2)
end

local function apply_case(token_text, word)
    if #token_text >= 2 and token_text:find("^%u+$") then
        return word:upper()
    end
    if token_text:find("^%u") then
        return capitalize_first(word)
    end
    return word
end

local function tokenize(text)
    local tokens = {}
    local previous
    local position = 0
    for start, token_text, after in text:gmatch("()([A-Za-z]+)()") do
        local gap = text:sub(position + 1, start - 1)
        local word = token_text:lower()
        local token = {
            number = #tokens + 1,
            text = token_text,
            word = word,
            stop = after - 1,
            gap = gap,
            sentence_start = previous == nil or gap:find("[.!?]") ~= nil,
            is_repeat = previous ~= nil and word == previous.word and gap:find("^ *$") ~= nil,
            mixed_case = token_text:find("%u", 2) ~= nil and not token_text:find("^%u+$"),
        }
        tokens[#tokens + 1] = token
        previous = token
        position = token.stop
    end
    return tokens
end

local function gap_cost(keyboard)
    return keyboard and 2 or 1
end

local function substitution_cost(first, second, keyboard)
    if first == second then
        return 0
    end
    if not keyboard then
        return 1
    end
    return ADJACENT_KEYS[first]:find(second, 1, true) and 1 or 2
end

local function is_swap(first, second, i, j)
    return i >= 2 and j >= 2
        and first:sub(i, i) == second:sub(j - 1, j - 1)
        and first:sub(i - 1, i - 1) == second:sub(j, j)
end

local function distance_table(first, second, keyboard)
    local gap = gap_cost(keyboard)
    local distances = {}
    for i = 0, #first do
        distances[i] = {[0] = i * gap}
    end
    for j = 1, #second do
        distances[0][j] = j * gap
    end
    for i = 1, #first do
        local row = distances[i]
        local above = distances[i - 1]
        for j = 1, #second do
            local best = math.min(
                above[j] + gap,
                row[j - 1] + gap,
                above[j - 1] + substitution_cost(first:sub(i, i), second:sub(j, j), keyboard)
            )
            if is_swap(first, second, i, j) then
                best = math.min(best, distances[i - 2][j - 2] + 1)
            end
            row[j] = best
        end
    end
    return distances
end

local function edit_distance(first, second, keyboard)
    return distance_table(first, second, keyboard)[#first][#second]
end

local function prefix_distance(word, other, keyboard)
    local row = distance_table(word, other, keyboard)[#word]
    local best = row[0]
    for j = 1, #other do
        best = math.min(best, row[j])
    end
    return best
end

local function edit_operations(first, second, keyboard)
    local distances = distance_table(first, second, keyboard)
    local gap = gap_cost(keyboard)
    local operations = {}
    local i, j = #first, #second
    while i > 0 or j > 0 do
        local source, target = first:sub(i, i), second:sub(j, j)
        if i >= 1 and j >= 1
            and distances[i][j] == distances[i - 1][j - 1]
                + substitution_cost(source, target, keyboard)
        then
            if source ~= target then
                table.insert(operations, 1, "sub:" .. source .. ">" .. target)
            end
            i, j = i - 1, j - 1
        elseif is_swap(first, second, i, j) and distances[i][j] == distances[i - 2][j - 2] + 1 then
            table.insert(operations, 1, "swap:" .. first:sub(i - 1, i))
            i, j = i - 2, j - 2
        elseif i >= 1 and distances[i][j] == distances[i - 1][j] + gap then
            table.insert(operations, 1, "del:" .. source)
            i = i - 1
        else
            table.insert(operations, 1, "ins:" .. target)
            j = j - 1
        end
    end
    return distances[#first][#second], operations
end

local function soundex(word)
    local first = word:sub(1, 1)
    local code = first:upper()
    local previous = SOUNDEX_DIGITS[first] or "0"
    for letter in word:sub(2):gmatch(".") do
        local digit = SOUNDEX_DIGITS[letter]
        if digit then
            if digit ~= "0" and digit ~= previous then
                code = code .. digit
            end
            previous = digit
        end
    end
    return (code .. "000"):sub(1, 4)
end

local function segmentation_less(first, second)
    if #first ~= #second then
        return #first < #second
    end
    for index = 1, #first do
        if first[index] ~= second[index] then
            return first[index] < second[index]
        end
    end
    return false
end

local function segment(word, dictionary)
    local length = #word
    local ways = {[length + 1] = 1}
    local best = {[length + 1] = {}}
    for start = length, 1, -1 do
        ways[start] = 0
        for stop = start, length do
            local piece = word:sub(start, stop)
            if dictionary[piece] and ways[stop + 1] > 0 then
                ways[start] = ways[start] + ways[stop + 1]
                local candidate = {piece, table.unpack(best[stop + 1])}
                if best[start] == nil or segmentation_less(candidate, best[start]) then
                    best[start] = candidate
                end
            end
        end
    end
    return ways[1], best[1]
end

local function ranked_less(first, second)
    if first.distance ~= second.distance then
        return first.distance < second.distance
    end
    if first.frequency ~= second.frequency then
        return first.frequency > second.frequency
    end
    return first.word < second.word
end

local function scored_item(entry)
    return entry.word .. ":" .. entry.distance
end

local function emit_ranked(head, log)
    local entries = {}
    for key, count in pairs(log) do
        entries[#entries + 1] = {key = key, count = count}
    end
    table.sort(entries, function(first, second)
        if first.count ~= second.count then
            return first.count > second.count
        end
        return first.key < second.key
    end)
    local items = take(entries, REPORT_SIZE, function(entry)
        return entry.key .. ":" .. entry.count
    end)
    emit(head, "distinct=" .. #entries, table.unpack(items))
end

local SpellChecker = {}
SpellChecker.__index = SpellChecker

function SpellChecker.new(dictionary)
    local counters = {}
    for _, name in ipairs(COUNTER_NAMES) do
        counters[name] = 0
    end
    return setmetatable({
        dictionary = dictionary,
        ignored = {},
        rules = {},
        keyboard = false,
        base_limit = 2,
        suggestion_count = 5,
        undo_history = {},
        unknown_log = {},
        correction_log = {},
        counters = counters,
    }, SpellChecker)
end

function SpellChecker:limit()
    return self.keyboard and 2 * self.base_limit or self.base_limit
end

function SpellChecker:is_known(word)
    return self.dictionary[word] ~= nil or self.ignored[word] ~= nil
end

function SpellChecker:frequency_order()
    local dictionary = self.dictionary
    return sorted_keys(dictionary, function(first, second)
        if dictionary[first] ~= dictionary[second] then
            return dictionary[first] > dictionary[second]
        end
        return first < second
    end)
end

function SpellChecker:with_frequencies(words, count)
    return take(words, count, function(word)
        return word .. ":" .. self.dictionary[word]
    end)
end

function SpellChecker:require_entry(word)
    local frequency = self.dictionary[word]
    if not frequency then
        fail("NOT FOUND " .. word)
    end
    return frequency
end

function SpellChecker:candidates(word)
    local limit = self:limit()
    local gap = gap_cost(self.keyboard)
    local found = {}
    for other, frequency in pairs(self.dictionary) do
        if other ~= word and math.abs(#other - #word) * gap <= limit then
            local distance = edit_distance(word, other, self.keyboard)
            if distance <= limit then
                found[#found + 1] = {word = other, distance = distance, frequency = frequency}
            end
        end
    end
    table.sort(found, ranked_less)
    return found
end

function SpellChecker:correction(word)
    if self:is_known(word) then
        return nil
    end
    if self.rules[word] then
        return self.rules[word]
    end
    local found = self:candidates(word)
    return found[1] and found[1].word
end

function SpellChecker:record_undo(name)
    self.undo_history[#self.undo_history + 1] = {
        name = name,
        dictionary = copy(self.dictionary),
        ignored = copy(self.ignored),
        rules = copy(self.rules),
    }
end

function SpellChecker:log_correction(word, replacement)
    -- ">" sorts before every letter, so ordering these keys orders by word, then correction.
    local key = word .. ">" .. replacement
    self.correction_log[key] = (self.correction_log[key] or 0) + 1
    self.counters.corrected = self.counters.corrected + 1
end

function SpellChecker:unknown_finding(token)
    local prefix = "UNKNOWN " .. token.number .. " " .. token.text
    local target = self.rules[token.word]
    if target then
        return prefix .. " RULE " .. target
    end
    local found = self:candidates(token.word)
    if #found == 0 then
        return prefix .. " NONE"
    end
    local words = take(found, self.suggestion_count, function(entry)
        return entry.word
    end)
    return prefix .. " SUGGEST " .. table.concat(words, " ")
end

function SpellChecker:check(text)
    local tokens = tokenize(text)
    local findings = {}
    local counts = {}
    for _, kind in ipairs(FINDING_KINDS) do
        counts[kind] = 0
    end
    local function add_finding(kind, line)
        counts[kind] = counts[kind] + 1
        findings[#findings + 1] = line
    end
    for _, token in ipairs(tokens) do
        if not self:is_known(token.word) then
            add_finding("unknown", self:unknown_finding(token))
            self.unknown_log[token.word] = (self.unknown_log[token.word] or 0) + 1
        end
        if token.mixed_case then
            add_finding("case", "CASE " .. token.number .. " " .. token.text)
        end
        if token.sentence_start and token.text:find("^%l") then
            add_finding("capital", "CAPITAL " .. token.number .. " " .. token.text)
        end
        if token.is_repeat then
            add_finding("repeats", "REPEAT " .. token.number .. " " .. token.text)
        end
    end
    self.counters.checked = self.counters.checked + #tokens
    local summary = {}
    for index, kind in ipairs(FINDING_KINDS) do
        self.counters[kind] = self.counters[kind] + counts[kind]
        summary[index] = kind .. "=" .. counts[kind]
    end
    emit("CHECK", "words=" .. #tokens, table.unpack(summary))
    for _, line in ipairs(findings) do
        print(line)
    end
end

function SpellChecker:correct(text)
    local pieces = {}
    local position = 0
    local changed = 0
    for _, token in ipairs(tokenize(text)) do
        local replacement = self:correction(token.word)
        if replacement then
            pieces[#pieces + 1] = token.gap .. apply_case(token.text, replacement)
            self:log_correction(token.word, replacement)
            changed = changed + 1
        else
            pieces[#pieces + 1] = token.gap .. token.text
        end
        position = token.stop
    end
    pieces[#pieces + 1] = text:sub(position + 1)
    emit("CORRECT changed=" .. changed .. ":", table.concat(pieces))
end

function SpellChecker:fix(text)
    local pieces = {}
    local position = 0
    local removed = 0
    local replaced = 0
    local recased = 0
    for _, token in ipairs(tokenize(text)) do
        position = token.stop
        if token.is_repeat then
            removed = removed + 1
        else
            local replacement = self:correction(token.word)
            local result = apply_case(token.text, replacement or token.word)
            if token.sentence_start and result:find("^%l") then
                result = capitalize_first(result)
            end
            if replacement then
                self:log_correction(token.word, replacement)
                replaced = replaced + 1
            elseif result ~= token.text then
                recased = recased + 1
            end
            pieces[#pieces + 1] = token.gap .. result
        end
    end
    pieces[#pieces + 1] = text:sub(position + 1)
    emit(
        "FIX", "removed=" .. removed, "replaced=" .. replaced,
        "recased=" .. recased .. ":", table.concat(pieces)
    )
end

function SpellChecker:profile(text)
    local tokens = tokenize(text)
    local forms = {}
    local distinct = 0
    local unknown = 0
    local sentences = 0
    local characters = 0
    local longest
    for _, token in ipairs(tokens) do
        if not forms[token.word] then
            forms[token.word] = true
            distinct = distinct + 1
        end
        if not self:is_known(token.word) then
            unknown = unknown + 1
        end
        if token.sentence_start then
            sentences = sentences + 1
        end
        characters = characters + #token.text
        if longest == nil or #token.text > #longest.text then
            longest = token
        end
    end
    local rate, average, longest_word = "0.0", "0.00", "-"
    if #tokens > 0 then
        rate = decimal_text(100 * unknown, #tokens, 1)
        average = decimal_text(characters, #tokens, 2)
        longest_word = longest.word
    end
    emit(
        "PROFILE", "words=" .. #tokens, "distinct=" .. distinct,
        "unknown=" .. unknown, "rate=" .. rate, "avglen=" .. average,
        "longest=" .. longest_word, "sentences=" .. sentences
    )
end

function SpellChecker:learn(text)
    self:record_undo("LEARN")
    local updated = 0
    local added = 0
    local skipped = 0
    for _, token in ipairs(tokenize(text)) do
        local word = token.word
        if #word > MAX_WORD_LENGTH then
            skipped = skipped + 1
        elseif self.dictionary[word] then
            self.dictionary[word] = self.dictionary[word] + 1
            updated = updated + 1
        else
            self.dictionary[word] = 1
            self.ignored[word] = nil
            added = added + 1
        end
    end
    emit("LEARN", "updated=" .. updated, "added=" .. added, "skipped=" .. skipped)
end

function SpellChecker:suggest(arguments)
    local word = word_argument(arguments[1])
    if self:is_known(word) then
        emit("SUGGEST", word, "KNOWN")
    elseif self.rules[word] then
        emit("SUGGEST", word, "RULE", self.rules[word])
    else
        local found = self:candidates(word)
        local items = take(found, self.suggestion_count, scored_item)
        emit("SUGGEST", word, "found=" .. #found, table.unpack(items))
    end
end

function SpellChecker:dist(arguments)
    local first = word_argument(arguments[1])
    local second = word_argument(arguments[2])
    local distance, operations = edit_operations(first, second, self.keyboard)
    emit("DIST", first, second, distance, table.unpack(operations))
end

function SpellChecker:soundex_code(arguments)
    local word = word_argument(arguments[1])
    emit("SOUNDEX", word, soundex(word))
end

function SpellChecker:sounds(arguments)
    local word = word_argument(arguments[1])
    local code = soundex(word)
    local matches = {}
    for _, other in ipairs(self:frequency_order()) do
        if other ~= word and soundex(other) == code then
            matches[#matches + 1] = other
        end
    end
    emit("SOUNDS", word, code, "count=" .. #matches, table.unpack(take(matches, REPORT_SIZE)))
end

function SpellChecker:split(arguments)
    local word = word_argument(arguments[1])
    local ways, best = segment(word, self.dictionary)
    if ways == 0 then
        emit("SPLIT", word, "ways=0", "->", "NONE")
    else
        emit("SPLIT", word, "ways=" .. ways, "->", table.unpack(best))
    end
end

function SpellChecker:prefix(arguments)
    local word = word_argument(arguments[1])
    local count = number_argument(arguments[2], 1, MAX_LISTED)
    local matches = {}
    for _, other in ipairs(self:frequency_order()) do
        if other:sub(1, #word) == word then
            matches[#matches + 1] = other
        end
    end
    local items = self:with_frequencies(matches, count)
    emit("PREFIX", word, "count=" .. #matches, table.unpack(items))
end

function SpellChecker:complete(arguments)
    local word = word_argument(arguments[1])
    local count = number_argument(arguments[2], 1, MAX_LISTED)
    local threshold = self:limit() // 2
    local matches = {}
    for other, frequency in pairs(self.dictionary) do
        local distance = prefix_distance(word, other, self.keyboard)
        if distance <= threshold then
            matches[#matches + 1] = {word = other, distance = distance, frequency = frequency}
        end
    end
    table.sort(matches, ranked_less)
    local items = take(matches, count, scored_item)
    emit("COMPLETE", word, "count=" .. #matches, table.unpack(items))
end

function SpellChecker:list_words(arguments)
    local word = word_argument(arguments[1])
    local count = number_argument(arguments[2], 1, MAX_LISTED)
    local matches = {}
    for _, other in ipairs(sorted_keys(self.dictionary)) do
        if other >= word then
            matches[#matches + 1] = other
        end
    end
    local items = self:with_frequencies(matches, count)
    emit("LIST", word, "count=" .. #matches, table.unpack(items))
end

function SpellChecker:word_info(arguments)
    local word = word_argument(arguments[1])
    local frequency = self:require_entry(word)
    local rank
    for index, other in ipairs(self:frequency_order()) do
        if other == word then
            rank = index
            break
        end
    end
    emit(
        "WORD", word, "freq=" .. frequency, "rank=" .. rank,
        "soundex=" .. soundex(word), "neighbors=" .. #self:candidates(word)
    )
end

function SpellChecker:add(arguments)
    local word = word_argument(arguments[1])
    local frequency = number_argument(arguments[2], 1, MAX_FREQUENCY)
    if self.dictionary[word] then
        fail("DUPLICATE " .. word)
    end
    self:record_undo("ADD")
    self.dictionary[word] = frequency
    self.ignored[word] = nil
    emit("ADD", word, frequency)
end

function SpellChecker:remove(arguments)
    local word = word_argument(arguments[1])
    local frequency = self:require_entry(word)
    self:record_undo("REMOVE")
    self.dictionary[word] = nil
    emit("REMOVE", word, frequency)
end

function SpellChecker:ignore(arguments)
    local word = word_argument(arguments[1])
    if self.dictionary[word] then
        fail("IN DICTIONARY " .. word)
    end
    if self.ignored[word] then
        fail("ALREADY IGNORED " .. word)
    end
    self:record_undo("IGNORE")
    self.ignored[word] = true
    emit("IGNORE", word)
end

function SpellChecker:unignore(arguments)
    local word = word_argument(arguments[1])
    if not self.ignored[word] then
        fail("NOT IGNORED " .. word)
    end
    self:record_undo("UNIGNORE")
    self.ignored[word] = nil
    emit("UNIGNORE", word)
end

function SpellChecker:rule(arguments)
    local source = word_argument(arguments[1])
    local target = word_argument(arguments[2])
    if self.dictionary[source] then
        fail("IN DICTIONARY " .. source)
    end
    if not self.dictionary[target] then
        fail("NOT FOUND " .. target)
    end
    self:record_undo("RULE")
    local previous = self.rules[source]
    self.rules[source] = target
    if previous then
        emit("RULE", source, target, "REPLACED", previous)
    else
        emit("RULE", source, target)
    end
end

function SpellChecker:unrule(arguments)
    local word = word_argument(arguments[1])
    local target = self.rules[word]
    if not target then
        fail("NO RULE " .. word)
    end
    self:record_undo("UNRULE")
    self.rules[word] = nil
    emit("UNRULE", word, target)
end

function SpellChecker:show_rules()
    local items = {}
    for index, source in ipairs(sorted_keys(self.rules)) do
        items[index] = source .. ">" .. self.rules[source]
    end
    emit("RULES", "count=" .. #items, table.unpack(items))
end

function SpellChecker:keyboard_mode(arguments)
    local mode = arguments[1]
    local enabled = KEYBOARD_MODES[mode]
    if enabled == nil then
        fail("BAD MODE " .. mode)
    end
    self.keyboard = enabled
    emit("KEYBOARD", mode)
end

function SpellChecker:set_option(arguments)
    local option = arguments[1]
    local maximum = OPTION_MAXIMUMS[option]
    if not maximum then
        fail("BAD OPTION " .. option)
    end
    local value = number_argument(arguments[2], 1, maximum)
    if option == "LIMIT" then
        self.base_limit = value
    else
        self.suggestion_count = value
    end
    emit("SET", option, value)
end

function SpellChecker:undo()
    if #self.undo_history == 0 then
        fail("NOTHING TO UNDO")
    end
    local record = table.remove(self.undo_history)
    self.dictionary = record.dictionary
    self.ignored = record.ignored
    self.rules = record.rules
    emit("UNDO", record.name)
end

function SpellChecker:report()
    emit_ranked("REPORT", self.unknown_log)
end

function SpellChecker:history()
    emit_ranked("HISTORY", self.correction_log)
end

function SpellChecker:stats()
    local order = self:frequency_order()
    local total = 0
    local characters = 0
    for word, frequency in pairs(self.dictionary) do
        total = total + frequency
        characters = characters + #word
    end
    local top = order[1]
    emit(
        "STATS", "words=" .. #order, "total=" .. total,
        "avglen=" .. decimal_text(characters, #order, 2),
        "top=" .. top .. ":" .. self.dictionary[top], "ignored=" .. count_keys(self.ignored),
        "rules=" .. count_keys(self.rules), "keyboard=" .. (self.keyboard and "ON" or "OFF"),
        "limit=" .. self:limit(), "suggestions=" .. self.suggestion_count,
        "undo=" .. #self.undo_history
    )
    local session = {}
    for index, name in ipairs(COUNTER_NAMES) do
        session[index] = name .. "=" .. self.counters[name]
    end
    emit("SESSION", table.unpack(session))
end

local COMMANDS = {
    CHECK = {text = true, run = SpellChecker.check},
    CORRECT = {text = true, run = SpellChecker.correct},
    FIX = {text = true, run = SpellChecker.fix},
    PROFILE = {text = true, run = SpellChecker.profile},
    LEARN = {text = true, run = SpellChecker.learn},
    SUGGEST = {arity = 1, run = SpellChecker.suggest},
    DIST = {arity = 2, run = SpellChecker.dist},
    SOUNDEX = {arity = 1, run = SpellChecker.soundex_code},
    SOUNDS = {arity = 1, run = SpellChecker.sounds},
    SPLIT = {arity = 1, run = SpellChecker.split},
    PREFIX = {arity = 2, run = SpellChecker.prefix},
    COMPLETE = {arity = 2, run = SpellChecker.complete},
    LIST = {arity = 2, run = SpellChecker.list_words},
    WORD = {arity = 1, run = SpellChecker.word_info},
    ADD = {arity = 2, run = SpellChecker.add},
    REMOVE = {arity = 1, run = SpellChecker.remove},
    IGNORE = {arity = 1, run = SpellChecker.ignore},
    UNIGNORE = {arity = 1, run = SpellChecker.unignore},
    RULE = {arity = 2, run = SpellChecker.rule},
    UNRULE = {arity = 1, run = SpellChecker.unrule},
    RULES = {arity = 0, run = SpellChecker.show_rules},
    KEYBOARD = {arity = 1, run = SpellChecker.keyboard_mode},
    SET = {arity = 2, run = SpellChecker.set_option},
    UNDO = {arity = 0, run = SpellChecker.undo},
    REPORT = {arity = 0, run = SpellChecker.report},
    HISTORY = {arity = 0, run = SpellChecker.history},
    STATS = {arity = 0, run = SpellChecker.stats},
}

function SpellChecker:dispatch(name, rest)
    local command = COMMANDS[name]
    if not command then
        fail("UNKNOWN COMMAND " .. name)
    end
    if command.text then
        if not rest then
            fail("BAD ARGUMENTS " .. name)
        end
        command.run(self, rest)
    else
        local arguments = rest and split_spaces(rest) or {}
        if #arguments ~= command.arity then
            fail("BAD ARGUMENTS " .. name)
        end
        command.run(self, arguments)
    end
end

function SpellChecker:execute(line)
    local space = line:find(" ", 1, true)
    local name = space and line:sub(1, space - 1) or line
    local rest = space and line:sub(space + 1)
    local ok, err = pcall(self.dispatch, self, name, rest)
    if not ok then
        if getmetatable(err) ~= CommandError then
            error(err, 0)
        end
        print("ERROR " .. err.message)
    end
end

local function main()
    local dictionary = {}
    local word_count = tonumber(io.read("l"))
    for _ = 1, word_count do
        local word, frequency = io.read("l"):match("^(%S+)%s+(%S+)")
        dictionary[word] = tonumber(frequency)
    end
    local checker = SpellChecker.new(dictionary)
    local command_count = tonumber(io.read("l"))
    for _ = 1, command_count do
        checker:execute(io.read("l"))
    end
end

main()
