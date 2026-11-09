include("document_parser.jl")
include("hyphenation.jl")
include("line_breaker.jl")
include("page_builder.jl")
include("renderer.jl")

text_line(text) = record(text=text,footnotes=Int[],indexes=Int[])
words_in(text) = String.(filter(word->!isempty(word),split(text,' ';keepempty=true)))
function split_label(text)
    position = findlast(" {#",text)
    if endswith(text,"}") && !isnothing(position)
        return text[1:first(position)-1],text[last(position)+1:end-1]
    end
    text,nothing
end
struct BreakPosition
    start::Tuple{Int,Int}
    stop::Tuple{Int,Int}
    midword::Bool
    append_hyphen::Bool
end
struct TextMetrics
    words::Vector{String}
    first_capacity::Int
    later_capacity::Int
    offsets::Vector{Int}
    breaks::Vector{BreakPosition}
    count::Int
end
function TextMetrics(words,first_capacity,later_capacity,dictionary)
    offsets = Int[]
    breaks = [BreakPosition((1,0),(1,0),false,false)]
    offset = 0
    for (index,word) in enumerate(words)
        push!(offsets,offset)
        offset += length(word)+1
        for (position,append_hyphen) in split_points(dictionary,word)
            push!(breaks,BreakPosition((index,position),(index,position),true,append_hyphen))
        end
        push!(breaks,BreakPosition((index+1,0),(index,length(word)),false,false))
    end
    TextMetrics(words,first_capacity,later_capacity,offsets,breaks,length(breaks)-1)
end
metrics_capacity(metrics,start) = start == 0 ? metrics.first_capacity : metrics.later_capacity
function metrics_length(metrics,start,stop)
    first_word,first_position = metrics.breaks[start+1].start
    last_word,last_position = metrics.breaks[stop+1].stop
    metrics.offsets[last_word]+last_position-metrics.offsets[first_word]-first_position+(metrics.breaks[stop+1].append_hyphen ? 1 : 0)
end
metrics_slack(metrics,start,stop) = metrics_capacity(metrics,start)-metrics_length(metrics,start,stop)
function measure(metrics,start,stop)
    first_word,first_position = metrics.breaks[start+1].start
    last_word,last_position = metrics.breaks[stop+1].stop
    pieces = String[]
    ranges = Tuple{Int,Int,Int}[]
    for word in first_word:last_word
        begin_position = word == first_word ? first_position : 0
        end_position = word == last_word ? last_position : length(metrics.words[word])
        push!(pieces,metrics.words[word][begin_position+1:end_position])
        push!(ranges,(word,begin_position,end_position))
    end
    metrics.breaks[stop+1].append_hyphen && (pieces[end] *= "-")
    (
        pieces=pieces,ranges=ranges,slack=metrics_slack(metrics,start,stop),
        last=stop == metrics.count,midword=metrics.breaks[stop+1].midword
    )
end
Base.@kwdef mutable struct Typesetter
    document::Dict{Symbol,Any}
    params::Dict{String,Int}
    dictionary::Hyphenation
    blocks::Vector{Dict{Symbol,Any}}
    warnings::Vector{Tuple{Int,String}}
    labels::Dict{String,Dict{Symbol,Any}} = Dict{String,Dict{Symbol,Any}}()
    bibliography::Dict{String,Dict{Symbol,Any}} = Dict{String,Dict{Symbol,Any}}()
    bibliography_entries::Vector{Dict{Symbol,Any}} = Dict{Symbol,Any}[]
    cited_entries::Vector{Dict{Symbol,Any}} = Dict{Symbol,Any}[]
    body_blocks::Vector{Dict{Symbol,Any}} = Dict{Symbol,Any}[]
    headings::Vector{Dict{Symbol,Any}} = Dict{Symbol,Any}[]
    numbered_tables::Vector{Dict{Symbol,Any}} = Dict{Symbol,Any}[]
    footnotes::Vector{String} = String[]
    index_marks::Vector{String} = String[]
    index_entries::Dict{String,Dict{Symbol,Any}} = Dict{String,Dict{Symbol,Any}}()
