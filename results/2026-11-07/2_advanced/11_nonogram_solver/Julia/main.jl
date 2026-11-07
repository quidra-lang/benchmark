include("line_solver.jl")
include("clues.jl")
include("propagation.jl")
include("search.jl")
include("render.jl")
using .LineSolver, .Clues, .Propagation, .PuzzleSearch, .Render

const Given = Tuple{Int,Int,Int}
Base.@kwdef mutable struct Puzzle
    name::String
    width::Int
    height::Int
    row_lines::Vector{String}
    column_lines::Vector{String}
    given_lines::Vector{Tuple{Int,Int,Char}}
    answer_lines::Union{Nothing,Vector{String}}
    rows::Vector{Vector{Int}} = Vector{Int}[]
    columns::Vector{Vector{Int}} = Vector{Int}[]
    givens::Vector{Given} = Given[]
    answer::Union{Nothing,Matrix{Int}} = nothing
end
function read_blocks(path)
    blocks = Vector{String}[]
    block = nothing
    for line in readlines(path)
        if block === nothing
            (!isempty(line) && !startswith(line, "#")) && (block = [line])
        elseif line == "END"
            push!(blocks, block)
            block = nothing
        else
            push!(block, line)
        end
    end
    blocks
end
function Puzzle(lines)
    size_fields = split(lines[2])
    column_at = findfirst(==("COLUMNS"), lines)
    row_lines = lines[4:column_at-1]
    column_lines = String[]
    given_lines = Tuple{Int,Int,Char}[]
    position = column_at+1
    while position <= length(lines) && is_clue_line(lines[position])
        push!(column_lines, lines[position])
        position += 1
    end
    while position <= length(lines) && startswith(lines[position], "GIVEN ")
        tokens = split(lines[position])
        push!(given_lines, (parse(Int, tokens[2]), parse(Int, tokens[3]), tokens[4][1]))
        position += 1
    end
    answer_lines = position <= length(lines) ? lines[position+1:end] : nothing
    Puzzle(name=lines[1][8:end], width=parse(Int, size_fields[2]), height=parse(Int, size_fields[3]), row_lines=row_lines, column_lines=column_lines, given_lines=given_lines, answer_lines=answer_lines)
end
valid_name(name) = occursin(r"^[a-z0-9_]{1,20}$", name)
number_list(numbers) = isempty(numbers) ? "-" : join(numbers, ",")
cell_text(row, column) = "$row,$column"
function state_grid(texts)
    h, w = length(texts), length(texts[1])
    [char_state(texts[r][c]) for r in 1:h, c in 1:w]
end
grid_columns(grid) = [grid[:, c] for c in axes(grid, 2)]
grid_rows(grid) = [grid[r, :] for r in axes(grid, 1)]
differing_cells(first, second) = [(r, c) for r in axes(first, 1) for c in axes(first, 2) if first[r, c] != second[r, c]]
function validate!(p, earlier)
    valid_name(p.name) || return "bad name"
    p.name in earlier && return "duplicate name"
    1 <= p.width <= 30 && 1 <= p.height <= 30 || return "bad size"
    length(p.row_lines) == p.height || return "row count $(length(p.row_lines)) expected $(p.height)"
    length(p.column_lines) == p.width || return "column count $(length(p.column_lines)) expected $(p.width)"
    for (texts, kind, size, result) in ((p.row_lines, "row", p.width, p.rows), (p.column_lines, "column", p.height, p.columns))
        for (i, text) in enumerate(texts)
            clue = parse_clue(text)
            clue === nothing && return "bad clue $kind $i"
            fits(clue, size) || return "$kind $i too long"
            push!(result, clue)
        end
    end
    row_total, column_total = sum(sum, p.rows), sum(sum, p.columns)
    row_total == column_total || return "total mismatch rows=$row_total columns=$column_total"
    taken = Set{Tuple{Int,Int}}()
    for (k, (r, c, value)) in enumerate(p.given_lines)
        1 <= r <= p.height && 1 <= c <= p.width && value in ('#', '.') || return "bad given $k"
        (r, c) in taken && return "duplicate given $k"
        push!(taken, (r, c))
        push!(p.givens, (r, c, char_state(value)))
    end
    if p.answer_lines !== nothing
        length(p.answer_lines) == p.height || return "bad answer"
        all(line -> length(line) == p.width && all(ch -> ch in ('#', '.', '?'), line), p.answer_lines) || return "bad answer"
        p.answer = state_grid(p.answer_lines)
    end
    nothing
