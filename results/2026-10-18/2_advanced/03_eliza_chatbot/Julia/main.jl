include("script_loader.jl")
include("matcher.jl")
include("linter.jl")
include("responder.jl")
include("memory.jl")

const SOURCES = ("keyword", "memory", "question", "default", "repeat")
const LISTS = ("DEFAULT", "QUESTION", "REPEAT")
const NOARGS = (":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo")
const TEXTARGS = (":prepare", ":reflect", ":say", ":explain")
const ONEARG = (":groups", ":find", ":script", ":cycles", ":coverage")
const KEYARGS = (":script", ":cycles", ":coverage", ":test")

mutable struct Session
    name::String
    turns::Int
    sources::Vector{Int}
    previous::Union{Nothing,Vector{Vector{String}}}
    history::Vector{String}
    lasttrace::Union{Nothing,Vector{String}}
    trace::Bool
    topics::Dict{String,Int}
    words::Dict{String,Int}
    stored::Int
    recalled::Int
    unrecognized::Vector{Int}
    undo::Any
end

Session(name) = Session(name, 0, zeros(Int, 5), nothing, String[], nothing, false,
    Dict{String,Int}(), Dict{String,Int}(), 0, 0, Int[], nothing)

mutable struct State
    positions::Vector{Int}
    hits::Vector{Int}
    itemuses::Vector{Int}
    keyworduses::Vector{Int}
    keywordreplies::Vector{Int}
    listpositions::Dict{String,Int}
    memory::ConversationMemory.Queue
    session::Session
end

mutable struct Chatbot
    script::ScriptLoader.Script
    state::State
    transcript::Vector{String}
    totalturns::Int
    totalsources::Vector{Int}
end

function Chatbot(script)
    state = State(ones(Int, length(script.rules)), zeros(Int, length(script.rules)), zeros(Int, length(script.items)),
        zeros(Int, length(script.keywords)), zeros(Int, length(script.keywords)), Dict(name => 1 for name in LISTS), ConversationMemory.Queue(script.memsize), Session(""))
    return Chatbot(script, state, String[], 0, zeros(Int, 5))
end

function normalize(text)
    clauses = Vector{String}[]
    for part in split(lowercase(text), r"[,.?!;]")
        words = String[]
        for piece in split(replace(part, r"[^a-z0-9']" => " "))
            word = String(strip(c -> c == '\'', piece))
            !isempty(word) && push!(words, word)
        end
        !isempty(words) && push!(clauses, words)
    end
    return clauses
end

allwords(clauses) = reduce(vcat, clauses; init=String[])
prefix(bot) = "$(bot.state.session.name) $(bot.state.session.turns)"
sourceline(turns, sources) = "turns=$turns " * join(("$name=$(sources[i])" for (i, name) in enumerate(SOURCES)), " ")
grouped(values, size) = [join(values[i:min(i + size - 1, length(values))], " ") for i in 1:size:length(values)]
ruleentries(script, keyword) = vcat([("memory", i, script.rules[id]) for (i, id) in enumerate(keyword.memories)], [("decomp", i, script.rules[id]) for (i, id) in enumerate(keyword.decomps)])

function rankedcounts(counts)
    pairs = sort!(collect(counts); by=entry -> (-last(entry), first(entry)))
    return isempty(pairs) ? "none" : join(("$word $count" for (word, count) in Iterators.take(pairs, 5)), ", ")
end

function cyclereset!(bot)
    fill!(bot.state.positions, 1)
    for name in LISTS
        bot.state.listpositions[name] = 1
    end
end

function taketext!(bot, name)
    texts = bot.script.texts[name]
    index = bot.state.listpositions[name]
    bot.state.listpositions[name] = mod(index, length(texts)) + 1
    return texts[index]
end

function takeitem!(bot, rule)
    index = bot.state.positions[rule.id]
    item = bot.script.items[rule.items[index]]
    bot.state.itemuses[item.id] += 1
    bot.state.positions[rule.id] = mod(index, length(rule.items)) + 1
    return index, item
end

function presubstitute(bot, clauses)
    return [reduce(vcat, (get(bot.script.pre, word, [word]) for word in clause); init=String[]) for clause in clauses]
end

prepared(bot, text) = presubstitute(bot, normalize(text))

function isquit(bot, text)
    words = allwords(normalize(text))
    return length(words) == 1 && words[1] in bot.script.quit
end

function selectclause(bot, clauses)
    return findfirst(clause -> any(word -> haskey(bot.script.keywordmap, word), clause), clauses)
end

function keywordlist(bot, words)
    ids = unique([bot.script.keywordmap[word] for word in words if haskey(bot.script.keywordmap, word)])
    return sort!(ids; by=id -> -bot.script.keywords[id].rank, alg=MergeSort)
