const SYSTEMS = split("HEPBURN TRADITIONAL KUNREI NIHON WAPURO")
const ROWS = split("a ka sa ta na ha ma ya ra wa ga za da ba pa")
const BASE_ROWS = ROWS[1:10]
const ROW_TEXT = ["a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
    "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo", "ra ri ru re ro",
    "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo", "da di du de do", "ba bi bu be bo", "pa pi pu pe po"]
const CONTRACT_ROWS = split("ka sa ta na ha ma ra ga za da ba pa")
const BASE_ROW = Dict("ga"=>"ka", "za"=>"sa", "da"=>"ta", "ba"=>"ha", "pa"=>"ha")
const DEVOICE = Dict('g'=>'k', 'z'=>'s', 'd'=>'t', 'b'=>'h', 'p'=>'h')
const GOJUON = split("a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N")
const IROHA = split("i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N")
const ARG_COUNTS = Dict("SET"=>2, "TABLE"=>2, "CONVERT"=>2, "NORMALIZE"=>0,
    "REVERSE"=>1, "VALID"=>1, "DETECT"=>0, "DIFF"=>2, "SAME"=>2, "MORAE"=>1,
    "SYLLABLES"=>1, "ROW"=>1, "STATS"=>1, "SORT"=>1, "INDEX"=>1, "FIND"=>2,
    "HAIKU"=>1, "KAIBUN"=>1, "SHIRITORI"=>1)
const SET_VALUES = Dict("LONG"=>split("KEEP DROP PASSPORT HYPHEN DOUBLE"),
    "CASE"=>split("KEEP LOWER UPPER TITLE"), "ORDER"=>split("GOJUON IROHA"))

function metadata()
    identifiers = String[]
    row_of = Dict{String,String}()
    dan_of = Dict{String,String}()
    i_of = Dict{String,String}()
    for (row,text) in zip(ROWS,ROW_TEXT)
        for id in split(text)
            push!(identifiers,id)
            row_of[id] = row
            dan_of[id] = string(last(id))
            last(id) == 'i' && (i_of[row] = id)
        end
    end
    for row in CONTRACT_ROWS
        stem = i_of[row][1:end-1]
        for dan in ("ya","yu","yo")
            id = stem*dan
            push!(identifiers,id)
            row_of[id] = row
            dan_of[id] = dan
        end
    end
    return identifiers,row_of,dan_of,i_of
end
const MORA_METADATA = metadata()
const IDS = MORA_METADATA[1]
const ROW_OF = MORA_METADATA[2]
const DAN_OF = MORA_METADATA[3]
const I_OF = MORA_METADATA[4]

function spelling(system,id)
    id in ("N","Q","-") && return id
    if system in ("HEPBURN","TRADITIONAL","WAPURO")
        changes = Dict("si"=>"shi", "ti"=>"chi", "tu"=>"tsu", "hu"=>"fu", "zi"=>"ji")
        if system != "WAPURO"
            merge!(changes,Dict("di"=>"ji", "du"=>"zu", "wi"=>"i", "we"=>"e", "wo"=>"o"))
        end
        haskey(changes,id) && return changes[id]
        if startswith(id,"sy")
            return "sh"*id[3:end]
        elseif startswith(id,"ty")
            return "ch"*id[3:end]
        elseif startswith(id,"zy") || (system != "WAPURO" && startswith(id,"dy"))
            return "j"*id[3:end]
        end
    elseif system == "KUNREI"
        changes = Dict("di"=>"zi", "du"=>"zu", "wi"=>"i", "we"=>"e", "wo"=>"o",
            "dya"=>"zya", "dyu"=>"zyu", "dyo"=>"zyo")
        return get(changes,id,id)
    end
    return id
end

function reading_tables()
    tables = Dict{String,Vector{Pair{String,String}}}()
    for system in vcat(String.(SYSTEMS),["NORMAL"])
        seen = Dict{String,String}()
        styles = system == "NORMAL" ? ["HEPBURN","KUNREI","NIHON","WAPURO"] : [system]
        for id in IDS
            for style in styles
                text = spelling(style,id)
                !haskey(seen,text) && (seen[text] = id)
            end
        end
        tables[system] = sort(collect(seen);by=pair -> -length(pair.first))
    end
    return tables
end
const READINGS = reading_tables()

