include("scoring.jl")
include("substitution.jl")
include("transposition.jl")
include("playfair.jl")
include("analysis.jl")

const COMMANDS = ["ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"]
const CIPHERS = Set(["caesar", "affine", "vigenere", "autokey",
    "railfence", "columnar", "playfair"])
const SUBSTITUTIONS = Set(["caesar", "affine", "vigenere", "autokey"])
const MULTIPLIERS = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25]

struct JobFault <: Exception
    message::String
end

Base.showerror(io::IO, fault::JobFault) = print(io, fault.message)

struct Candidate
    key::String
    plain::String
    score::Int
    order::Int
end

struct BreakOutcome
    ranked::Vector{Candidate}
    choice::Candidate
    length::Int
    method::String
    passes::Int
    changes::Int
    kasiski::Union{Nothing,Analysis.KasiskiData}
end

BreakOutcome(ranked::Vector{Candidate}, choice::Candidate) =
    BreakOutcome(ranked, choice, 0, "", 0, 0, nothing)

mutable struct Benchmark
    messages::Dict{String, Vector{String}}
    totals::Dict{String, Vector{Int}}
    results::Vector{String}
    candidates::Vector{String}
    analysis::Vector{String}
    mono::Vector{Int}
    bi::Vector{Vector{Int}}
end

function Benchmark()
    mono, bi = Scoring.readweights("input/weights.txt")
    totals = Dict(command => [0, 0] for command in COMMANDS)
    benchmark = Benchmark(Dict{String, Vector{String}}(), totals,
        String[], String[], String[], mono, bi)
    loadmessages!(benchmark, "input/messages.txt")
    return benchmark
end

fail(message::AbstractString) = throw(JobFault(String(message)))

validname(text::AbstractString) = occursin(r"^[a-z0-9_]{1,16}$", text)

function digits(text::AbstractString, maximum::Int)
    return 1 <= length(text) <= maximum && occursin(r"^[0-9]+$", text)
end

function loadmessages!(benchmark::Benchmark, path::String)
    current = nothing
    bodylines = String[]
    for line in readlines(path)
        if isnothing(current)
            if !isempty(line)
                current = line[9:end]
                bodylines = String[]
            end
        elseif line == "END"
            benchmark.messages[current] = bodylines
            current = nothing
        else
            push!(bodylines, line)
        end
    end
end

body(benchmark::Benchmark, name::String) =
    join(benchmark.messages[name], "\n")

letters(benchmark::Benchmark, name::String) =
    Scoring.letters(body(benchmark, name))

function normalizekey(cipher::String, raw::String)
    if cipher == "caesar"
        (!digits(raw, 2) || parse(Int, raw) > 25) && fail("bad key $raw")
        return string(parse(Int, raw))
    elseif cipher == "affine"
        parts = split(raw, ','; keepempty=true)
        (length(parts) != 2 || !digits(parts[1], 2)
            || !digits(parts[2], 2)) && fail("bad key $raw")
        a, b = parse(Int, parts[1]), parse(Int, parts[2])
        (a ∉ MULTIPLIERS || b > 25) && fail("bad key $raw")
        return "$a,$b"
    elseif cipher == "railfence"
        !digits(raw, 2) && fail("bad key $raw")
        rails = parse(Int, raw)
        !(2 <= rails <= 20) && fail("bad key $raw")
        return string(rails)
    end
    valid = if cipher == "columnar"
        occursin(r"^[A-Za-z0-9]{2,9}$", raw)
    elseif cipher == "playfair"
        occursin(r"^[A-Za-z]{1,25}$", raw)
    else
        occursin(r"^[A-Za-z]{1,20}$", raw)
    end
    !valid && fail("bad key $raw")
    key = uppercase(raw)
    return cipher == "playfair" ? replace(key, 'J' => 'I') : key
end