end

function findrule(bot, rules, words)
    for (number, id) in enumerate(rules)
        rule = bot.script.rules[id]
        bindings = Matcher.matchpattern(rule.pattern, words, bot.script.groupwords)
        !isnothing(bindings) && return number, rule, bindings
    end
    return nothing
end

function applymemory!(bot, keyword, words, trace)
    found = findrule(bot, keyword.memories, words)
    isnothing(found) && return
    number, rule, bindings = found
    push!(trace, "MEMORY $(keyword.word) $number")
    bot.state.hits[rule.id] += 1
    isempty(rule.items) && return
    _, item = takeitem!(bot, rule)
    text = Responder.reply(item.text, bindings, bot.script.post)
    if ConversationMemory.store!(bot.state.memory, prefix(bot), keyword.word, text)
        bot.state.session.stored += 1
    end
end

function followkeyword!(bot, id, words, entered, trace)
    while true
        keyword = bot.script.keywords[id]
        push!(entered, id)
        bot.state.keyworduses[id] += 1
        found = findrule(bot, keyword.decomps, words)
        if isnothing(found)
            push!(trace, "NOMATCH $(keyword.word)")
            return nothing
        end
        number, rule, bindings = found
        bot.state.hits[rule.id] += 1
        if isempty(rule.items)
            push!(trace, "DECOMP $(keyword.word) $number 0")
            return nothing
        end
        itemnumber, item = takeitem!(bot, rule)
        push!(trace, "DECOMP $(keyword.word) $number $itemnumber")
        if item.kind == "REASM"
            bot.state.keywordreplies[id] += 1
            topics = bot.state.session.topics
            topics[keyword.word] = get(topics, keyword.word, 0) + 1
            return Responder.reply(item.text, bindings, bot.script.post)
        elseif item.kind == "NEWKEY"
            return nothing
        end
        target = item.arguments[1]
        next = get(bot.script.keywordmap, target, 0)
        if next == 0 || next in entered
            push!(trace, "BLOCKED $target")
            return nothing
        end
        if item.kind == "RESTATE"
            words = Responder.restate(item.arguments[2:end], bindings)
            push!(trace, join(["RESTATE", target, words...], " "))
        else
            push!(trace, "GOTO $target")
        end
        id = next
    end
end

function keywordreply!(bot, clauses, trace)
    selected = selectclause(bot, clauses)
    if isnothing(selected)
        push!(trace, "CLAUSE none")
        return nothing
    end
    words = clauses[selected]
    push!(trace, "CLAUSE $selected $(join(words, " "))")
    ids = keywordlist(bot, words)
    push!(trace, "KEYS " * join((bot.script.keywords[id].word for id in ids), " "))
    applymemory!(bot, bot.script.keywords[first(ids)], words, trace)
    entered = Set{Int}()
    for id in ids
        id in entered && continue
        push!(trace, "ENTER $(bot.script.keywords[id].word)")
        reply = followkeyword!(bot, id, words, entered, trace)
        !isnothing(reply) && return reply
    end
    return nothing
end

function decide!(bot, text)
    session = bot.state.session
    clauses = normalize(text)
    trace = String[]
    source = 1
    if !isempty(bot.script.texts["REPEAT"]) && !isempty(clauses) && clauses == session.previous
        push!(trace, "REPEAT")
        reply, source = taketext!(bot, "REPEAT"), 5
    else
        reply = keywordreply!(bot, presubstitute(bot, clauses), trace)
        if isnothing(reply)
            if !isempty(bot.state.memory.texts)
                session.recalled += 1
                reply, source = ConversationMemory.recall!(bot.state.memory, prefix(bot)), 2
            elseif endswith(text, "?") && !isempty(bot.script.texts["QUESTION"])
                reply, source = taketext!(bot, "QUESTION"), 3
            else
                reply, source = taketext!(bot, "DEFAULT"), 4
            end
        end
    end
    push!(trace, "REPLY $(SOURCES[source])")
    session.previous = clauses
    session.sources[source] += 1
    source in (3, 4) && push!(session.unrecognized, session.turns)
    return reply, trace
end

function respond!(bot, line)
    snapshot = deepcopy(bot.state)
    snapshot.session.undo = nothing
    session = bot.state.session
    session.undo = snapshot
    session.turns += 1
    for word in allwords(normalize(line))
        word ∉ bot.script.stop && (session.words[word] = get(session.words, word, 0) + 1)
    end
    push!(session.history, "$(session.turns): $line")
    reply, trace = decide!(bot, line)
    append!(bot.transcript, Responder.wrap(reply))
    session.lasttrace = trace
    session.trace && append!(bot.transcript, "  " .* trace)
