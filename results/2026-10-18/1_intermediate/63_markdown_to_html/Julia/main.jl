const WHITE = " \n"
const PUNCT = "!\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
const TOC = "\x01toc\x02"
part(s, a, b=lastindex(s)) = a > b ? "" : String(s[a:b])
starts(s, prefix, at=1) = startswith(part(s, at), prefix)
escapehtml(s) = replace(s, '&'=>"&amp;", '<'=>"&lt;", '>'=>"&gt;", '"'=>"&quot;")
striptags(s) = replace(s, r"<[^>]*>"=>"")
normalize(s) = join(split(lowercase(s)), " ")
trim(s) = String(strip(s, ' '))
ltrim(s) = String(lstrip(s, ' '))
function skipspace(s, at)
    while at <= length(s) && s[at] in WHITE
        at += 1
    end
    at
end
function escapedread(s, at, stops)
    out = IOBuffer()
    while at <= length(s) && !(s[at] in stops)
        if s[at] == '\\' && at < length(s) && s[at+1] in PUNCT
            at += 1
        end
        print(out, s[at]); at += 1
    end
    String(take!(out)), at
end
struct Reference
    url::String
    title::Union{Nothing,String}
end
mutable struct Block
    kind::Symbol
    text::String
    number::Int
    ordered::Bool
    lines::Vector{String}
    children::Vector{Block}
    items::Vector{Vector{Block}}
    alignments::Vector{String}
    rows::Vector{Vector{String}}
end
Block(kind, text="", number=0) = Block(kind, text, number, false, String[], Block[], Vector{Block}[], String[], Vector{String}[])
mutable struct Parser
    references::Dict{String,Reference}
    footnotes::Dict{String,String}
end
Parser() = Parser(Dict{String,Reference}(), Dict{String,String}())
function fence(line)
    m = match(r"^(`{3,}|~{3,})", line)
    m === nothing && return nothing
    run = String(m.match); info = trim(part(line, length(run)+1))
    first(run) == '`' && occursin('`', info) && return nothing
    run, info
end
function atx(line)
    m = match(r"^(#{1,6})(?: |$)", line)
    m === nothing && return nothing
    n = length(m.captures[1]); text = trim(part(line, n+1))
    shorter = String(rstrip(text, '#'))
    if isempty(shorter) || endswith(shorter, " ")
        text = trim(shorter)
    end
    Block(:heading, text, n)
end
rule(line) = occursin(r"^(?:-{3,}|\*{3,}|_{3,})$", replace(line, " "=>""))
function marker(line)
    rule(line) && return nothing
    m = match(r"^(?:([-*+])|([0-9]{1,9})([.)])) +", line)
    m === nothing && return nothing
    ordered = m.captures[2] !== nothing
    kind = String(ordered ? m.captures[3] : m.captures[1])
    kind, ordered, ordered ? parse(Int, m.captures[2]) : 1, part(line, length(m.match)+1)
end
interrupts(line) = !startswith(line," ") && (fence(line)!==nothing || atx(line)!==nothing || rule(line) || startswith(line,">") || marker(line)!==nothing)
function cells(line)
    text = trim(line); at = startswith(text,"|") ? 2 : 1
    result = String[]; out = IOBuffer(); final_separator = false
    while at <= length(text)
        ch = text[at]; at += 1; final_separator = false
        if ch == '\\' && at <= length(text)
            text[at] != '|' && print(out, '\\')
            print(out,text[at]); at += 1
        elseif ch == '|'
            push!(result,trim(String(take!(out)))); final_separator = true
        else
            print(out,ch)
        end
    end
    !final_separator && push!(result,trim(String(take!(out))))
    result
