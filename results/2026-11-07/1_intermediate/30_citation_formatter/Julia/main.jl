@enum Style APA IEEE CHICAGO MLA
const STYLES = Dict(string(style) => style for style in instances(Style))
const KNOWN_FIELDS = split("author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note")
const REQUIRED_FIELDS = Dict(
    "article" => split("author title journal year"),
    "book" => split("author title publisher year"),
    "inproceedings" => split("author title booktitle year"),
    "incollection" => split("author title booktitle publisher year"),
    "techreport" => split("author title institution year"),
    "phdthesis" => split("author title school year"),
    "misc" => split("author title year")
)
const SMALL_WORDS = Set(split("a an and as at but by for from in into nor of on or over per so the to up via with yet"))
const MONTHS = split("January February March April May June July August September October November December")
const MONTH_SHORT = split("Jan. Feb. Mar. Apr. May June July Aug. Sep. Oct. Nov. Dec.")

struct BibError <: Exception
    message::String
end
struct DatabaseError <: Exception
    line::Int
    message::String
end
fail(message::String) = throw(BibError(message))
load_fail(line::Int, message::String) = throw(DatabaseError(line, message))
ascii_lower(c::Char) = 'A' <= c <= 'Z' ? Char(Int(c) + 32) : c
ascii_upper(c::Char) = 'a' <= c <= 'z' ? Char(Int(c) - 32) : c
ascii_lower(text::AbstractString) = join(ascii_lower(c) for c in text)
ascii_letter(c::Char) = 'A' <= c <= 'Z' || 'a' <= c <= 'z'
ascii_digit(c::Char) = '0' <= c <= '9'
all_digits(text::AbstractString) = !isempty(text) && all(ascii_digit, text)
plain(text::AbstractString) = replace(text, '{' => "", '}' => "")
letters_only(text::AbstractString) = ascii_lower(filter(ascii_letter, text))
part(text::AbstractString, start::Int, finish::Int = lastindex(text)) = start > finish ? "" : String(text[start:finish])

function split_depth(text::AbstractString, separator::String)
    result = String[]
    start = position = 1
    depth = 0
    while position <= lastindex(text)
        if depth == 0 && startswith(SubString(text, position), separator)
            push!(result, part(text, start, position - 1))
            position += length(separator)
            start = position
        else
            text[position] == '{' && (depth += 1)
            text[position] == '}' && (depth -= 1)
            position += 1
        end
    end
    push!(result, part(text, start))
end
function evaluate(expression::AbstractString, macros::Dict{String,String}, line::Int)
    depth = 0
    for c in expression
        c == '{' && (depth += 1)
        c == '}' && (depth -= 1)
        depth < 0 && load_fail(line, "unbalanced braces")
    end
    depth != 0 && load_fail(line, "unbalanced braces")
    output = IOBuffer()
    for term in split(expression, " # ")
        if first(term) in ('{', '"')
            print(output, part(term, 2, lastindex(term) - 1))
        elseif all_digits(term)
            print(output, term)
        else
            haskey(macros, term) || load_fail(line, "unknown macro '$term'")
            print(output, macros[term])
        end
    end
    String(take!(output))
end
function accent_at(text::AbstractString, position::Int)
    position + 1 > lastindex(text) && return nothing
    text[position] != '\\' && return nothing
    command = text[position + 1]
    command == '&' && return ('&', 2)
    symbol = command in ('\'', '"', '`', '^', '~', '=', '.')
    if symbol && position + 2 <= lastindex(text) && ascii_letter(text[position + 2])
        return text[position + 2], 3
    end
    if (symbol || command in ('c', 'u', 'v', 'H')) && position + 4 <= lastindex(text) &&
       text[position + 2] == '{' && ascii_letter(text[position + 3]) && text[position + 4] == '}'
        return text[position + 3], 5
    end
    nothing
