using Printf

const BASES = "ACGT"
const IUPAC = Dict(
    'A' => "A", 'C' => "C", 'G' => "G", 'T' => "T", 'R' => "AG",
    'Y' => "CT", 'W' => "AT", 'S' => "CG", 'K' => "GT", 'M' => "AC",
    'B' => "CGT", 'D' => "AGT", 'H' => "ACT", 'V' => "ACG", 'N' => "ACGT"
)
const SYMBOL = Dict(value => key for (key, value) in IUPAC)
const COMPLEMENT = Dict(
    'A' => 'T', 'C' => 'G', 'G' => 'C', 'T' => 'A', 'R' => 'Y',
    'Y' => 'R', 'W' => 'W', 'S' => 'S', 'K' => 'M', 'M' => 'K',
    'B' => 'V', 'D' => 'H', 'H' => 'D', 'V' => 'B', 'N' => 'N'
)
const GENETIC_GROUPS = Dict(
    "A" => "GCT GCC GCA GCG", "C" => "TGT TGC", "D" => "GAT GAC",
    "E" => "GAA GAG", "F" => "TTT TTC", "G" => "GGT GGC GGA GGG",
    "H" => "CAT CAC", "I" => "ATT ATC ATA", "K" => "AAA AAG",
    "L" => "TTA TTG CTT CTC CTA CTG", "M" => "ATG", "N" => "AAT AAC",
    "P" => "CCT CCC CCA CCG", "Q" => "CAA CAG",
    "R" => "CGT CGC CGG CGA AGA AGG", "S" => "TCT TCC TCA TCG AGT AGC",
    "T" => "ACT ACC ACA ACG", "V" => "GTT GTC GTA GTG", "W" => "TGG",
    "Y" => "TAT TAC", "*" => "TAA TAG TGA"
)
const GENETIC_CODE = let table = Dict{String, String}()
    for (amino, group) in GENETIC_GROUPS
        for codon in split(group)
            table[String(codon)] = amino
        end
    end
    table
end
const AMINO_MASS = Dict(zip(
    "ACDEFGHIKLMNPQRSTVWY",
    [71079, 103139, 115089, 129116, 147177, 57052, 137141,
     113160, 128174, 113160, 131193, 114104, 97117, 128131,
     156188, 87078, 101105, 99133, 186213, 163176]
))
const BASE_MASS = Dict(zip("ACGT", [331222, 307197, 347221, 322208]))
const ENZYMES = Dict(
    "EcoRI" => ("GAATTC", 1), "BamHI" => ("GGATCC", 1),
    "HindIII" => ("AAGCTT", 1), "PstI" => ("CTGCAG", 5),
    "SmaI" => ("CCCGGG", 3), "KpnI" => ("GGTACC", 5),
    "XbaI" => ("TCTAGA", 1), "NotI" => ("GCGGCCGC", 2),
    "EcoRV" => ("GATATC", 3), "HaeIII" => ("GGCC", 2),
    "AluI" => ("AGCT", 2), "TaqI" => ("TCGA", 1),
    "Sau3AI" => ("GATC", 0), "HincII" => ("GTYRAC", 3),
    "AvaI" => ("CYCGRG", 1)
)
const ARITY = Dict(
    "SEQ" => (2, 2), "SLICE" => (4, 4), "JOIN" => (3, 9),
    "MUTATE" => (3, 3), "DEL" => (1, 1), "LIST" => (0, 0),
    "REVCOMP" => (1, 1), "COMPLEMENT" => (1, 1), "REVERSE" => (1, 1),
    "TRANSCRIBE" => (1, 1), "TRANSLATE" => (2, 2), "CODONS" => (2, 2),
    "PROTEIN" => (2, 2), "ORFS" => (2, 2), "GC" => (1, 1),
    "GCWINDOW" => (3, 3), "SKEW" => (1, 1), "KMERS" => (3, 3),
    "FIND" => (2, 2), "RESTRICT" => (2, 7), "PALINDROMES" => (3, 3),
    "REPEATS" => (4, 4), "HAMMING" => (2, 2), "ALIGN" => (6, 6),
    "CONSENSUS" => (2, 10), "TM" => (1, 1), "MASS" => (1, 1),
    "PRIMER" => (1, 1), "FOLD" => (2, 2), "ASSEMBLE" => (4, 10),
    "PACK" => (1, 1), "UNPACK" => (3, 3)
)