fail(message) = throw(ArgumentError(message))
column_error(column,message) = fail("col $column: $message")
is_syllabic(id) = haskey(ROW_OF,id)
is_vowel(id) = id in ("a","i","u","e","o")

function match_syllable(word,position,system)
    position > length(word) && return nothing
    for pair in READINGS[system]
        startswith(SubString(word,position),pair.first) && return pair
    end
    return nothing
end

function parse_word(text,start,system)
    word = lowercase(text)
    ids = String[]
    columns = Int[]
    p = 1
    while p <= length(word)
        c = word[p]
        c2 = p < length(word) ? word[p+1] : '\0'
        c3 = p+2 <= length(word) ? word[p+2] : '\0'
        matched = match_syllable(word,p,system)
        advance = 1
        if c == '-'
            (isempty(ids) || !is_syllabic(ids[end])) && column_error(start+p-1,"misplaced long mark")
            id = "-"
        elseif c == '\''
            column_error(start+p-1,"misplaced apostrophe")
        elseif matched !== nothing
            id = matched.second
            advance = length(matched.first)
        elseif system in ("WAPURO","NORMAL") && startswith(SubString(word,p),"xtu")
            id = "Q"
            advance = 3
        elseif c == 'n'
            id = "N"
            if system == "WAPURO"
                advance = c2 == 'n' ? 2 : 1
            elseif system == "NORMAL"
                if c2 == '\'' || (c2 == 'n' && !(c3 in ('a','i','u','e','o','y','\'')))
                    advance = 2
                end
            elseif c2 == '\''
                advance = 2
            end
        elseif system in ("TRADITIONAL","NORMAL") && c == 'm' && c2 in ('b','m','p')
            id = "N"
        elseif 'a' <= c <= 'z' && !(c in ('a','i','u','e','o','n')) && c == c2 && match_syllable(word,p+1,system) !== nothing
            id = "Q"
        elseif system in ("HEPBURN","TRADITIONAL","NORMAL") && c == 't' && c2 == 'c' && c3 == 'h' && match_syllable(word,p+1,system) !== nothing
            id = "Q"
        else
            column_error(start+p-1,"unknown syllable")
        end
        push!(ids,id)
        push!(columns,start+p-1)
        p += advance
    end
    return ids,columns
end

function long_flags(ids)
    paired = falses(length(ids))
    long = [id == "-" for id in ids]
    i = 1
    while i < length(ids)
        first,second = ids[i],ids[i+1]
        if is_syllabic(first) && is_vowel(second)
            vowel = string(last(first))
            if vowel == second || (vowel == "o" && second == "u") || (vowel == "e" && second == "i")
                paired[i+1] = true
                long[i+1] = (vowel == "o" && second in ("o","u")) || (vowel == "u" && second == "u")
                i += 2
                continue
            end
        end
        i += 1
    end
    return paired,long
end

function write_parts(ids,columns,system,long_setting)
    paired,long = long_flags(ids)
    parts = String[]
    for i in eachindex(ids)
        id = ids[i]
        next_id = i < length(ids) ? ids[i+1] : ""
        next_text = is_syllabic(next_id) ? spelling(system,next_id) : ""
        first = isempty(next_text) ? '\0' : next_text[1]
        if long[i]
            vowel = last(ids[i-1])
            if long_setting == "KEEP"
                part = id == "-" ? "-" : spelling(system,id)
            elseif long_setting == "DROP"
                part = ""
            elseif long_setting == "PASSPORT"
                part = vowel == 'o' && !(first in ('a','i','u','e','o')) ? "h" : ""
            elseif long_setting == "HYPHEN"
                part = "-"
            else
                part = string(vowel)
            end
        elseif is_syllabic(id)
            part = spelling(system,id)
        elseif id == "N"
            if system == "WAPURO"
                part = next_id == "N" || first in ('a','i','u','e','o','y','n') ? "nn" : "n"
            elseif system == "TRADITIONAL" && first in ('b','m','p')
                part = "m"
            else
                part = first in ('a','i','u','e','o','y') ? "n'" : "n"
            end
        else
            if !isempty(next_text) && !(first in ('a','i','u','e','o','n'))
                part = system in ("HEPBURN","TRADITIONAL") && startswith(next_text,"ch") ? "t" : string(first)
            elseif system == "WAPURO"
                part = "xtu"
            else
                column_error(columns[i],"small tsu cannot be written")
            end
        end
        push!(parts,part)
    end
    return parts
