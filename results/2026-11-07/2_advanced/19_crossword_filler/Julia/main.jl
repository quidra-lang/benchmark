include("grid.jl")
include("slots.jl")
include("word_index.jl")
include("filler.jl")
include("render.jl")

const LETTER_POINTS = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10]
ignored(line) = isempty(line) || startswith(line, '#')
joined(items, separator) = isempty(items) ? "-" : join(items, separator)

function paragraphs(blocks)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines, "")
        append!(lines, block)
    end
    lines
end

struct Settings
    budget::Int
    minimum::Int
    symmetry::String
    relax::Int
    weak::Int
end

function read_settings(lines)
    values = Dict{String,String}()
    for line in lines
        ignored(line) && continue
        key, value = split(line, ' ')
        values[key] = value
    end
    Settings(parse(Int, values["node_budget"]), parse(Int, values["min_score"]), values["symmetry"],
        parse(Int, values["relax_step"]), parse(Int, values["weak_score"]))
end

struct WordList
    line_count::Int
    index::WordIndex
    invalid::Vector{Tuple{Int,String}}
    duplicates::Vector{Tuple{Int,String,Int}}
end

function WordList(lines)
    scores, first_lines = Dict{String,Int}(), Dict{String,Int}()
    invalid, duplicates = Tuple{Int,String}[], Tuple{Int,String,Int}[]
    for (number, line) in enumerate(lines)
        reason = word_line_error(line)
        if !isnothing(reason)
            push!(invalid, (number, reason))
            continue
        end
        word, score = split(line, ' ')
        if haskey(first_lines, word)
            push!(duplicates, (number, word, first_lines[word]))
        else
            scores[word] = parse(Int, score)
            first_lines[word] = number
        end
    end
    WordList(length(lines), WordIndex(scores), invalid, duplicates)
end

function word_report(list)
    index = list.index
    lines = ["WORDLIST lines=$(list.line_count) valid=$(length(index.words)) invalid=$(length(list.invalid)) duplicates=$(length(list.duplicates))"]
    append!(lines, ["invalid $number $reason" for (number, reason) in list.invalid])
    append!(lines, ["duplicate $number $word first=$first" for (number, word, first) in list.duplicates])
    for size in sort(collect(keys(index.by_length)))
        words = index.by_length[size]
        total = sum(index.words[id].score for id in words)
        best = index.words[words[1]]
        push!(lines, "length $size words=$(length(words)) average=$(decimal_text(total, length(words), 2)) best=$(best.text):$(best.score)")
    end
    bands = ["$low-$high=$(count(word -> low <= word.score <= high, index.words))" for (low, high) in [(1, 20), (21, 40), (41, 60), (61, 80), (81, 100)]]
    push!(lines, "bands " * join(bands, " "), "top " * join(["$(word.text):$(word.score)" for word in index.words[1:min(end, 5)]], " "))
    rare = sort([(count(word -> letter in word.letters, index.words), letter) for letter in 'A':'Z'])
    push!(lines, "rare_letters " * join(["$letter:$amount" for (amount, letter) in rare[1:5]], " "))
    lines
end

mutable struct Clue
    text::String
    uses::Int
end
struct ClueBook
    entries::Int
    added::Int
    invalid::Vector{Tuple{Int,String}}
    unknown::Vector{Tuple{Int,String}}
    clues::Vector{Vector{Clue}}
end

function ClueBook(lines, index)
    entries = added = 0
    invalid, unknown = Tuple{Int,String}[], Tuple{Int,String}[]
    clues = [Clue[] for _ in index.words]
    for (number, line) in enumerate(lines)
        ignored(line) && continue
        entries += 1
        reason = clue_line_error(line)
        if !isnothing(reason)
            push!(invalid, (number, reason))
            continue
        end
        word, text = split(line, '|'; keepempty=true)
        if haskey(index.lookup, word)
            push!(clues[index.lookup[word]], Clue(text, 0))
            added += 1
        else
            push!(unknown, (number, word))
        end
    end
    ClueBook(entries, added, invalid, unknown, clues)
