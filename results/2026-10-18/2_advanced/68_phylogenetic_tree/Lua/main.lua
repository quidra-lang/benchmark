package.path = 'Lua/?.lua;' .. package.path
local alignment = require('alignment')
local distances = require('distances')
local tree = require('tree_building')
local parsimony = require('parsimony')
local tree_io = require('tree_io')
local real, symbols = tree_io.real, tree_io.symbols
local nj_methods = {'NJ_P', 'NJ_JC', 'NJ_K2P'}
local methods = {'NJ_P', 'NJ_JC', 'NJ_K2P', 'ME', 'MP', 'CONSENSUS'}
local function append(a, b) for _, x in ipairs(b) do a[#a + 1] = x end end
local function line(out, ...) out[#out + 1] = table.concat({...}, ' ') end
local function count(set) local n = 0; for _ in pairs(set) do n = n + 1 end; return n end
local function sum(a) local total = 0.0; for _, v in ipairs(a) do total = total + v end; return total end
local function bits(mask) local n = 0; while mask ~= 0 do mask = mask & (mask - 1); n = n + 1 end; return n end
local function symmetric(a, b)
    local n = 0; for k in pairs(a) do if not b[k] then n = n + 1 end end; for k in pairs(b) do if not a[k] then n = n + 1 end end; return n
end
local function square(x) return x * x end
local p = {}
for text in io.lines('input/params.txt') do
    local words = {}; for word in text:gmatch('%S+') do words[#words + 1] = word end
    local key = words[1]
    if key == 'exhaustive_taxa' then p[key] = {}; for i = 2, #words do p[key][#p[key] + 1] = words[i] end
    elseif key == 'saturation_distance' then p[key] = tonumber(words[2]) + 0.0
    elseif key == 'replicates' or key == 'seed' or key == 'max_missing_percent' or key == 'low_sites' then p[key] = tonumber(words[2])
    else p[key] = words[2] end
end
local records = alignment.read()
local length = #records[1].sequence
local seen, names, sequences, rejected = {}, {}, {}, {}
for _, record in ipairs(records) do
    local reason
    if seen[record.name] then reason = 'duplicate name' end
    seen[record.name] = true
    if not reason then
        for i = 1, #record.sequence do
            local c = record.sequence:sub(i, i)
            if not alignment.sets[c] then reason = 'invalid character ' .. c .. ' at column ' .. i; break end
        end
    end
    if not reason and #record.sequence ~= length then reason = 'length mismatch ' .. #record.sequence end
    if not reason then
        local missing = 0
        for i = 1, #record.sequence do local c = record.sequence:sub(i, i); if c == '-' or c == 'N' then missing = missing + 1 end end
        if 100 * missing > p.max_missing_percent * length then reason = 'too many missing ' .. missing end
    end
    if reason then rejected[#rejected + 1] = {line = record.line, name = record.name, reason = reason}
    else names[#names + 1] = record.name; sequences[#sequences + 1] = record.sequence end
end
local n, outgroup, taxa, numbers = #names, nil, {}, {}
for i, name in ipairs(names) do taxa[i] = i; numbers[name] = i; if name == p.outgroup then outgroup = i end end
local patterns = alignment.patterns(sequences)
local function sorted_symbols(set)
    local out = tree.keys(set); table.sort(out, function(a, b) return symbols(a, n) < symbols(b, n) end); return out
end
local function summary_lines()
    local out, columns, composition = {}, {}, {0, 0, 0, 0}
    line(out, 'INPUT records', #records, 'accepted', n, 'rejected', #rejected, 'columns', length)
    for _, r in ipairs(rejected) do line(out, 'REJECT line', r.line, r.name, r.reason) end
    for c = 1, length do
        columns[c] = {}
        for _, sequence in ipairs(sequences) do
            local ch = sequence:sub(c, c)
            if alignment.base[ch] then columns[c][ch] = (columns[c][ch] or 0) + 1 end
        end
    end
    for taxon, sequence in ipairs(sequences) do
        local counts = {}; for c = 1, length do local ch = sequence:sub(c, c); counts[ch] = (counts[ch] or 0) + 1 end
        local bases, ambiguous, unique = 0, 0, 0
        for i = 1, 4 do
            local base = alignment.bases:sub(i, i); bases = bases + (counts[base] or 0); composition[i] = composition[i] + (counts[base] or 0)
        end
        for i = 1, 10 do ambiguous = ambiguous + (counts[('RYSWKMBDHV'):sub(i, i)] or 0) end
        for c = 1, length do
            local ch, total = sequence:sub(c, c), 0
            for _, value in pairs(columns[c]) do total = total + value end
            if alignment.base[ch] and columns[c][ch] == 1 and total > 1 then unique = unique + 1 end
        end
        line(out, 'TAXON', names[taxon], 'bases', bases, 'ambiguous', ambiguous, 'missing', (counts['-'] or 0) + (counts.N or 0),
            'unique', unique, 'gc', real(((counts.C or 0) + (counts.G or 0)) / bases, 4))
    end
    local classes = alignment.classify(sequences)
    line(out, 'COLUMNS constant', classes.constant, 'variable', classes.variable, 'informative', classes.informative, 'gapped', classes.gapped, 'empty', classes.empty)
    line(out, 'PATTERNS', #patterns.patterns)
    local total = sum(composition)
    line(out, 'COMPOSITION A', real(composition[1] / total, 4), 'C', real(composition[2] / total, 4), 'G', real(composition[3] / total, 4), 'T', real(composition[4] / total, 4))
    return out
end
local function matrix_lines(matrix)
    local width = 0; for _, name in ipairs(names) do width = math.max(width, #name) end
    local out = {}
    for i, name in ipairs(names) do
        local parts = {name .. string.rep(' ', width - #name)}
        for j = 1, n do parts[#parts + 1] = real(matrix[i][j], 5) end
        out[#out + 1] = table.concat(parts, ' ')
    end
    return out
end
local function bounds()
    local minimum_by_pattern, minimum, maximum = {}, 0, 0
    for i, pattern in ipairs(patterns.encoded) do
        local least, greatest = 4, n
        for mask = 1, 15 do
            local covers = true
            for _, bases in ipairs(pattern) do if mask & bases == 0 then covers = false; break end end
            if covers then least = math.min(least, bits(mask) - 1) end
        end
        for _, base in ipairs({1, 2, 4, 8}) do
            local absent = 0; for _, bases in ipairs(pattern) do if bases & base == 0 then absent = absent + 1 end end
            greatest = math.min(greatest, absent)
        end
        minimum_by_pattern[i] = least; maximum = maximum + greatest * patterns.weights[i]
    end
    local minima = {}
    for c, index in ipairs(patterns.columns) do minima[c] = minimum_by_pattern[index]; minimum = minimum + minima[c] end
    return minimum, maximum, minima
end
local function bme(t, matrix)
    local leaves, total = tree.taxa(t), 0.0
    for i, a in ipairs(leaves) do
        local paths = tree.paths(t, a, true)
        for j = i + 1, #leaves do local b = leaves[j]; total = total + matrix[a][b] / (1 << (paths[b] - 1)) end
    end
    return total
end
local function stepwise(order)
    local initial_taxa = {order[1], order[2], order[3]}
    local t = tree.star(n, initial_taxa)
    local initial = parsimony.score(t, patterns, outgroup)
    local current, additions, evaluated = initial, {}, 0
    for k = 4, #order do
        local taxon, best, chosen, selected_mask, ties = order[k], nil, nil, nil, 0
        for _, branch in ipairs(parsimony.branches(t, outgroup)) do
            local candidate = parsimony.insert(t, branch.first, branch.second, taxon)
            local value = parsimony.score(candidate, patterns, outgroup); evaluated = evaluated + 1
            if best == nil or value < best then best, chosen, selected_mask, ties = value, candidate, branch.mask, 1
            elseif value == best then ties = ties + 1 end
        end
        t, current = chosen, best
        additions[#additions + 1] = {taxon = taxon, mask = selected_mask, value = current, ties = ties}
    end
    return {tree = t, initial = initial, score = current, additions = additions, evaluated = evaluated, taxa = order}
end
local function hill_climb(t, objective, value)
    t = tree.copy(t)
    local evaluated, moves = 0, {}
    while true do
        local improved = false
        for _, candidate in ipairs(parsimony.nni(t, outgroup)) do
            local v = objective(candidate.tree); evaluated = evaluated + 1
            if v < value then
                t, value = candidate.tree, v; moves[#moves + 1] = {mask = candidate.mask, swap = candidate.swap, value = v}; improved = true; break
            end
        end
        if not improved then break end
    end
    return {tree = t, value = value, moves = moves, evaluated = evaluated}
end
local function consensus(order, clades)
    local t = tree.new(n, order); local root = tree.internal(t)
    local nodes = {}
    for _, mask in ipairs(tree.keys(clades)) do nodes[mask] = tree.internal(t) end
    local function container(mask, strict)
        local best
        for candidate in pairs(nodes) do
            if (not strict or candidate ~= mask) and candidate & mask == mask and (not best or bits(candidate) < bits(best)) then best = candidate end
        end
        return best and nodes[best] or root
    end
    for mask, node in pairs(nodes) do tree.connect(t, container(mask, true), node) end
    for _, taxon in ipairs(order) do tree.connect(t, container(1 << (taxon - 1), false), taxon) end
    return t
end
local function exhaustive_search(order, matrix)
    local ts = {tree.star(n, {order[1], order[2], order[3]})}
    for k = 4, #order do
        local expanded = {}
        for _, t in ipairs(ts) do
            for _, branch in ipairs(parsimony.branches(t, outgroup)) do expanded[#expanded + 1] = parsimony.insert(t, branch.first, branch.second, order[k]) end
        end
        ts = expanded
    end
    local records_list, histogram, best_score, best_bme = {}, {}, nil, nil
    for _, t in ipairs(ts) do
        local score = parsimony.score(t, patterns, outgroup)
        histogram[score] = (histogram[score] or 0) + 1
        if not best_score or score < best_score then best_score = score end
        local r = {tree = t, score = score, bme = bme(t, matrix), newick = tree_io.newick(t, names, outgroup), splits = tree.splits(tree.rooted(t, outgroup))}
        records_list[#records_list + 1] = r
        if not best_bme or r.bme < best_bme.bme or (r.bme == best_bme.bme and r.newick < best_bme.newick) then best_bme = r end
    end
    local optimal, second, common = {}, nil, nil
    for _, r in ipairs(records_list) do
        if r ~= best_bme and (second == nil or r.bme < second) then second = r.bme end
        if r.score == best_score then
            optimal[#optimal + 1] = r
            if not common then common = {}; for mask in pairs(r.splits) do common[mask] = true end
            else for mask in pairs(common) do if not r.splits[mask] then common[mask] = nil end end end
        end
    end
    table.sort(optimal, function(a, b) return a.newick < b.newick end)
    local initial = stepwise(order)
    local search = hill_climb(initial.tree, function(t) return parsimony.score(t, patterns, outgroup) end, initial.score)
    return {taxa = order, records = records_list, histogram = histogram, best_score = best_score, optimal = optimal,
        strict = consensus(order, common), best_bme = best_bme, second_bme = second, heuristic = search.value}
end
local function likelihood_sites(t)
    local r = tree.rooted(t, outgroup)
    local children, transition = tree_io.children(r, names), {}
    for i = 2, #r.order do
        local node = r.order[i]
        local branch = t.adjacent[node][r.parents[node]]
        local e = math.exp(-(4 * branch) / 3)
        transition[node] = {same = 0.25 + 0.75 * e, different = 0.25 - 0.25 * e}
    end
    local values = {}
    for index, pattern in ipairs(patterns.encoded) do
        local partial, upward = {}, {}
        for i = #r.order, 1, -1 do
            local node = r.order[i]
            partial[node] = {}
            if node <= t.size then
                for base = 1, 4 do partial[node][base] = pattern[node] & (1 << (base - 1)) ~= 0 and 1.0 or 0.0 end
            else
                for base = 1, 4 do partial[node][base] = 1.0 end
                for _, child in ipairs(children[node]) do
                    for base = 1, 4 do partial[node][base] = partial[node][base] * upward[child][base] end
                end
            end
            if node ~= r.root then
                upward[node] = {}
                for first = 1, 4 do
                    local total = 0.0
                    for second = 1, 4 do
                        local probability = first == second and transition[node].same or transition[node].different
                        total = total + probability * partial[node][second]
                    end
                    upward[node][first] = total
                end
            end
        end
        local probability = 0.0
        for base = 1, 4 do probability = probability + 0.25 * partial[r.root][base] end
        values[index] = math.log(probability)
    end
    local out = {}; for c, index in ipairs(patterns.columns) do out[c] = values[index] end; return out
end
local function likelihood_lines(nj_trees, main_method, site_logs)
    local out = {}; line(out, 'LIKELIHOOD columns', length, 'patterns', #patterns.patterns)
    for _, method in ipairs(nj_methods) do
        local total = sum(site_logs[method]); line(out, 'TREE', method, 'loglik', real(total, 4), 'per_site', real(total / length, 4))
    end
    for i = 1, 3 do
        for j = i + 1, 3 do
            local a, b = nj_methods[i], nj_methods[j]
            local deltas = {}; for c = 1, length do deltas[c] = site_logs[a][c] - site_logs[b][c] end
            local difference = sum(deltas); local mean = difference / length; local ss = 0.0
            for _, d in ipairs(deltas) do ss = ss + square(d - mean) end
            local se = math.sqrt(length / (length - 1) * ss)
            line(out, 'KH', a, b, 'difference', real(difference, 4), 'se', real(se, 4), 'z', real(difference / se, 4))
        end
    end
    local order, rounded = {}, {}
    for c = 1, length do order[c] = c; rounded[c] = tonumber(real(site_logs[main_method][c], 4)) end
    table.sort(order, function(a, b) return rounded[a] < rounded[b] or (rounded[a] == rounded[b] and a < b) end)
    local changes = parsimony.pattern_scores(nj_trees[main_method], patterns, outgroup)
    line(out, 'LOWEST', main_method, 'sites', p.low_sites)
    for i = 1, p.low_sites do
        local c = order[i]; local index = patterns.columns[c]
        line(out, 'SITE', c, 'loglik', real(site_logs[main_method][c], 4), 'changes', changes[index], 'pattern', patterns.patterns[index])
    end
    return out
end
local function bootstrap(main_tree, matrix)
    local state, support, identical, out = p.seed, {}, 0, {}
    local main_splits = tree.splits(tree.rooted(main_tree, outgroup))
    line(out, 'BOOTSTRAP model', p.model, 'replicates', p.replicates, 'seed', state)
    for replicate = 1, p.replicates do
        local weights = {}; for c = 1, length do weights[c] = 0 end
        for draw = 1, length do state = 48271 * state % 2147483647; local c = state % length + 1; weights[c] = weights[c] + 1 end
        local pairs_list = distances.all(sequences, weights)
        local dm = distances.matrix(pairs_list, n, p.model, p.saturation_distance)
        local t = tree.nj(dm, taxa); local splits = tree.splits(tree.rooted(t, outgroup))
        for mask in pairs(splits) do support[mask] = (support[mask] or 0) + 1 end
        local rf, distinct = symmetric(splits, main_splits), 0
        if rf == 0 then identical = identical + 1 end
        for _, w in ipairs(weights) do if w > 0 then distinct = distinct + 1 end end
        line(out, 'REPLICATE', replicate, 'distinct', distinct, 'rf', rf)
    end
    line(out, 'IDENTICAL', identical)
    for _, mask in ipairs(sorted_symbols(main_splits)) do line(out, 'SUPPORT', symbols(mask, n), support[mask] or 0) end
    local order, majority = tree.keys(support), {}
    table.sort(order, function(a, b) return support[a] > support[b] or (support[a] == support[b] and symbols(a, n) < symbols(b, n)) end)
    for _, mask in ipairs(order) do line(out, 'SPLIT', symbols(mask, n), support[mask]); if 2 * support[mask] > p.replicates then majority[mask] = true end end
    local consensus_tree = consensus(taxa, majority)
    line(out, 'CONSENSUS', tree_io.newick(consensus_tree, names, outgroup, false, support))
    for _, taxon in ipairs(taxa) do
        if taxon ~= outgroup then
            local reduced_taxa, reduced = {}, {}
            for _, other in ipairs(taxa) do if other ~= taxon then reduced_taxa[#reduced_taxa + 1] = other end end
            for mask in pairs(main_splits) do
                local smaller = mask & ~(1 << (taxon - 1))
                if bits(smaller) >= 2 and bits(smaller) <= n - 3 then reduced[smaller] = true end
            end
            local t = tree.nj(matrix, reduced_taxa)
            line(out, 'JACKKNIFE', names[taxon], 'rf', symmetric(tree.splits(tree.rooted(t, outgroup)), reduced))
        end
    end
    return consensus_tree, support, out
end
local function clock_lines(main_method, main_tree)
    local ingroup, pairs_list, rejected_count = {}, {}, 0
    for _, taxon in ipairs(taxa) do if taxon ~= outgroup then ingroup[#ingroup + 1] = taxon end end
    for i, a in ipairs(ingroup) do
        for j = i + 1, #ingroup do
            local b, m1, m2 = ingroup[j], 0, 0
            for c = 1, length do
                local aa, bb, oo = sequences[a]:sub(c, c), sequences[b]:sub(c, c), sequences[outgroup]:sub(c, c)
                if alignment.base[aa] and alignment.base[bb] and alignment.base[oo] and aa ~= bb then
                    if bb == oo then m1 = m1 + 1 end; if aa == oo then m2 = m2 + 1 end
                end
            end
            local reject = 1000 * square(m1 - m2) > 3841 * (m1 + m2)
            if reject then rejected_count = rejected_count + 1 end
            line(pairs_list, 'RRT', names[a], names[b], 'm1', m1, 'm2', m2, 'chi2', m1 + m2 > 0 and real(square(m1 - m2) / (m1 + m2), 4) or '-', reject and 'reject' or 'ok')
        end
    end
    local out = {}; line(out, 'RELATIVE_RATE outgroup', names[outgroup], 'pairs', #pairs_list, 'rejected', rejected_count); append(out, pairs_list)
    local root = tree.rooted(main_tree, outgroup).root
    local paths = tree.paths(main_tree, root)
    local total = 0.0; for _, taxon in ipairs(ingroup) do total = total + paths[taxon] end
    local mean, ss = total / #ingroup, 0.0
    for _, taxon in ipairs(ingroup) do ss = ss + square(paths[taxon] - mean) end
    local sd = math.sqrt(ss / (#ingroup - 1))
    line(out, 'ROOT_TO_TIP', main_method, 'mean', real(mean, 5), 'sd', real(sd, 5), 'cv', real(sd / mean, 4))
    for _, taxon in ipairs(ingroup) do line(out, 'TIP', names[taxon], real(paths[taxon], 5)) end
    return out
end
local function quartets(splits)
    local out = {}
    for a = 1, n - 3 do
        for b = a + 1, n - 2 do
            for c = b + 1, n - 1 do
                for d = c + 1, n do
                    local quartet = (1 << (a - 1)) | (1 << (b - 1)) | (1 << (c - 1)) | (1 << (d - 1))
                    local topology = 0
                    for number, other in ipairs({b, c, d}) do
                        local side = (1 << (a - 1)) | (1 << (other - 1))
                        for mask in pairs(splits) do
                            local part = mask & quartet
                            if part == side or part == quartet ~ side then topology = number; break end
                        end
                        if topology ~= 0 then break end
                    end
                    out[#out + 1] = topology
                end
            end
        end
    end
    return out
end
local function comparison_lines(trees, matrices, main_matrix, main_method, support, nj_scores, mp_score, mp_changes, site_logs, patristic)
    local splits, out = {}, {}
    for _, method in ipairs(methods) do splits[method] = tree.splits(tree.rooted(trees[method], outgroup)) end
    for index, method in ipairs(methods) do
        local supported = 0; for mask in pairs(splits[method]) do if 2 * (support[mask] or 0) > p.replicates then supported = supported + 1 end end
        local score, bme_value, total_length, negative, sse, likelihood = '-', '-', '-', '-', '-', '-'
        local t = trees[method]
        if method ~= 'CONSENSUS' then
            score = nj_scores[method] or (method == 'MP' and mp_score or parsimony.score(t, patterns, outgroup))
            bme_value = real(bme(t, main_matrix), 5)
        end
        if index <= 3 then
            local total = 0.0
            for _, branch in ipairs(parsimony.branches(t, outgroup)) do total = total + t.adjacent[branch.first][branch.second] end
            total_length, negative = real(total, 5), t.negative
            local ss, matrix = 0.0, matrices[method:sub(4)]
            for i = 1, n do for j = i + 1, n do ss = ss + square(matrix[i][j] - patristic[method][i][j]) end end
            sse, likelihood = real(ss, 6), real(sum(site_logs[method]), 4)
        elseif method == 'MP' then total_length = real(mp_score / length, 5) end
        line(out, 'TREE', method, 'splits', count(splits[method]), 'supported', supported, 'parsimony', score, 'bme', bme_value,
            'length', total_length, 'negative', negative, 'sse', sse, 'loglik', likelihood)
    end
    line(out, 'RF', table.concat(methods, ' '))
    for _, a in ipairs(methods) do
        local values = {a}; for _, b in ipairs(methods) do values[#values + 1] = symmetric(splits[a], splits[b]) end; line(out, table.concat(values, ' '))
    end
    local q = {}; for _, method in ipairs(methods) do q[method] = quartets(splits[method]) end
    line(out, 'QUARTET', table.concat(methods, ' '))
    for _, a in ipairs(methods) do
        local values = {a}
        for _, b in ipairs(methods) do
            local difference = 0; for i, v in ipairs(q[a]) do if v ~= q[b][i] then difference = difference + 1 end end
            values[#values + 1] = difference
        end
        line(out, table.concat(values, ' '))
    end
    local all_clades, lengths, changes = {}, tree.lengths(tree.rooted(trees[main_method], outgroup)), {}
    for _, method in ipairs(methods) do for mask in pairs(splits[method]) do all_clades[mask] = true end end
    for _, branch in ipairs(parsimony.branches(trees.MP, outgroup)) do changes[branch.mask] = mp_changes[parsimony.edge_key(branch.first, branch.second)] end
    for _, mask in ipairs(sorted_symbols(all_clades)) do
        local marks = {}; for _, method in ipairs(methods) do marks[#marks + 1] = splits[method][mask] and '+' or '-' end
        line(out, 'CLADE', symbols(mask, n), 'support', support[mask] or 0, 'trees', table.concat(marks),
            'length', lengths[mask] ~= nil and real(lengths[mask], 5) or '-', 'changes', changes[mask] or '-')
    end
    return out
end
local function hypothesis_lines(trees, support, exhaustive)
    local ingroup = ((1 << n) - 1) ~ (1 << (outgroup - 1))
    local exhaustive_ingroup, splits = 0, {}
    for _, taxon in ipairs(exhaustive.taxa) do if taxon ~= outgroup then exhaustive_ingroup = exhaustive_ingroup | (1 << (taxon - 1)) end end
    for _, method in ipairs(methods) do splits[method] = tree.splits(tree.rooted(trees[method], outgroup)) end
    local out = {}
    for text in io.lines('input/clades.txt') do
        local words = {}; for word in text:gmatch('%S+') do words[#words + 1] = word end
        local hypothesis, reason, mask = words[1], nil, 0
        for i = 2, #words do if not numbers[words[i]] then reason = 'unknown taxon ' .. words[i]; break end end
        if not reason then
            for i = 2, #words do
                local taxon = numbers[words[i]]; mask = mask | (1 << (taxon - 1)); if taxon == outgroup then reason = 'contains outgroup' end
            end
        end
        if reason then line(out, 'INVALID', hypothesis, reason) else
            line(out, 'CLADE', hypothesis, 'taxa', bits(mask), 'support', support[mask] or 0)
            for _, method in ipairs(methods) do
                local common = ingroup
                for clade in pairs(splits[method]) do if clade & mask == mask and bits(clade) < bits(common) then common = clade end end
                local intruders = {}
                for taxon, name in ipairs(names) do if common & ~mask & (1 << (taxon - 1)) ~= 0 then intruders[#intruders + 1] = name end end
                line(out, 'TEST', hypothesis, method, 'monophyletic', common == mask and 'yes' or 'no', 'mrca', bits(common),
                    'intruders', #intruders > 0 and table.concat(intruders, ',') or '-')
            end
            local subset = mask & exhaustive_ingroup
            if bits(subset) < 2 or bits(subset) >= bits(exhaustive_ingroup) then line(out, 'SUBSET', hypothesis, 'untestable') else
                local included, excluded = {}, {}
                for _, r in ipairs(exhaustive.records) do
                    local target = r.splits[subset] and included or excluded
                    if target.score == nil or r.score < target.score then target.score = r.score end
                    if target.bme == nil or r.bme < target.bme then target.bme = r.bme end
                end
                line(out, 'SUBSET', hypothesis, 'taxa', bits(subset), 'with', included.score, 'without', excluded.score,
                    'bme_with', real(included.bme, 5), 'bme_without', real(excluded.bme, 5))
            end
        end
    end
    return out
end
local function distance_lines(pairs_list, matrices, saturated, main_method, patristic, me_start, me, exhaustive)
    local out, totals = {}, {0, 0, 0}
    for _, pair in ipairs(pairs_list) do
        line(out, 'PAIR', names[pair.i], names[pair.j], 'sites', pair.n, 'transitions', pair.s, 'transversions', pair.v)
        totals[1], totals[2], totals[3] = totals[1] + pair.n, totals[2] + pair.s, totals[3] + pair.v
    end
    line(out, 'TOTAL sites', totals[1], 'transitions', totals[2], 'transversions', totals[3])
    for _, model in ipairs(distances.models) do
        out[#out + 1] = ''; line(out, 'MODEL', model); append(out, matrix_lines(matrices[model]))
        for _, pair in ipairs(saturated[model]) do line(out, 'SATURATED', names[pair.i], names[pair.j], 'sites', pair.n) end
    end
    out[#out + 1] = ''; line(out, 'PATRISTIC', main_method); append(out, matrix_lines(patristic[main_method]))
    out[#out + 1] = ''; line(out, 'ME start', main_method, 'length', real(me_start, 5))
    for _, move in ipairs(me.moves) do line(out, 'NNI edge', symbols(move.mask, n), 'swap', move.swap, 'length', real(move.value, 5)) end
    line(out, 'ME moves', #me.moves, 'evaluated', me.evaluated, 'length', real(me.value, 5))
    line(out, 'EXHAUSTIVE taxa', #exhaustive.taxa, 'trees', #exhaustive.records, 'best', real(exhaustive.best_bme.bme, 5), 'second', real(exhaustive.second_bme, 5))
    line(out, 'BEST', exhaustive.best_bme.newick, 'parsimony', exhaustive.best_bme.score)
    return out
end
local function score_line(out, method, score, minimum, maximum)
    line(out, 'TREE', method, 'score', score, 'ci', real(minimum / score, 4), 'ri', real((maximum - score) / (maximum - minimum), 4))
end
local function parsimony_lines(minimum, maximum, minima, nj_scores, initial, search, ancestors, column_changes, exhaustive)
    local out = {}; line(out, 'BOUNDS minimum', minimum, 'maximum', maximum)
    for _, method in ipairs(nj_methods) do score_line(out, method, nj_scores[method], minimum, maximum) end
    line(out, 'START', names[initial.taxa[1]], names[initial.taxa[2]], names[initial.taxa[3]], 'score', initial.initial)
    for _, addition in ipairs(initial.additions) do
        line(out, 'ADD', names[addition.taxon], 'edge', symbols(addition.mask, n), 'score', addition.value, 'ties', addition.ties)
    end
    line(out, 'STEPWISE score', initial.score, 'evaluated', initial.evaluated)
    for _, move in ipairs(search.moves) do line(out, 'NNI edge', symbols(move.mask, n), 'swap', move.swap, 'score', move.value) end
    line(out, 'SEARCH moves', #search.moves, 'evaluated', search.evaluated, 'score', search.value)
    score_line(out, 'MP', search.value, minimum, maximum)
    line(out, 'MP', tree_io.newick(search.tree, names, outgroup, true))
    local histogram, largest, homoplasy = {}, 0, 0
    for c, changes in ipairs(column_changes) do
        histogram[changes] = (histogram[changes] or 0) + 1; largest = math.max(largest, changes)
        if changes > minima[c] then homoplasy = homoplasy + 1 end
    end
    for k = 0, largest do line(out, 'CHANGES', k, 'columns', histogram[k] or 0) end
    line(out, 'HOMOPLASY columns', homoplasy, 'extra', search.value - minimum)
    local r, ordered_ancestors = tree.rooted(search.tree, outgroup), {}
    for node, sequence in pairs(ancestors) do ordered_ancestors[#ordered_ancestors + 1] = {symbol = symbols(node == r.root and r.ingroup or r.masks[node], n), sequence = sequence} end
    table.sort(ordered_ancestors, function(a, b) return a.symbol < b.symbol end)
    for _, row in ipairs(ordered_ancestors) do line(out, 'ANCESTOR', row.symbol, row.sequence) end
    out[#out + 1] = ''
    line(out, 'EXHAUSTIVE taxa', #exhaustive.taxa, 'trees', #exhaustive.records, 'best', exhaustive.best_score, 'optimal', #exhaustive.optimal)
    for _, score in ipairs(tree.keys(exhaustive.histogram)) do line(out, 'SCORE', score, 'trees', exhaustive.histogram[score]) end
    for _, record in ipairs(exhaustive.optimal) do line(out, 'OPTIMAL', record.newick, 'bme', real(record.bme, 5)) end
    line(out, 'STRICT', tree_io.newick(exhaustive.strict, names, outgroup))
    line(out, 'HEURISTIC score', exhaustive.heuristic, 'optimal', exhaustive.heuristic == exhaustive.best_score and 'yes' or 'no')
    return out
end
local weights = {}; for c = 1, length do weights[c] = 1 end
local pairs_list = distances.all(sequences, weights)
local matrices, saturated, nj_trees, nj_scores, site_logs, patristic = {}, {}, {}, {}, {}, {}
for i, model in ipairs(distances.models) do
    matrices[model], saturated[model] = distances.matrix(pairs_list, n, model, p.saturation_distance)
    local method = nj_methods[i]; nj_trees[method] = tree.nj(matrices[model], taxa)
    nj_scores[method] = parsimony.score(nj_trees[method], patterns, outgroup)
    site_logs[method] = likelihood_sites(nj_trees[method]); patristic[method] = tree.patristic(nj_trees[method])
end
local main_method, main_matrix = 'NJ_' .. p.model, matrices[p.model]
local main_tree = nj_trees[main_method]
local me_start = bme(main_tree, main_matrix)
local me = hill_climb(main_tree, function(t) return bme(t, main_matrix) end, me_start)
local addition_order = {outgroup}
for _, taxon in ipairs(taxa) do if taxon ~= outgroup then addition_order[#addition_order + 1] = taxon end end
local initial = stepwise(addition_order)
local mp = hill_climb(initial.tree, function(t) return parsimony.score(t, patterns, outgroup) end, initial.score)
local ancestors, branch_changes, column_changes = parsimony.reconstruct(mp.tree, patterns, outgroup)
for _, edge in ipairs(tree.edges(mp.tree)) do tree.connect(mp.tree, edge[1], edge[2], branch_changes[parsimony.edge_key(edge[1], edge[2])] / length) end
local minimum, maximum, minima = bounds()
local exhaustive_set, exhaustive_taxa = {}, {outgroup}
for _, name in ipairs(p.exhaustive_taxa) do exhaustive_set[name] = true end
for _, taxon in ipairs(taxa) do if taxon ~= outgroup and exhaustive_set[names[taxon]] then exhaustive_taxa[#exhaustive_taxa + 1] = taxon end end
local exhaustive = exhaustive_search(exhaustive_taxa, main_matrix)
local consensus_tree, support, bootstrap_lines = bootstrap(main_tree, main_matrix)
local trees = {NJ_P = nj_trees.NJ_P, NJ_JC = nj_trees.NJ_JC, NJ_K2P = nj_trees.NJ_K2P, ME = me.tree, MP = mp.tree, CONSENSUS = consensus_tree}
local newicks, diagrams = {}, {}
for i, method in ipairs(methods) do
    line(newicks, method, tree_io.newick(trees[method], names, outgroup, i <= 3 or method == 'MP', method == 'CONSENSUS' and support or nil))
    if #diagrams > 0 then diagrams[#diagrams + 1] = '' end
    line(diagrams, 'TREE', method); append(diagrams, tree_io.cladogram(trees[method], names, outgroup, support))
end
local outputs = {['summary.txt'] = summary_lines(), ['distances.txt'] = distance_lines(pairs_list, matrices, saturated, main_method, patristic, me_start, me, exhaustive),
    ['trees.nwk'] = newicks, ['cladograms.txt'] = diagrams, ['parsimony.txt'] = parsimony_lines(minimum, maximum, minima, nj_scores, initial, mp, ancestors, column_changes, exhaustive),
    ['likelihood.txt'] = likelihood_lines(nj_trees, main_method, site_logs), ['bootstrap.txt'] = bootstrap_lines, ['clock.txt'] = clock_lines(main_method, main_tree),
    ['comparison.txt'] = comparison_lines(trees, matrices, main_matrix, main_method, support, nj_scores, mp.value, branch_changes, site_logs, patristic),
    ['hypotheses.txt'] = hypothesis_lines(trees, support, exhaustive)}
for filename, lines in pairs(outputs) do tree_io.write(filename, lines) end
