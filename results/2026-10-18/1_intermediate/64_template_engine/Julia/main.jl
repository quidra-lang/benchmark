const IDENT = r"^[A-Za-z_][A-Za-z0-9_]*$"
const KEY = r"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[(?:0|[1-9][0-9]*)\])*$"
const NAME = r"^(?:\.|@(?:index|number|first|last)|(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*)(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*))*)$"
const NUMBER = r"^-?[0-9]{1,9}\z"
const FILTERS = split("upper lower title trim length first last reverse items comma sum min max default eq pad lpad truncate replace join sort pluck add sub mul div mod gt lt")
struct TemplateError <: Exception
    number::Int
    reason::String
end
fail(n, s) = throw(TemplateError(n, s))
part(s, a, b=length(s)) = a > b ? "" : String(s[a:b])
trim(s) = String(strip(s, ' '))
haspart(v, p) = p isa String ? v isa Dict && haskey(v,p) : v isa Vector && 0 <= p < length(v)
getpart(v, p) = v[p isa Integer ? p+1 : p]
function put!(v, p, x)
    if v isa Vector && p == length(v); push!(v,x)
    else; v[p isa Integer ? p+1 : p] = x; end
end
function keyparts(key, n)
    occursin(KEY,key) || fail(n,"bad key '$key'")
    [(m.captures[1] === nothing ? parse(Int,m.captures[2]) : String(m.captures[1]), part(key,1,m.offset+length(m.match)-1))
     for m in eachmatch(r"([A-Za-z_][A-Za-z0-9_]*)|\[([0-9]+)\]",key)]
end
function scalar(s, at)
    if at <= length(s) && s[at] == '"'
        out = IOBuffer(); at += 1
        while at <= length(s)
            c = s[at]; at += 1
            c == '"' && return String(take!(out)),at
            if c == '\\'
                at <= length(s) || error("value")
                c = s[at]; at += 1
                c in ('"','\\','n') || error("value")
                c == 'n' && (c = '\n')
            end
            print(out,c)
        end
        error("value")
    end
    finish = at
    while finish <= length(s) && !(s[finish] in ",]"); finish += 1; end
    word = part(s,at,finish-1)
    word == "true" && return true,finish
    word == "false" && return false,finish
    occursin(r"^(?:0|-?[1-9][0-9]*)$",word) || error("value")
    parse(Int,word),finish
end
function value(s,n)
    try
        s == "[]" && return Any[]
        s == "{}" && return Dict{String,Any}()
        if startswith(s,"[")
            list = Any[]; at = 2
            while true
                x,at = scalar(s,at); push!(list,x)
                part(s,at) == "]" && return list
                startswith(part(s,at),", ") || error("value")
                at += 2
            end
        end
        x,at = scalar(s,1); at == length(s)+1 || error("value"); x
    catch
        fail(n,"bad value '$s'")
    end
end
function assign!(root,line,n)
    separator = findfirst(" = ",line)
    separator === nothing && fail(n,"bad line")
    key = part(line,1,first(separator)-1); parts = keyparts(key,n)
    x = value(part(line,last(separator)+1),n); current = root
    for (i,(p,prefix)) in enumerate(parts)
        p isa Int && p > length(current) && fail(n,"index gap at '$prefix'")
        if i == length(parts); put!(current,p,x); break; end
        kind = parts[i+1][1] isa String ? Dict : Vector
        if haspart(current,p)
            getpart(current,p) isa kind || fail(n,"type conflict at '$prefix'")
        else
            put!(current,p,kind === Dict ? Dict{String,Any}() : Any[])
        end
        current = getpart(current,p)
    end
end
function unset!(root,key,n)
    parts = keyparts(key,n); current = root
    for (i,(p,_)) in enumerate(parts)
        haspart(current,p) || fail(n,"no value at '$key'")
        if i == length(parts)
            current isa Vector ? deleteat!(current,p+1) : delete!(current,p)
        else; current = getpart(current,p); end
    end
end
truth(v) = v !== nothing && (v isa Bool ? v : v isa Int ? v != 0 : !isempty(v))
function text(v,n)
    v === nothing && return ""
    v isa String && return v
    v isa Bool && return v ? "true" : "false"
    v isa Int && return string(v)
    v isa Vector && return join((text(x,n) for x in v),", ")
    fail(n,"cannot render map")
end
function number(v,f,n)
    v === nothing && return 0
    v isa Int && !(v isa Bool) && return v
    v isa String && occursin(NUMBER,v) && return parse(Int,v)
    fail(n,"not a number for '$f'")