end
warn!(setter,line,message) = push!(setter.warnings,(line,message))
function register_document!(setter)
    chapter,section,table_number = 0,0,0
    previous = nothing
    for (index,block) in enumerate(setter.blocks)
        block[:id],block[:label] = index,nothing
        kind = block[:kind]
        if kind in ("h1","h2")
            block[:text],block[:label] = split_label(block[:argument])
            if kind == "h1"
                chapter += 1
                section = 0
                block[:number] = string(chapter)
                index != 1 && (block[:page_break]=true)
            else
                section += 1
                block[:number] = "$chapter.$section"
            end
            push!(setter.headings,block)
        elseif kind == "enum"
            block[:number] = !isnothing(previous) && previous[:kind] == "enum" ? previous[:number]+1 : 1
        elseif kind == "table"
            block[:caption],block[:label] = split_label(block[:caption])
            block[:number] = nothing
            if !isempty(block[:caption])
                table_number += 1
                block[:number] = string(table_number)
                push!(setter.numbered_tables,block)
            end
        end
        label = block[:label]
        if !isnothing(label)
            if haskey(setter.labels,label)
                warn!(setter,block[:line_number],"duplicate label $label")
                block[:label] = nothing
            else
                setter.labels[label] = block
            end
        end
        kind == "paragraph" && !isnothing(previous) && previous[:kind] in ("h1","h2") && (block[:indent]=0)
        if kind in BODY_KINDS
            push!(setter.body_blocks,block)
            block[:paragraph_number] = length(setter.body_blocks)
        end
        previous = block
    end
    for original in setter.document[:bibliography]
        key = original[:key]
        if haskey(setter.bibliography,key)
            warn!(setter,original[:line_number],"duplicate bibliography key $key")
        else
            entry = copy(original)
            entry[:cited] = false
            setter.bibliography[key] = entry
            push!(setter.bibliography_entries,entry)
        end
    end
end
function check_table!(setter,block)
    count = length(block[:columns])
    rows = Vector{String}[]
    for (line_number,text) in block[:inner_lines]
        cells = String.(strip.(split(text,'|';keepempty=true),' '))
        if length(cells) != count
            warn!(setter,line_number,"table row has $(length(cells)) cells, expected $count")
            cells = vcat(cells,fill("",max(0,count-length(cells))))[1:count]
        end
        push!(rows,cells)
    end
    block[:table_lines] = format_table(rows,block[:columns],block[:caption],block[:number])
    excess = maximum(length.(block[:table_lines]))-block[:width]
    excess > 0 && warn!(setter,block[:line_number],"table too wide by $excess")
end
function accept_command!(setter,name,argument,line_number)
    if name in ("ref","page")
        !haskey(setter.labels,argument) && warn!(setter,line_number,"undefined label $argument")
    elseif name == "cite"
        for key in split(argument,',')
            if haskey(setter.bibliography,key)
                setter.bibliography[key][:cited] = true
            else
                warn!(setter,line_number,"undefined citation $key")
            end
        end
    elseif name == "fn"
        push!(setter.footnotes,argument)
        return (name,length(setter.footnotes))
    elseif name == "idx"
        push!(setter.index_marks,argument)
        return (name,length(setter.index_marks))
    end
    (name,argument)
end
function parse_body_line!(setter,text,line_number)
    tokens = Any[]
    position = 1
    while position <= length(text)
        opening = findnext('{',text,position)
        if isnothing(opening)
            push!(tokens,text[position:end])
            break
        end
        opening > position && push!(tokens,text[position:opening-1])
        closing = findnext('}',text,opening+1)
        if isnothing(closing)
            warn!(setter,line_number,"unclosed brace")
            push!(tokens,text[opening:end])
            break
        end
        content = text[opening+1:closing-1]
        name,separator,argument = partition_text(content,':')
        if name in ("ref","page","fn","idx","cite") && separator && !isempty(argument)
            push!(tokens,accept_command!(setter,name,argument,line_number))
        else
            warn!(setter,line_number,"bad command {$content}")
        end
        position = closing+1
    end
    tokens
end
function check_document!(setter)
    for block in setter.blocks
        kind = block[:kind]
        if kind == "table"
            check_table!(setter,block)
        elseif kind == "verbatim"
            for (number,text) in block[:inner_lines]
                excess = length(text)-block[:width]
                excess > 0 && warn!(setter,number,"verbatim line too long by $excess")
            end
        elseif kind in BODY_KINDS
            tokens = Any[]
            for (index,(number,text)) in enumerate(block[:body_lines])
                index > 1 && push!(tokens," ")
                append!(tokens,parse_body_line!(setter,text,number))
            end
            block[:tokens] = tokens
        end
    end
    for entry in setter.bibliography_entries
        !entry[:cited] && warn!(setter,entry[:line_number],"unused bibliography entry $(entry[:key])")
    end
