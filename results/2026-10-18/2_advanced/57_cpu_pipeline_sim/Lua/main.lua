local trace_io = require('trace_io')
local hazards = require('hazards')
local pipeline = require('pipeline')
local predictors = require('predictors')
local report = require('report')
local classes = {'ALU', 'MUL', 'LOAD', 'STORE', 'BRANCH', 'JUMP', 'NOP'}
local causes, stages = pipeline.causes, pipeline.stages
local operands = {ALU = {1, 1, 2}, MUL = {1, 1, 1}, LOAD = {1, 1, 0}, STORE = {0, 1, 1},
    BRANCH = {0, 1, 2}, JUMP = {2, 2, 0}, NOP = {0, 0, 0}}
local function increment(values, key, amount)
    values[key] = (values[key] or 0) + (amount or 1)
end
local function value(values, key) return values[key] or 0 end
local function control(instruction) return instruction.class == 'BRANCH' or instruction.class == 'JUMP' end
local function ordered_keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end
local function join(values, separator)
    local result = {}
    for i, item in ipairs(values) do result[i] = tostring(item) end
    return table.concat(result, separator or ' ')
end
local function cause_values(values, format)
    local parts = {}
    for _, cause in ipairs(causes) do
        parts[#parts + 1] = cause .. ' ' .. (format and format(value(values, cause)) or value(values, cause))
    end
    return table.concat(parts, ' ')
end
local function check(line, static)
    local fields = {}
    for token in (line .. ' '):gmatch('(.-) ') do fields[#fields + 1] = token end
    if #fields ~= 8 then return nil, 'fields' end
    for _, field in ipairs(fields) do if field == '' then return nil, 'fields' end end
    local pc = trace_io.hex(fields[1])
    if not pc or pc % 4 ~= 0 then return nil, 'pc' end
    local kind = fields[2]
    if not operands[kind] then return nil, 'class' end
    local registers = {}
    for i = 1, 3 do
        registers[i] = trace_io.register(fields[i + 2])
        if fields[i + 2] ~= '-' and registers[i] == nil then return nil, 'register' end
    end
    for i, usage in ipairs(operands[kind]) do
        if usage == 1 and fields[i + 2] == '-' or usage == 0 and fields[i + 2] ~= '-' then return nil, 'operands' end
    end
    local outcome = fields[6]
    if kind == 'BRANCH' then
        if outcome ~= 'T' and outcome ~= 'N' then return nil, 'taken' end
    elseif kind == 'JUMP' then
        if outcome ~= 'T' then return nil, 'taken' end
    elseif outcome ~= '-' then return nil, 'taken' end
    local target, address = trace_io.hex(fields[7]), trace_io.hex(fields[8])
    if kind == 'BRANCH' or kind == 'JUMP' then
        if not target or target % 4 ~= 0 or target == pc + 4 then return nil, 'target' end
    elseif fields[7] ~= '-' then return nil, 'target' end
    if kind == 'LOAD' or kind == 'STORE' then
        if not address or address % 4 ~= 0 then return nil, 'address' end
    elseif fields[8] ~= '-' then return nil, 'address' end
    local result = {pc = pc, class = kind, rd = registers[1], rs1 = registers[2], rs2 = registers[3],
        outcome = outcome, target = target, address = address, next_pc = outcome == 'T' and target or pc + 4}
    local previous = static[pc]
    if previous then
        for _, key in ipairs({'class', 'rd', 'rs1', 'rs2'}) do
            if result[key] ~= previous[key] then return nil, 'conflict' end
        end
        if (kind == 'BRANCH' or kind == 'JUMP' and result.rs1 == nil) and target ~= previous.target then return nil, 'conflict' end
    end
    return result
end
local function validate(lines)
    local result = {lines = #lines, instructions = {}, rejected = {}, gaps = {}, static = {}}
    for line_number, line in ipairs(lines) do
        local instruction, reason = check(line, result.static)
        if reason then result.rejected[#result.rejected + 1] = {line_number, reason}
        else
            local previous = result.instructions[#result.instructions]
            if previous and previous.next_pc ~= instruction.pc then
                result.gaps[#result.gaps + 1] = {line_number, previous.next_pc, instruction.pc}
            end
            instruction.number = #result.instructions + 1
            result.instructions[#result.instructions + 1] = instruction
            if not result.static[instruction.pc] then result.static[instruction.pc] = instruction end
        end
    end
    return result
end
local function predict(instructions, definition, config)
    local btb, ras, direction = predictors.btb(config.btb), predictors.ras(config.ras), predictors.direction(definition)
    local result = {definition = definition, details = {}, flags = {}, statistics = {}, bits = predictors.storage(direction)}
    local statistics = result.statistics
    for i, instruction in ipairs(instructions) do
        result.flags[i] = false
        if control(instruction) then
            local pc, target, kind = instruction.pc, instruction.target, instruction.class
            local taken = instruction.outcome == 'T'
            local candidate = predictors.lookup(btb, pc)
            increment(statistics, 'lookups')
            if candidate then increment(statistics, 'hits') end
            if kind == 'JUMP' and instruction.rd == nil and instruction.rs1 == 31 then
                increment(statistics, 'returns')
                local address = predictors.pop(ras)
                if address then
                    candidate = address
                    increment(statistics, 'ras_predictions')
                    if address == target then increment(statistics, 'ras_correct') end
                end
            end
            if kind == 'JUMP' and instruction.rd == 31 then
                increment(statistics, 'calls')
                predictors.push(ras, pc + 4)
            end
            local predicted_taken = kind == 'JUMP' or predictors.predict(direction, pc, target)
            local predicted_pc = pc + 4
            if definition.scheme == 'PERFECT' then predicted_pc = instruction.next_pc
            elseif predicted_taken and candidate then predicted_pc = candidate end
            local missed = predicted_pc ~= instruction.next_pc
            local miss_kind
            if missed then
                if kind == 'BRANCH' and predicted_taken ~= taken then miss_kind = 'direction'
                elseif candidate == nil then miss_kind = 'btb_miss'
                else miss_kind = 'wrong_target' end
                increment(statistics, miss_kind)
                increment(statistics, 'mispredictions')
                increment(statistics, kind .. '_misses')
            end
            result.flags[i] = missed
            result.details[i] = {predicted = predicted_pc, kind = miss_kind}
            increment(statistics, 'control')
            increment(statistics, kind)
            if kind == 'BRANCH' then predictors.update(direction, pc, taken) end
            if taken then predictors.insert(btb, pc, target) end
        end
    end
    return result
end
local function totals(records)
    local cycles, events = {}, {}
    for _, record in ipairs(records) do
        increment(cycles, record.cause, record.cycles)
        increment(events, record.cause)
    end
    return cycles, events
end
local function combinations(instructions, sources, predictions, config)
    local result, primary = {}, nil
    for _, variant in ipairs(config.variants) do
        for _, definition in ipairs(config.predictors) do
            local simulation = pipeline.simulate(instructions, sources, variant, predictions[definition.name].flags)
            simulation.stalls, simulation.events = totals(simulation.records)
            simulation.variant, simulation.predictor = variant, definition.name
            result[#result + 1] = simulation
            if variant.name == config.primary[1] and definition.name == config.primary[2] then primary = simulation end
        end
    end
    table.sort(result, function(a, b)
        if a.cycles ~= b.cycles then return a.cycles < b.cycles end
        if a.variant.name ~= b.variant.name then return a.variant.name < b.variant.name end
        return a.predictor < b.predictor
    end)
    return result, primary
end
local function build_rows(instructions, primary, prediction)
    local annotations, rows = {}, {}
    for _, record in ipairs(primary.records) do
        if record.waiting then
            annotations[record.waiting] = (annotations[record.waiting] or '') .. ' ' .. record.cause .. ' ' .. record.cycles
        end
    end
    for i, instruction in ipairs(instructions) do
        local t, annotation = primary.timings[i], annotations[i] or ''
        if prediction.flags[i] then annotation = annotation .. ' mispredict ' .. prediction.details[i].kind end
        rows[#rows + 1] = {number = i, pc = instruction.pc, class = instruction.class, annotation = annotation,
            characters = {{t.F, t.F, 'F'}, {t.F + 1, t.D - 1, '*'}, {t.D, t.D, 'D'}, {t.D + 1, t.X - 1, '*'},
                {t.X, t.M - 1, 'X'}, {t.M, t.M, 'M'}, {t.W, t.W, 'W'}},
            stages = {{1, t.F, t.D - 1}, {2, t.D, t.X - 1}, {3, t.X, t.M - 1}, {4, t.M, t.M}, {5, t.W, t.W}}}
        if prediction.flags[i] then
            local resolved = hazards.id_resolved(instruction, primary.variant)
            local first = {pc = prediction.details[i].predicted, class = 'FLUSH', annotation = '',
                characters = {{t.D, t.D, 'F'}, {t.D + 1, t.X - 1, '*'}, {t.X + (resolved and 0 or 1), t.X + (resolved and 0 or 1), 'x'}},
                stages = {{1, t.D, t.X - 1}}}
            if not resolved then
                first.characters[#first.characters + 1] = {t.X, t.X, 'D'}
                first.stages[#first.stages + 1] = {2, t.X, t.X}
            end
            rows[#rows + 1] = first
            if not resolved then
                rows[#rows + 1] = {pc = first.pc + 4, class = 'FLUSH', annotation = '',
                    characters = {{t.X, t.X, 'F'}, {t.X + 1, t.X + 1, 'x'}}, stages = {{1, t.X, t.X}}}
            end
        end
    end
    return rows
end
local function pipeline_lines(rows, primary, config)
    local first, last = table.unpack(config.window)
    local width = last - first + 1
    local lines = {'pipeline variant=' .. primary.variant.name .. ' predictor=' .. primary.predictor .. ' cycles ' .. first .. '-' .. last,
        report.heading(first, last)}
    local contents = {}
    for i = 1, width do contents[i] = {'.', '.', '.', '.', '.'} end
    local visible, stalled, flushed = 0, 0, 0
    for _, row in ipairs(rows) do
        local characters, nonempty = {}, false
        for i = 1, width do characters[i] = '.' end
        for _, span in ipairs(row.characters) do
            for cycle = math.max(first, span[1]), math.min(last, span[2]) do characters[cycle - first + 1] = span[3] end
        end
        for _, character in ipairs(characters) do
            if character ~= '.' then nonempty = true end
            if character == '*' then stalled = stalled + 1 end
            if character == 'x' then flushed = flushed + 1 end
        end
        if nonempty then
            visible = visible + 1
            lines[#lines + 1] = report.row(row.number, row.pc, row.class, table.concat(characters), row.annotation)
        end
        for _, span in ipairs(row.stages) do
            for cycle = math.max(first, span[2]), math.min(last, span[3]) do
                contents[cycle - first + 1][span[1]] = row.number and tostring(row.number) or 'w'
            end
        end
    end
    local completed = 0
    for _, timing in ipairs(primary.timings) do if timing.W >= first and timing.W <= last then completed = completed + 1 end end
    lines[#lines + 1] = 'rows ' .. visible .. ' completed ' .. completed .. ' stall_cells ' .. stalled .. ' flushed ' .. flushed
    lines[#lines + 1], lines[#lines + 2], lines[#lines + 3] = '', 'stages', 'cycle IF ID EX MEM WB'
    for cycle = first, last do lines[#lines + 1] = cycle .. ' ' .. table.concat(contents[cycle - first + 1], ' ') end
    return lines
end
local function accuracy(prediction, kind)
    kind = kind or 'control'
    local stats = prediction.statistics
    local count = value(stats, kind)
    return report.percentage(count - value(stats, kind == 'control' and 'mispredictions' or kind .. '_misses'), count)
end
local function group_instructions(instructions)
    local groups = {}
    for i, instruction in ipairs(instructions) do
        local pc = instruction.pc
        groups[pc] = groups[pc] or {}
        groups[pc][#groups[pc] + 1] = i
    end
    return groups, ordered_keys(groups)
end
local function aggregate(instructions, records)
    local class_stalls, by_pc, pairs_by_key, pairs_list = {}, {}, {}, {}
    for _, record in ipairs(records) do
        local instruction = instructions[record.responsible]
        increment(class_stalls, instruction.class, record.cycles)
        by_pc[instruction.pc] = by_pc[instruction.pc] or {}
        increment(by_pc[instruction.pc], record.cause, record.cycles)
        if record.cause == 'load_use' or record.cause == 'raw' then
            local p, w = instructions[record.producer].pc, instructions[record.waiting].pc
            local key = p .. ':' .. w .. ':' .. record.cause
            local item = pairs_by_key[key]
            if not item then
                item = {producer = p, waiting = w, cause = record.cause, cycles = 0, events = 0}
                pairs_by_key[key], pairs_list[#pairs_list + 1] = item, item
            end
            item.cycles, item.events = item.cycles + record.cycles, item.events + 1
        end
    end
    table.sort(pairs_list, function(a, b)
        if a.cycles ~= b.cycles then return a.cycles > b.cycles end
        if a.producer ~= b.producer then return a.producer < b.producer end
        if a.waiting ~= b.waiting then return a.waiting < b.waiting end
        return a.cause < b.cause
    end)
    return class_stalls, by_pc, pairs_list
end
local function statistics_lines(trace, sources, predictions, combinations_list, primary, rows, config)
    local instructions, n = trace.instructions, #trace.instructions
    local input = {'input lines ' .. trace.lines .. ' accepted ' .. n .. ' rejected ' .. #trace.rejected .. ' gaps ' .. #trace.gaps}
    for _, rejected in ipairs(trace.rejected) do input[#input + 1] = 'reject line ' .. rejected[1] .. ' ' .. rejected[2] end
    for _, gap in ipairs(trace.gaps) do input[#input + 1] = 'gap line ' .. gap[1] .. ' expected ' .. report.hex(gap[2]) .. ' found ' .. report.hex(gap[3]) end
    local counts, addresses, distances = {}, {}, {}
    local branches, taken, backward, jumps, indirect, links, source_count, produced = 0, 0, 0, 0, 0, 0, 0, 0
    for i, instruction in ipairs(instructions) do
        increment(counts, instruction.class)
        if instruction.address then addresses[instruction.address] = true end
        if instruction.class == 'BRANCH' then
            branches = branches + 1
            if instruction.outcome == 'T' then taken = taken + 1 end
            if instruction.target < instruction.pc then backward = backward + 1 end
        elseif instruction.class == 'JUMP' then
            jumps = jumps + 1
            if instruction.rs1 then indirect = indirect + 1 end
            if instruction.rd then links = links + 1 end
        end
        source_count = source_count + #sources[i]
        for _, source in ipairs(sources[i]) do
            if source.producer then increment(distances, math.min(5, i - source.producer)); produced = produced + 1 end
        end
    end
    local static_branches, static_jumps, static_count = 0, 0, 0
    for _, instruction in pairs(trace.static) do
        static_count = static_count + 1
        if instruction.class == 'BRANCH' then static_branches = static_branches + 1 end
        if instruction.class == 'JUMP' then static_jumps = static_jumps + 1 end
    end
    local mix = {}
    for _, kind in ipairs(classes) do mix[#mix + 1] = kind .. ' ' .. value(counts, kind) end
    local distance_parts = {}
    for i = 1, 5 do distance_parts[#distance_parts + 1] = (i == 5 and '5+' or tostring(i)) .. ' ' .. value(distances, i) end
    local trace_part = {'trace', 'instructions ' .. n, 'static_instructions ' .. static_count, 'mix ' .. table.concat(mix, ' '),
        'branches ' .. branches .. ' taken ' .. taken .. ' backward ' .. backward,
        'jumps ' .. jumps .. ' indirect ' .. indirect .. ' link ' .. links,
        'static_control branches ' .. static_branches .. ' jumps ' .. static_jumps,
        'memory loads ' .. value(counts, 'LOAD') .. ' stores ' .. value(counts, 'STORE') .. ' distinct_addresses ' .. #ordered_keys(addresses),
        'operands ' .. source_count .. ' with_producer ' .. produced .. ' distance ' .. table.concat(distance_parts, ' ')}
    local prediction_part = {'prediction'}
    for _, definition in ipairs(config.predictors) do
        local prediction = predictions[definition.name]
        local s = prediction.statistics
        prediction_part[#prediction_part + 1] = definition.name .. ' ' .. definition.scheme .. ' bits ' .. prediction.bits
            .. ' control ' .. value(s, 'control') .. ' mispredicted ' .. value(s, 'mispredictions')
            .. ' accuracy ' .. accuracy(prediction) .. ' branches ' .. accuracy(prediction, 'BRANCH') .. ' jumps ' .. accuracy(prediction, 'JUMP')
            .. ' direction ' .. value(s, 'direction') .. ' btb_miss ' .. value(s, 'btb_miss') .. ' wrong_target ' .. value(s, 'wrong_target')
    end
    local s = predictions[config.predictors[1].name].statistics
    prediction_part[#prediction_part + 1] = 'btb entries ' .. config.btb .. ' lookups ' .. value(s, 'lookups') .. ' hits ' .. value(s, 'hits') .. ' misses ' .. value(s, 'lookups') - value(s, 'hits')
    prediction_part[#prediction_part + 1] = 'ras depth ' .. config.ras .. ' calls ' .. value(s, 'calls') .. ' returns ' .. value(s, 'returns') .. ' predicted ' .. value(s, 'ras_predictions') .. ' correct ' .. value(s, 'ras_correct')
    local lengths, finish, height, flushed = {}, {}, 0, 0
    for _, delay in ipairs(primary.delays) do if delay > 0 then increment(lengths, math.min(5, delay)) end end
    for i, instruction in ipairs(instructions) do
        local start = 0
        for _, source in ipairs(sources[i]) do if source.producer then start = math.max(start, finish[source.producer]) end end
        local cost = instruction.class == 'LOAD' and 2 or instruction.class == 'MUL' and primary.variant.latency or 1
        finish[i] = start + cost
        height = math.max(height, finish[i])
    end
    for _, row in ipairs(rows) do if not row.number then flushed = flushed + 1 end end
    local stalls = 0
    for _, cause in ipairs(causes) do stalls = stalls + value(primary.stalls, cause) end
    local length_parts = {}
    for i = 1, 5 do length_parts[#length_parts + 1] = (i == 5 and '5+' or tostring(i)) .. ' ' .. value(lengths, i) end
    local timing = {'timing variant=' .. primary.variant.name .. ' predictor=' .. primary.predictor,
        'forwarding ' .. (primary.variant.forwarding and 'on' or 'off') .. ' branch_stage ' .. primary.variant.stage .. ' mul_latency ' .. primary.variant.latency,
        'cycles ' .. primary.cycles, 'cpi ' .. report.fraction(primary.cycles, n) .. ' ' .. report.decimal(primary.cycles, n),
        'ipc ' .. report.decimal(n, primary.cycles), 'stall_cycles total ' .. stalls .. ' ' .. cause_values(primary.stalls),
        'stall_events ' .. cause_values(primary.events), 'flushed ' .. flushed,
        'cycle_check ' .. n .. ' + 4 + ' .. stalls .. ' = ' .. n + 4 + stalls,
        'cpi_stack base 1.0000 fill ' .. report.decimal(4, n) .. ' ' .. cause_values(primary.stalls, function(v) return report.decimal(v, n) end),
        'stall_lengths ' .. table.concat(length_parts, ' '), 'dataflow height ' .. height .. ' ilp ' .. report.decimal(n, height)}
    local whatif, flags = {'whatif'}, predictions[primary.predictor].flags
    for change = 1, 4 do
        local variant = {}
        for key, item in pairs(primary.variant) do variant[key] = item end
        local name, missed = '', flags
        if change == 1 then
            name, missed = 'perfect_prediction', {}
            for i = 1, n do missed[i] = false end
        elseif change == 2 then name, variant.latency = 'single_cycle_mul', 1
        elseif change == 3 then
            name = variant.forwarding and 'forwarding_off' or 'forwarding_on'
            variant.forwarding = not variant.forwarding
        else
            variant.stage = variant.stage == 'ID' and 'EX' or 'ID'
            name = 'branch_stage_' .. variant.stage
        end
        local cycles = pipeline.simulate(instructions, sources, variant, missed).cycles
        whatif[#whatif + 1] = name .. ' cycles ' .. cycles .. ' saved ' .. primary.cycles - cycles .. ' speedup ' .. report.decimal(primary.cycles, cycles)
    end
    local class_stalls, by_pc, dependencies = aggregate(instructions, primary.records)
    local class_part = {'classes'}
    for _, kind in ipairs(classes) do
        class_part[#class_part + 1] = kind .. ' count ' .. value(counts, kind) .. ' stall_cycles ' .. value(class_stalls, kind)
            .. ' per_instruction ' .. (value(counts, kind) > 0 and report.decimal(value(class_stalls, kind), counts[kind]) or '-')
    end
    local paths = {}
    for i, instruction in ipairs(instructions) do
        for _, source in ipairs(sources[i]) do
            increment(paths, hazards.path(instruction, source.producer and primary.timings[source.producer], primary.timings[i], primary.variant))
        end
    end
    local forwarding = {'forwarding regfile ' .. value(paths, 'regfile') .. ' ex_mem ' .. value(paths, 'ex_mem') .. ' mem_wb ' .. value(paths, 'mem_wb')}
    local occupied = {}
    for i = 1, 5 do occupied[i] = {0, 0} end
    for _, row in ipairs(rows) do
        for _, span in ipairs(row.stages) do
            local slot = row.number and 1 or 2
            occupied[span[1]][slot] = occupied[span[1]][slot] + span[3] - span[2] + 1
        end
    end
    local occupancy_part = {'occupancy cycles ' .. primary.cycles}
    for i, stage in ipairs(stages) do
        local a, b = table.unpack(occupied[i])
        occupancy_part[#occupancy_part + 1] = stage .. ' correct ' .. a .. ' wrong ' .. b .. ' idle ' .. primary.cycles - a - b .. ' busy ' .. report.percentage(a + b, primary.cycles)
    end
    local ranked, totals_by_pc = ordered_keys(by_pc), {}
    for _, pc in ipairs(ranked) do
        totals_by_pc[pc] = 0
        for _, cause in ipairs(causes) do totals_by_pc[pc] = totals_by_pc[pc] + value(by_pc[pc], cause) end
    end
    table.sort(ranked, function(a, b) if totals_by_pc[a] ~= totals_by_pc[b] then return totals_by_pc[a] > totals_by_pc[b] end return a < b end)
    local hotspots = {'hotspots'}
    for rank = 1, math.min(config.top, #ranked) do
        local pc = ranked[rank]
        hotspots[#hotspots + 1] = rank .. ' ' .. report.hex(pc) .. ' ' .. trace.static[pc].class .. ' stall_cycles ' .. totals_by_pc[pc] .. ' ' .. cause_values(by_pc[pc])
    end
    local dependency_part = {'dependencies total ' .. #dependencies}
    for rank = 1, math.min(config.top, #dependencies) do
        local item = dependencies[rank]
        dependency_part[#dependency_part + 1] = rank .. ' ' .. report.hex(item.producer) .. ' ' .. trace.static[item.producer].class .. ' -> '
            .. report.hex(item.waiting) .. ' ' .. trace.static[item.waiting].class .. ' ' .. item.cause .. ' stall_cycles ' .. item.cycles .. ' events ' .. item.events
    end
    local intervals = {'intervals size ' .. config.interval}
    for first = 1, n, config.interval do
        local last = math.min(n, first + config.interval - 1)
        local cycles = primary.timings[last].W - (first > 1 and primary.timings[first - 1].W or 0)
        intervals[#intervals + 1] = first .. '-' .. last .. ' cycles ' .. cycles .. ' cpi ' .. report.decimal(cycles, last - first + 1)
    end
    local names = {}
    for _, definition in ipairs(config.predictors) do names[#names + 1] = definition.name end
    local cycle_table = {'cycles_table ' .. table.concat(names, ' ')}
    for _, variant in ipairs(config.variants) do
        local values = {variant.name}
        for _, definition in ipairs(config.predictors) do
            for _, pair in ipairs(combinations_list) do
                if pair.variant.name == variant.name and pair.predictor == definition.name then values[#values + 1] = pair.cycles end
            end
        end
        cycle_table[#cycle_table + 1] = join(values)
    end
    return report.join({input, trace_part, prediction_part, timing, whatif, class_part, forwarding, occupancy_part, hotspots, dependency_part, intervals, cycle_table})
end
local function branch_lines(instructions, groups, pcs, predictions, config)
    local lines = {'predictor,pc,class,executions,taken,mispredictions,accuracy'}
    for _, definition in ipairs(config.predictors) do
        for _, pc in ipairs(pcs) do
            local indices, taken, missed = groups[pc], 0, 0
            local instruction = instructions[indices[1]]
            if control(instruction) then
                for _, i in ipairs(indices) do
                    if instructions[i].outcome == 'T' then taken = taken + 1 end
                    if predictions[definition.name].flags[i] then missed = missed + 1 end
                end
                lines[#lines + 1] = join({definition.name, report.hex(pc), instruction.class, #indices, taken, missed, report.percentage(#indices - missed, #indices)}, ',')
            end
        end
    end
    return lines
end
local function comparison_lines(pairs, primary, predictions, count)
    local lines = {'rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw'}
    for rank, pair in ipairs(pairs) do
        local values = {rank, pair.variant.name, pair.predictor, pair.cycles, report.decimal(pair.cycles, count), report.decimal(primary.cycles, pair.cycles),
            accuracy(predictions[pair.predictor]), value(predictions[pair.predictor].statistics, 'mispredictions')}
        for _, cause in ipairs(causes) do values[#values + 1] = value(pair.stalls, cause) end
        lines[#lines + 1] = join(values, ',')
    end
    return lines
end
local function profile_lines(instructions, groups, pcs, predictions, primary, config)
    local branches, loops, indirect, static = {'branches'}, {'loops'}, {'indirect'}, {'instructions'}
    local stalled = {}
    for _, record in ipairs(primary.records) do increment(stalled, instructions[record.responsible].pc, record.cycles) end
    for _, pc in ipairs(pcs) do
        local indices = groups[pc]
        local instruction = instructions[indices[1]]
        if instruction.class == 'BRANCH' then
            local taken, transitions, previous, length = 0, 0, nil, 0
            local longest = {T = 0, N = 0}
            local trips, trip_length, max_trip = {}, 0, 0
            for _, i in ipairs(indices) do
                local outcome = instructions[i].outcome
                if outcome == 'T' then taken = taken + 1 end
                if previous and previous ~= outcome then transitions = transitions + 1 end
                length = previous == outcome and length + 1 or 1
                longest[outcome] = math.max(longest[outcome], length)
                previous = outcome
                trip_length = trip_length + 1
                if outcome == 'N' then trips[#trips + 1], trip_length = trip_length, 0 end
            end
            if trip_length > 0 then trips[#trips + 1] = trip_length end
            for _, trip in ipairs(trips) do max_trip = math.max(max_trip, trip) end
            local best, best_misses
            for _, definition in ipairs(config.predictors) do
                if definition.scheme ~= 'PERFECT' then
                    local missed = 0
                    for _, i in ipairs(indices) do if predictions[definition.name].flags[i] then missed = missed + 1 end end
                    if not best or missed < best_misses then best, best_misses = definition.name, missed end
                end
            end
            branches[#branches + 1] = report.hex(pc) .. ' ' .. (instruction.target < pc and 'backward' or 'forward') .. ' executions ' .. #indices
                .. ' taken ' .. taken .. ' transitions ' .. transitions .. ' longest_taken ' .. longest.T .. ' longest_not_taken ' .. longest.N .. ' best ' .. best .. ' ' .. best_misses
            if instruction.target < pc then
                loops[#loops + 1] = report.hex(instruction.target) .. '-' .. report.hex(pc) .. ' body ' .. (pc - instruction.target) // 4 + 1
                    .. ' entries ' .. #trips .. ' iterations ' .. #indices .. ' avg_trip ' .. report.decimal(#indices, #trips) .. ' max_trip ' .. max_trip
            end
        elseif instruction.class == 'JUMP' and instruction.rs1 then
            local targets = {}
            for _, i in ipairs(indices) do increment(targets, instructions[i].target) end
            local ordered = ordered_keys(targets)
            table.sort(ordered, function(a, b) if targets[a] ~= targets[b] then return targets[a] > targets[b] end return a < b end)
            local values = {}
            for _, target in ipairs(ordered) do values[#values + 1] = report.hex(target) .. ':' .. targets[target] end
            indirect[#indirect + 1] = report.hex(pc) .. ' executions ' .. #indices .. ' distinct ' .. #ordered .. ' targets ' .. table.concat(values, ' ')
        end
        static[#static + 1] = report.hex(pc) .. ' ' .. instruction.class .. ' ' .. report.register(instruction.rd) .. ' ' .. report.register(instruction.rs1)
            .. ' ' .. report.register(instruction.rs2) .. ' executions ' .. #indices .. ' stall_cycles ' .. value(stalled, pc)
    end
    local segments, first = {}, 1
    for last, instruction in ipairs(instructions) do
        if control(instruction) or last == #instructions then
            local pc = instructions[first].pc
            local group = segments[pc] or {instances = 0, instructions = 0, cycles = 0}
            group.instances = group.instances + 1
            group.instructions = group.instructions + last - first + 1
            group.cycles = group.cycles + primary.timings[last].W - (first > 1 and primary.timings[first - 1].W or 0)
            segments[pc], first = group, last + 1
        end
    end
    local ranked = ordered_keys(segments)
    table.sort(ranked, function(a, b) if segments[a].cycles ~= segments[b].cycles then return segments[a].cycles > segments[b].cycles end return a < b end)
    local segment_lines = {'segments total ' .. #ranked}
    for rank = 1, math.min(config.top, #ranked) do
        local pc = ranked[rank]
        local group = segments[pc]
        segment_lines[#segment_lines + 1] = rank .. ' ' .. report.hex(pc) .. ' instances ' .. group.instances .. ' instructions ' .. group.instructions
            .. ' cycles ' .. group.cycles .. ' cpi ' .. report.decimal(group.cycles, group.instructions)
    end
    return report.join({branches, loops, segment_lines, indirect, static})
end
local lines, config = trace_io.read()
local trace = validate(lines)
local instructions = trace.instructions
local sources = hazards.dependencies(instructions)
local predictions = {}
for _, definition in ipairs(config.predictors) do predictions[definition.name] = predict(instructions, definition, config) end
local pairs, primary = combinations(instructions, sources, predictions, config)
local rows = build_rows(instructions, primary, predictions[primary.predictor])
local groups, pcs = group_instructions(instructions)
report.write('pipeline.txt', pipeline_lines(rows, primary, config))
report.write('stats.txt', statistics_lines(trace, sources, predictions, pairs, primary, rows, config))
report.write('branches.csv', branch_lines(instructions, groups, pcs, predictions, config))
report.write('comparison.csv', comparison_lines(pairs, primary, predictions, #instructions))
report.write('profile.txt', profile_lines(instructions, groups, pcs, predictions, primary, config))
