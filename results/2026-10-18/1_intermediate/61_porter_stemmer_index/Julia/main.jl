const TOKEN_PATTERN = r"[A-Za-z]+"
const WORD_PATTERN = r"^[A-Za-z]{1,30}$"
const NUMBER_PATTERN = r"^[0-9]{1,7}$"
const PREFIX_TERM_PATTERN = r"^[A-Za-z]{1,30}\*$"
const LEXEME_PATTERN = r"[()]|[^ ()]+"
const SYMBOLS = Dict("AND" => :and, "OR" => :or, "NOT" => :not, "(" => :open, ")" => :close)
const CONJUNCTION_CONTINUATIONS = (:and, :not, :open, :term, :prefix)
const VOWELS = "aeiou"
const STEP_NAMES = ["1a", "1b", "1c", "2", "3", "4", "5a", "5b"]
const STEP_4_SUFFIXES = [
    "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
    "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
]
const KWIC_WIDTH = 30
const MAX_COUNT = 100
const MAX_DOCUMENT_NUMBER = 999
const MAX_LINE_NUMBER = 999

struct CommandError <: Exception
    message::String
end

function letter_pattern(word)
    kinds = Char[]
    for (index, letter) in enumerate(word)
        vowel = letter in VOWELS || (letter == 'y' && index > 1 && kinds[end] == 'C')
        push!(kinds, vowel ? 'V' : 'C')
    end
    return String(kinds)
end

measure(word) = count("VC", letter_pattern(word))

has_vowel(word) = 'V' in letter_pattern(word)

ends_double(word) = endswith(letter_pattern(word), "CC") && word[end] == word[end-1]

ends_cvc(word) = endswith(letter_pattern(word), "CVC") && word[end] ∉ "wxy"

always(remainder) = true

measure_above_zero(remainder) = measure(remainder) > 0

measure_above_one(remainder) = measure(remainder) > 1

function ion_condition(remainder)
    return measure(remainder) > 1 && (endswith(remainder, "s") || endswith(remainder, "t"))
end

function final_e_condition(remainder)
    value = measure(remainder)
    return value > 1 || (value == 1 && !ends_cvc(remainder))
end

struct Rule
    suffix::String
    replacement::String
    condition::Function
end

function rules_with(condition, replacements)
    return [Rule(suffix, replacement, condition) for (suffix, replacement) in replacements]
end

const RULE_TABLES = Dict(
    "1a" => rules_with(always, ["sses" => "ss", "ies" => "i", "ss" => "ss", "s" => ""]),
    "1b" => [
        Rule("eed", "ee", measure_above_zero),
        Rule("ed", "", has_vowel),
        Rule("ing", "", has_vowel),
    ],
    "1c" => [Rule("y", "i", has_vowel)],
    "2" => rules_with(measure_above_zero, [
        "ational" => "ate", "tional" => "tion", "enci" => "ence", "anci" => "ance",
        "izer" => "ize", "abli" => "able", "alli" => "al", "entli" => "ent", "eli" => "e",
        "ousli" => "ous", "ization" => "ize", "ation" => "ate", "ator" => "ate",
        "alism" => "al", "iveness" => "ive", "fulness" => "ful", "ousness" => "ous",
        "aliti" => "al", "iviti" => "ive", "biliti" => "ble",
    ]),
    "3" => rules_with(measure_above_zero, [
        "icate" => "ic", "ative" => "", "alize" => "al", "iciti" => "ic",
        "ical" => "ic", "ful" => "", "ness" => "",
    ]),
    "4" => [
        Rule(suffix, "", suffix == "ion" ? ion_condition : measure_above_one)
        for suffix in STEP_4_SUFFIXES
    ],
    "5a" => [Rule("e", "", final_e_condition)],
)

# Apply the rule with the longest matching suffix; return the word and the applied suffix.
function apply_rules(word, rules)
    matching = filter(rule -> endswith(word, rule.suffix), rules)
    isempty(matching) && return (word, nothing)
    selected = argmax(rule -> length(rule.suffix), matching)
    remainder = word[1:end-length(selected.suffix)]
    selected.condition(remainder) || return (word, nothing)
    return (remainder * selected.replacement, selected.suffix)