end
function normalize(text::AbstractString)
    output = IOBuffer()
    position = 1
    while position <= lastindex(text)
        wrapped = text[position] == '{' ? accent_at(text, position + 1) : nothing
        if wrapped !== nothing && position + wrapped[2] + 1 <= lastindex(text) && text[position + wrapped[2] + 1] == '}'
            print(output, wrapped[1])
            position += wrapped[2] + 2
        else
            accent = accent_at(text, position)
            print(output, accent === nothing ? text[position] : accent[1])
            position += accent === nothing ? 1 : accent[2]
        end
    end
    join(split(replace(String(take!(output)), '~' => ' ')), " ")
end

struct Person
    first::String
    von::String
    last::String
    junior::String
end
Base.:(==)(a::Person, b::Person) = (a.first, a.von, a.last, a.junior) == (b.first, b.von, b.last, b.junior)
struct NameList
    names::Vector{Person}
    etal::Bool
end
Base.:(==)(a::NameList, b::NameList) = a.etal == b.etal && a.names == b.names
function parse_person(text::AbstractString)
    parts = String.(strip.(split_depth(text, ",")))
    words = split_depth(parts[1], " ")
    lower = [i for i in 1:length(words)-1 if 'a' <= first(words[i]) <= 'z']
    if length(parts) == 1
        isempty(lower) && return Person(join(words[1:end-1], " "), "", words[end], "")
        left, right = first(lower), last(lower)
        return Person(join(words[1:left-1], " "), join(words[left:right], " "), join(words[right+1:end], " "), "")
    end
    right = isempty(lower) ? 0 : last(lower)
    Person(parts[end], join(words[1:right], " "), join(words[right+1:end], " "), length(parts) == 3 ? parts[2] : "")
end
function parse_names(text::AbstractString)
    parts = split_depth(text, " and ")
    etal = last(parts) == "others"
    etal && pop!(parts)
    NameList(parse_person.(parts), etal)
end
singular(names::NameList) = length(names.names) == 1 && !names.etal
surname(person::Person) = plain(isempty(person.von) ? person.last : "$(person.von) $(person.last)")
function initials(first::String)
    join((join((string(ascii_upper(piece[findfirst(ascii_letter, piece)]), '.') for piece in split(word, '-')), "-")
          for word in split(plain(first))), " ")
end
function name_text(person::Person, inverted::Bool, abbreviated::Bool)
    given = abbreviated ? initials(person.first) : plain(person.first)
    result = surname(person)
    if !isempty(person.first)
        result = inverted ? "$result, $given" : "$given $result"
    end
    !isempty(person.junior) && (result *= ", " * plain(person.junior))
    result
end

mutable struct Entry
    key::String
    kind::String
    fields::Dict{String,String}
    primary::NameList
    editors::Union{Nothing,NameList}
    year::String
    sort_title::String
    sort_key::NTuple{4,String}
    suffix::String
end
function Entry(key::String, kind::String, fields::Dict{String,String})
    primary = parse_names(fields[haskey(fields, "author") ? "author" : "editor"])
    editors = haskey(fields, "editor") ? parse_names(fields["editor"]) : nothing
    year = plain(fields["year"])
    title = ascii_lower(plain(fields["title"]))
    for prefix in ("a ", "an ", "the ")
        if startswith(title, prefix)
            title = part(title, length(prefix) + 1)
            break
        end
    end
    sort_key = (ascii_lower(plain(primary.names[1].last)), year, title, key)
    Entry(key, kind, copy(fields), primary, editors, year, title, sort_key, "")
end
field(entry::Entry, name::AbstractString) = get(entry.fields, name, "")
struct Database
    entries::Vector{Entry}
    lookup::Dict{String,Int}
    bibliography::Vector{Int}
    record::Vector{Int}
end
function read_entry(lines::Vector{String}, start::Int, finish::Int, kind::String, key::String, lookup::Dict{String,Int}, macros::Dict{String,String})
    haskey(REQUIRED_FIELDS, kind) || load_fail(start, "unknown type '$kind'")
    haskey(lookup, key) && load_fail(start, "duplicate key")
    fields = Dict{String,String}()
    for i in start+1:finish-1
        line = lines[i]
        separator = first(findfirst(" = ", line))
        name = part(line, 3, separator - 1)
        expression = part(line, separator + 3, lastindex(line) - Int(endswith(line, ',')))
        value = evaluate(expression, macros, i)
        haskey(fields, name) && load_fail(i, "duplicate field '$name'")
        fields[name] = normalize(value)
    end
    for required in REQUIRED_FIELDS[kind]
        if !haskey(fields, required) && !(kind == "book" && required == "author" && haskey(fields, "editor"))
            load_fail(finish, "missing field '$required'")
        end
    end
    Entry(key, kind, fields)