end
function definition!(p, line)
    m = match(r"^\[\^([A-Za-z0-9_-]+)\]:(.*)$",line)
    if m !== nothing && !isempty(trim(m.captures[2]))
        get!(p.footnotes,lowercase(m.captures[1]),trim(m.captures[2])); return true
    end
    startswith(line,"[") || return false
    close = findfirst(']',line)
    (close === nothing || !starts(line,":",close+1)) && return false
    label = part(line,2,close-1)
    (occursin('[',label) || isempty(trim(label)) || startswith(label,"^")) && return false
    url, finish = escapedread(line,skipspace(line,close+2)," ")
    isempty(url) && return false
    at = skipspace(line,finish); title = nothing
    if at <= length(line)
        (at == finish || !(line[at] in "\"'")) && return false
        title, finish = escapedread(line,at+1,string(line[at]))
        finish == length(line) || return false
    end
    get!(p.references,normalize(label),Reference(url,title)); true
end
function parseblocks!(p, lines)
    blocks = Block[]; at = 1
    while at <= length(lines)
        line = lines[at]
        if isempty(line)
            at += 1; continue
        elseif startswith(line,"    ")
            finish = at
            while finish <= length(lines) && (isempty(lines[finish]) || startswith(lines[finish],"    "))
                finish += 1
            end
            while isempty(lines[finish-1]); finish -= 1; end
            b = Block(:code); b.lines = [part(s,5) for s in lines[at:finish-1]]
            push!(blocks,b); at = finish; continue
        end
        if !startswith(line," ")
            f = fence(line)
            if f !== nothing
                run, info = f; b = Block(:code, isempty(info) ? "" : String(first(split(info,' '))))
                at += 1
                while at <= length(lines)
                    row = lines[at]; at += 1
                    length(row)>=length(run) && all(==(first(run)),row) && break
                    push!(b.lines,row)
                end
                push!(blocks,b); continue
            end
            h = atx(line)
            if h !== nothing; push!(blocks,h); at += 1; continue; end
            if rule(line); push!(blocks,Block(:rule)); at += 1; continue; end
            if startswith(line,">")
                content = String[]
                while at <= length(lines) && startswith(lines[at],">")
                    row = part(lines[at],2); push!(content,starts(row," ") ? part(row,2) : row); at += 1
                end
                alert = match(r"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$",content[1])
                b = alert === nothing ? Block(:quote) : Block(:alert,String(alert.captures[1]))
                b.children = parseblocks!(p,alert === nothing ? content : content[2:end])
                push!(blocks,b); continue
            end
            m = marker(line)
            if m !== nothing
                kind, ordered, number, body = m; b = Block(:list,"",number); b.ordered = ordered
                while true
                    content = [body]; at += 1
                    while at <= length(lines) && startswith(lines[at],"  ")
                        push!(content,part(lines[at],3)); at += 1
                    end
                    push!(b.items,parseblocks!(p,content)); following = at
                    while following<=length(lines) && isempty(lines[following]); following += 1; end
                    next = following<=length(lines) ? marker(lines[following]) : nothing
                    (next===nothing || next[1]!=kind || next[2]!=ordered) && break
                    at = following; body = next[4]
                end
                push!(blocks,b); continue
            end
            if definition!(p,line); at += 1; continue; end
            if at<length(lines) && occursin('|',line) && occursin('|',lines[at+1])
                header = cells(line); delimiters = cells(lines[at+1])
                if length(header)==length(delimiters) && all(c->occursin(r"^:?-+:?$",c),delimiters)
                    b = Block(:table); b.lines = header
                    b.alignments = [startswith(c,":") ? (endswith(c,":") ? "center" : "left") : (endswith(c,":") ? "right" : "") for c in delimiters]
                    at += 2
                    while at<=length(lines) && occursin('|',lines[at])
                        row = cells(lines[at]); resize!(row, min(length(row),length(header)))
                        while length(row)<length(header); push!(row,""); end
                        push!(b.rows,row); at += 1
                    end
                    push!(blocks,b); continue
                end
            end
        end
        finish = at+1; level = 0
        while finish<=length(lines) && !isempty(lines[finish])
            if occursin(r"^(?:={3,}|-{3,})$",lines[finish])
                level = first(lines[finish])=='=' ? 1 : 2; break
            end
            interrupts(lines[finish]) && break
            finish += 1
        end
        text = join(ltrim.(lines[at:finish-1]),"\n")
        push!(blocks,Block(level>0 ? :heading : text=="[TOC]" ? :toc : :paragraph,text,level))
        at = finish+(level>0)
    end
    blocks
