const ADJACENT_KEYS = Dict(
    'a' => "qswz", 'b' => "ghnv", 'c' => "dfvx", 'd' => "cefrsx", 'e' => "drsw",
    'f' => "cdgrtv", 'g' => "bfhtvy", 'h' => "bgjnuy", 'i' => "jkou", 'j' => "hikmnu",
    'k' => "ijlmo", 'l' => "kop", 'm' => "jkn", 'n' => "bhjm", 'o' => "iklp",
    'p' => "lo", 'q' => "aw", 'r' => "deft", 's' => "adewxz", 't' => "fgry",
    'u' => "hijy", 'v' => "bcfg", 'w' => "aeqs", 'x' => "cdsz", 'y' => "ghtu",
    'z' => "asx",
)
const SOUNDEX_GROUPS = (
    "bfpv" => '1', "cgjkqsxz" => '2', "dt" => '3', "l" => '4',
    "mn" => '5', "r" => '6', "aeiouy" => '0',
)
const SOUNDEX_DIGITS = Dict(
    letter => digit for (letters, digit) in SOUNDEX_GROUPS for letter in letters
)
const SENTENCE_MARKS = ".!?"
const FINDING_KINDS = (:unknown, :case, :capital, :repeats)
const COUNTER_NAMES = (:checked, :unknown, :case, :capital, :repeats, :corrected)
const OPTION_MAXIMUMS = Dict("LIMIT" => 3, "SUGGESTIONS" => 10)
const KEYBOARD_MODES = ("ON", "OFF")
const MAX_WORD_LENGTH = 30
const MAX_FREQUENCY = 1000000
const MAX_LISTED = 20
const REPORT_SIZE = 10

struct CommandError <: Exception
    message::String
end

function word_argument(text)
    occursin(r"^[A-Za-z]{1,30}$", text) || throw(CommandError("BAD WORD $text"))
    return lowercase(text)
end

function number_argument(text, lower, upper)
    occursin(r"^[0-9]{1,7}$", text) || throw(CommandError("BAD NUMBER $text"))
    value = parse(Int, text)
    lower <= value <= upper || throw(CommandError("BAD NUMBER $text"))
    return value
end

function decimal_text(numerator, denominator, digits)
    scale = 10^digits
    value = div(2 * numerator * scale + denominator, 2 * denominator)
    return "$(div(value, scale)).$(lpad(value % scale, digits, '0'))"
end

frequency_key((key, count)) = (-count, key)

emit(parts...) = println(join(parts, " "))

function apply_case(token_text, word)
    if length(token_text) >= 2 && all(isuppercase, token_text)
        return uppercase(word)
    elseif isuppercase(token_text[1])
        return uppercasefirst(word)
    end
    return word
end

struct Token
    number::Int
    text::String
    word::String
    stop::Int
    gap::String
    sentence_start::Bool
    repeat::Bool
end

is_mixed_case(token::Token) =
    any(isuppercase, token.text[2:end]) && !all(isuppercase, token.text)

function tokenize(text)
    tokens = Token[]
    position = 1
    for token_match in eachmatch(r"[A-Za-z]+", text)
        token_text = String(token_match.match)
        word = lowercase(token_text)
        gap = text[position:token_match.offset-1]
        is_sentence_start = isempty(tokens) || any(in(SENTENCE_MARKS), gap)
        is_repeat = !isempty(tokens) && word == tokens[end].word && all(==(' '), gap)
        stop = token_match.offset + length(token_text) - 1
        token = Token(
            length(tokens) + 1, token_text, word, stop, gap, is_sentence_start, is_repeat,
        )
        push!(tokens, token)
        position = stop + 1
    end
    return tokens
end

gap_cost(keyboard) = keyboard ? 2 : 1

function substitution_cost(x, y, keyboard)
    x == y && return 0
    keyboard || return 1
    return y in ADJACENT_KEYS[x] ? 1 : 2
end