struct CommandError <: Exception
    message::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.message)
fail(message::String) = throw(CommandError(message))

revcomp(sequence::AbstractString) = join(COMPLEMENT[base] for base in reverse(sequence))
gc(sequence::AbstractString) = count(base -> base == 'G' || base == 'C', sequence)
fixed(value::Int, places::Int) = string(div(value, 10^places), ".", lpad(string(mod(value, 10^places)), places, '0'))
pct(part::Int, whole::Int) = fixed(div(10000 * part, whole), 2)
transition(a::Char, b::Char) = a != b && string(a, b) in ("AG", "GA", "CT", "TC")
frequency_order(table) = sort(collect(keys(table)); by=key -> (-table[key], key))

function codons(sequence::String, frame::Int)
    strand = frame > 0 ? sequence : revcomp(sequence)
    triplets = String[]
    for i in abs(frame):3:(length(strand) - 2)
        push!(triplets, strand[i:i+2])
    end
    triplets
end

function occurrences(sequence::String, motif::String)
    positions = Int[]
    n, width = length(sequence), length(motif)
    for i in 1:(n - width + 1)
        if all(sequence[i+j-1] in IUPAC[motif[j]] for j in 1:width)
            push!(positions, i)
        end
    end
    positions
end

function repeat_count(sequence::String, position::Int, width::Int)
    unit = sequence[position:position+width-1]
    count = 0
    while position + (count + 1) * width - 1 <= length(sequence) &&
          sequence[position+count*width:position+(count+1)*width-1] == unit
        count += 1
    end
    count
end

function primitive(unit::String)
    n = length(unit)
    all(n % width != 0 || repeat(unit[1:width], div(n, width)) != unit
        for width in 1:(n-1))
end

function longest_palindrome(sequence::String)
    best = 0
    for center in 2:length(sequence)
        left, right = center - 1, center
        while left >= 1 && right <= length(sequence) &&
              COMPLEMENT[sequence[left]] == sequence[right]
            best = max(best, right - left + 1)
            left -= 1
            right += 1
        end
    end
    best
end

function temperature(sequence::String)
    n, amount = length(sequence), gc(sequence)
    n < 14 ? 10 * (2 * (n - amount) + 4 * amount) :
             fld(649 * n + 410 * amount - 6724, n)
end

strand_mass(sequence::String) =
    sum(BASE_MASS[base] for base in sequence) - (length(sequence) - 1) * 18015

mutable struct Toolkit
    sequences::Dict{String, String}
    output::Vector{String}
end
Toolkit() = Toolkit(Dict{String, String}(), String[])

emit!(tool::Toolkit, parts...) = push!(tool.output, join(string.(parts), " "))
emit_list!(tool::Toolkit, label, values) =
    emit!(tool, label, isempty(values) ? "none" : join(string.(values), " "))

function number(text::String, minimum::Int, maximum::Int; nonzero::Bool=false)
    occursin(r"^-?[0-9]{1,6}$", text) || fail("invalid number " * text)
    value = parse(Int, text)
    minimum <= value <= maximum && (!nonzero || value != 0) ||
        fail("invalid number " * text)
    value
end

function kinds(command::String, count::Int)
    if command == "SEQ"
        return ["new", "sequence"]
    elseif command == "SLICE"
        return ["name", "position", "position", "new"]
    elseif command == "JOIN"
        return vcat(["new"], fill("name", count - 1))
    elseif command == "MUTATE"
        return ["name", "position", "base"]
    elseif command in ("TRANSLATE", "CODONS", "PROTEIN")
        return ["name", "frame"]
    elseif command == "ORFS"
        return ["name", "orf"]
    elseif command == "GCWINDOW"
        return ["name", "window", "window"]
    elseif command == "KMERS"
        return ["name", "kmer", "limit"]
    elseif command == "FIND"
        return ["name", "motif"]
    elseif command == "RESTRICT"
        return vcat(["name"], fill("enzyme", count - 1))
    elseif command == "PALINDROMES"
        return ["name", "palindrome", "palindrome"]
    elseif command == "REPEATS"
        return ["name", "repeat", "repeat", "repeat_count"]
    elseif command == "ALIGN"
        return ["name", "name", "mode", "match", "mismatch", "gap"]
    elseif command == "FOLD"
        return ["name", "loop"]
    elseif command == "ASSEMBLE"
        return vcat(["new", "overlap"], fill("name", count - 2))
    elseif command == "UNPACK"
        return ["new", "length", "hex"]
    end
    fill("name", count)