end
function read_database(lines::Vector{String})
    entries = Entry[]
    lookup = Dict{String,Int}()
    macros = Dict{String,String}(ascii_lower(month[1:3]) => month for month in MONTHS)
    errors = 0
    position = 1
    while position <= length(lines)
        line = lines[position]
        if isempty(line) || startswith(line, '%')
            position += 1
            continue
        end
        if startswith(line, "@string{")
            separator = first(findfirst(" = ", line))
            name = part(line, 9, separator - 1)
            try
                value = evaluate(part(line, separator + 3, lastindex(line) - 1), macros, position)
                haskey(macros, name) && load_fail(position, "duplicate macro")
                macros[name] = value
            catch problem
                problem isa DatabaseError || rethrow()
                errors += 1
                println("ERROR line $(problem.line): $name: $(problem.message)")
            end
        else
            opening = findfirst('{', line)
            kind, key = part(line, 2, opening - 1), part(line, opening + 1, lastindex(line) - 1)
            finish = position + 1
            while lines[finish] != "}"
                finish += 1
            end
            try
                entry = read_entry(lines, position, finish, kind, key, lookup, macros)
                push!(entries, entry)
                lookup[key] = length(entries)
            catch problem
                problem isa DatabaseError || rethrow()
                errors += 1
                println("ERROR line $(problem.line): $key: $(problem.message)")
            end
            position = finish
        end
        position += 1
    end
    println("LOADED entries=$(length(entries)) macros=$(length(macros)-12) errors=$errors")
    assigned = falses(length(entries))
    for i in eachindex(entries)
        assigned[i] && continue
        entry = entries[i]
        group = findall(other -> other.primary == entry.primary && field(other, "year") == field(entry, "year"), entries)
        assigned[group] .= true
        if length(group) >= 2
            sort!(group; by = j -> (entries[j].sort_title, entries[j].key))
            for (ordinal, j) in enumerate(group)
                entries[j].suffix = string(Char(Int('a') + ordinal - 1))
            end
        end
    end
    Database(entries, lookup, sortperm(entries; by = entry -> entry.sort_key), Int[])
end

function list_names(names::Vector{String}, conjunction::String; list_b::Bool = false)
    length(names) == 1 && return names[1]
    list_b && length(names) == 2 && return join(names, " $conjunction ")
    join(names[1:end-1], ", ") * ", $conjunction " * names[end]
end
function author_names(names::NameList, style::Style)
    forms = [name_text(name, style == APA || (style in (CHICAGO, MLA) && i == 1), style in (APA, IEEE)) for (i, name) in enumerate(names.names)]
    if style == APA
        names.etal && return join(forms, ", ") * ", et al."
        length(forms) >= 21 && return join(forms[1:19], ", ") * ", . . . " * forms[end]
        return list_names(forms, "&")
    elseif style == IEEE
        return names.etal || length(forms) >= 7 ? forms[1] * " et al." : list_names(forms, "and"; list_b = true)
    elseif style == CHICAGO
        return names.etal || length(forms) >= 11 ? join(forms[1:min(7, end)], ", ") * ", et al." : list_names(forms, "and")
    end
    names.etal || length(forms) >= 3 ? forms[1] * ", et al." : list_names(forms, "and")
end
function editor_names(names::Union{Nothing,NameList}, style::Style)
    names === nothing && return ""
    forms = [name_text(person, false, style in (APA, IEEE)) for person in names.names]
    names.etal ? forms[1] * " et al." : list_names(forms, style == APA ? "&" : "and"; list_b = true)
