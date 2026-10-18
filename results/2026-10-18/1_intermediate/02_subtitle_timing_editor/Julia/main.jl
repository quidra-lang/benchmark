using Printf

mutable struct SubtitleCue
    index::Int
    start::Int
    stop::Int
    lines::Vector{String}
end

const SCHEMAS = Dict(
    "LIST"=>"", "VALIDATE"=>"", "SEARCH"=>"string", "AT"=>"time", "GAPS"=>"0:60000",
    "STATS"=>"", "PRINT"=>"", "TOVTT"=>"", "TOASS"=>"", "FRAMES"=>"fps",
    "SHIFT"=>"signed", "SHIFTFROM"=>"pos signed", "SCALE"=>"1:100000 1:100000",
    "SYNC"=>"pos time pos time", "SNAP"=>"fps", "FIXOVERLAP"=>"0:60000", "EXTEND"=>"1:60000",
    "TIME"=>"pos time time", "SORT"=>"", "RENUMBER"=>"", "MERGE"=>"0:60000", "SPLIT"=>"10:80",
    "INSERT"=>"pos time time text", "DELETE"=>"delete", "TEXT"=>"pos text", "BALANCE"=>"",
    "STRIP"=>"", "CLEANHI"=>"", "REPLACE"=>"replace", "UNDO"=>"")
const MODIFYING = Set(split("SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE"))
const FORMAT_TAGS = Dict("<i>"=>raw"{\i1}", "</i>"=>raw"{\i0}", "<b>"=>raw"{\b1}",
    "</b>"=>raw"{\b0}", "<u>"=>raw"{\u1}", "</u>"=>raw"{\u0}")

bad_arguments() = throw(ArgumentError("bad arguments"))
round_ratio(n,d) = fld(2*n+d,2*d)
char_count(cue) = sum(length(line) for line in cue.lines)
dialogue(cue) = any(startswith(line,"- ") for line in cue.lines)
cue_words(lines) = String.(split(join(lines," ")))
trim_spaces(text) = String(strip(text,[' ']))
two_decimal(value) = @sprintf("%d.%02d",div(value,100),value%100)

function time_value(text)
    occursin(r"^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}$",text) || bad_arguments()
    h,m,s,ms = parse.(Int,split(text,r"[:,]"))
    m <= 59 && s <= 59 || bad_arguments()
    return h*3600000+m*60000+s*1000+ms
end

function time_text(t,kind="SRT")
    if kind == "ASS"
        c = div(t+5,10)
        return @sprintf("%d:%02d:%02d.%02d",div(c,360000),div(c,6000)%60,div(c,100)%60,c%100)
    end
    separator = kind == "VTT" ? '.' : ','
    return @sprintf("%02d:%02d:%02d%c%03d",div(t,3600000),div(t,60000)%60,div(t,1000)%60,separator,t%1000)
end

function unsigned_arg(text,low=0,high=999999999)
    occursin(r"^[0-9]{1,9}$",text) || bad_arguments()
    value = parse(Int,text)
    low <= value <= high || bad_arguments()
    return value
end

function typed_arg(text,kind)
    kind == "string" && return String(text)
    kind == "time" && return time_value(text)
    kind == "pos" && return unsigned_arg(text,1)
    if kind == "signed"
        occursin(r"^-?[0-9]{1,9}$",text) || bad_arguments()
        return parse(Int,text)
    elseif kind == "fps"
        parts = split(text,'/';keepempty=true)
        1 <= length(parts) <= 2 || bad_arguments()
        a = unsigned_arg(parts[1],1,100000)
        b = length(parts) == 1 ? 1 : unsigned_arg(parts[2],1,100000)
        return (a,b)
    elseif kind in ("text","replace")
        parts = String.(split(text,'|';keepempty=true))
        all(!isempty(part) for part in parts) || bad_arguments()
        kind == "replace" && length(parts) != 2 && bad_arguments()
        return parts
    end
    low,high = parse.(Int,split(kind,':'))
    return unsigned_arg(text,low,high)
end