end

function validate(tool::Toolkit, command::String, arguments::Vector{String})
    haskey(ARITY, command) || fail("unknown command " * command)
    minimum, maximum = ARITY[command]
    minimum <= length(arguments) <= maximum || fail("wrong argument count")
    values = Any[arguments...]
    seen_enzymes = Set{String}()
    for (i, (kind, text)) in enumerate(zip(kinds(command, length(arguments)), arguments))
        if kind in ("position", "frame", "orf", "window", "kmer", "limit",
                    "palindrome", "repeat", "repeat_count", "match", "mismatch",
                    "gap", "loop", "overlap", "length")
            bounds = if kind == "position"
                (1, length(tool.sequences[arguments[1]]))
            elseif kind == "frame"
                (-3, 3)
            elseif kind == "orf"
                (1, 200)
            elseif kind == "window"
                (1, 500)
            elseif kind == "kmer"
                (1, 12)
            elseif kind == "limit"
                (1, 100)
            elseif kind == "palindrome"
                (2, 20)
            elseif kind == "repeat"
                (1, 6)
            elseif kind == "repeat_count"
                (2, 50)
            elseif kind == "match"
                (1, 20)
            elseif kind == "mismatch"
                (-20, 0)
            elseif kind == "gap"
                (-20, -1)
            elseif kind == "loop"
                (0, 10)
            elseif kind == "overlap"
                (1, 100)
            else
                (1, 500)
            end
            values[i] = number(text, bounds[1], bounds[2]; nonzero=kind == "frame")
        elseif kind == "name"
            haskey(tool.sequences, text) || fail("unknown sequence " * text)
        elseif kind == "new"
            occursin(r"^[a-z][a-z0-9]{0,9}$", text) || fail("invalid name " * text)
        elseif kind == "sequence"
            for (position, base) in enumerate(text)
                base in BASES || fail("invalid base $base at $position")
            end
        elseif kind == "base"
            length(text) == 1 && text[1] in BASES || fail("invalid base " * text)
        elseif kind == "motif"
            1 <= length(text) <= 30 && all(haskey(IUPAC, c) for c in text) ||
                fail("invalid motif " * text)
        elseif kind == "enzyme"
            haskey(ENZYMES, text) || fail("unknown enzyme " * text)
            text in seen_enzymes && fail("duplicate enzyme " * text)
            push!(seen_enzymes, text)
        elseif kind == "mode"
            text in ("GLOBAL", "LOCAL") || fail("invalid mode " * text)
        elseif kind == "hex"
            length(text) == 2 * cld(values[2], 4) &&
                occursin(r"^[0-9A-F]+$", text) || fail("invalid hex")
        end
    end
    values
end

function store!(tool::Toolkit, name::String, sequence::String)
    length(sequence) <= 500 || fail("too long")
    label = haskey(tool.sequences, name) ? "replaced" : "stored"
    tool.sequences[name] = sequence
    "$label $name $(length(sequence)) nt"
end

function translation!(tool::Toolkit, command::String, name::String, frame::Int)
    triplets = codons(tool.sequences[name], frame)
    protein = join(GENETIC_CODE[c] for c in triplets)
    if command == "TRANSLATE"
        emit!(tool, isempty(protein) ? "none" : protein)
    elseif command == "CODONS"
        table = Dict(codon => count(==(codon), triplets) for codon in unique(triplets))
        isempty(table) && emit!(tool, "none")
        for codon in frequency_order(table)
            emit!(tool, codon, GENETIC_CODE[codon], table[codon])
        end
    else
        protein = first(split(protein, "*"; limit=2))
        isempty(protein) && fail("empty protein")
        table = Dict(amino => count(==(amino), protein) for amino in unique(protein))
        mass = sum(AMINO_MASS[c] for c in protein) + 18015
        charge = count(c -> c in "KR", protein) - count(c -> c in "DE", protein)
        emit!(tool, protein)
        emit!(tool, "length", length(protein), "mass", fixed(mass, 3),
              "charge", charge > 0 ? "+$charge" : string(charge))
        emit!(tool, join(["$amino=$(table[amino])" for amino in frequency_order(table)], " "))
    end