end
struct Piece
    html::String
    char::Char
    count::Int
    opens::Bool
    closes::Bool
end
Piece(html::String) = Piece(html,' ',0,false,false)
function emphasis(pieces, first=1, last=length(pieces))
    out = IOBuffer(); at = first
    while at<=last
        p = pieces[at]; close = 0
        if p.opens
            for i in at+1:last
                q = pieces[i]
                if q.closes && q.char==p.char && q.count==p.count; close=i; break; end
            end
        end
        if close>0
            open, shut = p.char=='~' ? ("<del>","</del>") : p.count==1 ? ("<em>","</em>") : p.count==2 ? ("<strong>","</strong>") : ("<em><strong>","</strong></em>")
            print(out,open,emphasis(pieces,at+1,close-1),shut); at=close+1
        else
            print(out,p.count==0 ? p.html : repeat(string(p.char),p.count)); at+=1
        end
    end
    String(take!(out))
end
runend(s,at) = begin
    finish=at+1
    while finish<=length(s) && s[finish]==s[at]; finish+=1; end
    finish
end
function tickclose(s, at, count)
    while at<=length(s)
        if s[at]=='`'
            finish=runend(s,at)
            finish-at==count && return at
            at=finish
        else; at+=1; end
    end
    0
end
function closingbracket(s,at)
    depth=0
    while at<=length(s)
        if s[at]=='\\'; at+=2; continue
        elseif s[at]=='`'
            finish=runend(s,at); close=tickclose(s,finish,finish-at)
            at=close==0 ? finish : close+finish-at; continue
        elseif s[at]=='['; depth+=1
        elseif s[at]==']'
            depth-=1; depth==0 && return at
        end
        at+=1
    end
    0
end
mutable struct Renderer
    references::Dict{String,Reference}
    definitions::Dict{String,String}
    ids::Set{String}
    headings::Vector{Tuple{Int,String,String}}
    notes::Vector{String}
    counts::Vector{Int}
end
Renderer(p::Parser)=Renderer(p.references,p.footnotes,Set{String}(),Tuple{Int,String,String}[],String[],Int[])
function destination(r,s,at,label)
    if starts(s,"[",at)
        close=findnext(']',s,at+1)
        if close!==nothing && !occursin('[',part(s,at+1,close-1))
            raw=part(s,at+1,close-1); name=normalize(isempty(raw) ? label : raw)
            return haskey(r.references,name) ? (r.references[name],close+1) : nothing
        end
    elseif starts(s,"(",at)
        url,finish=escapedread(s,skipspace(s,at+1)," \n)")
        next=skipspace(s,finish); title=nothing; valid=true
        if next>finish && next<=length(s) && s[next] in "\"'"
            title,finish=escapedread(s,next+1,string(s[next]))
            valid=finish<=length(s); next=skipspace(s,finish+1)
        end
        valid && starts(s,")",next) && return (Reference(url,title),next+1)
    end
    name=normalize(label)
    haskey(r.references,name) ? (r.references[name],at) : nothing
end
refid(n,count)=count==1 ? "fnref-$n" : "fnref-$n-$count"
function noteref!(r,name)
    n=findfirst(==(name),r.notes)
    if n===nothing; push!(r.notes,name); push!(r.counts,0); n=length(r.notes); end
    r.counts[n]+=1; id=refid(n,r.counts[n])
    "<sup id=\"$id\"><a href=\"#fn-$n\">$n</a></sup>"