end

mutable struct RomajiWord
    text::String
    start::Int
    pattern::String
    ids::Vector{String}
    columns::Vector{Int}
    part::Int
    index::Int
end

function word_pattern(text)
    text == lowercase(text) && return "LOWER"
    if 'A' <= text[1] <= 'Z' && text[2:end] == lowercase(text[2:end])
        return "TITLE"
    end
    if count(c -> 'A' <= c <= 'Z',text) >= 2 && text == uppercase(text)
        return "UPPER"
    end
    return ""
end

function written(word,system,settings;canonical=false,ids=word.ids,columns=word.columns)
    mode = canonical ? "KEEP" : settings["LONG"]
    text = join(write_parts(ids,columns,system,mode))
    pattern = canonical || settings["CASE"] == "KEEP" ? word.pattern : settings["CASE"]
    pattern == "UPPER" && return uppercase(text)
    pattern == "TITLE" && return uppercase(text[1:1])*text[2:end]
    return text
end

function words_in(text)
    result = RomajiWord[]
    for matched in eachmatch(r"[A-Za-z'-]+",text)
        start = matched.offset
        part = count(==('/'),text[1:start-1])+1
        push!(result,RomajiWord(String(matched.match),start,"",String[],Int[],part,length(result)+1))
    end
    return result
end

function replace_words(text,words,replacements)
    result = IOBuffer()
    position = 1
    for (word,replacement) in zip(words,replacements)
        print(result,text[position:word.start-1],replacement)
        position = word.start+length(word.text)
    end
    print(result,text[position:end])
    return String(take!(result))
end

function devoice(id)
    return string(get(DEVOICE,id[1],id[1]),id[2:end])
end

function elements(ids)
    result = Tuple{String,Int,Int}[]
    for id in ids
        if id == "-"
            continue
        elseif id == "N"
            push!(result,("N",0,0))
        elseif id == "Q"
            push!(result,("tu",0,1))
        else
            row = ROW_OF[id]
            voice = 0
            if row in ("ga","za","da","ba")
                voice = 1
            elseif row == "pa"
                voice = 2
            end
            if length(DAN_OF[id]) == 2
                push!(result,(devoice(I_OF[row]),voice,0))
                push!(result,(DAN_OF[id],0,1))
            else
                push!(result,(devoice(id),voice,0))
            end
        end
    end
    return result
end

function collation(word,order)
    ranks = order == "GOJUON" ? GOJUON : IROHA
    items = elements(word.ids)
    return (Tuple(findfirst(==(item[1]),ranks) for item in items),
        Tuple(item[2] for item in items),Tuple(item[3] for item in items),
        Tuple(id == "-" ? 1 : 0 for id in word.ids),word.index)
end

function pattern_tokens(pattern,system)
    occursin(r"^[a-z'\-?*]+$",pattern) || fail("invalid pattern")
    tokens = String[]
    chunk = ""
    try
        for c in pattern
            if c in ('?','*')
                append!(tokens,parse_word(chunk,1,system)[1])
                push!(tokens,string(c))
                chunk = ""
            else
                chunk *= string(c)
            end
        end
        append!(tokens,parse_word(chunk,1,system)[1])
    catch exception
        exception isa ArgumentError || rethrow()
        fail("invalid pattern")
    end
    return tokens
end

function wildcard_matches(tokens,ids)
    previous = falses(length(ids)+1)
    previous[1] = true
    for token in tokens
        current = falses(length(ids)+1)
        token == "*" && (current[1] = previous[1])
        for j in eachindex(ids)
            if token == "*"
                current[j+1] = previous[j+1] || current[j]
            else
                current[j+1] = previous[j] && (token == "?" || token == ids[j])
            end
        end
        previous = current
    end
    return previous[end]
end

