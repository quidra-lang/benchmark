const DATA_COMMANDS = ("FILE", "PATCH", "EDIT")
const FORMATS_WITH_ARGUMENT = ("IFDEF", "UNIFIED", "CONTEXT", "SIDE")
const OFFSETS = (0, 1, -1, 2, -2, 3, -3)
const GRAPH_WIDTH = 20
const NUMBER_PAIR = r"^([0-9]{1,4})(?:,([0-9]{1,4}))?$"
const MARKER_PREFIXES = Dict("<<<<<<<" => "start", "|||||||" => "base", ">>>>>>>" => "end")
const SEPARATOR = "======="

struct CommandError <: Exception
    message::String
end

function range_r(start, count)
    if count >= 2
        return "$(start + 1),$(start + count)"
    elseif count == 1
        return string(start + 1)
    end
    return string(start)
end

function range_u(start, count)
    if count >= 2
        return "$(start + 1),$count"
    elseif count == 1
        return string(start + 1)
    end
    return "$start,0"
end

range_m(start, count) = "$(start + 1),$count"

function comparison_key(line, options)
    if "ICASE" in options
        line = lowercase(line)
    end
    if "IWHITE" in options
        line = replace(line, " " => "")
    end
    if "ISPACE" in options
        line = replace(line, r" {2,}" => " ")
    end
    return line
end

function matched_pairs(first, second)
    rows, columns = length(first), length(second)
    table = zeros(Int, rows + 1, columns + 1)
    for i in 1:rows, j in 1:columns
        if first[i] == second[j]
            table[i+1, j+1] = table[i, j] + 1
        else
            table[i+1, j+1] = max(table[i, j+1], table[i+1, j])
        end
    end
    pairs = [(rows + 1, columns + 1)]
    i, j = rows, columns
    while i >= 1 && j >= 1
        if first[i] == second[j]
            push!(pairs, (i, j))
            i -= 1
            j -= 1
        elseif table[i, j+1] >= table[i+1, j]
            i -= 1
        else
            j -= 1
        end
    end
    push!(pairs, (0, 0))
    return reverse!(pairs)
end

struct ChangeBlock
    p::Int
    q::Int
    x::Int
    y::Int
end

function letter(block::ChangeBlock)
    if block.x >= 1 && block.y >= 1
        return "c"
    end
    return block.y == 0 ? "d" : "a"
end

function change_blocks(first, second)
    pairs = matched_pairs(first, second)
    blocks = ChangeBlock[]
    for ((i, j), (next_i, next_j)) in zip(pairs, pairs[2:end])
        if next_i - i > 1 || next_j - j > 1
            push!(blocks, ChangeBlock(i, j, next_i - i - 1, next_j - j - 1))
        end
    end
    return blocks
end

struct WalkStep
    old_index::Int
    new_index::Int
    block::Union{ChangeBlock,Nothing}
end

function walk(blocks, old_start, new_start, old_end)
    entries = WalkStep[]
    old_index, new_index = old_start, new_start
    for block in blocks
        while old_index < block.p
            push!(entries, WalkStep(old_index, new_index, nothing))
            old_index += 1
            new_index += 1
        end
        push!(entries, WalkStep(old_index, new_index, block))
        old_index, new_index = block.p + block.x, block.q + block.y
    end
    while old_index < old_end
        push!(entries, WalkStep(old_index, new_index, nothing))
        old_index += 1
        new_index += 1
    end
    return entries
end

function side_row(left, symbol, right, width)
    return rstrip(rpad(first(left, width), width) * " " * symbol * " " * first(right, width))
end

function stat_graph(inserted, deleted)
    total = inserted + deleted
    plus, minus = inserted, deleted
    if total > GRAPH_WIDTH
        plus = div(GRAPH_WIDTH * inserted, total)
        minus = div(GRAPH_WIDTH * deleted, total)
        if inserted >= 1 && plus == 0
            plus = 1
        end
        if deleted >= 1 && minus == 0
            minus = 1
        end
    end
    return "+"^plus * "-"^minus
end

struct Hunk
    blocks::Vector{ChangeBlock}
    old_start::Int
    old_count::Int
    new_start::Int
    new_count::Int
end

function Hunk(blocks::Vector{ChangeBlock}, context::Int, old_total::Int)
    first_block, last_block = blocks[1], blocks[end]
    before = min(context, first_block.p)
    after = min(context, old_total - last_block.p - last_block.x)
    old_start = first_block.p - before
    new_start = first_block.q - before
    old_count = last_block.p + last_block.x + after - old_start
    new_count = last_block.q + last_block.y + after - new_start
    return Hunk(blocks, old_start, old_count, new_start, new_count)
