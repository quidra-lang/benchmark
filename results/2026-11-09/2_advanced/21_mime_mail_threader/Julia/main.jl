include("mime.jl")
include("headers.jl")
include("addresses.jl")
include("dates.jl")

const CHECKED_FIELDS = ["From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"]
const MailLine = Tuple{Int,String}
function read_mailbox(lines::Vector{String})
    messages = Vector{MailLine}[]
    for (number, line) in enumerate(lines)
        if startswith(line, "From ")
            push!(messages, MailLine[])
        elseif !isempty(messages)
            unquoted = lstrip(==('>'), line)
            text = length(unquoted) < length(line) && startswith(unquoted, "From ") ? line[2:end] : line
            push!(messages[end], (number, text))
        end
    end
    for lines in messages
        !isempty(lines) && isempty(lines[end][2]) && pop!(lines)
    end
    messages
end
function split_sections(lines::Vector{MailLine})
    index = findfirst(line -> isempty(line[2]), lines)
    isnothing(index) ? (lines, MailLine[]) : (lines[1:(index - 1)], lines[(index + 1):end])
end
function is_message_id(text::String)
    (length(text) < 3 || !startswith(text, '<') || !endswith(text, '>')) && return false
    inside = text[2:(end - 1)]
    count(==('@'), inside) == 1 && !startswith(inside, '@') && !endswith(inside, '@') && all(char -> 33 <= Int(char) <= 126 && char ∉ ('<', '>', '(', ')', '"', '\\'), inside)
end
function extract_ids(value::String)
    ids = String[]
    data = codeunits(value)
    position = 1
    while position <= length(data)
        start = findnext(==(0x3c), data, position)
        isnothing(start) && break
        last = findnext(==(0x3e), data, start + 1)
        isnothing(last) && break
        id = String(data[start:last])
        is_message_id(id) && push!(ids, id)
        position = last + 1
    end
    ids
end
date_notation(seconds::Nothing) = "invalid"
date_notation(seconds::Int) = format_utc(seconds)
subject_notation(subject::String) = isempty(subject) ? "(no subject)" : subject
mutable struct Entity
    number::String
    main_type::String
    subtype::String
    parameters::Dict{String,String}
    disposition::Union{Nothing,String}
    filename::String
    children::Union{Nothing,Vector{Entity}}
    content::String
end
Entity(number::String) = Entity(number, "text", "plain", Dict{String,String}(), nothing, "", nothing, "")
parameter(entity::Entity, name::String) = get(entity.parameters, name, "")
mutable struct Message
    number::Int
    problems::Vector{String}
    sender::Union{Nothing,Mailbox}
    to::Vector{String}
    cc::Vector{String}
    subject::String
    base_subject::String
    reply::Bool
    date::Union{Nothing,Int}
    id::String
    references::Vector{String}
    body::Entity
    thread::Int
    depth::Int
    parent::Union{Nothing,Message}
end
Message(number::Int) = Message(number, String[], nothing, String[], String[], "", "", false, nothing, "", String[], Entity("1"), 0, 0, nothing)
sort_key(message::Message) = (isnothing(message.date) ? 1 : 0, something(message.date, 0), message.id, message.number)

include("threader.jl")

function read_sender!(message::Message, value::Union{Nothing,String})
    if isnothing(value)
        push!(message.problems, "missing From")
        return
    end
    parsed = parse_address_list(value)
    if isnothing(parsed) || length(parsed[1]) != 1 || !(parsed[1][1] isa MailboxAddress)
        push!(message.problems, "bad From")
        return
    end
    addresses, error = parsed
    message.sender = addresses[1].mailbox
    error && push!(message.problems, "bad encoded word in From")
end
function read_recipients!(message::Message, value::Union{Nothing,String}, name::String)
    isnothing(value) && return String[]
    parsed = parse_address_list(value)
    if isnothing(parsed)
        push!(message.problems, "bad $name")
        return String[]
    end
    addresses, error = parsed
    recipients = String[]
    for address in addresses
        if address isa MailboxAddress
            push!(recipients, address.mailbox.address)
        else
            append!(recipients, [mailbox.address for mailbox in address.mailboxes])
        end
    end
    error && push!(message.problems, "bad encoded word in $name")
    recipients
