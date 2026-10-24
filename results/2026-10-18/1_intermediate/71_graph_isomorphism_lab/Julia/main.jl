struct CommandError <: Exception
    message::String
end
fail(s)=throw(CommandError(s))
check(b,s)=b ? nothing : fail(s)
yesno(b)=b ? "yes" : "no"
numbers(xs)=join(xs,' ')
struct Graph
    adj::BitMatrix
end
Graph(n::Int)=Graph(falses(n,n))
vertices(g)=size(g.adj,1)
graphedges(g)=[(u,v) for u in 1:vertices(g) for v in u+1:vertices(g) if g.adj[u,v]]
edgecount(g)=div(count(g.adj),2)
function addedge!(g,u,v)
    g.adj[u,v]=true; g.adj[v,u]=true
end
function sizecheck(n,minimum=1,maximum=16)
    check(n>=minimum,"bad value"); check(n<=maximum,"too large")
end
function distances(g,start)
    d=fill(-1,vertices(g)); d[start]=0; queue=[start]; at=1
    while at<=length(queue)
        u=queue[at]; at+=1
        for v in 1:vertices(g)
            if g.adj[u,v] && d[v]<0; d[v]=d[u]+1; push!(queue,v); end
        end
    end
    d
end
function graphinfo(g)
    n=vertices(g); seen=falses(n); sizes=Int[]; bipartite=true; girth=typemax(Int); eccentricities=Int[]
    for root in 1:n
        d=distances(g,root); push!(eccentricities,maximum(d))
        if !seen[root]; component=findall(>=(0),d); seen[component].=true; push!(sizes,length(component)); end
        for (u,v) in graphedges(g); d[u]>=0 && d[v]>=0 && iseven(d[u]-d[v]) && (bipartite=false); end
        depth=fill(-1,n); parents=zeros(Int,n); depth[root]=0; queue=[root]; at=1
        while at<=length(queue)
            u=queue[at]; at+=1
            for v in 1:n
                g.adj[u,v] || continue
                if depth[v]<0; depth[v]=depth[u]+1; parents[v]=u; push!(queue,v)
                elseif v!=parents[u]; girth=min(girth,depth[u]+depth[v]+1); end
            end
        end
    end
    triangles=sum(g.adj[u,w] && g.adj[v,w] for (u,v) in graphedges(g) for w in v+1:n;init=0)
    degrees=sort!(vec(sum(g.adj;dims=2));rev=true); sort!(sizes;rev=true)
    (n=n,m=edgecount(g),degrees=degrees,triangles=triangles,sizes=sizes,girth=girth==typemax(Int) ? "none" : string(girth),diameter=length(sizes)==1 ? string(maximum(eccentricities)) : "INF",radius=length(sizes)==1 ? string(minimum(eccentricities)) : "INF",bipartite=yesno(bipartite))
end
function maximumclique(g)
    best=Int[]
    function extend(clique,candidates)
        length(clique)>length(best) && (best=clique)
        for v in candidates; extend([clique;v],[w for w in candidates if w>v && g.adj[v,w]]); end
    end
    extend(Int[],collect(1:vertices(g))); best
end
function colouring(g,limit)
    colors=Int[]
    function extend(used)
        v=length(colors)+1; v>vertices(g) && return true
        for color in 0:min(used,limit-1)
            any(w->g.adj[v,w] && colors[w]==color,1:v-1) && continue
            push!(colors,color); extend(max(used,color+1)) && return true; pop!(colors)
        end
        false
    end
    extend(0) ? colors : nothing
end
function rankkeys(keys)
    ordered=sort!(unique(keys)); positions=Dict(key=>i-1 for (i,key) in enumerate(ordered)); [positions[key] for key in keys]
end
degreecolors(g)=rankkeys(vec(sum(g.adj;dims=2)))
function refine(g,colors)
    rounds=0
    while true
        signatures=[(colors[v],Tuple(sort!([colors[w] for w in 1:vertices(g) if g.adj[v,w]]))) for v in 1:vertices(g)]
        next=rankkeys(signatures); maximum(next)==maximum(colors) && return colors,rounds
        colors=next; rounds+=1
    end