end

function orfs!(tool::Toolkit, sequence::String, minimum::Int)
    rows = Tuple{Int, Int, Int, String}[]
    for frame in (1, 2, 3, -1, -2, -3)
        triplets = codons(sequence, frame)
        first_codon = nothing
        for (position, codon) in enumerate(triplets)
            if first_codon === nothing
                codon == "ATG" && (first_codon = position)
            elseif GENETIC_CODE[codon] == "*"
                if position - first_codon >= minimum
                    left = abs(frame) - 1 + 3 * (first_codon - 1)
                    right = abs(frame) - 1 + 3 * position
                    if frame < 0
                        left, right = length(sequence) - right, length(sequence) - left
                    end
                    protein = join(GENETIC_CODE[triplets[i]] for i in first_codon:(position-1))
                    push!(rows, (left + 1, right, frame, protein))
                end
                first_codon = nothing
            end
        end
    end
    isempty(rows) && emit!(tool, "none")
    for (left, right, frame, protein) in sort(rows)
        emit!(tool, @sprintf("%+d", frame), left, right, length(protein), protein)
    end
end

function restrict!(tool::Toolkit, sequence::String, selected::Vector{String})
    cuts = Set{Int}()
    for enzyme in selected
        motif, offset = ENZYMES[enzyme]
        positions = [p + offset - 1 for p in occurrences(sequence, motif)
                     if 1 <= p + offset - 1 < length(sequence)]
        emit_list!(tool, enzyme, positions)
        union!(cuts, positions)
    end
    endpoints = vcat([0], sort(collect(cuts)), [length(sequence)])
    fragments = ["$(a+1)-$b" for (a, b) in zip(endpoints[1:end-1], endpoints[2:end])]
    sizes = sort([b - a for (a, b) in zip(endpoints[1:end-1], endpoints[2:end])]; rev=true)
    emit_list!(tool, "fragments", fragments)
    emit_list!(tool, "sizes", sizes)
end

function repeats!(tool::Toolkit, sequence::String, minimum::Int, maximum::Int, count::Int)
    minimum <= maximum || fail("invalid range")
    rows = Tuple{Int, Int, Int, String}[]
    for width in minimum:maximum
        position = 1
        while position + width - 1 <= length(sequence)
            unit = sequence[position:position+width-1]
            repeated = repeat_count(sequence, position, width)
            if primitive(unit) && repeated >= count
                push!(rows, (position, width, repeated, unit))
                position += width * repeated
            else
                position += 1
            end
        end
    end
    isempty(rows) && emit!(tool, "none")
    for (position, width, repeated, unit) in sort(rows)
        emit!(tool, "$position-$(position + width * repeated - 1)", "$(unit)x$repeated")
    end
end

