local D = require("doc_builder")
local lexer = require("lexer")
local parse = require("parser")
local printer = require("printer")
local report = require("report")
local F = {}
F.__index = F
local C, H, L, SL = D.concat, D.hardline, D.line, D.softline

local function attach(tokens, items)
    local before, next_token, following = false, {}, false
    for i = #items, 1, -1 do
        next_token[i] = following
        if items[i].index then following = items[i] end
    end
    for i, entry in ipairs(items) do
        if entry.index then before = entry
        else
            local after, next_item = next_token[i], items[i + 1]
            entry.own_line = entry.kind == "line_comment" or not next_item or next_item.line > entry.line
            local destination
            if before and before.line == entry.line and (not after or after.line > entry.line) then
                destination = before.trailing
            else destination = (after or tokens[#tokens]).leading end
            destination[#destination + 1] = entry
        end
    end
    for _, entry in ipairs(tokens) do entry.had_trailing = #entry.trailing > 0 end
end
local function check_comments(tokens)
    for _, tok in ipairs(tokens) do
        for _, comment in ipairs(tok.leading) do
            if tok.trailing_comma or (comment.own_line and not tok.allowed) then
                lexer.fail(comment.line, comment.column, "comment not allowed here")
            end
        end
    end
end
local function pre_blank(tok)
    return tok.leading[1] and tok.leading[1].blank or tok.blank
end

function F:sep(blank)
    local parts = { H }
    for _ = 1, math.min(blank, self.profile.max_blank_lines) do parts[#parts + 1] = H end
    return C(parts)
end
function F:comments(comments, following)
    local parts = {}
    for i, comment in ipairs(comments) do
        parts[#parts + 1] = comment.text
        local next_entry = comments[i + 1] or following
        if next_entry then
            if comment.own_line then parts[#parts + 1] = self:sep(next_entry.blank)
            else parts[#parts + 1] = " " end
        end
    end
    return C(parts)
end
local function suffix(comments)
    if #comments == 0 then return false end
    local parts = {}
    for _, comment in ipairs(comments) do parts[#parts + 1] = comment.text end
    return D.suffix(table.concat(parts, " "))
end
function F:t(tok, leading)
    return C(self:comments(leading or tok.leading, tok), tok.text, suffix(tok.trailing))
end
function F:split(close)
    local last, own, inline = 0, {}, {}
    for i, comment in ipairs(close.leading) do if comment.own_line then last = i end end
    for i, comment in ipairs(close.leading) do
        local target = i <= last and own or inline
        target[#target + 1] = comment
    end
    return own, inline
end
function F:closing(comments, preceding)
    if #comments == 0 then return false end
    return C(preceding and self:sep(comments[1].blank), self:comments(comments, false))
end
function F:whole(items, ending)
    local parts = {}
    for i, item in ipairs(items) do
        if i > 1 then parts[#parts + 1] = self:sep(pre_blank(item.first)) end
        local doc = self:item(item)
        parts[#parts + 1] = doc
        if item.tag == "function" and not self.first_doc then
            self.first_doc, self.first_name = doc, item.name.text
        end
    end
    if #ending.leading > 0 then
        if #items > 0 then parts[#parts + 1] = self:sep(ending.leading[1].blank) end
        parts[#parts + 1] = self:comments(ending.leading, false)
    end
    return C(parts)
end
function F:item(item)
    if item.tag ~= "function" then return self:variable(item) end
    return C(self:t(item.typ), " ", self:t(item.name), self:list(item.parameters), H, self:block(item.body))
end
function F:parameter(item)
    local parts = { self:t(item.typ), " ", self:t(item.name) }
    for _, bracket in ipairs(item.brackets) do
        parts[#parts + 1], parts[#parts + 2] = self:t(bracket[1]), self:t(bracket[2])
    end
    return C(parts)
end
function F:variable(item)
    local parts = { self:t(item.typ), " ", self:t(item.name) }
    for _, dim in ipairs(item.dimensions) do
        parts[#parts + 1] = self:t(dim[1])
        if dim[2] then parts[#parts + 1] = self:expr(dim[2], 0) end
        parts[#parts + 1] = self:t(dim[3])
    end
    if item.equals then
        parts[#parts + 1] = C(self.space, self:t(item.equals), self.space, self:initializer(item.initializer))
    end
    if item.semi then parts[#parts + 1] = self:t(item.semi) end
    return C(parts)
end
function F:initializer(item)
    if item.tag == "list" then return self:list(item) end
    return self:expr(item, 0)
end
function F:list(item)
    local marker = false
    for i = item.left.index, item.right.index - 1 do
        if self.tokens[i].had_trailing then marker = D.break_parent; break end
    end
    local elements = {}
    for _, element in ipairs(item.elements) do
        if element.tag == "parameter" then elements[#elements + 1] = self:parameter(element)
        elseif item.role == "{" then elements[#elements + 1] = self:initializer(element)
        else elements[#elements + 1] = self:expr(element, 0) end
    end
    if #elements == 0 then return C(self:t(item.left), self:t(item.right)) end
    local inner = { SL, elements[1] }
    for i = 2, #elements do
        inner[#inner + 1] = C(self:t(item.commas[i - 1]), L, elements[i])
    end
    if item.role == "{" then
        inner[#inner + 1] = D.if_break(",", "")
        if item.trailing then inner[#inner + 1] = suffix(item.trailing.trailing) end
    end
    return D.group(C(marker, self:t(item.left), D.nest(self.indent, C(inner)), SL, self:t(item.right)))
end
function F:block(item)
    local own, inline = self:split(item.right)
    if #item.statements == 0 and #own == 0 then return C(self:t(item.left), self:t(item.right, inline)) end
    local body = { H }
    for i, statement in ipairs(item.statements) do
        if i > 1 then body[#body + 1] = self:sep(pre_blank(statement.first)) end
        body[#body + 1] = self:statement(statement)
    end
    body[#body + 1] = self:closing(own, #item.statements > 0)
    return C(self:t(item.left), D.nest(self.indent, C(body)), H, self:t(item.right, inline))
end
function F:body(item)
    local prefix = self.kr and " " or H
    if item.tag == "block" then return C(prefix, self:block(item)) end
    if self.profile.add_braces then
        return C(prefix, "{", D.nest(self.indent, C(H, self:statement(item))), H, "}")
    end
    return D.nest(self.indent, C(H, self:statement(item)))
end
function F:simple(item)
    if item.tag ~= "assign" then return self:expr(item.expr, 0) end
    return C(self:expr(item.left, 0), self.space, self:t(item.op), self.space, self:expr(item.right, 0))
end
function F:conditional_statement(item)
    local parts = { self:t(item.keyword), self.keyword_gap, self:t(item.left),
        self:expr(item.test, 0), self:t(item.right), self:body(item.body) }
    if item.else_token then
        local gap = self.kr and (item.body.tag == "block" or self.profile.add_braces) and " " or H
        parts[#parts + 1] = C(gap, self:t(item.else_token))
        if item.alternative.tag == "if" then
            parts[#parts + 1] = C(" ", self:conditional_statement(item.alternative))
        else parts[#parts + 1] = self:body(item.alternative) end
    end
    return C(parts)
end
function F:for_statement(item)
    local contents = {}
    if item.initial then
        contents[#contents + 1] = item.initial.tag == "variable" and self:variable(item.initial) or self:simple(item.initial)
    end
    contents[#contents + 1] = self:t(item.first_semi)
    if item.condition then contents[#contents + 1] = C(L, self:expr(item.condition, 0)) end
    contents[#contents + 1] = self:t(item.second_semi)
    if item.update then contents[#contents + 1] = C(L, self:simple(item.update)) end
    return C(self:t(item.keyword), self.keyword_gap, self:t(item.left), D.group(D.align(C(contents))),
        self:t(item.right), self:body(item.body))
end
function F:clause(item)
    local parts = { self:t(item.label) }
    if item.value then parts[#parts + 1] = C(" ", self:expr(item.value, 0)) end
    parts[#parts + 1] = self:t(item.colon)
    if #item.statements > 0 then
        local inner = { H }
        for i, statement in ipairs(item.statements) do
            if i > 1 then inner[#inner + 1] = self:sep(pre_blank(statement.first)) end
            inner[#inner + 1] = self:statement(statement)
        end
        parts[#parts + 1] = D.nest(self.indent, C(inner))
    end
    return C(parts)
end
function F:switch_statement(item)
    local own, inline = self:split(item.closing)
    local header = C(self:t(item.keyword), self.keyword_gap, self:t(item.left), self:expr(item.test, 0),
        self:t(item.right), self.kr and " " or H, self:t(item.opening))
    if #item.clauses == 0 and #own == 0 then return C(header, self:t(item.closing, inline)) end
    local inner = { H }
    for i, clause in ipairs(item.clauses) do
        if i > 1 then inner[#inner + 1] = self:sep(pre_blank(clause.first)) end
        inner[#inner + 1] = self:clause(clause)
    end
    inner[#inner + 1] = self:closing(own, #item.clauses > 0)
    return C(header, D.nest(self.profile.indent_case_labels and self.indent or 0, C(inner)),
        H, self:t(item.closing, inline))
end
function F:statement(item)
    local tag = item.tag
    if tag == "block" then return self:block(item)
    elseif tag == "variable" then return self:variable(item)
    elseif tag == "simple_stmt" then return C(self:simple(item.value), self:t(item.semi))
    elseif tag == "return" then
        return C(self:t(item.keyword), item.expr and C(" ", self:expr(item.expr, 0)), self:t(item.semi))
    elseif tag == "flow" then return C(self:t(item.keyword), self:t(item.semi))
    elseif tag == "if" then return self:conditional_statement(item)
    elseif tag == "while" then
        return C(self:t(item.keyword), self.keyword_gap, self:t(item.left), self:expr(item.test, 0),
            self:t(item.right), self:body(item.body))
    elseif tag == "for" then return self:for_statement(item)
    elseif tag == "switch" then return self:switch_statement(item) end
    error("unexpected statement " .. tag)
end
function F:last(item)
    local tag = item.tag
    if tag == "primary" then return item.value
    elseif tag == "paren" or tag == "index" then return item.right
    elseif tag == "member" then return item.member
    elseif tag == "call" then return item.arguments.right
    elseif tag == "unary" then return self:last(item.operand)
    elseif tag == "binary" then return self:last(item.right)
    elseif tag == "conditional" then return self:last(item.no) end
end
function F:opened(item, minimum)
    while self.profile.remove_parens and item.tag == "paren" do
        if (item.inner.level or 8) < minimum or #item.left.leading > 0 or #item.right.leading > 0 then break end
        local first, last = item.inner.first, self:last(item.inner)
        if #item.left.trailing > 0 then
            local merged = {}
            for _, comment in ipairs(item.left.trailing) do merged[#merged + 1] = comment end
            for _, comment in ipairs(first.trailing) do merged[#merged + 1] = comment end
            first.trailing, item.left.trailing = merged, {}
        end
        for _, comment in ipairs(item.right.trailing) do last.trailing[#last.trailing + 1] = comment end
        item.right.trailing = {}
        item = item.inner
    end
    return item
end
function F:binary(item)
    local level, operators, operands = item.level, {}, {}
    local current = item
    while current.tag == "binary" and current.level == level do
        operators[#operators + 1], operands[#operands + 1] = current.op, current.right
        current = self:opened(current.left, level)
    end
    local contents = {}
    for i = #operators, 1, -1 do
        contents[#contents + 1] = C(self.operator_break, self:t(operators[i]), self.space, self:expr(operands[i], level + 1))
    end
    return D.group(C(self:expr(current, level), D.nest(self.indent, C(contents))))
end
function F:conditional(item)
    local contents, current = {}, item
    while true do
        contents[#contents + 1] = C(self.operator_break, self:t(current.question), self.space,
            self:expr(current.yes, 0), self.operator_break, self:t(current.colon), self.space)
        local following = self:opened(current.no, 0)
        if following.tag ~= "conditional" then
            contents[#contents + 1] = self:expr(following, 0)
            break
        end
        contents[#contents + 1] = self:expr(following.test, 1)
        current = following
    end
    return D.group(C(self:expr(item.test, 1), D.nest(self.indent, C(contents))))
end
function F:postfix_piece(item)
    if item.tag == "call" then return self:list(item.arguments)
    elseif item.tag == "index" then return C(self:t(item.left), self:expr(item.index, 0), self:t(item.right)) end
    return C(self:t(item.dot), self:t(item.member))
end
function F:postfix(item)
    local reversed, current = {}, item
    while current.tag == "call" or current.tag == "index" or current.tag == "member" do
        reversed[#reversed + 1] = current
        current = self:opened(current.target, 8)
    end
    local segments, calls = { {} }, {}
    for i = #reversed, 1, -1 do
        local operation = reversed[i]
        if operation.tag == "member" then segments[#segments + 1] = {} end
        local segment = segments[#segments]
        segment[#segment + 1] = operation
    end
    for i = 2, #segments do
        for _, operation in ipairs(segments[i]) do
            if operation.tag == "call" then calls[#calls + 1] = i; break end
        end
    end
    local head = self:expr(current, 8)
    if #calls < 2 then
        local parts = { head }
        for i = #reversed, 1, -1 do parts[#parts + 1] = self:postfix_piece(reversed[i]) end
        return C(parts)
    end
    local before, after = { head }, {}
    for i, segment in ipairs(segments) do
        local target = i < calls[1] and before or after
        if i >= calls[1] then target[#target + 1] = SL end
        for _, operation in ipairs(segment) do target[#target + 1] = self:postfix_piece(operation) end
    end
    return D.group(C(before, D.nest(self.indent, C(after))))
end
function F:expr(item, minimum)
    item = self:opened(item, minimum)
    local tag = item.tag
    if tag == "primary" then return self:t(item.value)
    elseif tag == "paren" then return C(self:t(item.left), self:expr(item.inner, 0), self:t(item.right))
    elseif tag == "unary" then return C(self:t(item.op), self:expr(item.operand, 8))
    elseif tag == "binary" then return self:binary(item)
    elseif tag == "conditional" then return self:conditional(item) end
    return self:postfix(item)
end

local function render(lines, profile)
    local tokens, comments, source_items = lexer.lex(lines)
    attach(tokens, source_items)
    local items = parse(tokens)
    check_comments(tokens)
    local formatter = setmetatable({ profile = profile, tokens = tokens, indent = profile.indent,
        space = profile.space_around_operators and " " or "",
        operator_break = profile.space_around_operators and L or SL,
        keyword_gap = profile.space_after_keyword and " " or "", kr = profile.brace_style == "kr" }, F)
    if #items == 0 and #tokens[#tokens].leading == 0 then
        return { lines = {}, comments = comments }
    end
    local document = formatter:whole(items, tokens[#tokens])
    return { lines = printer.layout(document, profile), comments = comments, document = document,
        first_doc = formatter.first_doc, first_name = formatter.first_name }
end
local function format(file, profile)
    local original = {}
    for _, line in ipairs(file.lines) do original[#original + 1] = line:gsub(" +$", "") end
    local ok, first = pcall(render, file.lines, profile)
    file.original, file.diagnostics = original, {}
    if not ok then
        if type(first) ~= "table" then error(first) end
        file.error, file.formatted = first, original
        file.idempotency = file.filename .. ": skipped (syntax error)"
        file.diagnostics[1] = string.format("%s:%d:%d: error: %s", file.filename, first.line, first.column, first.message)
        return file
    end
    file.first, file.formatted = first, first.lines
    local second_ok, second = pcall(render, first.lines, profile)
    if not second_ok then
        if type(second) ~= "table" then error(second) end
        file.idempotency = string.format("%s: unstable (second pass: %d:%d: %s)",
            file.filename, second.line, second.column, second.message)
    else
        local different = false
        for i = 1, math.max(#first.lines, #second.lines) do
            if first.lines[i] ~= second.lines[i] then different = i; break end
        end
        file.idempotency = file.filename .. (different and ": unstable at line " .. different or ": stable")
    end
    for i, line in ipairs(first.lines) do
        if #line > profile.width then
            file.diagnostics[#file.diagnostics + 1] = string.format("%s:%d: warning: line too long (%d > %d)",
                file.filename, i, #line, profile.width)
        end
    end
    return file
end
local profiles, profile = {}, false
local numeric = { width = true, indent = true, max_blank_lines = true, comment_column = true }
for line in io.lines("input/style.txt") do
    local name = line:match("^%[(.+)%]$")
    if name then profile = {}; profiles[name] = profile
    elseif line ~= "" then
        local key, value = line:match("^([^=]+)=(.*)$")
        if numeric[key] then value = tonumber(value)
        elseif key ~= "brace_style" then value = value == "yes" end
        profile[key] = value
    end
end
local files, file = {}, false
for line in io.lines("input/sources.txt") do
    local filename, name = line:match("^=== ([^ ]+) ([^ ]+)$")
    if filename then
        file = { header = line, filename = filename, profile = name, lines = {} }
        files[#files + 1] = file
    else file.lines[#file.lines + 1] = line end
end
local formatted, idempotency, diagnostics, trees, changes = {}, {}, {}, {}, {}
local function append(target, source)
    for _, line in ipairs(source) do target[#target + 1] = line end
end
for _, source in ipairs(files) do
    local result = format(source, profiles[source.profile])
    formatted[#formatted + 1] = source.header
    append(formatted, result.formatted)
    idempotency[#idempotency + 1] = result.idempotency
    append(diagnostics, result.diagnostics)
    trees[#trees + 1], changes[#changes + 1] = "=== " .. source.filename, "=== " .. source.filename
    if result.error then
        trees[#trees + 1], changes[#changes + 1] = "syntax error", "skipped (syntax error)"
    else
        local first, longest, broken, forced = result.first, 0, 0, 0
        for _, line in ipairs(first.lines) do longest = math.max(longest, #line) end
        local groups = D.groups(first.document)
        for _, group in ipairs(groups) do
            if group.mode == "break" or group.mode == "forced" then broken = broken + 1 end
            if group.mode == "forced" then forced = forced + 1 end
        end
        trees[#trees + 1] = string.format("metrics lines=%d longest=%d comments=%d groups=%d broken=%d forced=%d",
            #first.lines, longest, #first.comments, #groups, broken, forced)
        if first.first_doc then
            trees[#trees + 1] = "function " .. first.first_name
            append(trees, report.tree(first.first_doc))
        else trees[#trees + 1] = "no function" end
        append(changes, report.diff(result.original, result.formatted))
    end
end
if #diagnostics == 0 then diagnostics[1] = "no diagnostics" end
local function write(filename, lines)
    local target = assert(io.open("output/" .. filename, "w"))
    if #lines > 0 then target:write(table.concat(lines, "\n"), "\n") end
    target:close()
end
write("formatted.txt", formatted)
write("idempotency.txt", idempotency)
write("diagnostics.txt", diagnostics)
write("doc_tree.txt", trees)
write("changes.txt", changes)