end
stable(g)=refine(g,degreecolors(g))
cells(colors)=[findall(==(c),colors) for c in 0:maximum(colors)]
individualize(colors,v)=[c<colors[v] || w==v ? c : c+1 for (w,c) in enumerate(colors)]
function leafstring(g,labels)
    inverse=sortperm(labels); join(g.adj[inverse[i],inverse[j]] ? '1' : '0' for i in 1:vertices(g) for j in i+1:vertices(g))
end
struct Canonical
    nodes::Int
    leaves::Int
    text::String
    labels::Vector{Int}
    best::Vector{Vector{Int}}
end
function canonical(g)
    nodes=0; leaves=0; text=nothing; labels=Int[]; best=Vector{Int}[]
    function visit(colors)
        nodes+=1
        if maximum(colors)==vertices(g)-1
            leaves+=1; s=leafstring(g,colors)
            if text===nothing || s>text; text=s; labels=colors; best=[colors]
            elseif s==text; push!(best,colors); end
            return
        end
        choices=[cell for cell in cells(colors) if length(cell)>1]; chosen=choices[argmin(length.(choices))]
        for v in chosen; next,_=refine(g,individualize(colors,v)); visit(next); end
    end
    colors,_=stable(g); visit(colors); Canonical(nodes,leaves,text,labels,best)
end
function invariantreport(g,name)
    info=graphinfo(g)
    println("invariants $name\ndegrees ",numbers(info.degrees)); println("edges $(info.m) triangles $(info.triangles)")
    println("components $(length(info.sizes)) sizes ",numbers(info.sizes)); println("girth $(info.girth) diameter $(info.diameter) radius $(info.radius)\nbipartite $(info.bipartite)")
    if vertices(g)>=13; println("clique -\nchromatic -"); return; end
    clique=maximumclique(g); println("clique $(length(clique)) ",numbers(clique.-1))
    for limit in length(clique):vertices(g)
        colors=colouring(g,limit)
        if colors!==nothing; println("chromatic $limit ",numbers(colors)); return; end
    end
end
function isoreport(a,b)
    x=graphinfo(a); y=graphinfo(b)
    tests=(("vertices",x.n,y.n,true),("edges",x.m,y.m,true),("degrees",x.degrees,y.degrees,false),("triangles",x.triangles,y.triangles,true),("components",length(x.sizes),length(y.sizes),true),("girth",x.girth,y.girth,true),("diameter",x.diameter,y.diameter,true),("bipartite",x.bipartite,y.bipartite,true))
    for (name,left,right,shown) in tests
        if left!=right; println("not isomorphic $name",shown ? " $left $right" : ""); return; end
    end
    ac,ar=stable(a); bc,br=stable(b)
    if ar!=br || length.(cells(ac))!=length.(cells(bc)); println("not isomorphic refinement"); return; end
    af=canonical(a); bf=canonical(b)
    if af.text!=bf.text; println("not isomorphic canonical"); return; end
    inverse=sortperm(bf.labels); println("isomorphic\nmapping ",numbers([inverse[label+1]-1 for label in af.labels]))
end
function automorphisms(g)
    form=canonical(g); inverse=sortperm(form.labels); [[inverse[label+1] for label in leaf] for leaf in form.best]