end
year_label(entry::Entry, style::Style) = entry.year * (style in (APA, CHICAGO) ? entry.suffix : "")
function convert_case(text::String, mode::Symbol)
    result = collect(text)
    depth = 0
    first_letter = true
    for i in eachindex(result)
        c = result[i]
        if c == '{'
            depth += 1
        elseif c == '}'
            depth -= 1
        elseif ascii_letter(c)
            if depth == 0
                if mode == :lower
                    result[i] = ascii_lower(c)
                elseif mode == :sentence
                    result[i] = i == 1 || i >= 3 && text[i-2:i-1] == ": " ? ascii_upper(c) : ascii_lower(c)
                elseif first_letter
                    result[i] = ascii_upper(c)
                end
            end
            first_letter = false
        end
    end
    join(result)
end
function title_text(title::String, style::Style)
    style == IEEE && return plain(title)
    style == APA && return plain(convert_case(title, :sentence))
    words = split_depth(title, " ")
    for i in eachindex(words)
        word = words[i]
        startswith(word, '{') && continue
        small = 1 < i < length(words) && !endswith(words[i-1], ':') && letters_only(word) in SMALL_WORDS
        words[i] = convert_case(word, small ? :lower : :title)
    end
    plain(join(words, " "))
end

const TEMPLATES = Dict(
    APA => Dict(
        "article" => "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "book" => "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "inproceedings" => "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "techreport" => "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "phdthesis" => "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "misc" => "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"
    ),
    IEEE => Dict(
        "article" => "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
        "book" => "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "inproceedings" => "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
        "techreport" => "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
        "phdthesis" => "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
        "misc" => "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>"
    ),
    CHICAGO => Dict(
        "article" => "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
        "book" => "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "inproceedings" => "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
        "techreport" => "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "phdthesis" => "{author}. {year}. \"{title}.\" PhD diss., {school}.",
        "misc" => "{author}. {year}. {title}.< {howpublished}.>< {note}.>"
    ),
    MLA => Dict(
        "article" => "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
        "book" => "{author}. {title}.< {edition},> {publisher}, {year}.",
        "inproceedings" => "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
        "techreport" => "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "phdthesis" => "{author}. {title}. {year}. {school}, PhD dissertation.",
        "misc" => "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"
    )
)
function optional_end(pattern::String, start::Int)
    position, depth = start, 1
    while depth > 0
        position += 1
        pattern[position] == '<' && (depth += 1)
        pattern[position] == '>' && (depth -= 1)
    end
    position
end
function optional_present(pattern::String, start::Int, finish::Int, values::Dict{String,String})
    position = start
    while position < finish
        if pattern[position] == '<'
            position = optional_end(pattern, position)
        elseif pattern[position] == '{'
            closing = findnext('}', pattern, position)
            isempty(values[part(pattern, position + 1, closing - 1)]) && return false
            position = closing
        end
        position += 1
    end
    true
end
function render_template!(output::IOBuffer, last_output::Ref{Char}, pattern::String, start::Int, finish::Int, values::Dict{String,String})
    position = start
    while position < finish
        c = pattern[position]
        if c == '<'
            closing = optional_end(pattern, position)
            if optional_present(pattern, position + 1, closing, values)
                render_template!(output, last_output, pattern, position + 1, closing, values)
            end
            position = closing
        elseif c == '{'
            closing = findnext('}', pattern, position)
            value = values[part(pattern, position + 1, closing - 1)]
            print(output, value)
            !isempty(value) && (last_output[] = last(value))
            position = closing
        elseif c != '.' || !(last_output[] in ('.', '?', '!'))
            print(output, c)
            last_output[] = c
        end
        position += 1
    end
