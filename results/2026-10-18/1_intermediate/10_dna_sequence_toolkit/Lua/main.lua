local bases = "ACGT"
local iupac = {
    A = "A", C = "C", G = "G", T = "T", R = "AG",
    Y = "CT", W = "AT", S = "CG", K = "GT", M = "AC",
    B = "CGT", D = "AGT", H = "ACT", V = "ACG", N = "ACGT"
}
local symbols = {}
for symbol, values in pairs(iupac) do
    symbols[values] = symbol
end

local complement = {}
local originals = "ACGTRYWSKMBVDHN"
local complements = "TGCAYRWSMKVBHDN"
for i = 1, #originals do
    complement[originals:sub(i, i)] = complements:sub(i, i)
end

local code_groups = {
    A = "GCT GCC GCA GCG", C = "TGT TGC", D = "GAT GAC",
    E = "GAA GAG", F = "TTT TTC", G = "GGT GGC GGA GGG",
    H = "CAT CAC", I = "ATT ATC ATA", K = "AAA AAG",
    L = "TTA TTG CTT CTC CTA CTG", M = "ATG", N = "AAT AAC",
    P = "CCT CCC CCA CCG", Q = "CAA CAG",
    R = "CGT CGC CGA CGG AGA AGG", S = "TCT TCC TCA TCG AGT AGC",
    T = "ACT ACC ACA ACG", V = "GTT GTC GTA GTG", W = "TGG",
    Y = "TAT TAC", ["*"] = "TAA TAG TGA"
}
local genetic_code = {}
for amino, group in pairs(code_groups) do
    for codon in group:gmatch("%S+") do
        genetic_code[codon] = amino
    end
end

local amino_mass = {}
local amino_labels = "ACDEFGHIKLMNPQRSTVWY"
local masses = {
    71079, 103139, 115089, 129116, 147177, 57052, 137141,
    113160, 128174, 113160, 131193, 114104, 97117, 128131,
    156188, 87078, 101105, 99133, 186213, 163176
}
for i = 1, #amino_labels do
    amino_mass[amino_labels:sub(i, i)] = masses[i]
end
local base_mass = {A = 331222, C = 307197, G = 347221, T = 322208}

local enzymes = {
    EcoRI = {"GAATTC", 1}, BamHI = {"GGATCC", 1},
    HindIII = {"AAGCTT", 1}, PstI = {"CTGCAG", 5},
    SmaI = {"CCCGGG", 3}, KpnI = {"GGTACC", 5},
    XbaI = {"TCTAGA", 1}, NotI = {"GCGGCCGC", 2},
    EcoRV = {"GATATC", 3}, HaeIII = {"GGCC", 2},
    AluI = {"AGCT", 2}, TaqI = {"TCGA", 1},
    Sau3AI = {"GATC", 0}, HincII = {"GTYRAC", 3},
    AvaI = {"CYCGRG", 1}
}

local arity = {
    SEQ = {2, 2}, SLICE = {4, 4}, JOIN = {3, 9},
    MUTATE = {3, 3}, DEL = {1, 1}, LIST = {0, 0},
    REVCOMP = {1, 1}, COMPLEMENT = {1, 1}, REVERSE = {1, 1},
    TRANSCRIBE = {1, 1}, TRANSLATE = {2, 2}, CODONS = {2, 2},
    PROTEIN = {2, 2}, ORFS = {2, 2}, GC = {1, 1},
    GCWINDOW = {3, 3}, SKEW = {1, 1}, KMERS = {3, 3},
    FIND = {2, 2}, RESTRICT = {2, 7}, PALINDROMES = {3, 3},
    REPEATS = {4, 4}, HAMMING = {2, 2}, ALIGN = {6, 6},
    CONSENSUS = {2, 10}, TM = {1, 1}, MASS = {1, 1},
    PRIMER = {1, 1}, FOLD = {2, 2}, ASSEMBLE = {4, 10},
    PACK = {1, 1}, UNPACK = {3, 3}
}

local sequences = {}
local output = {}