end

function tidy_step_1b(word)
    if any(suffix -> endswith(word, suffix), ("at", "bl", "iz"))
        return word * "e"
    elseif ends_double(word) && word[end] ∉ "lsz"
        return word[1:end-1]
    elseif measure(word) == 1 && ends_cvc(word)
        return word * "e"
    end
    return word
end

function apply_step(name, word)
    if name == "5b"
        if measure(word) > 1 && ends_double(word) && endswith(word, "l")
            return word[1:end-1]
        end
        return word
    end
    result, suffix = apply_rules(word, RULE_TABLES[name])
    if name == "1b" && suffix in ("ed", "ing")
        return tidy_step_1b(result)
    end
    return result
end

function stemming_steps(word)
    changes = Pair{String,String}[]
    if length(word) > 2
        for name in STEP_NAMES
            result = apply_step(name, word)
            result != word && push!(changes, name => result)
            word = result
        end
    end
    return word, changes
end

const STEM_CACHE = Dict{String,String}()

porter_stem(word) = get!(() -> first(stemming_steps(word)), STEM_CACHE, word)

yes_no(flag) = flag ? "YES" : "NO"

function word_argument(text)
    occursin(WORD_PATTERN, text) || throw(CommandError("BAD WORD $text"))
    return lowercase(text)
end

function number_argument(text, low, high)
    occursin(NUMBER_PATTERN, text) || throw(CommandError("BAD NUMBER $text"))
    value = parse(Int, text)
    low <= value <= high || throw(CommandError("BAD NUMBER $text"))
    return value
end

function split_arguments(name, rest)
    name == "SEARCH" && return [rest]
    name == "APPEND" && return split(rest, ' '; limit=2)
    return split(rest, ' ')
end

by_count((stem, frequency)) = (-frequency, stem)

document_count(occurrences) = length(unique(document.number for (document, _) in occurrences))

function closest_distance(positions, others, same_stem)
    if same_stem
        gaps = diff(positions)
    else
        # The closest pair of different stems is adjacent in the merged order.
        marked = [[(position, 0) for position in positions]; [(other, 1) for other in others]]
        merged = sort!(marked)
        gaps = [
            later[1] - earlier[1]
            for (earlier, later) in zip(merged, merged[2:end]) if earlier[2] != later[2]
        ]
    end
    return isempty(gaps) ? nothing : minimum(gaps)
end

struct QueryItem
    kind::Symbol
    spelling::String
end

function classify(lexeme)
    haskey(SYMBOLS, lexeme) && return QueryItem(SYMBOLS[lexeme], lexeme)
    occursin(WORD_PATTERN, lexeme) && return QueryItem(:term, lowercase(lexeme))
    occursin(PREFIX_TERM_PATTERN, lexeme) && return QueryItem(:prefix, lowercase(chop(lexeme)))
    throw(CommandError("BAD TERM $lexeme"))
end

struct Token
    text::String
    form::String
    stem::String
    line::Int
    position::Int
    start::Int
end

struct Document
    number::Int
    lines::Vector{String}
    tokens::Vector{Token}
end

Document(number) = Document(number, String[], Token[])

function add_line!(document, text)
    push!(document.lines, text)
    added = Token[]
    for found in eachmatch(TOKEN_PATTERN, text)
        form = lowercase(found.match)
        token = Token(found.match, form, porter_stem(form), length(document.lines),
                      length(document.tokens) + 1, found.offset)
        push!(document.tokens, token)
        push!(added, token)
    end
    return added
end

line_tokens(document, line_number) = filter(token -> token.line == line_number, document.tokens)

reference(document, token) = "$(document.number):$(token.line):$(token.position)"

mutable struct QueryParser
    items::Vector{QueryItem}
    position::Int
    stem_sets::Dict{Int,Set{String}}
end

QueryParser(items, stem_sets) = QueryParser(items, 1, stem_sets)

function next_kind(parser)
    parser.position <= length(parser.items) || return nothing
    return parser.items[parser.position].kind
end