end

function hunk_steps(hunk::Hunk)
    return walk(hunk.blocks, hunk.old_start, hunk.new_start, hunk.old_start + hunk.old_count)
end

struct LineDiff
    old_lines::Vector{String}
    new_lines::Vector{String}
    blocks::Vector{ChangeBlock}
end

function line_diff(old_lines, new_lines, options=())
    blocks = change_blocks(
        [comparison_key(line, options) for line in old_lines],
        [comparison_key(line, options) for line in new_lines],
    )
    return LineDiff(old_lines, new_lines, blocks)
end

deleted_lines(changes::LineDiff, block) = changes.old_lines[block.p+1:block.p+block.x]

inserted_lines(changes::LineDiff, block) = changes.new_lines[block.q+1:block.q+block.y]

function group_hunks(changes::LineDiff, context)
    groups = Vector{ChangeBlock}[]
    for block in changes.blocks
        if !isempty(groups)
            previous = groups[end][end]
            if block.p - (previous.p + previous.x) <= 2 * context
                push!(groups[end], block)
                continue
            end
        end
        push!(groups, [block])
    end
    return [Hunk(group, context, length(changes.old_lines)) for group in groups]
end

function normal_diff(changes::LineDiff)
    lines = String[]
    for block in changes.blocks
        code = letter(block)
        push!(lines, range_r(block.p, block.x) * code * range_r(block.q, block.y))
        append!(lines, "< " .* deleted_lines(changes, block))
        if code == "c"
            push!(lines, "---")
        end
        append!(lines, "> " .* inserted_lines(changes, block))
    end
    return lines
end

function ed_script(changes::LineDiff)
    lines = String[]
    for block in Iterators.reverse(changes.blocks)
        code = letter(block)
        push!(lines, range_r(block.p, block.x) * code)
        if code != "d"
            append!(lines, inserted_lines(changes, block))
            push!(lines, ".")
        end
    end
    return lines
end

function rcs_diff(changes::LineDiff)
    lines = String[]
    for block in changes.blocks
        if block.x >= 1
            push!(lines, "d$(block.p + 1) $(block.x)")
        end
        if block.y >= 1
            push!(lines, "a$(block.p + block.x) $(block.y)")
            append!(lines, inserted_lines(changes, block))
        end
    end
    return lines
end

function ifdef_diff(changes::LineDiff, macro_name)
    lines = String[]
    for entry in walk(changes.blocks, 0, 0, length(changes.old_lines))
        block = entry.block
        if block === nothing
            push!(lines, changes.old_lines[entry.old_index+1])
        elseif block.x >= 1 && block.y >= 1
            push!(lines, "#ifndef $macro_name")
            append!(lines, deleted_lines(changes, block))
            push!(lines, "#else /* $macro_name */")
            append!(lines, inserted_lines(changes, block))
            push!(lines, "#endif /* $macro_name */")
        elseif block.y == 0
            push!(lines, "#ifndef $macro_name")
            append!(lines, deleted_lines(changes, block))
            push!(lines, "#endif /* ! $macro_name */")
        else
            push!(lines, "#ifdef $macro_name")
            append!(lines, inserted_lines(changes, block))
            push!(lines, "#endif /* $macro_name */")
        end
    end
    return lines
end

function unified_diff(changes::LineDiff, context, old_name, new_name)
    lines = ["--- $old_name", "+++ $new_name"]
    for hunk in group_hunks(changes, context)
        old_range = range_u(hunk.old_start, hunk.old_count)
        new_range = range_u(hunk.new_start, hunk.new_count)
        push!(lines, "@@ -$old_range +$new_range @@")
        for entry in hunk_steps(hunk)
            if entry.block === nothing
                push!(lines, " " * changes.old_lines[entry.old_index+1])
            else
                append!(lines, "-" .* deleted_lines(changes, entry.block))
                append!(lines, "+" .* inserted_lines(changes, entry.block))
            end
        end
    end
    return lines
end

