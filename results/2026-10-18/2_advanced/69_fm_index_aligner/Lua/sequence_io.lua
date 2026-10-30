local M = {}
local complement = {A = 'T', C = 'G', G = 'C', T = 'A', N = 'N'}
function M.reverse_complement(sequence)
    local result = sequence:reverse():gsub('.', complement)
    return result
end
function M.read_inputs()
    local references, current = {}, nil
    for line in io.lines('input/reference.fasta') do
        if line:sub(1, 1) == '>' then
            current = {name = line:match('^>([^ ]+)'), parts = {}, masked = 0}
            references[#references + 1] = current
        else
            local _, count = line:gsub('[acgt]', '')
            current.masked = current.masked + count
            current.parts[#current.parts + 1] = line:upper()
        end
    end
    for _, reference in ipairs(references) do
        reference.bases = table.concat(reference.parts)
        reference.parts = nil
    end
    local lines, reads, params = {}, {}, {}
    for line in io.lines('input/reads.fastq') do lines[#lines + 1] = line end
    for i = 1, #lines, 4 do
        reads[#reads + 1] = {name = lines[i]:sub(2), bases = lines[i + 1], quality = lines[i + 3]}
    end
    for line in io.lines('input/params.txt') do
        local name = line:match('^([^ ]+)')
        local values = {}
        for value in line:gmatch(' %-?%d+') do values[#values + 1] = tonumber(value) end
        params[name] = values
    end
    return references, reads, params
end
return M