function arguments(line,cues)
    command = String(split(line,' ';limit=2)[1])
    haskey(SCHEMAS,command) || throw(ArgumentError("unknown command"))
    if command == "DELETE"
        raw = split(line,' ')[2:end]
        1 <= length(raw) <= 2 || bad_arguments()
        args = unsigned_arg.(raw,1)
        length(args) == 2 && args[2] < args[1] && bad_arguments()
        kinds = fill("pos",length(args))
    else
        kinds = split(SCHEMAS[command])
        if !isempty(kinds) && kinds[end] in ("string","text","replace")
            parts = split(line,' ';limit=length(kinds)+1)
        else
            parts = split(line,' ')
        end
        length(parts) == length(kinds)+1 || bad_arguments()
        args = Any[typed_arg(parts[i+1],kinds[i]) for i in eachindex(kinds)]
    end
    for (kind,arg) in zip(kinds,args)
        if kind == "pos" && arg > length(cues)+(command == "INSERT" ? 1 : 0)
            throw(ArgumentError("no cue $arg"))
        end
    end
    command == "SYNC" && cues[args[1]].start == cues[args[3]].start && throw(ArgumentError("sync points coincide"))
    return command,args
end

function wrap_lines(lines,width)
    output = String[]
    for word in cue_words(lines)
        if !isempty(output) && length(output[end])+1+length(word) <= width
            output[end] *= " "*word
        else
            push!(output,word)
        end
    end
    return output
end

function markup(line)
    items = Tuple{String,String,Int}[]
    p = 1
    while p <= length(line)
        rest = SubString(line,p)
        tags = collect(keys(FORMAT_TAGS))
        tag = findfirst(tag -> startswith(rest,tag),tags)
        if tag !== nothing
            text = tags[tag]
            push!(items,("format",text,0))
            p += length(text)
        elseif startswith(rest,"</font>")
            push!(items,("font","</font>",0))
            p += 7
        elseif startswith(rest,"<font") && p+5 <= length(line) && line[p+5] in (' ','>') && findnext('>',line,p+5) !== nothing
            ending = findnext('>',line,p+5)
            push!(items,("font",line[p:ending],0))
            p = ending+1
        elseif p+5 <= length(line) && line[p:p+3] == raw"{\an" && '1' <= line[p+4] <= '9' && line[p+5] == '}'
            push!(items,("position",line[p:p+5],Int(line[p+4]-'0')))
            p += 6
        else
            push!(items,("ordinary",string(line[p]),0))
            p += 1
        end
    end
    return items
end

function converted_line(line,mode)
    output = IOBuffer()
    tags = 0
    position = 0
    for (kind,text,digit) in markup(line)
        if kind != "ordinary"
            tags += 1
        end
        kind == "position" && position == 0 && (position = digit)
        if kind == "ordinary"
            value = mode == "VTT" ? get(Dict("&"=>"&amp;","<"=>"&lt;",">"=>"&gt;"),text,text) : text
            print(output,value)
        elseif mode == "VTT" && kind == "format"
            print(output,text)
        elseif mode == "ASS" && kind == "format"
            print(output,FORMAT_TAGS[text])
        elseif mode == "ASS" && kind == "position"
            print(output,text)
        end
    end
    result = String(take!(output))
    return mode == "ASS" ? result : trim_spaces(result),tags,position
end

function clean_hi(line)
    output = IOBuffer()
    segments = 0
    p = 1
    while p <= length(line)
        closing = '\0'
        if line[p] == '['
            closing = ']'
        elseif line[p] == '('
            closing = ')'
        end
        ending = closing == '\0' ? nothing : findnext(closing,line,p+1)
        if ending !== nothing
            segments += 1
            p = ending+1
        else
            print(output,line[p])
            p += 1
        end
    end
    normalize(text) = trim_spaces(replace(text,r" +"=>" "))
    result = normalize(String(take!(output)))
    prefix = startswith(result,"- ") ? "- " : ""
    body = isempty(prefix) ? result : result[3:end]
    matched = match(r"^[A-Z][A-Z0-9 ]*:",body)
    labels = matched === nothing ? 0 : 1
    if matched !== nothing
        result = normalize(prefix*body[length(matched.match)+1:end])
    end
    return result,segments,labels
end

function list_line(cue,p)
    return string(p,' ',cue.index,' ',time_text(cue.start),' ',time_text(cue.stop),' ',join(cue.lines,"|"))
end

