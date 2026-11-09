local hazards = require('hazards')
local M = {causes = {'control', 'structural', 'load_use', 'raw'}, stages = {'IF', 'ID', 'EX', 'MEM', 'WB'}}
function M.simulate(instructions, sources, variant, missed)
    local timings, records, delays = {}, {}, {}
    for i, instruction in ipairs(instructions) do
        local length = instruction.class == 'MUL' and variant.latency or 1
        local fetch, decode, start = 1, 2, 3
        if i > 1 then
            local previous = timings[i - 1]
            fetch = missed[i - 1] and previous.X + (hazards.id_resolved(instructions[i - 1], variant) and 0 or 1) or previous.D
            decode = math.max(fetch + 1, previous.X)
            local ideal = previous.X + 1
            local ready = {ideal, ideal}
            local producers = {}
            for _, source in ipairs(sources[i]) do
                local p = source.producer
                if p then
                    local cycle = hazards.ready(instruction, instructions[p], timings[p], variant)
                    local slot = instructions[p].class == 'LOAD' and 1 or 2
                    if cycle > ready[slot] then ready[slot], producers[slot] = cycle, p end
                end
            end
            local bounds = {decode + 1, previous.M, ready[1], ready[2]}
            start = ideal
            for c, bound in ipairs(bounds) do
                if bound > start then
                    records[#records + 1] = {cause = M.causes[c], cycles = bound - start,
                        responsible = c <= 2 and i - 1 or i, waiting = i, producer = producers[c - 2]}
                    start = bound
                end
            end
            delays[#delays + 1] = start - ideal
        end
        timings[i] = {F = fetch, D = decode, X = start, M = start + length, W = start + length + 1}
    end
    if instructions[#instructions].class == 'MUL' and variant.latency >= 2 then
        records[#records + 1] = {cause = 'structural', cycles = variant.latency - 1, responsible = #instructions}
    end
    return {timings = timings, records = records, delays = delays, cycles = timings[#timings].W}
end
return M