is_swap(a, b, i, j) = i >= 2 && j >= 2 && a[i] == b[j-1] && a[i-1] == b[j]

function distance_table(a, b, keyboard)
    gap = gap_cost(keyboard)
    rows, columns = length(a), length(b)
    table = zeros(Int, rows + 1, columns + 1)
    table[:, 1] .= (0:rows) .* gap
    table[1, :] .= (0:columns) .* gap
    for i in 1:rows, j in 1:columns
        best = min(
            table[i, j+1] + gap,
            table[i+1, j] + gap,
            table[i, j] + substitution_cost(a[i], b[j], keyboard),
        )
        if is_swap(a, b, i, j)
            best = min(best, table[i-1, j-1] + 1)
        end
        table[i+1, j+1] = best
    end
    return table
end

edit_distance(a, b, keyboard) = distance_table(a, b, keyboard)[end, end]

prefix_distance(word, other, keyboard) = minimum(distance_table(word, other, keyboard)[end, :])

function edit_operations(a, b, keyboard)
    table = distance_table(a, b, keyboard)
    gap = gap_cost(keyboard)
    operations = String[]
    i, j = length(a), length(b)
    while i > 0 || j > 0
        if i >= 1 && j >= 1 &&
           table[i+1, j+1] == table[i, j] + substitution_cost(a[i], b[j], keyboard)
            if a[i] != b[j]
                push!(operations, "sub:$(a[i])>$(b[j])")
            end
            i, j = i - 1, j - 1
        elseif is_swap(a, b, i, j) && table[i+1, j+1] == table[i-1, j-1] + 1
            push!(operations, "swap:$(a[i-1])$(a[i])")
            i, j = i - 2, j - 2
        elseif i >= 1 && table[i+1, j+1] == table[i, j+1] + gap
            push!(operations, "del:$(a[i])")
            i -= 1
        else
            push!(operations, "ins:$(b[j])")
            j -= 1
        end
    end
    return table[end, end], reverse(operations)
end

function soundex(word)
    code = string(uppercase(word[1]))
    previous = word[1] in "hw" ? '0' : SOUNDEX_DIGITS[word[1]]
    for letter in word[2:end]
        letter in "hw" && continue
        digit = SOUNDEX_DIGITS[letter]
        if digit != '0' && digit != previous
            code *= digit
        end
        previous = digit
    end
    return first(code * "000", 4)
end

function segment(word, dictionary)
    len = length(word)
    ways = zeros(Int, len + 1)
    best = Vector{Union{Nothing,Vector{String}}}(nothing, len + 1)
    ways[len+1] = 1
    best[len+1] = String[]
    for start in len:-1:1
        for stop in start:len
            piece = word[start:stop]
            (haskey(dictionary, piece) && ways[stop+1] > 0) || continue
            ways[start] += ways[stop+1]
            candidate = [piece; best[stop+1]]
            current = best[start]
            if current === nothing || (length(candidate), candidate) < (length(current), current)
                best[start] = candidate
            end
        end
    end
    return ways[1], best[1]
end

struct UndoRecord
    name::String
    dictionary::Dict{String,Int}
    ignored::Set{String}
    rules::Dict{String,String}
end

mutable struct SpellChecker
    dictionary::Dict{String,Int}
    ignored::Set{String}
    rules::Dict{String,String}
    keyboard::Bool
    base_limit::Int
    suggestion_count::Int
    undo_history::Vector{UndoRecord}
    unknown_log::Dict{String,Int}
    correction_log::Dict{Tuple{String,String},Int}
    counters::Dict{Symbol,Int}
end

SpellChecker(dictionary) = SpellChecker(
    dictionary, Set{String}(), Dict{String,String}(), false, 2, 5, UndoRecord[],
    Dict{String,Int}(), Dict{Tuple{String,String},Int}(),
    Dict(name => 0 for name in COUNTER_NAMES),
)

limit(checker) = checker.keyboard ? 2 * checker.base_limit : checker.base_limit