end
function unquoted(s,separator)
    result = String[]; at = 1; quoted = false
    for i in eachindex(s)
        if s[i] == '\''; quoted = !quoted
        elseif s[i] == separator && !quoted
            push!(result,part(s,at,i-1)); at=i+1
        end
    end
    push!(result,part(s,at)); result
end
function argumentsvalid(f,a)
    ints = all(x->x isa Int,a); strings = all(x->x isa String,a)
    f in ("default","eq") && return length(a)==1
    f in ("pad","lpad") && return length(a) in (1,2) && a[1] isa Int && a[1]>=0 && (length(a)==1 || a[2] isa String && length(a[2])==1)
    f=="truncate" && return length(a)==1 && ints && a[1]>=0
    f=="replace" && return length(a)==2 && strings && !isempty(a[1])
    f in ("join","pluck") && return length(a)==1 && strings
    f=="sort" && return length(a)<=1 && strings
    f in ("div","mod") && return length(a)==1 && ints && a[1]!=0
    f in ("add","sub","mul","gt","lt") && return length(a)==1 && ints
    isempty(a)
end
function expression(s,n)
    pieces = unquoted(s,'|'); name = trim(pieces[1])
    occursin(NAME,name) || fail(n,"invalid name '$name'")
    filters = Tuple{String,Vector{Any}}[]
    for piece in pieces[2:end]
        fields = unquoted(trim(piece),':'); f = fields[1]
        f in FILTERS || fail(n,"unknown filter '$f'")
        a = Any[]
        for raw in fields[2:end]
            if occursin(r"^'[^']*'$",raw); push!(a,part(raw,2,length(raw)-1))
            elseif occursin(NUMBER,raw); push!(a,parse(Int,raw))
            else; fail(n,"bad arguments for '$f'"); end
        end
        argumentsvalid(f,a) || fail(n,"bad arguments for '$f'")
        push!(filters,(f,a))
    end
    name,filters
end
mutable struct Node
    kind::Char
    number::Int
    argument::String
    expression::Any
    children::Vector{Node}
    indent::String
end
Node(k,n,s) = Node(k,n,s,nothing,Node[],"")
function source(lines)
    opening="{{"; closing="}}"; roots=Node[]; targets=[roots]; stack=Node[]
    for (n,line) in lines
        tokens=Node[]; at=1
        while true
            found=findnext(opening,line,at)
            if found===nothing; push!(tokens,Node('t',n,part(line,at))); break; end
            start=first(found); push!(tokens,Node('t',n,part(line,at,start-1)))
            after=start+length(opening); triple=startswith(part(line,after),"{")
            stop=triple ? "}"*closing : closing
            finish=findnext(stop,line,after+triple)
            finish===nothing && fail(n,"unclosed tag")
            content=trim(part(line,after+triple,first(finish)-1)); at=last(finish)+1
            k=triple ? '&' : !isempty(content) && first(content) in "#^/!>&=" ? first(content) : 'v'
            arg=k in ('v','=') || triple ? content : trim(part(content,2))
            tag=Node(k,n,arg)
            if k=='='
                fields=length(content)>=2 && endswith(content,"=") ? split(part(content,2,length(content)-1),' ';keepempty=false) : String[]
                length(fields)==2 && all(x->!occursin('=',x),fields) || fail(n,"invalid delimiters")
                opening,closing=String.(fields)
            elseif k in ('v','&','#','^')
                tag.expression=expression(arg,n)
                k in ('#','^') && push!(stack,tag)
            elseif k=='/'
                occursin(NAME,arg) || fail(n,"invalid name '$arg'")
                isempty(stack) && fail(n,"unexpected closing '$arg'")
                expected=last(stack).expression[1]
                arg==expected || fail(n,"mismatched closing '$arg', expected '$expected'")
                pop!(stack)
            elseif k=='>'
                occursin(IDENT,arg) || fail(n,"invalid name '$arg'")
            end
            push!(tokens,tag)
        end
        tags=filter(x->x.kind!='t',tokens)
        standalone=length(tags)==1 && tags[1].kind in "#^/!>=" && all(x->x.kind!='t' || isempty(trim(x.argument)),tokens)
        if standalone
            tags[1].kind=='>' && (tags[1].indent=tokens[1].argument)
            tokens=tags
        else; push!(tokens,Node('t',n,"\n")); end
        for node in tokens
            if node.kind=='/'; pop!(targets)
            elseif node.kind in ('#','^'); push!(last(targets),node); push!(targets,node.children)
            elseif !(node.kind in ('!','=')); push!(last(targets),node); end
        end
    end
    !isempty(stack) && fail(last(stack).number,"unclosed section '$(last(stack).expression[1])'")
    roots