function inspect(command,args,cues)
    output = String[]
    n = length(cues)
    if command in ("LIST","AT")
        for (p,cue) in enumerate(cues)
            if command == "LIST" || cue.start <= args[1] < cue.stop
                push!(output,list_line(cue,p))
            end
        end
        command == "AT" && push!(output,"AT active=$(length(output))")
    elseif command == "VALIDATE"
        for (p,cue) in enumerate(cues)
            d = cue.stop-cue.start
            cue.index != p && push!(output,"cue $p: index $(cue.index) (expected $p)")
            d <= 0 && push!(output,"cue $p: end not after start")
            p > 1 && cue.start < cues[p-1].stop && push!(output,"cue $p: overlaps previous by $(cues[p-1].stop-cue.start) ms")
            if 1 <= d < 700
                push!(output,"cue $p: too short ($d ms)")
            elseif d > 7000
                push!(output,"cue $p: too long ($d ms)")
            end
            for (j,line) in enumerate(cue.lines)
                length(line) > 42 && push!(output,"cue $p: line $j too long ($(length(line)) chars)")
            end
            length(cue.lines) >= 3 && push!(output,"cue $p: too many lines ($(length(cue.lines)))")
            d >= 1 && char_count(cue)*1000 > 21*d && push!(output,"cue $p: too fast ($(two_decimal(div(char_count(cue)*100000,d))) cps)")
        end
        push!(output,"VALIDATE problems=$(length(output))")
    elseif command == "SEARCH"
        for (p,cue) in enumerate(cues)
            j = findfirst(line -> occursin(args[1],line),cue.lines)
            j !== nothing && push!(output,"$p $(time_text(cue.start)) $(cue.lines[j])")
        end
        push!(output,"SEARCH found=$(length(output))")
    elseif command == "GAPS"
        for p in 1:n-1
            gap = cues[p+1].start-cues[p].stop
            gap < args[1] && push!(output,"$p $(p+1) $gap")
        end
        push!(output,"GAPS count=$(length(output))")
    elseif command == "STATS"
        push!(output,"STATS cues=$n")
        n == 0 && return output
        durations = [max(0,cue.stop-cue.start) for cue in cues]
        total = sum(durations)
        characters = sum((char_count(cues[i]) for i in eachindex(cues) if durations[i] > 0);init=0)
        push!(output,"duration total=$(time_text(total)) mean=$(time_text(div(total,n)))")
        push!(output,total == 0 ? "speed -" : "speed $(two_decimal(div(characters*100000,total)))")
        p = argmax(durations)
        push!(output,"longest cue=$p duration=$(time_text(durations[p]))")
        if n == 1
            push!(output,"gap none")
        else
            gaps = [cues[i+1].start-cues[i].stop for i in 1:n-1]
            p = argmax(gaps)
            push!(output,"gap cue=$p ms=$(gaps[p])")
        end
    elseif command == "PRINT"
        for cue in cues
            append!(output,[string(cue.index),time_text(cue.start)*" --> "*time_text(cue.stop)])
            append!(output,cue.lines)
            push!(output,"")
        end
    elseif command == "TOVTT"
        append!(output,["WEBVTT",""])
        for cue in cues
            lines = String[]
            position = 0
            for line in cue.lines
                text,tags,digit = converted_line(line,"VTT")
                position == 0 && digit > 0 && (position = digit)
                !isempty(text) && push!(lines,text)
            end
            isempty(lines) && continue
            settings = ""
            if position >= 7
                settings *= " line:0"
            elseif position >= 4
                settings *= " line:50%"
            end
            if position in (1,4,7)
                settings *= " align:start"
            elseif position in (3,6,9)
                settings *= " align:end"
            end
            append!(output,[string(cue.index),time_text(cue.start,"VTT")*" --> "*time_text(cue.stop,"VTT")*settings])
            append!(output,lines)
            push!(output,"")
        end
    elseif command == "TOASS"
        append!(output,["[Events]","Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"])
        for cue in cues
            text = join([converted_line(line,"ASS")[1] for line in cue.lines],raw"\N")
            push!(output,"Dialogue: 0,$(time_text(cue.start,"ASS")),$(time_text(cue.stop,"ASS")),Default,,0,0,0,,$text")
        end
    elseif command == "FRAMES"
        a,b = args[1]
        for (p,cue) in enumerate(cues)
            push!(output,"$p $(div(cue.start*a,1000*b)) $(div(cue.stop*a,1000*b))")
        end
    end
    return output
end