end

function command!(bot, line)
    pieces = String.(split(line, ' '; limit=2))
    name = pieces[1]
    text = length(pieces) == 2 ? pieces[2] : ""
    args = String.(split(text, ' '; keepempty=false))
    name ∉ (NOARGS..., TEXTARGS..., ONEARG..., ":trace", ":test") && return ["unknown command $name"]
    valid = name in NOARGS ? isempty(args) : name in TEXTARGS ? !isempty(text) :
        name in ONEARG ? length(args) == 1 : name == ":trace" ? length(args) == 1 && args[1] in ("on", "off") : length(args) >= 2
    !valid && return ["bad arguments"]
    name in KEYARGS && !haskey(bot.script.keywordmap, args[1]) && return ["unknown keyword $(args[1])"]
    script, state, session = bot.script, bot.state, bot.state.session
    output = String[]
    if name == ":prepare"
        clauses = prepared(bot, text)
        append!(output, ["clause $i: $(join(clause, " "))" for (i, clause) in enumerate(clauses)])
        isempty(clauses) && push!(output, "no words")
        selected = selectclause(bot, clauses)
        if isnothing(selected)
            push!(output, "selected none")
        else
            push!(output, "selected $selected")
            ids = keywordlist(bot, clauses[selected])
            push!(output, "keys " * join(("$(script.keywords[id].word)/$(script.keywords[id].rank)" for id in ids), " "))
        end
    elseif name == ":test"
        keyword = script.keywords[script.keywordmap[args[1]]]
        words = allwords(prepared(bot, join(args[2:end], " ")))
        for (label, number, rule) in ruleentries(script, keyword)
            bindings = Matcher.matchpattern(rule.pattern, words, script.groupwords)
            result = isnothing(bindings) ? "no match" : isempty(bindings) ? "match" : join(("[$(join(bound, " "))]" for bound in bindings), " ")
            push!(output, "$label $number: $result")
        end
        isempty(output) && push!(output, "no rules")
    elseif name == ":reflect"
        clauses = prepared(bot, text)
        append!(output, [join(Responder.reflect(clause, script.post), " ") for clause in clauses])
        isempty(clauses) && push!(output, "no words")
    elseif name == ":keys"
        keywords = sort(script.keywords; by=key -> (-key.rank, key.word))
        append!(output, grouped(["$(key.word)/$(key.rank)" for key in keywords], 8))
    elseif name == ":groups"
        groups = sort([group.name for group in script.groups if args[1] in group.members])
        push!(output, isempty(groups) ? "none" : join(groups, " "))
    elseif name == ":find"
        word = args[1]
        haskey(script.keywordmap, word) && push!(output, "keyword rank $(script.keywords[script.keywordmap[word]].rank)")
        for (label, substitutions) in (("pre", script.pres), ("post", script.posts)), entry in substitutions
            (entry.source == word || word in entry.replacement) && push!(output, "$label $(entry.line): $(entry.source) -> $(join(entry.replacement, " "))")
        end
        for group in script.groups
            word in group.members && push!(output, "group $(group.name) line $(group.line)")
        end
        for keyword in script.keywords, (label, number, rule) in ruleentries(script, keyword)
            word in rule.pattern && push!(output, "pattern $(keyword.word) $label $number")
        end
        word in script.stop && push!(output, "stop word")
        word in script.quit && push!(output, "quit word")
        isempty(output) && push!(output, "not found")
    elseif name == ":script"
        keyword = script.keywords[script.keywordmap[args[1]]]
        numbers = [keyword.line]
        for (_, _, rule) in ruleentries(script, keyword)
            push!(numbers, rule.line)
            append!(numbers, [script.items[id].line for id in rule.items])
        end
        append!(output, ["$number $(script.lines[number])" for number in sort!(numbers)])
    elseif name == ":why"
        append!(output, isnothing(session.lasttrace) ? ["no reply yet"] : session.lasttrace)
    elseif name == ":trace"
        session.trace = args[1] == "on"
        push!(output, "trace $(args[1])")
    elseif name == ":history"
        append!(output, isempty(session.history) ? ["no turns yet"] : session.history[max(1, end - 4):end])
    elseif name == ":memory"
        push!(output, "memory $(length(state.memory.texts))/$(state.memory.capacity)")
        append!(output, ["$i: $stored" for (i, stored) in enumerate(state.memory.texts)])
    elseif name == ":forget"
        push!(output, "forgot $(length(state.memory.texts))")
        ConversationMemory.clear!(state.memory, prefix(bot))
    elseif name in (":cycles", ":coverage")
        keyword = script.keywords[script.keywordmap[args[1]]]
        for (label, number, rule) in ruleentries(script, keyword)
            if name == ":cycles"
                result = isempty(rule.items) ? "empty" : "next $(state.positions[rule.id])/$(length(rule.items))"
            else
                uses = isempty(rule.items) ? "-" : join((state.itemuses[id] for id in rule.items), " ")
                result = "hits $(state.hits[rule.id]) entries $uses"
            end
            push!(output, "$label $number: $result")
        end
        isempty(output) && push!(output, "no rules")
    elseif name == ":reset"
        cyclereset!(bot)
        push!(output, "cycles reset")
    elseif name == ":unused"
        numbers = sort([item.line for item in script.items if state.itemuses[item.id] == 0])
        push!(output, "unused $(length(numbers))")
        append!(output, grouped(string.(numbers), 12))
    elseif name == ":stats"
        push!(output, sourceline(session.turns, session.sources))
    elseif name in (":say", ":explain")
        if isquit(bot, text)
            push!(output, "would quit")
        else
            saved = deepcopy(state)
            reply, trace = decide!(bot, text)
            bot.state = saved
            append!(output, name == ":say" ? [reply] : trace)
        end
    elseif name == ":undo"
        if isnothing(session.undo)
            push!(output, "nothing to undo")
        else
            bot.state = session.undo
            push!(output, "undone turn $(bot.state.session.turns + 1)")
        end
    end
    return output
