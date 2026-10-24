local function fail(reason)
    error({command_error = true, reason = reason}, 0)
end

local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end

local function slice(values, first, last)
    local result = {}
    for i = first, last do result[#result + 1] = values[i] end
    return result
end

local function digit(c)
    local byte = c:byte()
    return byte ~= nil and byte >= 48 and byte <= 57
end

local function digits(text)
    return text:match("^[0-9]+$") ~= nil
end

local function print_suffix(text)
    return text == "p" or text == "n" or text == "l"
end

local function sort_form(text)
    return text == "sort" or text:sub(1, 5) == "sort "
end

local Cursor = {}
Cursor.__index = Cursor

function Cursor.new(text, position)
    return setmetatable({text = text, position = position or 1}, Cursor)
end

function Cursor:rest()
    return self.text:sub(self.position)
end

function Cursor:delimited(delimiter)
    local start, content, replacement = self.position, {}, {}
    while self.position <= #self.text do
        local c = self.text:sub(self.position, self.position)
        self.position = self.position + 1
        if c == delimiter then
            return {text = table.concat(content), replacement = replacement,
                    raw = self.text:sub(start, self.position - 2)}
        end
        local escaped = c == "\\"
        if escaped then
            if self.position > #self.text then break end
            c = self.text:sub(self.position, self.position)
            self.position = self.position + 1
        end
        content[#content + 1] = c
        -- False is an unescaped &, while an empty array is a literal empty replacement.
        if c == "&" and not escaped then replacement[#replacement + 1] = false
        else replacement[#replacement + 1] = c end
    end
    fail("missing delimiter")
end

function Cursor:address()
    local elements = {}
    while self.position <= #self.text do
        local c = self.text:sub(self.position, self.position)
        local element
        if digit(c) then
            local start = self.position
            repeat self.position = self.position + 1
            until not digit(self.text:sub(self.position, self.position))
            element = {kind = "number", value = tonumber(self.text:sub(start, self.position - 1), 10)}
        elseif c == "+" or c == "-" then
            self.position = self.position + 1
            local start = self.position
            while digit(self.text:sub(self.position, self.position)) do self.position = self.position + 1 end
            local value = start == self.position and 1 or tonumber(self.text:sub(start, self.position - 1), 10)
            element = {kind = "offset", value = c == "+" and value or -value}
        elseif c == "'" then
            self.position = self.position + 1
            element = {kind = "mark", name = self.text:sub(self.position, self.position)}
            if self.position <= #self.text then self.position = self.position + 1 end
        elseif c == "/" or c == "?" then
            self.position = self.position + 1
            element = {kind = c, text = self:delimited(c).text}
        elseif c == "." or c == "$" or c == "," or c == ";" or c == "%" then
            element = {kind = c}
            self.position = self.position + 1
        else
            break
        end
        elements[#elements + 1] = element
    end
    return elements
end

local function expression(elements)
    for i, element in ipairs(elements) do
        if element.kind ~= "offset" and
           (i ~= 1 or element.kind == "," or element.kind == ";" or element.kind == "%") then return false end
    end
    return true
end

local function address_form(elements)
    if #elements == 1 and elements[1].kind == "%" then
        return {count = 2, left = {{kind = "number", value = 1}}, right = {{kind = "$"}}, separator = ","}
    end
    local separator
    for i, element in ipairs(elements) do
        if element.kind == "," or element.kind == ";" then
            if separator ~= nil then fail("bad address") end
            separator = i
        end
    end
    if separator == nil then
        if not expression(elements) then fail("bad address") end
        return {count = #elements == 0 and 0 or 1, left = elements}
    end
    local left, right = slice(elements, 1, separator - 1), slice(elements, separator + 1, #elements)
    if not expression(left) or not expression(right) then fail("bad address") end
    return {count = 2, left = left, right = right, separator = elements[separator].kind}
end

local function optional_count(argument)
    if argument == "" then return nil end
    if not digits(argument) or tonumber(argument, 10) == 0 then fail("invalid suffix") end
    return tonumber(argument, 10)
end

local function suffix(argument)
    if argument ~= "" and not print_suffix(argument) then fail("invalid suffix") end
    return argument
end

local function file_name(argument)
    if #argument < 2 or #argument > 9 or not argument:match("^ [a-z0-9]+$") then fail("invalid file name") end
    return argument:sub(2)
end

local function command(kind)
    return {kind = kind, suffix = "", pattern = ""}
end

local function substitution(argument)
    local result, flags = command("s"), argument
    result.count = 1
    if argument:find("[^gpnl0-9]") then
        local delimiter = argument:sub(1, 1)
        if delimiter == " " or delimiter == "\\" then fail("missing delimiter") end
        local cursor = Cursor.new(argument, 2)
        result.pattern = cursor:delimited(delimiter).text
        local replacement = cursor:delimited(delimiter)
        if replacement.raw ~= "%" then result.replacement = replacement.replacement end
        flags = cursor:rest()
    end
    local has_count, position = false, 1
    while position <= #flags do
        local c = flags:sub(position, position)
        position = position + 1
        if c == "g" and not result.all then result.all = true
        elseif print_suffix(c) and result.suffix == "" then result.suffix = c
        elseif digit(c) and not has_count then
            local start = position - 1
            while digit(flags:sub(position, position)) do position = position + 1 end
            result.count = tonumber(flags:sub(start, position - 1), 10)
            if result.count == 0 then fail("invalid suffix") end
            has_count = true
        else fail("invalid suffix") end
    end
    return result
end

local plain_commands = { [""] = true, a = true, i = true, c = true, p = true, n = true, l = true,
    ["="] = true, ["#"] = true, y = true, K = true, h = true, f = true }

local function parse_command(text)
    if sort_form(text) then
        local result = command("sort")
        result.options = {}
        local options = text == "sort" and "" or text:sub(6)
        if text ~= "sort" and options == "" then fail("invalid suffix") end
        for c in options:gmatch(".") do
            if not (c == "r" or c == "u" or c == "i" or c == "n") or result.options[c] then fail("invalid suffix") end
            result.options[c] = true
        end
        if result.options.i and result.options.n then fail("invalid suffix") end
        return result
    end
    local first, argument = text:sub(1, 1), text:sub(2)
    local result = command(first)
    if plain_commands[first] then
        if argument ~= "" then fail("invalid suffix") end
    elseif first == "d" or first == "x" or first == "j" or first == "J" then
        result.suffix = suffix(argument)
    elseif first == "z" or first == ">" or first == "<" or first == "u" then
        result.count = optional_count(argument)
    elseif first == "~" then
        if argument ~= "" and argument ~= "u" and argument ~= "l" then fail("invalid suffix") end
        result.case_mode = argument
    elseif first == "r" then
        if argument == "" or digits(argument) then
            result.kind, result.count = "redo", optional_count(argument)
        else
            result.kind, result.name = "read", file_name(argument)
        end
    elseif first == "w" then
        if argument == "" then result.kind = "write_print"
        else result.kind, result.name = "write", file_name(argument) end
    elseif first == "W" or first == "e" then
        result.name = file_name(argument)
    elseif first == "k" then
        if not argument:match("^[a-z]$") then fail("invalid mark") end
        result.name = argument
    elseif first == "m" or first == "t" then
        local cursor = Cursor.new(argument)
        result.destination = cursor:address()
        if #result.destination == 0 or not expression(result.destination) then fail("invalid destination") end
        result.suffix = suffix(cursor:rest())
    elseif first == "s" then
        return substitution(argument)
    elseif first == "g" or first == "v" then
        local delimiter = argument:sub(1, 1)
        if delimiter == "" or delimiter == " " or delimiter == "\\" then fail("missing delimiter") end
        local cursor = Cursor.new(argument, 2)
        result.pattern = cursor:delimited(delimiter).text
        local subcommand = cursor:rest()
        if subcommand == "" then subcommand = "p" end
        if not ("pnldmtjJs><~aicx"):find(subcommand:sub(1, 1), 1, true) or sort_form(subcommand) then
            fail("invalid global command")
        end
        result.subcommand = parse_command(subcommand)
    else
        fail("unknown command")
    end
    return result
end

local function has_text(line)
    local ok, result = pcall(function()
        local cursor = Cursor.new(line)
        cursor:address()
        local part = cursor:rest()
        if part == "a" or part == "i" or part == "c" then return true end
        local first, delimiter = part:sub(1, 1), part:sub(2, 2)
        if (first ~= "g" and first ~= "v") or delimiter == "" or delimiter == " " or delimiter == "\\" then return false end
        cursor = Cursor.new(part, 3)
        cursor:delimited(delimiter)
        part = cursor:rest()
        return part == "a" or part == "i" or part == "c"
    end)
    if ok then return result end
    if type(result) == "table" and result.command_error then return false end
    error(result, 0)
end

local no_address = {u = true, redo = true, h = true, K = true, f = true, e = true}
local one_address = {a = true, i = true, x = true, ["="] = true, read = true, k = true, z = true}
local modifying = {a = true, i = true, c = true, d = true, x = true, j = true, J = true, m = true,
    t = true, s = true, [">"] = true, ["<"] = true, ["~"] = true, sort = true, read = true, e = true}

local function modifies(cmd)
    if cmd.kind == "g" or cmd.kind == "v" then return modifying[cmd.subcommand.kind] == true end
    return modifying[cmd.kind] == true
end

local function copy_state(state)
    local result = copy(state)
    for _, name in ipairs({"lines", "marks", "undo", "redo", "files"}) do result[name] = copy(state[name]) end
    return result
end

local function ascii_compare(a, b)
    for i = 1, math.min(#a, #b) do
        if a:byte(i) ~= b:byte(i) then return a:byte(i) < b:byte(i) and -1 or 1 end
    end
    return #a < #b and -1 or #a > #b and 1 or 0
end

local function change_case(text, mode)
    local result = {}
    for i = 1, #text do
        local c = text:byte(i)
        if c >= 65 and c <= 90 and mode ~= "u" then c = c + 32
        elseif c >= 97 and c <= 122 and mode ~= "l" then c = c - 32 end
        result[i] = string.char(c)
    end
    return table.concat(result)
end

local Editor = {}
Editor.__index = Editor

function Editor.new(state)
    return setmetatable({state = state, output = {}}, Editor)
end

function Editor:resolve_pattern(search)
    if search ~= "" then self.state.pattern = search end
    if self.state.pattern == nil then fail("no previous pattern") end
    return self.state.pattern
end

function Editor:locate(id)
    for i, line in ipairs(self.state.lines) do if line.id == id then return i end end
    return nil
end

function Editor:evaluate(elements)
    local state, value = self.state, self.state.current
    for _, element in ipairs(elements) do
        local kind = element.kind
        if kind == "offset" then value = value + element.value
        elseif kind == "number" then value = element.value
        elseif kind == "." then value = state.current
        elseif kind == "$" then value = #state.lines
        elseif kind == "mark" then
            if not element.name:match("^[a-z]$") then fail("invalid mark") end
            value = self:locate(state.marks[element.name])
            if value == nil then fail("mark not set") end
        elseif kind == "/" or kind == "?" then
            local pattern = self:resolve_pattern(element.text)
            local step, index, found = kind == "/" and 1 or -1, state.current, false
            for _ = 1, #state.lines do
                index = index + step
                if index < 1 then index = #state.lines elseif index > #state.lines then index = 1 end
                if state.lines[index].text:find(pattern, 1, true) then value, found = index, true; break end
            end
            if not found then fail("no match") end
        end
    end
    return value
end

function Editor:range(kind, address)
    local state, count = self.state, address.count
    if no_address[kind] then return 0, 0 end
    local a, b
    if count >= 1 then
        if count == 2 and #address.left == 0 then a = address.separator == "," and 1 or state.current
        else a = self:evaluate(address.left) end
        if count == 2 then
            if address.separator == ";" then
                if a < 0 or a > #state.lines then fail("address out of range") end
                state.current = a
            end
            b = #address.right == 0 and #state.lines or self:evaluate(address.right)
        else b = a end
    end
    if one_address[kind] then
        if count == 0 then
            if kind == "=" or kind == "read" then a = #state.lines
            elseif kind == "z" then a = state.current + 1
            else a = state.current end
        end
        local minimum = (kind == "k" or kind == "z") and 1 or 0
        if a < minimum or a > #state.lines then fail("address out of range") end
        return a, a
    end
    local whole = kind == "write_print" or kind == "write" or kind == "W" or kind == "#"
    if count == 0 then
        if whole or kind == "g" or kind == "v" or kind == "sort" then a, b = 1, #state.lines
        elseif kind == "j" or kind == "J" then a, b = state.current, state.current + 1
        else a, b = state.current, state.current end
        if whole then return a, b end
    end
    if a < 1 or a > #state.lines or b < 1 or b > #state.lines then fail("address out of range") end
    if a > b or a == b and (kind == "j" or kind == "J") then fail("invalid range") end
    return a, b
end

function Editor:emit(text)
    self.output[#self.output + 1] = text
end

function Editor:print_line(number, form)
    local text = self.state.lines[number].text
    if form == "n" then self:emit(string.format("%3d %s", number, text))
    elseif form == "l" then
        local escaped = {}
        for i = 1, #text do
            local c = text:sub(i, i)
            escaped[#escaped + 1] = c == "\\" and "\\\\" or c
        end
        text = table.concat(escaped) .. "$"
        while #text > 40 do
            self:emit(text:sub(1, 39) .. "\\")
            text = text:sub(40)
        end
        self:emit(text)
    else self:emit(text) end
end

function Editor:contents(a, b)
    local result = {}
    for i = a, b do result[#result + 1] = self.state.lines[i].text end
    return result
end

function Editor:new_lines(text)
    local lines = {}
    for _, content in ipairs(text) do
        lines[#lines + 1] = {id = self.state.next_id, text = content}
        self.state.next_id = self.state.next_id + 1
    end
    return lines
end

function Editor:splice(position, remove, inserted)
    local lines, result = self.state.lines, {}
    for i = 1, position do result[#result + 1] = lines[i] end
    for _, line in ipairs(inserted) do result[#result + 1] = line end
    for i = position + remove + 1, #lines do result[#result + 1] = lines[i] end
    self.state.lines = result
end

local function bytes(text)
    local total = 0
    for _, line in ipairs(text) do total = total + #line + 1 end
    return total
end

function Editor:substitute(cmd, a, b, in_global)
    local state, pattern = self.state, self:resolve_pattern(cmd.pattern)
    local replacement = cmd.replacement or state.replacement
    if replacement == nil then fail("no previous substitution") end
    state.replacement = replacement
    local expanded = {}
    for _, part in ipairs(replacement) do expanded[#expanded + 1] = part == false and pattern or part end
    local text, changed = table.concat(expanded), 0
    for i = a, b do
        local original, pieces = state.lines[i].text, {}
        local position, occurrence, substituted = 1, 0, false
        while true do
            local found = original:find(pattern, position, true)
            if found == nil then break end
            occurrence = occurrence + 1
            pieces[#pieces + 1] = original:sub(position, found - 1)
            if occurrence == cmd.count or cmd.all and occurrence > cmd.count then
                pieces[#pieces + 1] = text
                substituted = true
            else pieces[#pieces + 1] = pattern end
            position = found + #pattern
        end
        if substituted then
            pieces[#pieces + 1] = original:sub(position)
            local result = table.concat(pieces)
            if #result > 80 then fail("line too long") end
            if result == "" or result:sub(-1) == " " then fail("bad line") end
            state.lines[i] = {id = state.lines[i].id, text = result}
            state.current, changed = i, changed + 1
        end
    end
    if changed == 0 and not in_global then fail("no match") end
    if changed > 0 and cmd.suffix ~= "" then self:print_line(state.current, cmd.suffix) end
    return changed
end

function Editor:sort_lines(cmd, a, b)
    local decorated = {}
    for i = a, b do
        local line = self.state.lines[i]
        local key = line.text
        if cmd.options.n then key = tonumber(key:match("^%-?[0-9]+") or "0", 10)
        elseif cmd.options.i then key = change_case(key, "l") end
        decorated[#decorated + 1] = {line = line, key = key, index = i}
    end
    table.sort(decorated, function(left, right)
        local order
        if cmd.options.n then order = left.key < right.key and -1 or left.key > right.key and 1 or 0
        else order = ascii_compare(left.key, right.key) end
        if cmd.options.r then order = -order end
        if order == 0 then return left.index < right.index end
        return order < 0
    end)
    local sorted, previous = {}, nil
    for _, item in ipairs(decorated) do
        if not cmd.options.u or #sorted == 0 or item.key ~= previous then sorted[#sorted + 1] = item.line end
        previous = item.key
    end
    self:splice(a - 1, b - a + 1, sorted)
    self.state.current = a + #sorted - 1
end

function Editor:execute(cmd, a, b, text, in_global)
    local state, kind = self.state, cmd.kind
    if kind == "" then
        self:print_line(b, "p")
        state.current = b
    elseif kind == "p" or kind == "n" or kind == "l" then
        for i = a, b do self:print_line(i, kind) end
        state.current = b
    elseif kind == "z" then
        if cmd.count ~= nil then state.display_count = cmd.count end
        local last = math.min(a + state.display_count - 1, #state.lines)
        for i = a, last do self:print_line(i, "p") end
        state.current = last
    elseif kind == "=" then self:emit(tostring(a))
    elseif kind == "#" then
        local words, chars = 0, 0
        for i = a, b do
            local content = state.lines[i].text
            chars = chars + #content
            for _ in content:gmatch("[^ ]+") do words = words + 1 end
        end
        self:emit("count lines=" .. (b - a + 1) .. " words=" .. words .. " chars=" .. chars)
    elseif kind == "write_print" then
        for i = a, b do self:print_line(i, "p") end
        self:emit("lines=" .. (b - a + 1) .. " bytes=" .. bytes(self:contents(a, b)))
    elseif kind == "a" or kind == "i" then
        local position = kind == "a" and a or math.max(a, 1) - 1
        self:splice(position, 0, self:new_lines(text))
        state.current = position + #text
    elseif kind == "c" or kind == "d" then
        state.cut = self:contents(a, b)
        self:splice(a - 1, b - a + 1, kind == "c" and self:new_lines(text) or {})
        state.current = kind == "c" and #text > 0 and a + #text - 1 or math.min(a, #state.lines)
    elseif kind == "y" then state.cut = self:contents(a, b)
    elseif kind == "x" then
        if #state.cut == 0 then fail("nothing to put") end
        self:splice(a, 0, self:new_lines(state.cut))
        state.current = a + #state.cut
    elseif kind == "m" or kind == "t" then
        local destination = self:evaluate(cmd.destination)
        if destination < 0 or destination > #state.lines then fail("address out of range") end
        if kind == "m" and a <= destination and destination < b then fail("invalid destination") end
        local block = kind == "m" and slice(state.lines, a, b) or self:new_lines(self:contents(a, b))
        if kind == "m" then
            self:splice(a - 1, b - a + 1, {})
            if destination >= b then destination = destination - #block end
        end
        self:splice(destination, 0, block)
        state.current = destination + #block
    elseif kind == "j" or kind == "J" then
        local parts = {state.lines[a].text}
        for i = a + 1, b do
            local part = state.lines[i].text
            if kind == "J" then part = part:gsub("^ +", "") end
            parts[#parts + 1] = part
        end
        local joined = table.concat(parts, kind == "J" and " " or "")
        if #joined > 80 then fail("line too long") end
        self:splice(a - 1, b - a + 1, {{id = state.lines[a].id, text = joined}})
        state.current = a
    elseif kind == ">" or kind == "<" or kind == "~" then
        for i = a, b do
            local line, width = state.lines[i], cmd.count or 4
            local content = line.text
            if kind == ">" then content = string.rep(" ", width) .. content
            elseif kind == "<" then content = content:sub(math.min(width, #(content:match("^ *"))) + 1)
            else content = change_case(content, cmd.case_mode) end
            if #content > 80 then fail("line too long") end
            state.lines[i] = {id = line.id, text = content}
        end
        state.current = b
    elseif kind == "sort" then self:sort_lines(cmd, a, b)
    elseif kind == "s" then return self:substitute(cmd, a, b, in_global)
    elseif kind == "k" then state.marks[cmd.name] = state.lines[a].id
    elseif kind == "K" then
        local marks = {}
        for code = 97, 122 do
            local name = string.char(code)
            local index = self:locate(state.marks[name])
            if index ~= nil then marks[#marks + 1] = name .. "=" .. index end
        end
        self:emit("marks " .. (#marks == 0 and "none" or table.concat(marks, " ")))
    elseif kind == "u" or kind == "redo" then
        local source = kind == "u" and state.undo or state.redo
        local target = kind == "u" and state.redo or state.undo
        local count = cmd.count or 1
        if #source < count then fail(kind == "u" and "nothing to undo" or "nothing to redo") end
        for _ = 1, count do
            local record = table.remove(source)
            target[#target + 1] = {command = record.command, lines = copy(state.lines), current = state.current}
            state.lines, state.current = copy(record.lines), record.current
        end
    elseif kind == "h" then
        self:emit("history undo=" .. #state.undo .. " redo=" .. #state.redo)
        for i = #state.undo, 1, -1 do self:emit("undo " .. (#state.undo - i + 1) .. ": " .. state.undo[i].command) end
        for i = #state.redo, 1, -1 do self:emit("redo " .. (#state.redo - i + 1) .. ": " .. state.redo[i].command) end
    elseif kind == "g" or kind == "v" then
        local pattern, selected = self:resolve_pattern(cmd.pattern), {}
        for i = a, b do
            local matches = state.lines[i].text:find(pattern, 1, true) ~= nil
            if matches == (kind == "g") then selected[#selected + 1] = state.lines[i].id end
        end
        if #selected == 0 then fail("no match") end
        local changed = 0
        for _, id in ipairs(selected) do
            local index = self:locate(id)
            if index ~= nil then
                state.current = index
                local first, last = self:range(cmd.subcommand.kind, {count = 0, left = {}})
                changed = changed + self:execute(cmd.subcommand, first, last, text, true)
            end
        end
        if cmd.subcommand.kind == "s" and changed == 0 then fail("no match") end
    elseif kind == "write" or kind == "W" then
        local contents = self:contents(a, b)
        if kind == "W" and state.files[cmd.name] ~= nil then
            local combined = copy(state.files[cmd.name])
            for _, line in ipairs(contents) do combined[#combined + 1] = line end
            contents = combined
        end
        state.files[cmd.name] = contents
        self:emit("file " .. cmd.name .. " lines=" .. #contents .. " bytes=" .. bytes(contents))
    elseif kind == "read" or kind == "e" then
        local contents = state.files[cmd.name]
        if contents == nil then fail("no such file") end
        local entered = self:new_lines(contents)
        if kind == "e" then state.lines, state.current = entered, #entered
        else self:splice(a, 0, entered); state.current = a + #entered end
        self:emit("file " .. cmd.name .. " lines=" .. #contents .. " bytes=" .. bytes(contents))
    elseif kind == "f" then
        local names, parts = {}, {}
        for name in pairs(state.files) do names[#names + 1] = name end
        table.sort(names, function(left, right) return ascii_compare(left, right) < 0 end)
        for _, name in ipairs(names) do parts[#parts + 1] = name .. "=" .. #state.files[name] end
        self:emit("files " .. (#parts == 0 and "none" or table.concat(parts, " ")))
    end
    if cmd.suffix ~= "" and state.current >= 1 then self:print_line(state.current, cmd.suffix) end
    return 0
end

local state = {lines = {}, current = 0, marks = {}, cut = {}, display_count = 5,
               undo = {}, redo = {}, files = {}, next_id = 1}

while true do
    local line = io.read("l")
    if line == nil or line == "Q" then break end
    local text = {}
    if has_text(line) then
        while true do
            local content = io.read("l")
            if content == "." then break end
            text[#text + 1] = content
        end
    end
    local ok, result = pcall(function()
        local cursor = Cursor.new(line)
        local address = address_form(cursor:address())
        local cmd = parse_command(cursor:rest())
        if no_address[cmd.kind] and address.count > 0 then fail("unexpected address") end
        if one_address[cmd.kind] and address.count == 2 then fail("too many addresses") end
        local next_state = copy_state(state)
        local editor = Editor.new(next_state)
        local a, b = editor:range(cmd.kind, address)
        editor:execute(cmd, a, b, text, false)
        if #next_state.lines > 200 then fail("buffer full") end
        if modifies(cmd) then
            next_state.undo[#next_state.undo + 1] = {command = line, lines = copy(state.lines), current = state.current}
            next_state.redo = {}
        end
        return {state = next_state, output = editor.output}
    end)
    if ok then
        state = result.state
        for _, output in ipairs(result.output) do io.write(output, "\n") end
    elseif type(result) == "table" and result.command_error then io.write("? ", result.reason, "\n")
    else error(result, 0) end
end
