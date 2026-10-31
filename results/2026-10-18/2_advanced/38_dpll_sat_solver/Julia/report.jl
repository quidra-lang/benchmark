named(;items...) = join(("$key=$value" for (key,value) in items),' ')
number_list(values) = isempty(values) ? "-" : join(values,',')
function frequency(values)
    counts = Dict{Int,Int}()
    for value in values
        counts[value] = get(counts,value,0)+1
    end
    isempty(counts) ? "-" : join(("$key:$(counts[key])" for key in sort(collect(keys(counts)))),',')
end
heading(job) = "JOB $(job[:number]) $(job[:text])"
function save_lines(filename,lines)
    mkpath("output")
    open(joinpath("output",filename),"w") do handle
        foreach(line->println(handle,line),lines)
    end
end
function save_paragraphs(filename,paragraphs)
    lines = String[]
    for (index,paragraph) in enumerate(paragraphs)
        index > 1 && push!(lines,"")
        append!(lines,paragraph)
    end
    save_lines(filename,lines)
end
queens_board(columns) = [repeat(".",column-1)*"Q"*repeat(".",length(columns)-column) for column in columns]
