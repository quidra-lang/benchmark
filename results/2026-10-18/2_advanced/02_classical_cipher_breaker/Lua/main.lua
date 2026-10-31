local scoring = require("scoring")
local substitution = require("substitution")
local transposition = require("transposition")
local playfair = require("playfair")
local analysis = require("analysis")

local commands = {
    "ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"
}
local ciphers = {
    caesar = true, affine = true, vigenere = true, autokey = true,
    railfence = true, columnar = true, playfair = true
}
local substitutions = {
    caesar = true, affine = true, vigenere = true, autokey = true
}
local multipliers = {1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25}
local outcomes = {}
local messages = {}
local result_lines, candidate_lines, analysis_lines = {}, {}, {}
local mono, bi = scoring.read("input/weights.txt")

for _, command in ipairs(commands) do
    outcomes[command] = {0, 0}
end

local function read_lines(path)
    local lines = {}
    for line in io.lines(path) do
        lines[#lines + 1] = line
    end
    return lines
end

local function load_messages(path)
    local name, body = nil, {}
    for _, line in ipairs(read_lines(path)) do
        if not name then
            if line ~= "" then
                name = line:sub(9)
                body = {}
            end
        elseif line == "END" then
            messages[name] = body
            name = nil
        else
            body[#body + 1] = line
        end
    end
end

load_messages("input/messages.txt")

local function raise(message)
    error(message, 0)
end

local function valid_name(value)
    return #value >= 1 and #value <= 16 and
        value:match("^[a-z0-9_]+$") ~= nil
end

local function digits(value, maximum)
    return #value >= 1 and #value <= maximum and
        value:match("^%d+$") ~= nil
end

local function body(name)
    return table.concat(messages[name], "\n")
end

local function letter_string(name)
    return scoring.letters(body(name))
end

local function normalize_key(cipher, original)
    if cipher == "caesar" then
        if not digits(original, 2) or tonumber(original) > 25 then
            raise("bad key " .. original)
        end
        return tostring(tonumber(original))
    elseif cipher == "affine" then
        local a, b = original:match("^(%d+),(%d+)$")
        local allowed = false
        if a and b and digits(a, 2) and digits(b, 2) then
            for _, multiplier in ipairs(multipliers) do
                if tonumber(a) == multiplier then
                    allowed = true
                    break
                end
            end
        end
        if not allowed or tonumber(b) > 25 then
            raise("bad key " .. original)
        end
        return tostring(tonumber(a)) .. "," .. tostring(tonumber(b))
    elseif cipher == "railfence" then
        if not digits(original, 2) or tonumber(original) < 2
            or tonumber(original) > 20 then
            raise("bad key " .. original)
        end
        return tostring(tonumber(original))
    elseif cipher == "columnar" then
        if #original < 2 or #original > 9 or not original:match("^[A-Za-z0-9]+$") then
            raise("bad key " .. original)
        end
    else
        local maximum = cipher == "playfair" and 25 or 20
        if #original == 0 or #original > maximum
            or not original:match("^[A-Za-z]+$") then
            raise("bad key " .. original)
        end
    end
    local key = original:upper()
    if cipher == "playfair" then
        key = key:gsub("J", "I")
    end
    return key
end

local function option_rules(command, cipher)
    local result = {}
    if command == "ANALYZE" then
        result.MAXLEN = {2, 20, 10}
    end
    if command ~= "BREAK" then
        return result
    end
    result.TOP = {1, 20, 5}
    if cipher == "vigenere" then
        result.MAXLEN = {2, 20, 10}
        result.IOC = {1, 100000, 6000}
        result.KASISKI = {1, 100, 60}
        result.REFINE = {0, 10, 5}
    elseif cipher == "autokey" then
        result.MAXLEN = {1, 20, 8}
    elseif cipher == "railfence" then
        result.MAXRAILS = {2, 20, 10}
    elseif cipher == "columnar" then
        result.MAXLEN = {2, 6, 6}
    end
    return result
end

local function parse_options(command, cipher, words)
    local rules = option_rules(command, cipher)
    local values, seen = {}, {}
    for name, bounds in pairs(rules) do
        values[name] = bounds[3]
    end
    for _, word in ipairs(words) do
        local separator = word:find("=", 1, true)
        local name = separator and word:sub(1, separator - 1) or ""
        local value = separator and word:sub(separator + 1) or ""
        if not separator or seen[name] then
            raise("bad option " .. word)
        end
        seen[name] = true
        if name == "KEYS" and (command == "IDENTIFY"
            or command == "BREAK" and cipher == "playfair") then
            if not valid_name(value) then
                raise("bad option " .. word)
            end
            values.KEYS = value
        else
            local bounds = rules[name]
            if not bounds or not digits(value, 6)
                or tonumber(value) < bounds[1] or tonumber(value) > bounds[2] then
                raise("bad option " .. word)
            end
            values[name] = tonumber(value)
        end
    end
    if command == "BREAK" and cipher == "playfair" and not values.KEYS then
        raise("missing option KEYS")
    end
    return values
end

local function decrypt(text, cipher, key)
    if substitutions[cipher] then
        return scoring.letters(substitution.apply(text, cipher, key, false))
    elseif cipher == "railfence" then
        return transposition.rail_fence(text, tonumber(key), false)
    elseif cipher == "columnar" then
        return transposition.columnar(text, key, false)
    end
    return playfair.apply(text, key, false)
end

local function transform(text, cipher, key, encrypt)
    if substitutions[cipher] then
        return substitution.apply(text, cipher, key, encrypt)
    end
    text = scoring.letters(text)
    if cipher == "railfence" then
        return transposition.rail_fence(text, tonumber(key), encrypt)
    elseif cipher == "columnar" then
        return transposition.columnar(text, key, encrypt)
    end
    return playfair.apply(text, key, encrypt)
end

local function key_list(name)
    local keys, seen = {}, {}
    for word in body(name):gmatch("[A-Za-z]+") do
        local key = word:upper():gsub("J", "I")
        if not seen[key] then
            keys[#keys + 1] = key
            seen[key] = true
        end
    end
    return keys
end

local function permutations(length)
    local digits, result = {}, {}
    for i = 1, length do
        digits[i] = tostring(i)
    end
    local function visit(index)
        if index > length then
            result[#result + 1] = table.concat(digits)
            return
        end
        for i = index, length do
            digits[index], digits[i] = digits[i], digits[index]
            visit(index + 1)
            digits[index], digits[i] = digits[i], digits[index]
        end
    end
    visit(1)
    table.sort(result)
    return result
end

local function column_key(text, length, autokey)
    local key = {}
    for column = 0, length - 1 do
        local segment = analysis.column(text, length, column)
        local best, best_score = 0, -math.huge
        for guess = 0, 25 do
            local score
            if autokey then
                local previous = guess
                score = 0
                for i = 1, #segment do
                    previous = (scoring.value(segment:sub(i, i)) - previous) % 26
                    score = score + mono[previous + 1]
                end
            else
                local plain = substitution.apply(segment, "caesar", tostring(guess), false)
                score = scoring.monogram(plain, mono)
            end
            if score > best_score then
                best, best_score = guess, score
            end
        end
        key[#key + 1] = scoring.upper(best)
    end
    return table.concat(key)
end

local function candidate_keys(cipher, text, options, keys)
    local result = {}
    if cipher == "caesar" then
        for key = 0, 25 do
            result[#result + 1] = tostring(key)
        end
    elseif cipher == "affine" then
        for _, a in ipairs(multipliers) do
            for b = 0, 25 do
                result[#result + 1] = a .. "," .. b
            end
        end
    elseif cipher == "railfence" then
        for rails = 2, options.MAXRAILS do
            result[#result + 1] = tostring(rails)
        end
    elseif cipher == "columnar" then
        for length = 2, options.MAXLEN do
            for _, key in ipairs(permutations(length)) do
                result[#result + 1] = key
            end
        end
    elseif cipher == "playfair" then
        for _, key in ipairs(keys) do
            result[#result + 1] = key
        end
    else
        for length = 1, options.MAXLEN do
            result[#result + 1] = column_key(text, length, cipher == "autokey")
        end
    end
    return result
end

local function score(cipher, plaintext)
    if cipher == "caesar" or cipher == "affine" then
        return scoring.monogram(plaintext, mono)
    end
    return scoring.bigram(plaintext, bi)
end

local function break_cipher(cipher, text, options, keys)
    local candidates = {}
    for _, key in ipairs(candidate_keys(cipher, text, options, keys)) do
        local plaintext = decrypt(text, cipher, key)
        candidates[#candidates + 1] = {
            key = key, plaintext = plaintext, score = score(cipher, plaintext),
            order = #candidates + 1
        }
    end
    local ranked = {}
    for i, candidate in ipairs(candidates) do
        ranked[i] = candidate
    end
    table.sort(ranked, function(a, b)
        return a.score == b.score and a.order < b.order or a.score > b.score
    end)
    if cipher ~= "vigenere" then
        return {ranked = ranked, choice = ranked[1]}
    end

    local kasiski = analysis.kasiski(text)
    local averages = {}
    for length = 1, options.MAXLEN do
        averages[length] = analysis.average_ioc(text, length)
    end
    local kasiski_length = 0
    for length = 2, options.MAXLEN do
        if #kasiski.gaps > 0 and
            100 * analysis.kasiski_count(kasiski, length) >= options.KASISKI * #kasiski.gaps then
            kasiski_length = length
        end
    end
    local chosen, method
    if kasiski_length > 0 and averages[kasiski_length] >= options.IOC then
        chosen, method = kasiski_length, "kasiski"
    else
        for length = 1, options.MAXLEN do
            if averages[length] >= options.IOC then
                chosen = length
                break
            end
        end
        if chosen then
            method = "ioc"
        else
            chosen, method = 1, "maxioc"
            for length = 2, options.MAXLEN do
                if averages[length] > averages[chosen] then
                    chosen = length
                end
            end
        end
    end
    local key = candidates[chosen].key
    local reference = score(cipher, decrypt(text, cipher, key))
    local passes, changes = 0, 0
    for attempt = 1, options.REFINE do
        passes = passes + 1
        local changes_this_pass = 0
        for position = 1, #key do
            local winner, high = key:sub(position, position), reference
            for value = 0, 25 do
                local trial = key:sub(1, position - 1) ..
                    scoring.upper(value) .. key:sub(position + 1)
                local trial_score = score(cipher, decrypt(text, cipher, trial))
                if trial_score > high then
                    winner, high = scoring.upper(value), trial_score
                end
            end
            if high > reference then
                key = key:sub(1, position - 1) .. winner .. key:sub(position + 1)
                reference = high
                changes = changes + 1
                changes_this_pass = changes_this_pass + 1
            end
        end
        if changes_this_pass == 0 then
            break
        end
    end
    return {
        ranked = ranked,
        choice = {key = key, plaintext = decrypt(text, cipher, key), score = reference},
        length = chosen, method = method, passes = passes, changes = changes,
        kasiski = kasiski
    }
end

local function candidate_report(job, cipher, source, broken, top)
    local rank = broken.ranked
    local margin = #rank > 1 and rank[1].score - rank[2].score or 0
    candidate_lines[#candidate_lines + 1] = string.format(
        "JOB %d BREAK %s source=%s tried=%d margin=%d",
        job, cipher, source, #rank, margin)
    for i = 1, math.min(top, #rank) do
        local candidate = rank[i]
        candidate_lines[#candidate_lines + 1] = string.format(
            "%d %s %d %s", i, candidate.key,
            candidate.score, candidate.plaintext:sub(1, 40))
    end
end

local function append_all(target, items)
    for _, item in ipairs(items) do
        target[#target + 1] = item
    end
end

local function break_analysis(job, cipher, source, text, options, broken)
    if cipher == "vigenere" then
        analysis_lines[#analysis_lines + 1] =
            string.format("JOB %d BREAK vigenere source=%s", job, source)
        analysis_lines[#analysis_lines + 1] = "letters=" .. #text
        append_all(analysis_lines, analysis.period_table(text, options.MAXLEN, broken.kasiski))
        append_all(analysis_lines, analysis.kasiski_table(broken.kasiski))
        analysis_lines[#analysis_lines + 1] =
            string.format("decision length=%d method=%s", broken.length, broken.method)
        analysis_lines[#analysis_lines + 1] =
            string.format("refine passes=%d changes=%d key=%s",
                broken.passes, broken.changes, broken.choice.key)
    elseif cipher == "playfair" then
        local normalized = text:gsub("J", "I")
        local distinct, unique = 0, {}
        for i = 1, #normalized, 2 do
            local pair = normalized:sub(i, i + 1)
            if not unique[pair] then
                unique[pair], distinct = true, distinct + 1
            end
        end
        local board = playfair.square(broken.choice.key)
        local rows = {}
        for i = 0, 4 do
            rows[#rows + 1] = board:sub(i * 5 + 1, i * 5 + 5)
        end
        analysis_lines[#analysis_lines + 1] =
            string.format("JOB %d BREAK playfair source=%s", job, source)
        analysis_lines[#analysis_lines + 1] = "letters=" .. #normalized
        analysis_lines[#analysis_lines + 1] =
            string.format("digraphs pairs=%d distinct=%d", #normalized // 2, distinct)
        analysis_lines[#analysis_lines + 1] =
            "top " .. analysis.top_pairs(normalized, true)
        analysis_lines[#analysis_lines + 1] =
            "square " .. table.concat(rows, " ")
    end
end

local function split_lines(text)
    local result, first = {}, 1
    for i = 1, #text do
        if text:sub(i, i) == "\n" then
            result[#result + 1] = text:sub(first, i - 1)
            first = i + 1
        end
    end
    result[#result + 1] = text:sub(first)
    return result
end

local function output_text(source, cipher, key, encrypt)
    local transformed = transform(source, cipher, key, encrypt)
    if substitutions[cipher] then
        return split_lines(transformed)
    end
    return scoring.groups(transformed)
end

local function save(target, lines)
    if target then
        messages[target] = lines
    end
end

local function cipher_job(job, command, cipher, key, source, target)
    local text = letter_string(source)
    if #text == 0 then
        raise("no letters")
    end
    if command == "DECRYPT" and cipher == "playfair" and not playfair.valid(text) then
        raise("bad playfair text")
    end
    local lines = output_text(body(source), cipher, key, command == "ENCRYPT")
    local count = 0
    for _, line in ipairs(lines) do
        count = count + #scoring.letters(line)
    end
    local heading = string.format("JOB %d %s %s key=%s source=%s letters=%d lines=%d",
        job, command, cipher, key, source, count, #lines)
    if target then
        heading = heading .. " as=" .. target
    end
    result_lines[#result_lines + 1] = heading
    append_all(result_lines, lines)
    save(target, lines)
end

local function break_job(job, cipher, source, target, options)
    local text = letter_string(source)
    if #text < 40 then
        raise("text too short")
    end
    if cipher == "playfair" and not playfair.valid(text) then
        raise("bad playfair text")
    end
    local keys = cipher == "playfair" and key_list(options.KEYS) or {}
    if cipher == "playfair" and #keys == 0 then
        raise("empty key list")
    end
    local outcome = break_cipher(cipher, text, options, keys)
    local winner = outcome.choice
    local lines = output_text(body(source), cipher, winner.key, false)
    local heading = string.format("JOB %d BREAK %s source=%s key=%s score=%d lines=%d",
        job, cipher, source, winner.key, winner.score, #lines)
    if target then
        heading = heading .. " as=" .. target
    end
    result_lines[#result_lines + 1] = heading
    append_all(result_lines, lines)
    candidate_report(job, cipher, source, outcome, options.TOP)
    break_analysis(job, cipher, source, text, options, outcome)
    save(target, lines)
end

local function analyze_job(job, source, options)
    local text = letter_string(source)
    if #text < 40 then
        raise("text too short")
    end
    result_lines[#result_lines + 1] = string.format(
        "JOB %d ANALYZE source=%s letters=%d", job, source, #text)
    append_all(analysis_lines,
        analysis.report(job, source, text, mono, bi, options.MAXLEN))
end

local function compare_job(job, first_name, second_name)
    local first, second = letter_string(first_name), letter_string(second_name)
    local length = math.min(#first, #second)
    local position, mismatches = length + 1, 0
    for i = 1, length do
        if first:sub(i, i) ~= second:sub(i, i) then
            if mismatches == 0 then
                position = i
            end
            mismatches = mismatches + 1
        end
    end
    if first == second then
        result_lines[#result_lines + 1] =
            string.format("JOB %d COMPARE %s %s equal letters=%d",
                job, first_name, second_name, #first)
    else
        result_lines[#result_lines + 1] =
            string.format("JOB %d COMPARE %s %s differ letters=%d,%d first=%d mismatches=%d",
                job, first_name, second_name, #first, #second, position, mismatches)
    end
end

local function identify_job(job, source, options)
    local text = letter_string(source)
    if #text < 40 then
        raise("text too short")
    end
    local coincidence = analysis.ioc(text)
    local mean = scoring.monogram(text, mono) // #text
    local distinct = 0
    for _, count in ipairs(analysis.frequency(text)) do
        if count > 0 then
            distinct = distinct + 1
        end
    end
    local shape = not text:find("J", 1, true) and playfair.valid(text)
    local family
    if shape then
        family = "playfair"
    elseif coincidence >= 5500 and mean >= 44 then
        family = "transposition"
    elseif coincidence >= 5500 then
        family = "monoalphabetic"
    else
        family = "polyalphabetic"
    end
    local keys
    if family == "playfair" and options.KEYS then
        keys = key_list(options.KEYS)
        if #keys == 0 then
            raise("empty key list")
        end
    end
    local to_try = {}
    if family == "transposition" then
        to_try = {"railfence", "columnar"}
    elseif family == "monoalphabetic" then
        to_try = {"affine"}
    elseif family == "polyalphabetic" then
        to_try = {"vigenere", "autokey"}
    elseif keys then
        to_try = {"playfair"}
    end
    local trials, best = {}, nil
    for _, cipher in ipairs(to_try) do
        local raw = cipher == "playfair" and {"KEYS=" .. options.KEYS} or {}
        local default_options = parse_options("BREAK", cipher, raw)
        local winner = break_cipher(cipher, text, default_options, keys).choice
        local trial = {cipher = cipher, choice = winner}
        trials[#trials + 1] = trial
        if not best or trial.choice.score > best.choice.score then
            best = trial
        end
    end
    local heading = string.format("JOB %d IDENTIFY source=%s family=%s",
        job, source, family)
    local reported = nil
    if best then
        local key
        reported, key = best.cipher, best.choice.key
        if reported == "affine" and key:match("^(%d+),") == "1" then
            reported, key = "caesar", key:match(",(%d+)$")
        end
        local lines = output_text(body(source), reported, key, false)
        heading = heading .. string.format(" cipher=%s key=%s score=%d lines=%d",
            reported, key, best.choice.score, #lines)
        result_lines[#result_lines + 1] = heading
        append_all(result_lines, lines)
    else
        result_lines[#result_lines + 1] = heading
    end
    analysis_lines[#analysis_lines + 1] =
        string.format("JOB %d IDENTIFY source=%s", job, source)
    analysis_lines[#analysis_lines + 1] =
        string.format("letters=%d ioc=%d mono_avg=%d distinct=%d shape=%s",
            #text, coincidence, mean, distinct, shape and "yes" or "no")
    analysis_lines[#analysis_lines + 1] = "family=" .. family
    for _, trial in ipairs(trials) do
        analysis_lines[#analysis_lines + 1] =
            string.format("try %s key=%s score=%d",
                trial.cipher, trial.choice.key, trial.choice.score)
    end
    if reported then
        analysis_lines[#analysis_lines + 1] = "choice " .. reported
    end
end

local function check_references(words, command, options)
    local source
    if command == "ENCRYPT" or command == "DECRYPT" then
        source = words[4]
    elseif command == "BREAK" then
        source = words[3]
    else
        source = words[2]
    end
    if not messages[source] then
        raise("unknown message " .. source)
    end
    if options.KEYS and not messages[options.KEYS] then
        raise("unknown message " .. options.KEYS)
    end
    if command == "COMPARE" and not messages[words[3]] then
        raise("unknown message " .. words[3])
    end
end

local function execute(job, line)
    local words = {}
    for word in line:gmatch("[^ ]+") do
        words[#words + 1] = word
    end
    local command = words[1]
    if not outcomes[command] then
        raise("unknown command")
    end
    local target
    if (command == "ENCRYPT" or command == "DECRYPT" or command == "BREAK")
        and #words >= 5 and words[#words - 1] == "AS" then
        target = words[#words]
        words[#words] = nil
        words[#words] = nil
        if not valid_name(target) then
            raise("bad syntax")
        end
    end
    local valid
    if command == "ENCRYPT" or command == "DECRYPT" then
        valid = #words == 4
    elseif command == "BREAK" then
        valid = #words >= 3
    elseif command == "ANALYZE" or command == "IDENTIFY" then
        valid = #words == 2 or #words == 3
    else
        valid = #words == 3
    end
    if not valid then
        raise("bad syntax")
    end
    local cipher = ""
    if command == "ENCRYPT" or command == "DECRYPT" or command == "BREAK" then
        cipher = words[2]
        if not ciphers[cipher] then
            raise("unknown cipher " .. cipher)
        end
    end
    local key
    if command == "ENCRYPT" or command == "DECRYPT" then
        key = normalize_key(cipher, words[3])
    end
    local option_words = {}
    if command == "BREAK" then
        for i = 4, #words do
            option_words[#option_words + 1] = words[i]
        end
    elseif command == "ANALYZE" or command == "IDENTIFY" then
        for i = 3, #words do
            option_words[#option_words + 1] = words[i]
        end
    end
    local options = parse_options(command, cipher, option_words)
    check_references(words, command, options)
    if target and messages[target] then
        raise("duplicate message " .. target)
    end
    if command == "ENCRYPT" or command == "DECRYPT" then
        cipher_job(job, command, cipher, key, words[4], target)
    elseif command == "BREAK" then
        break_job(job, cipher, words[3], target, options)
    elseif command == "ANALYZE" then
        analyze_job(job, words[2], options)
    elseif command == "COMPARE" then
        compare_job(job, words[2], words[3])
    elseif command == "IDENTIFY" then
        identify_job(job, words[2], options)
    end
end

local function run_jobs(path)
    local jobs, ok, errors = 0, 0, 0
    for _, line in ipairs(read_lines(path)) do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            jobs = jobs + 1
            local command = line:match("^[^ ]+")
            local success, message = pcall(execute, jobs, line)
            if success then
                ok = ok + 1
                if outcomes[command] then
                    outcomes[command][1] = outcomes[command][1] + 1
                end
            else
                errors = errors + 1
                if outcomes[command] then
                    outcomes[command][2] = outcomes[command][2] + 1
                end
                result_lines[#result_lines + 1] =
                    string.format("JOB %d ERROR %s", jobs, message)
            end
        end
    end
    for _, command in ipairs(commands) do
        result_lines[#result_lines + 1] =
            string.format("TOTAL %s ok=%d errors=%d",
                command, outcomes[command][1], outcomes[command][2])
    end
    local count = 0
    for _ in pairs(messages) do
        count = count + 1
    end
    result_lines[#result_lines + 1] =
        string.format("SUMMARY jobs=%d ok=%d errors=%d messages=%d",
            jobs, ok, errors, count)
end

local function write_file(path, lines)
    local file = assert(io.open(path, "wb"))
    if #lines > 0 then
        file:write(table.concat(lines, "\n"), "\n")
    end
    file:close()
end

run_jobs("input/jobs.txt")
write_file("output/results.txt", result_lines)
write_file("output/candidates.txt", candidate_lines)
write_file("output/analysis.txt", analysis_lines)