function optionrules(command::String, cipher::String)
    rules = Dict{String, NTuple{3, Int}}()
    if command == "ANALYZE"
        rules["MAXLEN"] = (2, 20, 10)
    end
    command != "BREAK" && return rules
    rules["TOP"] = (1, 20, 5)
    if cipher == "vigenere"
        rules["MAXLEN"] = (2, 20, 10)
        rules["IOC"] = (1, 100000, 6000)
        rules["KASISKI"] = (1, 100, 60)
        rules["REFINE"] = (0, 10, 5)
    elseif cipher == "autokey"
        rules["MAXLEN"] = (1, 20, 8)
    elseif cipher == "railfence"
        rules["MAXRAILS"] = (2, 20, 10)
    elseif cipher == "columnar"
        rules["MAXLEN"] = (2, 6, 6)
    end
    return rules
end

function parseoptions(command::String, cipher::String, words::Vector{String})
    rules = optionrules(command, cipher)
    options = Dict{String, Any}(name => rule[3] for (name, rule) in rules)
    seen = Set{String}()
    for word in words
        equal = findfirst(==('='), word)
        name = isnothing(equal) ? "" : word[1:equal - 1]
        value = isnothing(equal) ? "" : word[equal + 1:end]
        (isnothing(equal) || name ∈ seen) && fail("bad option $word")
        push!(seen, name)
        if name == "KEYS" && (command == "IDENTIFY"
            || command == "BREAK" && cipher == "playfair")
            !validname(value) && fail("bad option $word")
            options[name] = value
            continue
        end
        bounds = get(rules, name, nothing)
        (isnothing(bounds) || !digits(value, 6)) && fail("bad option $word")
        number = parse(Int, value)
        !(bounds[1] <= number <= bounds[2]) && fail("bad option $word")
        options[name] = number
    end
    if command == "BREAK" && cipher == "playfair" && !haskey(options, "KEYS")
        fail("missing option KEYS")
    end
    return options
end

function decrypt(text::String, cipher::String, key::String)
    if cipher ∈ SUBSTITUTIONS
        return Scoring.letters(Substitution.apply(text, cipher, key, false))
    elseif cipher == "railfence"
        return Transposition.railfence(text, parse(Int, key), false)
    elseif cipher == "columnar"
        return Transposition.columnar(text, key, false)
    end
    return Playfair.apply(text, key, false)
end

function transform(text::String, cipher::String, key::String, encrypt::Bool)
    if cipher ∈ SUBSTITUTIONS
        return Substitution.apply(text, cipher, key, encrypt)
    end
    input = Scoring.letters(text)
    if cipher == "railfence"
        return Transposition.railfence(input, parse(Int, key), encrypt)
    elseif cipher == "columnar"
        return Transposition.columnar(input, key, encrypt)
    end
    return Playfair.apply(input, key, encrypt)
end

function keylist(benchmark::Benchmark, name::String)
    keys, seen = String[], Set{String}()
    for matched in eachmatch(r"[A-Za-z]+", body(benchmark, name))
        key = replace(uppercase(matched.match), 'J' => 'I')
        if key ∉ seen
            push!(keys, key)
            push!(seen, key)
        end
    end
    return keys
end

function permutations(length::Int)
    digits = [Char(Int('0') + i) for i in 1:length]
    result = String[]
    function visit(index::Int)
        if index > length
            push!(result, join(digits))
            return
        end
        for i in index:length
            digits[index], digits[i] = digits[i], digits[index]
            visit(index + 1)
            digits[index], digits[i] = digits[i], digits[index]
        end
    end
    visit(1)
    return sort!(result)
end

function columnkey(benchmark::Benchmark, text::String,
    length::Int, autokey::Bool)
    key = Char[]
    for position in 0:(length - 1)
        segment = Analysis.column(text, length, position)
        best, high = 0, typemin(Int)
        for guess in 0:25
            score = if !autokey
                plain = Substitution.apply(segment, "caesar", string(guess), false)
                Scoring.monogram(plain, benchmark.mono)
            else
                previous, total = guess, 0
                for c in segment
                    previous = mod(Scoring.value(c) - previous, 26)
                    total += benchmark.mono[previous + 1]
                end
                total
            end
            if score > high
                best, high = guess, score
            end
        end
        push!(key, Scoring.upper(best))
    end
    return join(key)