end
field(v,k) = v isa Dict ? get(v,k,nothing) : nothing
rank(v) = v===nothing ? (0,0) : v isa Bool ? (3,Int(v)) : v isa Int ? (1,v) : v isa String ? (2,v) : (4,0)
function applyfilter(f,a,v,n)
    f=="upper" && return uppercase(text(v,n))
    f=="lower" && return lowercase(text(v,n))
    if f=="title"
        s=text(v,n); return join(i==1 || s[i-1]==' ' ? uppercase(string(s[i])) : lowercase(string(s[i])) for i in eachindex(s))
    end
    f=="trim" && return trim(text(v,n))
    f=="length" && return v isa Union{Vector,Dict} ? length(v) : length(text(v,n))
    f in ("first","last") && return !(v isa Vector) ? v : isempty(v) ? nothing : f=="first" ? first(v) : last(v)
    f=="reverse" && return v isa Union{Vector,String} ? reverse(v) : v
    f=="items" && return v isa Dict ? Any[Dict{String,Any}("key"=>k,"value"=>v[k]) for k in sort!(collect(keys(v)))] : v
    if f=="comma"
        x=number(v,f,n); s=string(abs(x)); groups=String[]
        while length(s)>3; pushfirst!(groups,part(s,length(s)-2)); s=part(s,1,length(s)-3); end
        return (x<0 ? "-" : "")*join(pushfirst!(groups,s),",")
    end
    if f in ("sum","min","max")
        v isa Vector || return number(v,f,n)
        nums=[number(x,f,n) for x in v]
        return f=="sum" ? sum(nums;init=0) : isempty(nums) ? nothing : f=="min" ? minimum(nums) : maximum(nums)
    end
    f=="default" && return truth(v) ? v : a[1]
    f=="eq" && return text(v,n)==text(a[1],n)
    if f in ("pad","lpad")
        s=text(v,n); fill=repeat(length(a)==1 ? " " : a[2],max(0,a[1]-length(s)))
        return f=="pad" ? s*fill : fill*s
    end
    if f=="truncate"; s=text(v,n); return length(s)>a[1] ? part(s,1,a[1])*"..." : s; end
    f=="replace" && return replace(text(v,n),a[1]=>a[2])
    f=="join" && return v isa Vector ? join((text(x,n) for x in v),a[1]) : text(v,n)
    f=="sort" && return v isa Vector ? sort(v;by=x->rank(isempty(a) ? x : field(x,a[1])),alg=Base.Sort.MergeSort) : v
    f=="pluck" && return v isa Vector ? Any[field(x,a[1]) for x in v] : v
    x=number(v,f,n); y=a[1]
    f=="add" ? x+y : f=="sub" ? x-y : f=="mul" ? x*y : f=="div" ? fld(x,y) : f=="mod" ? mod(x,y) : f=="gt" ? x>y : x<y
end
function resolve(name,contexts,loops)
    name=="." && return true,last(contexts)
    if startswith(name,"@")
        isempty(loops) && return false,nothing
        i,count=last(loops)
        return true,name=="@index" ? i : name=="@number" ? i+1 : name=="@first" ? i==0 : i==count-1
    end
    parts=Any[occursin(r"^[0-9]+$",p) ? parse(BigInt,p) : String(p) for p in split(name,'.')]
    for context in reverse(contexts)
        if haspart(context,parts[1])
            v=context
            for p in parts; haspart(v,p) || return false,nothing; v=getpart(v,p); end
            return true,v
        end
    end
    false,nothing
