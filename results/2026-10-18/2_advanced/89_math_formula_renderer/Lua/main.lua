local Lexer = require("lexer")
local Parser = require("parser")
local Box = require("boxes")
local Layout = require("layout")
local Canvas = require("canvas")
local Typesetter = {}
Typesetter.__index = Typesetter
local atom_kinds = {identifier = true, number = true, symbol = true, command = true, text = true, reference = true}
local stacked_commands = {["\\sum"] = true, ["\\prod"] = true, ["\\lim"] = true, ["\\max"] = true, ["\\min"] = true}
local brace_accents = {overbrace = true, underbrace = true}
local delimiter_pairs = {["("] = ")", ["["] = "]", ["|"] = "|", ["\\{"] = "\\}"}

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function formula(number, line)
    local result = {number = number, line = line, nodes = {}, warnings = {}}
    local ok, failure = pcall(function()
        result.tokens = Lexer.tokenize(line)
        Parser.check_braces(result.tokens)
        local reader = Parser.new(result.tokens)
        result.nodes = reader:parse()
        result.tag, result.label = reader.tag, reader.label
    end)
    if not ok then
        if type(failure) ~= "table" or not failure.message then error(failure, 0) end
        result.error = failure
    end
    return result
end

local function read_inputs()
    local parameters, formulas = {}, {}
    for line in io.lines("input/params.txt") do
        local name, value = line:match("^(%S+) (%d+)$")
        parameters[name] = tonumber(value)
    end
    for line in io.lines("input/formulas.txt") do append(formulas, formula(#formulas + 1, line)) end
    return parameters, formulas
end

local function reference_table(formulas)
    local counter, references = 0, {}
    for _, formula in ipairs(formulas) do
        if not formula.error then
            if formula.tag then formula.tag_string = "(" .. formula.tag.value .. ")"
            elseif formula.label then counter = counter + 1; formula.tag_string = "(" .. counter .. ")" end
        end
    end
    for _, formula in ipairs(formulas) do
        if not formula.error and formula.label then
            local label = formula.label
            if references[label.value] then append(formula.warnings, {column = label.column, message = 'duplicate label "' .. label.value .. '"'})
            else references[label.value] = formula.tag_string end
        end
    end
    return references
end

local function walk_nodes(node, callback)
    callback(node)
    if node.kind == "matrix" then
        for _, row in ipairs(node.children) do for _, cell in ipairs(row) do walk_nodes(cell, callback) end end
    else for _, child in ipairs(node.children) do if child then walk_nodes(child, callback) end end end
end

local function collect_warnings(formula, references)
    for _, element in ipairs(formula.nodes) do
        walk_nodes(element, function(node)
            local message
            if node.kind == "identifier" and Lexer.command_names[node.value] then message = node.value .. " is a command name; write \\" .. node.value
            elseif node.kind == "reference" and not references[node.value] then message = 'undefined reference "' .. node.value .. '"'
            elseif node.kind == "delim" then
                local left, right = node.value[1], node.value[2]
                if left ~= "." and right ~= "." and delimiter_pairs[left] ~= right then message = "\\left" .. left .. " closed by \\right" .. right end
            end
            if message then append(formula.warnings, {column = node.column, message = message}) end
        end)
    end
    table.sort(formula.warnings, function(a, b) return a.column < b.column end)
end

local function center(box, width)
    return (width - box.width) // 2
end

local function draw_delimiter(box, delimiter, x, height)
    for y, character in ipairs(Box.delimiter_glyph(delimiter, height)) do box:draw(character, x, y - 1) end
end

local function delimiter_string(delimiter)
    return delimiter == "." and "" or delimiter:sub(-1)
end

function Typesetter.new(parameters, references)
    return setmetatable({parameters = parameters, references = references}, Typesetter)
end

function Typesetter:typeset(node, style)
    style = style or "normal"
    if atom_kinds[node.kind] then return self:atom(node, style) end
    return self[node.kind](self, node, style)
end

function Typesetter:atom(node, style)
    local display, description
    if node.kind == "text" then description, display = 'text "' .. node.value .. '"', node.value
    elseif node.kind == "reference" then description, display = 'eqref "' .. node.value .. '"', self.references[node.value] or "(??)"
    else description, display = 'atom "' .. node.value .. '"', node.kind == "command" and Box.command_display[node.value] or node.value end
    local glyph = node.kind == "command" and Box.large_glyphs[node.value] or nil
    local result
    if glyph and style == "normal" then
        result = Box.new(#glyph[1], 3, 1, description)
        for y, line in ipairs(glyph) do result:draw(line, 0, y - 1) end
    else result = Box.new(#display, 1, 0, description); result:draw(display) end
    return result
end

function Typesetter:row(node, style)
    local _, gaps = Layout.spacing(node.children, style, self.parameters)
    local children = {}
    for _, child in ipairs(node.children) do append(children, self:typeset(child, style)) end
    return Layout.row(children, gaps)
end

function Typesetter:script(node, style)
    local base_node, sub_node, sup_node = node.children[1], node.children[2], node.children[3]
    local base = self:typeset(base_node, style)
    local sub, sup = sub_node and self:typeset(sub_node, "script") or nil, sup_node and self:typeset(sup_node, "script") or nil
    local sw, sh, pw, ph = sub and sub.width or 0, sub and sub.height or 0, sup and sup.width or 0, sup and sup.height or 0
    local stacked = style == "normal" and ((base_node.kind == "command" and stacked_commands[base_node.value])
        or (base_node.kind == "accent" and brace_accents[base_node.value]))
    if stacked then
        local width = math.max(base.width, sw, pw)
        local result = Box.new(width, ph + base.height + sh, ph + base.baseline, "limits")
        result:add(base, center(base, width), ph, "base: ")
        if sub then result:add(sub, center(sub, width), ph + base.height, "sub: ") end
        if sup then result:add(sup, center(sup, width), 0, "sup: ") end
        return result
    end
    local sup_top = (base.baseline == 0 and -1 or 0) - ph + 1
    local sub_top = base:descent() == 0 and base.height or base.height - 1
    local top = sup and math.min(0, sup_top) or 0
    local bottom = sub and math.max(base.height - 1, sub_top + sh - 1) or base.height - 1
    local result = Box.new(base.width + math.max(sw, pw), bottom - top + 1, base.baseline - top, "scripts")
    result:add(base, 0, -top, "base: ")
    if sub then result:add(sub, base.width, sub_top - top, "sub: ") end
    if sup then result:add(sup, base.width, sup_top - top, "sup: ") end
    return result
end

function Typesetter:frac(node, style)
    local numerator = self:typeset(node.children[1], style)
    local denominator = self:typeset(node.children[2], style)
    if style == "normal" then
        local width = math.max(numerator.width, denominator.width) + 2
        local result = Box.new(width, numerator.height + 1 + denominator.height, numerator.height, "frac")
        result:add(numerator, center(numerator, width), 0, "num: ")
        result:add(denominator, center(denominator, width), numerator.height + 1, "den: ")
        result:draw(string.rep("-", width), 0, numerator.height)
        return result
    end
    if node.children[1].kind == "row" or node.children[1].kind == "frac" then numerator = self:delimit(numerator, "(", ")") end
    if node.children[2].kind == "row" or node.children[2].kind == "frac" then denominator = self:delimit(denominator, "(", ")") end
    local slash = Box.new(1, 1, 0, 'atom "/"')
    slash:draw("/")
    return Layout.row({numerator, slash, denominator}, {0, 0}, "slash", {"num: ", "", "den: "})
end

function Typesetter:binom(node, style)
    local upper, lower = self:typeset(node.children[1], style), self:typeset(node.children[2], style)
    local width, height = math.max(upper.width, lower.width), upper.height + 1 + lower.height
    local result = Box.new(width + 2, height, upper.height, "binom")
    result:add(upper, center(upper, width) + 1, 0, "upper: ")
    result:add(lower, center(lower, width) + 1, upper.height + 1, "lower: ")
    draw_delimiter(result, "(", 0, height)
    draw_delimiter(result, ")", width + 1, height)
    return result
end

function Typesetter:overset(node, style)
    local placed, base = self:typeset(node.children[1], "script"), self:typeset(node.children[2], style)
    local width = math.max(placed.width, base.width)
    local result = Box.new(width, placed.height + base.height, placed.height + base.baseline, "overset")
    result:add(placed, center(placed, width), 0, "over: ")
    result:add(base, center(base, width), placed.height, "base: ")
    return result
end

function Typesetter:underset(node, style)
    local placed, base = self:typeset(node.children[1], "script"), self:typeset(node.children[2], style)
    local width = math.max(placed.width, base.width)
    local result = Box.new(width, base.height + placed.height, base.baseline, "underset")
    result:add(base, center(base, width), 0, "base: ")
    result:add(placed, center(placed, width), base.height, "under: ")
    return result
end

function Typesetter:radical(body, index)
    local height = body.height
    local extra, top = index and math.max(0, index.width - 1) or 0, index and math.max(0, index.height - height) or 0
    local result = Box.new(extra + height + 1 + body.width, height + 1 + top, body.baseline + 1 + top, index and "root" or "sqrt")
    result:draw(string.rep("_", body.width), extra + height + 1, top)
    result:draw("\\", extra, height + top)
    for row = 1, height do result:draw("/", extra + height - row + 1, row + top) end
    if index then
        result:add(index, 0, height - index.height + top, "index: ")
        result:add(body, extra + height + 1, 1 + top, "body: ")
    else result:add(body, extra + height + 1, 1) end
    return result
end

function Typesetter:sqrt(node, style)
    return self:radical(self:typeset(node.children[1], style))
end

function Typesetter:root(node, style)
    local index = self:typeset(node.children[1], "script")
    local body = self:typeset(node.children[2], style)
    return self:radical(body, index)
end

function Typesetter:delimit(body, left, right)
    local left_width, right_width = left == "." and 0 or 1, right == "." and 0 or 1
    local result = Box.new(left_width + body.width + right_width, body.height, body.baseline, "delim " .. left .. " " .. right)
    result:add(body, left_width, 0)
    draw_delimiter(result, left, 0, body.height)
    draw_delimiter(result, right, left_width + body.width, body.height)
    return result
end

function Typesetter:delim(node, style)
    return self:delimit(self:typeset(node.children[1], style), node.value[1], node.value[2])
end

function Typesetter:matrix(node, style)
    local cells, widths, ascents, heights, body_width, body_height = {}, {}, {}, {}, 0, 0
    local row_count, column_count = #node.children, #node.children[1]
    for i, row in ipairs(node.children) do
        cells[i] = {}
        local ascent, descent = 0, 0
        for j, child in ipairs(row) do
            local cell = self:typeset(child, style)
            cells[i][j], widths[j] = cell, math.max(widths[j] or 0, cell.width)
            ascent, descent = math.max(ascent, cell.baseline), math.max(descent, cell:descent())
        end
        ascents[i], heights[i] = ascent, ascent + descent + 1
        body_height = body_height + heights[i]
    end
    for _, width in ipairs(widths) do body_width = body_width + width end
    body_width, body_height = body_width + self.parameters.col_gap * (column_count - 1), body_height + self.parameters.row_gap * (row_count - 1)
    local environment = node.value
    local shift = environment == "matrix" and 0 or 2
    local extra = environment == "matrix" and 0 or environment == "cases" and 2 or 4
    local result = Box.new(body_width + extra, body_height, (body_height - 1) // 2,
        string.format("%s rows=%d cols=%d", environment, row_count, column_count))
    local y = 0
    for i, row in ipairs(cells) do
        local x = shift
        for j, cell in ipairs(row) do
            local offset = environment == "cases" and 0 or center(cell, widths[j])
            result:add(cell, x + offset, y + ascents[i] - cell.baseline, string.format("cell %d,%d: ", i, j))
            x = x + widths[j] + self.parameters.col_gap
        end
        y = y + heights[i] + self.parameters.row_gap
    end
    if environment == "cases" then draw_delimiter(result, "\\{", 0, body_height)
    elseif environment ~= "matrix" then
        local delimiters = ({pmatrix = {"(", ")"}, bmatrix = {"[", "]"}, vmatrix = {"|", "|"}})[environment]
        draw_delimiter(result, delimiters[1], 0, body_height)
        draw_delimiter(result, delimiters[2], body_width + 3, body_height)
    end
    return result
end

function Typesetter:accent(node, style)
    local body, name = self:typeset(node.children[1], style), node.value
    local width = body.width
    if name == "hat" or name == "dot" or name == "tilde" then width = math.max(width, 1)
    elseif name == "vec" then width = math.max(width, 2)
    elseif brace_accents[name] then width = width + 2 end
    local baseline = name == "underbrace" and body.baseline or body.baseline + 1
    local result = Box.new(width, body.height + 1, baseline, name)
    if name == "underbrace" then
        result:add(body, 1, 0)
        result:draw("\\" .. string.rep("-", body.width) .. "/", 0, body.height)
    elseif name == "overbrace" then
        result:add(body, 1, 1)
        result:draw("/" .. string.rep("-", body.width) .. "\\")
    else
        result:add(body, 0, 1)
        if name == "overline" then result:draw(string.rep("_", width))
        elseif name == "vec" then result:draw(string.rep("-", width - 1) .. ">")
        else result:draw(({hat = "^", dot = ".", tilde = "~"})[name], (width - 1) // 2, 0) end
    end
    return result
end

local function build_lines(breaks, types, boxes, starts, parameters)
    local result, position, alignment = {}, 1, nil
    while position <= #boxes do
        local indentation
        if position == 1 then indentation = 0
        elseif not alignment then indentation = parameters.indent
        elseif types[position][1] == "relation" then indentation = alignment[1]
        else indentation = alignment[1] + alignment[2] + parameters.rel_space end
        local candidates = {}
        for finish = position + 1, #boxes do
            if breaks[finish] then append(candidates, {finish = finish - 1, width = starts[finish - 1] + boxes[finish - 1].width - starts[position]}) end
        end
        append(candidates, {finish = #boxes, width = starts[#boxes] + boxes[#boxes].width - starts[position]})
        local chosen
        for _, candidate in ipairs(candidates) do if indentation + candidate.width <= parameters.width then chosen = candidate end end
        chosen = chosen or candidates[1]
        append(result, {start = position, finish = chosen.finish, indentation = indentation, width = chosen.width})
        if position == 1 then
            for i = 1, chosen.finish do if types[i][1] == "relation" then alignment = {starts[i], boxes[i].width}; break end end
        end
        position = chosen.finish + 1
    end
    return result
end

local function place_formula(formula, typesetter, parameters)
    local nodes = formula.nodes
    local types, gaps = Layout.spacing(nodes, "normal", parameters)
    local boxes, starts, x = {}, {}, 0
    for i, node in ipairs(nodes) do
        local box = typesetter:typeset(node)
        boxes[i], starts[i] = box, x
        x = x + box.width + (gaps[i] or 0)
    end
    local relations, plus_minus, punctuation = {}, {}, {}
    for i = 2, #nodes do
        if types[i][1] == "relation" then relations[i] = true end
        if nodes[i].kind == "symbol" and (nodes[i].value == "+" or nodes[i].value == "-") and types[i][1] == "binary" then plus_minus[i] = true end
        if types[i - 1][2] == "punctuation" then punctuation[i] = true end
    end
    local plan, breaks = nil, {}
    for _, additions in ipairs({relations, plus_minus, punctuation}) do
        for index in pairs(additions) do breaks[index] = true end
        plan = build_lines(breaks, types, boxes, starts, parameters)
        local fitting = true
        for _, line in ipairs(plan) do if line.indentation + line.width > parameters.width then fitting = false; break end end
        if fitting then break end
    end
    local roots, overfull, width, height = {}, {}, 0, 0
    for number, item in ipairs(plan) do
        local children, line_gaps = {}, {}
        for i = item.start, item.finish do
            append(children, boxes[i])
            if i < item.finish then append(line_gaps, gaps[i]) end
        end
        local line = Layout.row(children, line_gaps, "line " .. number)
        append(roots, {box = line, x = item.indentation, y = height})
        height, width = height + line.height, math.max(width, item.indentation + line.width)
        if item.indentation + item.width > parameters.width then append(overfull, {number, item.indentation + item.width}) end
    end
    if formula.tag_string then
        local tag, last = formula.tag_string, roots[#roots]
        local tx, ty = parameters.width - #tag
        if tx >= last.x + last.box.width + 2 then ty = last.y + last.box.baseline else ty, height = height, height + 1 end
        local tag_box = Box.new(#tag, 1, 0, 'tag "' .. tag .. '"')
        tag_box:draw(tag)
        append(roots, {box = tag_box, x = tx, y = ty})
        width = math.max(width, tx + #tag)
    end
    return roots, #plan, width, height, overfull
end

local function tree_notation(node)
    local kind = node.kind
    if kind == "identifier" or kind == "number" or kind == "command" then return node.value end
    if kind == "symbol" then return "'" .. node.value .. "'" end
    if kind == "text" then return '"' .. node.value .. '"' end
    if kind == "reference" then return '(eqref "' .. node.value .. '")' end
    if kind == "row" then
        local parts = {"(row"}
        for _, child in ipairs(node.children) do append(parts, " " .. tree_notation(child)) end
        return table.concat(parts) .. ")"
    end
    if kind == "matrix" then
        local rows = {}
        for _, row in ipairs(node.children) do
            local cells = {}
            for _, cell in ipairs(row) do append(cells, tree_notation(cell)) end
            append(rows, "[" .. table.concat(cells, " ") .. "]")
        end
        return "(" .. node.value .. " " .. table.concat(rows, " ") .. ")"
    end
    if kind == "delim" then
        local delimiters = {}
        for _, value in ipairs(node.value) do append(delimiters, #value == 1 and "'" .. value .. "'" or value) end
        return "(delim " .. table.concat(delimiters, " ") .. " " .. tree_notation(node.children[1]) .. ")"
    end
    local name = kind == "accent" and node.value or kind
    if kind == "script" then name = not node.children[2] and "sup" or not node.children[3] and "sub" or "subsup" end
    local children = {}
    for _, child in ipairs(node.children) do if child then append(children, tree_notation(child)) end end
    return "(" .. name .. " " .. table.concat(children, " ") .. ")"
end

local Linear = {}
Linear.__index = Linear

function Linear.new(parameters, references)
    return setmetatable({parameters = parameters, references = references}, Linear)
end

function Linear:row(nodes, style)
    local _, gaps = Layout.spacing(nodes, style, self.parameters)
    local parts = {}
    for i, node in ipairs(nodes) do
        if i > 1 then append(parts, string.rep(" ", gaps[i - 1])) end
        append(parts, self:node(node, style))
    end
    return table.concat(parts)
end

function Linear:parenthesize(node, style, kinds)
    local value = self:node(node, style)
    return kinds[node.kind] and "(" .. value .. ")" or value
end

function Linear:node(node, style)
    style = style or "normal"
    local kind = node.kind
    if kind == "identifier" or kind == "number" or kind == "symbol" or kind == "text" then return node.value end
    if kind == "command" then return Box.command_display[node.value] end
    if kind == "reference" then return self.references[node.value] or "(??)" end
    if kind == "row" then return self:row(node.children, style) end
    if kind == "frac" then
        return self:parenthesize(node.children[1], style, {row = true, frac = true}) .. "/"
            .. self:parenthesize(node.children[2], style, {row = true, frac = true})
    end
    if kind == "script" then
        local result = self:parenthesize(node.children[1], style, {row = true, frac = true, script = true})
        if node.children[2] then result = result .. "_" .. self:parenthesize(node.children[2], "script", {row = true, frac = true}) end
        if node.children[3] then result = result .. "^" .. self:parenthesize(node.children[3], "script", {row = true, frac = true}) end
        return result
    end
    if kind == "delim" then return delimiter_string(node.value[1]) .. self:node(node.children[1], style) .. delimiter_string(node.value[2]) end
    if kind == "matrix" then
        local rows = {}
        for _, row in ipairs(node.children) do
            local cells = {}
            for _, cell in ipairs(row) do append(cells, self:node(cell, style)) end
            append(rows, table.concat(cells, ", "))
        end
        return node.value .. "[" .. table.concat(rows, "; ") .. "]"
    end
    if kind == "root" or kind == "overset" or kind == "underset" then
        return kind .. "(" .. self:node(node.children[1], "script") .. ", " .. self:node(node.children[2], style) .. ")"
    end
    local parts = {}
    for _, child in ipairs(node.children) do append(parts, self:node(child, style)) end
    return (kind == "accent" and node.value or kind) .. "(" .. table.concat(parts, ", ") .. ")"
end

local function diagnostic(formula, column, message, warning)
    return {string.format("formula %d, column %d: %s%s", formula.number, column, warning and "warning: " or "", message),
        "  " .. formula.line, string.rep(" ", column + 1) .. "^"}
end

local Reports = {}
Reports.__index = Reports

function Reports.new(parameters, formulas, references)
    return setmetatable({parameters = parameters, formulas = formulas, references = references,
        typesetter = Typesetter.new(parameters, references), linear = Linear.new(parameters, references), rendered = {},
        boxes = {}, trees = {}, errors = {}, box_kinds = {}, total_boxes = 0, max_depth = 0,
        valid_count = 0, error_count = 0, warning_count = 0, overfull_count = 0}, Reports)
end

function Reports:record_error(formula)
    self.error_count = self.error_count + 1
    append(self.rendered, "(error)")
    append(self.boxes, "formula " .. formula.number .. ": error")
    append(self.trees, "formula " .. formula.number .. ": error")
    extend(self.errors, diagnostic(formula, formula.error.column, formula.error.message, false))
end

function Reports:record_valid(formula)
    self.valid_count = self.valid_count + 1
    collect_warnings(formula, self.references)
    local roots, line_count, width, height, overfull = place_formula(formula, self.typesetter, self.parameters)
    extend(self.rendered, Canvas.draw(roots, width, height))
    local entries = Canvas.box_lines(roots)
    local depth = 0
    for _, entry in ipairs(entries) do depth = math.max(depth, entry.level + 1) end
    self.total_boxes, self.max_depth = self.total_boxes + #entries, math.max(self.max_depth, depth)
    append(self.boxes, string.format("formula %d: lines=%d width=%d height=%d boxes=%d depth=%d", formula.number,
        line_count, width, height, #entries, depth))
    for _, entry in ipairs(entries) do append(self.boxes, entry.line); self.box_kinds[entry.kind] = (self.box_kinds[entry.kind] or 0) + 1 end
    local tree = {}
    for _, node in ipairs(formula.nodes) do append(tree, tree_notation(node)) end
    local linear = self.linear:row(formula.nodes, "normal"):gsub(" +$", "")
    append(self.trees, "formula " .. formula.number .. ": " .. table.concat(tree, " "))
    append(self.trees, "  linear:" .. (linear == "" and "" or " " .. linear))
    if formula.tag_string then append(self.trees, "  tag: " .. formula.tag_string) end
    self.warning_count = self.warning_count + #formula.warnings
    for _, warning in ipairs(formula.warnings) do extend(self.errors, diagnostic(formula, warning.column, warning.message, true)) end
    self.overfull_count = self.overfull_count + #overfull
    for _, line in ipairs(overfull) do append(self.errors, string.format("formula %d: line %d is overfull (width %d > %d)",
        formula.number, line[1], line[2], self.parameters.width)) end
end

function Reports:build()
    for i, formula in ipairs(self.formulas) do
        if i > 1 then append(self.rendered, "") end
        append(self.rendered, "formula " .. formula.number)
        if formula.error then self:record_error(formula) else self:record_valid(formula) end
    end
    append(self.boxes, string.format("summary: boxes=%d max_depth=%d", self.total_boxes, self.max_depth))
    local kinds = {}
    for kind in pairs(self.box_kinds) do append(kinds, kind) end
    table.sort(kinds)
    for _, kind in ipairs(kinds) do append(self.boxes, "  " .. kind .. ": " .. self.box_kinds[kind]) end
    append(self.errors, string.format("formulas=%d rendered=%d errors=%d warnings=%d overfull=%d", #self.formulas,
        self.valid_count, self.error_count, self.warning_count, self.overfull_count))
end

function Reports:write()
    assert(os.execute("mkdir -p output"))
    for _, report in ipairs({{"rendered.txt", self.rendered}, {"boxes.txt", self.boxes}, {"trees.txt", self.trees}, {"errors.txt", self.errors}}) do
        local file = assert(io.open("output/" .. report[1], "wb"))
        for _, line in ipairs(report[2]) do file:write(line, "\n") end
        file:close()
    end
end

local parameters, formulas = read_inputs()
local references = reference_table(formulas)
local reports = Reports.new(parameters, formulas, references)
reports:build()
reports:write()
