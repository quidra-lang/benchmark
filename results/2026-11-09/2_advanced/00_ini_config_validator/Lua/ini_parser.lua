local logical_lines = require("lexer").logical_lines

local DIRECTIVES = { ["@include"] = true, ["@unset"] = true }

local function is_name(text)
    return text:find("^[a-z][a-z0-9_]*$") ~= nil
end

local function is_section_name(text)
    for part in (text .. "."):gmatch("(.-)%.") do
        if not is_name(part) then
            return false
        end
    end
    return true
end

local function strip(text)
    return text:match("^ *(.-) *$")
end

local function trimmed(segments)
    local result = table.move(segments, 1, #segments, 1, {})
    result[1] = result[1]:match("^ *(.*)$")
    result[#result] = result[#result]:match("^(.-) *$")
    return result
end

local function assigned_value(segments)
    if #segments == 1 then
        return segments[1]
    end
    if #segments == 3 and segments[1] == "" and segments[3] == "" then
        return segments[2]
    end
    return nil
end

local Parser = {}
Parser.__index = Parser

function Parser.new(name)
    local document = { name = name, statements = {}, diagnostics = {} }
    return setmetatable({ document = document, assigned = {} }, Parser)
end

function Parser:report(line, code, message)
    table.insert(self.document.diagnostics, {
        document = self.document.name,
        line = line,
        code = code,
        message = message,
    })
end

function Parser:add(kind, line, target, value)
    table.insert(self.document.statements, {
        kind = kind,
        line = line,
        target = target,
        value = value or "",
    })
end

function Parser:interpret(line)
    if line.error then
        self:report(line.number, line.error.code, line.error.message)
        return
    end
    local segments = trimmed(line.segments)
    local first = segments[1]
    if #segments == 1 and first == "" then
        return
    end
    if first:sub(1, 1) == "[" then
        self:header(line.number, segments)
    elseif first:sub(1, 1) == "@" then
        self:directive(line.number, segments)
    else
        self:assignment(line.number, segments)
    end
end

function Parser:fail_header(number, message)
    self:report(number, "E_SECTION", message)
    self.section = nil
end

function Parser:header(number, segments)
    local text = segments[1]
    local name = text:sub(2, -2)
    local parent
    local colon = name:find(":", 1, true)
    if colon then
        parent = strip(name:sub(colon + 1))
        name = name:sub(1, colon - 1)
    end
    name = strip(name)
    local well_formed = #segments == 1 and text:sub(-1) == "]"
    local relative = name:sub(1, 1) == "." and is_section_name(name:sub(2))
    if not well_formed or (parent and not is_section_name(parent)) then
        self:fail_header(number, "invalid section header")
    elseif not relative and not is_section_name(name) then
        self:fail_header(number, "invalid section header")
    elseif relative and self.base == nil then
        self:fail_header(number, "relative section without base")
    else
        if relative then
            self.section = self.base .. name
        else
            self.section = name
            self.base = name
        end
        if parent then
            self:add("inherit", number, self.section, parent)
        end
    end
end

function Parser:directive(number, segments)
    local words = {}
    for word in segments[1]:gmatch("[^ ]+") do
        table.insert(words, word)
    end
    local valid = #segments == 1 and #words == 2 and DIRECTIVES[words[1]] and is_name(words[2])
    if not valid then
        self:report(number, "E_SYNTAX", "invalid directive")
    elseif words[1] == "@include" then
        self:add("include", number, words[2])
    elseif self.section == nil then
        self:report(number, "E_NO_SECTION", "no current section")
    else
        self:add("unset", number, self.section .. "." .. words[2])
    end
end

function Parser:assignment(number, segments)
    local has_equals = false
    for index = 1, #segments, 2 do
        if segments[index]:find("=", 1, true) then
            has_equals = true
        end
    end
    if not has_equals then
        self:report(number, "E_SYNTAX", "invalid line")
        return
    end
    local equals = segments[1]:find("=", 1, true)
    if not equals then
        self:report(number, "E_SYNTAX", "invalid key")
        return
    end
    local key = strip(segments[1]:sub(1, equals - 1))
    local append = key:sub(-1) == "+"
    if append then
        key = key:sub(1, -2):match("^(.-) *$")
    end
    if not is_name(key) then
        self:report(number, "E_SYNTAX", "invalid key")
        return
    end
    local rest = { segments[1]:sub(equals + 1), table.unpack(segments, 2) }
    local value = assigned_value(trimmed(rest))
    if value == nil then
        self:report(number, "E_SYNTAX", "invalid value")
        return
    end
    if self.section == nil then
        self:report(number, "E_NO_SECTION", "no current section")
        return
    end
    local full_key = self.section .. "." .. key
    if not append then
        local previous = self.assigned[full_key]
        if previous then
            self:report(number, "W_DUPLICATE", full_key .. " already set at line " .. previous)
        end
        self.assigned[full_key] = number
    end
    self:add(append and "append" or "assign", number, full_key, value)
end

local function parse_document(name, physical_lines)
    local parser = Parser.new(name)
    for _, line in ipairs(logical_lines(physical_lines)) do
        parser:interpret(line)
    end
    return parser.document
end

return { is_section_name = is_section_name, parse_document = parse_document }