function take_item!(parser)
    parser.position > length(parser.items) && throw(CommandError("SYNTAX"))
    item = parser.items[parser.position]
    parser.position += 1
    return item
end

function parse_query!(parser)
    result = parse_expression!(parser)
    parser.position <= length(parser.items) && throw(CommandError("SYNTAX"))
    return result
end

function parse_expression!(parser)
    canonical, documents = parse_conjunction!(parser)
    while next_kind(parser) == :or
        parser.position += 1
        right, right_documents = parse_conjunction!(parser)
        canonical = "($canonical OR $right)"
        documents = union(documents, right_documents)
    end
    return canonical, documents
end

function parse_conjunction!(parser)
    canonical, documents = parse_negation!(parser)
    while next_kind(parser) in CONJUNCTION_CONTINUATIONS
        next_kind(parser) == :and && (parser.position += 1)
        right, right_documents = parse_negation!(parser)
        canonical = "($canonical AND $right)"
        documents = intersect(documents, right_documents)
    end
    return canonical, documents
end

function parse_negation!(parser)
    next_kind(parser) == :not || return parse_element!(parser)
    parser.position += 1
    canonical, documents = parse_negation!(parser)
    return "(NOT $canonical)", setdiff(Set(keys(parser.stem_sets)), documents)
end

function parse_element!(parser)
    item = take_item!(parser)
    if item.kind == :open
        result = parse_expression!(parser)
        take_item!(parser).kind == :close || throw(CommandError("SYNTAX"))
        return result
    elseif item.kind == :term
        stem = porter_stem(item.spelling)
        return stem, documents_where(stems -> stem in stems, parser)
    elseif item.kind == :prefix
        prefix_documents = documents_where(stems -> any(startswith(item.spelling), stems), parser)
        return "$(item.spelling)*", prefix_documents
    end
    throw(CommandError("SYNTAX"))
end

function documents_where(condition, parser)
    return Set{Int}(number for (number, stems) in parser.stem_sets if condition(stems))
end

struct SearchEngine
    stopwords::Set{String}
    documents::Dict{Int,Document}
    output::IOBuffer
end

SearchEngine(stopwords) = SearchEngine(stopwords, Dict{Int,Document}(), IOBuffer())

emit(engine, parts...) = println(engine.output, join(parts, " "))

add_document!(engine, number) = engine.documents[number] = Document(number)

function ordered_documents(engine)
    return [engine.documents[number] for number in sort!(collect(keys(engine.documents)))]
end

is_indexed(engine, token) = token.form ∉ engine.stopwords

indexed_tokens(engine, document) = filter(token -> is_indexed(engine, token), document.tokens)

function term_frequencies(engine, document)
    counts = Dict{String,Int}()
    for token in indexed_tokens(engine, document)
        counts[token.stem] = get(counts, token.stem, 0) + 1
    end
    return counts
end

stem_set(engine, document) = Set(keys(term_frequencies(engine, document)))

function total_frequencies(engine)
    totals = Dict{String,Int}()
    for document in values(engine.documents)
        mergewith!(+, totals, term_frequencies(engine, document))
    end
    return totals
end

function occurrence_map(engine)
    occurrences = Dict{String,Vector{Tuple{Document,Token}}}()
    for document in ordered_documents(engine), token in indexed_tokens(engine, document)
        push!(get!(Vector{Tuple{Document,Token}}, occurrences, token.stem), (document, token))
    end
    return occurrences
end

occurrences_of(engine, stem) = get(occurrence_map(engine), stem, Tuple{Document,Token}[])

function stem_positions(engine, document, stem)
    return [token.position for token in indexed_tokens(engine, document) if token.stem == stem]
end

function form_count(engine, form)
    return sum(
        count(token -> token.form == form, document.tokens)
        for document in values(engine.documents);
        init=0,
    )
end

function token_matches(engine, token, target)
    return target == "?" || (is_indexed(engine, token) && token.stem == target)
end

function describe_token(engine, token)
    return is_indexed(engine, token) ? "$(token.form)/$(token.stem)" : "$(token.form)/-"
end