end
function logical_solve(rows, columns, givens, precise)
    grid = fill(UNKNOWN, length(rows), length(columns))
    for (r, c, value) in givens
        grid[r, c] = value
    end
    propagation = propagate!(grid, rows, columns, precise, trues(length(rows)), trues(length(columns)))
    grid, propagation
end
function solving_result(grid, propagation)
    if propagation.conflict !== nothing
        step = propagation.conflict
        return "contradiction at=" * line_label(step.is_row, step.index)
    end
    determined_count(grid) == length(grid) ? "solved" : "stuck"
end
struct Analysis
    simple_grid::Matrix{Int}
    logic_grid::Matrix{Int}
    simple::PropagationResult
    logic::PropagationResult
    simple_result::String
    logic_result::String
    search::Union{Nothing,SearchResult}
    solutions::Vector{Matrix{Int}}
    status::String
    difficulty::String
    line_solves::Int
    guesses::Int
    max_depth::Int
end
function Analysis(rows, columns, givens)
    simple_grid, simple = logical_solve(rows, columns, givens, false)
    logic_grid, logic = logical_solve(rows, columns, givens, true)
    simple_result, logic_result = solving_result(simple_grid, simple), solving_result(logic_grid, logic)
    search = nothing
    solutions = Matrix{Int}[]
    difficulty = "-"
    if logic.conflict !== nothing
        status = "contradiction"
    elseif logic_result == "solved"
        status = "unique"
        solutions = [logic_grid]
        difficulty = simple_result == "solved" ? "easy" : "medium"
    else
        search = SearchResult()
        search!(search, logic_grid, rows, columns)
        solutions = search.solutions
        status = ("none", "unique", "multiple")[length(solutions)+1]
        status == "unique" && (difficulty = "hard")
    end
    solves = length(logic.steps) + (search === nothing ? 0 : search.line_solves)
    guesses = search === nothing ? 0 : length(search.guesses)
    depth = search === nothing ? 0 : search.max_depth
    Analysis(simple_grid, logic_grid, simple, logic, simple_result, logic_result, search, solutions, status, difficulty, solves, guesses, depth)
end
function clue_statistics(rows, columns)
    lengths = [size for clue in vcat(rows, columns) for size in clue]
    fixed = count(clue -> isempty(clue) || span(clue) == length(columns), rows)
    fixed += count(clue -> isempty(clue) || span(clue) == length(rows), columns)
    "row_blocks=$(sum(length, rows)) column_blocks=$(sum(length, columns)) filled=$(sum(sum, rows)) max_block=$(isempty(lengths) ? 0 : maximum(lengths)) fixed_lines=$fixed"
end
function step_statistics(propagation)
    productive = idle = best = 0
    label = "-"
    for step in propagation.steps
        step.contradiction && continue
        if step.gain > 0
            productive += 1
        else
            idle += 1
        end
        if step.gain > best
            best, label = step.gain, line_label(step.is_row, step.index)
        end
    end
    "productive=$productive idle=$idle best=$best at=$label"
end
function features_text(grid)
    h, w = size(grid)
    seen = falses(h, w)
    sizes = Int[]
    filled = count(==(FILLED), grid)
    min_row, min_column, max_row, max_column = h+1, w+1, 0, 0
    for r in 1:h, c in 1:w
        grid[r, c] == FILLED || continue
        min_row, min_column = min(min_row, r), min(min_column, c)
        max_row, max_column = max(max_row, r), max(max_column, c)
        seen[r, c] && continue
        seen[r, c] = true
        pending = [(r, c)]
        cells = 0
        while !isempty(pending)
            a, b = pop!(pending)
            cells += 1
            for (dr, dc) in ((-1, 0), (1, 0), (0, -1), (0, 1))
                nr, nc = a+dr, b+dc
                if 1 <= nr <= h && 1 <= nc <= w && grid[nr, nc] == FILLED && !seen[nr, nc]
                    seen[nr, nc] = true
                    push!(pending, (nr, nc))
                end
            end
        end
        push!(sizes, cells)
    end
    bbox = filled == 0 ? "-" : "$min_row,$min_column,$max_row,$max_column"
    symmetries = String[]
    for (name, flip_rows, flip_columns) in (("lr", false, true), ("ud", true, false), ("rot180", true, true))
        all(grid[r, c] == grid[flip_rows ? h+1-r : r, flip_columns ? w+1-c : c] for r in 1:h for c in 1:w) && push!(symmetries, name)
    end
    symmetry = isempty(symmetries) ? "none" : join(symmetries, ",")
    "filled=$filled components=$(length(sizes)) largest=$(isempty(sizes) ? 0 : maximum(sizes)) bbox=$bbox symmetry=$symmetry"