function align!(tool::Toolkit, a::String, b::String, mode::String,
                match_score::Int, mismatch::Int, gap::Int)
    m, n = length(a), length(b)
    local_alignment = mode == "LOCAL"
    table = zeros(Int, m + 1, n + 1)
    if !local_alignment
        for i in 0:m
            table[i+1, 1] = i * gap
        end
        for j in 0:n
            table[1, j+1] = j * gap
        end
    end
    best, end_i, end_j = 0, 0, 0
    for i in 1:m, j in 1:n
        diagonal = table[i, j] + (a[i] == b[j] ? match_score : mismatch)
        score = max(diagonal, table[i, j+1] + gap, table[i+1, j] + gap)
        table[i+1, j+1] = local_alignment ? max(0, score) : score
        if local_alignment && table[i+1, j+1] > best
            best, end_i, end_j = table[i+1, j+1], i, j
        end
    end
    if !local_alignment
        best, end_i, end_j = table[m+1, n+1], m, n
    end
    if local_alignment && best == 0
        emit!(tool, "score", 0)
        return
    end
    i, j = end_i, end_j
    row_a, row_b = Char[], Char[]
    while (local_alignment && table[i+1, j+1] != 0) ||
          (!local_alignment && (i != 0 || j != 0))
        if i > 0 && j > 0 && table[i+1, j+1] ==
           table[i, j] + (a[i] == b[j] ? match_score : mismatch)
            push!(row_a, a[i])
            push!(row_b, b[j])
            i -= 1
            j -= 1
        elseif i > 0 && table[i+1, j+1] == table[i, j+1] + gap
            push!(row_a, a[i])
            push!(row_b, '-')
            i -= 1
        else
            push!(row_a, '-')
            push!(row_b, b[j])
            j -= 1
        end
    end
    reverse!(row_a)
    reverse!(row_b)
    marks = [x == '-' || y == '-' ? '-' : x == y ? '|' : '*'
             for (x, y) in zip(row_a, row_b)]
    emit!(tool, "score", best, "a", "$(i+1)-$end_i", "b", "$(j+1)-$end_j",
          "identity", "$(count(==('|'), marks))/$(length(marks))",
          "gaps", count(==('-'), marks))
    emit!(tool, join(row_a))
    emit!(tool, join(marks))
    emit!(tool, join(row_b))
end

function consensus!(tool::Toolkit, sequences::Vector{String})
    n = length(first(sequences))
    all(length(s) == n for s in sequences) || fail("length mismatch")
    profile = Dict(base => Int[] for base in BASES)
    consensus, ambiguous = Char[], Char[]
    for column in 1:n
        counts = Dict(base => count(s -> s[column] == base, sequences) for base in BASES)
        for base in BASES
            push!(profile[base], counts[base])
        end
        largest = maximum(values(counts))
        tied = join(base for base in BASES if counts[base] == largest)
        push!(consensus, first(tied))
        push!(ambiguous, SYMBOL[tied])
    end
    for base in BASES
        emit!(tool, base, join(profile[base], " "))
    end
    emit!(tool, "consensus", join(consensus))
    emit!(tool, "iupac", join(ambiguous))
end

function primer!(tool::Toolkit, sequence::String)
    n, amount = length(sequence), gc(sequence)
    tm = temperature(sequence)
    clamp = gc(sequence[max(1, n-4):n])
    longest_run, current_run = 0, 0
    previous = '\0'
    for c in sequence
        current_run = c == previous ? current_run + 1 : 1
        longest_run = max(longest_run, current_run)
        previous = c
    end
    repeated = 0
    for i in 1:(n-1)
        if sequence[i] != sequence[i+1]
            repeated = max(repeated, repeat_count(sequence, i, 2))
        end
    end
    selfcomp = longest_palindrome(sequence)
    checks = [
        ("length", string(n), 18 <= n <= 25),
        ("gc", pct(amount, n), 40*n <= 100*amount <= 60*n),
        ("tm", fixed(tm, 1), 520 <= tm <= 620),
        ("clamp", string(clamp), 1 <= clamp <= 3),
        ("run", string(longest_run), longest_run <= 4),
        ("repeat", string(repeated), repeated <= 4),
        ("selfcomp", string(selfcomp), selfcomp <= 6)
    ]
    failed = String[]
    for (label, value, passed) in checks
        emit!(tool, label, value, passed ? "OK" : "FAIL")
        !passed && push!(failed, label)
    end
    if isempty(failed)
        emit!(tool, "PASS")
    else
        emit!(tool, "FAIL", join(failed, " "))
    end
end

paired(a::Char, b::Char) = string(a, b) in ("AT", "TA", "CG", "GC", "GT", "TG")

function fold!(tool::Toolkit, sequence::String, loop::Int)
    n = length(sequence)
    n <= 100 || fail("too long")
    table = zeros(Int, n, n)
    value(i, j) = i > j ? 0 : table[i, j]
    for width in 2:n, i in 1:(n-width+1)
        j = i + width - 1
        best = value(i, j-1)
        for k in i:(j-loop-1)
            if paired(sequence[k], sequence[j])
                best = max(best, value(i, k-1) + 1 + value(k+1, j-1))
            end
        end
        table[i, j] = best
    end
    structure = fill('.', n)
    pending = [(1, n)]
    while !isempty(pending)
        i, j = pop!(pending)
        if i > j || value(i, j) == 0
            continue
        end
        if value(i, j) == value(i, j-1)
            push!(pending, (i, j-1))
            continue
        end
        for k in i:(j-loop-1)
            if paired(sequence[k], sequence[j]) &&
               value(i, k-1) + 1 + value(k+1, j-1) == value(i, j)
                structure[k] = '('
                structure[j] = ')'
                push!(pending, (i, k-1))
                push!(pending, (k+1, j-1))
                break
            end
        end
    end
    emit!(tool, join(structure))
    emit!(tool, "pairs", table[1, n])