end
function placeholder_values(entry::Entry, style::Style, repeated::Bool)
    values = Dict{String,String}(name => plain(field(entry, name)) for name in KNOWN_FIELDS)
    for name in ("eds", "pp", "mon")
        values[name] = ""
    end
    author = repeated ? "---" : author_names(entry.primary, style)
    if !haskey(entry.fields, "author")
        labels = style == APA ? (" (Ed.)", " (Eds.)") : style == IEEE ? (", Ed.", ", Eds.") :
                 style == CHICAGO ? (", ed.", ", eds.") : (", editor", ", editors")
        author *= labels[singular(entry.primary) ? 1 : 2]
    end
    values["author"] = author
    values["editor"] = editor_names(entry.editors, style)
    if entry.editors !== nothing
        values["eds"] = singular(entry.editors) ? "Ed." : "Eds."
    end
    values["title"] = title_text(field(entry, "title"), style)
    values["year"] = year_label(entry, style)
    values["pages"] = replace(values["pages"], "--" => "-")
    if haskey(entry.fields, "pages")
        values["pp"] = (occursin('-', values["pages"]) ? "pp. " : "p. ") * values["pages"]
    end
    if haskey(entry.fields, "edition")
        edition = values["edition"]
        if all_digits(edition)
            n = parse(Int, edition)
            suffix = n % 100 in 11:13 ? "th" : n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th"
            edition *= suffix
        end
        values["edition"] = edition * " ed."
    end
    if haskey(entry.fields, "month")
        index = findfirst(==(values["month"]), MONTHS)
        values["mon"] = index === nothing ? values["month"] : MONTH_SHORT[index]
    end
    values
end
function reference(entry::Entry, style::Style, number::Int; repeated::Bool = false)
    kind = entry.kind == "incollection" ? "inproceedings" : entry.kind
    pattern = TEMPLATES[style][kind]
    output = IOBuffer()
    render_template!(output, Ref('\0'), pattern, 1, lastindex(pattern) + 1, placeholder_values(entry, style, repeated))
    result = String(take!(output))
    style == IEEE ? "[$number] $result" : result
end
function ieee_order(database::Database)
    remaining = setdiff(collect(eachindex(database.entries)), database.record)
    sort!(remaining; by = i -> database.entries[i].key)
    vcat(database.record, remaining)
end
function ieee_numbers(database::Database)
    numbers = zeros(Int, length(database.entries))
    numbers[ieee_order(database)] = eachindex(numbers)
    numbers
end
function short_name(entry::Entry, style::Style, parenthetical::Bool = false)
    names = surname.(entry.primary.names)
    if entry.primary.etal || length(names) >= (style == CHICAGO ? 4 : 3)
        return names[1] * " et al."
    end
    list_names(names, style == APA && parenthetical ? "&" : "and"; list_b = true)
end
@enum CitationKind Parenthetical Narrative AuthorOnly YearOnly
struct Citation
    start::Int
    finish::Int
    kind::CitationKind
    entries::Vector{Int}
end
function citation_text(database::Database, citation::Citation, style::Style, numbers::Vector{Int})
    indices = citation.entries
    parenthetical = citation.kind == Parenthetical
    if citation.kind in (AuthorOnly, YearOnly) || style == MLA || style == IEEE && !parenthetical
        values = [citation.kind == YearOnly ? year_label(database.entries[i], style) :
                  short_name(database.entries[i], style) * (style == IEEE && citation.kind == Narrative ? " [$(numbers[i])]" : "") for i in indices]
        result = join(values, citation.kind == YearOnly ? ", " : "; ")
        return style == MLA && parenthetical ? "($result)" : result
    end
    groups = String[]
    if style == IEEE
        ordered = sort(numbers[indices])
        position = 1
        while position <= length(ordered)
            finish = position + 1
            while finish <= length(ordered) && ordered[finish] == ordered[finish-1] + 1
                finish += 1
            end
            if finish - position >= 3
                push!(groups, "[$(ordered[position])]-[$(ordered[finish-1])]")
            else
                append!(groups, ["[$(ordered[i])]" for i in position:finish-1])
            end
            position = finish
        end
        return join(groups, ", ")
    end
    ordered = parenthetical ? sort(indices; by = i -> database.entries[i].sort_key) : indices
    position = 1
    while position <= length(ordered)
        name = short_name(database.entries[ordered[position]], style, parenthetical)
        finish = position + 1
        while finish <= length(ordered) && short_name(database.entries[ordered[finish]], style, parenthetical) == name
            finish += 1
        end
        years = join((year_label(database.entries[ordered[i]], style) for i in position:finish-1), ", ")
        push!(groups, parenthetical ? name * (style == APA ? ", " : " ") * years : "$name ($years)")
        position = finish
    end
    result = join(groups, "; ")
    parenthetical ? "($result)" : result