function modify(command,args,cues)
    output = String[]
    n = length(cues)
    if command in ("SHIFT","SHIFTFROM","SCALE","SYNC","SNAP")
        first = command == "SHIFTFROM" ? args[1] : 1
        clamped = 0
        changed = 0
        if command == "SYNC"
            p1,t1,p2,t2 = args
            s1,s2 = cues[p1].start,cues[p2].start
            den = s2-s1
            transform = t -> den > 0 ? round_ratio(t1*den+(t-s1)*(t2-t1),den) : round_ratio(-t1*den-(t-s1)*(t2-t1),-den)
        elseif command == "SCALE"
            transform = t -> round_ratio(t*args[1],args[2])
        elseif command == "SNAP"
            a,b = args[1]
            transform = t -> round_ratio(round_ratio(t*a,1000*b)*1000*b,a)
        else
            delta = command == "SHIFT" ? args[1] : args[2]
            transform = t -> t+delta
        end
        for p in first:n
            cue = cues[p]
            start,stop = transform(cue.start),transform(cue.stop)
            clamped += start < 0 || stop < 0
            start,stop = max(0,start),max(0,stop)
            changed += (start != cue.start)+(stop != cue.stop)
            cue.start,cue.stop = start,stop
        end
        if command == "SNAP"
            push!(output,"SNAP changed=$changed")
        elseif command == "SCALE"
            push!(output,"SCALE cues=$n")
        else
            push!(output,"$command cues=$(max(0,n-first+1)) clamped=$clamped")
        end
    elseif command == "FIXOVERLAP"
        fixed,failed = 0,0
        for p in 1:n-1
            cue = cues[p]
            candidate = cues[p+1].start-args[1]
            if cue.stop > candidate
                if candidate > cue.start
                    cue.stop = candidate
                    fixed += 1
                else
                    push!(output,"cue $p: cannot fix")
                    failed += 1
                end
            end
        end
        push!(output,"FIXOVERLAP fixed=$fixed failed=$failed")
    elseif command == "EXTEND"
        extended = 0
        for (p,cue) in enumerate(cues)
            if cue.stop-cue.start < args[1]
                candidate = cue.start+args[1]
                p < n && (candidate = min(candidate,cues[p+1].start))
                if candidate > cue.stop
                    cue.stop = candidate
                    extended += 1
                end
            end
        end
        short = count(cue -> cue.stop-cue.start < args[1],cues)
        push!(output,"EXTEND extended=$extended short=$short")
    elseif command == "TIME"
        p,start,stop = args
        cues[p].start,cues[p].stop = start,stop
        push!(output,"TIME cue=$p")
    elseif command == "SORT"
        indices = sortperm(1:n;by=i -> (cues[i].start,cues[i].stop,i))
        moved = count(i -> indices[i] != i,1:n)
        cues = cues[indices]
        push!(output,"SORT moved=$moved")
    elseif command == "RENUMBER"
        changed = 0
        for (p,cue) in enumerate(cues)
            changed += cue.index != p
            cue.index = p
        end
        push!(output,"RENUMBER changed=$changed")
    elseif command == "MERGE"
        result = SubtitleCue[]
        merged = 0
        for cue in cues
            if !isempty(result) && cue.start-result[end].stop < args[1] && !dialogue(result[end]) && !dialogue(cue)
                lines = wrap_lines(vcat(result[end].lines,cue.lines),42)
                if length(lines) <= 2
                    result[end].stop = max(result[end].stop,cue.stop)
                    result[end].lines = lines
                    merged += 1
                    continue
                end
            end
            push!(result,cue)
        end
        cues = result
        push!(output,"MERGE merged=$merged cues=$(length(cues))")
    elseif command == "SPLIT"
        result = SubtitleCue[]
        split_count = 0
        for cue in cues
            duration = cue.stop-cue.start
            if duration <= 0 || dialogue(cue)
                push!(result,cue)
                continue
            end
            lines = wrap_lines(cue.lines,args[1])
            if length(lines) <= 2
                cue.lines = lines
                push!(result,cue)
                continue
            end
            parts = [lines[i:min(i+1,length(lines))] for i in 1:2:length(lines)]
            weights = [sum(length(line) for line in part) for part in parts]
            total = sum(weights)
            allotted = [div(duration*weight,total) for weight in weights]
            order = sortperm(1:length(parts);by=i -> (-mod(duration*weights[i],total),i))
            for i in 1:duration-sum(allotted)
                allotted[order[i]] += 1
            end
            start = cue.start
            for (i,part) in enumerate(parts)
                push!(result,SubtitleCue(cue.index,start,start+allotted[i],part))
                start += allotted[i]
            end
            split_count += 1
        end
        cues = result
        push!(output,"SPLIT split=$split_count cues=$(length(cues))")
    elseif command == "INSERT"
        p,start,stop,lines = args
        insert!(cues,p,SubtitleCue(p,start,stop,lines))
        push!(output,"INSERT cue=$p cues=$(length(cues))")
    elseif command == "DELETE"
        p = args[1]
        q = length(args) == 1 ? p : args[2]
        deleteat!(cues,p:q)
        push!(output,"DELETE removed=$(q-p+1) cues=$(length(cues))")
    elseif command == "TEXT"
        p,lines = args
        cues[p].lines = lines
        push!(output,"TEXT cue=$p lines=$(length(lines))")
    elseif command == "BALANCE"
        changed,skipped,dialogues = 0,0,0
        for cue in cues
            if dialogue(cue)
                dialogues += 1
                continue
            end
            words = cue_words(cue.lines)
            text = join(words," ")
            candidate = nothing
            best = (typemax(Int),typemax(Int))
            if length(text) <= 42
                candidate = [text]
            else
                for j in 1:length(words)-1
                    left,right = join(words[1:j]," "),join(words[j+1:end]," ")
                    key = (abs(length(left)-length(right)),length(left))
                    if length(left) <= 42 && length(right) <= 42 && isless(key,best)
                        candidate,best = [left,right],key
                    end
                end
            end
            if candidate === nothing
                skipped += 1
            else
                changed += cue.lines != candidate
                cue.lines = candidate
            end
        end
        push!(output,"BALANCE changed=$changed skipped=$skipped dialogue=$dialogues")
    elseif command in ("STRIP","CLEANHI")
        result = SubtitleCue[]
        tags,labels,removed_lines,removed_cues = 0,0,0,0
        for cue in cues
            lines = String[]
            for line in cue.lines
                if command == "STRIP"
                    text,count,digit = converted_line(line,"STRIP")
                    tags += count
                else
                    text,count,speakers = clean_hi(line)
                    tags += count
                    labels += speakers
                end
                if isempty(text) || (command == "CLEANHI" && text == "-")
                    removed_lines += 1
                else
                    push!(lines,text)
                end
            end
            if isempty(lines)
                removed_cues += 1
            else
                cue.lines = lines
                push!(result,cue)
            end
        end
        cues = result
        if command == "STRIP"
            push!(output,"STRIP tags=$tags removed_lines=$removed_lines removed_cues=$removed_cues")
        else
            push!(output,"CLEANHI segments=$tags labels=$labels removed_lines=$removed_lines removed_cues=$removed_cues")
        end
    elseif command == "REPLACE"
        old,new = args[1]
        replacements,changed = 0,0
        for cue in cues
            local_count = sum(length(findall(old,line)) for line in cue.lines)
            replacements += local_count
            changed += local_count > 0
            cue.lines = [replace(line,old=>new) for line in cue.lines]
        end
        push!(output,"REPLACE count=$replacements cues=$changed")
    end
    return cues,output