end
function automorphismreport(g,name)
    permutations=automorphisms(g); seen=Set{Int}(); vorbits=Vector{Int}[]
    for v in 1:vertices(g)
        v in seen && continue; orbit=sort!(unique([p[v] for p in permutations])); union!(seen,orbit); push!(vorbits,orbit)
    end
    eseen=Set{Tuple{Int,Int}}(); eorbits=Vector{Tuple{Int,Int}}[]
    for (u,v) in graphedges(g)
        (u,v) in eseen && continue
        orbit=sort!(unique([minmax(p[u],p[v]) for p in permutations])); union!(eseen,orbit); push!(eorbits,orbit)
    end
    println("aut $name order $(length(permutations))\nvertex orbits $(length(vorbits))")
    for orbit in vorbits; println("orbit ",numbers(orbit.-1)); end
    println("edge orbits $(length(eorbits))")
    for orbit in eorbits; println("orbit ",join(["$(u-1)-$(v-1)" for (u,v) in orbit],' ')); end
    println("transitive vertex $(yesno(length(vorbits)==1)) edge $(yesno(length(eorbits)==1))")
end
function subisoreport(pattern,target,pname,tname)
    mapping=Int[]; total=0; induced=0; shown=Tuple{Vector{Int},Bool}[]
    function extend()
        v=length(mapping)+1
        if v>vertices(pattern)
            exact=all(pattern.adj[u,w]==target.adj[mapping[u],mapping[w]] for u in 1:vertices(pattern) for w in u+1:vertices(pattern))
            total+=1; induced+=exact; length(shown)<5 && push!(shown,(copy(mapping),exact)); return
        end
        for w in 1:vertices(target)
            w in mapping && continue
            all(u->!pattern.adj[v,u] || target.adj[w,mapping[u]],1:v-1) || continue
            push!(mapping,w); extend(); pop!(mapping)
        end
    end
    extend(); order=length(canonical(pattern).best)
    println("subiso $pname $tname embeddings $total induced $induced\ncopies $(div(total,order)) induced $(div(induced,order))")
    for (image,exact) in shown; println("embedding ",numbers(image.-1),exact ? " induced" : ""); end
end
function classify(n)
    sizecheck(n,1,5); pairs=[(u,v) for u in 1:n for v in u+1:n]; layers=[Set([canonical(Graph(n)).text])]
    for _ in eachindex(pairs)
        next=Set{String}()
        for text in layers[end]
            g=Graph(n)
            for (i,(u,v)) in enumerate(pairs); text[i]=='1' && addedge!(g,u,v); end
            for (i,(u,v)) in enumerate(pairs)
                if text[i]=='0'; changed=Graph(copy(g.adj)); addedge!(changed,u,v); push!(next,canonical(changed).text); end
            end
        end
        push!(layers,next)
    end
    println("classify $n total $(sum(length,layers))")
    for (m,layer) in enumerate(layers)
        strings=sort!(collect(layer)); println("edges $(m-1) count $(length(layer)) ",join([isempty(s) ? "-" : s for s in strings],' '))
    end
end
const SCHEMAS=Dict("GRAPH"=>["name","number","edge*"],"CYCLE"=>["name","number"],"PATH"=>["name","number"],"COMPLETE"=>["name","number"],"BIPARTITE"=>["name","number","number"],"STAR"=>["name","number"],"WHEEL"=>["name","number"],"PETERSEN"=>["name"],"HYPERCUBE"=>["name","number"],"CIRCULANT"=>["name","number","number+"],"GRID"=>["name","number","number"],"COMPLEMENT"=>["name","graph"],"LINE"=>["name","graph"],"PRODUCT"=>["name","graph","graph"],"UNION"=>["name","graph","graph"],"RELABEL"=>["name","graph","number*"],"INDUCED"=>["name","graph","number+"],"CANONIZE"=>["name","graph"],"DELETE"=>["graph"],"LIST"=>String[],"SHOW"=>["graph"],"INVARIANTS"=>["graph"],"REFINE"=>["graph","number*"],"CANON"=>["graph"],"ISO"=>["graph","graph"],"AUT"=>["graph"],"SUBISO"=>["graph","graph"],"CLASSIFY"=>["number"])
function arguments(command,words,registry)
    check(haskey(SCHEMAS,command),"unknown command $command"); schema=SCHEMAS[command]
    repeat=!isempty(schema) && last(schema)[end] in ('*','+'); fixed=length(schema)-repeat
    check(repeat ? length(words)>=fixed+(last(schema)[end]=='+') : length(words)==fixed,"bad arguments")
    for (i,word) in enumerate(words)
        kind=i<=fixed ? schema[i] : chop(last(schema))
        valid=kind in ("name","graph") ? occursin(r"\A[a-z][a-z0-9]{0,7}\z",word) : kind=="number" ? occursin(r"\A(?:0|[1-9][0-9]{0,2})\z",word) : occursin(r"\A(?:0|[1-9][0-9]{0,2})-(?:0|[1-9][0-9]{0,2})\z",word)
        check(valid,"bad arguments")
    end
    for i in 1:fixed; schema[i]=="graph" && check(haskey(registry,words[i]),"no graph $(words[i])"); end
    nothing
