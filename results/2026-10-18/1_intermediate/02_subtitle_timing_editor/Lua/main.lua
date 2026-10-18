local function words(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do
        result[#result + 1] = word
    end
    return result
end

local schemas = {
    LIST = "",
    VALIDATE = "",
    SEARCH = "string",
    AT = "time",
    GAPS = "0:60000",
    STATS = "",
    PRINT = "",
    TOVTT = "",
    TOASS = "",
    FRAMES = "fps",
    SHIFT = "signed",
    SHIFTFROM = "pos signed",
    SCALE = "1:100000 1:100000",
    SYNC = "pos time pos time",
    SNAP = "fps",
    FIXOVERLAP = "0:60000",
    EXTEND = "1:60000",
    TIME = "pos time time",
    SORT = "",
    RENUMBER = "",
    MERGE = "0:60000",
    SPLIT = "10:80",
    INSERT = "pos time time text",
    DELETE = "delete",
    TEXT = "pos text",
    BALANCE = "",
    STRIP = "",
    CLEANHI = "",
    REPLACE = "replace",
    UNDO = "",
}
local modifying = {}
for _, command in ipairs(words("SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE")) do
    modifying[command] = true
end
local format_tags = {
    ["<i>"] = "{\\i1}", ["</i>"] = "{\\i0}", ["<b>"] = "{\\b1}",
    ["</b>"] = "{\\b0}", ["<u>"] = "{\\u1}", ["</u>"] = "{\\u0}"
}

local function fail(message)
    error(message, 0)
end

local function round_ratio(n, d)
    return (2 * n + d) // (2 * d)
end

local function split_literal(text, separator)
    local result = {}
    local position = 1
    while true do
        local ending = text:find(separator, position, true)
        if not ending then
            result[#result + 1] = text:sub(position)
            return result
        end
        result[#result + 1] = text:sub(position, ending - 1)
        position = ending + #separator
    end
end

local function copy_cues(cues)
    local copy = {}
    for i, cue in ipairs(cues) do
        local lines = {}
        for j, line in ipairs(cue.lines) do
            lines[j] = line
        end
        copy[i] = {index = cue.index, start = cue.start, stop = cue.stop, lines = lines}
    end
    return copy
end

local function char_count(cue)
    local total = 0
    for _, line in ipairs(cue.lines) do
        total = total + #line
    end
    return total
end

local function dialogue(cue)
    for _, line in ipairs(cue.lines) do
        if line:sub(1, 2) == "- " then
            return true
        end
    end
    return false
end

local function two_decimal(value)
    return string.format("%d.%02d", value // 100, value % 100)
end

local function trim_spaces(text)
    return text:match("^ *(.-) *$")
end

local function time_value(text)
    local h, m, s, ms = text:match("^(%d%d):(%d%d):(%d%d),(%d%d%d)$")
    if not h or tonumber(m) > 59 or tonumber(s) > 59 then
        fail("bad arguments")
    end
    return tonumber(h) * 3600000 + tonumber(m) * 60000 + tonumber(s) * 1000 + tonumber(ms)
end

local function time_text(t, kind)
    if kind == "ASS" then
        local c = (t + 5) // 10
        return string.format("%d:%02d:%02d.%02d", c // 360000, (c // 6000) % 60, (c // 100) % 60, c % 100)
    end
    return string.format("%02d:%02d:%02d%s%03d", t // 3600000, (t // 60000) % 60, (t // 1000) % 60,
        kind == "VTT" and "." or ",", t % 1000)
end

local function unsigned_arg(text, low, high)
    if not text:match("^%d+$") or #text > 9 then
        fail("bad arguments")
    end
    local value = tonumber(text)
    if value < (low or 0) or value > (high or 999999999) then
        fail("bad arguments")
    end
    return value
end

local function typed_arg(text, kind)
    if kind == "string" then
        return text
    elseif kind == "time" then
        return time_value(text)
    elseif kind == "pos" then
        return unsigned_arg(text, 1)
    elseif kind == "signed" then
        local digits = text:match("^%-?(%d+)$")
        if not digits or #digits > 9 then
            fail("bad arguments")
        end
        return tonumber(text)
    elseif kind == "fps" then
        local parts = split_literal(text, "/")
        if #parts > 2 then
            fail("bad arguments")
        end
        return {unsigned_arg(parts[1], 1, 100000), #parts == 1 and 1 or unsigned_arg(parts[2], 1, 100000)}
    elseif kind == "text" or kind == "replace" then
        local parts = split_literal(text, "|")
        for _, part in ipairs(parts) do
            if part == "" then
                fail("bad arguments")
            end
        end
        if kind == "replace" and #parts ~= 2 then
            fail("bad arguments")
        end
        return parts
    end
    local low, high = kind:match("^(%d+):(%d+)$")
    return unsigned_arg(text, tonumber(low), tonumber(high))
end

local function arguments(line, cues)
    local command = line:match("^[^ ]+")
    if schemas[command] == nil then
        fail("unknown command")
    end
    local args, kinds = {}, {}
    if command == "DELETE" then
        local parts = words(line)
        if #parts < 2 or #parts > 3 then
            fail("bad arguments")
        end
        for i = 2, #parts do
            args[#args + 1] = unsigned_arg(parts[i], 1)
            kinds[#kinds + 1] = "pos"
        end
        if #args == 2 and args[2] < args[1] then
            fail("bad arguments")
        end
    else
        kinds = words(schemas[command])
        local position = #command + 2
        local raw = {}
        for i = 1, #kinds do
            if position > #line then
                fail("bad arguments")
            end
            if i == #kinds and (kinds[i] == "string" or kinds[i] == "text" or kinds[i] == "replace") then
                raw[i] = line:sub(position)
                position = #line + 2
            else
                local ending = line:find(" ", position, true)
                if ending then
                    raw[i] = line:sub(position, ending - 1)
                    position = ending + 1
                else
                    raw[i] = line:sub(position)
                    position = #line + 2
                end
            end
        end
        if position <= #line or (#kinds == 0 and #line ~= #command) then
            fail("bad arguments")
        end
        for i, kind in ipairs(kinds) do
            args[i] = typed_arg(raw[i], kind)
        end
    end
    for i, kind in ipairs(kinds) do
        local maximum = #cues + (command == "INSERT" and 1 or 0)
        if kind == "pos" and args[i] > maximum then
            fail("no cue " .. args[i])
        end
    end
    if command == "SYNC" and cues[args[1]].start == cues[args[3]].start then
        fail("sync points coincide")
    end
    return command, args
end

local function wrap_lines(lines, width)
    local output = {}
    for _, word in ipairs(words(table.concat(lines, " "))) do
        if #output > 0 and #output[#output] + 1 + #word <= width then
            output[#output] = output[#output] .. " " .. word
        else
            output[#output + 1] = word
        end
    end
    return output
end

local function markup(line)
    local items = {}
    local p = 1
    while p <= #line do
        local tag
        for text in pairs(format_tags) do
            if line:sub(p, p + #text - 1) == text then
                tag = text
                break
            end
        end
        local rest = line:sub(p)
        local ending = line:find(">", p + 5, true)
        if tag then
            items[#items + 1] = {"format", tag, 0}
            p = p + #tag
        elseif rest:sub(1, 7) == "</font>" then
            items[#items + 1] = {"font", "</font>", 0}
            p = p + 7
        elseif rest:sub(1, 5) == "<font" and (line:sub(p + 5, p + 5) == " " or line:sub(p + 5, p + 5) == ">") and ending then
            items[#items + 1] = {"font", line:sub(p, ending), 0}
            p = ending + 1
        elseif line:sub(p, p + 3) == "{\\an" and line:sub(p + 4, p + 4):match("^[1-9]$") and line:sub(p + 5, p + 5) == "}" then
            items[#items + 1] = {"position", line:sub(p, p + 5), tonumber(line:sub(p + 4, p + 4))}
            p = p + 6
        else
            items[#items + 1] = {"ordinary", line:sub(p, p), 0}
            p = p + 1
        end
    end
    return items
end

local function converted_line(line, mode)
    local output, tags, position = {}, 0, 0
    local escapes = {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;"}
    for _, item in ipairs(markup(line)) do
        local kind, text, digit = table.unpack(item)
        if kind ~= "ordinary" then
            tags = tags + 1
        end
        if kind == "position" and position == 0 then
            position = digit
        end
        if kind == "ordinary" then
            output[#output + 1] = mode == "VTT" and (escapes[text] or text) or text
        elseif mode == "VTT" and kind == "format" then
            output[#output + 1] = text
        elseif mode == "ASS" and kind == "format" then
            output[#output + 1] = format_tags[text]
        elseif mode == "ASS" and kind == "position" then
            output[#output + 1] = text
        end
    end
    local result = table.concat(output)
    if mode ~= "ASS" then
        result = trim_spaces(result)
    end
    return result, tags, position
end

local function clean_hi(line)
    local output, segments, p = {}, 0, 1
    while p <= #line do
        local c = line:sub(p, p)
        local closing = ({["["] = "]", ["("] = ")"})[c]
        local ending = closing and line:find(closing, p + 1, true)
        if ending then
            segments = segments + 1
            p = ending + 1
        else
            output[#output + 1] = c
            p = p + 1
        end
    end
    local function normalize(text)
        return trim_spaces((text:gsub(" +", " ")))
    end
    local result = normalize(table.concat(output))
    local prefix = result:sub(1, 2) == "- " and "- " or ""
    local body = prefix == "" and result or result:sub(3)
    local label = body:match("^[A-Z][A-Z0-9 ]*:")
    if label then
        result = normalize(prefix .. body:sub(#label + 1))
    end
    return result, segments, label and 1 or 0
end

local function list_line(cue, p)
    return p .. " " .. cue.index .. " " .. time_text(cue.start) .. " " .. time_text(cue.stop) .. " " .. table.concat(cue.lines, "|")
end

local function inspect(command, args, cues)
    local output, n = {}, #cues
    if command == "LIST" or command == "AT" then
        for p, cue in ipairs(cues) do
            if command == "LIST" or (cue.start <= args[1] and args[1] < cue.stop) then
                output[#output + 1] = list_line(cue, p)
            end
        end
        if command == "AT" then
            output[#output + 1] = "AT active=" .. #output
        end
    elseif command == "VALIDATE" then
        for p, cue in ipairs(cues) do
            local d = cue.stop - cue.start
            if cue.index ~= p then
                output[#output + 1] = "cue " .. p .. ": index " .. cue.index .. " (expected " .. p .. ")"
            end
            if d <= 0 then
                output[#output + 1] = "cue " .. p .. ": end not after start"
            end
            if p > 1 and cue.start < cues[p - 1].stop then
                output[#output + 1] = "cue " .. p .. ": overlaps previous by " .. (cues[p - 1].stop - cue.start) .. " ms"
            end
            if d >= 1 and d < 700 then
                output[#output + 1] = "cue " .. p .. ": too short (" .. d .. " ms)"
            elseif d > 7000 then
                output[#output + 1] = "cue " .. p .. ": too long (" .. d .. " ms)"
            end
            for j, line in ipairs(cue.lines) do
                if #line > 42 then
                    output[#output + 1] = "cue " .. p .. ": line " .. j .. " too long (" .. #line .. " chars)"
                end
            end
            if #cue.lines >= 3 then
                output[#output + 1] = "cue " .. p .. ": too many lines (" .. #cue.lines .. ")"
            end
            if d >= 1 and char_count(cue) * 1000 > 21 * d then
                output[#output + 1] = "cue " .. p .. ": too fast (" .. two_decimal((char_count(cue) * 100000) // d) .. " cps)"
            end
        end
        output[#output + 1] = "VALIDATE problems=" .. #output
    elseif command == "SEARCH" then
        for p, cue in ipairs(cues) do
            for _, line in ipairs(cue.lines) do
                if line:find(args[1], 1, true) then
                    output[#output + 1] = p .. " " .. time_text(cue.start) .. " " .. line
                    break
                end
            end
        end
        output[#output + 1] = "SEARCH found=" .. #output
    elseif command == "GAPS" then
        for p = 1, n - 1 do
            local gap = cues[p + 1].start - cues[p].stop
            if gap < args[1] then
                output[#output + 1] = p .. " " .. (p + 1) .. " " .. gap
            end
        end
        output[#output + 1] = "GAPS count=" .. #output
    elseif command == "STATS" then
        output[1] = "STATS cues=" .. n
        if n == 0 then
            return output
        end
        local durations, total, characters, longest = {}, 0, 0, 1
        for i, cue in ipairs(cues) do
            durations[i] = math.max(0, cue.stop - cue.start)
            total = total + durations[i]
            if durations[i] > 0 then
                characters = characters + char_count(cue)
            end
            if durations[i] > durations[longest] then
                longest = i
            end
        end
        output[#output + 1] = "duration total=" .. time_text(total) .. " mean=" .. time_text(total // n)
        output[#output + 1] = total == 0 and "speed -" or "speed " .. two_decimal((characters * 100000) // total)
        output[#output + 1] = "longest cue=" .. longest .. " duration=" .. time_text(durations[longest])
        if n == 1 then
            output[#output + 1] = "gap none"
        else
            local selected, best = 1, cues[2].start - cues[1].stop
            for p = 2, n - 1 do
                local gap = cues[p + 1].start - cues[p].stop
                if gap > best then
                    selected, best = p, gap
                end
            end
            output[#output + 1] = "gap cue=" .. selected .. " ms=" .. best
        end
    elseif command == "PRINT" then
        for _, cue in ipairs(cues) do
            output[#output + 1] = tostring(cue.index)
            output[#output + 1] = time_text(cue.start) .. " --> " .. time_text(cue.stop)
            for _, line in ipairs(cue.lines) do
                output[#output + 1] = line
            end
            output[#output + 1] = ""
        end
    elseif command == "TOVTT" then
        output = {"WEBVTT", ""}
        for _, cue in ipairs(cues) do
            local lines, position = {}, 0
            for _, line in ipairs(cue.lines) do
                local text, tags, digit = converted_line(line, "VTT")
                if position == 0 and digit > 0 then
                    position = digit
                end
                if text ~= "" then
                    lines[#lines + 1] = text
                end
            end
            if #lines > 0 then
                local settings = ""
                if position >= 7 then
                    settings = " line:0"
                elseif position >= 4 then
                    settings = " line:50%"
                end
                if position == 1 or position == 4 or position == 7 then
                    settings = settings .. " align:start"
                elseif position == 3 or position == 6 or position == 9 then
                    settings = settings .. " align:end"
                end
                output[#output + 1] = tostring(cue.index)
                output[#output + 1] = time_text(cue.start, "VTT") .. " --> " .. time_text(cue.stop, "VTT") .. settings
                for _, line in ipairs(lines) do
                    output[#output + 1] = line
                end
                output[#output + 1] = ""
            end
        end
    elseif command == "TOASS" then
        output = {"[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"}
        for _, cue in ipairs(cues) do
            local lines = {}
            for j, line in ipairs(cue.lines) do
                lines[j] = converted_line(line, "ASS")
            end
            output[#output + 1] = "Dialogue: 0," .. time_text(cue.start, "ASS") .. "," .. time_text(cue.stop, "ASS") .. ",Default,,0,0,0,," .. table.concat(lines, "\\N")
        end
    elseif command == "FRAMES" then
        local a, b = table.unpack(args[1])
        for p, cue in ipairs(cues) do
            output[#output + 1] = p .. " " .. ((cue.start * a) // (1000 * b)) .. " " .. ((cue.stop * a) // (1000 * b))
        end
    end
    return output
end

local function modify(command, args, cues)
    local output, n = {}, #cues
    if command == "SHIFT" or command == "SHIFTFROM" or command == "SCALE" or command == "SYNC" or command == "SNAP" then
        local first = command == "SHIFTFROM" and args[1] or 1
        local clamped, changed = 0, 0
        local transform
        if command == "SYNC" then
            local p1, t1, p2, t2 = table.unpack(args)
            local s1 = cues[p1].start
            local den = cues[p2].start - s1
            transform = function(t)
                local num = t1 * den + (t - s1) * (t2 - t1)
                if den < 0 then
                    return round_ratio(-num, -den)
                end
                return round_ratio(num, den)
            end
        elseif command == "SCALE" then
            transform = function(t)
                return round_ratio(t * args[1], args[2])
            end
        elseif command == "SNAP" then
            local a, b = table.unpack(args[1])
            transform = function(t)
                return round_ratio(round_ratio(t * a, 1000 * b) * 1000 * b, a)
            end
        else
            local delta = command == "SHIFT" and args[1] or args[2]
            transform = function(t)
                return t + delta
            end
        end
        for p = first, n do
            local cue = cues[p]
            local start, stop = transform(cue.start), transform(cue.stop)
            if start < 0 or stop < 0 then
                clamped = clamped + 1
            end
            start, stop = math.max(0, start), math.max(0, stop)
            if start ~= cue.start then
                changed = changed + 1
            end
            if stop ~= cue.stop then
                changed = changed + 1
            end
            cue.start, cue.stop = start, stop
        end
        if command == "SNAP" then
            output[1] = "SNAP changed=" .. changed
        elseif command == "SCALE" then
            output[1] = "SCALE cues=" .. n
        else
            output[1] = command .. " cues=" .. math.max(0, n - first + 1) .. " clamped=" .. clamped
        end
    elseif command == "FIXOVERLAP" then
        local fixed, failed = 0, 0
        for p = 1, n - 1 do
            local candidate = cues[p + 1].start - args[1]
            if cues[p].stop > candidate then
                if candidate > cues[p].start then
                    cues[p].stop = candidate
                    fixed = fixed + 1
                else
                    output[#output + 1] = "cue " .. p .. ": cannot fix"
                    failed = failed + 1
                end
            end
        end
        output[#output + 1] = "FIXOVERLAP fixed=" .. fixed .. " failed=" .. failed
    elseif command == "EXTEND" then
        local extended, short = 0, 0
        for p, cue in ipairs(cues) do
            if cue.stop - cue.start < args[1] then
                local candidate = cue.start + args[1]
                if p < n then
                    candidate = math.min(candidate, cues[p + 1].start)
                end
                if candidate > cue.stop then
                    cue.stop = candidate
                    extended = extended + 1
                end
            end
            if cue.stop - cue.start < args[1] then
                short = short + 1
            end
        end
        output[1] = "EXTEND extended=" .. extended .. " short=" .. short
    elseif command == "TIME" then
        local p, start, stop = table.unpack(args)
        cues[p].start, cues[p].stop = start, stop
        output[1] = "TIME cue=" .. p
    elseif command == "SORT" then
        for p, cue in ipairs(cues) do
            cue.original = p
        end
        table.sort(cues, function(a, b)
            if a.start ~= b.start then
                return a.start < b.start
            elseif a.stop ~= b.stop then
                return a.stop < b.stop
            end
            return a.original < b.original
        end)
        local moved = 0
        for p, cue in ipairs(cues) do
            if cue.original ~= p then
                moved = moved + 1
            end
            cue.original = nil
        end
        output[1] = "SORT moved=" .. moved
    elseif command == "RENUMBER" then
        local changed = 0
        for p, cue in ipairs(cues) do
            if cue.index ~= p then
                changed = changed + 1
            end
            cue.index = p
        end
        output[1] = "RENUMBER changed=" .. changed
    elseif command == "MERGE" then
        local result, merged = {}, 0
        for _, cue in ipairs(cues) do
            local previous = result[#result]
            local joined = false
            if previous and cue.start - previous.stop < args[1] and not dialogue(previous) and not dialogue(cue) then
                local lines = {}
                for _, line in ipairs(previous.lines) do
                    lines[#lines + 1] = line
                end
                for _, line in ipairs(cue.lines) do
                    lines[#lines + 1] = line
                end
                lines = wrap_lines(lines, 42)
                if #lines <= 2 then
                    previous.stop = math.max(previous.stop, cue.stop)
                    previous.lines = lines
                    merged = merged + 1
                    joined = true
                end
            end
            if not joined then
                result[#result + 1] = cue
            end
        end
        cues = result
        output[1] = "MERGE merged=" .. merged .. " cues=" .. #cues
    elseif command == "SPLIT" then
        local result, split = {}, 0
        for _, cue in ipairs(cues) do
            local duration = cue.stop - cue.start
            if duration <= 0 or dialogue(cue) then
                result[#result + 1] = cue
            else
                local lines = wrap_lines(cue.lines, args[1])
                if #lines <= 2 then
                    cue.lines = lines
                    result[#result + 1] = cue
                else
                    local parts, weights, allotted, order = {}, {}, {}, {}
                    local total = 0
                    for i = 1, #lines, 2 do
                        local part = {lines[i]}
                        if lines[i + 1] then
                            part[2] = lines[i + 1]
                        end
                        parts[#parts + 1] = part
                        local weight = #part[1] + (part[2] and #part[2] or 0)
                        weights[#weights + 1] = weight
                        total = total + weight
                    end
                    local remaining = duration
                    for i, weight in ipairs(weights) do
                        allotted[i] = (duration * weight) // total
                        remaining = remaining - allotted[i]
                        order[i] = i
                    end
                    table.sort(order, function(a, b)
                        local ra, rb = (duration * weights[a]) % total, (duration * weights[b]) % total
                        if ra ~= rb then
                            return ra > rb
                        end
                        return a < b
                    end)
                    for i = 1, remaining do
                        allotted[order[i]] = allotted[order[i]] + 1
                    end
                    local start = cue.start
                    for i, part in ipairs(parts) do
                        result[#result + 1] = {index = cue.index, start = start, stop = start + allotted[i], lines = part}
                        start = start + allotted[i]
                    end
                    split = split + 1
                end
            end
        end
        cues = result
        output[1] = "SPLIT split=" .. split .. " cues=" .. #cues
    elseif command == "INSERT" then
        local p, start, stop, lines = table.unpack(args)
        table.insert(cues, p, {index = p, start = start, stop = stop, lines = lines})
        output[1] = "INSERT cue=" .. p .. " cues=" .. #cues
    elseif command == "DELETE" then
        local p, q = args[1], args[2] or args[1]
        for i = q, p, -1 do
            table.remove(cues, i)
        end
        output[1] = "DELETE removed=" .. (q - p + 1) .. " cues=" .. #cues
    elseif command == "TEXT" then
        local p, lines = table.unpack(args)
        cues[p].lines = lines
        output[1] = "TEXT cue=" .. p .. " lines=" .. #lines
    elseif command == "BALANCE" then
        local changed, skipped, dialogues = 0, 0, 0
        for _, cue in ipairs(cues) do
            if dialogue(cue) then
                dialogues = dialogues + 1
            else
                local cue_words = words(table.concat(cue.lines, " "))
                local text = table.concat(cue_words, " ")
                local candidate, best_difference, best_first = nil, math.maxinteger, math.maxinteger
                if #text <= 42 then
                    candidate = {text}
                else
                    for j = 1, #cue_words - 1 do
                        local left = table.concat(cue_words, " ", 1, j)
                        local right = table.concat(cue_words, " ", j + 1)
                        local difference = math.abs(#left - #right)
                        if #left <= 42 and #right <= 42 and (difference < best_difference or (difference == best_difference and #left < best_first)) then
                            candidate, best_difference, best_first = {left, right}, difference, #left
                        end
                    end
                end
                if not candidate then
                    skipped = skipped + 1
                else
                    local different = #cue.lines ~= #candidate
                    for i, line in ipairs(candidate) do
                        if cue.lines[i] ~= line then
                            different = true
                        end
                    end
                    if different then
                        changed = changed + 1
                    end
                    cue.lines = candidate
                end
            end
        end
        output[1] = "BALANCE changed=" .. changed .. " skipped=" .. skipped .. " dialogue=" .. dialogues
    elseif command == "STRIP" or command == "CLEANHI" then
        local result, tags, labels, removed_lines, removed_cues = {}, 0, 0, 0, 0
        for _, cue in ipairs(cues) do
            local lines = {}
            for _, line in ipairs(cue.lines) do
                local text, count, speakers
                if command == "STRIP" then
                    text, count = converted_line(line, "STRIP")
                else
                    text, count, speakers = clean_hi(line)
                    labels = labels + speakers
                end
                tags = tags + count
                if text == "" or (command == "CLEANHI" and text == "-") then
                    removed_lines = removed_lines + 1
                else
                    lines[#lines + 1] = text
                end
            end
            if #lines == 0 then
                removed_cues = removed_cues + 1
            else
                cue.lines = lines
                result[#result + 1] = cue
            end
        end
        cues = result
        local prefix = command == "STRIP" and "STRIP tags=" .. tags or "CLEANHI segments=" .. tags .. " labels=" .. labels
        output[1] = prefix .. " removed_lines=" .. removed_lines .. " removed_cues=" .. removed_cues
    elseif command == "REPLACE" then
        local old, new = table.unpack(args[1])
        local replacements, changed = 0, 0
        for _, cue in ipairs(cues) do
            local local_count = 0
            for j, line in ipairs(cue.lines) do
                local pieces, position = {}, 1
                while true do
                    local first, last = line:find(old, position, true)
                    if not first then
                        pieces[#pieces + 1] = line:sub(position)
                        break
                    end
                    pieces[#pieces + 1] = line:sub(position, first - 1)
                    pieces[#pieces + 1] = new
                    position = last + 1
                    local_count = local_count + 1
                end
                cue.lines[j] = table.concat(pieces)
            end
            replacements = replacements + local_count
            if local_count > 0 then
                changed = changed + 1
            end
        end
        output[1] = "REPLACE count=" .. replacements .. " cues=" .. changed
    end
    return cues, output
end

local function load_block(block, k, cues)
    if not block[1]:match("^%d+$") or #block[1] > 6 then
        return "BAD CUE " .. k .. ": index"
    end
    if not block[2] or #block[2] ~= 29 or block[2]:sub(13, 17) ~= " --> " then
        return "BAD CUE " .. k .. ": time"
    end
    local valid_start, start = pcall(time_value, block[2]:sub(1, 12))
    local valid_stop, stop = pcall(time_value, block[2]:sub(18, 29))
    if not valid_start or not valid_stop then
        return "BAD CUE " .. k .. ": time"
    end
    if #block < 3 then
        return "BAD CUE " .. k .. ": no text"
    end
    local lines = {}
    for i = 3, #block do
        lines[#lines + 1] = block[i]
    end
    cues[#cues + 1] = {index = tonumber(block[1]), start = start, stop = stop, lines = lines}
    return nil
end

local cues, block, blocks, bad = {}, {}, 0, 0
while true do
    local line = io.read("l")
    if line == "" or line == "###" then
        if #block > 0 then
            blocks = blocks + 1
            local problem = load_block(block, blocks, cues)
            if problem then
                io.write(problem, "\n")
                bad = bad + 1
            end
            block = {}
        end
        if line == "###" then
            break
        end
    else
        block[#block + 1] = line
    end
end
io.write("LOAD cues=", #cues, " bad=", bad, "\n")
local history = {}
local function execute(line)
    local command, args = arguments(line, cues)
    if command == "UNDO" then
        if #history == 0 then
            fail("nothing to undo")
        end
        local previous = table.remove(history)
        cues = previous.cues
        return {"UNDO command=" .. previous.command}
    elseif modifying[command] then
        history[#history + 1] = {command = command, cues = copy_cues(cues)}
        local output
        cues, output = modify(command, args, cues)
        return output
    end
    return inspect(command, args, cues)
end
local count = tonumber(io.read("l"))
for i = 1, count do
    local valid, output = pcall(execute, io.read("l"))
    if valid then
        for _, line in ipairs(output) do
            io.write(line, "\n")
        end
    else
        io.write("ERROR ", output, "\n")
    end
end