is_known(checker, word) = haskey(checker.dictionary, word) || word in checker.ignored

frequency_order(checker) = first.(sort!(collect(checker.dictionary), by = frequency_key))

function require_entry(checker, word)
    haskey(checker.dictionary, word) || throw(CommandError("NOT FOUND $word"))
    return checker.dictionary[word]
end

function candidates(checker, word)
    max_distance = limit(checker)
    gap = gap_cost(checker.keyboard)
    found = Tuple{Int,Int,String}[]
    for (other, frequency) in checker.dictionary
        if other == word || abs(length(other) - length(word)) * gap > max_distance
            continue
        end
        distance = edit_distance(word, other, checker.keyboard)
        if distance <= max_distance
            push!(found, (distance, -frequency, other))
        end
    end
    sort!(found)
    return [(other, distance) for (distance, _, other) in found]
end

function correction(checker, word)
    is_known(checker, word) && return nothing
    haskey(checker.rules, word) && return checker.rules[word]
    found = candidates(checker, word)
    return isempty(found) ? nothing : found[1][1]
end

function record_undo!(checker, name)
    record = UndoRecord(
        name, copy(checker.dictionary), copy(checker.ignored), copy(checker.rules),
    )
    push!(checker.undo_history, record)
end

function log_correction!(checker, word, replacement)
    key = (word, replacement)
    checker.correction_log[key] = get(checker.correction_log, key, 0) + 1
    checker.counters[:corrected] += 1
end

function unknown_finding(checker, token)
    label = "UNKNOWN $(token.number) $(token.text)"
    haskey(checker.rules, token.word) && return "$label RULE $(checker.rules[token.word])"
    found = candidates(checker, token.word)
    isempty(found) && return "$label NONE"
    words = [other for (other, _) in first(found, checker.suggestion_count)]
    return join([label, "SUGGEST", words...], " ")
end

function check!(checker, text)
    tokens = tokenize(text)
    findings = Pair{Symbol,String}[]
    for token in tokens
        if !is_known(checker, token.word)
            push!(findings, :unknown => unknown_finding(checker, token))
            checker.unknown_log[token.word] = get(checker.unknown_log, token.word, 0) + 1
        end
        if is_mixed_case(token)
            push!(findings, :case => "CASE $(token.number) $(token.text)")
        end
        if token.sentence_start && islowercase(token.text[1])
            push!(findings, :capital => "CAPITAL $(token.number) $(token.text)")
        end
        if token.repeat
            push!(findings, :repeats => "REPEAT $(token.number) $(token.text)")
        end
    end
    counts = Dict(
        kind => count(finding -> finding.first == kind, findings) for kind in FINDING_KINDS
    )
    checker.counters[:checked] += length(tokens)
    for kind in FINDING_KINDS
        checker.counters[kind] += counts[kind]
    end
    emit(
        "CHECK", "words=$(length(tokens))",
        ("$kind=$(counts[kind])" for kind in FINDING_KINDS)...,
    )
    for finding in findings
        emit(finding.second)
    end
end

function correct!(checker, text)
    pieces = String[]
    position = 0
    changed = 0
    for token in tokenize(text)
        replacement = correction(checker, token.word)
        if replacement === nothing
            push!(pieces, token.gap * token.text)
        else
            push!(pieces, token.gap * apply_case(token.text, replacement))
            log_correction!(checker, token.word, replacement)
            changed += 1
        end
        position = token.stop
    end
    push!(pieces, text[position+1:end])
    emit("CORRECT changed=$changed:", join(pieces))
end

function fix!(checker, text)
    pieces = String[]
    position = 0
    removed = 0
    replaced = 0
    recased = 0
    for token in tokenize(text)
        position = token.stop
        if token.repeat
            removed += 1
            continue
        end
        replacement = correction(checker, token.word)
        result = apply_case(token.text, something(replacement, token.word))
        if token.sentence_start && islowercase(result[1])
            result = uppercasefirst(result)
        end
        if replacement !== nothing
            log_correction!(checker, token.word, replacement)
            replaced += 1
        elseif result != token.text
            recased += 1
        end
        push!(pieces, token.gap * result)
    end
    push!(pieces, text[position+1:end])
    emit("FIX", "removed=$removed", "replaced=$replaced", "recased=$recased:", join(pieces))
