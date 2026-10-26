local headers = require("headers")
local M = {}
local phrase_kinds, atom_kinds = {word = true, quoted = true, ["."] = true}, {word = true, ["."] = true}

local function address_error() error("invalid address", 0) end
local function dot_atom(tokens)
    if #tokens % 2 == 0 then return false end
    for index, token in ipairs(tokens) do
        if token.kind ~= (index % 2 == 1 and "word" or ".") then return false end
    end
    return true
end
local function address_string(local_part, domain)
    if not dot_atom(local_part) or not dot_atom(domain) then address_error() end
    local first, second = {}, {}
    for _, token in ipairs(local_part) do first[#first + 1] = token.text end
    for _, token in ipairs(domain) do second[#second + 1] = token.text end
    return (table.concat(first) .. "@" .. table.concat(second)):lower()
end

local Parser = {}
Parser.__index = Parser
function Parser:peek() return self.tokens[self.position] and self.tokens[self.position].kind or nil end
function Parser:expect(kind)
    if self:peek() ~= kind then address_error() end
    self.position = self.position + 1
end
function Parser:read_run(kinds)
    local result = {}
    while kinds[self:peek()] do result[#result + 1] = self.tokens[self.position] self.position = self.position + 1 end
    return result
end
function Parser:display_name(phrase)
    local parts, previous = {}, false
    for index, token in ipairs(phrase) do
        local text, decoded = token.text, false
        if token.kind == "word" then
            local failed
            text, decoded, failed = headers.decode_word(text)
            self.encoding_error = self.encoding_error or failed
        end
        if index > 1 and token.spaced and not (decoded and previous) then parts[#parts + 1] = " " end
        parts[#parts + 1], previous = text, decoded
    end
    return headers.collapse_whitespace(table.concat(parts))
end
function Parser:parse_address(in_group)
    local phrase = self:read_run(phrase_kinds)
    local following = self:peek()
    if following == "<" then
        self.position = self.position + 1
        local local_part = self:read_run(atom_kinds)
        self:expect("@")
        local domain = self:read_run(atom_kinds)
        self:expect(">")
        return {name = self:display_name(phrase), address = address_string(local_part, domain)}
    elseif following == "@" then
        self.position = self.position + 1
        return {name = "", address = address_string(phrase, self:read_run(atom_kinds))}
    elseif following == ":" and #phrase > 0 and not in_group then
        self.position = self.position + 1
        local mailboxes = {}
        if self:peek() ~= ";" then
            mailboxes[#mailboxes + 1] = self:parse_address(true)
            while self:peek() == "," do self.position = self.position + 1 mailboxes[#mailboxes + 1] = self:parse_address(true) end
        end
        self:expect(";")
        return {mailboxes = mailboxes}
    end
    address_error()
end
function Parser:parse_list()
    local addresses = {self:parse_address(false)}
    while self:peek() == "," do self.position = self.position + 1 addresses[#addresses + 1] = self:parse_address(false) end
    if self.position <= #self.tokens then address_error() end
    return addresses
end

function M.parse_address_list(value)
    local tokens = headers.tokenize_address(value)
    if tokens == nil or #tokens == 0 then return nil end
    local parser = setmetatable({tokens = tokens, position = 1, encoding_error = false}, Parser)
    local success, addresses = pcall(function() return parser:parse_list() end)
    if not success then return nil end
    return addresses, parser.encoding_error
end

return M
