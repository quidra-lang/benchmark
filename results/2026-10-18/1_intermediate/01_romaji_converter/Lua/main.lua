local function split_words(text)
    local values = {}
    for value in text:gmatch("[^ ]+") do
        values[#values + 1] = value
    end
    return values
end

local systems = split_words("HEPBURN TRADITIONAL KUNREI NIHON WAPURO")
local rows = split_words("a ka sa ta na ha ma ya ra wa ga za da ba pa")
local row_text = {"a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
    "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo", "ra ri ru re ro",
    "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo", "da di du de do", "ba bi bu be bo", "pa pi pu pe po"}
local contract_rows = split_words("ka sa ta na ha ma ra ga za da ba pa")
local base_row = {ga = "ka", za = "sa", da = "ta", ba = "ha", pa = "ha"}
local devoice_letter = {g = "k", z = "s", d = "t", b = "h", p = "h"}
local gojuon = split_words("a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N")
local iroha = split_words("i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N")
local arg_counts = {SET = 2, TABLE = 2, CONVERT = 2, NORMALIZE = 0, REVERSE = 1,
    VALID = 1, DETECT = 0, DIFF = 2, SAME = 2, MORAE = 1, SYLLABLES = 1, ROW = 1,
    STATS = 1, SORT = 1, INDEX = 1, FIND = 2, HAIKU = 1, KAIBUN = 1, SHIRITORI = 1}
local set_values = {LONG = split_words("KEEP DROP PASSPORT HYPHEN DOUBLE"),
    CASE = split_words("KEEP LOWER UPPER TITLE"), ORDER = split_words("GOJUON IROHA")}
local identifiers, row_of, dan_of, i_of = {}, {}, {}, {}
for i, row in ipairs(rows) do
    for _, id in ipairs(split_words(row_text[i])) do
        identifiers[#identifiers + 1] = id
        row_of[id] = row
        dan_of[id] = id:sub(-1)
        if dan_of[id] == "i" then
            i_of[row] = id
        end
    end
end
for _, row in ipairs(contract_rows) do
    for _, dan in ipairs({"ya", "yu", "yo"}) do
        local id = i_of[row]:sub(1, -2) .. dan
        identifiers[#identifiers + 1] = id
        row_of[id] = row
        dan_of[id] = dan
    end
end

local function contains(values, value)
    for _, other in ipairs(values) do
        if other == value then
            return true
        end
    end
    return false
end

local function fail(message)
    error(message, 0)
end

local function column_error(column, message)
    fail("col " .. column .. ": " .. message)
end

local function is_syllabic(id)
    return row_of[id] ~= nil
end

local function is_vowel(id)
    return id ~= "" and #id == 1 and ("aiueo"):find(id, 1, true) ~= nil
end

local function spelling(system, id)
    if system == "HEPBURN" or system == "TRADITIONAL" or system == "WAPURO" then
        local changes = {si = "shi", ti = "chi", tu = "tsu", hu = "fu", zi = "ji"}
        if system ~= "WAPURO" then
            changes.di, changes.du, changes.wi, changes.we, changes.wo = "ji", "zu", "i", "e", "o"
        end
        if changes[id] then
            return changes[id]
        end
        local prefix = id:sub(1, 2)
        if prefix == "sy" then
            return "sh" .. id:sub(3)
        elseif prefix == "ty" then
            return "ch" .. id:sub(3)
        elseif prefix == "zy" or (system ~= "WAPURO" and prefix == "dy") then
            return "j" .. id:sub(3)
        end
    elseif system == "KUNREI" then
        local changes = {di = "zi", du = "zu", wi = "i", we = "e", wo = "o", dya = "zya", dyu = "zyu", dyo = "zyo"}
        return changes[id] or id
    end
    return id
end

local readings = {}
for _, system in ipairs({"HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO", "NORMAL"}) do
    local seen, entries = {}, {}
    local styles = {system}
    if system == "NORMAL" then
        styles = {"HEPBURN", "KUNREI", "NIHON", "WAPURO"}
    end
    for _, id in ipairs(identifiers) do
        for _, style in ipairs(styles) do
            local text = spelling(style, id)
            if not seen[text] then
                seen[text] = true
                entries[#entries + 1] = {text = text, id = id}
            end
        end
    end
    table.sort(entries, function(a, b)
        return #a.text > #b.text
    end)
    readings[system] = entries
end

local function match_syllable(word, position, system)
    if position > #word then
        return nil
    end
    for _, entry in ipairs(readings[system]) do
        if word:sub(position, position + #entry.text - 1) == entry.text then
            return entry
        end
    end
    return nil
end

local function parse_word(text, start, system)
    local word = text:lower()
    local ids, columns = {}, {}
    local p = 1
    while p <= #word do
        local c, c2, c3 = word:sub(p, p), word:sub(p + 1, p + 1), word:sub(p + 2, p + 2)
        local matched = match_syllable(word, p, system)
        local id, advance = nil, 1
        if c == "-" then
            if #ids == 0 or not is_syllabic(ids[#ids]) then
                column_error(start + p - 1, "misplaced long mark")
            end
            id = "-"
        elseif c == "'" then
            column_error(start + p - 1, "misplaced apostrophe")
        elseif matched then
            id, advance = matched.id, #matched.text
        elseif (system == "WAPURO" or system == "NORMAL") and word:sub(p, p + 2) == "xtu" then
            id, advance = "Q", 3
        elseif c == "n" then
            id = "N"
            if system == "WAPURO" then
                if c2 == "n" then
                    advance = 2
                end
            elseif system == "NORMAL" then
                if c2 == "'" or (c2 == "n" and not contains({"a", "i", "u", "e", "o", "y", "'"}, c3)) then
                    advance = 2
                end
            elseif c2 == "'" then
                advance = 2
            end
        elseif (system == "TRADITIONAL" or system == "NORMAL") and c == "m" and contains({"b", "m", "p"}, c2) then
            id = "N"
        elseif c:match("^[a-z]$") and not contains({"a", "i", "u", "e", "o", "n"}, c) and c == c2 and match_syllable(word, p + 1, system) then
            id = "Q"
        elseif contains({"HEPBURN", "TRADITIONAL", "NORMAL"}, system) and c == "t" and c2 == "c" and c3 == "h" and match_syllable(word, p + 1, system) then
            id = "Q"
        else
            column_error(start + p - 1, "unknown syllable")
        end
        ids[#ids + 1] = id
        columns[#columns + 1] = start + p - 1
        p = p + advance
    end
    return ids, columns
end

local function long_flags(ids)
    local paired, long = {}, {}
    for i, id in ipairs(ids) do
        paired[i], long[i] = false, id == "-"
    end
    local i = 1
    while i < #ids do
        local first, second = ids[i], ids[i + 1]
        local pair = false
        if is_syllabic(first) and is_vowel(second) then
            local vowel = first:sub(-1)
            if vowel == second or (vowel == "o" and second == "u") or (vowel == "e" and second == "i") then
                paired[i + 1] = true
                long[i + 1] = (vowel == "o" and (second == "o" or second == "u")) or (vowel == "u" and second == "u")
                pair = true
            end
        end
        i = i + (pair and 2 or 1)
    end
    return paired, long
end

local function write_parts(ids, columns, system, long_setting)
    local _, long = long_flags(ids)
    local parts = {}
    for i, id in ipairs(ids) do
        local next_id = ids[i + 1] or ""
        local next_text = is_syllabic(next_id) and spelling(system, next_id) or ""
        local first = next_text:sub(1, 1)
        local part
        if long[i] then
            local vowel = ids[i - 1]:sub(-1)
            if long_setting == "KEEP" then
                part = id == "-" and "-" or spelling(system, id)
            elseif long_setting == "DROP" then
                part = ""
            elseif long_setting == "PASSPORT" then
                part = vowel == "o" and not is_vowel(first) and "h" or ""
            elseif long_setting == "HYPHEN" then
                part = "-"
            else
                part = vowel
            end
        elseif is_syllabic(id) then
            part = spelling(system, id)
        elseif id == "N" then
            if system == "WAPURO" then
                part = (next_id == "N" or contains({"a", "i", "u", "e", "o", "y", "n"}, first)) and "nn" or "n"
            elseif system == "TRADITIONAL" and contains({"b", "m", "p"}, first) then
                part = "m"
            else
                part = contains({"a", "i", "u", "e", "o", "y"}, first) and "n'" or "n"
            end
        else
            if next_text ~= "" and not contains({"a", "i", "u", "e", "o", "n"}, first) then
                part = (system == "HEPBURN" or system == "TRADITIONAL") and next_text:sub(1, 2) == "ch" and "t" or first
            elseif system == "WAPURO" then
                part = "xtu"
            else
                column_error(columns[i], "small tsu cannot be written")
            end
        end
        parts[i] = part
    end
    return parts
end

local function word_pattern(text)
    if text == text:lower() then
        return "LOWER"
    elseif text:sub(1, 1):match("^[A-Z]$") and text:sub(2) == text:sub(2):lower() then
        return "TITLE"
    end
    local _, count = text:gsub("[A-Z]", "")
    if count >= 2 and text == text:upper() then
        return "UPPER"
    end
    return ""
end

local function written(word, system, settings, canonical, ids, columns)
    local mode = canonical and "KEEP" or settings.LONG
    local text = table.concat(write_parts(ids or word.ids, columns or word.columns, system, mode))
    local pattern = word.pattern
    if not canonical and settings.CASE ~= "KEEP" then
        pattern = settings.CASE
    end
    if pattern == "UPPER" then
        return text:upper()
    elseif pattern == "TITLE" then
        return text:sub(1, 1):upper() .. text:sub(2)
    end
    return text
end

local function count_character(text, character)
    local count = 0
    for i = 1, #text do
        if text:sub(i, i) == character then
            count = count + 1
        end
    end
    return count
end

local function words_in(text)
    local words = {}
    local position = 1
    while true do
        local first, last = text:find("[A-Za-z'-]+", position)
        if not first then
            break
        end
        words[#words + 1] = {text = text:sub(first, last), start = first, pattern = "", ids = {}, columns = {},
            part = count_character(text:sub(1, first - 1), "/") + 1, index = #words + 1}
        position = last + 1
    end
    return words
end

local function replace_words(text, words, replacements)
    local output = {}
    local position = 1
    for i, word in ipairs(words) do
        output[#output + 1] = text:sub(position, word.start - 1)
        output[#output + 1] = replacements[i]
        position = word.start + #word.text
    end
    output[#output + 1] = text:sub(position)
    return table.concat(output)
end

local function devoice(id)
    return (devoice_letter[id:sub(1, 1)] or id:sub(1, 1)) .. id:sub(2)
end

local function elements(ids)
    local items = {}
    for _, id in ipairs(ids) do
        if id == "N" then
            items[#items + 1] = {"N", 0, 0}
        elseif id == "Q" then
            items[#items + 1] = {"tu", 0, 1}
        elseif id ~= "-" then
            local row = row_of[id]
            local voice = 0
            if contains({"ga", "za", "da", "ba"}, row) then
                voice = 1
            elseif row == "pa" then
                voice = 2
            end
            if #dan_of[id] == 2 then
                items[#items + 1] = {devoice(i_of[row]), voice, 0}
                items[#items + 1] = {dan_of[id], 0, 1}
            else
                items[#items + 1] = {devoice(id), voice, 0}
            end
        end
    end
    return items
end

local function collation(word, order)
    local ranks = {}
    for i, id in ipairs(order == "GOJUON" and gojuon or iroha) do
        ranks[id] = i
    end
    local key = {{}, {}, {}, {}}
    for i, item in ipairs(elements(word.ids)) do
        key[1][i], key[2][i], key[3][i] = ranks[item[1]], item[2], item[3]
    end
    for i, id in ipairs(word.ids) do
        key[4][i] = id == "-" and 1 or 0
    end
    return key
end

local function vector_compare(a, b)
    for i = 1, math.min(#a, #b) do
        if a[i] ~= b[i] then
            return a[i] < b[i] and -1 or 1
        end
    end
    if #a == #b then
        return 0
    end
    return #a < #b and -1 or 1
end

local function pattern_tokens(pattern, system)
    if pattern:find("[^a-z'%-?*]") then
        fail("invalid pattern")
    end
    local tokens, chunk = {}, ""
    local function flush()
        local valid, ids = pcall(parse_word, chunk, 1, system)
        if not valid then
            fail("invalid pattern")
        end
        for _, id in ipairs(ids) do
            tokens[#tokens + 1] = id
        end
        chunk = ""
    end
    for i = 1, #pattern do
        local c = pattern:sub(i, i)
        if c == "?" or c == "*" then
            flush()
            tokens[#tokens + 1] = c
        else
            chunk = chunk .. c
        end
    end
    flush()
    return tokens
end

local function wildcard_matches(tokens, ids)
    local previous = {[0] = true}
    for j = 1, #ids do
        previous[j] = false
    end
    for _, token in ipairs(tokens) do
        local current = {[0] = token == "*" and previous[0] or false}
        for j, id in ipairs(ids) do
            if token == "*" then
                current[j] = previous[j] or current[j - 1]
            else
                current[j] = previous[j - 1] and (token == "?" or token == id)
            end
        end
        previous = current
    end
    return previous[#ids]
end

local function equal_ids(a, b)
    return vector_compare(a, b) == 0
end

local function execute(line, settings)
    local command = line:match("^[^ ]+")
    local k = arg_counts[command]
    if k == nil then
        fail("unknown command " .. command)
    end
    local args, text = {}, ""
    if command == "SET" or command == "TABLE" then
        local parts = split_words(line)
        if #parts < 3 then
            fail("missing argument")
        elseif #parts > 3 then
            fail("too many arguments")
        end
        args = {parts[2], parts[3]}
    else
        if count_character(line, " ") < k + 1 then
            fail("missing argument")
        end
        local position = #command + 2
        for i = 1, k do
            local ending = line:find(" ", position, true)
            args[i] = line:sub(position, ending - 1)
            position = ending + 1
        end
        text = line:sub(position)
    end
    local system_count = 1
    if command == "SET" or command == "NORMALIZE" or command == "DETECT" then
        system_count = 0
    elseif command == "CONVERT" or command == "DIFF" or command == "SAME" then
        system_count = 2
    end
    for i = 1, system_count do
        if not contains(systems, args[i]) then
            fail("unknown system " .. args[i])
        end
    end
    if command == "SET" then
        local option, value = table.unpack(args)
        if not set_values[option] then
            fail("unknown option " .. option)
        elseif not contains(set_values[option], value) then
            fail("unknown value " .. value)
        end
        settings[option] = value
        return option .. "=" .. value
    elseif command == "TABLE" then
        local system, row = table.unpack(args)
        if not contains(rows, row) then
            fail("unknown row " .. row)
        end
        local output = {}
        for _, id in ipairs(identifiers) do
            if row_of[id] == row then
                output[#output + 1] = spelling(system, id)
            end
        end
        return table.concat(output, " ")
    end
    local tokens = command == "FIND" and pattern_tokens(args[2], args[1]) or {}
    local slash_allowed = command == "HAIKU" or command == "SAME"
    for i = 1, #text do
        local c = text:sub(i, i)
        local allowed = c:match("^[A-Za-z0-9]$") or ("'- .,!?;:()\""):find(c, 1, true) or (slash_allowed and c == "/")
        if not allowed then
            column_error(i, "invalid character")
        end
    end
    local words = words_in(text)
    if command == "SAME" or command == "HAIKU" then
        local parts = count_character(text, "/") + 1
        local expected = command == "SAME" and "expected two texts" or "expected 3 or 5 lines"
        if (command == "SAME" and parts ~= 2) or (command == "HAIKU" and parts ~= 3 and parts ~= 5) then
            fail(expected)
        end
        for i = 1, parts do
            local found = false
            for _, word in ipairs(words) do
                if word.part == i then
                    found = true
                end
            end
            if not found then
                fail(expected)
            end
        end
    end
    if #words == 0 then
        fail("no words")
    end
    for _, word in ipairs(words) do
        word.pattern = word_pattern(word.text)
        if word.pattern == "" then
            column_error(word.start, "mixed case")
        end
    end
    if command == "DETECT" then
        local output = {}
        for _, system in ipairs(systems) do
            local verdict = "canonical"
            for _, word in ipairs(words) do
                local valid, ids, columns = pcall(parse_word, word.text, word.start, system)
                if not valid then
                    verdict = "error"
                    break
                end
                word.ids, word.columns = ids, columns
            end
            if verdict ~= "error" then
                for _, word in ipairs(words) do
                    if written(word, system, settings, true) ~= word.text then
                        verdict = "readable"
                    end
                end
            end
            output[#output + 1] = system .. "=" .. verdict
        end
        return table.concat(output, " ")
    end
    for _, word in ipairs(words) do
        local system = args[1]
        if command == "NORMALIZE" then
            system = "NORMAL"
        elseif command == "SAME" then
            system = args[word.part]
        end
        word.ids, word.columns = parse_word(word.text, word.start, system)
    end
    local system = command == "NORMALIZE" and "HEPBURN" or args[1]
    if command == "CONVERT" or command == "NORMALIZE" or command == "REVERSE" then
        local target = command == "CONVERT" and args[2] or system
        local output = {}
        for i, word in ipairs(words) do
            local ids, columns = word.ids, word.columns
            if command == "REVERSE" then
                ids, columns = {}, {}
                for j = #word.ids, 1, -1 do
                    local id = word.ids[j]
                    ids[#ids + 1] = id == "-" and word.ids[j - 1]:sub(-1) or id
                    columns[#columns + 1] = word.columns[j]
                end
            end
            output[i] = written(word, target, settings, false, ids, columns)
        end
        return replace_words(text, words, output)
    elseif command == "VALID" then
        for _, word in ipairs(words) do
            local expected = written(word, system, settings, true)
            if expected ~= word.text then
                local i = 1
                while i <= math.min(#expected, #word.text) and expected:sub(i, i) == word.text:sub(i, i) do
                    i = i + 1
                end
                return "INVALID col " .. (word.start + i - 1) .. ": expected " .. expected
            end
        end
        return "VALID"
    elseif command == "DIFF" then
        local output = {}
        for _, word in ipairs(words) do
            local a = written(word, args[1], settings)
            local b = written(word, args[2], settings)
            if a ~= b then
                output[#output + 1] = a .. ">" .. b
            end
        end
        local prefix = #output .. " of " .. #words
        return #output == 0 and prefix or prefix .. ": " .. table.concat(output, " ")
    elseif command == "SAME" then
        local left, right = {}, {}
        for _, word in ipairs(words) do
            local side = word.part == 1 and left or right
            side[#side + 1] = word
        end
        local exact = true
        for i = 1, math.min(#left, #right) do
            local a, b = left[i].ids, right[i].ids
            local _, a_long = long_flags(a)
            local _, b_long = long_flags(b)
            local a_loose, b_loose = {}, {}
            for j, id in ipairs(a) do
                if not a_long[j] then
                    a_loose[#a_loose + 1] = id
                end
            end
            for j, id in ipairs(b) do
                if not b_long[j] then
                    b_loose[#b_loose + 1] = id
                end
            end
            if not equal_ids(a_loose, b_loose) then
                return "DIFFERENT at word " .. i
            end
            exact = exact and equal_ids(a, b)
        end
        if #left ~= #right then
            return "DIFFERENT at word " .. (math.min(#left, #right) + 1)
        end
        return exact and "EXACT" or "LOOSE"
    elseif command == "MORAE" or command == "SYLLABLES" then
        local output, total = {}, 0
        for _, word in ipairs(words) do
            local parts = {}
            if command == "MORAE" then
                for i, id in ipairs(word.ids) do
                    parts[i] = spelling(system, id)
                end
            else
                local paired = long_flags(word.ids)
                local written_parts = write_parts(word.ids, word.columns, system, "KEEP")
                for i, id in ipairs(word.ids) do
                    if i > 1 and (not is_syllabic(id) or paired[i]) then
                        parts[#parts] = parts[#parts] .. written_parts[i]
                    else
                        parts[#parts + 1] = written_parts[i]
                    end
                end
            end
            total = total + #parts
            output[#output + 1] = table.concat(parts, ".")
        end
        return total .. ": " .. table.concat(output, " ")
    elseif command == "ROW" then
        local output = {}
        for _, word in ipairs(words) do
            for _, id in ipairs(word.ids) do
                if is_syllabic(id) then
                    output[#output + 1] = spelling(system, id) .. ": " .. row_of[id] .. " " .. dan_of[id]
                else
                    output[#output + 1] = id .. ": special"
                end
            end
        end
        return table.concat(output, ", ")
    elseif command == "STATS" then
        local counts, total = {}, 0
        for i = 1, 10 do
            counts[rows[i]] = 0
        end
        for _, name in ipairs(split_words("voiced semivoiced contracted N Q L")) do
            counts[name] = 0
        end
        for _, word in ipairs(words) do
            for _, id in ipairs(word.ids) do
                total = total + 1
                if is_syllabic(id) then
                    local row = row_of[id]
                    local base = base_row[row] or row
                    counts[base] = counts[base] + 1
                    if contains({"ga", "za", "da", "ba"}, row) then
                        counts.voiced = counts.voiced + 1
                    elseif row == "pa" then
                        counts.semivoiced = counts.semivoiced + 1
                    end
                    if #dan_of[id] == 2 then
                        counts.contracted = counts.contracted + 1
                    end
                else
                    local key = id == "-" and "L" or id
                    counts[key] = counts[key] + 1
                end
            end
        end
        local output = {"morae=" .. total}
        for i = 1, 10 do
            local row = rows[i]
            if counts[row] > 0 then
                output[#output + 1] = row .. "=" .. counts[row]
            end
        end
        for _, name in ipairs(split_words("voiced semivoiced contracted N Q L")) do
            output[#output + 1] = name .. "=" .. counts[name]
        end
        return table.concat(output, " ")
    elseif command == "SORT" or command == "INDEX" then
        for _, word in ipairs(words) do
            word.key = collation(word, settings.ORDER)
        end
        table.sort(words, function(a, b)
            for j = 1, 4 do
                local comparison = vector_compare(a.key[j], b.key[j])
                if comparison ~= 0 then
                    return comparison < 0
                end
            end
            return a.index < b.index
        end)
        local output = {}
        if command == "SORT" then
            for i, word in ipairs(words) do
                output[i] = word.text
            end
            return table.concat(output, " ")
        end
        local previous = ""
        for _, word in ipairs(words) do
            local base = elements(word.ids)[1][1]
            local heading = base
            if settings.ORDER == "GOJUON" and base ~= "N" then
                heading = row_of[base]
            end
            if heading == previous then
                output[#output] = output[#output] .. " " .. word.text
            else
                output[#output + 1] = heading .. ": " .. word.text
                previous = heading
            end
        end
        return table.concat(output, "; ")
    elseif command == "FIND" then
        local output = {}
        for _, word in ipairs(words) do
            if wildcard_matches(tokens, word.ids) then
                output[#output + 1] = word.text
            end
        end
        local prefix = #output .. " of " .. #words
        return #output == 0 and prefix or prefix .. ": " .. table.concat(output, " ")
    elseif command == "HAIKU" then
        local counts = {}
        for i = 1, count_character(text, "/") + 1 do
            counts[i] = 0
        end
        for _, word in ipairs(words) do
            counts[word.part] = counts[word.part] + #word.ids
        end
        local expected = #counts == 3 and {5, 7, 5} or {5, 7, 5, 7, 7}
        local verdict = equal_ids(counts, expected) and "OK" or "NG"
        local form = #counts == 3 and "haiku" or "tanka"
        return verdict .. " " .. form .. " " .. table.concat(counts, "-")
    elseif command == "KAIBUN" then
        local bases = {}
        for _, word in ipairs(words) do
            for _, item in ipairs(elements(word.ids)) do
                bases[#bases + 1] = item[1]
            end
        end
        local palindrome = true
        for i = 1, #bases // 2 do
            if bases[i] ~= bases[#bases - i + 1] then
                palindrome = false
            end
        end
        return (palindrome and "YES " or "NO ") .. table.concat(bases, ".")
    end
    local seen, previous = {}, ""
    for i, word in ipairs(words) do
        local items = elements(word.ids)
        local head, tail = items[1][1], items[#items][1]
        local prefix = "NG " .. i .. ": " .. word.text
        if i > 1 and head ~= previous then
            return prefix .. " must start with " .. spelling(system, previous)
        end
        local key = table.concat(word.ids, ".")
        if seen[key] then
            return prefix .. " is repeated"
        elseif tail == "N" then
            return prefix .. " ends with N"
        end
        seen[key] = true
        previous = tail
    end
    return "OK " .. #words
end

local count = tonumber(io.read("l"))
local settings = {LONG = "KEEP", CASE = "KEEP", ORDER = "GOJUON"}
for i = 1, count do
    local valid, output = pcall(execute, io.read("l"), settings)
    io.write(valid and output or "ERROR " .. output, "\n")
end
