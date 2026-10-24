@enum TokenKind NumberToken OffsetToken CurrentToken LastToken CommaToken SemicolonToken WholeToken MarkToken ForwardToken BackwardToken
@enum CommandKind EmptyCommand AppendText InsertText ChangeText PrintText PrintNumbers PrintList PrintEqual CountText YankText ListMarks ListHistory ListFiles DeleteText PutText JoinText JoinWords PageText IndentText OutdentText UndoChange RedoChange ReadFile PrintWrite WriteFile AppendFile EditFile MarkLine MoveText CopyText SubstituteText ConvertCase SortText GlobalCommand InverseCommand

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))
digit(ch::Char) = '0' <= ch <= '9'
lower(ch::Char) = 'a' <= ch <= 'z'
part(text::String, first::Int, last::Int = lastindex(text)) = first > last ? "" : text[first:last]

struct Atom
    character::Char
    matched::Bool
end
struct Delimited
    text::String
    atoms::Vector{Atom}
    raw::String
    next::Int
end
Base.@kwdef struct Token
    kind::TokenKind
    value::Int = 0
    name::Char = '\0'
    search::String = ""
end
struct Scanned
    tokens::Vector{Token}
    tail::String
end
Base.@kwdef struct Addresses
    count::Int
    left::Vector{Token} = Token[]
    right::Vector{Token} = Token[]
    semicolon::Bool = false
end
struct LineRange
    first::Int
    last::Int
end

Base.@kwdef mutable struct Command
    kind::CommandKind
    amount::Int = 0
    suffix::Union{Nothing,Char} = nothing
    option::Char = '\0'
    name::String = ""
    search::String = ""
    destination::Vector{Token} = Token[]
    replacement::Union{Nothing,Vector{Atom}} = nothing
    all::Bool = false
    options::String = ""
    sub::Union{Nothing,Command} = nothing
end

const SIMPLE = Dict('a' => AppendText, 'i' => InsertText, 'c' => ChangeText, 'p' => PrintText,
                    'n' => PrintNumbers, 'l' => PrintList, '=' => PrintEqual, '#' => CountText,
                    'y' => YankText, 'K' => ListMarks, 'h' => ListHistory, 'f' => ListFiles)

function digits_end(text::String, position::Int)
    while position <= lastindex(text) && digit(text[position])
        position += 1
    end
    position
end

function delimited(text::String, position::Int, delimiter::Char)
    start = position
    atoms = Atom[]
    while position <= lastindex(text)
        ch = text[position]
        escaped = ch == '\\'
        if escaped
            position += 1
            position <= lastindex(text) || fail("missing delimiter")
            ch = text[position]
        elseif ch == delimiter
            return Delimited(join(atom.character for atom in atoms), atoms, part(text, start, position - 1), position + 1)
        end
        push!(atoms, Atom(ch, !escaped && ch == '&'))
        position += 1
    end
    fail("missing delimiter")
end

function scan_address(text::String)
    tokens = Token[]
    position = 1
    while position <= lastindex(text)
        ch = text[position]
        if digit(ch)
            stop = digits_end(text, position)
            token = Token(kind = NumberToken, value = parse(Int, part(text, position, stop - 1)))
            position = stop
        elseif ch == '+' || ch == '-'
            stop = digits_end(text, position + 1)
            magnitude = stop == position + 1 ? 1 : parse(Int, part(text, position + 1, stop - 1))
            token = Token(kind = OffsetToken, value = ch == '+' ? magnitude : -magnitude)
            position = stop
        elseif ch in ".\$,;%"
            kinds = (CurrentToken, LastToken, CommaToken, SemicolonToken, WholeToken)
            token = Token(kind = kinds[findfirst(==(ch), ".\$,;%")])
            position += 1
        elseif ch == '\''
            position += 1
            name = position <= lastindex(text) ? text[position] : '\0'
            token = Token(kind = MarkToken, name = name)
            position += name == '\0' ? 0 : 1
        elseif ch == '/' || ch == '?'
            found = delimited(text, position + 1, ch)
            token = Token(kind = ch == '/' ? ForwardToken : BackwardToken, search = found.text)
            position = found.next
        else
            break
        end
        push!(tokens, token)
    end
    Scanned(tokens, part(text, position))
end

function valid_address(tokens::Vector{Token})
    bases = (NumberToken, CurrentToken, LastToken, MarkToken, ForwardToken, BackwardToken)
    all(token.kind == OffsetToken || index == 1 && token.kind in bases for (index, token) in enumerate(tokens))