end

function choose_clue!(book, id)
    isempty(book.clues[id]) && return nothing
    clues = book.clues[id]
    number = first(sort(collect(eachindex(clues)); by=i -> (clues[i].uses, i)))
    clues[number].uses += 1
    clues[number].text
end

function clue_report(book, index)
    lines = ["CLUES entries=$(book.entries) valid=$(book.added) invalid=$(length(book.invalid)) unknown=$(length(book.unknown)) words=$(count(clues -> !isempty(clues), book.clues))"]
    append!(lines, ["clue_invalid $number $reason" for (number, reason) in book.invalid])
    append!(lines, ["clue_unknown $number $word" for (number, word) in book.unknown])
    all_clues = [clue for clues in book.clues for clue in clues]
    used, repeated = count(clue -> clue.uses > 0, all_clues), count(clue -> clue.uses >= 2, all_clues)
    push!(lines, "CLUE_USE used=$used unused=$(book.added - used) repeated=$repeated")
    for word in sort(collect(keys(index.lookup)))
        for (number, clue) in enumerate(book.clues[index.lookup[word]])
            clue.uses >= 2 && push!(lines, "repeated $word clue=$number uses=$(clue.uses)")
        end
    end
    lines
end

mutable struct Block
    name::String
    options::Vector{String}
    rows::Vector{String}
end

function split_blocks(lines)
    blocks, current = Block[], nothing
    for line in lines
        if isnothing(current)
            startswith(line, "TEMPLATE ") && (current = Block(line[10:end], String[], String[]))
        elseif line == "END"
            push!(blocks, current)
            current = nothing
        elseif occursin(' ', line)
            push!(current.options, line)
        else
            push!(current.rows, line)
        end
    end
    blocks
end

struct Prepared
    settings::Settings
    layout::Layout
    initial::GridState
    theme_slots::Set{Int}
end

function prepare(block, defaults, names, index)
    name = block.name
    1 <= length(name) <= 20 && all('a' <= c <= 'z' || '0' <= c <= '9' || c == '_' for c in name) || return nothing, "bad name"
    name in names && return nothing, "duplicate name"
    budget, minimum, symmetry = defaults.budget, defaults.minimum, defaults.symmetry
    seen, themes = Set{String}(), String[]
    for (number, line) in enumerate(block.options)
        key, value = split(line, ' '; limit=2, keepempty=true)
        valid = false
        if key == "theme"
            if is_valid_word(value) && !(value in themes)
                push!(themes, value)
                valid = true
            end
        elseif !(key in seen)
            if key == "node_budget" && is_valid_integer(value, 1, 100000)
                budget, valid = parse(Int, value), true
            elseif key == "min_score" && is_valid_integer(value, 1, 100)
                minimum, valid = parse(Int, value), true
            elseif key == "symmetry" && value in ("rot180", "mirror", "none")
                symmetry, valid = value, true
            end
        end
        valid || return nothing, "bad option $number"
        push!(seen, key)
    end
    3 <= length(block.rows) <= 15 || return nothing, "bad height"
    width = length(block.rows[1])
    for (number, row) in enumerate(block.rows)
        if !(3 <= length(row) <= 15) || length(row) != width || !all(c == '.' || c == '#' || 'A' <= c <= 'Z' for c in row)
            return nothing, "bad row $number"
        end
    end
    grid = Grid(block.rows)
    if symmetry != "none"
        asymmetric = asymmetric_cell(grid, symmetry)
        !isnothing(asymmetric) && return nothing, "asymmetric at $(location(grid, asymmetric))"
    end
    components = component_count(grid)
    components == 1 || return nothing, "disconnected components=$components"
    short = find_short_run(grid)
    !isnothing(short) && return nothing, "short slot at $(location(grid, short[1])) $(short[2])"
    layout = Layout(grid)
    orphan = orphan_cell(layout)
    !isnothing(orphan) && return nothing, "orphan cell $(location(grid, orphan))"
    initial = GridState(grid.cells, length(layout.slots))
    theme_slots = Set{Int}()
    for (number, theme) in enumerate(themes)
        haskey(index.lookup, theme) || return nothing, "unknown theme $number"
        id = index.lookup[theme]
        fitting = findfirst(slot -> initial.words[slot.index] == 0 && length(slot.cells) == length(theme) && matches(index.words[id].letters, pattern(initial, slot)), layout.slots)
        isnothing(fitting) && return nothing, "theme $number does not fit"
        assign!(initial, layout.slots[fitting], id, index)
        push!(theme_slots, fitting)
    end
    settings = Settings(budget, minimum, symmetry, defaults.relax, defaults.weak)
    Prepared(settings, layout, initial, theme_slots), nothing