end
function assign_bibliography_labels!(setter)
    for entry in setter.bibliography_entries
        entry[:cited] || continue
        surnames = split(entry[:author]," and ")
        base = length(surnames) == 1 ? surnames[1][1:min(
            3,
            length(surnames[1])
        )] : length(surnames) <= 4 ? join(first.(surnames)) : join(first.(surnames[1:3]))*"+"
        entry[:base_label] = base*entry[:year][end-1:end]
        push!(setter.cited_entries,entry)
    end
    sort!(setter.cited_entries,by=entry->(entry[:base_label],entry[:author],entry[:title],entry[:key]))
    for entry in setter.cited_entries
        group = filter(other->other[:base_label] == entry[:base_label],setter.cited_entries)
        index = findfirst(other->other === entry,group)
        entry[:label] = entry[:base_label]*(length(group) == 1 ? "" : string(Char(Int('a')+index-1)))
    end
end
new_index_entry(name) = record(
    name=name,
    marks=Int[],
    references=Set{String}(),
    children=Dict{String,Dict{Symbol,Any}}()
)
function prepare_index!(setter)
    for (number,phrase) in enumerate(setter.index_marks)
        entry_part,has_reference,reference = partition_text(phrase,'|')
        parent_name,has_child,child_name = partition_text(entry_part,'!')
        parent = get!(()->new_index_entry(parent_name),setter.index_entries,parent_name)
        entry = has_child ? get!(()->new_index_entry(child_name),parent[:children],child_name) : parent
        has_reference ? push!(entry[:references],reference) : push!(entry[:marks],number)
    end
end
function citation_text(setter,argument)
    labels = Set{String}()
    undefined = false
    for key in split(argument,',')
        if haskey(setter.bibliography,key)
            push!(labels,setter.bibliography[key][:label])
        else
            undefined = true
        end
    end
    parts = sort(collect(labels))
    undefined && push!(parts,"?")
    "["*join(parts,", ")*"]"
end
function expand_body(setter,block,page_values)
    parts = String[]
    marks = Tuple{Int,String,Int}[]
    offset = 0
    for token in block[:tokens]
        if token isa AbstractString
            text = token
        else
            name,argument = token
            if name == "idx"
                push!(marks,(offset-1,name,argument))
                continue
            elseif name == "fn"
                push!(marks,(offset,name,argument))
                text = "[$argument]"
            elseif name == "ref"
                text = haskey(setter.labels,argument) ? setter.labels[argument][:number] : "??"
            elseif name == "page"
                text = get(page_values,argument,"??")
            else
                text = citation_text(setter,argument)
            end
        end
        push!(parts,text)
        offset += length(text)
    end
    expanded = join(parts)
    matches = collect(eachmatch(r"[^ ]+",expanded))
    words = [String(match.match) for match in matches]
    starts = [match.offset-1 for match in matches]
    word_marks = Dict{Int,Vector{Tuple{String,Int,Int}}}()
    for (offset,kind,number) in marks
        word = searchsortedlast(starts,offset)
        push!(get!(()->Tuple{String,Int,Int}[],word_marks,word),(kind,number,offset-starts[word]))
    end
    words,word_marks
end
function lay_out_text(setter,words,capacities,alignment,prefixes,method;word_marks=Dict())
    metrics = TextMetrics(words,capacities...,setter.dictionary)
    breaking,cost = break_text(metrics,method,setter.params)
    lines = Dict{Symbol,Any}[]
    broken = NamedTuple[]
    start = 0
    for (index,stop) in enumerate(breaking)
        measured = measure(metrics,start,stop)
        text = display_line(measured.pieces,measured.slack,alignment,measured.last)
        line = text_line(prefixes[index == 1 ? 1 : 2]*text)
        for (word,first_position,last_position) in measured.ranges
            for (kind,number,position) in get(word_marks,word,[])
                first_position <= position < last_position && push!(
                    line[kind == "fn" ? :footnotes : :indexes],
                    number
                )
            end
        end
        push!(lines,line)
        push!(broken,measured)
        start = stop
    end
    record(lines=lines,broken=broken,cost=cost)
end
function body_format(block)
    width,kind = block[:width],block[:kind]
    kind == "paragraph" && return (width-block[:indent],width),(repeat(" ",block[:indent]),"")
    kind == "item" && return (width-2,width-2),("- ","  ")
    kind == "enum" && return (width-4,width-4),(lpad(block[:number],2)*". ","    ")
    kind == "quote" && return (width-8,width-8),("    ","    ")
    first_prefix = length(block[:term]) <= 10 ? rpad(block[:term],12) : repeat(" ",12)
    (width-12,width-12),(first_prefix,repeat(" ",12))