end

function address_form(tokens::Vector{Token})
    isempty(tokens) && return Addresses(count = 0)
    if length(tokens) == 1 && tokens[1].kind == WholeToken
        return Addresses(count = 2, left = [Token(kind = NumberToken, value = 1)], right = [Token(kind = LastToken)])
    end
    separators = findall(token -> token.kind in (CommaToken, SemicolonToken), tokens)
    length(separators) <= 1 || fail("bad address")
    if isempty(separators)
        valid_address(tokens) || fail("bad address")
        return Addresses(count = 1, left = tokens)
    end
    separator = separators[1]
    left = tokens[1:separator-1]
    right = tokens[separator+1:end]
    valid_address(left) && valid_address(right) || fail("bad address")
    Addresses(count = 2, left = left, right = right, semicolon = tokens[separator].kind == SemicolonToken)
end

function positive(argument::String)
    isempty(argument) && return 0
    all(digit, argument) || fail("invalid suffix")
    value = parse(Int, argument)
    value > 0 || fail("invalid suffix")
    value
end
function print_suffix(argument::String)
    isempty(argument) && return nothing
    length(argument) == 1 && argument[1] in "pnl" || fail("invalid suffix")
    argument[1]
end
function file_name(argument::String)
    2 <= length(argument) <= 9 && argument[1] == ' ' || fail("invalid file name")
    name = part(argument, 2)
    all(ch -> lower(ch) || digit(ch), name) || fail("invalid file name")
    name
end
sort_form(text::String) = text == "sort" || startswith(text, "sort ")

function parse_substitution(argument::String)
    command = Command(kind = SubstituteText, amount = 1)
    flags = argument
    if !all(ch -> ch in "gpnl" || digit(ch), argument)
        delimiter = argument[1]
        delimiter in " \\" && fail("missing delimiter")
        search = delimited(argument, 2, delimiter)
        replacement = delimited(argument, search.next, delimiter)
        command.search = search.text
        replacement.raw == "%" || (command.replacement = replacement.atoms)
        flags = part(argument, replacement.next)
    end
    position = 1
    counted = false
    while position <= lastindex(flags)
        ch = flags[position]
        position += 1
        if ch == 'g'
            command.all && fail("invalid suffix")
            command.all = true
        elseif ch in "pnl"
            isnothing(command.suffix) || fail("invalid suffix")
            command.suffix = ch
        elseif digit(ch)
            counted && fail("invalid suffix")
            counted = true
            start = position - 1
            position = digits_end(flags, position)
            command.amount = parse(Int, part(flags, start, position - 1))
            command.amount > 0 || fail("invalid suffix")
        else
            fail("invalid suffix")
        end
    end
    command
end

function parse_command(text::String)
    if sort_form(text)
        options = text == "sort" ? "" : part(text, 6)
        if text != "sort"
            !isempty(options) && all(ch -> ch in "ruin", options) && length(Set(options)) == length(options) || fail("invalid suffix")
            'i' in options && 'n' in options && fail("invalid suffix")
        end
        return Command(kind = SortText, options = options)
    end
    isempty(text) && return Command(kind = EmptyCommand)
    first = text[1]
    argument = part(text, 2)
    if haskey(SIMPLE, first)
        isempty(argument) || fail("invalid suffix")
        return Command(kind = SIMPLE[first])
    elseif first in "dxjJ"
        kinds = (DeleteText, PutText, JoinText, JoinWords)
        return Command(kind = kinds[findfirst(==(first), "dxjJ")], suffix = print_suffix(argument))
    elseif first in "z><u"
        kinds = (PageText, IndentText, OutdentText, UndoChange)
        return Command(kind = kinds[findfirst(==(first), "z><u")], amount = positive(argument))
    elseif first == '~'
        argument in ("", "u", "l") || fail("invalid suffix")
        return Command(kind = ConvertCase, option = isempty(argument) ? '\0' : argument[1])
    elseif first == 'r'
        all(digit, argument) && return Command(kind = RedoChange, amount = positive(argument))
        return Command(kind = ReadFile, name = file_name(argument))
    elseif first == 'w'
        isempty(argument) && return Command(kind = PrintWrite)
        return Command(kind = WriteFile, name = file_name(argument))
    elseif first == 'W' || first == 'e'
        return Command(kind = first == 'W' ? AppendFile : EditFile, name = file_name(argument))
    elseif first == 'k'
        length(argument) == 1 && lower(argument[1]) || fail("invalid mark")
        return Command(kind = MarkLine, option = argument[1])
    elseif first == 'm' || first == 't'
        destination = scan_address(argument)
        !isempty(destination.tokens) && valid_address(destination.tokens) || fail("invalid destination")
        return Command(kind = first == 'm' ? MoveText : CopyText, destination = destination.tokens, suffix = print_suffix(destination.tail))
    elseif first == 's'
        return parse_substitution(argument)
    elseif first == 'g' || first == 'v'
        !isempty(argument) && !(argument[1] in " \\") || fail("missing delimiter")
        search = delimited(argument, 2, argument[1])
        body = part(argument, search.next)
        isempty(body) && (body = "p")
        body[1] in "pnldmtjJs><~aicx" && !sort_form(body) || fail("invalid global command")
        return Command(kind = first == 'g' ? GlobalCommand : InverseCommand, search = search.text, sub = parse_command(body))
    end
    fail("unknown command")