end
function process_message!(message::Message, lines::Vector{MailLine}, known_ids::Dict{String,Int})
    header_lines, body_lines = split_sections(lines)
    header = parse_fields(header_lines)
    for number in header.invalid_lines
        push!(message.problems, "bad header line $number")
    end
    for name in CHECKED_FIELDS
        field_count(header, name) > 1 && push!(message.problems, "duplicate $name")
    end
    read_sender!(message, field_value(header, "From"))
    message.to = read_recipients!(message, field_value(header, "To"), "To")
    message.cc = read_recipients!(message, field_value(header, "Cc"), "Cc")
    subject, error = decode_unstructured(something(field_value(header, "Subject"), ""))
    message.subject = subject
    error && push!(message.problems, "bad encoded word in Subject")
    base = subject
    while length(base) >= 3 && lowercase(base[1:3]) == "re:"
        base = String(lstrip(==(' '), base[4:end]))
        message.reply = true
    end
    message.base_subject = base
    value = field_value(header, "Date")
    if isnothing(value)
        push!(message.problems, "missing Date")
    else
        try
            message.date = parse_date(value)
        catch problem
            problem isa DateProblem || rethrow()
            push!(message.problems, problem.text)
        end
    end
    value = field_value(header, "Message-ID")
    if isnothing(value)
        push!(message.problems, "missing Message-ID")
    elseif !is_message_id(value)
        push!(message.problems, "bad Message-ID")
    elseif haskey(known_ids, value)
        push!(message.problems, "Message-ID already used by message $(known_ids[value])")
    else
        message.id = value
        known_ids[value] = message.number
    end
    message.references = extract_ids(something(field_value(header, "References"), ""))
    replies = extract_ids(something(field_value(header, "In-Reply-To"), ""))
    if !isempty(replies) && (isempty(message.references) || message.references[end] != replies[1])
        push!(message.references, replies[1])
    end
    enabled = false
    value = field_value(header, "MIME-Version")
    if !isnothing(value)
        text = remove_comments(value)
        if !isnothing(text) && filter(char -> char ∉ (' ', '\t'), text) == "1.0"
            enabled = true
        else
            push!(message.problems, "bad MIME-Version")
        end
    end
    message.body = parse_entity!(message, "1", header, body_lines, enabled)
end
function parse_entity!(message::Message, number::String, header::Header, lines::Vector{MailLine}, enabled::Bool)
    entity = Entity(number)
    if enabled
        value = field_value(header, "Content-Type")
        if !isnothing(value)
            parsed = parse_parameters(value, true)
            if isnothing(parsed)
                push!(message.problems, "bad Content-Type in part $number")
            else
                entity.main_type = parsed.main_type
                entity.subtype = parsed.subtype
                entity.parameters = parsed.values
            end
        end
        value = field_value(header, "Content-Disposition")
        if !isnothing(value)
            parsed = parse_parameters(value, false)
            if isnothing(parsed)
                push!(message.problems, "bad Content-Disposition in part $number")
            else
                entity.disposition = parsed.main_type
                entity.filename = get(parsed.values, "filename", "")
            end
        end
    end
    isempty(entity.filename) && (entity.filename = parameter(entity, "name"))
    charset = get(entity.parameters, "charset", nothing)
    if entity.main_type == "text" && !isnothing(charset) && lowercase(charset) != "us-ascii"
        push!(message.problems, "unsupported charset \"$(lowercase(charset))\" in part $number")
    end
    if enabled && entity.main_type == "multipart"
        boundary = parameter(entity, "boundary")
        if !isempty(boundary)
            split_multipart!(message, entity, lines, boundary)
            return entity
        end
        push!(message.problems, "missing boundary in part $number")
    end
    original = join((text for (_, text) in lines), '\n')
    encoding = enabled ? lowercase(something(field_value(header, "Content-Transfer-Encoding"), "7bit")) : "7bit"
    if encoding == "base64"
        content = decode_base64_body(original)
        if isnothing(content)
            push!(message.problems, "bad base64 in part $number")
        else
            entity.content = content
        end
    elseif encoding == "quoted-printable"
        entity.content, error = decode_quoted_printable(original)
        error && push!(message.problems, "bad quoted-printable in part $number")
    else
        entity.content = original
        encoding ∉ ("7bit", "8bit", "binary") && push!(message.problems, "unknown encoding \"$encoding\" in part $number")
    end
    entity
