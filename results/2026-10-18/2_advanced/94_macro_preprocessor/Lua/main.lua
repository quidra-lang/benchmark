local L = require("lexer")
local D = require("definitions")
local Expression = require("expression")
local Expander = require("expander")
local Manager = require("include_manager")
local P = {}
P.__index = P
local I = {}
I.__index = I
function I:position(physical) return { self.display_file, physical + self.offset } end
function I:skipping() return #self.stack > 0 and not self.stack[#self.stack].active end
local function append(target, source)
    for _, value in ipairs(source) do target[#target + 1] = value end
end
local function slice(values, first, last)
    local result = {}
    for i = first, last or #values do result[#result + 1] = values[i] end
    return result
end
local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function following(heading, items)
    return heading .. (#items > 0 and " " .. table.concat(items, " ") or "")
end
local function fail(message) error({ category = "directive", message = message }, 0) end
local function header_specification(tokens, position)
    position = position or 1
    local token = tokens[position]
    if not token then return false, position end
    if token.kind == "string" or token.kind == "header" then
        local text = token.spelling
        return { rendering = text, name = text:sub(2, -2), quoted = text:sub(1, 1) == '"' }, position + 1
    elseif token.spelling == "<" then
        local closing = position + 1
        while tokens[closing] and tokens[closing].spelling ~= ">" do closing = closing + 1 end
        if not tokens[closing] then fail("missing terminating > character") end
        local text = "<" .. L.render(slice(tokens, position + 1, closing - 1)) .. ">"
        return { rendering = text, name = text:sub(2, -2), quoted = false }, closing + 1
    end
    return false, position
end
local function output_render(tokens)
    local parts, previous = {}, false
    for _, token in ipairs(tokens) do
        if previous then
            local _, _, ending = L.read_token(previous .. token.spelling)
            local ch = token.spelling:sub(1, 1)
            local separator = (previous == "/" and (ch == "/" or ch == "*")) or ending ~= #previous + 1
            if token.space or separator then parts[#parts + 1] = " " end
        end
        parts[#parts + 1], previous = token.spelling, token.spelling
    end
    return table.concat(parts)
end
local function decimal_token(token) return token and token.kind == "number" and token.spelling:match("^[0-9]+$") ~= nil end
function P.new()
    local result = setmetatable({ macros = {}, ever_defined = {}, saved = {}, poisoned = {}, manager = Manager.new(),
        output = {}, history = {}, diagnostics = {}, tree = { "main.c" }, conditional_records = {}, regions = {},
        diagnostic_counts = { error = 0, warning = 0 },
        condition_counts = { taken = 0, not_taken = 0, skipped = 0, not_evaluated = 0, endif = 0 } }, P)
    result.expander = Expander.new(result.macros, function(position, kind, message) result:diagnostic(position, kind, message) end)
    return result
end
function P:diagnostic(position, kind, message)
    self.diagnostics[#self.diagnostics + 1] = string.format("%s:%d: %s: %s", position[1], position[2], kind, message)
    self.diagnostic_counts[kind] = self.diagnostic_counts[kind] + 1
end
function P:event(position, content) self.history[#self.history + 1] = string.format("%s:%d: %s", position[1], position[2], content) end
function P:poison_check(context, tokens)
    for _, token in ipairs(tokens) do
        if token.kind == "identifier" and self.poisoned[token.spelling] then
            self:diagnostic(context:position(token.line), "error", 'attempt to use poisoned "' .. token.spelling .. '"')
        end
    end
end
function P:unused_check(macro)
    if macro.main_file and macro.expanded == 0 and macro.tested == 0 then
        self:diagnostic(macro.position, "warning", 'macro "' .. macro.name .. '" is not used')
    end
end
function P:define(tokens, position, main_file)
    local ok, macro = pcall(D.parse, tokens, position, main_file)
    if not ok then
        if type(macro) ~= "table" or macro.category ~= "definition" then error(macro) end
        self:diagnostic(position, "error", macro.message)
        return
    end
    local previous, operation = self.macros[macro.name]
    if not previous then
        self.macros[macro.name], self.ever_defined[macro.name], operation = macro, true, "define"
    elseif D.identical(previous, macro) then operation = "identical"
    else
        self:unused_check(previous)
        self:diagnostic(position, "warning", string.format('"%s" redefined (previous definition at %s:%d)', macro.name, previous.position[1], previous.position[2]))
        self.macros[macro.name], self.ever_defined[macro.name], operation = macro, true, "redefine"
    end
    self:event(position, operation .. " " .. D.signature(macro))
end
function P:undefine(tokens, position)
    local err = D.check_name(tokens, "undef")
    if err then self:diagnostic(position, "error", err); return end
    if #tokens >= 2 then self:diagnostic(position, "warning", "extra tokens at end of #undef directive") end
    local name = tokens[1].spelling
    if self.macros[name] then
        self:unused_check(self.macros[name])
        self.macros[name] = nil
        self:event(position, "undef " .. name)
    else self:event(position, "undef " .. name .. " (not defined)") end
end
function P:process_defines()
    local number = 0
    for line in io.lines("input/defines.txt") do
        number = number + 1
        if line ~= "" then
            local at = line:find("=", 1, true)
            local text = at and line:sub(1, at - 1) .. " " .. line:sub(at + 1) or line .. " 1"
            self:define(L.definition(text, number), { "defines.txt", number }, false)
        end
    end
end
function P:marker(filename, line, flag)
    local text = string.format('# %d "%s"', line, filename)
    if flag then text = text .. " " .. flag end
    self.output[#self.output + 1], self.previous = text, { filename, line - 1 }
end
function P:output_line(context, physical, text)
    local position = context:position(physical)
    local filename, line = position[1], position[2]
    if filename == self.previous[1] and line > self.previous[2] and line <= self.previous[2] + 8 then
        for _ = 1, line - self.previous[2] - 1 do self.output[#self.output + 1] = "" end
    else self:marker(filename, line) end
    self.output[#self.output + 1], self.previous = text, position
    context.source.output_lines = context.source.output_lines + 1
end
function P:flush(context)
    local segment = context.segment
    context.segment = {}
    if #segment == 0 then return end
    self:poison_check(context, segment)
    local expanded = self.expander:expand(segment, context)
    local index = 1
    while index <= #expanded do
        local last, physical = index, expanded[index].line
        while expanded[last + 1] and expanded[last + 1].line == physical do last = last + 1 end
        self:output_line(context, physical, output_render(slice(expanded, index, last)))
        index = last + 1
    end
end
function P:macro_defined(name)
    if self.macros[name] then self.macros[name].tested = self.macros[name].tested + 1; return true end
    return D.builtins[name] or name == "__has_include"
end
function P:replace_operators(context, operands)
    local replaced, position = {}, 1
    while position <= #operands do
        local token, index, value = operands[position]
        if token.kind == "identifier" and token.spelling == "defined" then
            index = position + 1
            local parenthesized = operands[index] and operands[index].spelling == "("
            if parenthesized then index = index + 1 end
            if not operands[index] or operands[index].kind ~= "identifier" then fail('operator "defined" requires an identifier') end
            local name = operands[index].spelling
            index = index + 1
            if parenthesized then
                if not operands[index] or operands[index].spelling ~= ")" then fail('missing \')\' after "defined"') end
                index = index + 1
            end
            value = self:macro_defined(name)
        elseif token.kind == "identifier" and token.spelling == "__has_include" then
            index = position + 1
            if not operands[index] or operands[index].spelling ~= "(" then fail('missing \'(\' after "__has_include"') end
            local header
            header, index = header_specification(operands, index + 1)
            if not header or header.name == "" then fail('operator "__has_include" requires a header-name') end
            if not operands[index] or operands[index].spelling ~= ")" then fail('missing \')\' after "__has_include" operand') end
            index, value = index + 1, self.manager:search(header.name, header.quoted) ~= false
        else replaced[#replaced + 1], position = token, position + 1 end
        if index then
            replaced[#replaced + 1] = L.token("number", value and "1" or "0", token.line, token.space)
            position = index
        end
    end
    return replaced
end
function P:test(context, logical, name, operands)
    local position = context:position(logical.tokens[1].line)
    self:poison_check(context, operands)
    if name ~= "if" and name ~= "elif" then
        if #operands == 0 then self:diagnostic(position, "error", "no macro name given in #" .. name .. " directive"); return nil, false end
        if operands[1].kind ~= "identifier" then self:diagnostic(position, "error", "macro names must be identifiers"); return nil, false end
        if #operands >= 2 then self:diagnostic(position, "warning", "extra tokens at end of #" .. name .. " directive") end
        local defined = self:macro_defined(operands[1].spelling)
        if name == "ifndef" or name == "elifndef" then defined = not defined end
        return defined and 1 or 0, false
    end
    local ok, replaced = pcall(self.replace_operators, self, context, operands)
    if not ok then
        if type(replaced) ~= "table" or replaced.category ~= "directive" then error(replaced) end
        self:diagnostic(position, "error", replaced.message)
        return nil, false
    end
    local expanded = self.expander:expand(replaced, context)
    local value
    ok, value = pcall(function()
        local tree = Expression.parse(expanded, name)
        return Expression.evaluate(tree, function(message) self:diagnostic(position, "warning", message) end)
    end)
    if not ok then
        if type(value) ~= "table" or value.category ~= "expression" then error(value) end
        self:diagnostic(position, "error", value.message)
        return nil, expanded
    end
    return value, expanded
end
local function test_description(name, value, expanded)
    local description
    if value == nil then description = "not taken (error)"
    else
        description = value ~= 0 and "taken" or "not taken"
        if name == "if" or name == "elif" then description = description .. " (value " .. value .. ")" end
    end
    if expanded then description = description .. " [" .. output_render(expanded) .. "]" end
    return description
end
function P:close_region(context, block, ending)
    local start = block.skip_start
    if start and ending >= start then
        local first, last = context:position(start), context:position(ending)
        self.regions[#self.regions + 1] = string.format("%s:%d-%d lines=%d", first[1], first[2], last[2], ending - start + 1)
        context.source.skipped_lines = context.source.skipped_lines + ending - start + 1
    end
    block.skip_start = false
end
function P:conditional_record(position, depth, name, operands, description)
    local directive = "#" .. name .. (#operands > 0 and " " .. L.render(operands) or "")
    self.conditional_records[#self.conditional_records + 1] = string.format("%s:%d: %s%s => %s", position[1], position[2], string.rep("  ", depth), directive, description)
    for _, entry in ipairs({ { "taken", "taken" }, { "not taken", "not_taken" }, { "skipped", "skipped" },
        { "not evaluated", "not_evaluated" }, { "closes", "endif" } }) do
        if description:sub(1, #entry[1]) == entry[1] then self.condition_counts[entry[2]] = self.condition_counts[entry[2]] + 1; break end
    end
end
function P:conditional(context, logical, name, operands)
    local position = context:position(logical.tokens[1].line)
    if Manager.starts[name] then
        local parent = #context.stack == 0 or context.stack[#context.stack].active
        local block = { kind = name, position = position, parent = parent, chosen = false, active = false, else_seen = false, skip_start = false }
        local description
        if parent then
            local value, expanded = self:test(context, logical, name, operands)
            if value ~= nil and value ~= 0 then block.chosen, block.active = true, true
            else block.skip_start = logical.ending + 1 end
            description = test_description(name, value, expanded)
        else description = "skipped" end
        self:conditional_record(position, #context.stack, name, operands, description)
        context.stack[#context.stack + 1] = block
        return
    end
    if #context.stack == 0 then self:diagnostic(position, "error", "#" .. name .. " without #if"); return end
    local block, depth, description = context.stack[#context.stack], #context.stack - 1
    self:close_region(context, block, logical.start - 1)
    if name == "endif" then
        table.remove(context.stack)
        if block.parent and #operands > 0 then self:diagnostic(position, "warning", "extra tokens at end of #endif directive") end
        description = "closes #" .. block.kind .. " at line " .. block.position[2]
    else
        if block.else_seen then self:diagnostic(position, "error", "#" .. name .. " after #else") end
        if name == "else" then
            if block.parent and #operands > 0 then self:diagnostic(position, "warning", "extra tokens at end of #else directive") end
            block.else_seen = true
            if block.parent then
                block.active, block.chosen = not block.chosen, true
                description = block.active and "taken" or "not taken"
            else block.active, description = false, "skipped" end
        elseif not block.parent then block.active, description = false, "skipped"
        elseif block.chosen then block.active, description = false, "not evaluated"
        else
            local value, expanded = self:test(context, logical, name, operands)
            block.active = value ~= nil and value ~= 0
            if block.active then block.chosen = true end
            description = test_description(name, value, expanded)
        end
        if block.parent and not block.active then block.skip_start = logical.ending + 1 end
    end
    self:conditional_record(position, depth, name, operands, description)
end
function P:include(context, logical, operands)
    local position, header = context:position(logical.tokens[1].line)
    local ok, err = pcall(function()
        local sequence, consumed = operands
        header, consumed = header_specification(sequence)
        if not header and #sequence > 0 then
            sequence = self.expander:expand(sequence, context)
            header, consumed = header_specification(sequence)
        end
        if not header then fail('#include expects "FILENAME" or <FILENAME>') end
        if consumed <= #sequence then self:diagnostic(position, "warning", "extra tokens at end of #include directive") end
        if header.name == "" then fail("empty filename in #include") end
    end)
    if not ok then
        if type(err) ~= "table" or err.category ~= "directive" then error(err) end
        self:diagnostic(position, "error", err.message)
        return
    end
    local prefix = string.rep("  ", context.depth + 1) .. logical.tokens[1].line .. ": "
    local path = self.manager:search(header.name, header.quoted)
    if not path then
        self.tree[#self.tree + 1] = prefix .. header.rendering .. " [not found]"
        self:diagnostic(position, "error", "cannot find include file " .. header.rendering)
        return
    end
    local previous = self.manager.files[path]
    if previous and previous.once then
        self.tree[#self.tree + 1] = prefix .. path .. " [skipped: pragma once]"
        previous.skipped = previous.skipped + 1
        return
    elseif previous and previous.guard and self.macros[previous.guard] then
        self.tree[#self.tree + 1] = prefix .. path .. " [skipped: guard " .. previous.guard .. "]"
        previous.skipped = previous.skipped + 1
        return
    elseif context.depth + 1 > 8 then
        self.tree[#self.tree + 1] = prefix .. path .. " [too deep]"
        self:diagnostic(position, "error", "#include nested too deeply")
        return
    end
    self.tree[#self.tree + 1] = prefix .. path
    self:marker(path, 1, 1)
    self:process_file(path, context.depth + 1)
    local returning = context:position(logical.ending + 1)
    self:marker(returning[1], returning[2], 2)
end
function P:line_directive(context, logical, operands)
    local position = context:position(logical.tokens[1].line)
    if #operands == 0 or not decimal_token(operands[1]) then operands = self.expander:expand(operands, context) end
    if (#operands ~= 1 and #operands ~= 2) or not decimal_token(operands[1]) or (#operands == 2 and operands[2].kind ~= "string") then
        self:diagnostic(position, "error", "invalid #line directive")
        return
    end
    local line = tonumber(operands[1].spelling)
    if line < 1 or line > 2147483647 then self:diagnostic(position, "error", "line number out of range"); return end
    context.offset = line - (logical.ending + 1)
    if #operands == 2 then context.display_file = operands[2].spelling:sub(2, -2) end
end
function P:macro_pragma(position, operands, operation)
    if #operands ~= 4 or operands[2].spelling ~= "(" or operands[3].kind ~= "string" or operands[4].spelling ~= ")" then
        self:diagnostic(position, "error", "invalid #pragma " .. operation .. " directive")
        return
    end
    local name = operands[3].spelling:sub(2, -2)
    self.saved[name] = self.saved[name] or {}
    local stack = self.saved[name]
    if operation == "push_macro" then
        stack[#stack + 1] = self.macros[name] or false
        self:event(position, "push " .. name)
    elseif #stack == 0 then self:diagnostic(position, "warning", 'no matching push_macro for "' .. name .. '"')
    else
        local macro = table.remove(stack)
        if not macro then self.macros[name] = nil; self:event(position, "pop " .. name .. " (undefined)")
        else self.macros[name] = macro; self:event(position, "pop " .. name) end
    end
end
function P:pragma(context, logical, operands)
    local position = context:position(logical.tokens[1].line)
    local name = operands[1] and operands[1].kind == "identifier" and operands[1].spelling
    if name == "once" then
        if #operands >= 2 then self:diagnostic(position, "warning", "extra tokens at end of #pragma once directive") end
        if context.depth == 0 then self:diagnostic(position, "warning", "#pragma once in main file") end
        context.source.once = true
    elseif #operands >= 2 and operands[1].spelling == "GCC" and operands[2].spelling == "poison" then
        for i = 3, #operands do
            if operands[i].kind ~= "identifier" then self:diagnostic(position, "error", "invalid #pragma GCC poison directive"); return end
        end
        for i = 3, #operands do
            local token = operands[i]
            if self.macros[token.spelling] then self:diagnostic(position, "warning", 'poisoning existing macro "' .. token.spelling .. '"') end
            self.poisoned[token.spelling] = true
        end
    elseif name == "push_macro" or name == "pop_macro" then self:macro_pragma(position, operands, name)
    else self:output_line(context, logical.tokens[1].line, "#pragma" .. (#operands > 0 and " " .. L.render(operands) or "")) end
end
function P:directive(context, logical, name, operands)
    if #logical.tokens == 1 then return end
    local poisoning = name == "pragma" and #operands >= 2 and operands[1].spelling == "GCC" and operands[2].spelling == "poison"
    if not poisoning then self:poison_check(context, operands) end
    local position = context:position(logical.tokens[1].line)
    if name == "define" then self:define(operands, position, context.depth == 0)
    elseif name == "undef" then self:undefine(operands, position)
    elseif name == "include" then self:include(context, logical, operands)
    elseif name == "line" then self:line_directive(context, logical, operands)
    elseif name == "error" or name == "warning" then
        self:diagnostic(position, name, "#" .. name .. (#operands > 0 and " " .. L.render(operands) or ""))
    elseif name == "pragma" then self:pragma(context, logical, operands)
    else self:diagnostic(position, "error", "invalid preprocessing directive #" .. logical.tokens[2].spelling) end
end
function P:process_file(path, depth)
    local source = self.manager:load(path)
    source.entered = source.entered + 1
    local context = setmetatable({ source = source, depth = depth, display_file = path, offset = 0, stack = {}, segment = {} }, I)
    for _, logical in ipairs(source.lines) do
        local tokens = logical.tokens
        local is_directive = #tokens > 0 and tokens[1].spelling == "#"
        local name, operands = Manager.directive_name(tokens), slice(tokens, 3)
        if is_directive and (Manager.starts[name] or Manager.branches[name] or name == "endif") then
            self:flush(context)
            self:conditional(context, logical, name, operands)
        elseif context:skipping() then
        elseif is_directive then
            self:flush(context)
            self:directive(context, logical, name, operands)
        else append(context.segment, tokens) end
    end
    self:flush(context)
    for _, block in ipairs(context.stack) do self:close_region(context, block, source.physical_lines) end
    for _, block in ipairs(context.stack) do self:diagnostic(block.position, "error", "unterminated #" .. block.kind) end
end
function P:include_report()
    local lines = { table.unpack(self.tree) }
    append(lines, { "", "== files ==" })
    for _, path in ipairs(keys(self.manager.files)) do
        local source = self.manager.files[path]
        lines[#lines + 1] = string.format("%s entered=%d skipped=%d lines=%d output_lines=%d skipped_lines=%d guard=%s once=%s",
            path, source.entered, source.skipped, source.physical_lines, source.output_lines, source.skipped_lines,
            source.guard or "-", source.once and "yes" or "no")
    end
    lines[#lines + 1] = ""
    local current, has_path = "main.o:", false
    for _, path in ipairs(self.manager.order) do
        if #current + 1 + #path > 76 and has_path then
            lines[#lines + 1] = current .. " \\"
            current, has_path = " ", false
        end
        current, has_path = current .. " " .. path, true
    end
    lines[#lines + 1] = current
    return lines
end
function P:references()
    local references = {}
    for name, macro in pairs(self.macros) do
        local parameters, found = {}, {}
        for _, parameter in ipairs(macro.parameters or {}) do parameters[parameter] = true end
        for _, token in ipairs(macro.replacement) do
            if token.kind == "identifier" and self.macros[token.spelling] and not parameters[token.spelling] then found[token.spelling] = true end
        end
        references[name] = keys(found)
    end
    return references
end
local function recursive(name, references)
    local pending, seen = { table.unpack(references[name]) }, {}
    while #pending > 0 do
        local current = table.remove(pending)
        if current == name then return true end
        if not seen[current] then seen[current] = true; append(pending, references[current]) end
    end
    return false
end
function P:macro_report()
    local lines = { "== history ==" }
    append(lines, self.history)
    append(lines, { "", "== table ==" })
    local references, names, object_like = self:references(), keys(self.macros), 0
    for _, name in ipairs(names) do
        local macro = self.macros[name]
        local definition = "#define " .. D.signature(macro)
        if #macro.replacement > 0 then definition = definition .. " " .. L.render(macro.replacement) end
        lines[#lines + 1] = definition
        lines[#lines + 1] = string.format("  at %s:%d expanded=%d tested=%d recursive=%s", macro.position[1], macro.position[2],
            macro.expanded, macro.tested, recursive(name, references) and "yes" or "no")
        lines[#lines + 1] = following("  refs:", references[name])
        if not macro.parameters then object_like = object_like + 1 end
    end
    append(lines, { "", string.format("macros=%d object_like=%d function_like=%d", #names, object_like, #names - object_like) })
    local undefined = {}
    for _, name in ipairs(keys(self.ever_defined)) do if not self.macros[name] then undefined[#undefined + 1] = name end end
    lines[#lines + 1] = following("undefined:", undefined)
    local counts = self.expander.builtin_counts
    lines[#lines + 1] = string.format("builtins: __COUNTER__=%d __FILE__=%d __LINE__=%d", counts.__COUNTER__, counts.__FILE__, counts.__LINE__)
    return lines
end
function P:conditional_report()
    local lines = { table.unpack(self.conditional_records) }
    append(lines, { "", "== skipped regions ==" })
    append(lines, self.regions)
    lines[#lines + 1] = ""
    local counts = self.condition_counts
    lines[#lines + 1] = string.format("directives=%d taken=%d not_taken=%d skipped=%d not_evaluated=%d endif=%d regions=%d",
        #self.conditional_records, counts.taken, counts.not_taken, counts.skipped, counts.not_evaluated, counts.endif, #self.regions)
    return lines
end
function P:write_reports()
    local diagnostics = { table.unpack(self.diagnostics) }
    diagnostics[#diagnostics + 1] = string.format("errors=%d warnings=%d", self.diagnostic_counts.error, self.diagnostic_counts.warning)
    for _, entry in ipairs({ { "preprocessed.txt", self.output }, { "includes.txt", self:include_report() },
        { "macros.txt", self:macro_report() }, { "conditionals.txt", self:conditional_report() }, { "diagnostics.txt", diagnostics } }) do
        local output = assert(io.open("output/" .. entry[1], "w"))
        for _, line in ipairs(entry[2]) do output:write((line:gsub(" +$", "")), "\n") end
        output:close()
    end
end
local preprocessor = P.new()
preprocessor:process_defines()
preprocessor:marker("main.c", 1)
preprocessor:process_file("main.c", 0)
for _, name in ipairs(keys(preprocessor.macros)) do preprocessor:unused_check(preprocessor.macros[name]) end
preprocessor:write_reports()