end

function candidatekeys(benchmark::Benchmark, cipher::String,
    text::String, options::Dict{String, Any}, keys::Vector{String})
    result = String[]
    if cipher == "caesar"
        append!(result, string.(0:25))
    elseif cipher == "affine"
        for a in MULTIPLIERS, b in 0:25
            push!(result, "$a,$b")
        end
    elseif cipher == "railfence"
        append!(result, string.(2:options["MAXRAILS"]))
    elseif cipher == "columnar"
        for length in 2:options["MAXLEN"]
            append!(result, permutations(length))
        end
    elseif cipher == "playfair"
        append!(result, keys)
    else
        for length in 1:options["MAXLEN"]
            push!(result, columnkey(benchmark, text, length, cipher == "autokey"))
        end
    end
    return result
end

function score(benchmark::Benchmark, cipher::String, plaintext::String)
    if cipher == "caesar" || cipher == "affine"
        return Scoring.monogram(plaintext, benchmark.mono)
    end
    return Scoring.bigram(plaintext, benchmark.bi)
end

function breakcipher(benchmark::Benchmark, cipher::String,
    text::String, options::Dict{String, Any}, keys::Vector{String}=String[])
    candidates = Candidate[]
    for key in candidatekeys(benchmark, cipher, text, options, keys)
        plain = decrypt(text, cipher, key)
        push!(candidates, Candidate(key, plain, score(benchmark, cipher, plain),
            length(candidates) + 1))
    end
    ranked = sort(candidates, by=item -> (-item.score, item.order))
    if cipher != "vigenere"
        return BreakOutcome(ranked, first(ranked))
    end

    maxlen, threshold = options["MAXLEN"], options["IOC"]
    kasiski = Analysis.kasiski(text)
    averages = [Analysis.averageioc(text, length) for length in 1:maxlen]
    kasiskilength = 0
    for length in 2:maxlen
        if !isempty(kasiski.gaps) && 100 * Analysis.kasiskicount(kasiski, length) >=
            options["KASISKI"] * Base.length(kasiski.gaps)
            kasiskilength = length
        end
    end
    chosen, method = 0, ""
    if kasiskilength != 0 && averages[kasiskilength] >= threshold
        chosen, method = kasiskilength, "kasiski"
    else
        found = findfirst(average -> average >= threshold, averages)
        if !isnothing(found)
            chosen, method = found, "ioc"
        else
            chosen, method = argmax(averages), "maxioc"
        end
    end

    key = candidates[chosen].key
    reference = score(benchmark, cipher, decrypt(text, cipher, key))
    passes, changes = 0, 0
    for _ in 1:options["REFINE"]
        passes += 1
        changed = 0
        for position in 1:length(key)
            winner, high = key[position], reference
            for value in 0:25
                chars = collect(key)
                chars[position] = Scoring.upper(value)
                trial = join(chars)
                measured = score(benchmark, cipher, decrypt(text, cipher, trial))
                if measured > high
                    high, winner = measured, Scoring.upper(value)
                end
            end
            if high > reference
                chars = collect(key)
                chars[position] = winner
                key = join(chars)
                reference = high
                changes += 1
                changed += 1
            end
        end
        changed == 0 && break
    end
    choice = Candidate(key, decrypt(text, cipher, key), reference, -1)
    return BreakOutcome(ranked, choice, chosen, method, passes, changes, kasiski)
end

function candidatereport!(benchmark::Benchmark, job::Int, cipher::String,
    source::String, broken::BreakOutcome, top::Int)
    ranked = broken.ranked
    margin = length(ranked) >= 2 ? ranked[1].score - ranked[2].score : 0
    push!(benchmark.candidates,
        "JOB $job BREAK $cipher source=$source tried=$(length(ranked)) margin=$margin")
    for index in 1:min(top, length(ranked))
        candidate = ranked[index]
        preview = join(Iterators.take(candidate.plain, 40))
        push!(benchmark.candidates,
            "$index $(candidate.key) $(candidate.score) $preview")
    end