end
function buildgraph(command,args,registry)
    if command in ("GRAPH","CYCLE","PATH","COMPLETE","CIRCULANT")
        n=parse(Int,args[2]); sizecheck(n,command in ("CYCLE","CIRCULANT") ? 3 : 1); g=Graph(n)
        if command=="GRAPH"
            for word in args[3:end]
                u,v=parse.(Int,split(word,'-')); check(u<n && v<n && u!=v,"bad edge $word"); check(!g.adj[u+1,v+1],"duplicate edge $word"); addedge!(g,u+1,v+1)
            end
        elseif command=="CYCLE"; for u in 1:n; addedge!(g,u,mod1(u+1,n)); end
        elseif command=="PATH"; for u in 1:n-1; addedge!(g,u,u+1); end
        elseif command=="COMPLETE"; for u in 1:n, v in u+1:n; addedge!(g,u,v); end
        else
            jumps=parse.(Int,args[3:end]); check(all(j->j>0 && 2j<=n,jumps) && all(i->jumps[i]<jumps[i+1],1:length(jumps)-1),"bad value")
            for u in 1:n, j in jumps; addedge!(g,u,mod1(u+j,n)); end
        end
        return g
    elseif command in ("BIPARTITE","GRID")
        a,b=parse.(Int,args[2:3]); check(a>0 && b>0,"bad value"); n=command=="GRID" ? a*b : a+b; sizecheck(n); g=Graph(n)
        if command=="BIPARTITE"; for u in 1:a, v in a+1:a+b; addedge!(g,u,v); end
        else
            for x in 0:a-1, y in 0:b-1; u=x*b+y+1; y+1<b && addedge!(g,u,u+1); x+1<a && addedge!(g,u,u+b); end
        end
        return g
    elseif command in ("STAR","WHEEL")
        k=parse(Int,args[2]); sizecheck(k,command=="WHEEL" ? 3 : 1,15); g=Graph(k+1)
        for v in 2:k+1; addedge!(g,1,v); end
        if command=="WHEEL"; for u in 1:k; addedge!(g,u+1,mod(u,k)+2); end; end
        return g
    elseif command=="PETERSEN"
        g=Graph(10)
        for i in 0:4; addedge!(g,i+1,mod(i+1,5)+1); addedge!(g,i+1,i+6); addedge!(g,i+6,mod(i+2,5)+6); end
        return g
    elseif command=="HYPERCUBE"
        d=parse(Int,args[2]); sizecheck(d,1,4); n=2^d; g=Graph(n)
        for v in 0:n-1, bit in 0:d-1; addedge!(g,v+1,xor(v,1<<bit)+1); end
        return g
    end
    source=registry[args[2]]; n=vertices(source)
    if command=="COMPLEMENT"
        g=Graph(n); for u in 1:n, v in u+1:n; !source.adj[u,v] && addedge!(g,u,v); end; return g
    elseif command=="LINE"
        edges=graphedges(source); check(!isempty(edges),"no edges"); sizecheck(length(edges)); g=Graph(length(edges))
        for i in eachindex(edges), j in i+1:length(edges); any(x->x in edges[j],edges[i]) && addedge!(g,i,j); end
        return g
    elseif command in ("PRODUCT","UNION")
        other=registry[args[3]]; m=vertices(other); size=command=="PRODUCT" ? n*m : n+m; sizecheck(size); g=Graph(size)
        if command=="PRODUCT"
            for (u,v) in graphedges(source), y in 1:m; addedge!(g,(u-1)*m+y,(v-1)*m+y); end
            for (u,v) in graphedges(other), x in 0:n-1; addedge!(g,x*m+u,x*m+v); end
        else
            for (u,v) in graphedges(source); addedge!(g,u,v); end
            for (u,v) in graphedges(other); addedge!(g,u+n,v+n); end
        end
        return g
    elseif command in ("RELABEL","CANONIZE")
        permutation=command=="CANONIZE" ? canonical(source).labels : parse.(Int,args[3:end]); check(sort(permutation)==collect(0:n-1),"bad permutation"); g=Graph(n)
        for (u,v) in graphedges(source); addedge!(g,permutation[u]+1,permutation[v]+1); end
        return g
    else
        selected=parse.(Int,args[3:end]); check(all(v->v<n,selected) && length(unique(selected))==length(selected),"bad vertices"); g=Graph(length(selected))
        for i in eachindex(selected), j in i+1:length(selected); source.adj[selected[i]+1,selected[j]+1] && addedge!(g,i,j); end
        return g
    end
