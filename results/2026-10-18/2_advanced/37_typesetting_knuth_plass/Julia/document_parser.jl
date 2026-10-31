const BODY_KINDS = ("paragraph","item","enum","quote","term")
const SETTING_NAMES = ("width","indent","align")
const PREAMBLE_NAMES = ("page","header","footer")
const BLOCK_NAMES = (
    "title",
    "author",
    "h1",
    "h2",
    "item",
    "enum",
    "quote",
    "term",
    "table",
    "verbatim",
    "toc",
    "lot",
    "index",
    "bibliography"
)
const DIRECTIVE_NAMES = (SETTING_NAMES...,PREAMBLE_NAMES...,BLOCK_NAMES...,"newpage","hyphenation","bib")
const EMPTY_ARGUMENT_NAMES = ("newpage","verbatim","toc","lot","index","bibliography")
record(;values...) = Dict{Symbol,Any}(values)
function partition_text(text,separator)
    parts = split(text,separator;limit=2,keepempty=true)
    length(parts) == 1 ? (String(parts[1]),false,"") : (String(parts[1]),true,String(parts[2]))
end
function valid_argument(name,argument)
    if name in ("width","indent","page")
        occursin(r"^[0-9]{1,9}$",argument) || return false
        low,high = name == "width" ? (20,80) : name == "indent" ? (0,8) : (10,100)
        return low <= parse(Int,argument) <= high
    elseif name == "align"
        return argument in ("left","right","center","justify")
    elseif name in ("header","footer")
        return count(==('|'),argument) == 2
    elseif name in EMPTY_ARGUMENT_NAMES
        return isempty(argument)
    elseif name == "hyphenation"
        return !isempty(argument) && all(
            word->occursin(r"^[a-z]+(?:-[a-z]+)*$",word),
            split(argument,' ';keepempty=true)
        )
    elseif name == "bib"
        key,separator,fields = partition_text(argument,' ')
        separator && occursin(r"^[a-z0-9]+$",key) || return false
        parts = split(fields,'|';keepempty=true)
        return length(parts) == 3 && !isempty(parts[1]) && !isempty(parts[3]) && occursin(
            r"^[0-9]{4}$",
            parts[2]
        )
    elseif name == "term"
        term,separator,description = partition_text(argument,'|')
        return separator && !isempty(term) && !isempty(description)
    elseif name == "table"
        return occursin(r"^[lrc]+$",partition_text(argument,' ')[1])
    end
    !isempty(argument)
end
function parse_document(lines)
    document = record(
        blocks=Dict{Symbol,Any}[],
        warnings=Tuple{Int,String}[],
        height=40,
        page_width=60,
        header=("","",""),
        footer=("","",""),
        hyphenation_words=String[],
        bibliography=Dict{Symbol,Any}[]
    )
    settings = record(width=60,indent=0,align="left")
    accepted = Set{String}()
    open_body,inner_block = nothing,nothing
    pending = false
    function create_block(kind,line_number,argument="")
        isempty(document[:blocks]) && (document[:page_width]=settings[:width])
        block = record(
            kind=kind,
            line_number=line_number,
            argument=argument,
            page_break=pending,
            width=settings[:width],
            indent=settings[:indent],
            align=settings[:align]
        )
        pending = false
        push!(document[:blocks],block)
        kind in BODY_KINDS && (block[:body_lines]=Tuple{Int,String}[])
        kind in ("table","verbatim") && (block[:inner_lines]=Tuple{Int,String}[])
        block
    end
    for (line_number,line) in enumerate(lines)
        if !isnothing(inner_block)
            if line == ".end"
                inner_block = nothing
            else
                push!(inner_block[:inner_lines],(line_number,line))
            end
            continue
        elseif isempty(line)
            open_body = nothing
            continue
        elseif !startswith(line,".")
            isnothing(open_body) && (open_body=create_block("paragraph",line_number))
            push!(open_body[:body_lines],(line_number,line))
            continue
        end
        open_body = nothing
        name,_,argument = partition_text(line[2:end],' ')
        warning = !(name in DIRECTIVE_NAMES) ? "unknown directive .$name" : !valid_argument(
            name,
            argument
        ) ? "bad argument for .$name" : name in PREAMBLE_NAMES && !isempty(document[:blocks]) ? ".$name ignored after the preamble" : name in PREAMBLE_NAMES && name in accepted ? "duplicate .$name" : nothing
        if !isnothing(warning)
            push!(document[:warnings],(line_number,warning))
            continue
        end
        if name in SETTING_NAMES
            settings[Symbol(name)] = name == "align" ? argument : parse(Int,argument)
        elseif name in PREAMBLE_NAMES
            push!(accepted,name)
            if name == "page"
                document[:height] = parse(Int,argument)
            else
                document[Symbol(name)] = Tuple(String.(split(argument,'|';keepempty=true)))
            end
        elseif name == "newpage"
            pending = true
        elseif name == "hyphenation"
            append!(document[:hyphenation_words],split(argument,' '))
        elseif name == "bib"
            key,_,fields = partition_text(argument,' ')
            author,year,title = String.(split(fields,'|';keepempty=true))
            push!(
                document[:bibliography],
                record(line_number=line_number,key=key,author=author,year=year,title=title)
            )
        else
            block = create_block(name,line_number,argument)
            if name in ("item","enum","quote")
                push!(block[:body_lines],(line_number,argument))
                open_body = block
            elseif name == "term"
                term,_,description = partition_text(argument,'|')
                block[:term] = term
                push!(block[:body_lines],(line_number,description))
                open_body = block
            elseif name == "table"
                block[:columns],_,block[:caption] = partition_text(argument,' ')
                inner_block = block
            elseif name == "verbatim"
                inner_block = block
            end
        end
    end
    !isnothing(inner_block) && push!(
        document[:warnings],
        (inner_block[:line_number],"unterminated $(inner_block[:kind])")
    )
    document
end