end

function breakanalysis!(benchmark::Benchmark, job::Int,
    cipher::String, source::String, text::String,
    options::Dict{String, Any}, broken::BreakOutcome)
    if cipher == "vigenere"
        push!(benchmark.analysis,
            "JOB $job BREAK vigenere source=$source",
            "letters=$(length(text))")
        append!(benchmark.analysis,
            Analysis.periodtable(text, options["MAXLEN"], broken.kasiski))
        append!(benchmark.analysis, Analysis.kasiskitable(broken.kasiski))
        push!(benchmark.analysis,
            "decision length=$(broken.length) method=$(broken.method)",
            "refine passes=$(broken.passes) changes=$(broken.changes) key=$(broken.choice.key)")
    elseif cipher == "playfair"
        normalized = replace(text, 'J' => 'I')
        chars = collect(normalized)
        pairs = [join(chars[i:i + 1]) for i in 1:2:length(chars)]
        board = collect(Playfair.square(broken.choice.key))
        rows = [join(board[i:i + 4]) for i in 1:5:25]
        push!(benchmark.analysis,
            "JOB $job BREAK playfair source=$source",
            "letters=$(length(normalized))",
            "digraphs pairs=$(length(pairs)) distinct=$(length(unique(pairs)))",
            "top $(Analysis.toppairs(normalized, true))",
            "square $(join(rows, " "))")
    end
end

function outputtext(source::String, cipher::String,
    key::String, encrypt::Bool)
    converted = transform(source, cipher, key, encrypt)
    if cipher ∈ SUBSTITUTIONS
        return String.(split(converted, '\n'; keepempty=true))
    end
    return Scoring.groups(converted)
end

function save!(benchmark::Benchmark, target::Union{Nothing,String}, lines::Vector{String})
    if !isnothing(target)
        benchmark.messages[target] = copy(lines)
    end
end

function cipherjob!(benchmark::Benchmark, job::Int, command::String,
    cipher::String, key::String, source::String, target::Union{Nothing,String})
    text = letters(benchmark, source)
    isempty(text) && fail("no letters")
    if command == "DECRYPT" && cipher == "playfair" && !Playfair.valid(text)
        fail("bad playfair text")
    end
    lines = outputtext(body(benchmark, source), cipher, key, command == "ENCRYPT")
    count = sum(length(Scoring.letters(line)) for line in lines)
    header = "JOB $job $command $cipher key=$key source=$source letters=$count lines=$(length(lines))"
    !isnothing(target) && (header *= " as=$target")
    push!(benchmark.results, header)
    append!(benchmark.results, lines)
    save!(benchmark, target, lines)
end

function breakjob!(benchmark::Benchmark, job::Int, cipher::String,
    source::String, target::Union{Nothing,String}, options::Dict{String, Any})
    text = letters(benchmark, source)
    length(text) < 40 && fail("text too short")
    if cipher == "playfair" && !Playfair.valid(text)
        fail("bad playfair text")
    end
    keys = cipher == "playfair" ? keylist(benchmark, options["KEYS"]) : String[]
    cipher == "playfair" && isempty(keys) && fail("empty key list")
    broken = breakcipher(benchmark, cipher, text, options, keys)
    winner = broken.choice
    lines = outputtext(body(benchmark, source), cipher, winner.key, false)
    header = "JOB $job BREAK $cipher source=$source key=$(winner.key) score=$(winner.score) lines=$(length(lines))"
    !isnothing(target) && (header *= " as=$target")
    push!(benchmark.results, header)
    append!(benchmark.results, lines)
    candidatereport!(benchmark, job, cipher, source, broken, options["TOP"])
    breakanalysis!(benchmark, job, cipher, source, text, options, broken)
    save!(benchmark, target, lines)
end