end
function split_multipart!(message::Message, entity::Entity, lines::Vector{MailLine}, boundary::String)
    parts = Vector{MailLine}[]
    closed = false
    for line in lines
        text = strip_trailing(line[2])
        if text == "--$boundary--"
            closed = true
            break
        elseif text == "--$boundary"
            push!(parts, MailLine[])
        elseif !isempty(parts)
            push!(parts[end], line)
        end
    end
    if isempty(parts)
        push!(message.problems, "no parts in part $(entity.number)")
    elseif !closed
        push!(message.problems, "unterminated multipart in part $(entity.number)")
    end
    entity.children = Entity[]
    for (index, lines) in enumerate(parts)
        header_lines, body_lines = split_sections(lines)
        header = parse_fields(header_lines)
        for number in header.invalid_lines
            push!(message.problems, "bad header line $number")
        end
        number = "$(entity.number).$index"
        push!(entity.children, parse_entity!(message, number, header, body_lines, true))
    end
end
function collect_text_parts(entity::Entity, allow_html::Bool)
    if isnothing(entity.children)
        (entity.disposition == "attachment" || entity.main_type != "text") && return Entity[]
        return entity.subtype == "plain" || entity.subtype == "html" && allow_html ? [entity] : Entity[]
    end
    if entity.subtype == "alternative"
        for pass in (false, true), child in entity.children
            parts = collect_text_parts(child, pass)
            isempty(parts) || return parts
        end
        return Entity[]
    end
    parts = Entity[]
    for child in entity.children
        append!(parts, collect_text_parts(child, allow_html))
    end
    parts
end
quote_prefix(depth::Int) = depth == 0 ? "" : repeat(">", depth) * " "
function wrap_text(text::String, prefix::String)
    lines = String[]
    current = ""
    for word in split_words(text)
        if !isempty(current) && length(current) + 1 + length(word) > 72
            push!(lines, prefix * current)
            current = word
        else
            isempty(current) || (current *= " ")
            current *= word
        end
    end
    push!(lines, prefix * current)
    lines
end
mutable struct LogicalLine
    depth::Int
    text::String
    flowing::Bool
end
LogicalLine(depth::Int, text::String) = LogicalLine(depth, text, false)
function flowed_lines(content::String, delete_space::Bool)
    isempty(content) && return String[]
    logical = LogicalLine[]
    for line in split(content, '\n'; keepempty=true)
        remainder = lstrip(==('>'), line)
        depth = length(line) - length(remainder)
        text = startswith(remainder, ' ') ? String(remainder[2:end]) : String(remainder)
        flowing = endswith(text, ' ') && text != "-- "
        if !isempty(logical) && logical[end].flowing && logical[end].depth == depth
            previous = logical[end]
            delete_space && (previous.text = previous.text[1:(end - 1)])
            previous.text *= text
            previous.flowing = flowing
        else
            push!(logical, LogicalLine(depth, text, flowing))
        end
    end
    lines = String[]
    for line in logical
        append!(lines, wrap_text(line.text, quote_prefix(line.depth)))
    end
    lines
end
function reference_value(name::String)
    named = Dict("amp" => "&", "lt" => "<", "gt" => ">", "quot" => "\"", "apos" => "'", "nbsp" => " ")
    haskey(named, name) && return named[name]
    if startswith(name, '#')
        digits = name[2:end]
        if 1 <= length(digits) <= 3 && all(byte -> 48 <= byte <= 57, codeunits(digits))
            value = parse(Int, digits)
            32 <= value <= 126 && return string(Char(value))
        end
    end
    nothing
end
function replace_references(text::String)
    data = codeunits(text)
    result = ""
    position = 1
    while position <= length(data)
        if data[position] == 38
            last = findnext(==(0x3b), data, position + 1)
            if !isnothing(last)
                replacement = reference_value(String(data[(position + 1):(last - 1)]))
                if !isnothing(replacement)
                    result *= replacement
                    position = last + 1
                    continue
                end
            end
        end
        result *= string(Char(data[position]))
        position += 1
    end
    result
end
function html_blocks(content::String)
    data = codeunits(content)
    blocks = LogicalLine[]
    depth = 0
    position = 1
    text = ""
    hide = nothing
    while position <= length(data)
        last = data[position] == 60 ? findnext(==(0x3e), data, position + 1) : nothing
        if isnothing(last)
            isnothing(hide) && (text *= string(Char(data[position])))
            position += 1
            continue
        end
        inside = data[(position + 1):(last - 1)]
        position = last + 1
        end_tag = !isempty(inside) && inside[1] == 47
        start = end_tag ? inside[2:end] : inside
        count = 0
        while count < length(start) && (65 <= start[count + 1] <= 90 || 97 <= start[count + 1] <= 122 || 48 <= start[count + 1] <= 57)
            count += 1
        end
        name = lowercase(String(start[1:count]))
        if !isnothing(hide)
            end_tag && name == hide && (hide = nothing)
        elseif !end_tag && name in ("head", "style", "script")
            hide = name
        elseif name == "br" || name == "li" && !end_tag
            push!(blocks, LogicalLine(depth, text))
            text = name == "li" ? "* " : ""
        elseif name in ("p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6")
            push!(blocks, LogicalLine(depth, text))
            push!(blocks, LogicalLine(depth, ""))
            text = ""
            if name == "blockquote"
                depth = end_tag ? max(0, depth - 1) : depth + 1
            end
        end
    end
    push!(blocks, LogicalLine(depth, text))
    blocks