end

struct Completed
    prepared::Prepared
    attempts::Vector{Attempt}
    state::GridState
    chosen::Vector{Union{Nothing,String}}
end

function Completed(prepared, index, clues)
    attempts = Attempt[]
    minimum = prepared.settings.minimum
    while true
        attempt = Attempt(prepared.initial, minimum, prepared.settings.budget)
        run_attempt!(attempt, prepared.layout, index)
        push!(attempts, attempt)
        (attempt.outcome == "filled" || prepared.settings.relax == 0 || minimum <= 1) && break
        minimum = max(minimum - prepared.settings.relax, 1)
    end
    state = copy_state(final_state(attempts[end]))
    chosen = Union{Nothing,String}[nothing for _ in prepared.layout.slots]
    for across in (true, false), slot in prepared.layout.slots
        slot.across == across && state.words[slot.index] != 0 && (chosen[slot.index] = choose_clue!(clues, state.words[slot.index]))
    end
    Completed(prepared, attempts, state, chosen)
end

is_filled(result) = result.attempts[end].outcome == "filled"
total_score(result, index) = sum(index.words[id].score for id in result.state.words)
entry(result, slot, index) = "$(slot.label):$(index.words[result.state.words[slot.index]].text):$(index.words[result.state.words[slot.index]].score)"

function clue_paragraph(name, result, index)
    lines = ["TEMPLATE $name"]
    clued = missing = unfilled = 0
    for (heading, across) in [("ACROSS", true), ("DOWN", false)]
        slots = [slot for slot in result.prepared.layout.slots if slot.across == across]
        !isempty(slots) && push!(lines, heading)
        for slot in slots
            id = result.state.words[slot.index]
            if id == 0
                unfilled += 1
                push!(lines, list_line(slot, "(unfilled)", join(pattern(result.state, slot)), "-", false))
            else
                clue = result.chosen[slot.index]
                if isnothing(clue)
                    missing += 1
                    clue = "(no clue)"
                else
                    clued += 1
                end
                word = index.words[id]
                push!(lines, list_line(slot, clue, word.text, word.score, slot.index in result.prepared.theme_slots))
            end
        end
    end
    push!(lines, "clued=$clued missing=$missing unfilled=$unfilled")
    lines
end