function term_argument(engine, text)
    word = word_argument(text)
    word in engine.stopwords && throw(CommandError("STOPWORD $word"))
    return porter_stem(word)
end

function document_argument(engine, text)
    number = number_argument(text, 1, MAX_DOCUMENT_NUMBER)
    haskey(engine.documents, number) || throw(CommandError("NO DOC $number"))
    return engine.documents[number]
end

function stem_words(engine, arguments)
    words = map(word_argument, arguments)
    emit(engine, "STEM", ("$word:$(porter_stem(word))" for word in words)...)
end

function show_steps(engine, arguments)
    word = word_argument(arguments[1])
    _, changes = stemming_steps(word)
    if isempty(changes)
        emit(engine, "STEPS", word, "NONE")
    else
        emit(engine, "STEPS", word, ("$name:$result" for (name, result) in changes)...)
    end
end

function show_measure(engine, arguments)
    word = word_argument(arguments[1])
    emit(
        engine, "MEASURE", word, letter_pattern(word), "m=$(measure(word))",
        "vowel=$(yes_no(has_vowel(word)))", "double=$(yes_no(ends_double(word)))",
        "cvc=$(yes_no(ends_cvc(word)))",
    )
end

function show_index(engine, arguments)
    prefix = isempty(arguments) ? "" : word_argument(arguments[1])
    occurrences = occurrence_map(engine)
    stems = sort!(filter(stem -> startswith(stem, prefix), collect(keys(occurrences))))
    emit(engine, "INDEX", "stems=$(length(stems))")
    for stem in stems
        found = occurrences[stem]
        references = (reference(document, token) for (document, token) in found)
        emit(engine, stem, "df=$(document_count(found))", references...)
    end
end

function search(engine, arguments)
    items = [classify(lexeme.match) for lexeme in eachmatch(LEXEME_PATTERN, arguments[1])]
    stem_sets = Dict{Int,Set{String}}(
        document.number => stem_set(engine, document) for document in values(engine.documents)
    )
    canonical, matches = parse_query!(QueryParser(items, stem_sets))
    for item in items
        if item.kind == :term && item.spelling in engine.stopwords
            throw(CommandError("STOPWORD $(item.spelling)"))
        end
    end
    emit(engine, "SEARCH", canonical, "count=$(length(matches))", sort!(collect(matches))...)
end

function phrase(engine, arguments)
    words = map(word_argument, arguments)
    all(word -> word in engine.stopwords, words) && throw(CommandError("STOPWORDS ONLY"))
    targets = [word in engine.stopwords ? "?" : porter_stem(word) for word in words]
    matches = String[]
    for document in ordered_documents(engine)
        tokens = document.tokens
        for start in 1:length(tokens)-length(targets)+1
            if all(token_matches(engine, tokens[start+offset-1], target)
                   for (offset, target) in enumerate(targets))
                push!(matches, reference(document, tokens[start]))
            end
        end
    end
    emit(engine, "PHRASE \"$(join(targets, " "))\"", "matches=$(length(matches))", matches...)
end

function near(engine, arguments)
    first_stem = term_argument(engine, arguments[1])
    second_stem = term_argument(engine, arguments[2])
    limit = number_argument(arguments[3], 1, MAX_COUNT)
    found = String[]
    for document in ordered_documents(engine)
        distance = closest_distance(
            stem_positions(engine, document, first_stem),
            stem_positions(engine, document, second_stem),
            first_stem == second_stem,
        )
        if !isnothing(distance) && distance <= limit
            push!(found, "$(document.number):$distance")
        end
    end
    emit(engine, "NEAR", first_stem, second_stem, limit, "count=$(length(found))", found...)
end

function top(engine, arguments)
    limit = number_argument(arguments[1], 1, MAX_COUNT)
    if length(arguments) == 2
        document = document_argument(engine, arguments[2])
        counts = term_frequencies(engine, document)
        header = "TOP $limit doc=$(document.number)"
    else
        counts = total_frequencies(engine)
        header = "TOP $limit"
    end
    ranked = sort!(collect(counts); by=by_count)
    emit(engine, header, ("$stem:$frequency" for (stem, frequency) in first(ranked, limit))...)
end