end
function unknown_summary(lines)
    parts = String[]
    for (i, cells) in enumerate(lines)
        n = count(==(UNKNOWN), cells)
        n > 0 && push!(parts, "$i:$n")
    end
    join(parts, " ")
end
function evaluate_givens(p, analysis)
    (isempty(p.givens) || analysis.status == "multiple") && return nothing
    label = analysis.status == "unique" ? "redundant" : "blame"
    accepted = analysis.status == "unique" ? ("unique",) : ("unique", "multiple")
    numbers = Int[]
    for k in eachindex(p.givens)
        others = vcat(p.givens[1:k-1], p.givens[k+1:end])
        Analysis(p.rows, p.columns, others).status in accepted && push!(numbers, k)
    end
    "givens $label=$(number_list(numbers))"
end
function grade_answer(p, analysis)
    answer = p.answer
    rows = [r for r in 1:p.height if !has_placement(answer[r, :], p.rows[r])]
    columns = [c for c in 1:p.width if !has_placement(answer[:, c], p.columns[c])]
    givens = [k for (k, (r, c, value)) in enumerate(p.givens) if answer[r, c] != UNKNOWN && answer[r, c] != value]
    known = determined_count(answer)
    mismatched = !isempty(rows) || !isempty(columns) || !isempty(givens)
    result = known < length(answer) ? "partial" : mismatched ? "wrong" : "correct"
    text = "answer result=$result known=$known rows=$(number_list(rows)) columns=$(number_list(columns)) givens=$(number_list(givens))"
    if result == "partial"
        extendable = false
        if !mismatched
            taken = Set((r, c) for (r, c, _) in p.givens)
            extra = Given[(r, c, answer[r, c]) for r in 1:p.height for c in 1:p.width if answer[r, c] != UNKNOWN && !((r, c) in taken)]
            extendable = Analysis(p.rows, p.columns, vcat(p.givens, extra)).status in ("unique", "multiple")
        end
        text *= " extendable=$(extendable ? "yes" : "no")"
    end
    if analysis.status == "unique"
        solution = analysis.solutions[1]
        differs = count(i -> answer[i] != UNKNOWN && answer[i] != solution[i], eachindex(answer))
        text *= " differs=$differs"
    end
    lines = [text]
    for (is_row, indices, clues) in ((true, rows, p.rows), (false, columns, p.columns))
        for i in indices
            cells = line_cells(answer, is_row, i)
            suffix = result == "partial" ? "cells=$(state_string(cells))" : "got=$(comma_separated(run_clue(cells)))"
            push!(lines, "mismatch $(line_label(is_row, i)) expected=$(comma_separated(clues[i])) $suffix")
        end
    end
    result, lines
end
struct Report
    puzzle::Puzzle
    analysis::Analysis
    grading::String
    lines::Vector{String}