function context_diff(changes::LineDiff, context, old_name, new_name)
    lines = ["*** $old_name", "--- $new_name"]
    for hunk in group_hunks(changes, context)
        push!(lines, "*"^15)
        push!(lines, "*** $(range_r(hunk.old_start, hunk.old_count)) ****")
        if any(block -> block.x >= 1, hunk.blocks)
            for entry in hunk_steps(hunk)
                if entry.block === nothing
                    push!(lines, "  " * changes.old_lines[entry.old_index+1])
                else
                    marker = entry.block.y >= 1 ? "! " : "- "
                    append!(lines, marker .* deleted_lines(changes, entry.block))
                end
            end
        end
        push!(lines, "--- $(range_r(hunk.new_start, hunk.new_count)) ----")
        if any(block -> block.y >= 1, hunk.blocks)
            for entry in hunk_steps(hunk)
                if entry.block === nothing
                    push!(lines, "  " * changes.new_lines[entry.new_index+1])
                else
                    marker = entry.block.x >= 1 ? "! " : "+ "
                    append!(lines, marker .* inserted_lines(changes, entry.block))
                end
            end
        end
    end
    return lines
end

function side_by_side(changes::LineDiff, width)
    lines = String[]
    for entry in walk(changes.blocks, 0, 0, length(changes.old_lines))
        block = entry.block
        if block === nothing
            left = changes.old_lines[entry.old_index+1]
            right = changes.new_lines[entry.new_index+1]
            push!(lines, side_row(left, " ", right, width))
            continue
        end
        for row in 1:max(block.x, block.y)
            if row <= block.x && row <= block.y
                left = changes.old_lines[block.p+row]
                symbol = "|"
                right = changes.new_lines[block.q+row]
            elseif row <= block.x
                left, symbol, right = changes.old_lines[block.p+row], "<", ""
            else
                left, symbol, right = "", ">", changes.new_lines[block.q+row]
            end
            push!(lines, side_row(left, symbol, right, width))
        end
    end
    return lines
end

mutable struct TokenTotals
    deleted::Int
    inserted::Int
    common::Int
end

split_tokens(line, by_word) = by_word ? split(line) : split(line, "")

deletion(tokens, separator) = "[-" * join(tokens, separator) * "-]"

insertion(tokens, separator) = "{+" * join(tokens, separator) * "+}"

function compare_tokens(old_tokens, new_tokens, separator, totals)
    parts = String[]
    for entry in walk(change_blocks(old_tokens, new_tokens), 0, 0, length(old_tokens))
        block = entry.block
        if block === nothing
            push!(parts, old_tokens[entry.old_index+1])
            totals.common += 1
            continue
        end
        if block.x >= 1
            push!(parts, deletion(old_tokens[block.p+1:block.p+block.x], separator))
        end
        if block.y >= 1
            push!(parts, insertion(new_tokens[block.q+1:block.q+block.y], separator))
        end
        totals.deleted += block.x
        totals.inserted += block.y
    end
    return join(parts, separator)
end

struct BodyLine
    kind::Char
    text::String
end

struct PatchHunk
    line_number::Int
    old_start::Int
    old_count::Int
    new_start::Int
    new_count::Int
    body::Vector{BodyLine}
end

function sequences(hunk::PatchHunk, reversed)
    old_kinds = reversed ? (' ', '+') : (' ', '-')
    new_kinds = reversed ? (' ', '-') : (' ', '+')
    old_sequence = [line.text for line in hunk.body if line.kind in old_kinds]
    new_sequence = [line.text for line in hunk.body if line.kind in new_kinds]
    return old_sequence, new_sequence
end

start_line(hunk::PatchHunk, reversed) = reversed ? hunk.new_start : hunk.old_start

function leading_context(hunk::PatchHunk)
    index = findfirst(line -> line.kind != ' ', hunk.body)
    return index === nothing ? length(hunk.body) : index - 1
end

function trailing_context(hunk::PatchHunk)
    index = findlast(line -> line.kind != ' ', hunk.body)
    return index === nothing ? length(hunk.body) : length(hunk.body) - index
end

struct HunkMatch
    fuzz::Int
    delta::Int
    position::Int
    lines::Vector{String}
end

function report(found::HunkMatch, number)
    text = "Hunk #$number succeeded at $(found.position + 1)"
    if found.fuzz >= 1
        text *= " with fuzz $(found.fuzz)"
    end
    if found.delta in (1, -1)
        text *= " (offset $(found.delta) line)"
    elseif found.delta != 0
        text *= " (offset $(found.delta) lines)"
    end
    return text
end