function kwic(engine, arguments)
    stem = term_argument(engine, arguments[1])
    found = occurrences_of(engine, stem)
    emit(engine, "KWIC", stem, "count=$(length(found))")
    for (document, token) in found
        text = document.lines[token.line]
        after_start = token.start + length(token.text)
        before = text[max(1, token.start - KWIC_WIDTH):token.start-1]
        after = text[after_start:min(lastindex(text), after_start + KWIC_WIDTH - 1)]
        context = "|$(lpad(before, KWIC_WIDTH))[$(token.text)]$(rpad(after, KWIC_WIDTH))|"
        emit(engine, context, reference(document, token))
    end
end

function term_frequency(engine, arguments)
    document = document_argument(engine, arguments[1])
    stem = term_argument(engine, arguments[2])
    emit(engine, "TF", document.number, stem, get(term_frequencies(engine, document), stem, 0))
end

function document_frequency(engine, arguments)
    stem = term_argument(engine, arguments[1])
    emit(engine, "DF", stem, document_count(occurrences_of(engine, stem)))
end

function variants(engine, arguments)
    stem = term_argument(engine, arguments[1])
    forms = Dict{String,Int}()
    for (_, token) in occurrences_of(engine, stem)
        forms[token.form] = get(forms, token.form, 0) + 1
    end
    items = ("$form:$frequency" for (form, frequency) in sort!(collect(forms)))
    emit(engine, "VARIANTS", stem, "count=$(length(forms))", items...)
end

function similar_documents(engine, arguments)
    document = document_argument(engine, arguments[1])
    limit = number_argument(arguments[2], 1, MAX_COUNT)
    stems = stem_set(engine, document)
    scores = Tuple{Rational{Int},Int}[]
    for other in values(engine.documents)
        other === document && continue
        other_stems = stem_set(engine, other)
        union_size = length(union(stems, other_stems))
        score = union_size == 0 ? 0 // 1 : length(intersect(stems, other_stems)) // union_size
        push!(scores, (score, other.number))
    end
    sort!(scores; by=((score, number),) -> (-score, number))
    items = (
        "$number:$(numerator(score))/$(denominator(score))"
        for (score, number) in first(scores, limit)
    )
    emit(engine, "SIMILAR", document.number, items...)
end

function rank_documents(engine, arguments)
    limit = number_argument(arguments[1], 1, MAX_COUNT)
    query = Set(term_argument(engine, argument) for argument in arguments[2:end])
    ranked = Tuple{Int,Int,Int}[]
    for document in values(engine.documents)
        counts = term_frequencies(engine, document)
        matched = count(stem -> haskey(counts, stem), query)
        total = sum(stem -> get(counts, stem, 0), query)
        matched > 0 && push!(ranked, (matched, total, document.number))
    end
    sort!(ranked; by=((matched, total, number),) -> (-matched, -total, number))
    items = ("$number:$matched:$total" for (matched, total, number) in first(ranked, limit))
    emit(engine, "RANK", "count=$(length(ranked))", items...)
end

function info(engine, arguments)
    document = document_argument(engine, arguments[1])
    counts = term_frequencies(engine, document)
    if isempty(counts)
        top_stem = "-"
    else
        stem, frequency = argmin(by_count, collect(counts))
        top_stem = "$stem:$frequency"
    end
    emit(
        engine, "INFO", document.number, "lines=$(length(document.lines))",
        "tokens=$(length(document.tokens))", "indexed=$(sum(values(counts); init=0))",
        "stems=$(length(counts))", "top=$top_stem",
    )
end

function show_line(engine, arguments)
    document = document_argument(engine, arguments[1])
    line_number = number_argument(arguments[2], 1, MAX_LINE_NUMBER)
    if line_number > length(document.lines)
        throw(CommandError("NO LINE $(document.number):$line_number"))
    end
    tokens = line_tokens(document, line_number)
    emit(
        engine, "LINE $(document.number):$line_number", "tokens=$(length(tokens))",
        (describe_token(engine, token) for token in tokens)...,
    )
end