end
function html_lines(content::String)
    lines = String[]
    for block in html_blocks(content)
        normalized = collapse_whitespace(replace(block.text, '\n' => ' '))
        text = String(strip(==(' '), replace_references(normalized)))
        if !isempty(text)
            append!(lines, wrap_text(text, quote_prefix(block.depth)))
        elseif !isempty(lines) && !isempty(lines[end])
            push!(lines, "")
        end
    end
    while !isempty(lines) && isempty(lines[end])
        pop!(lines)
    end
    lines
end
function display_lines(entity::Entity)
    entity.subtype == "html" && return ("html", html_lines(entity.content))
    lowercase(parameter(entity, "format")) == "flowed" && return ("flowed", flowed_lines(entity.content, lowercase(parameter(entity, "delsp")) == "yes"))
    ("plain", isempty(entity.content) ? String[] : String.(split(entity.content, '\n'; keepempty=true)))
end
function line_counts(lines::Vector{String})
    quoted = 0
    signature = 0
    for (index, line) in enumerate(lines)
        stripped = strip_trailing(line)
        startswith(stripped, '>') && (quoted += 1)
        stripped == "--" && (signature = length(lines) - index)
    end
    (quoted, signature)
end
function walk_container(container::Container, prefix::String, stem::String, depth::Int)
    entries = Tuple{Container,String,Int}[(container, prefix, depth)]
    for (index, child) in enumerate(container.children)
        last = index == length(container.children)
        append!(entries, walk_container(child, stem * (last ? "`- " : "+- "), stem * (last ? "   " : "|  "), depth + 1))
    end
    entries
end
struct MailThread
    number::Int
    root::Container
    entries::Vector{Tuple{Container,String,Int}}
end
MailThread(number::Int, root::Container) = MailThread(number, root, walk_container(root, "", "", 0))
function place_messages!(thread::MailThread)
    for (container, _, depth) in thread.entries
        message = container.message
        isnothing(message) && continue
        message.thread = thread.number
        message.depth = depth
        message.parent = isnothing(container.parent) ? nothing : container.parent.message
    end
end
function container_notation(container::Container)
    message = container.message
    if !isnothing(message)
        sender = isnothing(message.sender) ? "-" : message.sender.address
        "[$(message.number)] $(date_notation(message.date)) $sender $(subject_notation(message.subject))"
    elseif !isnothing(container.subject)
        "[subject] $(container.subject)"
    else
        "[missing] $(container.id)"
    end
end
function thread_report(thread::MailThread)
    messages = [container.message for (container, _, _) in thread.entries if !isnothing(container.message)]
    depth = maximum(entry[3] for entry in thread.entries)
    senders = Set(message.sender.address for message in messages if !isnothing(message.sender))
    dates = [message.date for message in messages if !isnothing(message.date)]
    lines = ["thread $(thread.number) messages $(length(messages)) depth $depth senders $(length(senders))"]
    push!(lines, isempty(dates) ? "span -" : "span $(format_utc(minimum(dates))) .. $(format_utc(maximum(dates)))")
    subject = isnothing(thread.root.subject) ? root_subject(thread.root) : thread.root.subject
    push!(lines, "subject $(subject_notation(subject))")
    for (container, prefix, _) in thread.entries
        push!(lines, prefix * container_notation(container))
    end
    lines
end
sender_notation(sender::Nothing) = "-"
sender_notation(sender::Mailbox) = isempty(sender.name) ? sender.address : "$(sender.name) <$(sender.address)>"
function entity_lines(entity::Entity)
    line = "part $(entity.number) $(entity.main_type)/$(entity.subtype)"
    if !isnothing(entity.children)
        lines = [line]
        for child in entity.children
            append!(lines, entity_lines(child))
        end
        return lines
    end
    line *= " $(length(entity.content))"
    isnothing(entity.disposition) || (line *= " $(entity.disposition)")
    isempty(entity.filename) || (line *= " \"$(entity.filename)\"")
    [line]