function parse_range(text, sign)
    startswith(text, sign) || return nothing
    m = match(NUMBER_PAIR, text[2:end])
    m === nothing && return nothing
    start = parse(Int, m[1])
    count = m[2] === nothing ? 1 : parse(Int, m[2])
    if start == 0 && count != 0
        return nothing
    end
    return start, count
end

function parse_hunk_header(line, line_number)
    parts = split(line, " ")
    old_range = new_range = nothing
    if length(parts) == 4 && parts[1] == "@@" && parts[4] == "@@"
        old_range = parse_range(parts[2], "-")
        new_range = parse_range(parts[3], "+")
    end
    if old_range === nothing || new_range === nothing
        throw(CommandError("PATCH ERROR line $line_number: bad hunk header"))
    end
    return PatchHunk(line_number, old_range..., new_range..., BodyLine[])
end

function parse_patch(patch_lines)
    index = findfirst(line -> startswith(line, "@@"), patch_lines)
    index === nothing && throw(CommandError("PATCH ERROR no hunks"))
    hunks = PatchHunk[]
    while index <= length(patch_lines)
        hunk = parse_hunk_header(patch_lines[index], index)
        index += 1
        old_seen = new_seen = 0
        while old_seen < hunk.old_count || new_seen < hunk.new_count
            if index > length(patch_lines)
                throw(CommandError("PATCH ERROR line $(hunk.line_number): truncated hunk"))
            end
            line = patch_lines[index]
            kind = line[1]
            in_old = kind in (' ', '-')
            in_new = kind in (' ', '+')
            if length(line) < 2 ||
               !(in_old || in_new) ||
               (in_old && old_seen == hunk.old_count) ||
               (in_new && new_seen == hunk.new_count)
                throw(CommandError("PATCH ERROR line $index: bad hunk line"))
            end
            push!(hunk.body, BodyLine(kind, line[2:end]))
            if in_old
                old_seen += 1
            end
            if in_new
                new_seen += 1
            end
            index += 1
        end
        if all(line -> line.kind == ' ', hunk.body)
            throw(CommandError("PATCH ERROR line $(hunk.line_number): no changes"))
        end
        push!(hunks, hunk)
    end
    return hunks
end

function search_hunk(hunk, lines, adjustment, reversed, max_fuzz)
    old_sequence, new_sequence = sequences(hunk, reversed)
    start = start_line(hunk, reversed)
    expected = isempty(old_sequence) ? start + adjustment : start - 1 + adjustment
    leading, trailing = leading_context(hunk), trailing_context(hunk)
    for fuzz in 0:max_fuzz
        head = min(fuzz, leading)
        tail = min(fuzz, trailing)
        old_part = old_sequence[head+1:end-tail]
        new_part = new_sequence[head+1:end-tail]
        for delta in OFFSETS
            position = expected + head + delta
            stop = position + length(old_part)
            if position < 0 || stop > length(lines)
                continue
            end
            if lines[position+1:stop] == old_part
                result = [lines[1:position]; new_part; lines[stop+1:end]]
                return HunkMatch(fuzz, delta, position, result)
            end
        end
    end
    return nothing
end

function parse_edit_command(line)
    instruction, address = line[end], line[1:end-1]
    m = match(NUMBER_PAIR, address)
    if !(instruction in ('a', 'c', 'd')) || m === nothing
        return nothing
    end
    if instruction == 'a' && m[2] !== nothing
        return nothing
    end
    first_line = parse(Int, m[1])
    last_line = m[2] === nothing ? first_line : parse(Int, m[2])
    return instruction, first_line, last_line
end

function run_edit_script(lines, script)
    lines = copy(lines)
    executed = 0
    index = 1
    while index <= length(script)
        line_number = index
        command = parse_edit_command(script[index])
        if command === nothing
            throw(CommandError("EDIT ERROR line $line_number: bad command"))
        end
        instruction, first_line, last_line = command
        if instruction == 'a'
            valid = first_line <= length(lines)
        else
            valid = 1 <= first_line <= last_line <= length(lines)
        end
        if !valid
            throw(CommandError("EDIT ERROR line $line_number: bad range"))
        end
        index += 1
        text = String[]
        if instruction in ('a', 'c')
            stop = findnext(==("."), script, index)
            if stop === nothing
                throw(CommandError("EDIT ERROR line $line_number: missing terminator"))
            end
            text = script[index:stop-1]
            index = stop + 1
        end
        if instruction == 'a'
            splice!(lines, first_line+1:first_line, text)
        elseif instruction == 'c'
            splice!(lines, first_line:last_line, text)
        else
            deleteat!(lines, first_line:last_line)
        end
        executed += 1
    end
    return lines, executed
