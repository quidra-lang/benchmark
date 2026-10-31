local M = {}
function M.dependencies(instructions)
    local last, result = {}, {}
    for i, instruction in ipairs(instructions) do
        local operands = {}
        for _, field in ipairs({'rs1', 'rs2'}) do
            local register = instruction[field]
            if register and register ~= 0 then
                operands[#operands + 1] = {register = register, producer = last[register]}
            end
        end
        result[i] = operands
        if instruction.rd and instruction.rd ~= 0 then last[instruction.rd] = i end
    end
    return result
end
function M.id_resolved(instruction, variant)
    return instruction.class == 'JUMP' and not instruction.rs1
        or (instruction.class == 'BRANCH' or instruction.class == 'JUMP') and variant.stage == 'ID'
end
function M.ready(instruction, producer, timing, variant)
    if not variant.forwarding then return timing.W + 1 end
    local result = producer.class == 'LOAD' and timing.W or timing.M
    return result + (M.id_resolved(instruction, variant) and 1 or 0)
end
function M.path(instruction, producer_time, instruction_time, variant)
    if not producer_time or not variant.forwarding then return 'regfile' end
    local resolved = M.id_resolved(instruction, variant)
    local use = instruction_time.X - (resolved and 1 or 0)
    if producer_time.M == use then return 'ex_mem' end
    if not resolved and producer_time.W == use then return 'mem_wb' end
    return 'regfile'
end
return M
