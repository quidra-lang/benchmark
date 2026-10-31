function build_sequence(blocks,orphan_lines,widow_lines)
    lines = Dict{Symbol,Any}[]
    boundaries = Tuple{Int,Int,Bool}[]
    for (index,block) in enumerate(blocks)
        start = length(lines)
        append!(lines,block[:lines])
        count = length(block[:lines])
        if block[:kind] == "flow"
            for kept in 1:count-1
                if kept >= orphan_lines && count-kept >= widow_lines
                    push!(boundaries,(start+kept,start+kept,false))
                end
            end
        end
        if index == length(blocks)
            push!(boundaries,(length(lines),length(lines),true))
            continue
        end
        following = blocks[index+1]
        stop = length(lines)
        !(block[:list] && following[:list]) && push!(lines,text_line(""))
        forced = following[:page_break]
        (forced || block[:kind] != "heading") && push!(boundaries,(stop,length(lines),forced))
    end
    lines,boundaries
end
function choose_pages(blocks,footnote_heights,height,orphan_lines,widow_lines)
    lines,boundaries = build_sequence(blocks,orphan_lines,widow_lines)
    pages = Dict{Symbol,Any}[]
    start,first_boundary = 0,1
    while start < length(lines)
        notes = Set{Int}()
        note_height,scanned = 0,start
        chosen = nothing
        for index in first_boundary:length(boundaries)
            stop,next_start,forced = boundaries[index]
            while scanned < stop
                for number in lines[scanned+1][:footnotes]
                    if !(number in notes)
                        push!(notes,number)
                        note_height += footnote_heights[number]
                    end
                end
                scanned += 1
            end
            used = stop-start+note_height+(!isempty(notes) ? 1 : 0)
            used > height && break
            chosen = (index,stop,next_start,forced,used,sort(collect(notes)))
            forced && break
        end
        index,stop,next_start,forced,used,page_notes = chosen
        push!(
            pages,
            record(
                content=lines[start+1:stop],
                footnotes=page_notes,
                height=used,
                ends_by_force=forced,
                blank=false
            )
        )
        start,first_boundary = next_start,index+1
    end
    pages
end