end

struct Chunk
    kind::Symbol
    base_start::Int
    ours_start::Int
    theirs_start::Int
    base::Vector{String}
    ours::Vector{String}
    theirs::Vector{String}
end

function location(chunk::Chunk)
    return "base $(range_m(chunk.base_start, length(chunk.base)))" *
           " a $(range_m(chunk.ours_start, length(chunk.ours)))" *
           " b $(range_m(chunk.theirs_start, length(chunk.theirs)))"
end

function chunk_kind(base, ours, theirs)
    if ours == base
        return :b
    elseif theirs == base
        return :a
    elseif ours == theirs
        return :both
    end
    return :conflict
end

function match_table(first, second)
    matches = zeros(Int, length(first))
    for (i, j) in matched_pairs(first, second)[2:end-1]
        matches[i] = j
    end
    return matches
end

function three_way_chunks(base, ours, theirs)
    ours_match = match_table(base, ours)
    theirs_match = match_table(base, theirs)
    chunks = Chunk[]
    x = y = z = 0
    while x < length(base) || y < length(ours) || z < length(theirs)
        if x < length(base) && ours_match[x+1] == y + 1 && theirs_match[x+1] == z + 1
            push!(chunks, Chunk(:stable, x, y, z, base[x+1:x+1], ours[y+1:y+1], theirs[z+1:z+1]))
            x += 1
            y += 1
            z += 1
            continue
        end
        anchor = x + 1
        while anchor <= length(base) && (ours_match[anchor] == 0 || theirs_match[anchor] == 0)
            anchor += 1
        end
        if anchor <= length(base)
            next_x, next_y, next_z = anchor - 1, ours_match[anchor] - 1, theirs_match[anchor] - 1
        else
            next_x, next_y, next_z = length(base), length(ours), length(theirs)
        end
        base_part, ours_part, theirs_part = base[x+1:next_x], ours[y+1:next_y], theirs[z+1:next_z]
        kind = chunk_kind(base_part, ours_part, theirs_part)
        push!(chunks, Chunk(kind, x, y, z, base_part, ours_part, theirs_part))
        x, y, z = next_x, next_y, next_z
    end
    return chunks
end

function kind_counts(chunks)
    tally(kind) = count(chunk -> chunk.kind == kind, chunks)
    return "a=$(tally(:a)) b=$(tally(:b)) both=$(tally(:both)) conflicts=$(tally(:conflict))"
end

function common_prefix_length(first, second)
    length_so_far = 0
    while length_so_far < min(length(first), length(second)) &&
          first[length_so_far+1] == second[length_so_far+1]
        length_so_far += 1
    end
    return length_so_far
end

function common_suffix_length(first, second, limit)
    length_so_far = 0
    while length_so_far < limit && first[end-length_so_far] == second[end-length_so_far]
        length_so_far += 1
    end
    return length_so_far
end

function conflict_lines(chunk::Chunk, mode, base_name, ours_name, theirs_name)
    if mode == "OURS"
        return chunk.ours
    elseif mode == "THEIRS"
        return chunk.theirs
    elseif mode == "DIFF3"
        return [
            "<<<<<<< $ours_name"; chunk.ours; "||||||| $base_name"; chunk.base
            SEPARATOR; chunk.theirs; ">>>>>>> $theirs_name"
        ]
    end
    ours, theirs = chunk.ours, chunk.theirs
    head = common_prefix_length(ours, theirs)
    tail = common_suffix_length(ours, theirs, min(length(ours), length(theirs)) - head)
    ours_middle = ours[head+1:end-tail]
    theirs_middle = theirs[head+1:end-tail]
    if mode == "UNION"
        middle = [ours_middle; theirs_middle]
    else
        middle = [
            "<<<<<<< $ours_name"; ours_middle; SEPARATOR; theirs_middle; ">>>>>>> $theirs_name"
        ]
    end
    return [ours[1:head]; middle; ours[end-tail+1:end]]
end

function marker_kind(line)
    line == SEPARATOR && return "separator"
    if length(line) >= 7 && (length(line) == 7 || line[8] == ' ')
        return get(MARKER_PREFIXES, line[1:7], nothing)
    end
    return nothing
end

next_marker(lines, index) = findnext(line -> marker_kind(line) !== nothing, lines, index + 1)