end

function profile(checker, text)
    tokens = tokenize(text)
    distinct = length(unique(token.word for token in tokens))
    unknown = count(token -> !is_known(checker, token.word), tokens)
    sentences = count(token -> token.sentence_start, tokens)
    if isempty(tokens)
        rate, average, longest = "0.0", "0.00", "-"
    else
        characters = sum(token -> length(token.text), tokens)
        rate = decimal_text(100 * unknown, length(tokens), 1)
        average = decimal_text(characters, length(tokens), 2)
        longest = argmax(token -> length(token.text), tokens).word
    end
    emit(
        "PROFILE", "words=$(length(tokens))", "distinct=$distinct", "unknown=$unknown",
        "rate=$rate", "avglen=$average", "longest=$longest", "sentences=$sentences",
    )
end

function learn!(checker, text)
    record_undo!(checker, "LEARN")
    updated = 0
    added = 0
    skipped = 0
    for token in tokenize(text)
        if length(token.word) > MAX_WORD_LENGTH
            skipped += 1
        elseif haskey(checker.dictionary, token.word)
            checker.dictionary[token.word] += 1
            updated += 1
        else
            checker.dictionary[token.word] = 1
            delete!(checker.ignored, token.word)
            added += 1
        end
    end
    emit("LEARN", "updated=$updated", "added=$added", "skipped=$skipped")
end

function suggest(checker, arguments)
    word = word_argument(arguments[1])
    if is_known(checker, word)
        emit("SUGGEST", word, "KNOWN")
    elseif haskey(checker.rules, word)
        emit("SUGGEST", word, "RULE", checker.rules[word])
    else
        found = candidates(checker, word)
        shown = first(found, checker.suggestion_count)
        emit(
            "SUGGEST", word, "found=$(length(found))",
            ("$other:$distance" for (other, distance) in shown)...,
        )
    end
end

function dist(checker, arguments)
    source = word_argument(arguments[1])
    target = word_argument(arguments[2])
    distance, operations = edit_operations(source, target, checker.keyboard)
    emit("DIST", source, target, distance, operations...)
end

function soundex_code(checker, arguments)
    word = word_argument(arguments[1])
    emit("SOUNDEX", word, soundex(word))
end

function sounds(checker, arguments)
    word = word_argument(arguments[1])
    code = soundex(word)
    matches = [
        other for other in frequency_order(checker) if other != word && soundex(other) == code
    ]
    emit("SOUNDS", word, code, "count=$(length(matches))", first(matches, REPORT_SIZE)...)
end

function split_word(checker, arguments)
    word = word_argument(arguments[1])
    ways, best = segment(word, checker.dictionary)
    if ways == 0
        emit("SPLIT", word, "ways=0", "->", "NONE")
    else
        emit("SPLIT", word, "ways=$ways", "->", best...)
    end
end

function prefix(checker, arguments)
    word = word_argument(arguments[1])
    shown = number_argument(arguments[2], 1, MAX_LISTED)
    matches = [other for other in frequency_order(checker) if startswith(other, word)]
    emit(
        "PREFIX", word, "count=$(length(matches))",
        ("$other:$(checker.dictionary[other])" for other in first(matches, shown))...,
    )
end

function complete(checker, arguments)
    word = word_argument(arguments[1])
    shown = number_argument(arguments[2], 1, MAX_LISTED)
    threshold = limit(checker) ÷ 2
    matches = Tuple{Int,Int,String}[]
    for (other, frequency) in checker.dictionary
        distance = prefix_distance(word, other, checker.keyboard)
        if distance <= threshold
            push!(matches, (distance, -frequency, other))
        end
    end
    sort!(matches)
    emit(
        "COMPLETE", word, "count=$(length(matches))",
        ("$other:$distance" for (distance, _, other) in first(matches, shown))...,
    )