end
function lay_out_body(setter,block,page_values,method)
    words,marks = expand_body(setter,block,page_values)
    capacities,prefixes = body_format(block)
    result = lay_out_text(setter,words,capacities,block[:align],prefixes,method;word_marks=marks)
    block[:kind] == "term" && length(block[:term]) >= 11 && pushfirst!(result[:lines],text_line(block[:term]))
    result
end
function lay_out_footnotes(setter,method)
    results = Dict{Int,Dict{Symbol,Any}}()
    for (number,text) in enumerate(setter.footnotes)
        prefix = "[$number] "
        capacity = setter.document[:page_width]-length(prefix)
        results[number] = lay_out_text(
            setter,
            words_in(text),
            (capacity,capacity),
            "left",
            (prefix,repeat(" ",length(prefix))),
            method
        )
    end
    results
end
function lay_out_reference(setter,entry,width,method)
    margin = maximum(length(item[:label]) for item in setter.cited_entries)+3
    text = "$(entry[:author]). $(entry[:year]). $(entry[:title])"
    prefix = rpad("[$(entry[:label])]",margin)
    lay_out_text(setter,words_in(text),(width-margin,width-margin),"left",(prefix,repeat(" ",margin)),method)
end
function page_list(numbers)
    numbers = sort(unique(numbers))
    parts = String[]
    index = 1
    while index <= length(numbers)
        stop = index
        while stop < length(numbers) && numbers[stop+1] == numbers[stop]+1
            stop += 1
        end
        if stop-index >= 2
            push!(parts,"$(numbers[index])-$(numbers[stop])")
        else
            append!(parts,string.(numbers[index:stop]))
        end
        index = stop+1
    end
    join(parts,", ")
end
function index_entry_line(entry,mark_pages;child=false)
    text = (child ? "  " : "")*entry[:name]
    numbers = [mark_pages[number] for number in entry[:marks] if haskey(mark_pages,number)]
    !isempty(numbers) && (text *= ", "*page_list(numbers))
    !isempty(entry[:references]) && (text *= ", see "*join(sort(collect(entry[:references])),", "))
    text
end
function index_lines(setter,mark_pages)
    lines = String[]
    previous = nothing
    for name in sort(collect(keys(setter.index_entries)),by=name->(lowercase(name),name))
        parent = setter.index_entries[name]
        group = is_letter(name[1]) ? uppercase(name[1:1]) : "Symbols"
        if group != previous
            push!(lines,group)
            previous = group
        end
        push!(lines,index_entry_line(parent,mark_pages))
        for name in sort(collect(keys(parent[:children])),by=name->(lowercase(name),name))
            push!(lines,index_entry_line(parent[:children][name],mark_pages;child=true))
        end
    end
    lines
end
function contents_lines(setter,block,block_pages)
    entries = block[:kind] == "toc" ? setter.headings : setter.numbered_tables
    lines = String[]
    for entry in entries
        left = block[:kind] == "toc" ? (entry[:kind] == "h2" ? "  " : "")*"$(entry[:number]) $(entry[:text])" : "Table $(entry[:number]). $(entry[:caption])"
        page = get(block_pages,entry[:id],nothing)
        number = isnothing(page) ? "??" : page[:display]
        push!(lines,left*" "*repeat(".",block[:width]-length(left)-length(number)-2)*" "*number)
    end
    lines
end
function add_layout_block!(layout,source,kind,lines;list_mark=false,first=true)
    if first
        lines[1][:anchor] = source[:id]
        source[:kind] == "h1" && (lines[1][:chapter_start]=true)
    end
    push!(layout,record(kind=kind,lines=lines,list=list_mark,page_break=first && source[:page_break]))