struct ConflictRegion
    start_line::Int
    end_line::Int
    ours::Vector{String}
    base::Union{Vector{String},Nothing}
    theirs::Vector{String}
end

function part(region::ConflictRegion, side)
    if side == "OURS"
        return region.ours
    elseif side == "THEIRS"
        return region.theirs
    elseif side == "BASE"
        return region.base
    end
    return [region.ours; region.theirs]
end

function region_at(lines, start)
    marker_kind(lines[start]) == "start" || return nothing
    middle = next_marker(lines, start)
    base_marker = nothing
    if middle !== nothing && marker_kind(lines[middle]) == "base"
        base_marker = middle
        middle = next_marker(lines, middle)
    end
    if middle === nothing || marker_kind(lines[middle]) != "separator"
        return nothing
    end
    stop = next_marker(lines, middle)
    if stop === nothing || marker_kind(lines[stop]) != "end"
        return nothing
    end
    if base_marker === nothing
        ours, base = lines[start+1:middle-1], nothing
    else
        ours, base = lines[start+1:base_marker-1], lines[base_marker+1:middle-1]
    end
    return ConflictRegion(start, stop, ours, base, lines[middle+1:stop-1])
end

function conflict_regions(lines)
    regions = ConflictRegion[]
    index = 1
    while index <= length(lines)
        region = region_at(lines, index)
        if region === nothing
            index += 1
        else
            push!(regions, region)
            index = region.end_line + 1
        end
    end
    return regions
end

const Snapshot = Union{Vector{String},Nothing}

struct Workspace
    files::Dict{String,Vector{String}}
    history::Dict{String,Vector{Snapshot}}
end

Workspace() = Workspace(Dict{String,Vector{String}}(), Dict{String,Vector{Snapshot}}())

print_prefixed(prefix, lines) = foreach(line -> println(prefix, line), lines)

function require(workspace::Workspace, names...)
    for name in names
        haskey(workspace.files, name) || throw(CommandError("ERROR no such file $name"))
    end
end

function save!(workspace::Workspace, name, lines)
    push!(get!(workspace.history, name, Snapshot[]), get(workspace.files, name, nothing))
    workspace.files[name] = copy(lines)
end

function file_command!(workspace, arguments, data)
    name = arguments[1]
    save!(workspace, name, data)
    println("FILE $name lines=$(length(data))")
end

function copy_command!(workspace, arguments)
    source, target = arguments
    require(workspace, source)
    lines = workspace.files[source]
    save!(workspace, target, lines)
    println("COPY $source $target lines=$(length(lines))")
end

function print_command(workspace, arguments)
    name = arguments[1]
    require(workspace, name)
    lines = workspace.files[name]
    println("PRINT $name lines=$(length(lines))")
    for (number, line) in enumerate(lines)
        println(lpad(number, 3), "| ", line)
    end
end

function files_command(workspace, arguments)
    println("FILES count=$(length(workspace.files))")
    for name in sort(collect(keys(workspace.files)))
        lines = workspace.files[name]
        println("$name lines=$(length(lines)) undo=$(length(workspace.history[name]))")
    end
end

function undo_command!(workspace, arguments)
    name = arguments[1]
    states = get(workspace.history, name, Snapshot[])
    isempty(states) && throw(CommandError("ERROR nothing to undo $name"))
    state = pop!(states)
    if state === nothing
        delete!(workspace.files, name)
        println("UNDO $name removed")
    else
        workspace.files[name] = state
        println("UNDO $name lines=$(length(state))")
    end
end

function diff_command(workspace, arguments)
    old_name, new_name, form = arguments[1:3]
    require(workspace, old_name, new_name)
    parameter = nothing
    options = arguments[4:end]
    if form in FORMATS_WITH_ARGUMENT
        parameter = arguments[4]
        options = arguments[5:end]
    end
    changes = line_diff(workspace.files[old_name], workspace.files[new_name], options)
    if isempty(changes.blocks)
        println("Files $old_name and $new_name are identical")
    elseif form == "BRIEF"
        println("Files $old_name and $new_name differ")
    elseif form == "NORMAL"
        foreach(println, normal_diff(changes))
    elseif form == "ED"
        foreach(println, ed_script(changes))
    elseif form == "RCS"
        foreach(println, rcs_diff(changes))
    elseif form == "IFDEF"
        foreach(println, ifdef_diff(changes, parameter))
    elseif form == "UNIFIED"
        foreach(println, unified_diff(changes, parse(Int, parameter), old_name, new_name))
    elseif form == "CONTEXT"
        foreach(println, context_diff(changes, parse(Int, parameter), old_name, new_name))
    else
        foreach(println, side_by_side(changes, parse(Int, parameter)))
    end