end

function list_words(checker, arguments)
    word = word_argument(arguments[1])
    shown = number_argument(arguments[2], 1, MAX_LISTED)
    matches = sort([other for other in keys(checker.dictionary) if other >= word])
    emit(
        "LIST", word, "count=$(length(matches))",
        ("$other:$(checker.dictionary[other])" for other in first(matches, shown))...,
    )
end

function word_info(checker, arguments)
    word = word_argument(arguments[1])
    frequency = require_entry(checker, word)
    rank = findfirst(==(word), frequency_order(checker))
    emit(
        "WORD", word, "freq=$frequency", "rank=$rank", "soundex=$(soundex(word))",
        "neighbors=$(length(candidates(checker, word)))",
    )
end

function add!(checker, arguments)
    word = word_argument(arguments[1])
    frequency = number_argument(arguments[2], 1, MAX_FREQUENCY)
    haskey(checker.dictionary, word) && throw(CommandError("DUPLICATE $word"))
    record_undo!(checker, "ADD")
    checker.dictionary[word] = frequency
    delete!(checker.ignored, word)
    emit("ADD", word, frequency)
end

function remove!(checker, arguments)
    word = word_argument(arguments[1])
    frequency = require_entry(checker, word)
    record_undo!(checker, "REMOVE")
    delete!(checker.dictionary, word)
    emit("REMOVE", word, frequency)
end

function ignore!(checker, arguments)
    word = word_argument(arguments[1])
    haskey(checker.dictionary, word) && throw(CommandError("IN DICTIONARY $word"))
    word in checker.ignored && throw(CommandError("ALREADY IGNORED $word"))
    record_undo!(checker, "IGNORE")
    push!(checker.ignored, word)
    emit("IGNORE", word)
end

function unignore!(checker, arguments)
    word = word_argument(arguments[1])
    word in checker.ignored || throw(CommandError("NOT IGNORED $word"))
    record_undo!(checker, "UNIGNORE")
    delete!(checker.ignored, word)
    emit("UNIGNORE", word)
end

function rule!(checker, arguments)
    source = word_argument(arguments[1])
    target = word_argument(arguments[2])
    haskey(checker.dictionary, source) && throw(CommandError("IN DICTIONARY $source"))
    haskey(checker.dictionary, target) || throw(CommandError("NOT FOUND $target"))
    record_undo!(checker, "RULE")
    previous = get(checker.rules, source, nothing)
    checker.rules[source] = target
    if previous === nothing
        emit("RULE", source, target)
    else
        emit("RULE", source, target, "REPLACED", previous)
    end
end

function unrule!(checker, arguments)
    word = word_argument(arguments[1])
    haskey(checker.rules, word) || throw(CommandError("NO RULE $word"))
    record_undo!(checker, "UNRULE")
    target = pop!(checker.rules, word)
    emit("UNRULE", word, target)
end

function show_rules(checker, _)
    rules = sort(collect(checker.rules))
    emit("RULES", "count=$(length(rules))", ("$source>$target" for (source, target) in rules)...)
end

function keyboard_mode!(checker, arguments)
    mode = arguments[1]
    mode in KEYBOARD_MODES || throw(CommandError("BAD MODE $mode"))
    checker.keyboard = mode == "ON"
    emit("KEYBOARD", mode)
end

function set_option!(checker, arguments)
    option = arguments[1]
    haskey(OPTION_MAXIMUMS, option) || throw(CommandError("BAD OPTION $option"))
    value = number_argument(arguments[2], 1, OPTION_MAXIMUMS[option])
    if option == "LIMIT"
        checker.base_limit = value
    else
        checker.suggestion_count = value
    end
    emit("SET", option, value)
end