function stats_paragraph(name, result, index)
    p, state = result.prepared, result.state
    layout, final_attempt = p.layout, result.attempts[end]
    grid, slots = layout.grid, layout.slots
    whites = white_cells(grid)
    blacks = length(grid.cells) - length(whites)
    givens = count(cell -> grid.cells[cell] != '.', whites)
    holding = [symmetry for symmetry in ("rot180", "mirror") if isnothing(asymmetric_cell(grid, symmetry))]
    symmetry = isempty(holding) ? "none" : join(holding, ',')
    lengths = sort(unique([length(slot.cells) for slot in slots]))
    across = count(slot -> slot.across, slots)
    length_text = join(["$size:$(count(slot -> length(slot.cells) == size, slots))" for size in lengths], ',')
    length_sum = sum(length(slot.cells) for slot in slots)
    unchecked = count(cell -> owner_count(layout, cell) == 1, whites)
    lines = ["TEMPLATE $name", "grid size=$(grid.width)x$(grid.height) blocks=$blacks white=$(length(whites)) density=$(decimal_text(100 * blacks, length(grid.cells), 1)) givens=$givens required=$(p.settings.symmetry) symmetry=$symmetry",
        "slots across=$across down=$(length(slots) - across) total=$(length(slots)) lengths=$length_text avg_length=$(decimal_text(length_sum, length(slots), 2)) longest=$(last(lengths)) unchecked=$unchecked"]
    !isempty(p.theme_slots) && push!(lines, "themes " * join([entry(result, slot, index) for slot in slots if slot.index in p.theme_slots], " "))
    supply = ["$size:$(count(id -> index.words[id].score >= p.settings.minimum, get(index.by_length, size, Int[])))" for size in lengths]
    push!(lines, "coverage " * join(supply, " "))
    tightest = sort([(length(candidates(index, pattern(p.initial, slot), p.settings.minimum, p.initial.used)), slot.index) for slot in slots if !(slot.index in p.theme_slots)])
    push!(lines, "tightest " * joined(["$(slots[id].label):$amount" for (amount, id) in tightest[1:min(end, 3)]], " "))
    for (number, attempt) in enumerate(result.attempts)
        push!(lines, "attempt $number min_score=$(attempt.minimum) budget=$(attempt.budget) outcome=$(attempt.outcome) nodes=$(attempt.nodes) backtracks=$(attempt.backtracks) prunes=$(attempt.prunes) dead_ends=$(attempt.dead_ends) max_depth=$(attempt.max_depth)")
    end
    push!(lines, "trace " * joined(final_attempt.trace, " "))
    hotspots = sort([slot.index for slot in slots if final_attempt.failures[slot.index] > 0]; by=id -> (-final_attempt.failures[id], id))
    push!(lines, "hotspots " * joined(["$(slots[id].label):$(final_attempt.failures[id])" for id in hotspots[1:min(end, 3)]], " "))
    if is_filled(result)
        push!(lines, "order " * joined([slots[id].label for id in final_attempt.sequence], " "))
        total = total_score(result, index)
        weakest = first(sort(slots; by=slot -> (index.words[state.words[slot.index]].score, slot.index)))
        weak = [entry(result, slot, index) for slot in slots if index.words[state.words[slot.index]].score < p.settings.weak]
        push!(lines, "quality total=$total average=$(decimal_text(total, length(slots), 2)) weakest=$(entry(result, weakest, index)) weak=$(joined(weak, ','))")
        letters = Set(state.letters[whites])
        missing = join([letter for letter in 'A':'Z' if !(letter in letters)])
        points = sum(LETTER_POINTS[Int(state.letters[cell]) - Int('A') + 1] for cell in whites)
        worst = nothing
        for cell in whites
            a, d = layout.across_slot[cell], layout.down_slot[cell]
            (a == 0 || d == 0) && continue
            combined = index.words[state.words[a]].score + index.words[state.words[d]].score
            (isnothing(worst) || combined < worst[1]) && (worst = (combined, cell, a, d))
        end
        crossing = "-"
        if !isnothing(worst)
            combined, cell, a, d = worst
            crossing = "$(location(grid, cell)) $(slots[a].label):$(index.words[state.words[a]].text)+$(slots[d].label):$(index.words[state.words[d]].text)=$combined"
        end
        push!(lines, "letters distinct=$(length(letters)) pangram=$(isempty(missing) ? "yes" : "no") missing=$(isempty(missing) ? "-" : missing) scrabble=$(decimal_text(points, length(whites), 2)) worst_crossing=$crossing")
    else
        assigned = count(!=(0), state.words)
        lettered = count(cell -> state.letters[cell] != '.', whites)
        blocked = [slot.label for slot in slots if state.words[slot.index] == 0 && isempty(candidates(index, pattern(state, slot), final_attempt.minimum, state.used))]
        push!(lines, "partial assigned=$assigned/$(length(slots)) letters=$lettered/$(length(whites)) blocked=$(joined(blocked, ','))")
    end
    lines
