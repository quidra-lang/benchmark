local Lexer = require("lexer")
local Parser = {}
Parser.__index = Parser
Parser.atom_kinds = {identifier = true, number = true, symbol = true, command = true, text = true}
local terminators = {["}"] = true, ["&"] = true, newline = true, right = true, ["end"] = true, eof = true}
local arguments = {identifier = true, number = true, symbol = true, command = true, text = true, eqref = true,
    ["{"] = true, frac = true, binom = true, overset = true, underset = true, sqrt = true, accent = true}
local unexpected = {right = "unexpected \\right", ["end"] = "unexpected \\end", ["&"] = "misplaced &", newline = "misplaced \\\\"}

function Parser.node(kind, children, value, column)
    return {kind = kind, children = children or {}, value = value, column = column or 0}
end

function Parser.collapse(elements)
    return #elements == 1 and elements[1] or Parser.node("row", elements)
end

function Parser.check_braces(tokens)
    local stack = {}
    for _, token in ipairs(tokens) do
        if token.kind == "{" then stack[#stack + 1] = token.column
        elseif token.kind == "}" then
            if #stack == 0 then Lexer.fail(token.column, "unmatched }") end
            stack[#stack] = nil
        end
    end
    if #stack > 0 then Lexer.fail(stack[#stack], "unclosed {") end
end

function Parser.new(tokens)
    return setmetatable({tokens = tokens, position = 1}, Parser)
end

function Parser:peek()
    return self.tokens[self.position]
end

function Parser:take()
    local token = self:peek()
    if token.kind ~= "eof" then self.position = self.position + 1 end
    return token
end

function Parser:unexpected()
    local token = self:peek()
    Lexer.fail(token.column, assert(unexpected[token.kind]))
end

function Parser:parse()
    local elements = self:element_list(true, false)
    if self:peek().kind ~= "eof" then self:unexpected() end
    return elements
end

function Parser:element_list(top, index)
    local elements = {}
    while true do
        local token = self:peek()
        if terminators[token.kind] or (index and token.kind == "symbol" and token.value == "]") then return elements end
        if token.kind == "tag" or token.kind == "label" then
            if not top then Lexer.fail(token.column, "misplaced \\" .. token.kind) end
            if self[token.kind] then Lexer.fail(token.column, "duplicate \\" .. token.kind) end
            self[token.kind] = self:take()
        else elements[#elements + 1] = self:element() end
    end
end

function Parser:element()
    local kind = self:peek().kind
    local base = (kind == "^" or kind == "_") and Parser.node("row") or self:nucleus()
    local subscript, superscript = false, false
    while self:peek().kind == "^" or self:peek().kind == "_" do
        local token = self:take()
        if token.kind == "^" then
            if superscript then Lexer.fail(token.column, "double superscript") end
            superscript = self:argument("^")
        else
            if subscript then Lexer.fail(token.column, "double subscript") end
            subscript = self:argument("_")
        end
    end
    if not subscript and not superscript then return base end
    return Parser.node("script", {base, subscript, superscript})
end

function Parser:argument(name)
    if not arguments[self:peek().kind] then Lexer.fail(self:peek().column, "missing argument for " .. name) end
    return self:nucleus()
end

function Parser:delimiter()
    local token = self:take()
    local delimiters = {["("] = true, [")"] = true, ["["] = true, ["]"] = true, ["|"] = true, ["."] = true}
    if token.kind == "symbol" and delimiters[token.value] then return token.value end
    if token.kind == "command" and (token.value == "\\{" or token.value == "\\}") then return token.value end
    Lexer.fail(token.column, "invalid delimiter")
end

function Parser:nucleus()
    local token = self:take()
    local kind = token.kind
    if Parser.atom_kinds[kind] then return Parser.node(kind, nil, token.value, token.column) end
    if kind == "eqref" then return Parser.node("reference", nil, token.value, token.column) end
    if kind == "{" then
        local elements = self:element_list()
        if self:peek().kind ~= "}" then self:unexpected() end
        self:take()
        return Parser.collapse(elements)
    end
    if kind == "frac" or kind == "binom" or kind == "overset" or kind == "underset" then
        local first = self:argument("\\" .. kind)
        local second = self:argument("\\" .. kind)
        return Parser.node(kind, {first, second})
    end
    if kind == "sqrt" then
        local index
        if self:peek().kind == "symbol" and self:peek().value == "[" then
            local opening = self:take()
            local elements = self:element_list(false, true)
            if self:peek().kind ~= "symbol" or self:peek().value ~= "]" then Lexer.fail(opening.column, "missing ]") end
            self:take()
            index = Parser.collapse(elements)
        end
        local body = self:argument("\\sqrt")
        return index and Parser.node("root", {index, body}) or Parser.node("sqrt", {body})
    end
    if kind == "accent" then return Parser.node("accent", {self:argument("\\" .. token.value)}, token.value) end
    if kind == "left" then
        local left = self:delimiter()
        local elements = self:element_list()
        if self:peek().kind ~= "right" then Lexer.fail(token.column, "missing \\right") end
        local closing = self:take()
        local right = self:delimiter()
        return Parser.node("delim", {Parser.collapse(elements)}, {left, right}, closing.column)
    end
    return self:matrix(token.value, token.column)
end

function Parser:matrix(environment, column)
    local rows = {{}}
    while true do
        local row = rows[#rows]
        row[#row + 1] = Parser.collapse(self:element_list())
        local token = self:take()
        if token.kind == "newline" then rows[#rows + 1] = {}
        elseif token.kind ~= "&" then
            if token.kind ~= "end" then Lexer.fail(column, "missing \\end") end
            if token.value ~= environment then Lexer.fail(token.column, "mismatched \\end") end
            break
        end
    end
    local last = rows[#rows]
    if #rows >= 2 and #last == 1 and last[1].kind == "row" and #last[1].children == 0 then rows[#rows] = nil end
    local columns = 0
    for _, row in ipairs(rows) do columns = math.max(columns, #row) end
    for _, row in ipairs(rows) do while #row < columns do row[#row + 1] = Parser.node("row") end end
    return Parser.node("matrix", rows, environment)
end

return Parser