end

function load_block(block,k,cues)
    if !occursin(r"^[0-9]{1,6}$",block[1])
        return "BAD CUE $k: index"
    end
    try
        length(block) >= 2 && length(block[2]) == 29 && block[2][13:17] == " --> " || bad_arguments()
        start,stop = time_value(block[2][1:12]),time_value(block[2][18:29])
        length(block) >= 3 || return "BAD CUE $k: no text"
        push!(cues,SubtitleCue(parse(Int,block[1]),start,stop,copy(block[3:end])))
    catch exception
        exception isa ArgumentError || rethrow()
        return "BAD CUE $k: time"
    end
    return ""
end

function main()
    cues = SubtitleCue[]
    block = String[]
    blocks,bad = 0,0
    while true
        line = readline()
        if isempty(line) || line == "###"
            if !isempty(block)
                blocks += 1
                problem = load_block(block,blocks,cues)
                if !isempty(problem)
                    println(problem)
                    bad += 1
                end
                empty!(block)
            end
            line == "###" && break
        else
            push!(block,line)
        end
    end
    println("LOAD cues=$(length(cues)) bad=$bad")
    history = Tuple{String,Vector{SubtitleCue}}[]
    count = parse(Int,readline())
    for i in 1:count
        line = readline()
        try
            command,args = arguments(line,cues)
            if command == "UNDO"
                isempty(history) && throw(ArgumentError("nothing to undo"))
                previous,cues = pop!(history)
                output = ["UNDO command=$previous"]
            elseif command in MODIFYING
                push!(history,(command,deepcopy(cues)))
                cues,output = modify(command,args,cues)
            else
                output = inspect(command,args,cues)
            end
            foreach(println,output)
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
