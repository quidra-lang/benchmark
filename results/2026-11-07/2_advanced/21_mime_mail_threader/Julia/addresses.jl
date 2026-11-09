struct Mailbox
    name::String
    address::String
end
abstract type Address end
struct MailboxAddress <: Address
    mailbox::Mailbox
end
struct GroupAddress <: Address
    mailboxes::Vector{Mailbox}
end
mutable struct AddressParser
    tokens::Vector{Token}
    position::Int
    error::Bool
end
peek_kind(parser::AddressParser) = parser.position <= length(parser.tokens) ? parser.tokens[parser.position].kind : nothing
function expect!(parser::AddressParser, kind::String)
    peek_kind(parser) == kind || return false
    parser.position += 1
    true
end
function read_run!(parser::AddressParser, quoted::Bool)
    start = parser.position
    while peek_kind(parser) in ("word", ".") || quoted && peek_kind(parser) == "quoted"
        parser.position += 1
    end
    start:(parser.position - 1)
end
function display_name!(parser::AddressParser, range::UnitRange{Int})
    result = ""
    previous = false
    for (index, token) in enumerate(parser.tokens[range])
        text, decoded, failed = token.kind == "word" ? decode_word(token.text) : (token.text, false, false)
        parser.error |= failed
        index > 1 && token.spaced && !(decoded && previous) && (result *= " ")
        result *= text
        previous = decoded
    end
    collapse_whitespace(result)
end
function dot_atom(parser::AddressParser, range::UnitRange{Int})
    isodd(length(range)) || return nothing
    for (index, token) in enumerate(parser.tokens[range])
        token.kind == (isodd(index) ? "word" : ".") || return nothing
    end
    join(token.text for token in parser.tokens[range])
end
function parse_address!(parser::AddressParser, in_group::Bool)
    phrase = read_run!(parser, true)
    if peek_kind(parser) == "<"
        parser.position += 1
        local_part = read_run!(parser, false)
        expect!(parser, "@") || return nothing
        domain = read_run!(parser, false)
        expect!(parser, ">") || return nothing
        first = dot_atom(parser, local_part)
        second = dot_atom(parser, domain)
        (isnothing(first) || isnothing(second)) && return nothing
        MailboxAddress(Mailbox(display_name!(parser, phrase), lowercase(first * "@" * second)))
    elseif peek_kind(parser) == "@"
        parser.position += 1
        domain = read_run!(parser, false)
        first = dot_atom(parser, phrase)
        second = dot_atom(parser, domain)
        (isnothing(first) || isnothing(second)) && return nothing
        MailboxAddress(Mailbox("", lowercase(first * "@" * second)))
    elseif peek_kind(parser) == ":" && !isempty(phrase) && !in_group
        parser.position += 1
        mailboxes = Mailbox[]
        if peek_kind(parser) != ";"
            while true
                entry = parse_address!(parser, true)
                entry isa MailboxAddress || return nothing
                push!(mailboxes, entry.mailbox)
                peek_kind(parser) == "," || break
                parser.position += 1
            end
        end
        expect!(parser, ";") || return nothing
        GroupAddress(mailboxes)
    else
        nothing
    end
end
function parse_address_list(value::String)
    tokens = tokenize(value, true)
    isnothing(tokens) && return nothing
    parser = AddressParser(tokens, 1, false)
    first = parse_address!(parser, false)
    isnothing(first) && return nothing
    addresses = Address[first]
    while peek_kind(parser) == ","
        parser.position += 1
        next = parse_address!(parser, false)
        isnothing(next) && return nothing
        push!(addresses, next)
    end
    parser.position == length(tokens) + 1 ? (addresses, parser.error) : nothing
end