local function emit(...)
    local values = {...}
    for i, value in ipairs(values) do
        values[i] = tostring(value)
    end
    output[#output + 1] = table.concat(values, " ")
end

local function emit_list(label, values)
    if #values == 0 then
        emit(label, "none")
        return
    end
    local pieces = {label}
    for _, value in ipairs(values) do
        pieces[#pieces + 1] = value
    end
    emit(table.unpack(pieces))
end

local function fail(reason)
    error({command_error = reason}, 0)
end

local function revcomp(sequence)
    return (sequence:reverse():gsub(".", complement))
end

local function gc(sequence)
    local _, count = sequence:gsub("[GC]", "")
    return count
end

local function fixed(value, places)
    local scale = 10 ^ places
    return math.floor(value / scale) .. "." ..
           string.format("%0" .. places .. "d", value % scale)
end

local function pct(part, whole)
    return fixed(math.floor(10000 * part / whole), 2)
end

local function transition(a, b)
    local pair = a .. b
    return a ~= b and (pair == "AG" or pair == "GA" or pair == "CT" or pair == "TC")
end

local function frequency_order(counts)
    local keys = {}
    for key in pairs(counts) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    return keys
end

local function codons(sequence, frame)
    local strand = frame > 0 and sequence or revcomp(sequence)
    local triplets = {}
    for i = math.abs(frame), #strand - 2, 3 do
        triplets[#triplets + 1] = strand:sub(i, i + 2)
    end
    return triplets
end

local function occurrences(sequence, motif)
    local positions = {}
    for start = 1, #sequence - #motif + 1 do
        local valid = true
        for i = 1, #motif do
            local base = sequence:sub(start + i - 1, start + i - 1)
            local symbol = motif:sub(i, i)
            if not iupac[symbol]:find(base, 1, true) then
                valid = false
                break
            end
        end
        if valid then
            positions[#positions + 1] = start
        end
    end
    return positions
end

local function repeat_count(sequence, start, width)
    local unit = sequence:sub(start, start + width - 1)
    local count = 0
    while sequence:sub(start + count * width,
                       start + (count + 1) * width - 1) == unit do
        count = count + 1
    end
    return count
end

local function primitive(unit)
    for width = 1, #unit - 1 do
        if #unit % width == 0 and
           unit:sub(1, width):rep(#unit / width) == unit then
            return false
        end
    end
    return true
end

local function longest_palindrome(sequence)
    local best = 0
    for center = 2, #sequence do
        local left, right = center - 1, center
        while left >= 1 and right <= #sequence and
              complement[sequence:sub(left, left)] == sequence:sub(right, right) do
            best = math.max(best, right - left + 1)
            left, right = left - 1, right + 1
        end
    end
    return best
end

local function temperature(sequence)
    local n, amount = #sequence, gc(sequence)
    if n < 14 then
        return 10 * (2 * (n - amount) + 4 * amount)
    end
    return math.floor((649 * n + 410 * amount - 6724) / n)
end

local function strand_mass(sequence)
    local total = 0
    for i = 1, #sequence do
        total = total + base_mass[sequence:sub(i, i)]
    end
    return total - (#sequence - 1) * 18015
end

local function number(text, minimum, maximum, nonzero)
    local digits = text:match("^%-?(%d+)$")
    if not digits or #digits > 6 then
        fail("invalid number " .. text)
    end
    local value = tonumber(text)
    if value < minimum or value > maximum or (nonzero and value == 0) then
        fail("invalid number " .. text)
    end
    return value
end

local function kinds(command, count)
    if command == "SEQ" then return {"new", "sequence"} end
    if command == "SLICE" then return {"name", "position", "position", "new"} end
    if command == "MUTATE" then return {"name", "position", "base"} end
    if command == "TRANSLATE" or command == "CODONS" or command == "PROTEIN" then
        return {"name", "frame"}
    end
    if command == "ORFS" then return {"name", "orf"} end
    if command == "GCWINDOW" then return {"name", "window", "window"} end
    if command == "KMERS" then return {"name", "kmer", "limit"} end
    if command == "FIND" then return {"name", "motif"} end
    if command == "PALINDROMES" then return {"name", "palindrome", "palindrome"} end
    if command == "REPEATS" then return {"name", "repeat", "repeat", "repeat_count"} end
    if command == "ALIGN" then
        return {"name", "name", "mode", "match", "mismatch", "gap"}
    end
    if command == "FOLD" then return {"name", "loop"} end
    if command == "UNPACK" then return {"new", "length", "hex"} end

    local result = {}
    if command == "JOIN" or command == "ASSEMBLE" then
        result[1] = "new"
        if command == "ASSEMBLE" then result[2] = "overlap" end
    end
    for i = 1, count do
        if not result[i] then
            result[i] = command == "RESTRICT" and i > 1 and "enzyme" or "name"
        end
    end
    return result
end

local bounds = {
    frame = {-3, 3}, orf = {1, 200}, window = {1, 500},
    kmer = {1, 12}, limit = {1, 100}, palindrome = {2, 20},
    repeat = {1, 6}, repeat_count = {2, 50}, match = {1, 20},
    mismatch = {-20, 0}, gap = {-20, -1}, loop = {0, 10},
    overlap = {1, 100}, length = {1, 500}
}

local function validate(command, args)
    local range = arity[command]
    if not range then fail("unknown command " .. command) end
    if #args < range[1] or #args > range[2] then fail("wrong argument count") end
    local values = {}
    local seen = {}
    local types = kinds(command, #args)
    for i, text in ipairs(args) do
        local kind = types[i]
        local numeric = bounds[kind]
        if kind == "position" then
            numeric = {1, #sequences[args[1]]}
        end
        if numeric then
            values[i] = number(text, numeric[1], numeric[2], kind == "frame")
        elseif kind == "name" then
            if not sequences[text] then fail("unknown sequence " .. text) end
            values[i] = text
        elseif kind == "new" then
            if not text:match("^[a-z][a-z0-9]*$") or #text > 10 then
                fail("invalid name " .. text)
            end
            values[i] = text
        elseif kind == "sequence" then
            for position = 1, #text do
                local base = text:sub(position, position)
                if not bases:find(base, 1, true) then
                    fail("invalid base " .. base .. " at " .. position)
                end
            end
            values[i] = text
        elseif kind == "base" then
            if #text ~= 1 or not bases:find(text, 1, true) then
                fail("invalid base " .. text)
            end
            values[i] = text
        elseif kind == "motif" then
            if #text < 1 or #text > 30 then fail("invalid motif " .. text) end
            for j = 1, #text do
                if not iupac[text:sub(j, j)] then fail("invalid motif " .. text) end
            end
            values[i] = text
        elseif kind == "enzyme" then
            if not enzymes[text] then fail("unknown enzyme " .. text) end
            if seen[text] then fail("duplicate enzyme " .. text) end
            seen[text] = true
            values[i] = text
        elseif kind == "mode" then
            if text ~= "GLOBAL" and text ~= "LOCAL" then
                fail("invalid mode " .. text)
            end
            values[i] = text
        elseif kind == "hex" then
            if #text ~= 2 * math.floor((values[2] + 3) / 4) or
               not text:match("^[0-9A-F]+$") then
                fail("invalid hex")
            end
            values[i] = text
        else
            values[i] = text
        end
    end
    return values
end

local function store(name, sequence)
    if #sequence > 500 then fail("too long") end
    local label = sequences[name] and "replaced" or "stored"
    sequences[name] = sequence
    return label .. " " .. name .. " " .. #sequence .. " nt"
end

local function translation(command, name, frame)
    local triplets = codons(sequences[name], frame)
    local translated = {}
    for _, codon in ipairs(triplets) do
        translated[#translated + 1] = genetic_code[codon]
    end
    local protein = table.concat(translated)
    if command == "TRANSLATE" then
        emit(protein ~= "" and protein or "none")
    elseif command == "CODONS" then
        local counts = {}
        for _, codon in ipairs(triplets) do
            counts[codon] = (counts[codon] or 0) + 1
        end
        local order = frequency_order(counts)
        if #order == 0 then emit("none") end
        for _, codon in ipairs(order) do
            emit(codon, genetic_code[codon], counts[codon])
        end
    else
        protein = protein:match("^[^*]*")
        if protein == "" then fail("empty protein") end
        local counts, mass, charge = {}, 18015, 0
        for i = 1, #protein do
            local amino = protein:sub(i, i)
            counts[amino] = (counts[amino] or 0) + 1
            mass = mass + amino_mass[amino]
            if amino == "K" or amino == "R" then charge = charge + 1 end
            if amino == "D" or amino == "E" then charge = charge - 1 end
        end
        emit(protein)
        local charge_text = charge > 0 and "+" .. charge or tostring(charge)
        emit("length", #protein, "mass", fixed(mass, 3), "charge", charge_text)
        local parts = {}
        for _, amino in ipairs(frequency_order(counts)) do
            parts[#parts + 1] = amino .. "=" .. counts[amino]
        end
        emit(table.unpack(parts))
    end
end

local function orfs(sequence, minimum)
    local rows = {}
    for _, frame in ipairs({1, 2, 3, -1, -2, -3}) do
        local triplets = codons(sequence, frame)
        local first = nil
        for position, codon in ipairs(triplets) do
            if not first then
                if codon == "ATG" then first = position end
            elseif genetic_code[codon] == "*" then
                if position - first >= minimum then
                    local left = math.abs(frame) - 1 + 3 * (first - 1)
                    local right = math.abs(frame) - 1 + 3 * position
                    if frame < 0 then
                        left, right = #sequence - right, #sequence - left
                    end
                    local protein = {}
                    for i = first, position - 1 do
                        protein[#protein + 1] = genetic_code[triplets[i]]
                    end
                    rows[#rows + 1] = {left + 1, right, frame, table.concat(protein)}
                end
                first = nil
            end
        end
    end
    table.sort(rows, function(a, b)
        for i = 1, 3 do
            if a[i] ~= b[i] then return a[i] < b[i] end
        end
        return a[4] < b[4]
    end)
    if #rows == 0 then emit("none") end
    for _, row in ipairs(rows) do
        emit(string.format("%+d", row[3]), row[1], row[2], #row[4], row[4])
    end
end

local function restrict(sequence, selected)
    local allcuts = {}
    for _, enzyme in ipairs(selected) do
        local motif, offset = table.unpack(enzymes[enzyme])
        local cuts = {}
        for _, position in ipairs(occurrences(sequence, motif)) do
            local cut = position + offset - 1
            if cut >= 1 and cut < #sequence then
                cuts[#cuts + 1] = cut
                allcuts[cut] = true
            end
        end
        emit_list(enzyme, cuts)
    end
    local endpoints = {0}
    for position in pairs(allcuts) do endpoints[#endpoints + 1] = position end
    table.sort(endpoints)
    endpoints[#endpoints + 1] = #sequence
    local fragments, sizes = {}, {}
    for i = 2, #endpoints do
        local left, right = endpoints[i - 1] + 1, endpoints[i]
        fragments[#fragments + 1] = left .. "-" .. right
        sizes[#sizes + 1] = right - left + 1
    end
    table.sort(sizes, function(a, b) return a > b end)
    emit_list("fragments", fragments)
    emit_list("sizes", sizes)
end

local function repeats(sequence, minimum, maximum, count)
    if minimum > maximum then fail("invalid range") end
    local results = {}
    for width = minimum, maximum do
        local position = 1
        while position + width - 1 <= #sequence do
            local unit = sequence:sub(position, position + width - 1)
            local repeated = repeat_count(sequence, position, width)
            if primitive(unit) and repeated >= count then
                results[#results + 1] = {position, width, repeated, unit}
                position = position + width * repeated
            else
                position = position + 1
            end
        end
    end
    table.sort(results, function(a, b)
        for i = 1, 3 do
            if a[i] ~= b[i] then return a[i] < b[i] end
        end
        return a[4] < b[4]
    end)
    if #results == 0 then emit("none") end
    for _, row in ipairs(results) do
        emit(row[1] .. "-" .. (row[1] + row[2] * row[3] - 1),
             row[4] .. "x" .. row[3])
    end
end

local function align(a, b, mode, match_score, mismatch, gap)
    local m, n = #a, #b
    local local_alignment = mode == "LOCAL"
    local table_ = {}
    for i = 0, m do
        table_[i] = {}
        for j = 0, n do table_[i][j] = 0 end
    end
    if not local_alignment then
        for i = 0, m do table_[i][0] = i * gap end
        for j = 0, n do table_[0][j] = j * gap end
    end
    local best, end_i, end_j = 0, 0, 0
    for i = 1, m do
        for j = 1, n do
            local score = a:sub(i, i) == b:sub(j, j) and match_score or mismatch
            local diagonal = table_[i - 1][j - 1] + score
            local value = math.max(diagonal, table_[i - 1][j] + gap, table_[i][j - 1] + gap)
            table_[i][j] = local_alignment and math.max(0, value) or value
            if local_alignment and table_[i][j] > best then
                best, end_i, end_j = table_[i][j], i, j
            end
        end
    end
    if not local_alignment then
        best, end_i, end_j = table_[m][n], m, n
    end
    if local_alignment and best == 0 then
        emit("score", 0)
        return
    end
    local i, j = end_i, end_j
    local row_a, row_b = {}, {}
    while (local_alignment and table_[i][j] ~= 0) or
          (not local_alignment and (i ~= 0 or j ~= 0)) do
        if i > 0 and j > 0 and
           table_[i][j] == table_[i - 1][j - 1] +
           (a:sub(i, i) == b:sub(j, j) and match_score or mismatch) then
            row_a[#row_a + 1] = a:sub(i, i)
            row_b[#row_b + 1] = b:sub(j, j)
            i, j = i - 1, j - 1
        elseif i > 0 and table_[i][j] == table_[i - 1][j] + gap then
            row_a[#row_a + 1] = a:sub(i, i)
            row_b[#row_b + 1] = "-"
            i = i - 1
        else
            row_a[#row_a + 1] = "-"
            row_b[#row_b + 1] = b:sub(j, j)
            j = j - 1
        end
    end
    local marks, reverse_a, reverse_b = {}, {}, {}
    local identical, gaps = 0, 0
    for pos = #row_a, 1, -1 do
        local x, y = row_a[pos], row_b[pos]
        reverse_a[#reverse_a + 1] = x
        reverse_b[#reverse_b + 1] = y
        if x == "-" or y == "-" then
            marks[#marks + 1] = "-"
            gaps = gaps + 1
        elseif x == y then
            marks[#marks + 1] = "|"
            identical = identical + 1
        else
            marks[#marks + 1] = "*"
        end
    end
    emit("score", best, "a", (i + 1) .. "-" .. end_i,
         "b", (j + 1) .. "-" .. end_j,
         "identity", identical .. "/" .. #marks, "gaps", gaps)
    emit(table.concat(reverse_a))
    emit(table.concat(marks))
    emit(table.concat(reverse_b))
end

local function consensus(names)
    local n = #sequences[names[1]]
    for _, name in ipairs(names) do
        if #sequences[name] ~= n then fail("length mismatch") end
    end
    local profile = {A = {}, C = {}, G = {}, T = {}}
    local consensus_sequence, ambiguous = {}, {}
    for position = 1, n do
        local counts = {A = 0, C = 0, G = 0, T = 0}
        for _, name in ipairs(names) do
            local base = sequences[name]:sub(position, position)
            counts[base] = counts[base] + 1
        end
        local most = math.max(counts.A, counts.C, counts.G, counts.T)
        local tied = {}
        for i = 1, #bases do
            local base = bases:sub(i, i)
            profile[base][#profile[base] + 1] = counts[base]
            if counts[base] == most then tied[#tied + 1] = base end
        end
        consensus_sequence[#consensus_sequence + 1] = tied[1]
        ambiguous[#ambiguous + 1] = symbols[table.concat(tied)]
    end
    for i = 1, #bases do
        local base = bases:sub(i, i)
        emit(base, table.unpack(profile[base]))
    end
    emit("consensus", table.concat(consensus_sequence))
    emit("iupac", table.concat(ambiguous))
end

local function primer(sequence)
    local n, amount, tm = #sequence, gc(sequence), temperature(sequence)
    local clamp = gc(sequence:sub(-5))
    local longest_run, current_run = 0, 0
    local previous = ""
    for i = 1, n do
        local base = sequence:sub(i, i)
        current_run = base == previous and current_run + 1 or 1
        longest_run = math.max(longest_run, current_run)
        previous = base
    end
    local repeated = 0
    for i = 1, n - 1 do
        if sequence:sub(i, i) ~= sequence:sub(i + 1, i + 1) then
            repeated = math.max(repeated, repeat_count(sequence, i, 2))
        end
    end
    local selfcomp = longest_palindrome(sequence)
    local items = {
        {"length", n, n >= 18 and n <= 25},
        {"gc", pct(amount, n), 40 * n <= 100 * amount and 100 * amount <= 60 * n},
        {"tm", fixed(tm, 1), tm >= 520 and tm <= 620},
        {"clamp", clamp, clamp >= 1 and clamp <= 3},
        {"run", longest_run, longest_run <= 4},
        {"repeat", repeated, repeated <= 4},
        {"selfcomp", selfcomp, selfcomp <= 6}
    }
    local failed = {}
    for _, item in ipairs(items) do
        emit(item[1], item[2], item[3] and "OK" or "FAIL")
        if not item[3] then failed[#failed + 1] = item[1] end
    end
    if #failed == 0 then
        emit("PASS")
    else
        emit("FAIL", table.unpack(failed))
    end
end

local function fold(sequence, loop)
    local n = #sequence
    if n > 100 then fail("too long") end
    local table_ = {}
    for i = 1, n do
        table_[i] = {}
        for j = 1, n do table_[i][j] = 0 end
    end
    local function value(i, j)
        return i > j and 0 or table_[i][j]
    end
    local function paired(i, j)
        local pair = sequence:sub(i, i) .. sequence:sub(j, j)
        return pair == "AT" or pair == "TA" or pair == "CG" or
               pair == "GC" or pair == "GT" or pair == "TG"
    end
    for width = 2, n do
        for i = 1, n - width + 1 do
            local j = i + width - 1
            local best = value(i, j - 1)
            for k = i, j - loop - 1 do
                if paired(k, j) then
                    best = math.max(best, value(i, k - 1) + 1 + value(k + 1, j - 1))
                end
            end
            table_[i][j] = best
        end
    end
    local structure = {}
    for i = 1, n do structure[i] = "." end
    local pending = {{1, n}}
    while #pending > 0 do
        local pair = table.remove(pending)
        local i, j = pair[1], pair[2]
        if i <= j and value(i, j) > 0 then
            if value(i, j) == value(i, j - 1) then
                pending[#pending + 1] = {i, j - 1}
            else
                for k = i, j - loop - 1 do
                    if paired(k, j) and
                       value(i, k - 1) + 1 + value(k + 1, j - 1) == value(i, j) then
                        structure[k], structure[j] = "(", ")"
                        pending[#pending + 1] = {i, k - 1}
                        pending[#pending + 1] = {k + 1, j - 1}
                        break
                    end
                end
            end
        end
    end
    emit(table.concat(structure))
    emit("pairs", table_[1][n])
end

local function assemble(name, minimum, fragments)
    local unique, seen = {}, {}
    for _, sequence in ipairs(fragments) do
        if not seen[sequence] then
            seen[sequence] = true
            unique[#unique + 1] = sequence
        end
    end
    fragments = {}
    for _, sequence in ipairs(unique) do
        local contained = false
        for _, other in ipairs(unique) do
            if sequence ~= other and other:find(sequence, 1, true) then
                contained = true
                break
            end
        end
        if not contained then fragments[#fragments + 1] = sequence end
    end
    while #fragments >= 2 do
        local best, chosen_i, chosen_j = 0, nil, nil
        for i, x in ipairs(fragments) do
            for j, y in ipairs(fragments) do
                if i ~= j then
                    local overlap = 0
                    for width = math.min(#x, #y) - 1, 1, -1 do
                        if x:sub(-width) == y:sub(1, width) then
                            overlap = width
                            break
                        end
                    end
                    if not chosen_i or overlap > best then
                        best, chosen_i, chosen_j = overlap, i, j
                    end
                end
            end
        end
        if best < minimum then break end
        local merged = fragments[chosen_i] .. fragments[chosen_j]:sub(best + 1)
        local next_fragments = {}
        for i, fragment in ipairs(fragments) do
            if i == chosen_i then
                next_fragments[#next_fragments + 1] = merged
            elseif i ~= chosen_j and not merged:find(fragment, 1, true) then
                next_fragments[#next_fragments + 1] = fragment
            end
        end
        fragments = next_fragments
    end
    local longest = fragments[1]
    for _, fragment in ipairs(fragments) do
        if #fragment > #longest then longest = fragment end
    end
    local registration = store(name, longest)
    emit("contigs", #fragments)
    for _, fragment in ipairs(fragments) do
        emit(#fragment, fragment)
    end
    emit(registration)
end

local function command(cmd, args)
    if cmd == "SEQ" then
        emit(store(args[1], args[2]))
        return
    elseif cmd == "UNPACK" then
        local codes = {}
        for i = 1, #args[3], 2 do
            local byte = tonumber(args[3]:sub(i, i + 1), 16)
            codes[#codes + 1] = math.floor(byte / 64)
            codes[#codes + 1] = math.floor(byte / 16) % 4
            codes[#codes + 1] = math.floor(byte / 4) % 4
            codes[#codes + 1] = byte % 4
        end
        for i = args[2] + 1, #codes do
            if codes[i] ~= 0 then fail("invalid padding") end
        end
        local sequence = {}
        for i = 1, args[2] do
            sequence[#sequence + 1] = bases:sub(codes[i] + 1, codes[i] + 1)
        end
        emit(store(args[1], table.concat(sequence)))
        return
    elseif cmd == "JOIN" then
        local parts = {}
        for i = 2, #args do parts[#parts + 1] = sequences[args[i]] end
        emit(store(args[1], table.concat(parts)))
        return
    elseif cmd == "ASSEMBLE" then
        local parts = {}
        for i = 3, #args do parts[#parts + 1] = sequences[args[i]] end
        assemble(args[1], args[2], parts)
        return
    elseif cmd == "LIST" then
        local names = {}
        for name in pairs(sequences) do names[#names + 1] = name end
        table.sort(names)
        if #names == 0 then emit("no sequences") end
        for _, name in ipairs(names) do emit(name, #sequences[name], "nt") end
        return
    end
    local name = args[1]
    local sequence = sequences[name]
    local n = #sequence
    if cmd == "SLICE" then
        local first, last = args[2], args[3]
        local part = first <= last and sequence:sub(first, last) or
                     revcomp(sequence:sub(last, first))
        emit(store(args[4], part))
    elseif cmd == "MUTATE" then
        local position, base = args[2], args[3]
        local old = sequence:sub(position, position)
        if old == base then fail("no change") end
        sequences[name] = sequence:sub(1, position - 1) .. base .. sequence:sub(position + 1)
        emit(name, old .. position .. base, transition(old, base) and
             "transition" or "transversion")
    elseif cmd == "DEL" then
        sequences[name] = nil
        emit("deleted", name)
    elseif cmd == "REVCOMP" then
        emit(revcomp(sequence))
    elseif cmd == "COMPLEMENT" then
        emit((sequence:gsub(".", complement)))
    elseif cmd == "REVERSE" then
        emit(sequence:reverse())
    elseif cmd == "TRANSCRIBE" then
        emit((sequence:gsub("T", "U")))
    elseif cmd == "TRANSLATE" or cmd == "CODONS" or cmd == "PROTEIN" then
        translation(cmd, name, args[2])
    elseif cmd == "ORFS" then
        orfs(sequence, args[2])
    elseif cmd == "GC" then
        local fields = {}
        for i = 1, #bases do
            local base = bases:sub(i, i)
            local _, count = sequence:gsub(base, "")
            fields[#fields + 1] = base .. "=" .. count
        end
        fields[#fields + 1] = "GC=" .. pct(gc(sequence), n) .. "%"
        emit(table.unpack(fields))
    elseif cmd == "GCWINDOW" then
        local width, step = args[2], args[3]
        if width > n then fail("window too large") end
        for i = 1, n - width + 1, step do
            emit(i .. "-" .. (i + width - 1),
                 pct(gc(sequence:sub(i, i + width - 1)), width) .. "%")
        end
    elseif cmd == "SKEW" then
        local values = {0}
        for i = 1, n do
            local base = sequence:sub(i, i)
            values[i + 1] = values[i] + (base == "G" and 1 or 0) -
                            (base == "C" and 1 or 0)
        end
        local least, greatest = values[1], values[1]
        for _, value in ipairs(values) do
            least, greatest = math.min(least, value), math.max(greatest, value)
        end
        for _, item in ipairs({{"min", least}, {"max", greatest}}) do
            local locations = {item[1], item[2], "at"}
            for i, value in ipairs(values) do
                if value == item[2] then locations[#locations + 1] = i - 1 end
            end
            emit(table.unpack(locations))
        end
    elseif cmd == "KMERS" then
        local width, limit = args[2], args[3]
        if width > n then fail("k too large") end
        local counts = {}
        for i = 1, n - width + 1 do
            local word = sequence:sub(i, i + width - 1)
            counts[word] = (counts[word] or 0) + 1
        end
        local order = frequency_order(counts)
        emit(n - width + 1, "windows", #order, "distinct")
        for i = 1, math.min(limit, #order) do
            local word = order[i]
            emit(word, counts[word])
        end
    elseif cmd == "FIND" then
        emit_list("forward", occurrences(sequence, args[2]))
        emit_list("reverse", occurrences(sequence, revcomp(args[2])))
    elseif cmd == "RESTRICT" then
        local selected = {}
        for i = 2, #args do selected[#selected + 1] = args[i] end
        restrict(sequence, selected)
    elseif cmd == "PALINDROMES" then
        local minimum, maximum = args[2], args[3]
        if minimum > maximum then fail("invalid range") end
        local found = false
        for i = 1, n do
            for width = minimum, math.min(maximum, n - i + 1) do
                local part = sequence:sub(i, i + width - 1)
                if part == revcomp(part) then
                    emit(i, width, part)
                    found = true
                end
            end
        end
        if not found then emit("none") end
    elseif cmd == "REPEATS" then
        repeats(sequence, args[2], args[3], args[4])
    elseif cmd == "HAMMING" then
        local other = sequences[args[2]]
        if #other ~= n then fail("length mismatch") end
        local distance, changes = 0, 0
        for i = 1, n do
            local a, b = sequence:sub(i, i), other:sub(i, i)
            if a ~= b then
                distance = distance + 1
                if transition(a, b) then changes = changes + 1 end
            end
        end
        emit("distance", distance, "transitions", changes,
             "transversions", distance - changes)
    elseif cmd == "ALIGN" then
        align(sequence, sequences[args[2]], args[3], args[4], args[5], args[6])
    elseif cmd == "CONSENSUS" then
        consensus(args)
    elseif cmd == "TM" then
        emit("Tm", fixed(temperature(sequence), 1), n < 14 and "wallace" or "gc")
    elseif cmd == "MASS" then
        local single = strand_mass(sequence)
        emit("ss", fixed(single, 3), "ds", fixed(single + strand_mass(revcomp(sequence)), 3))
    elseif cmd == "PRIMER" then
        primer(sequence)
    elseif cmd == "FOLD" then
        fold(sequence, args[2])
    elseif cmd == "PACK" then
        local codes = {}
        for i = 1, n do
            codes[#codes + 1] = bases:find(sequence:sub(i, i), 1, true) - 1
        end
        while #codes % 4 ~= 0 do codes[#codes + 1] = 0 end
        local encoded = {}
        for i = 1, #codes, 4 do
            local byte = codes[i] * 64 + codes[i + 1] * 16 +
                         codes[i + 2] * 4 + codes[i + 3]
            encoded[#encoded + 1] = string.format("%02X", byte)
        end
        emit(n, table.concat(encoded))
    end
end

local function execute(line)
    local fields = {}
    for token in line:gmatch("[^ ]+") do fields[#fields + 1] = token end
    local command_name = fields[1]
    local arguments = {}
    for i = 2, #fields do arguments[#arguments + 1] = fields[i] end
    local ok, reason = pcall(function()
        local values = validate(command_name, arguments)
        command(command_name, values)
    end)
    if not ok then
        if type(reason) == "table" and reason.command_error then
            emit("ERROR", reason.command_error)
        else
            error(reason)
        end
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    execute(io.read("*l"))
end
io.write(table.concat(output, "\n"), "\n")
