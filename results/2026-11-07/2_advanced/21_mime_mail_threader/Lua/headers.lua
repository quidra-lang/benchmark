local mime = require("mime")
local M = {}
local address_specials = "<>:;@,."
local address_word_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~"
local mime_specials, mime_word_chars = "/;=", ""
for code = 33, 126 do
    local char = string.char(code)
    if not ('()<>@,;:\\"/[]?='):find(char, 1, true) then mime_word_chars = mime_word_chars .. char end
end

function M.split(text, separator)
    local result, position = {}, 1
    while true do
        local ending = text:find(separator, position, true)
        if ending == nil then result[#result + 1] = text:sub(position) break end
        result[#result + 1], position = text:sub(position, ending - 1), ending + #separator
    end
    return result
end

function M.split_words(text)
    local words = {}
    for word in text:gmatch("[^ \t]+") do words[#words + 1] = word end
    return words
end
function M.collapse_whitespace(text) return table.concat(M.split_words(text), " ") end
function M.strip(text) return text:match("^[ \t]*(.-)[ \t]*$") end
function M.rstrip(text) return (text:gsub("[ \t]+$", "")) end

local Header = {}
Header.__index = Header
function Header:value(name)
    name = name:lower()
    for _, field in ipairs(self.fields) do if field[1] == name then return field[2] end end
    return nil
end
function Header:count(name)
    local count = 0
    name = name:lower()
    for _, field in ipairs(self.fields) do if field[1] == name then count = count + 1 end end
    return count
end

function M.parse_fields(lines)
    local header, in_field = setmetatable({fields = {}, invalid_lines = {}}, Header), false
    for _, entry in ipairs(lines) do
        local number, text = entry[1], entry[2]
        local first = text:sub(1, 1)
        if first == " " or first == "\t" then
            if in_field then
                local field = header.fields[#header.fields]
                field[2] = field[2] .. text
            else header.invalid_lines[#header.invalid_lines + 1] = number end
        else
            local colon = text:find(":", 1, true)
            local name = colon and text:sub(1, colon - 1) or ""
            in_field = #name > 0 and name:match("^[!-~]+$") ~= nil
            if in_field then header.fields[#header.fields + 1] = {name:lower(), text:sub(colon + 1)}
            else header.invalid_lines[#header.invalid_lines + 1] = number end
        end
    end
    for _, field in ipairs(header.fields) do field[2] = M.strip(field[2]) end
    return header
end

function M.remove_comments(text)
    local result, depth, position = {}, 0, 1
    while position <= #text do
        local char = text:sub(position, position)
        if depth == 0 then
            if char == "(" then depth = 1 result[#result + 1] = " " else result[#result + 1] = char end
        elseif char == "\\" then position = position + 1
        elseif char == "(" then depth = depth + 1
        elseif char == ")" then depth = depth - 1 end
        position = position + 1
    end
    if depth ~= 0 then return nil end
    return table.concat(result)
end

local function skip_comment(text, position)
    local depth = 0
    while position <= #text do
        local char = text:sub(position, position)
        if char == "\\" then position = position + 2
        else
            if char == "(" then depth = depth + 1
            elseif char == ")" then depth = depth - 1 if depth == 0 then return position + 1 end end
            position = position + 1
        end
    end
    return nil
end

local function read_quoted(text, position)
    local chars = {}
    position = position + 1
    while position <= #text do
        local char = text:sub(position, position)
        if char == '"' then return table.concat(chars), position + 1 end
        if char == "\\" then position = position + 1 if position > #text then return nil end char = text:sub(position, position) end
        chars[#chars + 1], position = char, position + 1
    end
    return nil
end

local function tokenize(text, specials, word_chars)
    local tokens, position, spaced = {}, 1, false
    while position <= #text do
        local char = text:sub(position, position)
        if char == " " or char == "\t" then spaced, position = true, position + 1
        elseif char == "(" then
            position = skip_comment(text, position)
            if position == nil then return nil end
            spaced = true
        else
            if char == '"' then
                local value, next_position = read_quoted(text, position)
                if value == nil then return nil end
                tokens[#tokens + 1], position = {kind = "quoted", text = value, spaced = spaced}, next_position
            elseif specials:find(char, 1, true) then tokens[#tokens + 1], position = {kind = char, text = char, spaced = spaced}, position + 1
            elseif word_chars:find(char, 1, true) then
                local ending = position + 1
                while ending <= #text and word_chars:find(text:sub(ending, ending), 1, true) do ending = ending + 1 end
                tokens[#tokens + 1], position = {kind = "word", text = text:sub(position, ending - 1), spaced = spaced}, ending
            else return nil end
            spaced = false
        end
    end
    return tokens
end

function M.tokenize_address(text) return tokenize(text, address_specials, address_word_chars) end
function M.tokenize_mime(text) return tokenize(text, mime_specials, mime_word_chars) end

local function decode_q(text)
    local result, position = {}, 1
    while position <= #text do
        local char = text:sub(position, position)
        if char == "_" then result[#result + 1], position = " ", position + 1
        elseif char == "=" then
            local digits = text:sub(position + 1, position + 2)
            if #digits ~= 2 or not digits:match("^%x%x$") then return nil end
            result[#result + 1], position = string.char(tonumber(digits, 16)), position + 3
        else result[#result + 1], position = char, position + 1 end
    end
    return table.concat(result)
end

function M.decode_word(word)
    if #word < 4 or word:sub(1, 2) ~= "=?" or word:sub(-2) ~= "?=" then return word, false, false end
    local pieces = M.split(word:sub(3, -3), "?")
    if #pieces ~= 3 or pieces[1] == "" or pieces[2] == "" or pieces[3] == "" then return word, false, false end
    local decoded
    if pieces[1]:lower() == "us-ascii" then
        local encoding = pieces[2]:lower()
        if encoding == "q" then decoded = decode_q(pieces[3])
        elseif encoding == "b" then decoded = mime.strict_base64(pieces[3]) end
    end
    if decoded ~= nil then
        for position = 1, #decoded do
            local byte = decoded:byte(position)
            if byte < 32 or byte > 126 then decoded = nil break end
        end
    end
    if decoded == nil then return word, false, true end
    return decoded, true, false
end

function M.decode_unstructured(value)
    local parts, error, previous = {}, false, false
    for _, word in ipairs(M.split_words(value)) do
        local text, decoded, failed = M.decode_word(word)
        if #parts > 0 and not (decoded and previous) then parts[#parts + 1] = " " end
        parts[#parts + 1], previous, error = text, decoded, error or failed
    end
    return M.collapse_whitespace(table.concat(parts)), error
end

function M.parse_parameters(value, with_subtype)
    local tokens = M.tokenize_mime(value)
    if tokens == nil or #tokens == 0 or tokens[1].kind ~= "word" then return nil end
    local main_type, subtype, position = tokens[1].text:lower(), "", 2
    if with_subtype then
        if #tokens < 3 or tokens[2].kind ~= "/" or tokens[3].kind ~= "word" then return nil end
        subtype, position = tokens[3].text:lower(), 4
    end
    local parameters = {}
    while position <= #tokens do
        local a, b, c, d = tokens[position], tokens[position + 1], tokens[position + 2], tokens[position + 3]
        if not d or a.kind ~= ";" or b.kind ~= "word" or c.kind ~= "=" or d.kind ~= "word" and d.kind ~= "quoted" then return nil end
        local name = b.text:lower()
        if parameters[name] == nil then parameters[name] = d.text end
        position = position + 4
    end
    return {main_type, subtype, parameters}
end

return M