end
function cite!(database::Database, style::Style, text::AbstractString)
    citations = Citation[]
    start = findfirst('\\', text)
    while start !== nothing
        opening = findnext('{', text, start)
        finish = findnext('}', text, opening)
        kind_text = part(text, start + 1, opening - 1)
        kind = kind_text == "citet" ? Narrative : kind_text == "citeauthor" ? AuthorOnly : kind_text == "citeyear" ? YearOnly : Parenthetical
        indices = Int[]
        for key in unique(split(part(text, opening + 1, finish - 1), ','))
            haskey(database.lookup, key) || fail("unknown key '$key'")
            push!(indices, database.lookup[key])
        end
        push!(citations, Citation(start, finish, kind, indices))
        start = findnext('\\', text, finish + 1)
    end
    recorded = Set(database.record)
    for citation in citations, index in citation.entries
        if !(index in recorded)
            push!(recorded, index)
            push!(database.record, index)
        end
    end
    numbers = ieee_numbers(database)
    output = IOBuffer()
    position = 1
    for citation in citations
        print(output, part(text, position, citation.start - 1), citation_text(database, citation, style, numbers))
        position = citation.finish + 1
    end
    print(output, part(text, position))
    String(take!(output))
end

function keygen(database::Database)
    bases = String[]
    for entry in database.entries
        words = letters_only.(split(plain(field(entry, "title"))))
        index = findfirst(word -> !isempty(word) && !(word in SMALL_WORDS), words)
        push!(bases, letters_only(plain(entry.primary.names[1].last)) * filter(ascii_digit, field(entry, "year")) * (index === nothing ? "" : words[index]))
    end
    totals = Dict{String,Int}()
    for base in bases
        totals[base] = get(totals, base, 0) + 1
    end
    seen = Dict{String,Int}()
    for (i, base) in enumerate(bases)
        ordinal = get(seen, base, 0)
        suffix = totals[base] >= 2 ? string(Char(Int('a') + ordinal)) : ""
        seen[base] = ordinal + 1
        println("$(database.entries[i].key) -> $base$suffix")
    end
end
unknown_fields(entry::Entry) = sort(setdiff(collect(keys(entry.fields)), KNOWN_FIELDS))
function check_entries(database::Database)
    warnings = 0
    titles = Dict{String,String}()
    for entry in database.entries
        messages = String[]
        if haskey(entry.fields, "pages")
            pages = plain(field(entry, "pages"))
            occursin('-', pages) && !occursin("--", pages) && push!(messages, "pages use a single hyphen")
            parts = split(pages, '-'; keepempty = false)
            if length(parts) == 2 && all(all_digits, parts) && parse(Int, parts[1]) > parse(Int, parts[2])
                push!(messages, "pages are reversed")
            end
        end
        !(length(entry.year) == 4 && all_digits(entry.year)) && push!(messages, "year is not 4 digits")
        title = plain(field(entry, "title"))
        if !any(c -> 'a' <= c <= 'z', title) && count(c -> 'A' <= c <= 'Z', title) >= 2
            push!(messages, "title is all caps")
        end
        entry.kind == "article" && !haskey(entry.fields, "doi") && push!(messages, "article has no doi")
        lowered = ascii_lower(title)
        if haskey(titles, lowered)
            push!(messages, "same title as $(titles[lowered])")
        else
            titles[lowered] = entry.key
        end
        append!(messages, ["unknown field '$name'" for name in unknown_fields(entry)])
        for message in messages
            println("WARN $(entry.key): $message")
        end
        warnings += length(messages)
    end
    println("CHECK warnings=$warnings")
end
function export_entry(entry::Entry)
    fields = vcat(filter(name -> haskey(entry.fields, name), KNOWN_FIELDS), unknown_fields(entry))
    println("@$(entry.kind){$(entry.key),")
    for (i, name) in enumerate(fields)
        println("  $name = {$(field(entry, name))}", i < length(fields) ? "," : "")
    end
    println('}')