function stats(engine, arguments)
    documents = collect(values(engine.documents))
    emit(
        engine, "STATS", "docs=$(length(documents))",
        "lines=$(sum(document -> length(document.lines), documents; init=0))",
        "tokens=$(sum(document -> length(document.tokens), documents; init=0))",
        "indexed=$(sum(document -> length(indexed_tokens(engine, document)), documents; init=0))",
        "stems=$(length(total_frequencies(engine)))", "stopwords=$(length(engine.stopwords))",
    )
end

function stop_word!(engine, arguments)
    word = word_argument(arguments[1])
    word in engine.stopwords && throw(CommandError("ALREADY STOPWORD $word"))
    push!(engine.stopwords, word)
    emit(engine, "STOP", word, "unindexed=$(form_count(engine, word))")
end

function unstop_word!(engine, arguments)
    word = word_argument(arguments[1])
    word in engine.stopwords || throw(CommandError("NOT STOPWORD $word"))
    delete!(engine.stopwords, word)
    emit(engine, "UNSTOP", word, "indexed=$(form_count(engine, word))")
end

function append_line!(engine, arguments)
    number = number_argument(arguments[1], 1, MAX_DOCUMENT_NUMBER)
    created = !haskey(engine.documents, number)
    document = created ? add_document!(engine, number) : engine.documents[number]
    tokens = add_line!(document, arguments[2])
    indexed = count(token -> is_indexed(engine, token), tokens)
    emit(
        engine, "APPEND", number, "line=$(length(document.lines))", "tokens=$(length(tokens))",
        "indexed=$indexed", "new=$(yes_no(created))",
    )
end

function delete_document!(engine, arguments)
    document = document_argument(engine, arguments[1])
    delete!(engine.documents, document.number)
    emit(
        engine, "DELETE", document.number, "lines=$(length(document.lines))",
        "tokens=$(length(document.tokens))",
    )
end

struct Command
    arity::UnitRange{Int}
    handler::Function
end

const COMMANDS = Dict(
    "STEM" => Command(1:10, stem_words),
    "STEPS" => Command(1:1, show_steps),
    "MEASURE" => Command(1:1, show_measure),
    "INDEX" => Command(0:1, show_index),
    "SEARCH" => Command(1:1, search),
    "PHRASE" => Command(2:10, phrase),
    "NEAR" => Command(3:3, near),
    "TOP" => Command(1:2, top),
    "KWIC" => Command(1:1, kwic),
    "TF" => Command(2:2, term_frequency),
    "DF" => Command(1:1, document_frequency),
    "VARIANTS" => Command(1:1, variants),
    "SIMILAR" => Command(2:2, similar_documents),
    "RANK" => Command(2:11, rank_documents),
    "INFO" => Command(1:1, info),
    "LINE" => Command(2:2, show_line),
    "STATS" => Command(0:0, stats),
    "STOP" => Command(1:1, stop_word!),
    "UNSTOP" => Command(1:1, unstop_word!),
    "APPEND" => Command(2:2, append_line!),
    "DELETE" => Command(1:1, delete_document!),
)

function execute!(engine, line)
    space = findfirst(' ', line)
    name = isnothing(space) ? line : line[1:space-1]
    try
        haskey(COMMANDS, name) || throw(CommandError("UNKNOWN COMMAND $name"))
        command = COMMANDS[name]
        arguments = isnothing(space) ? String[] : split_arguments(name, line[space+1:end])
        length(arguments) in command.arity || throw(CommandError("BAD ARGUMENTS $name"))
        command.handler(engine, arguments)
    catch exception
        exception isa CommandError || rethrow()
        emit(engine, "ERROR", exception.message)
    end
end

function main()
    lines = readlines(stdin)
    engine = SearchEngine(Set{String}(split(lines[1])[2:end]))
    index = 2
    while startswith(lines[index], "DOC ")
        document = add_document!(engine, parse(Int, lines[index][5:end]))
        index += 1
        while lines[index] != "ENDDOC"
            add_line!(document, lines[index])
            index += 1
        end
        index += 1
    end
    for line in lines[index:end]
        line == "END" && break
        execute!(engine, line)
    end
    print(String(take!(engine.output)))
end

main()