function undo!(checker, _)
    isempty(checker.undo_history) && throw(CommandError("NOTHING TO UNDO"))
    record = pop!(checker.undo_history)
    checker.dictionary = record.dictionary
    checker.ignored = record.ignored
    checker.rules = record.rules
    emit("UNDO", record.name)
end

function report(checker, _)
    entries = sort(collect(checker.unknown_log), by = frequency_key)
    emit(
        "REPORT", "distinct=$(length(entries))",
        ("$word:$tally" for (word, tally) in first(entries, REPORT_SIZE))...,
    )
end

function history(checker, _)
    entries = sort(collect(checker.correction_log), by = frequency_key)
    emit(
        "HISTORY", "distinct=$(length(entries))",
        (
            "$word>$replacement:$tally"
            for ((word, replacement), tally) in first(entries, REPORT_SIZE)
        )...,
    )
end

function stats(checker, _)
    top, top_frequency = argmin(frequency_key, checker.dictionary)
    characters = sum(length, keys(checker.dictionary))
    emit(
        "STATS", "words=$(length(checker.dictionary))",
        "total=$(sum(values(checker.dictionary)))",
        "avglen=$(decimal_text(characters, length(checker.dictionary), 2))",
        "top=$top:$top_frequency", "ignored=$(length(checker.ignored))",
        "rules=$(length(checker.rules))", "keyboard=$(checker.keyboard ? "ON" : "OFF")",
        "limit=$(limit(checker))", "suggestions=$(checker.suggestion_count)",
        "undo=$(length(checker.undo_history))",
    )
    emit("SESSION", ("$name=$(checker.counters[name])" for name in COUNTER_NAMES)...)
end

const HANDLERS = Dict(
    "CHECK" => (nothing, check!),
    "CORRECT" => (nothing, correct!),
    "FIX" => (nothing, fix!),
    "PROFILE" => (nothing, profile),
    "LEARN" => (nothing, learn!),
    "SUGGEST" => (1, suggest),
    "DIST" => (2, dist),
    "SOUNDEX" => (1, soundex_code),
    "SOUNDS" => (1, sounds),
    "SPLIT" => (1, split_word),
    "PREFIX" => (2, prefix),
    "COMPLETE" => (2, complete),
    "LIST" => (2, list_words),
    "WORD" => (1, word_info),
    "ADD" => (2, add!),
    "REMOVE" => (1, remove!),
    "IGNORE" => (1, ignore!),
    "UNIGNORE" => (1, unignore!),
    "RULE" => (2, rule!),
    "UNRULE" => (1, unrule!),
    "RULES" => (0, show_rules),
    "KEYBOARD" => (1, keyboard_mode!),
    "SET" => (2, set_option!),
    "UNDO" => (0, undo!),
    "REPORT" => (0, report),
    "HISTORY" => (0, history),
    "STATS" => (0, stats),
)

function execute!(checker, line)
    parts = split(line, ' ', limit = 2)
    name = parts[1]
    try
        haskey(HANDLERS, name) || throw(CommandError("UNKNOWN COMMAND $name"))
        arity, handler = HANDLERS[name]
        if arity === nothing
            length(parts) == 2 || throw(CommandError("BAD ARGUMENTS $name"))
            handler(checker, parts[2])
        else
            arguments = length(parts) == 2 ? split(parts[2], ' ') : SubString{String}[]
            length(arguments) == arity || throw(CommandError("BAD ARGUMENTS $name"))
            handler(checker, arguments)
        end
    catch err
        err isa CommandError || rethrow()
        emit("ERROR", err.message)
    end
end

function main()
    dictionary = Dict{String,Int}()
    word_count = parse(Int, readline())
    for _ in 1:word_count
        word, frequency = split(readline())
        dictionary[word] = parse(Int, frequency)
    end
    checker = SpellChecker(dictionary)
    command_count = parse(Int, readline())
    for _ in 1:command_count
        execute!(checker, readline())
    end
end

main()
