local grammar = require("grammar_parser")
local transform = require("transform")
local first_follow = require("first_follow")
local ll_table = require("ll_table")
local driver = require("driver")
local function lines(path)
    local result = {}
    for line in io.lines(path) do
        result[#result + 1] = line
    end
    return result
end
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function joined(heading, values)
    local fields = {}
    for _, value in ipairs(values) do
        fields[#fields + 1] = tostring(value)
    end
    return heading .. (#fields > 0 and " " .. table.concat(fields, " ") or "")
end
local function yes_no(value)
    return value and "yes" or "no"
end
local function less(first, second)
    for index, value in ipairs(first) do
        if value ~= second[index] then
            return value < second[index]
        end
    end
    return false
end
local function check_declarations(source)
    local result, names = {}, {}
    if source.has_declarations then
        for name in pairs(source.word_first) do
            if not source.declared[name] then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        result[#result + 1] = "undeclared terminal " .. name .. " at line " .. source.word_first[name]
    end
    return result
end
local function reachable(source)
    local found, queue, cursor = {[source.start] = true}, {source.start}, 1
    while cursor <= #queue do
        local lhs = queue[cursor]
        cursor = cursor + 1
        for _, rhs in ipairs(source.rules[lhs]) do
            for _, symbol in ipairs(rhs) do
                if grammar.is_nonterminal(symbol) and not found[symbol] then
                    found[symbol], queue[#queue + 1] = true, symbol
                end
            end
        end
    end
    return found
end
local function clean(source)
    local result, diagnostics, undefined = grammar.copy(source), {}, {}
    for _, lhs in ipairs(result.order) do
        for _, rhs in ipairs(result.rules[lhs]) do
            for _, symbol in ipairs(rhs) do
                if grammar.is_nonterminal(symbol) and not result.rules[symbol] then
                    undefined[symbol] = true
                end
            end
        end
    end
    local names = {}
    for name in pairs(undefined) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b) return a:sub(2, -2) < b:sub(2, -2) end)
    for _, name in ipairs(names) do
        diagnostics[#diagnostics + 1] = "undefined nonterminal " .. name
    end
    local function remove_alternatives(removed, reason)
        for _, lhs in ipairs(result.order) do
            local retained = {}
            for _, rhs in ipairs(result.rules[lhs]) do
                local first = nil
                for _, symbol in ipairs(rhs) do
                    if removed[symbol] then
                        first = symbol
                        break
                    end
                end
                if first then
                    diagnostics[#diagnostics + 1] = "removed " .. grammar.production(lhs, rhs) .. " (" .. reason .. " " .. first .. ")"
                else
                    retained[#retained + 1] = rhs
                end
            end
            result.rules[lhs] = retained
        end
    end
    remove_alternatives(undefined, "undefined")
    local productive, changed = {}, true
    while changed do
        changed = false
        for _, lhs in ipairs(result.order) do
            if not productive[lhs] then
                for _, rhs in ipairs(result.rules[lhs]) do
                    local valid = true
                    for _, symbol in ipairs(rhs) do
                        if grammar.is_nonterminal(symbol) and not productive[symbol] then
                            valid = false
                            break
                        end
                    end
                    if valid then
                        productive[lhs], changed = true, true
                        break
                    end
                end
            end
        end
    end
    local removed, order = {}, {}
    for _, lhs in ipairs(result.order) do
        if productive[lhs] then
            order[#order + 1] = lhs
        else
            removed[lhs], result.rules[lhs] = true, nil
            diagnostics[#diagnostics + 1] = "unproductive nonterminal " .. lhs
        end
    end
    result.order = order
    remove_alternatives(removed, "unproductive")
    local reached = reachable(result)
    order = {}
    for _, lhs in ipairs(result.order) do
        if reached[lhs] then
            order[#order + 1] = lhs
        else
            result.rules[lhs] = nil
            diagnostics[#diagnostics + 1] = "unreachable nonterminal " .. lhs
        end
    end
    result.order = order
    return result, diagnostics
end
local function left_recursion(source)
    local diagnostics = {}
    for _, start in ipairs(source.order) do
        local queue, visited, parent, cursor, found = {start}, {[start] = true}, {}, 1, nil
        while cursor <= #queue and not found do
            local lhs = queue[cursor]
            cursor = cursor + 1
            for _, rhs in ipairs(source.rules[lhs]) do
                local symbol = rhs[1]
                if symbol == start then
                    found = lhs
                    break
                elseif symbol and grammar.is_nonterminal(symbol) and not visited[symbol] then
                    visited[symbol], parent[symbol], queue[#queue + 1] = true, lhs, symbol
                end
            end
        end
        if found then
            local path, current = {}, found
            while current ~= start do
                table.insert(path, 1, current)
                current = parent[current]
            end
            table.insert(path, 1, start)
            path[#path + 1] = start
            diagnostics[#diagnostics + 1] = "left recursion: " .. table.concat(path, " -> ")
        end
    end
    return diagnostics
end
local function prune(source)
    local result, log, diagnostics = grammar.copy(source), {}, {}
    local reached, order = reachable(result), {}
    for _, lhs in ipairs(result.order) do
        if reached[lhs] then
            order[#order + 1] = lhs
        else
            result.rules[lhs] = nil
            log[#log + 1] = "remove unreachable " .. lhs
            diagnostics[#diagnostics + 1] = "unreachable after transformation " .. lhs
        end
    end
    result.order = order
    return result, log, diagnostics
end
local function unused_declarations(source, final)
    local known, result = {}, {}
    for _, name in ipairs(first_follow.terminals(final)) do
        known[name] = true
    end
    if source.has_declarations then
        for _, name in ipairs(first_follow.terminal_order(source.declared)) do
            if not known[name] then
                result[#result + 1] = "unused token " .. name
            end
        end
    end
    return result
end
local function summary(source)
    local productions, empty, unit = 0, 0, 0
    for _, lhs in ipairs(source.order) do
        for _, rhs in ipairs(source.rules[lhs]) do
            productions = productions + 1
            empty = empty + (#rhs == 0 and 1 or 0)
            unit = unit + (#rhs == 1 and grammar.is_nonterminal(rhs[1]) and 1 or 0)
        end
    end
    return "start=" .. source.start .. " nonterminals=" .. #source.order .. " terminals=" .. #first_follow.terminals(source) ..
        " productions=" .. productions .. " empty=" .. empty .. " unit=" .. unit
end
local function listing(source, numbered)
    local result, count = {}, 0
    local total = #ll_table.number(source)
    local width = #tostring(total)
    for _, lhs in ipairs(source.order) do
        for index, rhs in ipairs(source.rules[lhs]) do
            count = count + 1
            local prefix = index == 1 and lhs .. " -> " or string.rep(" ", #lhs) .. " | "
            if numbered then
                prefix = string.rep(" ", width - #tostring(count)) .. count .. "  " .. prefix
            end
            result[#result + 1] = prefix .. grammar.alternative(rhs)
        end
    end
    return result
end
local function grammar_report(cleaned, recursion, factored, final, recursion_log, factor_log, final_log)
    local result = {"== cleaned grammar ==", summary(cleaned)}
    append(result, listing(cleaned, false))
    for _, stage in ipairs({
        {"left recursion elimination", recursion, recursion_log, false},
        {"left factoring", factored, factor_log, false},
        {"final grammar", final, final_log, true}
    }) do
        append(result, {"", "== " .. stage[1] .. " =="})
        append(result, #stage[3] > 0 and stage[3] or {"none"})
        result[#result + 1] = summary(stage[2])
        append(result, listing(stage[2], stage[4]))
    end
    append(result, {"", "== cross reference =="})
    local symbols = {table.unpack(final.order)}
    append(symbols, first_follow.terminals(final))
    local productions = ll_table.number(final)
    for _, symbol in ipairs(symbols) do
        local numbers = {}
        for _, production in ipairs(productions) do
            for _, member in ipairs(production.rhs) do
                if member == symbol then
                    numbers[#numbers + 1] = production.number
                    break
                end
            end
        end
        local name = grammar.is_nonterminal(symbol) and symbol or '"' .. symbol .. '"'
        result[#result + 1] = #numbers > 0 and joined(name .. " used in", numbers) or name .. " not used"
    end
    return result
end
local function sequence_score(symbols, scores)
    local length, height = 0, 0
    for _, symbol in ipairs(symbols) do
        if grammar.is_nonterminal(symbol) then
            if not scores[symbol] then
                return nil
            end
            length, height = length + scores[symbol][1], math.max(height, scores[symbol][2])
        else
            length = length + 1
        end
    end
    return {length, height + 1}
end
local function shortest(source)
    local scores, changed = {}, true
    while changed do
        changed = false
        for _, lhs in ipairs(source.order) do
            for _, rhs in ipairs(source.rules[lhs]) do
                local score = sequence_score(rhs, scores)
                if score and (not scores[lhs] or less(score, scores[lhs])) then
                    scores[lhs], changed = score, true
                end
            end
        end
    end
    local selected, sentences = {}, {}
    for _, lhs in ipairs(source.order) do
        for _, rhs in ipairs(source.rules[lhs]) do
            local score = sequence_score(rhs, scores)
            if score and grammar.same(score, scores[lhs]) then
                selected[lhs] = rhs
                break
            end
        end
    end
    local function expand(symbol)
        if not grammar.is_nonterminal(symbol) then
            return {symbol}
        end
        if not sentences[symbol] then
            local value = {}
            for _, child in ipairs(selected[symbol]) do
                append(value, expand(child))
            end
            sentences[symbol] = value
        end
        return sentences[symbol]
    end
    for _, lhs in ipairs(source.order) do
        expand(lhs)
    end
    return scores, sentences
end
local function sentence(symbols, sentences)
    local result = {}
    for _, symbol in ipairs(symbols) do
        append(result, grammar.is_nonterminal(symbol) and sentences[symbol] or {symbol})
    end
    return result
end
local function contexts(source, scores, sentences, productions)
    local costs, parents, changed = {[source.start] = {0, 0}}, {}, true
    while changed do
        changed = false
        for _, production in ipairs(productions) do
            local lhs, rhs = production.lhs, production.rhs
            if costs[lhs] then
                for index, symbol in ipairs(rhs) do
                    if grammar.is_nonterminal(symbol) and symbol ~= source.start then
                        local before, after = {table.unpack(rhs, 1, index - 1)}, {table.unpack(rhs, index + 1)}
                        local outside = {table.unpack(before)}
                        append(outside, after)
                        local score = sequence_score(outside, scores)
                        local cost, key = {costs[lhs][1] + score[1], costs[lhs][2] + 1}, {production.number, index}
                        if not costs[symbol] or less(cost, costs[symbol]) or grammar.same(cost, costs[symbol]) and less(key, parents[symbol].key) then
                            costs[symbol], parents[symbol], changed = cost, {key = key, lhs = lhs, before = before, after = after}, true
                        end
                    end
                end
            end
        end
    end
    local result = {[source.start] = {{}, {}}}
    local function build(symbol)
        if not result[symbol] then
            local parent = parents[symbol]
            local outer = build(parent.lhs)
            local prefix, suffix = {table.unpack(outer[1])}, sentence(parent.after, sentences)
            append(prefix, sentence(parent.before, sentences))
            append(suffix, outer[2])
            result[symbol] = {prefix, suffix}
        end
        return result[symbol]
    end
    for _, lhs in ipairs(source.order) do
        build(lhs)
    end
    return result
end
local function sets_report(source, sets, sentences)
    local result = {"passes: nullable=" .. sets.passes.nullable .. " first=" .. sets.passes.first .. " follow=" .. sets.passes.follow, ""}
    for _, lhs in ipairs(source.order) do
        append(result, {
            lhs,
            "  nullable: " .. yes_no(sets.nullable[lhs]),
            joined("  first:", first_follow.terminal_order(sets.first[lhs])),
            joined("  follow:", first_follow.terminal_order(sets.follow[lhs])),
            joined("  shortest:", sentences[lhs])
        })
    end
    return result
end
local function first_path(production, token, parse_table, sets)
    local queue, parent, visited, cursor = {production.number}, {}, {[production.number] = true}, 1
    while cursor <= #queue do
        local current = queue[cursor]
        cursor = cursor + 1
        for _, symbol in ipairs(parse_table.productions[current].rhs) do
            if symbol == token then
                local path = {}
                while current ~= production.number do
                    table.insert(path, 1, current)
                    current = parent[current]
                end
                return path
            end
            if grammar.is_nonterminal(symbol) then
                for _, candidate in ipairs(parse_table.productions) do
                    if candidate.lhs == symbol and not visited[candidate.number] then
                        visited[candidate.number], parent[candidate.number] = true, current
                        queue[#queue + 1] = candidate.number
                    end
                end
                if not sets.nullable[symbol] then
                    break
                end
            else
                break
            end
        end
    end
    return {}
end
local function follow_path(lhs, token, source, parse_table, sets)
    local queue, paths, cursor = {lhs}, {[lhs] = {}}, 1
    while cursor <= #queue do
        local symbol = queue[cursor]
        cursor = cursor + 1
        local path = paths[symbol]
        if symbol == source.start and token == "$" then
            return path
        end
        for _, production in ipairs(parse_table.productions) do
            for index, member in ipairs(production.rhs) do
                if member == symbol then
                    local suffix = {table.unpack(production.rhs, index + 1)}
                    local values, empty = first_follow.sequence(suffix, sets.nullable, sets.first)
                    local extended = {table.unpack(path)}
                    extended[#extended + 1] = production.number
                    if values[token] then
                        return extended
                    elseif empty and not paths[production.lhs] then
                        paths[production.lhs], queue[#queue + 1] = extended, production.lhs
                    end
                end
            end
        end
    end
    return {}
end
local function table_report(source, sets, parse_table, conflicts_before)
    local result = {"== predict sets =="}
    for _, production in ipairs(parse_table.productions) do
        append(result, {production.number .. ": " .. production.notation, joined("  predict:", first_follow.terminal_order(production.predict))})
    end
    append(result, {"", "== parse table =="})
    local terminals = {table.unpack(sets.terminals)}
    terminals[#terminals + 1] = "$"
    local header = {""}
    append(header, terminals)
    local matrix, widths = {header}, {}
    for _, lhs in ipairs(source.order) do
        local row = {lhs}
        for _, token in ipairs(terminals) do
            local cell, fields = parse_table.cells[lhs][token], {}
            for _, number in ipairs(cell) do
                fields[#fields + 1] = tostring(number)
            end
            row[#row + 1] = #fields > 0 and table.concat(fields, "/") or "."
        end
        matrix[#matrix + 1] = row
    end
    for _, row in ipairs(matrix) do
        for index, value in ipairs(row) do
            widths[index] = math.max(widths[index] or 0, #value)
        end
    end
    for _, row in ipairs(matrix) do
        local line = row[1] .. string.rep(" ", widths[1] - #row[1])
        for index = 2, #row do
            line = line .. "  " .. string.rep(" ", widths[index] - #row[index]) .. row[index]
        end
        result[#result + 1] = line
    end
    append(result, {"", "== conflicts =="})
    if #parse_table.conflicts == 0 then
        result[#result + 1] = "none"
    end
    for _, conflict in ipairs(parse_table.conflicts) do
        result[#result + 1] = "conflict " .. conflict.lhs .. " on " .. conflict.token .. ": " .. conflict.kind .. ", chosen " .. conflict.chosen
        for _, number in ipairs(conflict.numbers) do
            local production = parse_table.productions[number]
            local reason = production.reasons[conflict.token]
            local path = reason == "FIRST" and first_path(production, conflict.token, parse_table, sets) or follow_path(conflict.lhs, conflict.token, source, parse_table, sets)
            if #path > 0 then
                reason = joined(reason .. " via", path)
            end
            result[#result + 1] = "  " .. number .. ": " .. production.notation .. " (" .. reason .. ")"
        end
    end
    append(result, {"LL(1): " .. yes_no(#parse_table.conflicts == 0), "conflicts before transformation: " .. conflicts_before})
    return result
end
local function compact(node)
    local children = {}
    for _, original in ipairs(node.children) do
        if original.symbol ~= "%empty" then
            local child = compact(original)
            local excluded = grammar.is_nonterminal(child.symbol) and not child.mark and #child.children == 0
            if not excluded then
                if grammar.is_nonterminal(child.symbol) and child.symbol:find("'", 1, true) and not child.mark then
                    append(children, child.children)
                else
                    children[#children + 1] = child
                end
            end
        end
    end
    if #children == 1 and not node.mark then
        return children[1]
    end
    return {symbol = node.symbol, mark = node.mark, children = children}
end
local function label(node)
    return node.symbol .. (node.mark and " (" .. node.mark .. ")" or "")
end
local function tree_lines(root)
    local result = {label(root)}
    local function visit(node, prefix, last)
        result[#result + 1] = prefix .. (last and "`-- " or "|-- ") .. label(node)
        local next_prefix = prefix .. (last and "    " or "|   ")
        for index, child in ipairs(node.children) do
            visit(child, next_prefix, index == #node.children)
        end
    end
    for index, child in ipairs(root.children) do
        visit(child, "", index == #root.children)
    end
    return result
end
local function trace_lines(trace)
    local rows = {{"step", "stack", "input", "action"}}
    append(rows, trace)
    local widths, result = {0, 0, 0}, {}
    for _, row in ipairs(rows) do
        for index = 1, 3 do
            widths[index] = math.max(widths[index], #row[index])
        end
    end
    for _, row in ipairs(rows) do
        local line = ""
        for index = 1, 3 do
            line = line .. row[index] .. string.rep(" ", widths[index] - #row[index]) .. "  "
        end
        result[#result + 1] = line .. row[4]
    end
    return result
end
local function derivation(source, numbers, productions)
    local symbols, result = {source.start}, {"  " .. source.start}
    for _, number in ipairs(numbers) do
        local position = nil
        for index, symbol in ipairs(symbols) do
            if grammar.is_nonterminal(symbol) then
                position = index
                break
            end
        end
        local value = {table.unpack(symbols, 1, position - 1)}
        append(value, productions[number].rhs)
        append(value, {table.unpack(symbols, position + 1)})
        symbols = value
        result[#result + 1] = "  => " .. grammar.alternative(symbols)
    end
    return result
end
local function language(source, tokens)
    local productions = ll_table.number(source)
    productions[0] = {lhs = "", rhs = {source.start}}
    local by_lhs = {}
    for _, production in ipairs(productions) do
        by_lhs[production.lhs] = by_lhs[production.lhs] or {}
        by_lhs[production.lhs][#by_lhs[production.lhs] + 1] = production.number
    end
    local chart = {}
    for position = 0, #tokens do
        chart[position] = {items = {}, seen = {}}
    end
    local function add(position, number, dot, origin)
        local key = number .. ":" .. dot .. ":" .. origin
        local column = chart[position]
        if not column.seen[key] then
            column.seen[key] = true
            column.items[#column.items + 1] = {number = number, dot = dot, origin = origin}
        end
    end
    add(0, 0, 0, 0)
    for position = 0, #tokens do
        local cursor = 1
        while cursor <= #chart[position].items do
            local state = chart[position].items[cursor]
            cursor = cursor + 1
            local production = productions[state.number]
            if state.dot == #production.rhs then
                local prior = chart[state.origin].items
                local count = #prior
                for index = 1, count do
                    local waiting = prior[index]
                    local rhs = productions[waiting.number].rhs
                    if rhs[waiting.dot + 1] == production.lhs then
                        add(position, waiting.number, waiting.dot + 1, waiting.origin)
                    end
                end
            else
                local symbol = production.rhs[state.dot + 1]
                if grammar.is_nonterminal(symbol) then
                    for _, number in ipairs(by_lhs[symbol]) do
                        add(position, number, 0, position)
                    end
                    local count = #chart[position].items
                    for index = 1, count do
                        local completed = chart[position].items[index]
                        local body = productions[completed.number]
                        if body.lhs == symbol and completed.dot == #body.rhs and completed.origin == position then
                            add(position, state.number, state.dot + 1, state.origin)
                        end
                    end
                elseif position < #tokens and symbol == tokens[position + 1] then
                    add(position + 1, state.number, state.dot + 1, state.origin)
                end
            end
        end
    end
    return chart[#tokens].seen["0:1:0"] or false
end
local function event_error(event, sets, parse_table)
    local token, symbol = event.token, event.symbol
    local unexpected = token == "$" and "end of input" or '"' .. token .. '" at token ' .. event.position
    local expected
    if grammar.is_nonterminal(symbol) then
        local names = {}
        local present = {}
        for name in pairs(parse_table.choices[symbol]) do
            present[name] = true
        end
        for _, name in ipairs(first_follow.terminal_order(present)) do
            names[#names + 1] = name == "$" and "$" or '"' .. name .. '"'
        end
        expected = table.concat(names, " ")
    else
        expected = symbol == "$" and "$" or '"' .. symbol .. '"'
    end
    local recovery = event.kind == "skip" and 'skipped "' .. token .. '"' or
        event.kind == "pop" and "popped " .. symbol or 'inserted "' .. symbol .. '"'
    return "step " .. event.step .. ": unexpected " .. unexpected .. "; expected " .. expected .. "; " .. recovery
end
local function parse_input(tokens, source, sets, parse_table)
    local known, kept, positions, errors = {}, {}, {}, {}
    for _, terminal in ipairs(sets.terminals) do
        known[terminal] = true
    end
    for position, token in ipairs(tokens) do
        if known[token] then
            kept[#kept + 1], positions[#positions + 1] = token, position
        else
            errors[#errors + 1] = 'unknown "' .. token .. '" at token ' .. position .. "; removed"
        end
    end
    local result = driver.parse(kept, positions, source, sets, parse_table)
    result.original, result.unknown, result.errors = tokens, #errors, errors
    for _, event in ipairs(result.events) do
        errors[#errors + 1] = event_error(event, sets, parse_table)
    end
    result.accepted = #errors == 0
    return result
end
local function one_parse(number, parsed, source, parse_table)
    local result = {"== input " .. number .. " ==", joined("tokens:", parsed.original)}
    append(result, trace_lines(parsed.trace))
    result[#result + 1] = joined("left parse:", parsed.left_parse)
    result[#result + 1] = "stats: steps=" .. #parsed.trace .. " predicts=" .. parsed.counts.predict .. " matches=" .. parsed.counts.match .. " max_stack=" .. parsed.counts.max_stack
    if #parsed.errors > 0 then
        result[#result + 1] = "errors:"
        for _, message in ipairs(parsed.errors) do
            result[#result + 1] = "  " .. message
        end
    end
    result[#result + 1] = parsed.accepted and "result: accepted" or "result: rejected (errors: " .. #parsed.errors .. ")"
    result[#result + 1] = "language: " .. yes_no(parsed.language)
    if parsed.accepted then
        result[#result + 1] = "derivation:"
        append(result, derivation(source, parsed.left_parse, parse_table.productions))
    end
    result[#result + 1] = "tree:"
    append(result, tree_lines(parsed.root))
    result[#result + 1] = "compact tree:"
    append(result, tree_lines(compact(parsed.root)))
    return result
end
local function parses_report(inputs, source, sets, parse_table, sentences, context)
    local result, accepted, in_language, mismatches, used = {}, 0, 0, {}, {}
    local unknown, skip, pop, missing = 0, 0, 0, 0
    for number, parsed in ipairs(inputs) do
        append(result, one_parse(number, parsed, source, parse_table))
        result[#result + 1] = ""
        accepted = accepted + (parsed.accepted and 1 or 0)
        in_language = in_language + (parsed.language and 1 or 0)
        if parsed.accepted ~= parsed.language then
            mismatches[#mismatches + 1] = number
        end
        unknown, skip = unknown + parsed.unknown, skip + parsed.counts.skip
        pop, missing = pop + parsed.counts.pop, missing + parsed.counts.missing
        for _, number_used in ipairs(parsed.left_parse) do
            used[number_used] = true
        end
    end
    local unused = {}
    for _, production in ipairs(parse_table.productions) do
        if not used[production.number] then
            unused[#unused + 1] = production.number
        end
    end
    append(result, {
        "== summary ==",
        "inputs=" .. #inputs .. " accepted=" .. accepted .. " rejected=" .. #inputs - accepted .. " in_language=" .. in_language,
        joined("mismatches:", mismatches),
        "recovery: unknown=" .. unknown .. " skip=" .. skip .. " pop=" .. pop .. " missing=" .. missing,
        "coverage: " .. #parse_table.productions - #unused .. " of " .. #parse_table.productions .. " productions used",
        joined("unused:", unused)
    })
    for _, number in ipairs(unused) do
        local production = parse_table.productions[number]
        local outer = context[production.lhs]
        local example = {table.unpack(outer[1])}
        append(example, sentence(production.rhs, sentences))
        append(example, outer[2])
        local positions = {}
        for index = 1, #example do
            positions[index] = index
        end
        local parsed = driver.parse(example, positions, source, sets, parse_table)
        local present = false
        for _, number_used in ipairs(parsed.left_parse) do
            if number_used == number then
                present = true
            end
        end
        append(result, {
            "  " .. number .. ": " .. production.notation,
            joined("    example:", example),
            #parsed.events == 0 and "    result: accepted" or "    result: rejected (errors: " .. #parsed.events .. ")",
            "    used: " .. yes_no(present)
        })
    end
    return result
end
local function save(name, values)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(values, "\n"), "\n")
    output:close()
end
local source = grammar.parse(lines("input/grammar.bnf"))
local declaration_diagnostics = check_declarations(source)
local cleaned, clean_diagnostics = clean(source)
local recursion_diagnostics = left_recursion(cleaned)
local recursion, recursion_log = transform.eliminate(cleaned)
local factored, factor_log = transform.factor(recursion)
local final, final_log, final_diagnostics = prune(factored)
local unused_diagnostics = unused_declarations(source, final)
local before_sets = first_follow.analyze(cleaned)
local before_table = ll_table.build(cleaned, before_sets)
local sets = first_follow.analyze(final)
local parse_table = ll_table.build(final, sets)
local scores, sentences = shortest(final)
local context = contexts(final, scores, sentences, parse_table.productions)
local inputs = {}
for _, line in ipairs(lines("input/inputs.txt")) do
    local tokens = {}
    for token in line:gmatch("[^ ]+") do
        tokens[#tokens + 1] = token
    end
    local parsed = parse_input(tokens, final, sets, parse_table)
    parsed.language = language(cleaned, tokens)
    inputs[#inputs + 1] = parsed
end
local diagnostics = {table.unpack(source.diagnostics)}
for _, values in ipairs({declaration_diagnostics, clean_diagnostics, recursion_diagnostics, final_diagnostics, unused_diagnostics}) do
    append(diagnostics, values)
end
diagnostics[#diagnostics + 1] = #parse_table.conflicts == 0 and "result: LL(1)" or "result: not LL(1) (conflicts: " .. #parse_table.conflicts .. ")"
save("grammar.txt", grammar_report(cleaned, recursion, factored, final, recursion_log, factor_log, final_log))
save("sets.txt", sets_report(final, sets, sentences))
save("table.txt", table_report(final, sets, parse_table, #before_table.conflicts))
save("parses.txt", parses_report(inputs, final, sets, parse_table, sentences, context))
save("diagnostics.txt", diagnostics)