end
function message_report(message::Message)
    parent = isnothing(message.parent) ? "-" : string(message.parent.number)
    lines = ["message $(message.number)", "id $(isempty(message.id) ? "-" : message.id)", "date $(date_notation(message.date))", "from $(sender_notation(message.sender))",
        "to $(isempty(message.to) ? "-" : join(message.to, ", "))", "cc $(isempty(message.cc) ? "-" : join(message.cc, ", "))", "subject $(subject_notation(message.subject))",
        "refs $(isempty(message.references) ? "-" : join(message.references, ' '))", "thread $(message.thread) depth $(message.depth) parent $parent"]
    append!(lines, entity_lines(message.body))
    lines
end
function body_report(request::String, lookup::Dict{String,Message})
    lines = ["request $request"]
    if !haskey(lookup, request)
        push!(lines, "not found")
        return lines
    end
    message = lookup[request]
    parts = collect_text_parts(message.body, true)
    push!(lines, "message $(message.number) text parts $(length(parts))")
    for part in parts
        format, display = display_lines(part)
        quoted, signature = line_counts(display)
        push!(lines, "part $(part.number) $format lines $(length(display)) quoted $quoted signature $signature")
        for line in display
            text = strip_trailing(line)
            push!(lines, isempty(text) ? "|" : "| $text")
        end
    end
    lines
end
mutable struct SenderStats
    address::String
    count::Int
    threads::Set{Int}
    first::Union{Nothing,Int}
    last::Union{Nothing,Int}
    name::String
end
SenderStats(address::String) = SenderStats(address, 0, Set{Int}(), nothing, nothing, "")
function add_message!(entry::SenderStats, message::Message)
    entry.count += 1
    push!(entry.threads, message.thread)
    if !isnothing(message.date)
        entry.first = isnothing(entry.first) ? message.date : min(entry.first, message.date)
        entry.last = isnothing(entry.last) ? message.date : max(entry.last, message.date)
    end
    isempty(message.sender.name) || (entry.name = message.sender.name)
end
csv_field(text::String) = occursin(',', text) || occursin('"', text) ? "\"" * replace(text, '"' => "\"\"") * "\"" : text
function senders_report(messages::Vector{Message})
    stats = Dict{String,SenderStats}()
    for message in messages
        isnothing(message.sender) && continue
        address = message.sender.address
        entry = get!(stats, address, SenderStats(address))
        add_message!(entry, message)
    end
    lines = ["address,name,messages,threads,first,last"]
    for entry in sort!(collect(values(stats)); by=entry -> (-entry.count, entry.address))
        first = isnothing(entry.first) ? "-" : format_utc(entry.first)
        last = isnothing(entry.last) ? "-" : format_utc(entry.last)
        push!(lines, "$(entry.address),$(csv_field(entry.name)),$(entry.count),$(length(entry.threads)),$first,$last")
    end
    lines
end
function malformed_report(messages::Vector{Message})
    flagged = count(message -> !isempty(message.problems), messages)
    total = sum(length(message.problems) for message in messages)
    lines = ["messages $(length(messages)) malformed $flagged problems $total"]
    for message in messages, problem in message.problems
        push!(lines, "message $(message.number): $problem")
    end
    lines
end
function join_blocks(blocks::Vector{Vector{String}})
    lines = String[]
    for block in blocks
        isempty(lines) || push!(lines, "")
        append!(lines, block)
    end
    lines
end
function main()
    messages = Message[]
    known_ids = Dict{String,Int}()
    for (number, lines) in enumerate(read_mailbox(readlines("input/mailbox.mbox")))
        message = Message(number)
        process_message!(message, lines, known_ids)
        push!(messages, message)
    end
    roots = build_threads(messages)
    threads = [MailThread(number, root) for (number, root) in enumerate(roots)]
    for thread in threads
        place_messages!(thread)
    end
    for message in messages
        parent = message.parent
        if !isnothing(parent) && !isnothing(message.date) && !isnothing(parent.date) && message.date < parent.date
            push!(message.problems, "dated before parent message $(parent.number)")
        end
    end
    lookup = Dict{String,Message}(message.id => message for message in messages if !isempty(message.id))
    requests = readlines("input/requests.txt")
    files = [("threads.txt", join_blocks([thread_report(thread) for thread in threads])), ("messages.txt", join_blocks(message_report.(messages))),
        ("bodies.txt", join_blocks([body_report(request, lookup) for request in requests])), ("senders.csv", senders_report(messages)), ("malformed.txt", malformed_report(messages))]
    mkpath("output")
    for (name, lines) in files
        write(joinpath("output", name), join(lines, '\n') * "\n")
    end
end

main()