end
function execute!(registry,line)
    words=String.(split(line,' ')); command=words[1]; args=words[2:end]; arguments(command,args,registry); schema=SCHEMAS[command]
    if !isempty(schema) && schema[1]=="name"
        g=buildgraph(command,args,registry); name=args[1]; status=haskey(registry,name) ? "redefined" : "defined"; registry[name]=g; println("$status $name n $(vertices(g)) m $(edgecount(g))"); return
    end
    if command=="LIST"
        println("graphs $(length(registry))"); for name in sort!(collect(keys(registry))); g=registry[name]; println("$name n $(vertices(g)) m $(edgecount(g))"); end
    elseif command=="CLASSIFY"; classify(parse(Int,args[1]))
    elseif command=="DELETE"; delete!(registry,args[1]); println("deleted $(args[1])")
    else
        name=args[1]; g=registry[name]
        if command=="SHOW"
            println("graph $name n $(vertices(g)) m $(edgecount(g))")
            for v in 1:vertices(g); neighbors=[w-1 for w in 1:vertices(g) if g.adj[v,w]]; println("$(v-1):",isempty(neighbors) ? "" : " "*numbers(neighbors)); end
        elseif command=="INVARIANTS"; invariantreport(g,name)
        elseif command=="CANON"
            form=canonical(g); println("canon $name nodes $(form.nodes) leaves $(form.leaves)\nlabels ",numbers(form.labels)); println("string ",isempty(form.text) ? "-" : form.text)
        elseif command=="REFINE"
            selected=parse.(Int,args[2:end]); check(all(v->v<vertices(g),selected),"bad vertices"); colors,rounds=stable(g)
            for v in selected
                check(count(==(colors[v+1]),colors)>1,"singleton $v"); colors,extra=refine(g,individualize(colors,v+1)); rounds+=extra
            end
            groups=cells(colors); println("refine $name rounds $rounds cells $(length(groups))")
            for (c,cell) in enumerate(groups); println("$(c-1): ",numbers(cell.-1)); end
        elseif command=="ISO"; isoreport(g,registry[args[2]])
        elseif command=="AUT"; automorphismreport(g,name)
        elseif command=="SUBISO"; subisoreport(g,registry[args[2]],name,args[2]); end
    end
end
function main()
    registry=Dict{String,Graph}(); n=parse(Int,readline())
    for _ in 1:n
        line=readline()
        try; execute!(registry,line)
        catch e; e isa CommandError || rethrow(); println("error: $(e.message)"); end
    end
end
main()