function execute(line,settings)
    command = split(line,' ';limit=2)[1]
    haskey(ARG_COUNTS,command) || fail("unknown command $command")
    k = ARG_COUNTS[command]
    if command in ("SET","TABLE")
        parts = split(line,' ')
        length(parts) < 3 && fail("missing argument")
        length(parts) > 3 && fail("too many arguments")
        args = parts[2:3]
        text = ""
    else
        count(==(' '),line) >= k+1 || fail("missing argument")
        parts = split(line,' ';limit=k+2)
        args = parts[2:k+1]
        text = String(parts[end])
    end
    system_count = 1
    if command in ("SET","NORMALIZE","DETECT")
        system_count = 0
    elseif command in ("CONVERT","DIFF","SAME")
        system_count = 2
    end
    for system in args[1:system_count]
        system in SYSTEMS || fail("unknown system $system")
    end
    if command == "SET"
        option,value = args
        haskey(SET_VALUES,option) || fail("unknown option $option")
        value in SET_VALUES[option] || fail("unknown value $value")
        settings[option] = value
        return "$option=$value"
    elseif command == "TABLE"
        system,row = args
        row in ROWS || fail("unknown row $row")
        return join([spelling(system,id) for id in IDS if ROW_OF[id] == row]," ")
    end
    tokens = command == "FIND" ? pattern_tokens(args[2],args[1]) : String[]
    slash_allowed = command in ("HAIKU","SAME")
    for (column,c) in enumerate(text)
        allowed = 'A' <= c <= 'Z' || 'a' <= c <= 'z' || '0' <= c <= '9' || c in "'- .,!?;:()\"" || (slash_allowed && c == '/')
        allowed || column_error(column,"invalid character")
    end
    words = words_in(text)
    if command == "SAME"
        (count(==('/'),text) == 1 && any(w.part == 1 for w in words) && any(w.part == 2 for w in words)) || fail("expected two texts")
    elseif command == "HAIKU"
        lines = count(==('/'),text)+1
        (lines in (3,5) && all(any(w.part == i for w in words) for i in 1:lines)) || fail("expected 3 or 5 lines")
    end
    isempty(words) && fail("no words")
    for word in words
        word.pattern = word_pattern(word.text)
        isempty(word.pattern) && column_error(word.start,"mixed case")
    end
    if command == "DETECT"
        output = String[]
        for system in SYSTEMS
            verdict = "canonical"
            try
                for word in words
                    word.ids,word.columns = parse_word(word.text,word.start,system)
                end
                for word in words
                    if written(word,system,settings;canonical=true) != word.text
                        verdict = "readable"
                    end
                end
            catch exception
                exception isa ArgumentError || rethrow()
                verdict = "error"
            end
            push!(output,"$system=$verdict")
        end
        return join(output," ")
    end
    for word in words
        if command == "NORMALIZE"
            system = "NORMAL"
        elseif command == "SAME"
            system = args[word.part]
        else
            system = args[1]
        end
        word.ids,word.columns = parse_word(word.text,word.start,system)
    end
    system = command == "NORMALIZE" ? "HEPBURN" : args[1]
    if command in ("CONVERT","NORMALIZE","REVERSE")
        target = command == "CONVERT" ? args[2] : system
        output = String[]
        for word in words
            ids = word.ids
            columns = word.columns
            if command == "REVERSE"
                ids = [id == "-" ? string(last(word.ids[i-1])) : id for (i,id) in enumerate(word.ids)]
                ids = reverse(ids)
                columns = reverse(columns)
            end
            push!(output,written(word,target,settings;ids=ids,columns=columns))
        end
        return replace_words(text,words,output)
    elseif command == "VALID"
        for word in words
            expected = written(word,system,settings;canonical=true)
            if expected != word.text
                i = 1
                while i <= min(length(expected),length(word.text)) && expected[i] == word.text[i]
                    i += 1
                end
                return "INVALID col $(word.start+i-1): expected $expected"
            end
        end
        return "VALID"
    elseif command == "DIFF"
        output = String[]
        for word in words
            first = written(word,args[1],settings)
            second = written(word,args[2],settings)
            first != second && push!(output,first*">"*second)
        end
        prefix = "$(length(output)) of $(length(words))"
        return isempty(output) ? prefix : prefix*": "*join(output," ")
    elseif command == "SAME"
        left = filter(w -> w.part == 1,words)
        right = filter(w -> w.part == 2,words)
        exact = true
        for i in 1:min(length(left),length(right))
            a,b = left[i].ids,right[i].ids
            a_loose = a[.!long_flags(a)[2]]
            b_loose = b[.!long_flags(b)[2]]
            a_loose != b_loose && return "DIFFERENT at word $i"
            exact &= a == b
        end
        length(left) != length(right) && return "DIFFERENT at word $(min(length(left),length(right))+1)"
        return exact ? "EXACT" : "LOOSE"
    elseif command == "MORAE"
        output = [join(spelling.(Ref(system),word.ids),".") for word in words]
        return "$(sum(length(w.ids) for w in words)): "*join(output," ")
    elseif command == "SYLLABLES"
        output = String[]
        total = 0
        for word in words
            paired,long = long_flags(word.ids)
            parts = write_parts(word.ids,word.columns,system,"KEEP")
            syllables = String[]
            for i in eachindex(word.ids)
                if i > 1 && (!is_syllabic(word.ids[i]) || paired[i])
                    syllables[end] *= parts[i]
                else
                    push!(syllables,parts[i])
                end
            end
            total += length(syllables)
            push!(output,join(syllables,"."))
        end
        return "$total: "*join(output," ")
    elseif command == "ROW"
        output = String[]
        for word in words
            for id in word.ids
                push!(output,is_syllabic(id) ? "$(spelling(system,id)): $(ROW_OF[id]) $(DAN_OF[id])" : "$id: special")
            end
        end
        return join(output,", ")
    elseif command == "STATS"
        counts = Dict(name=>0 for name in vcat(String.(BASE_ROWS),split("voiced semivoiced contracted N Q L")))
        total = 0
        for word in words
            for id in word.ids
                total += 1
                if is_syllabic(id)
                    row = ROW_OF[id]
                    counts[get(BASE_ROW,row,row)] += 1
                    row in ("ga","za","da","ba") && (counts["voiced"] += 1)
                    row == "pa" && (counts["semivoiced"] += 1)
                    length(DAN_OF[id]) == 2 && (counts["contracted"] += 1)
                else
                    counts[id == "-" ? "L" : id] += 1
                end
            end
        end
        output = ["morae=$total"]
        append!(output,["$row=$(counts[row])" for row in BASE_ROWS if counts[row] > 0])
        append!(output,["$name=$(counts[name])" for name in split("voiced semivoiced contracted N Q L")])
        return join(output," ")
    elseif command in ("SORT","INDEX")
        ordered = sort(words;by=w -> collation(w,settings["ORDER"]))
        command == "SORT" && return join([word.text for word in ordered]," ")
        groups = String[]
        previous = ""
        for word in ordered
            base = elements(word.ids)[1][1]
            heading = settings["ORDER"] == "IROHA" || base == "N" ? base : ROW_OF[base]
            if heading == previous
                groups[end] *= " "*word.text
            else
                push!(groups,heading*": "*word.text)
                previous = heading
            end
        end
        return join(groups,"; ")
    elseif command == "FIND"
        output = [word.text for word in words if wildcard_matches(tokens,word.ids)]
        prefix = "$(length(output)) of $(length(words))"
        return isempty(output) ? prefix : prefix*": "*join(output," ")
    elseif command == "HAIKU"
        counts = [sum(length(w.ids) for w in words if w.part == i) for i in 1:count(==('/'),text)+1]
        expected = length(counts) == 3 ? [5,7,5] : [5,7,5,7,7]
        verdict = counts == expected ? "OK" : "NG"
        form = length(counts) == 3 ? "haiku" : "tanka"
        return "$verdict $form "*join(counts,"-")
    elseif command == "KAIBUN"
        bases = [item[1] for word in words for item in elements(word.ids)]
        return (bases == reverse(bases) ? "YES " : "NO ")*join(bases,".")
    elseif command == "SHIRITORI"
        seen = Vector{String}[]
        previous = ""
        for (i,word) in enumerate(words)
            items = elements(word.ids)
            head,tail = items[1][1],items[end][1]
            if i > 1 && head != previous
                return "NG $i: $(word.text) must start with $(spelling(system,previous))"
            elseif word.ids in seen
                return "NG $i: $(word.text) is repeated"
            elseif tail == "N"
                return "NG $i: $(word.text) ends with N"
            end
            push!(seen,word.ids)
            previous = tail
        end
        return "OK $(length(words))"
    end
end

function main()
    count = parse(Int,readline())
    settings = Dict("LONG"=>"KEEP", "CASE"=>"KEEP", "ORDER"=>"GOJUON")
    for i in 1:count
        line = readline()
        try
            println(execute(line,settings))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