end
function inline!(r,s; links=true, notes=true)
    pieces=Piece[]; at=1
    while at<=length(s)
        ch=s[at]
        if ch=='\\'
            if at<length(s) && s[at+1] in PUNCT
                push!(pieces,Piece(escapehtml(string(s[at+1])))); at+=2
            elseif at<length(s) && s[at+1]=='\n'
                push!(pieces,Piece("<br />\n")); at+=2
            else; push!(pieces,Piece("\\")); at+=1; end
            continue
        elseif ch=='`'
            finish=runend(s,at); count=finish-at; close=tickclose(s,finish,count)
            if close==0; push!(pieces,Piece(repeat("`",count))); at=finish
            else
                code=replace(part(s,finish,close-1),"\n"=>" ")
                if startswith(code," ") && endswith(code," ") && !isempty(trim(code)); code=part(code,2,length(code)-1); end
                push!(pieces,Piece("<code>$(escapehtml(code))</code>")); at=close+count
            end
            continue
        end
        if links
            if ch=='<'
                close=findnext('>',s,at+1)
                if close!==nothing
                    target=part(s,at+1,close-1)
                    url=occursin(r"^https?://[^ \n<]+\z",target)
                    email=occursin(r"^[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z",target)
                    if url || email
                        href=escapehtml((email && !url ? "mailto:" : "")*target)
                        push!(pieces,Piece("<a href=\"$href\">$(escapehtml(target))</a>")); at=close+1; continue
                    end
                end
            end
            if (at==1 || s[at-1] in " \n*_~(") && (starts(s,"http://",at) || starts(s,"https://",at))
                finish=at
                while finish<=length(s) && !(s[finish] in " \n<"); finish+=1; end
                while finish>at && s[finish-1] in ".,:;!?*_~)"; finish-=1; end
                url=part(s,at,finish-1)
                if !(url in ("http://","https://"))
                    escaped=escapehtml(url); push!(pieces,Piece("<a href=\"$escaped\">$escaped</a>")); at=finish; continue
                end
            end
        end
        if ch=='[' || (ch=='!' && starts(s,"[",at+1))
            if links && notes && starts(s,"[^",at)
                close=findnext(']',s,at+2)
                if close!==nothing
                    name=lowercase(part(s,at+2,close-1))
                    if haskey(r.definitions,name)
                        push!(pieces,Piece(noteref!(r,name))); at=close+1; continue
                    end
                end
            end
            image=ch=='!'
            if image || links
                opening=at+image; close=closingbracket(s,opening)
                if close>0
                    label=part(s,opening+1,close-1); dest=destination(r,s,close+1,label)
                    if dest!==nothing
                        reference,finish=dest; content=inline!(r,label;links=false,notes=false)
                        title=reference.title===nothing ? "" : " title=\"$(escapehtml(reference.title))\""
                        url=escapehtml(reference.url)
                        html=image ? "<img src=\"$url\" alt=\"$(striptags(content))\"$title />" : "<a href=\"$url\"$title>$content</a>"
                        push!(pieces,Piece(html)); at=finish; continue
                    end
                end
            end
        end
        if ch in "*_~"
            finish=runend(s,at); count=finish-at
            before=at==1 ? ' ' : s[at-1]; after=finish>length(s) ? ' ' : s[finish]
            opens=!(after in WHITE); closes=!(before in WHITE)
            if ch=='_' && isletterordigit(before) && isletterordigit(after); opens=closes=false; end
            if (ch!='~' && count<=3) || (ch=='~' && count==2)
                push!(pieces,Piece("",ch,count,opens,closes))
            else; push!(pieces,Piece(repeat(string(ch),count))); end
            at=finish; continue
        end
        push!(pieces,Piece(escapehtml(string(ch)))); at+=1
    end
    emphasis(pieces)
end
isletterordigit(c)=('a'<=c<='z') || ('A'<=c<='Z') || ('0'<=c<='9')
function renderheading!(r,b)
    text=b.text; m=match(r"^(.*) \{#([A-Za-z0-9_-]+)\}$"s,text)
    if m!==nothing
        text=String(rstrip(m.captures[1],' ')); id=String(m.captures[2])
    else
        base=replace(replace(lowercase(text),r"[^a-z0-9_ \n-]"=>""),r"[ \n]"=>"-")
        isempty(base) && (base="heading")
        id=base; suffix=1
        while id in r.ids; id="$base-$suffix"; suffix+=1; end
    end
    push!(r.ids,id); html=inline!(r,text); push!(r.headings,(b.number,id,striptags(html)))
    "<h$(b.number) id=\"$id\">$html</h$(b.number)>"
