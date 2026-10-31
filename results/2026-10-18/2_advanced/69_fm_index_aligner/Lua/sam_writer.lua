local reverse_complement = require('sequence_io').reverse_complement
local M = {}
function M.ratio(numerator, denominator)
    return denominator == 0 and '-' or string.format('%.4f', numerator / denominator)
end
function M.header(references)
    local result = {'@HD\tVN:1.6\tSO:unsorted'}
    for _, reference in ipairs(references) do result[#result + 1] = '@SQ\tSN:' .. reference.name .. '\tLN:' .. #reference.bases end
    result[#result + 1] = '@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0'
    return result
end
function M.record(result, references, maximum_alternatives)
    local read = result.read
    if not result.mapped then return table.concat({read.name, 4, '*', 0, 0, '*', '*', 0, 0, read.bases, read.quality, 'YM:Z:' .. result.reason}, '\t') end
    local alignment = result.primary
    local reverse = alignment.strand == '-'
    local fields = {read.name, reverse and 16 or 0, references[alignment.reference].name, alignment.position + 1, result.mapq, alignment.cigar, '*', 0, 0,
        reverse and reverse_complement(read.bases) or read.bases, reverse and read.quality:reverse() or read.quality,
        'NM:i:' .. alignment.nm, 'MD:Z:' .. alignment.md, 'AS:i:' .. result.score, 'X0:i:' .. result.x0, 'X1:i:' .. result.x1, 'YM:Z:' .. result.method}
    if #result.others >= 1 and #result.others <= maximum_alternatives then
        local alternatives = {}
        for _, other in ipairs(result.others) do alternatives[#alternatives + 1] = references[other.reference].name .. ',' .. other.strand .. (other.position + 1) .. ',' .. other.cigar .. ',' .. other.nm .. ';' end
        fields[#fields + 1] = 'XA:Z:' .. table.concat(alternatives)
    end
    return table.concat(fields, '\t')
end
function M.write_lines(path, lines)
    local file = assert(io.open(path, 'wb'))
    if #lines > 0 then file:write(table.concat(lines, '\n'), '\n') end
    file:close()
end
return M