function analyzejob!(benchmark::Benchmark, job::Int,
    source::String, options::Dict{String, Any})
    text = letters(benchmark, source)
    length(text) < 40 && fail("text too short")
    push!(benchmark.results,
        "JOB $job ANALYZE source=$source letters=$(length(text))")
    append!(benchmark.analysis,
        Analysis.report(job, source, text, benchmark.mono, benchmark.bi, options["MAXLEN"]))
end

function comparejob!(benchmark::Benchmark, job::Int, a::String, b::String)
    first, second = letters(benchmark, a), letters(benchmark, b)
    left, right = collect(first), collect(second)
    count = min(length(left), length(right))
    position, mismatches = count + 1, 0
    for i in 1:count
        if left[i] != right[i]
            mismatches == 0 && (position = i)
            mismatches += 1
        end
    end
    if first == second
        push!(benchmark.results,
            "JOB $job COMPARE $a $b equal letters=$(length(first))")
    else
        push!(benchmark.results,
            "JOB $job COMPARE $a $b differ letters=$(length(first)),$(length(second)) first=$position mismatches=$mismatches")
    end
end

function identifyjob!(benchmark::Benchmark, job::Int,
    source::String, options::Dict{String, Any})
    text = letters(benchmark, source)
    length(text) < 40 && fail("text too short")
    coincidence = Analysis.ioc(text)
    average = Scoring.monogram(text, benchmark.mono) ÷ length(text)
    distinct = count(x -> x > 0, Analysis.frequency(text))
    shape = !occursin('J', text) && Playfair.valid(text)
    family = if shape
        "playfair"
    elseif coincidence >= 5500 && average >= 44
        "transposition"
    elseif coincidence >= 5500
        "monoalphabetic"
    else
        "polyalphabetic"
    end
    keys = family == "playfair" && haskey(options, "KEYS") ?
        keylist(benchmark, options["KEYS"]) : nothing
    family == "playfair" && !isnothing(keys) && isempty(keys) && fail("empty key list")
    ciphers = if family == "transposition"
        ["railfence", "columnar"]
    elseif family == "monoalphabetic"
        ["affine"]
    elseif family == "polyalphabetic"
        ["vigenere", "autokey"]
    else
        isnothing(keys) ? String[] : ["playfair"]
    end
    tested = Pair{String,Candidate}[]
    winner = nothing
    chosen = ""
    for cipher in ciphers
        raw = cipher == "playfair" ? ["KEYS=$(options["KEYS"])"] : String[]
        defaults = parseoptions("BREAK", cipher, raw)
        trial = breakcipher(benchmark, cipher, text, defaults,
            isnothing(keys) ? String[] : keys).choice
        push!(tested, cipher => trial)
        if isnothing(winner) || trial.score > winner.score
            winner, chosen = trial, cipher
        end
    end

    header = "JOB $job IDENTIFY source=$source family=$family"
    reported = chosen
    if isnothing(winner)
        push!(benchmark.results, header)
    else
        key = winner.key
        if reported == "affine" && startswith(key, "1,")
            reported, key = "caesar", split(key, ',')[2]
        end
        lines = outputtext(body(benchmark, source), reported, key, false)
        push!(benchmark.results,
            header * " cipher=$reported key=$key score=$(winner.score) lines=$(length(lines))")
        append!(benchmark.results, lines)
    end
    push!(benchmark.analysis,
        "JOB $job IDENTIFY source=$source",
        "letters=$(length(text)) ioc=$coincidence mono_avg=$average distinct=$distinct shape=$(shape ? "yes" : "no")",
        "family=$family")
    for (cipher, result) in tested
        push!(benchmark.analysis,
            "try $cipher key=$(result.key) score=$(result.score)")
    end
    !isnothing(winner) && push!(benchmark.analysis, "choice $reported")
end

