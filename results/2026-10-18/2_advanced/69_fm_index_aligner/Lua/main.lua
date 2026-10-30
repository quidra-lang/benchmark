package.path = 'Lua/?.lua;' .. package.path
local sequence_io = require('sequence_io')
local suffix_array = require('suffix_array')
local FMIndex = require('fm_index')
local search = require('search')
local sam = require('sam_writer')
local ratio, reverse_complement = sam.ratio, sequence_io.reverse_complement
local references, reads, params = sequence_io.read_inputs()
local function value(name) return params[name][1] end
local function line(lines, ...) lines[#lines + 1] = table.concat({...}, ' ') end
local function increment(counts, key, amount) counts[key] = (counts[key] or 0) + (amount or 1) end
local function keys(values, descending)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result, descending and function(a, b) return a > b end or nil)
    return result
end
local function sum(values)
    local total = 0
    for _, item in ipairs(values) do total = total + item end
    return total
end
local function count_char(text, c)
    local count = 0
    for i = 1, #text do if text:sub(i, i) == c then count = count + 1 end end
    return count
end
local function operation_runs(operations)
    local result, first = {}, 1
    while first <= #operations do
        local next_position = first + 1
        local op = operations:sub(first, first)
        while next_position <= #operations and operations:sub(next_position, next_position) == op do next_position = next_position + 1 end
        result[#result + 1] = {op, next_position - first}
        first = next_position
    end
    return result
end
local offsets, parts, offset = {}, {}, 0
for r, reference in ipairs(references) do offsets[r] = offset; parts[r] = reference.bases; offset = offset + #reference.bases + 1 end
local text = table.concat(parts, '#') .. '$'
local reverse_text = text:sub(1, -2):reverse() .. '$'
local function locate_position(position)
    local low, high = 1, #references
    while low <= high do
        local middle = (low + high) // 2
        if offsets[middle] <= position then low = middle + 1 else high = middle - 1 end
    end
    if high < 1 or position - offsets[high] >= #references[high].bases then return nil end
    return high, position - offsets[high]
end
local function position_label(position)
    local reference, position_in_reference = locate_position(position)
    return reference and references[reference].name .. ':' .. (position_in_reference + 1) or '*'
end
local suffixes, classes = suffix_array.build(text)
local reverse_suffixes, reverse_classes = suffix_array.build(reverse_text)
local forward = FMIndex.new(text, suffixes, value('OCC_INTERVAL'), value('SA_SAMPLE_INTERVAL'))
local reverse = FMIndex.new(reverse_text, reverse_suffixes, value('OCC_INTERVAL'))
local function describe(reference, position, strand, operations, core, trimmed)
    local oriented = strand == '+' and core or reverse_complement(core)
    local sequence = references[reference].bases
    local cigar, md, pairs = {}, {}, {}
    local i, j, matches, nm = 0, position, 0, 0
    for _, run in ipairs(operation_runs(operations)) do
        local op, count = table.unpack(run)
        cigar[#cigar + 1] = count .. op
        if op == 'I' then i = i + count; nm = nm + count
        elseif op == 'D' then
            md[#md + 1] = matches .. '^' .. sequence:sub(j + 1, j + count)
            matches, j, nm = 0, j + count, nm + count
        else
            for _ = 1, count do
                pairs[#pairs + 1] = {i, j}
                if oriented:sub(i + 1, i + 1) == sequence:sub(j + 1, j + 1) then matches = matches + 1
                else md[#md + 1] = matches .. sequence:sub(j + 1, j + 1); matches, nm = 0, nm + 1 end
                i, j = i + 1, j + 1
            end
        end
    end
    md[#md + 1] = tostring(matches)
    if trimmed > 0 then
        if strand == '+' then cigar[#cigar + 1] = trimmed .. 'S' else table.insert(cigar, 1, trimmed .. 'S') end
    end
    return {reference = reference, position = position, strand = strand, operations = operations, oriented = oriented, pairs = pairs,
        cigar = table.concat(cigar), nm = nm, md = table.concat(md)}
end
local function get(matrix, i, j) return matrix[i] and matrix[i][j] end
local function subtract(number, penalty) return number and number - penalty end
local function maximum(...)
    local result
    for i = 1, select('#', ...) do
        local item = select(i, ...)
        if item ~= nil and (result == nil or item > result) then result = item end
    end
    return result
end
local function banded_alignment(oriented, sequence, center)
    local match, mismatch, gap_open, gap_extend = table.unpack(params.SCORES)
    local length, reference_length, width = #oriented, #sequence, value('BAND_WIDTH')
    local h, e, f = {[0] = {}}, {}, {}
    for j = math.max(0, center - width), math.min(reference_length, center + width) do h[0][j] = 0 end
    for i = 1, length do
        h[i], e[i], f[i] = {}, {}, {}
        for j = math.max(0, i + center - width), math.min(reference_length, i + center + width) do
            f[i][j] = maximum(subtract(get(h, i - 1, j), gap_open + gap_extend), subtract(get(f, i - 1, j), gap_extend))
            local diagonal
            if j >= 1 then
                e[i][j] = maximum(subtract(get(h, i, j - 1), gap_open + gap_extend), subtract(get(e, i, j - 1), gap_extend))
                local previous = get(h, i - 1, j - 1)
                if previous then diagonal = previous + (oriented:sub(i, i) == sequence:sub(j, j) and match or -mismatch) end
            end
            h[i][j] = maximum(diagonal, e[i][j], f[i][j])
        end
    end
    local score, column
    for j = math.max(0, length + center - width), math.min(reference_length, length + center + width) do
        local candidate = get(h, length, j)
        if candidate and (not score or candidate > score) then score, column = candidate, j end
    end
    if not score then return nil end
    local row, state, backward = length, 'H', {}
    while true do
        if state == 'H' then
            if row == 0 then break end
            local previous = column >= 1 and get(h, row - 1, column - 1) or nil
            local delta = oriented:sub(row, row) == sequence:sub(column, column) and match or -mismatch
            if previous and h[row][column] == previous + delta then
                backward[#backward + 1] = 'M'
                row, column = row - 1, column - 1
            else state = get(f, row, column) and h[row][column] == f[row][column] and 'I' or 'D' end
        elseif state == 'I' then
            backward[#backward + 1] = 'I'
            local previous = get(f, row - 1, column)
            state = previous and f[row][column] == previous - gap_extend and 'I' or 'H'
            row = row - 1
        else
            backward[#backward + 1] = 'D'
            local previous = get(e, row, column - 1)
            state = previous and e[row][column] == previous - gap_extend and 'D' or 'H'
            column = column - 1
        end
    end
    return score, column, table.concat(backward):reverse()
end
local search_counts = {calls = 0, nodes = 0, leaves = 0, positions = 0}
local seed_counts = {reads = 0, seeds = 0, with_n = 0, repetitive = 0, without_hit = 0, candidates = 0, passing = 0}
local function finish(result, alignments, method, score, mapq, best_count, second_count, target_set)
    result.mapped, result.primary, result.others = true, alignments[1], {}
    for i = 2, #alignments do result.others[#result.others + 1] = alignments[i] end
    result.method, result.score, result.mapq, result.x0, result.x1 = method, score, mapq, best_count, second_count
    result.targets = keys(target_set)
end
local function tuple_less(a, b)
    for i = 1, #a do if a[i] ~= b[i] then return a[i] < b[i] end end
    return false
end
local function map_read(read)
    local qualities = {}
    for i = 1, #read.quality do qualities[i] = read.quality:byte(i) - 33 end
    local length = #read.bases
    while length > 0 and qualities[length] < value('TRIM_QUALITY') do length = length - 1 end
    local result = {read = read, core = read.bases:sub(1, length), qualities = qualities, length = length, trimmed = #read.bases - length, mapped = false, reason = 'SHORT'}
    if length < value('MIN_READ_LENGTH') then return result end
    local oriented = {result.core, reverse_complement(result.core)}
    local maximum_mismatches = value('MAX_MISMATCHES')
    for _, sequence in ipairs(oriented) do local lower, upper = forward:backward_search(sequence); if lower < upper then maximum_mismatches = 1 end end
    local hits = {}
    for strand = 0, 1 do
        local nodes, leaves, positions = search.backtrack(oriented[strand + 1], maximum_mismatches, forward, reverse)
        increment(search_counts, 'calls'); increment(search_counts, 'nodes', nodes); increment(search_counts, 'leaves', #leaves); increment(search_counts, 'positions', positions)
        for _, leaf in ipairs(leaves) do
            for row = leaf[1], leaf[2] - 1 do
                local reference, position = locate_position(forward:locate(row))
                hits[#hits + 1] = {leaf[3], reference, position, strand}
            end
        end
    end
    if #hits > 0 then
        table.sort(hits, tuple_less)
        local best, best_count, second_count, targets, alignments = hits[1][1], 0, 0, {}, {}
        for _, hit in ipairs(hits) do
            if hit[1] == best then best_count = best_count + 1; targets[hit[2]] = true end
            if hit[1] == best + 1 then second_count = second_count + 1 end
            if hit[1] <= best + 1 then alignments[#alignments + 1] = describe(hit[2], hit[3], hit[4] == 0 and '+' or '-', string.rep('M', length), result.core, result.trimmed) end
        end
        local mapq = best_count >= 2 and 0 or second_count == 0 and 60 - 12 * best or math.max(30 - 12 * best - 3 * second_count, 1)
        finish(result, alignments, best == 0 and 'EXACT' or 'MISMATCH', (length - best) * params.SCORES[1] - best * params.SCORES[2], mapq, best_count, second_count, targets)
        return result
    end
    result.reason = 'NOHIT'
    if length < value('SEED_LENGTH') then return result end
    increment(seed_counts, 'reads')
    local candidates, seen = {}, {}
    local seed_length = value('SEED_LENGTH')
    for strand = 0, 1 do
        local sequence = oriented[strand + 1]
        for seed_offset = 0, length - seed_length, value('SEED_STEP') do
            increment(seed_counts, 'seeds')
            local seed = sequence:sub(seed_offset + 1, seed_offset + seed_length)
            if seed:find('N', 1, true) then increment(seed_counts, 'with_n')
            else
                local lower, upper = forward:backward_search(seed)
                if upper - lower > value('MAX_SEED_HITS') then increment(seed_counts, 'repetitive')
                elseif lower >= upper then increment(seed_counts, 'without_hit')
                else
                    for row = lower, upper - 1 do
                        local reference, position = locate_position(forward:locate(row))
                        local center = position - seed_offset
                        local key = strand .. ':' .. reference .. ':' .. center
                        if not seen[key] then seen[key] = true; candidates[#candidates + 1] = {strand, reference, center} end
                    end
                end
            end
        end
    end
    table.sort(candidates, tuple_less)
    increment(seed_counts, 'candidates', #candidates)
    local accepted = {}
    for _, candidate in ipairs(candidates) do
        local strand, reference, center = table.unpack(candidate)
        local score, position, operations = banded_alignment(oriented[strand + 1], references[reference].bases, center)
        if score and 100 * score >= value('MIN_SCORE_PERCENT') * params.SCORES[1] * length then
            local key = reference .. ':' .. position .. ':' .. strand
            if not accepted[key] or score > accepted[key].score then accepted[key] = {score = score, reference = reference, position = position, strand = strand, operations = operations} end
        end
    end
    local ordered = {}
    for _, alignment in pairs(accepted) do ordered[#ordered + 1] = alignment end
    increment(seed_counts, 'passing', #ordered)
    if #ordered == 0 then return result end
    table.sort(ordered, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.reference ~= b.reference then return a.reference < b.reference end
        if a.position ~= b.position then return a.position < b.position end
        return a.strand < b.strand
    end)
    local best, best_count, second, alignments, targets = ordered[1].score, 0, 0, {}, {}
    for _, item in ipairs(ordered) do
        if item.score == best then best_count = best_count + 1; targets[item.reference] = true else second = math.max(second, item.score) end
        alignments[#alignments + 1] = describe(item.reference, item.position, item.strand == 0 and '+' or '-', item.operations, result.core, result.trimmed)
    end
    finish(result, alignments, 'SEED', best, best_count >= 2 and 0 or 60 * (best - second) // best, best_count, #ordered - best_count, targets)
    return result
end

local function index_statistics()
    local lines, size = {}, #text
    line(lines, 'text length', size, 'sequences', #references)
    for r, reference in ipairs(references) do
        line(lines, 'sequence', reference.name, 'length', #reference.bases, 'offset', offsets[r], 'gc', ratio(count_char(reference.bases, 'G') + count_char(reference.bases, 'C'), #reference.bases), 'masked', reference.masked)
    end
    local symbols = {'symbols'}
    for i = 1, 6 do local c = suffix_array.symbols:sub(i, i); symbols[#symbols + 1] = c; symbols[#symbols + 1] = count_char(text, c) end
    lines[#lines + 1] = table.concat(symbols, ' ')
    lines[#lines + 1] = ''; lines[#lines + 1] = 'forward_index'
    line(lines, 'suffix_array rounds', #classes - 1)
    for i, count in ipairs(classes) do line(lines, 'round', i - 1, 'prefix_length', 1 << (i - 1), 'classes', count) end
    local ordered, lcp_sum, longest, row = suffix_array.adjacent_check(text, suffixes)
    line(lines, 'sa_check pairs', size - 1, 'ordered', ordered, 'lcp_sum', lcp_sum, 'mean_lcp', ratio(lcp_sum, size - 1), 'max_lcp', longest)
    line(lines, 'longest_repeat', longest, position_label(suffixes[row - 1]), position_label(suffixes[row]))
    local kmers, occurrences, unique, max_occurrence = {}, 0, 0, 0
    local length = value('SEED_LENGTH')
    for _, reference in ipairs(references) do
        for position = 1, #reference.bases - length + 1 do increment(kmers, reference.bases:sub(position, position + length - 1)) end
    end
    local distinct = 0
    for _, count in pairs(kmers) do distinct = distinct + 1; occurrences = occurrences + count; if count == 1 then unique = unique + 1 end; max_occurrence = math.max(max_occurrence, count) end
    line(lines, 'kmers length', length, 'occurrences', occurrences, 'distinct', distinct, 'unique', unique, 'max_occurrence', max_occurrence, 'unique_fraction', ratio(unique, occurrences))
    line(lines, 'bwt runs', #operation_runs(forward.bwt), 'head', forward.bwt:sub(1, 60))
    local c_array = {'c_array'}
    for i = 1, 6 do local c = suffix_array.symbols:sub(i, i); c_array[#c_array + 1] = c; c_array[#c_array + 1] = forward.C[c] end
    lines[#lines + 1] = table.concat(c_array, ' ')
    line(lines, 'occ interval', forward.interval, 'checkpoints', #forward.checkpoints)
    line(lines, 'sa_sample interval', value('SA_SAMPLE_INTERVAL'), 'samples', forward.sample_count)
    local correct, total_steps, maximum_steps = 0, 0, 0
    for index, position in ipairs(suffixes) do
        local found, steps = forward:locate(index - 1)
        if found == position then correct = correct + 1 end
        total_steps, maximum_steps = total_steps + steps, math.max(maximum_steps, steps)
    end
    line(lines, 'locate rows', size, 'correct', correct, 'total_steps', total_steps, 'max_steps', maximum_steps, 'mean_steps', ratio(total_steps, size))
    line(lines, 'inverse_bwt identical', forward:inverse() == text and 'yes' or 'no')
    lines[#lines + 1] = ''; lines[#lines + 1] = 'reverse_index'
    line(lines, 'suffix_array rounds', #reverse_classes - 1)
    local reverse_ordered = suffix_array.adjacent_check(reverse_text, reverse_suffixes)
    line(lines, 'sa_check pairs', size - 1, 'ordered', reverse_ordered)
    line(lines, 'bwt runs', #operation_runs(reverse.bwt), 'head', reverse.bwt:sub(1, 60))
    line(lines, 'inverse_bwt identical', reverse:inverse() == reverse_text and 'yes' or 'no')
    lines[#lines + 1] = ''; lines[#lines + 1] = 'direct_sort'
    local checks = 0
    for _, reference in ipairs(references) do
        if #reference.bases <= value('DIRECT_SORT_LIMIT') then
            local sequence = reference.bases .. '$'
            local doubled, counts = suffix_array.build(sequence)
            local direct, identical = suffix_array.direct_sort(sequence), true
            for i = 1, #doubled do if doubled[i] ~= direct[i] then identical = false end end
            line(lines, reference.name, 'length', #sequence, 'rounds', #counts - 1, 'identical', identical and 'yes' or 'no')
            checks = checks + 1
        end
    end
    if checks == 0 then lines[#lines + 1] = 'none' end
    local occurrence_bytes, sample_bytes, bitmap_bytes = 24 * #forward.checkpoints, 4 * forward.sample_count, (size + 7) // 8
    local total_bytes = size + occurrence_bytes + sample_bytes + bitmap_bytes
    lines[#lines + 1] = ''
    line(lines, 'index_size bwt_bytes', size, 'occ_bytes', occurrence_bytes, 'sample_bytes', sample_bytes, 'bitmap_bytes', bitmap_bytes, 'total_bytes', total_bytes, 'full_bytes', 5 * size, 'ratio', ratio(total_bytes, 5 * size))
    return lines
end
local function coverage_and_variants(results)
    local depths, starts, pileups = {}, {}, {}
    for r, reference in ipairs(references) do
        depths[r], starts[r], pileups[r] = {}, {}, {}
        for j = 1, #reference.bases do depths[r][j], starts[r][j], pileups[r][j] = 0, 0, {{0, 0}, {0, 0}, {0, 0}, {0, 0}} end
    end
    local min_depth, min_quality, min_alt, hom_percent = table.unpack(params.VARIANTS)
    local minimum_mapq = value('COVERAGE_MIN_MAPQ')
    for _, result in ipairs(results) do
        if result.mapped then
            local alignment = result.primary
            local r, strand = alignment.reference, alignment.strand == '+' and 1 or 2
            if result.mapq == 0 then starts[r][alignment.position + 1] = starts[r][alignment.position + 1] + 1 end
            if result.mapq >= minimum_mapq then
                for _, pair in ipairs(alignment.pairs) do
                    local i, j = pair[1], pair[2] + 1
                    depths[r][j] = depths[r][j] + 1
                    local base = alignment.oriented:sub(i + 1, i + 1)
                    local cycle = strand == 1 and i + 1 or result.length - i
                    if base ~= 'N' and result.qualities[cycle] >= min_quality then
                        local b = suffix_array.bases:find(base, 1, true)
                        pileups[r][j][b][strand] = pileups[r][j][b][strand] + 1
                    end
                end
            end
        end
    end
    local window, coverage, variants = value('COVERAGE_WINDOW'), {}, {}
    line(coverage, 'window', window, 'min_mapq', minimum_mapq)
    line(variants, 'min_depth', min_depth, 'min_base_quality', min_quality, 'min_alt_percent', min_alt, 'hom_percent', hom_percent)
    local callable, variant_count, heterozygous, homozygous = 0, 0, 0, 0
    for r, reference in ipairs(references) do
        local length, depth, covered, histogram, maximum_depth = #reference.bases, depths[r], 0, {}, 0
        for _, count in ipairs(depth) do if count > 0 then covered = covered + 1 end; increment(histogram, count); maximum_depth = math.max(maximum_depth, count) end
        line(coverage, 'reference', reference.name, 'length', length, 'covered', covered, 'breadth', ratio(covered, length), 'mean_depth', ratio(sum(depth), length), 'max_depth', maximum_depth)
        local histogram_line = {'depth_histogram'}
        for count = 0, maximum_depth do histogram_line[#histogram_line + 1] = count .. ':' .. (histogram[count] or 0) end
        coverage[#coverage + 1] = table.concat(histogram_line, ' ')
        for first = 1, length, window do
            local last = math.min(first + window - 1, length)
            local total, zeros, mapq_zero, gc, maximum_window = 0, 0, 0, 0, 0
            for j = first, last do
                total = total + depth[j]; mapq_zero = mapq_zero + starts[r][j]; maximum_window = math.max(maximum_window, depth[j])
                if depth[j] == 0 then zeros = zeros + 1 end
                local base = reference.bases:sub(j, j); if base == 'G' or base == 'C' then gc = gc + 1 end
            end
            local size = last - first + 1
            line(coverage, reference.name, first, last, 'gc', ratio(gc, size), 'sum', total, 'mean', ratio(total, size), 'max', maximum_window, 'zero', zeros, 'mapq0', mapq_zero, '|' .. string.rep('#', 10 * total // size))
        end
        for j, strand_counts in ipairs(pileups[r]) do
            local counts, call_depth = {}, 0
            for b = 1, 4 do counts[b] = strand_counts[b][1] + strand_counts[b][2]; call_depth = call_depth + counts[b] end
            if call_depth >= min_depth then
                callable = callable + 1
                local reference_base, alternative = reference.bases:sub(j, j), nil
                for b = 1, 4 do
                    if suffix_array.bases:sub(b, b) ~= reference_base and (not alternative or counts[b] > counts[alternative]) then alternative = b end
                end
                local alt = counts[alternative]
                if alt >= 2 and 100 * alt >= min_alt * call_depth then
                    local homo = 100 * alt >= hom_percent * call_depth
                    if homo then homozygous = homozygous + 1 else heterozygous = heterozygous + 1 end
                    variant_count = variant_count + 1
                    line(variants, reference.name, j, reference_base .. '>' .. suffix_array.bases:sub(alternative, alternative), 'depth', call_depth, 'alt', alt, 'fraction', ratio(alt, call_depth), 'genotype', homo and '1/1' or '0/1', 'strands', strand_counts[alternative][1], strand_counts[alternative][2], 'counts', table.concat(counts, ' '))
                end
            end
        end
    end
    line(variants, 'callable', callable, 'variants', variant_count, 'heterozygous', heterozygous, 'homozygous', homozygous)
    return coverage, variants
end
local function error_statistics(results)
    local maximum_cycle = 0
    for _, result in ipairs(results) do maximum_cycle = math.max(maximum_cycle, #result.read.bases) end
    local cycles, substitutions, quality_counts, quality_sums, quality_bins = {}, {}, {0, 0}, {0, 0}, {}
    for cycle = 1, maximum_cycle do cycles[cycle] = {0, 0} end
    for base = 1, 4 do substitutions[base] = {0, 0, 0, 0, 0} end
    for bin = 1, 5 do quality_bins[bin] = {0, 0} end
    local operations, events, indel_bases = {M = 0, I = 0, D = 0, S = 0}, {I = 0, D = 0}, {I = 0, D = 0}
    for _, result in ipairs(results) do
        if result.mapped then
            local alignment = result.primary
            for i = 1, #alignment.operations do increment(operations, alignment.operations:sub(i, i)) end
            increment(operations, 'S', result.trimmed)
            if result.x0 == 1 then
                local sequence = references[alignment.reference].bases
                for _, pair in ipairs(alignment.pairs) do
                    local i, j = pair[1], pair[2]
                    local observed, reference = alignment.oriented:sub(i + 1, i + 1), sequence:sub(j + 1, j + 1)
                    local mismatch = observed == reference and 0 or 1
                    local cycle = alignment.strand == '+' and i + 1 or result.length - i
                    local quality = result.qualities[cycle]
                    cycles[cycle][1], cycles[cycle][2] = cycles[cycle][1] + 1, cycles[cycle][2] + mismatch
                    local rb, ob = suffix_array.bases:find(reference, 1, true), ('ACGTN'):find(observed, 1, true)
                    substitutions[rb][ob] = substitutions[rb][ob] + 1
                    quality_counts[mismatch + 1], quality_sums[mismatch + 1] = quality_counts[mismatch + 1] + 1, quality_sums[mismatch + 1] + quality
                    local bin = math.min(quality // 10, 4) + 1
                    quality_bins[bin][1], quality_bins[bin][2] = quality_bins[bin][1] + 1, quality_bins[bin][2] + mismatch
                end
                for _, run in ipairs(operation_runs(alignment.operations)) do
                    if run[1] == 'I' or run[1] == 'D' then increment(events, run[1]); increment(indel_bases, run[1], run[2]) end
                end
            end
        end
    end
    local aligned, mismatches, lines = sum(quality_counts), quality_counts[2], {}
    line(lines, 'error_profile aligned_bases', aligned, 'mismatches', mismatches, 'rate', ratio(mismatches, aligned))
    lines[#lines + 1] = 'substitutions'; lines[#lines + 1] = 'ref A C G T N'
    for b = 1, 4 do line(lines, suffix_array.bases:sub(b, b), table.concat(substitutions[b], ' ')) end
    lines[#lines + 1] = 'mismatch_by_cycle'
    for cycle, counts in ipairs(cycles) do line(lines, 'cycle', cycle, 'aligned', counts[1], 'mismatches', counts[2], 'rate', ratio(counts[2], counts[1])) end
    line(lines, 'quality matched', quality_counts[1], 'mean', ratio(quality_sums[1], quality_counts[1]), 'mismatched', quality_counts[2], 'mean', ratio(quality_sums[2], quality_counts[2]))
    lines[#lines + 1] = 'quality_bins'
    local names = {'0-9', '10-19', '20-29', '30-39', '40-'}
    for i, counts in ipairs(quality_bins) do line(lines, names[i], 'aligned', counts[1], 'mismatches', counts[2], 'rate', ratio(counts[2], counts[1])) end
    line(lines, 'cigar M', operations.M, 'I', operations.I, 'D', operations.D, 'S', operations.S)
    line(lines, 'indels insertions', events.I, indel_bases.I, 'deletions', events.D, indel_bases.D)
    return lines
end
local function mapping_statistics(results)
    local total, mapped, unique, trimmed, trimmed_bases = #results, {}, 0, 0, 0
    local reasons, methods, strands = {}, {}, {}
    for _, result in ipairs(results) do
        if result.trimmed > 0 then trimmed = trimmed + 1 end
        trimmed_bases = trimmed_bases + result.trimmed
        if result.mapped then
            mapped[#mapped + 1] = result
            if result.x0 == 1 then unique = unique + 1 end
            increment(methods, result.method); increment(strands, result.primary.strand)
        else increment(reasons, result.reason) end
    end
    local lines = {}
    line(lines, 'reads total', total, 'trimmed', trimmed, 'trimmed_bases', trimmed_bases, 'short', reasons.SHORT or 0)
    line(lines, 'mapped', #mapped, 'rate', ratio(#mapped, total), 'unique', unique, 'multi', #mapped - unique, 'unmapped', total - #mapped)
    line(lines, 'unmapped short', reasons.SHORT or 0, 'nohit', reasons.NOHIT or 0)
    line(lines, 'method exact', methods.EXACT or 0, 'mismatch', methods.MISMATCH or 0, 'seed', methods.SEED or 0)
    line(lines, 'strand forward', strands['+'] or 0, 'reverse', strands['-'] or 0)
    for r, reference in ipairs(references) do
        local count, unique_count, forward_count = 0, 0, 0
        for _, result in ipairs(mapped) do
            if result.primary.reference == r then count = count + 1; if result.x0 == 1 then unique_count = unique_count + 1 end; if result.primary.strand == '+' then forward_count = forward_count + 1 end end
        end
        line(lines, 'reference', reference.name, 'mapped', count, 'unique', unique_count, 'forward', forward_count, 'reverse', count - forward_count)
    end
    lines[#lines + 1] = 'length_bins'
    local minimum, maximum_length = math.huge, 0
    for _, result in ipairs(results) do minimum = math.min(minimum, result.length); maximum_length = math.max(maximum_length, result.length) end
    for lower = minimum // 10 * 10, maximum_length // 10 * 10, 10 do
        local count, mapped_count, unique_count = 0, 0, 0
        for _, result in ipairs(results) do
            if result.length >= lower and result.length <= lower + 9 then
                count = count + 1
                if result.mapped then mapped_count = mapped_count + 1; if result.x0 == 1 then unique_count = unique_count + 1 end end
            end
        end
        line(lines, lower .. '-' .. (lower + 9), 'reads', count, 'mapped', mapped_count, 'unique', unique_count)
    end
    local n_reads, n_bases, n_mapped = 0, 0, 0
    for _, result in ipairs(results) do
        local count = count_char(result.read.bases, 'N')
        if count > 0 then n_reads, n_bases = n_reads + 1, n_bases + count; if result.mapped then n_mapped = n_mapped + 1 end end
    end
    line(lines, 'n_reads', n_reads, 'n_bases', n_bases, 'mapped', n_mapped)
    local target_counts, mapq_counts, nm_counts = {}, {}, {}
    for _, result in ipairs(mapped) do
        increment(mapq_counts, result.mapq); increment(nm_counts, result.primary.nm)
        if result.x0 >= 2 then
            local names = {}
            for _, reference in ipairs(result.targets) do names[#names + 1] = references[reference].name end
            increment(target_counts, table.concat(names, '+'))
        end
    end
    lines[#lines + 1] = 'multi_targets'
    local targets = keys(target_counts)
    if #targets == 0 then lines[#lines + 1] = 'none' else for _, target in ipairs(targets) do line(lines, target, target_counts[target]) end end
    lines[#lines + 1] = 'mapq_histogram'
    for _, mapq in ipairs(keys(mapq_counts, true)) do line(lines, mapq, mapq_counts[mapq]) end
    lines[#lines + 1] = 'nm_histogram'
    for _, nm in ipairs(keys(nm_counts)) do line(lines, nm, nm_counts[nm]) end
    for _, text_line in ipairs(error_statistics(results)) do lines[#lines + 1] = text_line end
    line(lines, 'search dfs_calls', search_counts.calls, 'dfs_nodes', search_counts.nodes, 'dfs_leaves', search_counts.leaves, 'dfs_positions', search_counts.positions)
    line(lines, 'seeds reads', seed_counts.reads, 'seeds', seed_counts.seeds, 'with_n', seed_counts.with_n, 'repetitive', seed_counts.repetitive, 'without_hit', seed_counts.without_hit, 'candidates', seed_counts.candidates, 'passing', seed_counts.passing)
    return lines
end
local index_lines, results = index_statistics(), {}
for _, read in ipairs(reads) do results[#results + 1] = map_read(read) end
local sam_lines = sam.header(references)
for _, result in ipairs(results) do sam_lines[#sam_lines + 1] = sam.record(result, references, value('MAX_ALT_HITS')) end
local coverage, variants = coverage_and_variants(results)
sam.write_lines('output/alignments.sam', sam_lines)
sam.write_lines('output/coverage.txt', coverage)
sam.write_lines('output/variants.txt', variants)
sam.write_lines('output/index_stats.txt', index_lines)
sam.write_lines('output/summary.txt', mapping_statistics(results))