end

function notes!(bot)
    session = bot.state.session
    unrecognized = isempty(session.unrecognized) ? "none" : join(session.unrecognized, " ")
    push!(bot.transcript, "NOTES $(session.name)",
        "  " * sourceline(session.turns, session.sources),
        "  topics: " * rankedcounts(session.topics), "  words: " * rankedcounts(session.words),
        "  memory: stored=$(session.stored) recalled=$(session.recalled) pending=$(length(bot.state.memory.texts))",
        "  unrecognized: $unrecognized")
    bot.totalturns += session.turns
    bot.totalsources .+= session.sources
end

function run!(bot, lines)
    sessions = 0
    for line in lines
        if startswith(line, "SESSION ")
            sessions += 1
            name = line[9:end]
            if sessions >= 2
                push!(bot.transcript, "")
                "cycles" ∉ bot.script.persist && cyclereset!(bot)
                "memory" ∉ bot.script.persist && ConversationMemory.clear!(bot.state.memory, "$name 0")
            end
            bot.state.session = Session(name)
            push!(bot.transcript, line)
            texts = bot.script.texts["INITIAL"]
            append!(bot.transcript, Responder.wrap(texts[mod(sessions - 1, length(texts)) + 1]))
        elseif startswith(line, ":")
            push!(bot.transcript, line)
            append!(bot.transcript, "  " .* command!(bot, line))
        else
            push!(bot.transcript, "YOU: $line")
            if isquit(bot, line)
                texts = bot.script.texts["FINAL"]
                append!(bot.transcript, Responder.wrap(texts[mod(sessions - 1, length(texts)) + 1]))
                notes!(bot)
            else
                respond!(bot, line)
            end
        end
    end
    push!(bot.transcript, "", "SUMMARY sessions=$sessions " * sourceline(bot.totalturns, bot.totalsources))
end

function keywordstats(bot)
    output = ["keyword,rank,uses,replies,decomposition_hits"]
    keywords = sort(bot.script.keywords; by=key -> (-bot.state.keyworduses[key.id], key.word))
    for key in keywords
        hits = isempty(key.decomps) ? "-" : join((bot.state.hits[id] for id in key.decomps), "/")
        push!(output, "$(key.word),$(key.rank),$(bot.state.keyworduses[key.id]),$(bot.state.keywordreplies[key.id]),$hits")
    end
    return output
end

function writefile(name, lines)
    open(joinpath("output", name), "w") do file
        for line in lines
            println(file, line)
        end
    end
end

function main()
    script = ScriptLoader.load("input/script.txt")
    diagnostics = Linter.lint(script)
    lint = ["$(entry.line) $(entry.code) $(entry.message)" for entry in diagnostics]
    errors = count(entry -> entry.code in Linter.ERRORS, diagnostics)
    push!(lint, isempty(diagnostics) ? "OK" : "TOTAL $(length(diagnostics)) errors=$errors warnings=$(length(diagnostics) - errors)")
    bot = Chatbot(script)
    run!(bot, readlines("input/dialogue.txt"))
    mkpath("output")
    writefile("lint.txt", lint)
    writefile("transcript.txt", bot.transcript)
    writefile("keyword_stats.csv", keywordstats(bot))
    writefile("memory_log.txt", bot.state.memory.log)
end

main()