end
function statistics(database::Database)
    println("ENTRIES $(length(database.entries))")
    for property in (:kind, :year)
        counts = Dict{String,Int}()
        for entry in database.entries
            value = getfield(entry, property)
            counts[value] = get(counts, value, 0) + 1
        end
        label = property == :kind ? "TYPE" : "YEAR"
        for value in sort(collect(keys(counts)))
            println("$label $value $(counts[value])")
        end
    end
    authors = Set{String}()
    pairs = Dict{Tuple{String,String},Int}()
    for entry in database.entries
        haskey(entry.fields, "author") || continue
        names = sort(unique([name_text(person, false, false) for person in entry.primary.names]))
        union!(authors, names)
        for i in eachindex(names), j in i+1:length(names)
            pair = (names[i], names[j])
            pairs[pair] = get(pairs, pair, 0) + 1
        end
    end
    println("AUTHORS $(length(authors))")
    if isempty(pairs)
        println("PAIR none")
    else
        best = first(sort(collect(keys(pairs)); by = pair -> (-pairs[pair], pair...)))
        println("PAIR $(best[1]) & $(best[2]) $(pairs[best])")
    end
end
function execute!(database::Database, line::String)
    command = first(split(line, ' '; limit = 2))
    commands = ("FORMAT", "BIBLIOGRAPHY", "CITE", "KEYGEN", "CHECK", "SEARCH", "EXPORT", "STATS")
    command in commands || fail("unknown command '$command'")
    words = split(line, ' '; limit = command in ("CITE", "SEARCH") ? 3 : 0, keepempty = true)
    arguments = length(words) - 1
    arity = command in ("BIBLIOGRAPHY", "EXPORT") ? 1 : command in ("CITE", "SEARCH") ? 2 : 0
    (command == "FORMAT" ? arguments < 2 : arguments != arity) && fail("wrong number of arguments")
    style = APA
    if command in ("FORMAT", "BIBLIOGRAPHY", "CITE")
        haskey(STYLES, words[2]) || fail("unknown style '$(words[2])'")
        style = STYLES[words[2]]
    end
    if command == "FORMAT"
        numbers = ieee_numbers(database)
        for key in words[3:end]
            if haskey(database.lookup, key)
                index = database.lookup[key]
                println(reference(database.entries[index], style, numbers[index]))
            else
                println("ERROR unknown key '$key'")
            end
        end
    elseif command == "BIBLIOGRAPHY"
        println(style == MLA ? "Works Cited" : "References")
        order = style == IEEE ? ieee_order(database) : database.bibliography
        numbers = ieee_numbers(database)
        previous = nothing
        for index in order
            entry = database.entries[index]
            repeated = style in (CHICAGO, MLA) && previous !== nothing && entry.primary == previous
            println(reference(entry, style, numbers[index]; repeated = repeated))
            previous = entry.primary
        end
    elseif command == "CITE"
        println(cite!(database, style, words[3]))
    elseif command == "KEYGEN"
        keygen(database)
    elseif command == "CHECK"
        check_entries(database)
    elseif command == "EXPORT"
        haskey(database.lookup, words[2]) || fail("unknown key '$(words[2])'")
        export_entry(database.entries[database.lookup[words[2]]])
    elseif command == "SEARCH"
        needle = ascii_lower(words[3])
        matches = [entry.key for entry in database.entries if haskey(entry.fields, words[2]) && occursin(needle, ascii_lower(plain(field(entry, words[2]))))]
        println(isempty(matches) ? "MATCHES 0" : "MATCHES $(length(matches)): " * join(matches, " "))
    else
        statistics(database)
    end
end

function main()
    lines = String[]
    while true
        line = readline()
        line == "%%" && break
        push!(lines, line)
    end
    database = read_database(lines)
    for _ in 1:parse(Int, readline())
        try
            execute!(database, readline())
        catch problem
            problem isa BibError || rethrow()
            println("ERROR $(problem.message)")
        end
    end
end
main()