end

function token_diff_command(workspace, arguments, by_word)
    old_name, new_name = arguments
    require(workspace, old_name, new_name)
    old_lines, new_lines = workspace.files[old_name], workspace.files[new_name]
    changes = line_diff(old_lines, new_lines)
    if isempty(changes.blocks)
        println("Files $old_name and $new_name are identical")
        return
    end
    separator = by_word ? " " : ""
    totals = TokenTotals(0, 0, 0)
    for block in changes.blocks, row in 1:max(block.x, block.y)
        old_number, new_number = block.p + row, block.q + row
        if row <= block.x && row <= block.y
            old_tokens = split_tokens(old_lines[old_number], by_word)
            new_tokens = split_tokens(new_lines[new_number], by_word)
            text = compare_tokens(old_tokens, new_tokens, separator, totals)
            println("a$old_number b$new_number: $text")
        elseif row <= block.x
            old_tokens = split_tokens(old_lines[old_number], by_word)
            totals.deleted += length(old_tokens)
            println("a$old_number: $(deletion(old_tokens, separator))")
        else
            new_tokens = split_tokens(new_lines[new_number], by_word)
            totals.inserted += length(new_tokens)
            println("b$new_number: $(insertion(new_tokens, separator))")
        end
    end
    label = by_word ? "WORDS" : "CHARS"
    println("$label deleted=$(totals.deleted) inserted=$(totals.inserted) common=$(totals.common)")
end

function stat_command(workspace, arguments)
    old_name, new_name = arguments[1:2]
    require(workspace, old_name, new_name)
    old_lines, new_lines = workspace.files[old_name], workspace.files[new_name]
    changes = line_diff(old_lines, new_lines, arguments[3:end])
    deleted = sum(block -> block.x, changes.blocks; init=0)
    inserted = sum(block -> block.y, changes.blocks; init=0)
    total = deleted + inserted
    unchanged = length(old_lines) - deleted
    summary = "$old_name -> $new_name | $total"
    if total > 0
        summary *= " " * stat_graph(inserted, deleted)
    end
    println(summary)
    line_total = length(old_lines) + length(new_lines)
    similarity = line_total > 0 ? div(200 * unchanged, line_total) : 100
    println(
        "changes=$(length(changes.blocks)) insertions=$inserted deletions=$deleted",
        " unchanged=$unchanged similarity=$similarity%",
    )
end

function patch_command!(workspace, arguments, data)
    name = arguments[1]
    require(workspace, name)
    options = arguments[3:end]
    reversed = "REVERSE" in options
    dry_run = "DRYRUN" in options
    fuzz_index = findfirst(==("FUZZ"), options)
    max_fuzz = fuzz_index === nothing ? 0 : parse(Int, options[fuzz_index+1])
    hunks = parse_patch(data)
    println(dry_run ? "checking file " : "patching file ", name)
    lines = workspace.files[name]
    first_hunk = hunks[1]
    if search_hunk(first_hunk, lines, 0, reversed, max_fuzz) === nothing &&
       search_hunk(first_hunk, lines, 0, !reversed, max_fuzz) !== nothing
        println("Reversed (or previously applied) patch detected! Skipping patch.")
        println("RESULT applied=0 failed=0 ignored=$(length(hunks)) lines=$(length(lines))")
        return
    end
    adjustment = applied = failed = 0
    for (number, hunk) in enumerate(hunks)
        found = search_hunk(hunk, lines, adjustment, reversed, max_fuzz)
        if found === nothing
            failed += 1
            println("Hunk #$number FAILED at $(start_line(hunk, reversed))")
            continue
        end
        old_sequence, new_sequence = sequences(hunk, reversed)
        lines = found.lines
        adjustment += found.delta + length(new_sequence) - length(old_sequence)
        applied += 1
        println(report(found, number))
    end
    println("RESULT applied=$applied failed=$failed ignored=0 lines=$(length(lines))")
    if !dry_run && applied >= 1
        save!(workspace, name, lines)
    end
end

function edit_command!(workspace, arguments, data)
    name = arguments[1]
    require(workspace, name)
    lines, executed = run_edit_script(workspace.files[name], data)
    println("EDIT $name commands=$executed lines=$(length(lines))")
    save!(workspace, name, lines)