end
function build_layout_blocks(setter,page_values,method,result)
    layout = Dict{Symbol,Any}[]
    for block in setter.blocks
        kind = block[:kind]
        if kind in BODY_KINDS
            body = lay_out_body(setter,block,page_values,method)
            result[:bodies][block[:id]] = body
            push!(
                result[:warning_texts],
                ("paragraph $(block[:paragraph_number])",body,block[:align] == "justify")
            )
            add_layout_block!(layout,block,"flow",body[:lines];list_mark=kind in ("item","enum","term"))
        elseif kind in ("title","author")
            text = kind == "title" ? uppercase(block[:argument]) : block[:argument]
            text = repeat(" ",(block[:width]-length(text))÷2)*text
            add_layout_block!(layout,block,"heading",[text_line(text)])
        elseif kind in ("h1","h2")
            text = kind == "h1" ? uppercase(block[:text]) : block[:text]
            text = "$(block[:number]) $text"
            rule = repeat(kind == "h1" ? "=" : "-",length(text))
            add_layout_block!(layout,block,"heading",text_line.([text,rule]))
        elseif kind == "table"
            add_layout_block!(layout,block,"solid",text_line.(block[:table_lines]))
        elseif kind == "verbatim"
            add_layout_block!(layout,block,"flow",[text_line(text) for (_,text) in block[:inner_lines]])
        elseif kind in ("toc","lot","index")
            title = kind == "toc" ? "CONTENTS" : kind == "lot" ? "TABLES" : "INDEX"
            add_layout_block!(layout,block,"heading",text_line.([title,repeat("=",length(title))]))
            entries = kind == "index" ? index_lines(setter,Dict()) : contents_lines(setter,block,Dict())
            lines = text_line.(entries)
            add_layout_block!(layout,block,"flow",lines;first=false)
            push!(result[:generated],(block,lines))
        elseif kind == "bibliography"
            add_layout_block!(layout,block,"heading",text_line.(["REFERENCES","=========="]))
            for entry in setter.cited_entries
                reference = lay_out_reference(setter,entry,block[:width],method)
                push!(result[:warning_texts],("reference $(entry[:label])",reference,false))
                add_layout_block!(layout,block,"flow",reference[:lines];list_mark=true,first=false)
            end
        end
    end
    layout
end
roman(number) = repeat("x",number÷10)*("","i","ii","iii","iv","v","vi","vii","viii","ix")[number%10+1]
function number_pages!(setter,pages,result)
    numbered = Dict{Symbol,Any}[]
    for page in pages
        chapter_start = get(page[:content][1],:chapter_start,false)
        serial = length(numbered)+1
        if chapter_start && iseven(serial)
            push!(
                numbered,
                record(
                    serial=serial,
                    blank=true,
                    content=Dict{Symbol,Any}[],
                    footnotes=Int[],
                    height=0,
                    ends_by_force=true,
                    chapter_start=false
                )
            )
            serial += 1
        end
        page[:serial],page[:chapter_start] = serial,chapter_start
        push!(numbered,page)
    end
    block_pages = Dict{Int,Dict{Symbol,Any}}()
    for page in numbered, line in page[:content]
        haskey(line,:anchor) && (block_pages[line[:anchor]]=page)
    end
    front_matter = isempty(setter.headings) ? 0 : block_pages[setter.headings[1][:id]][:serial]-1
    mark_pages = Dict{Int,Int}()
    for page in numbered
        serial = page[:serial]
        page[:body_number] = serial-front_matter
        page[:display] = serial <= front_matter ? roman(serial) : string(page[:body_number])
        for line in page[:content], mark in line[:indexes]
            mark_pages[mark] = page[:body_number]
        end
    end
    result[:pages],result[:front_matter],result[:block_pages],result[:mark_pages] = numbered,front_matter,block_pages,mark_pages
    result[:label_values] = Dict(label=>block_pages[block[:id]][:display] for (label,block) in setter.labels)
end
function layout_once(setter,page_values,method)
    footnotes = lay_out_footnotes(setter,method)
    result = record(
        method=method,
        bodies=Dict{Int,Any}(),
        footnotes=footnotes,
        warning_texts=Any[],
        generated=Any[]
    )
    blocks = build_layout_blocks(setter,page_values,method,result)
    heights = Dict(number=>length(note[:lines]) for (number,note) in footnotes)
    pages = choose_pages(
        blocks,
        heights,
        setter.document[:height],
        setter.params["orphan_lines"],
        setter.params["widow_lines"]
    )
    number_pages!(setter,pages,result)
    for number in eachindex(setter.footnotes)
        push!(result[:warning_texts],("footnote $number",footnotes[number],false))
    end
    result
end
function complete_generated_lines!(setter,result)
    for (block,records) in result[:generated]
        texts = block[:kind] == "index" ? index_lines(setter,result[:mark_pages]) : contents_lines(
            setter,
            block,
            result[:block_pages]
        )
        for (line,text) in zip(records,texts)
            line[:text] = text
        end
    end