end
escapehtml(s)=replace(s,'&'=>"&amp;",'<'=>"&lt;",'>'=>"&gt;",'"'=>"&quot;",'\''=>"&#39;")
function render(nodes,contexts,loops,partials,strict,depth=0)
    out=IOBuffer()
    for node in nodes
        k=node.kind; n=node.number
        if k=='t'; print(out,node.argument); continue; end
        if k=='>'
            name=node.argument
            haskey(partials,name) || fail(n,"unknown partial '$name'")
            depth==8 && fail(n,"partial depth exceeded at '$name'")
            lines=[(i,isempty(s) ? s : node.indent*s) for (i,s) in partials[name]]
            print(out,render(source(lines),contexts,loops,partials,strict,depth+1)); continue
        end
        name,filters=node.expression; found,v=resolve(name,contexts,loops)
        !found && strict && k in ('v','&') && fail(n,"missing '$name'")
        for (f,a) in filters; v=applyfilter(f,a,v,n); end
        if k in ('v','&'); s=text(v,n); print(out,k=='&' ? s : escapehtml(s))
        elseif k=='^'; !truth(v) && print(out,render(node.children,contexts,loops,partials,strict,depth))
        elseif v isa Vector
            for (i,x) in enumerate(v)
                print(out,render(node.children,[contexts;Any[x]], [loops;[(i-1,length(v))]],partials,strict,depth))
            end
        elseif truth(v); print(out,render(node.children,[contexts;Any[v]],loops,partials,strict,depth)); end
    end
    String(take!(out))
end
notation(v)=v isa String ? "\""*replace(v,'\\'=>"\\\\",'"'=>"\\\"",'\n'=>"\\n")*"\"" : v isa Bool ? (v ? "true" : "false") : v isa Int ? string(v) : v isa Vector ? "[]" : "{}"
function leaves!(result,v,path)
    if v isa Dict && !isempty(v)
        for k in sort!(collect(keys(v))); leaves!(result,v[k],isempty(path) ? k : path*"."*k); end
    elseif v isa Vector && !isempty(v)
        for (i,x) in enumerate(v); leaves!(result,x,path*"[$(i-1)]"); end
    elseif !isempty(path); push!(result,path*" = "*notation(v)); end
end
function showtemplate(name,templates,root,partials,strict)
    try
        result=render(source(templates[name]),Any[root],Tuple{Int,Int}[],partials,strict)
        lines=isempty(result) ? String[] : String.(split(result,'\n';keepempty=true))
        !isempty(lines) && isempty(last(lines)) && pop!(lines)
        println("TEMPLATE $name OK lines=$(length(lines)) chars=$(length(result))")
        foreach(println,lines)
    catch e
        e isa TemplateError || rethrow()
        println("TEMPLATE $name ERROR line $(e.number): $(e.reason)")
    end
end
function main()
    lines=readlines(); root=Dict{String,Any}(); partials=Dict{String,Vector{Tuple{Int,String}}}(); templates=copy(partials); strict=false; at=1
    while lines[at]!="END"
        line=lines[at]; n=at; fields=split(line,' ';limit=2); cmd=fields[1]; name=length(fields)==2 ? String(fields[2]) : ""; at+=1
        if cmd in ("DATA","PARTIAL","TEMPLATE")
            marker=cmd=="DATA" ? "ENDDATA" : cmd=="PARTIAL" ? "ENDPARTIAL" : "ENDTEMPLATE"
            body=Tuple{Int,String}[]
            while lines[at]!=marker; push!(body,(at,lines[at])); at+=1; end
            at+=1
            if cmd=="DATA"
                sets=0; unsets=0; errors=String[]
                for (i,s) in body
                    (isempty(s) || startswith(s,"#")) && continue
                    candidate=deepcopy(root)
                    try
                        if startswith(s,"UNSET "); unset!(candidate,part(s,7),i); unsets+=1
                        else; assign!(candidate,s,i); sets+=1; end
                        root=candidate
                    catch e
                        e isa TemplateError || rethrow()
                        push!(errors,"ERROR line $(e.number): $(e.reason)")
                    end
                end
                println("DATA set=$sets unset=$unsets errors=$(length(errors))"); foreach(println,errors)
            elseif cmd=="PARTIAL"
                try
                    source(body); status=haskey(partials,name) ? "REPLACED" : "DEFINED"; partials[name]=body
                    println("PARTIAL $name $status lines=$(length(body))")
                catch e
                    e isa TemplateError || rethrow(); println("PARTIAL $name ERROR line $(e.number): $(e.reason)")
                end
            else; templates[name]=body; showtemplate(name,templates,root,partials,strict); end
        elseif cmd=="RENDER"
            if haskey(templates,name); showtemplate(name,templates,root,partials,strict)
            else; println("TEMPLATE $name ERROR line $n: unknown template '$name'"); end
        elseif cmd=="DUMP"
            result=String[]; leaves!(result,root,""); println("DUMP leaves=$(length(result))"); foreach(println,result)
        elseif cmd=="STRICT"; strict=name=="ON"; println(line)
        elseif cmd=="RESET"; empty!(root); empty!(partials); empty!(templates); println("RESET"); end
    end
end
main()