end

function assemble!(tool::Toolkit, name::String, minimum::Int, sequences::Vector{String})
    unique_sequences = unique(sequences)
    fragments = [s for s in unique_sequences if
                 !any(s != t && occursin(s, t) for t in unique_sequences)]
    while length(fragments) >= 2
        best = 0
        chosen = nothing
        for i in eachindex(fragments), j in eachindex(fragments)
            i == j && continue
            x, y = fragments[i], fragments[j]
            overlap = 0
            for width in (min(length(x), length(y))-1):-1:1
                if x[end-width+1:end] == y[1:width]
                    overlap = width
                    break
                end
            end
            if chosen === nothing || overlap > best
                best = overlap
                chosen = (i, j)
            end
        end
        best < minimum && break
        i, j = chosen
        merged = fragments[i] * fragments[j][best+1:end]
        fragments = [k == i ? merged : fragments[k]
                     for k in eachindex(fragments)
                     if k == i || (k != j && !occursin(fragments[k], merged))]
    end
    longest = reduce((a, b) -> length(b) > length(a) ? b : a, fragments)
    registration = store!(tool, name, longest)
    emit!(tool, "contigs", length(fragments))
    for fragment in fragments
        emit!(tool, length(fragment), fragment)
    end
    emit!(tool, registration)
end