function checkreferences(benchmark::Benchmark, words::Vector{String},
    command::String, options::Dict{String, Any})
    source = if command == "ENCRYPT" || command == "DECRYPT"
        words[4]
    elseif command == "BREAK"
        words[3]
    else
        words[2]
    end
    !haskey(benchmark.messages, source) && fail("unknown message $source")
    if haskey(options, "KEYS") && !haskey(benchmark.messages, options["KEYS"])
        fail("unknown message $(options["KEYS"])")
    end
    if command == "COMPARE" && !haskey(benchmark.messages, words[3])
        fail("unknown message $(words[3])")
    end
end

function execute!(benchmark::Benchmark, job::Int, line::String)
    words = String.(split(line, ' '; keepempty=true))
    command = words[1]
    command ∉ COMMANDS && fail("unknown command")
    target = nothing
    if command ∈ ("ENCRYPT", "DECRYPT", "BREAK") && length(words) >= 5
        if words[end - 1] == "AS"
            target = pop!(words)
            pop!(words)
            !validname(target) && fail("bad syntax")
        end
    end
    valid = if command == "ENCRYPT" || command == "DECRYPT"
        length(words) == 4
    elseif command == "BREAK"
        length(words) >= 3
    elseif command == "ANALYZE" || command == "IDENTIFY"
        length(words) ∈ (2, 3)
    else
        length(words) == 3
    end
    !valid && fail("bad syntax")
    cipher = command ∈ ("ENCRYPT", "DECRYPT", "BREAK") ? words[2] : ""
    !isempty(cipher) && cipher ∉ CIPHERS && fail("unknown cipher $cipher")
    key = command ∈ ("ENCRYPT", "DECRYPT") ? normalizekey(cipher, words[3]) : ""
    optionwords = if command == "BREAK"
        words[4:end]
    elseif command == "ANALYZE" || command == "IDENTIFY"
        words[3:end]
    else
        String[]
    end
    options = parseoptions(command, cipher, optionwords)
    checkreferences(benchmark, words, command, options)
    !isnothing(target) && haskey(benchmark.messages, target) &&
        fail("duplicate message $target")
    if command == "ENCRYPT" || command == "DECRYPT"
        cipherjob!(benchmark, job, command, cipher, key, words[4], target)
    elseif command == "BREAK"
        breakjob!(benchmark, job, cipher, words[3], target, options)
    elseif command == "ANALYZE"
        analyzejob!(benchmark, job, words[2], options)
    elseif command == "COMPARE"
        comparejob!(benchmark, job, words[2], words[3])
    elseif command == "IDENTIFY"
        identifyjob!(benchmark, job, words[2], options)
    end
end

function runjobs!(benchmark::Benchmark, path::String)
    jobs, successful, errors = 0, 0, 0
    for line in readlines(path)
        if isempty(line) || startswith(line, "#")
            continue
        end
        jobs += 1
        command = String(first(split(line, ' ')))
        try
            execute!(benchmark, jobs, line)
            successful += 1
            haskey(benchmark.totals, command) && (benchmark.totals[command][1] += 1)
        catch fault
            if !(fault isa JobFault)
                rethrow()
            end
            errors += 1
            haskey(benchmark.totals, command) && (benchmark.totals[command][2] += 1)
            push!(benchmark.results, "JOB $jobs ERROR $(fault.message)")
        end
    end
    for command in COMMANDS
        counts = benchmark.totals[command]
        push!(benchmark.results, "TOTAL $command ok=$(counts[1]) errors=$(counts[2])")
    end
    push!(benchmark.results,
        "SUMMARY jobs=$jobs ok=$successful errors=$errors messages=$(length(benchmark.messages))")
end

function writefile(name::String, lines::Vector{String})
    open(joinpath("output", name), "w") do file
        if !isempty(lines)
            write(file, join(lines, "\n") * "\n")
        end
    end
end

function main()
    benchmark = Benchmark()
    runjobs!(benchmark, "input/jobs.txt")
    mkpath("output")
    writefile("results.txt", benchmark.results)
    writefile("candidates.txt", benchmark.candidates)
    writefile("analysis.txt", benchmark.analysis)
end

main()