end

function three_way(workspace, base_name, ours_name, theirs_name)
    require(workspace, base_name, ours_name, theirs_name)
    files = workspace.files
    return three_way_chunks(files[base_name], files[ours_name], files[theirs_name])
end

function diff3_command(workspace, arguments)
    base_name, ours_name, theirs_name = arguments
    chunks = three_way(workspace, base_name, ours_name, theirs_name)
    changes = filter(chunk -> chunk.kind != :stable, chunks)
    for chunk in changes
        println("==== $(chunk.kind) $(location(chunk))")
        print_prefixed("O ", chunk.base)
        if chunk.kind != :b
            print_prefixed("A ", chunk.ours)
        end
        if chunk.kind in (:b, :conflict)
            print_prefixed("B ", chunk.theirs)
        end
    end
    println("DIFF3 chunks=$(length(changes)) $(kind_counts(chunks))")
end

function merge_command!(workspace, arguments)
    base_name, ours_name, theirs_name, target = arguments[1:4]
    mode = length(arguments) == 5 ? arguments[5] : "MARKERS"
    chunks = three_way(workspace, base_name, ours_name, theirs_name)
    result = String[]
    conflicts = Chunk[]
    for chunk in chunks
        if chunk.kind == :b
            append!(result, chunk.theirs)
        elseif chunk.kind == :conflict
            append!(result, conflict_lines(chunk, mode, base_name, ours_name, theirs_name))
            push!(conflicts, chunk)
        else
            append!(result, chunk.ours)
        end
    end
    println("MERGE $target lines=$(length(result)) $(kind_counts(chunks))")
    for (number, chunk) in enumerate(conflicts)
        println("CONFLICT $number $(location(chunk))")
    end
    save!(workspace, target, result)
end

function conflicts_command(workspace, arguments)
    name = arguments[1]
    require(workspace, name)
    regions = conflict_regions(workspace.files[name])
    println("CONFLICTS $name count=$(length(regions))")
    for (number, region) in enumerate(regions)
        base = region.base === nothing ? "none" : length(region.base)
        println(
            "$number: lines $(region.start_line)-$(region.end_line) ours=$(length(region.ours))",
            " base=$base theirs=$(length(region.theirs))",
        )
    end
end

function resolve_command!(workspace, arguments)
    name, number_text, side = arguments
    require(workspace, name)
    number = parse(Int, number_text)
    lines = workspace.files[name]
    regions = conflict_regions(lines)
    if length(regions) < number
        throw(CommandError("ERROR no conflict $number in $name"))
    end
    region = regions[number]
    if side == "BASE" && region.base === nothing
        throw(CommandError("ERROR no base section in conflict $number"))
    end
    content = [lines[1:region.start_line-1]; part(region, side); lines[region.end_line+1:end]]
    remaining = length(conflict_regions(content))
    println("RESOLVE $name $number $side lines=$(length(content)) remaining=$remaining")
    save!(workspace, name, content)
end

const HANDLERS = Dict(
    "FILE" => file_command!,
    "COPY" => copy_command!,
    "PRINT" => print_command,
    "FILES" => files_command,
    "DIFF" => diff_command,
    "WORDDIFF" => (workspace, arguments) -> token_diff_command(workspace, arguments, true),
    "CHARDIFF" => (workspace, arguments) -> token_diff_command(workspace, arguments, false),
    "STAT" => stat_command,
    "PATCH" => patch_command!,
    "EDIT" => edit_command!,
    "DIFF3" => diff3_command,
    "MERGE" => merge_command!,
    "CONFLICTS" => conflicts_command,
    "RESOLVE" => resolve_command!,
    "UNDO" => undo_command!,
)

function execute!(workspace, words, data)
    command, arguments = words[1], words[2:end]
    handler = HANDLERS[command]
    try
        if command in DATA_COMMANDS
            handler(workspace, arguments, data)
        else
            handler(workspace, arguments)
        end
    catch error
        error isa CommandError || rethrow()
        println(error.message)
    end
end

function main()
    lines = readlines(stdin)
    workspace = Workspace()
    position = 2
    for _ in 1:parse(Int, lines[1])
        words = String.(split(lines[position], " "))
        position += 1
        data = String[]
        if words[1] in DATA_COMMANDS
            line_count = parse(Int, words[3])
            data = lines[position:position+line_count-1]
            position += line_count
        end
        execute!(workspace, words, data)
    end
end

main()