function run_command!(tool::Toolkit, command::String, a::Vector{Any})
    if command == "SEQ"
        emit!(tool, store!(tool, a[1], a[2]))
        return
    elseif command == "UNPACK"
        codes = Int[]
        for i in 1:2:length(a[3])
            byte = parse(Int, a[3][i:i+1]; base=16)
            append!(codes, (div(byte, 64), div(byte, 16) % 4,
                            div(byte, 4) % 4, byte % 4))
        end
        all(==(0), codes[a[2]+1:end]) || fail("invalid padding")
        emit!(tool, store!(tool, a[1], join(BASES[c+1] for c in codes[1:a[2]])))
        return
    elseif command == "JOIN"
        emit!(tool, store!(tool, a[1], join(tool.sequences[name] for name in a[2:end])))
        return
    elseif command == "ASSEMBLE"
        assemble!(tool, a[1], a[2], [tool.sequences[name] for name in a[3:end]])
        return
    elseif command == "LIST"
        names = sort(collect(keys(tool.sequences)))
        isempty(names) && emit!(tool, "no sequences")
        for name in names
            emit!(tool, name, length(tool.sequences[name]), "nt")
        end
        return
    end
    name, sequence = a[1], tool.sequences[a[1]]
    n = length(sequence)
    if command == "SLICE"
        first, last = a[2:3]
        part = first <= last ? sequence[first:last] : revcomp(sequence[last:first])
        emit!(tool, store!(tool, a[4], part))
    elseif command == "MUTATE"
        position, base = a[2:3]
        old = sequence[position]
        string(old) == base && fail("no change")
        prefix = position > 1 ? sequence[1:position-1] : ""
        suffix = position < n ? sequence[position+1:end] : ""
        tool.sequences[name] = prefix * base * suffix
        emit!(tool, name, "$old$position$base",
              transition(old, first(base)) ? "transition" : "transversion")
    elseif command == "DEL"
        delete!(tool.sequences, name)
        emit!(tool, "deleted", name)
    elseif command in ("REVCOMP", "COMPLEMENT", "REVERSE", "TRANSCRIBE")
        result = if command == "REVCOMP"
            revcomp(sequence)
        elseif command == "COMPLEMENT"
            join(COMPLEMENT[base] for base in sequence)
        elseif command == "REVERSE"
            reverse(sequence)
        else
            replace(sequence, 'T' => 'U')
        end
        emit!(tool, result)
    elseif command in ("TRANSLATE", "CODONS", "PROTEIN")
        translation!(tool, command, name, a[2])
    elseif command == "ORFS"
        orfs!(tool, sequence, a[2])
    elseif command == "GC"
        emit!(tool, join(["$base=$(count(==(base), sequence))" for base in BASES], " "),
              "GC=$(pct(gc(sequence), n))%")
    elseif command == "GCWINDOW"
        width, step = a[2:3]
        width <= n || fail("window too large")
        for i in 1:step:(n-width+1)
            emit!(tool, "$i-$(i+width-1)",
                  "$(pct(gc(sequence[i:i+width-1]), width))%")
        end
    elseif command == "SKEW"
        values = [0]
        for base in sequence
            push!(values, values[end] + (base == 'G') - (base == 'C'))
        end
        for (label, extreme) in (("min", minimum(values)), ("max", maximum(values)))
            emit!(tool, label, extreme, "at",
                  join((i-1 for (i, v) in enumerate(values) if v == extreme), " "))
        end
    elseif command == "KMERS"
        width, limit = a[2:3]
        width <= n || fail("k too large")
        table = Dict{String, Int}()
        for i in 1:(n-width+1)
            word = sequence[i:i+width-1]
            table[word] = get(table, word, 0) + 1
        end
        emit!(tool, n-width+1, "windows", length(table), "distinct")
        for word in frequency_order(table)[1:min(limit, length(table))]
            emit!(tool, word, table[word])
        end
    elseif command == "FIND"
        emit_list!(tool, "forward", occurrences(sequence, a[2]))
        emit_list!(tool, "reverse", occurrences(sequence, revcomp(a[2])))
    elseif command == "RESTRICT"
        restrict!(tool, sequence, String[a[2:end]...])
    elseif command == "PALINDROMES"
        minimum, maximum = a[2:3]
        minimum <= maximum || fail("invalid range")
        found = false
        for position in 1:n, width in minimum:min(maximum, n-position+1)
            part = sequence[position:position+width-1]
            if part == revcomp(part)
                emit!(tool, position, width, part)
                found = true
            end
        end
        !found && emit!(tool, "none")
    elseif command == "REPEATS"
        repeats!(tool, sequence, a[2], a[3], a[4])
    elseif command == "HAMMING"
        other = tool.sequences[a[2]]
        length(other) == n || fail("length mismatch")
        distance = count(i -> sequence[i] != other[i], 1:n)
        transitions = count(i -> transition(sequence[i], other[i]), 1:n)
        emit!(tool, "distance", distance, "transitions", transitions,
              "transversions", distance - transitions)
    elseif command == "ALIGN"
        align!(tool, sequence, tool.sequences[a[2]], a[3], a[4], a[5], a[6])
    elseif command == "CONSENSUS"
        consensus!(tool, String[tool.sequences[key] for key in a])
    elseif command == "TM"
        emit!(tool, "Tm", fixed(temperature(sequence), 1), n < 14 ? "wallace" : "gc")
    elseif command == "MASS"
        single = strand_mass(sequence)
        emit!(tool, "ss", fixed(single, 3),
              "ds", fixed(single + strand_mass(revcomp(sequence)), 3))
    elseif command == "PRIMER"
        primer!(tool, sequence)
    elseif command == "FOLD"
        fold!(tool, sequence, a[2])
    elseif command == "PACK"
        codes = [findfirst(==(base), BASES) - 1 for base in sequence]
        append!(codes, fill(0, mod(-n, 4)))
        encoded = join(@sprintf("%02X",
                       64*codes[i]+16*codes[i+1]+4*codes[i+2]+codes[i+3])
                       for i in 1:4:length(codes))
        emit!(tool, n, encoded)
    end
end

function execute!(tool::Toolkit, line::String)
    fields = String.(split(line, ' '))
    command = first(fields)
    try
        args = validate(tool, command, fields[2:end])
        run_command!(tool, command, args)
    catch error
        if error isa CommandError
            emit!(tool, "ERROR", error.message)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    toolkit = Toolkit()
    for _ in 1:count
        execute!(toolkit, readline(stdin))
    end
    println(join(toolkit.output, "\n"))
end

main()