end

function with_text(text::String)
    try
        tail = scan_address(text).tail
        tail in ("a", "i", "c") && return true
        length(tail) >= 2 && tail[1] in "gv" && !(tail[2] in " \\") || return false
        search = delimited(tail, 3, tail[2])
        part(tail, search.next) in ("a", "i", "c")
    catch error
        error isa CommandError || rethrow()
        false
    end
end

function address_kind(kind::CommandKind)
    kind in (UndoChange, RedoChange, ListHistory, ListMarks, ListFiles, EditFile) && return 0
    kind in (AppendText, InsertText, PutText, PrintEqual, ReadFile, MarkLine, PageText) ? 1 : 2
end
function modifying(command::Command)
    command.kind in (GlobalCommand, InverseCommand) && return modifying(command.sub::Command)
    command.kind in (AppendText, InsertText, ChangeText, DeleteText, PutText, JoinText, JoinWords,
                     MoveText, CopyText, SubstituteText, IndentText, OutdentText, ConvertCase, SortText, ReadFile, EditFile)
end

struct Line
    id::Int
    text::String
end
struct HistoryRecord
    source::String
    buffer::Vector{Line}
    current::Int
end
Base.@kwdef mutable struct State
    buffer::Vector{Line} = Line[]
    current::Int = 0
    marks::Vector{Int} = zeros(Int, 26)
    cut::Vector{String} = String[]
    pattern::Union{Nothing,String} = nothing
    replacement::Union{Nothing,Vector{Atom}} = nothing
    display::Int = 5
    undo::Vector{HistoryRecord} = HistoryRecord[]
    redo::Vector{HistoryRecord} = HistoryRecord[]
    files::Dict{String,Vector{String}} = Dict{String,Vector{String}}()
    next_id::Int = 1
end
Base.@kwdef mutable struct Editor
    state::State = State()
end

function fork(state::State)
    State(buffer = copy(state.buffer), current = state.current, marks = copy(state.marks), cut = state.cut,
          pattern = state.pattern, replacement = state.replacement, display = state.display,
          undo = copy(state.undo), redo = copy(state.redo), files = copy(state.files), next_id = state.next_id)
end
snapshot(state::State, source::String) = HistoryRecord(source, copy(state.buffer), state.current)
locate(state::State, identity::Int) = something(findfirst(line -> line.id == identity, state.buffer), 0)
function choose_pattern!(state::State, search::String)
    isempty(search) || (state.pattern = search)
    isnothing(state.pattern) && fail("no previous pattern")
    state.pattern::String
end

function address_value!(state::State, tokens::Vector{Token})
    value = state.current
    for token in tokens
        if token.kind == OffsetToken
            value += token.value
        elseif token.kind == NumberToken
            value = token.value
        elseif token.kind == CurrentToken
            value = state.current
        elseif token.kind == LastToken
            value = length(state.buffer)
        elseif token.kind == MarkToken
            lower(token.name) || fail("invalid mark")
            value = locate(state, state.marks[Int(token.name - 'a') + 1])
            value != 0 || fail("mark not set")
        else
            pattern = choose_pattern!(state, token.search)
            size = length(state.buffer)
            pivot = token.kind == BackwardToken && state.current == 0 ? size + 1 : state.current
            value = 0
            for step in 1:size
                index = token.kind == ForwardToken ? mod(pivot + step - 1, size) + 1 : mod(pivot - step - 1, size) + 1
                if occursin(pattern, state.buffer[index].text)
                    value = index
                    break
                end
            end
            value != 0 || fail("no match")
        end
    end
    value
end