end

struct Template
    name::String
    completed::Union{Nothing,Completed}
    error::Union{Nothing,String}
end

function grid_paragraph(template)
    lines = ["TEMPLATE $(template.name)"]
    if !isnothing(template.error)
        push!(lines, "error $(template.error)")
    else
        result = template.completed
        final_attempt = result.attempts[end]
        push!(lines, "outcome=$(final_attempt.outcome) attempts=$(length(result.attempts)) min_score=$(final_attempt.minimum)")
        append!(lines, grid_lines(result.prepared.layout.grid, result.state.letters))
        push!(lines, "numbers")
        append!(lines, number_lines(result.prepared.layout))
    end
    lines
end

function overall_paragraphs(templates, index)
    valid = [template for template in templates if !isnothing(template.completed)]
    filled = [template for template in valid if is_filled(template.completed)]
    ranked = sort(filled; lt=(a, b) -> begin
        left = total_score(a.completed, index) * length(b.completed.prepared.layout.slots)
        right = total_score(b.completed, index) * length(a.completed.prepared.layout.slots)
        left == right ? a.name < b.name : left > right
    end)
    ranking = ["RANKING"]
    for (position, template) in enumerate(ranked)
        total = total_score(template.completed, index)
        entries = length(template.completed.prepared.layout.slots)
        push!(ranking, "rank $position $(template.name) average=$(decimal_text(total, entries, 2)) total=$total entries=$entries")
    end
    appearances = Dict{Int,Vector{String}}()
    for template in filled, id in template.completed.state.words
        push!(get!(appearances, id, String[]), template.name)
    end
    reused = sort([id for (id, names) in appearances if length(names) >= 2]; by=id -> (-length(appearances[id]), index.words[id].text))
    reuse = ["REUSE"]
    for id in reused
        push!(reuse, "reused $(index.words[id].text) $(length(appearances[id])) $(join(appearances[id], ','))")
    end
    attempts = sum((length(template.completed.attempts) for template in valid); init=0)
    nodes = sum((attempt.nodes for template in valid for attempt in template.completed.attempts); init=0)
    unfillable = count(template -> template.completed.attempts[end].outcome == "unfillable", valid)
    budget = count(template -> template.completed.attempts[end].outcome == "budget", valid)
    summary = ["SUMMARY templates=$(length(templates)) invalid=$(length(templates) - length(valid)) filled=$(length(filled)) unfillable=$unfillable budget=$budget attempts=$attempts nodes=$nodes"]
    [ranking, reuse, summary]
end

function main()
    settings = read_settings(readlines(joinpath("input", "params.txt")))
    word_list = WordList(readlines(joinpath("input", "words.txt")))
    index = word_list.index
    clues = ClueBook(readlines(joinpath("input", "clues.txt")), index)
    templates, names = Template[], Set{String}()
    for block in split_blocks(readlines(joinpath("input", "templates.txt")))
        prepared, error = prepare(block, settings, names, index)
        completed = isnothing(error) ? Completed(prepared, index, clues) : nothing
        push!(templates, Template(block.name, completed, error))
        push!(names, block.name)
    end
    grid = paragraphs(grid_paragraph.(templates))
    clue_lines = paragraphs([clue_paragraph(template.name, template.completed, index) for template in templates if !isnothing(template.completed)])
    stats = [stats_paragraph(template.name, template.completed, index) for template in templates if !isnothing(template.completed)]
    append!(stats, overall_paragraphs(templates, index))
    words = vcat(word_report(word_list), clue_report(clues, index))
    mkpath("output")
    for (name, lines) in [("grid.txt", grid), ("clues.txt", clue_lines), ("search_stats.txt", paragraphs(stats)), ("wordlist.txt", words)]
        open(joinpath("output", name), "w") do file
            for line in lines
                println(file, line)
            end
        end
    end
end

main()