end
function Report(p)
    a = Analysis(p.rows, p.columns, p.givens)
    lines = ["PUZZLE $(p.name)", "size=$(p.width)x$(p.height) givens=$(length(p.givens)) status=$(a.status) difficulty=$(a.difficulty)",
        "clues " * clue_statistics(p.rows, p.columns),
        "simple known=$(determined_count(a.simple_grid)) line_solves=$(length(a.simple.steps)) result=$(a.simple_result)",
        "logic known=$(determined_count(a.logic_grid)) line_solves=$(length(a.logic.steps)) result=$(a.logic_result)", "steps " * step_statistics(a.logic)]
    p.width*p.height <= 49 && push!(lines, "trace " * join((step_text(step) for step in a.logic.steps), " "))
    if a.logic_result == "stuck"
        push!(lines, "stuck rows=$(unknown_summary(grid_rows(a.logic_grid))) columns=$(unknown_summary(grid_columns(a.logic_grid)))")
    end
    if a.status == "contradiction"
        step = a.logic.conflict
        clue = step.is_row ? p.rows[step.index] : p.columns[step.index]
        push!(lines, "conflict line=$(line_label(step.is_row, step.index)) clue=$(comma_separated(clue)) cells=$(state_string(line_cells(a.logic_grid, step.is_row, step.index)))")
    end
    if a.search !== nothing
        search = a.search
        push!(lines, "search guesses=$(length(search.guesses)) max_depth=$(search.max_depth) backtracks=$(search.backtracks) solutions=$(length(search.solutions)) line_solves=$(search.line_solves)")
        for g in search.guesses
            push!(lines, "guess $(g.number) depth=$(g.depth) cell=$(g.row),$(g.column) value=$(state_char(g.value)) solves=$(g.solves) known=$(g.known) result=$(g.result)")
        end
    end
    if a.status == "multiple"
        cells = differing_cells(a.solutions...)
        push!(lines, "differ count=$(length(cells)) cells=$(join([cell_text(r, c) for (r, c) in cells], " "))")
    end
    names, grids = String[], Matrix{Int}[]
    if a.status == "contradiction"
        push!(names, "partial"); push!(grids, a.logic_grid)
    else
        a.simple_result == "stuck" && (push!(names, "simple"); push!(grids, a.simple_grid))
        a.logic_result == "stuck" && (push!(names, "logic"); push!(grids, a.logic_grid))
        if a.status == "multiple"
            append!(names, ["first", "second"]); append!(grids, a.solutions)
        end
    end
    !isempty(names) && append!(lines, grid_display(names, grids))
    if a.status == "unique"
        push!(lines, "sheet")
        append!(lines, answer_sheet(p.rows, p.columns, a.solutions[1]))
        push!(lines, "picture " * features_text(a.solutions[1]))
    end
    evaluation = evaluate_givens(p, a)
    evaluation !== nothing && push!(lines, evaluation)
    grading = "-"
    if p.answer !== nothing
        grading, detail = grade_answer(p, a)
        append!(lines, detail)
    end
    Report(p, a, grading, lines)
end
function stats_row(report)
    p, a = report.puzzle, report.analysis
    join([p.name, a.status, a.difficulty, p.width, p.height, length(p.givens), determined_count(a.simple_grid), determined_count(a.logic_grid), a.line_solves, a.guesses, a.max_depth, length(a.solutions), report.grading], ",")
end
function join_paragraphs(paragraphs)
    lines = String[]
    for paragraph in paragraphs
        !isempty(lines) && push!(lines, "")
        append!(lines, paragraph)
    end
    lines
end
function process_puzzles(blocks)
    names = Set{String}()
    reports = Report[]
    paragraphs = Vector{String}[]
    stats = ["puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer"]
    for block in blocks
        p = Puzzle(block)
        reason = validate!(p, names)
        push!(names, p.name)
        if reason !== nothing
            push!(paragraphs, ["PUZZLE $(p.name)", "error $reason"])
            push!(stats, p.name * ",invalid" * repeat(",-", 11))
        else
            report = Report(p)
            push!(reports, report)
            push!(paragraphs, report.lines)
            push!(stats, stats_row(report))
        end
    end
    order = Dict("easy" => 0, "medium" => 1, "hard" => 2)
    ranked = sort(filter(r -> r.analysis.status == "unique", reports); by=r -> (order[r.analysis.difficulty], r.analysis.line_solves+25 * r.analysis.guesses, r.puzzle.name))
    ranking = ["RANKING"]
    for (k, report) in enumerate(ranked)
        p, a = report.puzzle, report.analysis
        push!(ranking, "rank $k $(p.name) $(a.difficulty) score=$(a.line_solves+25 * a.guesses) size=$(p.width)x$(p.height)")
    end
    push!(paragraphs, ranking)
    statuses = [r.analysis.status for r in reports]
    difficulties = [r.analysis.difficulty for r in reports]
    solves = sum((r.analysis.line_solves for r in reports); init=0)
    guesses = sum((r.analysis.guesses for r in reports); init=0)
    push!(paragraphs, ["SUMMARY puzzles=$(length(blocks)) invalid=$(length(blocks)-length(reports)) contradiction=$(count(==("contradiction"), statuses)) none=$(count(==("none"), statuses)) unique=$(count(==("unique"), statuses)) multiple=$(count(==("multiple"), statuses)) easy=$(count(==("easy"), difficulties)) medium=$(count(==("medium"), difficulties)) hard=$(count(==("hard"), difficulties)) line_solves=$solves guesses=$guesses"])
    reports, join_paragraphs(paragraphs), stats