function address_values!(state::State, form::Addresses)
    form.count == 0 && return Int[]
    left = isempty(form.left) ? (form.semicolon ? state.current : 1) : address_value!(state, form.left)
    form.count == 1 && return [left]
    if form.semicolon
        0 <= left <= length(state.buffer) || fail("address out of range")
        state.current = left
    end
    right = isempty(form.right) ? length(state.buffer) : address_value!(state, form.right)
    [left, right]
end

function checked_range(state::State, kind::CommandKind, values::Vector{Int})
    arity = address_kind(kind)
    size = length(state.buffer)
    arity == 0 && return LineRange(0, 0)
    if arity == 1
        first = isempty(values) ? (kind in (PrintEqual, ReadFile) ? size : state.current + (kind == PageText)) : values[1]
        minimum = kind in (MarkLine, PageText) ? 1 : 0
        minimum <= first <= size || fail("address out of range")
        return LineRange(first, first)
    end
    if !isempty(values)
        first = values[1]
        last = length(values) == 1 ? first : values[2]
    elseif kind in (PrintWrite, WriteFile, AppendFile, CountText)
        return LineRange(1, size)
    elseif kind in (GlobalCommand, InverseCommand, SortText)
        first, last = 1, size
    else
        first = state.current
        last = first + (kind in (JoinText, JoinWords))
    end
    1 <= first <= size && 1 <= last <= size || fail("address out of range")
    first <= last && (first != last || !(kind in (JoinText, JoinWords))) || fail("invalid range")
    LineRange(first, last)
end

contents(state::State, range::LineRange) = [line.text for line in state.buffer[range.first:range.last]]
function new_lines!(state::State, text::Vector{String})
    first = state.next_id
    state.next_id += length(text)
    [Line(first + index - 1, line) for (index, line) in enumerate(text)]
end
function replace_lines!(state::State, position::Int, count::Int, inserted::Vector{Line})
    state.buffer = [state.buffer[1:position]; inserted; state.buffer[position+count+1:end]]
end
function print_line!(output::Vector{String}, state::State, number::Int, form::Char)
    text = state.buffer[number].text
    if form == 'n'
        push!(output, lpad(string(number), 3) * " " * text)
    elseif form == 'l'
        escaped = replace(text, "\\" => "\\\\") * "\$"
        while length(escaped) > 40
            push!(output, escaped[1:39] * "\\")
            escaped = escaped[40:end]
        end
        push!(output, escaped)
    else
        push!(output, text)
    end
end
function suffix_line!(output::Vector{String}, state::State, suffix::Union{Nothing,Char})
    isnothing(suffix) || state.current == 0 || print_line!(output, state, state.current, suffix)
    nothing
end
byte_count(text::Vector{String}) = sum(line -> length(line) + 1, text; init = 0)
word_count(text::String) = length(split(text, ' '; keepempty = false))
leading_spaces(text::String) = length(text) - length(lstrip(text, ' '))
function letter_case(text::String, option::Char)
    option == 'u' && return uppercase(text)
    option == 'l' && return lowercase(text)
    join(lower(ch) ? uppercase(ch) : ('A' <= ch <= 'Z' ? lowercase(ch) : ch) for ch in text)
end
function leading_integer(text::String)
    start = text[1] == '-' ? 2 : 1
    stop = digits_end(text, start)
    start == stop && return 0
    magnitude = parse(Int, text[start:stop-1])
    start == 2 ? -magnitude : magnitude
end

function substitute!(state::State, command::Command, range::LineRange, output::Vector{String}, inside::Bool)
    pattern = choose_pattern!(state, command.search)
    replacement = isnothing(command.replacement) ? state.replacement : command.replacement
    isnothing(replacement) && fail("no previous substitution")
    state.replacement = replacement
    expanded = join(atom.matched ? pattern : string(atom.character) for atom in replacement)
    changed = 0
    for number in range.first:range.last
        original = state.buffer[number].text
        result = IOBuffer()
        position, occurrence = 1, 0
        replaced = false
        while true
            found = findnext(pattern, original, position)
            isnothing(found) && break
            print(result, part(original, position, first(found) - 1))
            occurrence += 1
            if occurrence == command.amount || command.all && occurrence > command.amount
                print(result, expanded)
                replaced = true
            else
                print(result, pattern)
            end
            position = last(found) + 1
        end
        if replaced
            print(result, part(original, position))
            text = String(take!(result))
            length(text) <= 80 || fail("line too long")
            !isempty(text) && !endswith(text, ' ') || fail("bad line")
            state.buffer[number] = Line(state.buffer[number].id, text)
            state.current = number
            changed += 1
        end
    end
    changed != 0 || inside || fail("no match")
    changed > 0 && suffix_line!(output, state, command.suffix)
    changed