end
function assemble_pages!(setter,result)
    chapter,section = "",""
    height = setter.document[:height]
    total = length(result[:pages])-result[:front_matter]
    for page in result[:pages]
        if page[:blank]
            page[:header],page[:footer],page[:body] = "","",fill("",height)
            continue
        end
        for line in page[:content]
            haskey(line,:anchor) || continue
            block = setter.blocks[line[:anchor]]
            if block[:kind] == "h1"
                chapter,section = "$(block[:number]) $(block[:text])",""
            elseif block[:kind] == "h2"
                section = "$(block[:number]) $(block[:text])"
            end
        end
        values = Dict("page"=>page[:display],"pages"=>string(total),"chapter"=>chapter,"section"=>section)
        page[:header] = page[:chapter_start] ? "" : running_head(
            setter.document[:header],
            values,
            setter.document[:page_width],
            page[:serial]
        )
        page[:footer] = running_head(
            setter.document[:footer],
            values,
            setter.document[:page_width],
            page[:serial]
        )
        content = [line[:text] for line in page[:content]]
        note_lines = String[]
        for number in page[:footnotes]
            append!(note_lines,[line[:text] for line in result[:footnotes][number][:lines]])
        end
        page[:body] = isempty(note_lines) ? vcat(content,fill("",height-length(content))) : vcat(
            content,
            fill("",height-length(content)-length(note_lines)-1),
            ["----------"],
            note_lines
        )
    end
end
function layout(setter,method)
    page_values = Dict(label=>"??" for label in keys(setter.labels))
    while true
        result = layout_once(setter,page_values,method)
        if result[:label_values] == page_values
            complete_generated_lines!(setter,result)
            assemble_pages!(setter,result)
            return result
        end
        page_values = result[:label_values]
    end
end
function layout_warnings(setter,result)
    warnings = String[]
    for (name,text,justify) in result[:warning_texts]
        for (number,line) in enumerate(text[:broken])
            slack = line.slack
            if slack < 0
                push!(warnings,"$name line $number: overfull by $(-slack)")
            elseif justify && !line.last && slack >= setter.params["underfull_slack"]
                push!(warnings,"$name line $number: underfull, slack $slack")
            end
        end
    end
    for page in result[:pages]
        (page[:blank] || page[:ends_by_force]) && continue
        empty = setter.document[:height]-page[:height]
        empty >= setter.params["underfull_page"] && push!(
            warnings,
            "page $(page[:serial]): underfull, $empty empty lines"
        )
    end
    hyphenated = sum(line.midword for body in values(result[:bodies]) for line in body[:broken];init=0)
    push!(warnings,"$(length(result[:pages])) pages, $hyphenated hyphenated lines")
    ["$(result[:method]): $warning" for warning in warnings]
end
function statistics(setter,optimal,greedy_result)
    lines = ["paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"]
    totals = zeros(Int,4)
    for block in setter.body_blocks
        kp,greedy_body = optimal[:bodies][block[:id]],greedy_result[:bodies][block[:id]]
        values = [length(kp[:broken]),kp[:cost],length(greedy_body[:broken]),greedy_body[:cost]]
        totals .+= values
        push!(lines,join(vcat([block[:paragraph_number]],values),','))
    end
    push!(lines,"total,"*join(totals,','))
    lines
end
function main()
    params = Dict{String,Int}()
    for line in readlines(joinpath("input","params.txt"))
        name,value = split(line)
        params[name] = parse(Int,value)
    end
    document = parse_document(readlines(joinpath("input","document.txt")))
    dictionary = Hyphenation(
        readlines(joinpath("input","hyphenation.txt")),
        document[:hyphenation_words],
        params["left_min"],
        params["right_min"]
    )
    setter = Typesetter(
        document=document,
        params=params,
        dictionary=dictionary,
        blocks=document[:blocks],
        warnings=document[:warnings]
    )
    register_document!(setter)
    check_document!(setter)
    assign_bibliography_labels!(setter)
    prepare_index!(setter)
    sort!(setter.warnings,by=first,alg=MergeSort)
    optimal,greedy_result = layout(setter,"kp"),layout(setter,"greedy")
    warnings = ["line $number: $message" for (number,message) in setter.warnings]
    append!(warnings,layout_warnings(setter,optimal))
    append!(warnings,layout_warnings(setter,greedy_result))
    outputs = (
        "pages.txt"=>pages_lines(optimal[:pages]),"greedy_pages.txt"=>pages_lines(greedy_result[:pages]),
        "stats.csv"=>statistics(setter,optimal,greedy_result),"log.txt"=>warnings
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do handle
            foreach(line->println(handle,line),lines)
        end
    end
end
main()