end
function validate_picture(name, rows, earlier)
    valid_name(name) || return "bad name"
    name in earlier && return "duplicate name"
    1 <= length(rows) <= 30 || return "bad height"
    width = length(rows[1])
    for (i, row) in enumerate(rows)
        1 <= length(row) <= 30 && length(row) == width && all(ch -> ch in ('#', '.'), row) || return "bad row $i"
    end
    nothing
end
function generate_picture(name, grid, reports)
    rows, columns = run_clue.(grid_rows(grid)), run_clue.(grid_columns(grid))
    givens = Given[]
    initial = Analysis(rows, columns, givens)
    a = initial
    log = String[]
    while a.status == "multiple"
        r, c = differing_cells(a.solutions...)[1]
        value = grid[r, c]
        push!(givens, (r, c, value))
        a = Analysis(rows, columns, givens)
        push!(log, "# hint $(length(givens)) cell=$r,$c value=$(state_char(value)) status=$(a.status)")
    end
    for given in copy(givens)
        others = filter(!=(given), givens)
        if Analysis(rows, columns, others).status == "unique"
            givens = others
            push!(log, "# drop cell=$(given[1]),$(given[2])")
        end
    end
    a = Analysis(rows, columns, givens)
    additions = 0
    while a.difficulty == "hard"
        r, c = guess_cell(a.logic_grid)
        value = grid[r, c]
        push!(givens, (r, c, value))
        a = Analysis(rows, columns, givens)
        additions += 1
        push!(log, "# logic hint $additions cell=$r,$c value=$(state_char(value)) difficulty=$(a.difficulty)")
    end
    duplicate = "-"
    for report in reports
        p = report.puzzle
        if p.rows == rows && p.columns == columns
            duplicate = p.name
            break
        end
    end
    h, w = size(grid)
    lines = ["# picture $name size=$(w)x$h $(features_text(grid))", "# clues $(clue_statistics(rows, columns)) duplicate_of=$duplicate", "# plain status=$(initial.status) difficulty=$(initial.difficulty) line_solves=$(initial.line_solves) guesses=$(initial.guesses)"]
    append!(lines, log)
    push!(lines, "# final status=$(a.status) difficulty=$(a.difficulty) hints=$(length(givens)) line_solves=$(a.line_solves) guesses=$(a.guesses)")
    append!(lines, ["PUZZLE $name", "SIZE $w $h", "ROWS"])
    append!(lines, spaced.(rows))
    push!(lines, "COLUMNS")
    append!(lines, spaced.(columns))
    for (r, c, value) in sort(givens)
        push!(lines, "GIVEN $r $c $(state_char(value))")
    end
    push!(lines, "END")
    (lines=lines, unique=initial.status == "unique", logic=initial.difficulty in ("easy", "medium"), hints=length(givens))
end
function process_pictures(blocks, reports)
    names = Set{String}()
    paragraphs = Vector{String}[]
    invalid = unique = logic = hinted = hints = 0
    for block in blocks
        name, rows = block[1][9:end], block[2:end]
        reason = validate_picture(name, rows, names)
        push!(names, name)
        if reason !== nothing
            invalid += 1
            push!(paragraphs, ["# picture $name error $reason"])
            continue
        end
        result = generate_picture(name, state_grid(rows), reports)
        push!(paragraphs, result.lines)
        unique += result.unique
        logic += result.logic
        hinted += result.hints > 0
        hints += result.hints
    end
    push!(paragraphs, ["# SUMMARY pictures=$(length(blocks)) invalid=$invalid unique=$unique line_logic=$logic hinted=$hinted hints=$hints"])
    join_paragraphs(paragraphs)
end
function main()
    reports, solutions, stats = process_puzzles(read_blocks("input/puzzles.txt"))
    generated = process_pictures(read_blocks("input/pictures.txt"), reports)
    mkpath("output")
    for (name, lines) in zip(["solutions.txt", "stats.csv", "generated.txt"], [solutions, stats, generated])
        open(joinpath("output", name), "w") do io
            for line in lines
                println(io, line)
            end
        end
    end
end
main()