end

function transfer_history!(state::State, redo::Bool, count::Int)
    source = redo ? state.redo : state.undo
    target = redo ? state.undo : state.redo
    length(source) >= count || fail(redo ? "nothing to redo" : "nothing to undo")
    for _ in 1:count
        saved = pop!(source)
        push!(target, snapshot(state, saved.source))
        state.buffer = copy(saved.buffer)
        state.current = saved.current
    end
end

function file_command!(state::State, command::Command, range::LineRange, output::Vector{String})
    text = get(state.files, command.name, nothing)
    if command.kind in (WriteFile, AppendFile)
        selected = contents(state, range)
        text = command.kind == AppendFile && !isnothing(text) ? [text; selected] : selected
        state.files[command.name] = text
    else
        isnothing(text) && fail("no such file")
        inserted = new_lines!(state, text)
        if command.kind == ReadFile
            replace_lines!(state, range.first, 0, inserted)
            state.current = range.first + length(text)
        else
            state.buffer = inserted
            state.current = length(text)
        end
    end
    push!(output, "file $(command.name) lines=$(length(text)) bytes=$(byte_count(text))")
end

function execute!(state::State, command::Command, range::LineRange, text::Vector{String}, output::Vector{String}; inside::Bool = false)
    kind = command.kind
    a, b = range.first, range.last
    if kind == EmptyCommand
        print_line!(output, state, b, 'p')
        state.current = b
    elseif kind in (PrintText, PrintNumbers, PrintList)
        form = kind == PrintText ? 'p' : (kind == PrintNumbers ? 'n' : 'l')
        for number in a:b
            print_line!(output, state, number, form)
        end
        state.current = b
    elseif kind == PageText
        command.amount == 0 || (state.display = command.amount)
        stop = min(length(state.buffer), a + state.display - 1)
        for number in a:stop
            print_line!(output, state, number, 'p')
        end
        state.current = stop
    elseif kind == PrintEqual
        push!(output, string(a))
    elseif kind == CountText
        selected = contents(state, range)
        words = sum(word_count, selected; init = 0)
        chars = sum(length, selected; init = 0)
        push!(output, "count lines=$(length(selected)) words=$words chars=$chars")
    elseif kind == PrintWrite
        selected = contents(state, range)
        append!(output, selected)
        push!(output, "lines=$(length(selected)) bytes=$(byte_count(selected))")
    elseif kind in (AppendText, InsertText)
        position = kind == AppendText ? a : max(a, 1) - 1
        replace_lines!(state, position, 0, new_lines!(state, text))
        state.current = position + length(text)
    elseif kind in (ChangeText, DeleteText)
        state.cut = contents(state, range)
        inserted = kind == ChangeText ? new_lines!(state, text) : Line[]
        replace_lines!(state, a - 1, b - a + 1, inserted)
        state.current = isempty(inserted) ? min(a, length(state.buffer)) : a + length(inserted) - 1
    elseif kind == YankText
        state.cut = contents(state, range)
    elseif kind == PutText
        isempty(state.cut) && fail("nothing to put")
        replace_lines!(state, a, 0, new_lines!(state, state.cut))
        state.current = a + length(state.cut)
    elseif kind in (MoveText, CopyText)
        destination = address_value!(state, command.destination)
        0 <= destination <= length(state.buffer) || fail("address out of range")
        kind == MoveText && a <= destination < b && fail("invalid destination")
        selected = state.buffer[a:b]
        position = destination
        if kind == MoveText
            replace_lines!(state, a - 1, b - a + 1, Line[])
            destination >= b && (position -= length(selected))
        else
            selected = new_lines!(state, [line.text for line in selected])
        end
        replace_lines!(state, position, 0, selected)
        state.current = position + length(selected)
    elseif kind in (JoinText, JoinWords)
        selected = contents(state, range)
        if kind == JoinWords
            selected[2:end] = lstrip.(selected[2:end], ' ')
        end
        joined = join(selected, kind == JoinText ? "" : " ")
        length(joined) <= 80 || fail("line too long")
        replace_lines!(state, a - 1, b - a + 1, [Line(state.buffer[a].id, joined)])
        state.current = a
    elseif kind in (IndentText, OutdentText, ConvertCase)
        width = command.amount == 0 ? 4 : command.amount
        for number in a:b
            original = state.buffer[number]
            if kind == IndentText
                length(original.text) + width <= 80 || fail("line too long")
                changed = repeat(" ", width) * original.text
            elseif kind == OutdentText
                changed = part(original.text, min(width, leading_spaces(original.text)) + 1)
            else
                changed = letter_case(original.text, command.option)
            end
            state.buffer[number] = Line(original.id, changed)
        end
        state.current = b
    elseif kind == SortText
        selected = state.buffer[a:b]
        sort_keys = 'n' in command.options ? leading_integer.(getfield.(selected, :text)) :
                    ('i' in command.options ? lowercase.(getfield.(selected, :text)) : getfield.(selected, :text))
        ordered = sortperm(sort_keys; rev = 'r' in command.options)
        if 'u' in command.options
            ordered = [index for (position, index) in enumerate(ordered) if position == 1 || sort_keys[index] != sort_keys[ordered[position-1]]]
        end
        replace_lines!(state, a - 1, b - a + 1, selected[ordered])
        state.current = a + length(ordered) - 1
    elseif kind == SubstituteText
        return substitute!(state, command, range, output, inside)
    elseif kind == MarkLine
        state.marks[Int(command.option - 'a') + 1] = state.buffer[a].id
    elseif kind == ListMarks
        pieces = String[]
        for index in eachindex(state.marks)
            position = locate(state, state.marks[index])
            position > 0 && push!(pieces, "$(Char(Int('a') + index - 1))=$position")
        end
        push!(output, "marks " * (isempty(pieces) ? "none" : join(pieces, ' ')))
    elseif kind in (UndoChange, RedoChange)
        transfer_history!(state, kind == RedoChange, command.amount == 0 ? 1 : command.amount)
    elseif kind == ListHistory
        push!(output, "history undo=$(length(state.undo)) redo=$(length(state.redo))")
        for (name, history) in (("undo", state.undo), ("redo", state.redo))
            for (index, record) in enumerate(Iterators.reverse(history))
                push!(output, "$name $index: $(record.source)")
            end
        end
    elseif kind in (ReadFile, WriteFile, AppendFile, EditFile)
        file_command!(state, command, range, output)
    elseif kind == ListFiles
        names = sort!(collect(keys(state.files)))
        pieces = ["$name=$(length(state.files[name]))" for name in names]
        push!(output, "files " * (isempty(pieces) ? "none" : join(pieces, ' ')))
    elseif kind in (GlobalCommand, InverseCommand)
        pattern = choose_pattern!(state, command.search)
        selected = [line.id for line in state.buffer[a:b] if occursin(pattern, line.text) == (kind == GlobalCommand)]
        isempty(selected) && fail("no match")
        subcommand = command.sub::Command
        changed = 0
        for identity in selected
            position = locate(state, identity)
            position == 0 && continue
            state.current = position
            subrange = checked_range(state, subcommand.kind, Int[])
            changed += execute!(state, subcommand, subrange, text, output; inside = true)
        end
        subcommand.kind == SubstituteText && changed == 0 && fail("no match")
    end
    kind in (DeleteText, PutText, JoinText, JoinWords, MoveText, CopyText) && suffix_line!(output, state, command.suffix)
    0
end

function apply!(editor::Editor, source::String, text::Vector{String})
    scanned = scan_address(source)
    form = address_form(scanned.tokens)
    command = parse_command(scanned.tail)
    arity = address_kind(command.kind)
    arity == 0 && form.count > 0 && fail("unexpected address")
    arity == 1 && form.count == 2 && fail("too many addresses")
    # Trial arrays are owned; shared strings and saved vectors are never mutated.
    trial = fork(editor.state)
    values = address_values!(trial, form)
    range = checked_range(trial, command.kind, values)
    output = String[]
    execute!(trial, command, range, text, output)
    length(trial.buffer) <= 200 || fail("buffer full")
    if modifying(command)
        push!(trial.undo, snapshot(editor.state, source))
        empty!(trial.redo)
    end
    editor.state = trial
    output
end

function main()
    editor = Editor()
    while !eof(stdin)
        source = readline()
        source == "Q" && break
        text = String[]
        if with_text(source)
            while true
                entered = readline()
                entered == "." && break
                push!(text, entered)
            end
        end
        try
            for output in apply!(editor, source, text)
                println(output)
            end
        catch error
            error isa CommandError || rethrow()
            println("? ", error.message)
        end
    end
end

main()