end
renderblocks!(r,blocks)=join((renderblock!(r,b)*"\n" for b in blocks))
function renderitem!(r,blocks)
    html="<li>"
    for (i,b) in enumerate(blocks)
        if b.kind==:paragraph
            text=b.text
            if i==1 && length(text)>4 && part(text,1,4) in ("[ ] ","[x] ","[X] ")
                checked=text[2]==' ' ? "" : " checked=\"\""
                html*="<input type=\"checkbox\"$checked disabled=\"\" /> "; text=part(text,5)
            end
            html*=inline!(r,text)
        else
            !endswith(html,"\n") && (html*="\n")
            html*=renderblock!(r,b)*"\n"
        end
    end
    html*"</li>"
end
function renderblock!(r,b)
    if b.kind==:heading; return renderheading!(r,b)
    elseif b.kind==:paragraph; return "<p>$(inline!(r,b.text))</p>"
    elseif b.kind==:rule; return "<hr />"
    elseif b.kind==:toc; return TOC
    elseif b.kind==:code
        attr=isempty(b.text) ? "" : " class=\"language-$(escapehtml(b.text))\""
        return "<pre><code$attr>"*join(escapehtml(s)*"\n" for s in b.lines)*"</code></pre>"
    elseif b.kind==:quote; return "<blockquote>\n"*renderblocks!(r,b.children)*"</blockquote>"
    elseif b.kind==:alert
        title=uppercasefirst(lowercase(b.text))
        return "<div class=\"alert alert-$(lowercase(b.text))\">\n<p class=\"alert-title\">$title</p>\n"*renderblocks!(r,b.children)*"</div>"
    elseif b.kind==:list
        tag=b.ordered ? "ol" : "ul"; attr=b.ordered && b.number!=1 ? " start=\"$(b.number)\"" : ""
        return "<$tag$attr>\n"*join(renderitem!(r,item)*"\n" for item in b.items)*"</$tag>"
    end
    lines=["<table>","<thead>","<tr>"]
    function row!(tag,row)
        for (align,cell) in zip(b.alignments,row)
            style=isempty(align) ? "" : " style=\"text-align:$align\""
            push!(lines,"<$tag$style>$(inline!(r,cell))</$tag>")
        end
    end
    row!("th",b.lines); append!(lines,["</tr>","</thead>"])
    if !isempty(b.rows)
        push!(lines,"<tbody>")
        for row in b.rows; push!(lines,"<tr>"); row!("td",row); push!(lines,"</tr>"); end
        push!(lines,"</tbody>")
    end
    push!(lines,"</table>"); join(lines,"\n")
end
function toc(r)
    parents=Int[]; stack=Int[]
    for (i,(level,id,label)) in enumerate(r.headings)
        while !isempty(stack) && r.headings[last(stack)][1]>=level; pop!(stack); end
        push!(parents,isempty(stack) ? 0 : last(stack)); push!(stack,i)
    end
    function listing(parent)
        html="<ul>\n"
        for i in findall(==(parent),parents)
            _,id,label=r.headings[i]; html*="<li><a href=\"#$id\">$label</a>"
            if i in parents; html*="\n"*listing(i)*"\n"; end
            html*="</li>\n"
        end
        html*"</ul>"
    end
    "<nav class=\"toc\">\n"*(isempty(parents) ? "" : listing(0)*"\n")*"</nav>"
end
function footnotes!(r)
    isempty(r.notes) && return ""
    html="<section class=\"footnotes\">\n<ol>\n"
    for (n,name) in enumerate(r.notes)
        body=inline!(r,r.definitions[name];notes=false)
        links=join(("<a href=\"#$(refid(n,j))\">&#8617;</a>" for j in 1:r.counts[n])," ")
        html*="<li id=\"fn-$n\">$body $links</li>\n"
    end
    html*"</ol>\n</section>\n"
end
function main()
    lines=String[]
    for line in eachline(stdin)
        line=="@@END@@" && break
        push!(lines,line)
    end
    parser=Parser(); blocks=parseblocks!(parser,lines); renderer=Renderer(parser)
    html=renderblocks!(renderer,blocks)
    print(replace(html,TOC=>toc(renderer)),footnotes!(renderer))
end
main()
