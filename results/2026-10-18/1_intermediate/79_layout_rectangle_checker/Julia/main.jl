struct CommandError <: Exception
    message::String
end
fail(s)=throw(CommandError(s))
check(b,s)=b ? nothing : fail(s)
struct Rectangle
    name::String
    layer::String
    box::NTuple{4,Int}
end
boxtext(b)="($(b[1]),$(b[2]))-($(b[3]),$(b[4]))"
pointtext(x,y)="($x,$y)"
rectwidth(r)=r.box[3]-r.box[1]
rectheight(r)=r.box[4]-r.box[2]
rectarea(r)=rectwidth(r)*rectheight(r)
namelist(rects)=isempty(rects) ? "none" : join((r.name for r in rects),' ')
function margins(a,b)
    x,y,u,v=a.box; p,q,r,s=b.box; (p-x,q-y,u-r,v-s)
end
containsrect(a,b)=minimum(margins(a,b))>=0
function relation(a,b)
    x=max(a.box[1],b.box[1]); y=max(a.box[2],b.box[2]); u=min(a.box[3],b.box[3]); v=min(a.box[4],b.box[4]); ox=u-x; oy=v-y
    kind=ox>0 && oy>0 ? 0 : ox<0 || oy<0 ? 3 : ox==0 && oy==0 ? 2 : 1
    (kind=kind,box=(x,y,u,v),ox=ox,oy=oy,gap=max(0,-ox,-oy),direction=ox<0 && oy<0 ? "diagonal" : ox<0 ? "x" : "y")
end
connected(a,b)=relation(a,b).kind in (0,1)
function bounding(rects)
    (minimum(r.box[1] for r in rects),minimum(r.box[2] for r in rects),maximum(r.box[3] for r in rects),maximum(r.box[4] for r in rects))
end
function spacinglines(rects,s)
    found=Tuple{Int,String,String,String}[]
    for i in 1:length(rects)-1, j in i+1:length(rects)
        a=rects[i]; b=rects[j]; r=relation(a,b)
        r.kind==2 && push!(found,(0,a.name,b.name,"corner"))
        r.kind==3 && r.gap<s && push!(found,(r.gap,a.name,b.name,r.direction))
    end
    ["$a $b gap $gap $direction" for (gap,a,b,direction) in sort!(found)]
end
function overlaplines(rects)
    result=String[]
    for i in 1:length(rects)-1, j in i+1:length(rects)
        a=rects[i]; b=rects[j]; r=relation(a,b); r.kind==0 && push!(result,"$(a.name) $(b.name) $(boxtext(r.box)) area $(r.ox*r.oy)")
    end
    result
end
function nets(rects)
    seen=falses(length(rects)); groups=Vector{Rectangle}[]
    for start in eachindex(rects)
        seen[start] && continue; pending=[start]; seen[start]=true; group=Rectangle[]
        while !isempty(pending)
            i=pop!(pending); push!(group,rects[i])
            for j in eachindex(rects); if !seen[j] && connected(rects[i],rects[j]); seen[j]=true; push!(pending,j); end; end
        end
        push!(groups,sort!(group;by=r->r.name))
    end
    groups
end
struct Coverage
    xs::Vector{Int}
    ys::Vector{Int}
    counts::Matrix{Int}
end
function Coverage(rects,extraxs=Int[],extrays=Int[])
    xs=sort!(unique([extraxs;[v for r in rects for v in (r.box[1],r.box[3])]])); ys=sort!(unique([extrays;[v for r in rects for v in (r.box[2],r.box[4])]])); counts=zeros(Int,length(xs)-1,length(ys)-1)
    for r in rects
        a=searchsortedfirst(xs,r.box[1]); b=searchsortedfirst(xs,r.box[3]); c=searchsortedfirst(ys,r.box[2]); f=searchsortedfirst(ys,r.box[4])
        for i in a:b-1, j in c:f-1; counts[i,j]+=1; end
    end
    Coverage(xs,ys,counts)
end
cellarea(c,i,j)=(c.xs[i+1]-c.xs[i])*(c.ys[j+1]-c.ys[j])
covered(c,i,j)=1<=i<size(c.xs,1) && 1<=j<size(c.ys,1) && c.counts[i,j]>0
coveragearea(c,k=1)=sum((cellarea(c,i,j) for i in axes(c.counts,1) for j in axes(c.counts,2) if c.counts[i,j]>=k);init=0)
function perimeter(c)
    result=0; nx,ny=size(c.counts)
    for i in 1:nx+1, j in 1:ny; covered(c,i-1,j)!=covered(c,i,j) && (result+=c.ys[j+1]-c.ys[j]); end
    for j in 1:ny+1, i in 1:nx; covered(c,i,j-1)!=covered(c,i,j) && (result+=c.xs[i+1]-c.xs[i]); end
    result
end
function runs(flags,coordinates)
    result=Tuple{Int,Int}[]; i=1
    while i<=length(flags)
        if !flags[i]; i+=1; continue; end
        start=i
        while i<=length(flags) && flags[i]; i+=1; end
        push!(result,(coordinates[start],coordinates[i]))
    end
    result
end
function holes(c)
    nx,ny=size(c.counts); seen=falses(nx,ny); result=Tuple{Int,NTuple{4,Int}}[]
    for j in 1:ny, i in 1:nx
        (seen[i,j] || c.counts[i,j]>0) && continue; pending=[(i,j)]; seen[i,j]=true; boundary=false; area=0; x=c.xs[i]; y=c.ys[j]; u=c.xs[i+1]; v=c.ys[j+1]
        while !isempty(pending)
            a,b=pop!(pending); boundary|=a in (1,nx) || b in (1,ny); area+=cellarea(c,a,b); x=min(x,c.xs[a]); y=min(y,c.ys[b]); u=max(u,c.xs[a+1]); v=max(v,c.ys[b+1])
            for (p,q) in ((a-1,b),(a+1,b),(a,b-1),(a,b+1))
                if 1<=p<=nx && 1<=q<=ny && !seen[p,q] && c.counts[p,q]==0; seen[p,q]=true; push!(pending,(p,q)); end
            end
        end
        !boundary && push!(result,(area,(x,y,u,v)))
    end
    result
end
function pieces(c)
    nx,ny=size(c.counts); rows=[runs(c.counts[:,j].>0,c.xs) for j in 1:ny]; result=NTuple{4,Int}[]
    for j in 1:ny, (left,right) in rows[j]
        j>1 && (left,right) in rows[j-1] && continue; top=j+1
        while top<=ny && (left,right) in rows[top]; top+=1; end
        push!(result,(left,c.ys[j],right,c.ys[top]))
    end
    result
end
function largestempty(c)
    nx,ny=size(c.counts); best=nothing; box=nothing
    for a in 1:nx
        free=trues(ny)
        for b in a+1:nx+1
            free .&=c.counts[b-1,:].==0; width=c.xs[b]-c.xs[a]
            for (bottom,top) in runs(free,c.ys)
                candidate=(-width*(top-bottom),c.xs[a],bottom,width)
                if best===nothing || candidate<best; best=candidate; box=(c.xs[a],bottom,c.xs[b],top); end
            end
        end
    end
    box
end
function percentage(area,denominator)
    h=div(10000area,denominator); "$(div(h,100)).$(lpad(string(h%100),2,'0'))"
end
mutable struct Layout
    rectangles::Dict{String,Rectangle}
    rules::Dict{NTuple{3,String},Int}
    history::Vector{Tuple{Dict{String,Rectangle},String}}
end
Layout()=Layout(Dict{String,Rectangle}(),Dict{NTuple{3,String},Int}(),Tuple{Dict{String,Rectangle},String}[])
sortedrects(w)=sort!(collect(values(w.rectangles));by=r->r.name)
onlayer(w,layer)=[r for r in sortedrects(w) if r.layer==layer]
function requirelayer(w,layer); result=onlayer(w,layer); check(!isempty(result),"no rectangles on $layer"); result; end
function getrect(w,name); check(haskey(w.rectangles,name),"unknown rectangle $name"); w.rectangles[name]; end
unused(w,name)=check(!haskey(w.rectangles,name),"duplicate rectangle $name")
function pair(w,a,b); firstrect=getrect(w,a); secondrect=getrect(w,b); check(a!=b,"same rectangle $a"); firstrect,secondrect; end
function place!(w,r); check(all(x->abs(x)<=10000,r.box),"out of bounds"); w.rectangles[r.name]=r; end
function report(heading,lines); println(heading); foreach(println,lines); end
function ruleviolations(w,kind,layer,other,value)
    kind=="spacing" && return spacinglines(onlayer(w,layer),value)
    result=String[]
    for r in onlayer(w,layer)
        if kind=="width"; size=min(rectwidth(r),rectheight(r)); size<value && push!(result,"$(r.name) width $size")
        else
            outers=onlayer(w,other); best=isempty(outers) ? nothing : maximum(minimum(margins(u,r)) for u in outers)
            (best===nothing || best<value) && push!(result,"$(r.name) best margin $(best===nothing ? "none" : string(best))")
        end
    end
    result
end
function execute!(w,line)
    parts=String.(split(line,' ')); command=parts[1]; args=parts[2:end]; before=copy(w.rectangles)
    if command=="ADD"
        name,layer=args[1:2]; x,y,u,v=parse.(Int,args[3:6]); unused(w,name); check(x<u && y<v,"invalid rectangle"); r=Rectangle(name,layer,(x,y,u,v)); place!(w,r); println("added $name $layer $(boxtext(r.box))")
    elseif command in ("COPY","MOVE","RESIZE","SPLIT","LAYER","DELETE")
        name=args[1]; r=getrect(w,name); x,y,u,v=r.box
        if command=="COPY"
            new=args[2]; unused(w,new); dx,dy=parse.(Int,args[3:4]); copied=Rectangle(new,r.layer,(x+dx,y+dy,u+dx,v+dy)); place!(w,copied); println("copied $name to $new $(boxtext(copied.box))")
        elseif command=="MOVE"
            dx,dy=parse.(Int,args[2:3]); moved=Rectangle(name,r.layer,(x+dx,y+dy,u+dx,v+dy)); place!(w,moved); println("moved $name to $(boxtext(moved.box))")
        elseif command=="RESIZE"
            width,height=parse.(Int,args[2:3]); check(width>0 && height>0,"invalid size"); resized=Rectangle(name,r.layer,(x,y,x+width,y+height)); place!(w,resized); println("resized $name to $(boxtext(resized.box))")
        elseif command=="SPLIT"
            axis=args[2]; pos=parse(Int,args[3]); new=args[4]; unused(w,new); check(axis=="x" ? x<pos<u : y<pos<v,"cut outside $name"); firstbox=axis=="x" ? (x,y,pos,v) : (x,y,u,pos); secondbox=axis=="x" ? (pos,y,u,v) : (x,pos,u,v); w.rectangles[name]=Rectangle(name,r.layer,firstbox); w.rectangles[new]=Rectangle(new,r.layer,secondbox); println("split $name at $axis=$pos: $name $(boxtext(firstbox)), $new $(boxtext(secondbox))")
        elseif command=="LAYER"
            layer=args[2]; check(layer!=r.layer,"already on $layer"); w.rectangles[name]=Rectangle(name,layer,r.box); println("layer $name $(r.layer) -> $layer")
        else; delete!(w.rectangles,name); println("deleted $name"); end
    elseif command=="UNDO"
        check(!isempty(w.history),"nothing to undo"); w.rectangles,original=pop!(w.history); println("undo: $original")
    elseif command=="LIST"
        report("rectangles: $(length(w.rectangles))",["$(r.name) $(r.layer) $(boxtext(r.box)) $(rectwidth(r))x$(rectheight(r))" for r in sortedrects(w)])
    elseif command=="INFO"
        name=args[1]; r=getrect(w,name); others=[s for s in sortedrects(w) if s.name!=name]; println("$name $(r.layer) $(boxtext(r.box)) $(rectwidth(r))x$(rectheight(r)) area $(rectarea(r))")
        for (label,kind) in (("overlaps",0),("touches",1),("corners",2)); println("$label: $(namelist([s for s in others if s.layer==r.layer && relation(r,s).kind==kind]))"); end
        println("encloses: $(namelist([s for s in others if containsrect(r,s)]))\nenclosed by: $(namelist([s for s in others if containsrect(s,r)]))")
    elseif command=="LAYERS"
        layers=sort!(unique([r.layer for r in values(w.rectangles)])); println("layers: $(length(layers))")
        for layer in layers; rects=onlayer(w,layer); println("$layer: $(length(rects)) rectangles, area $(coveragearea(Coverage(rects))), nets $(length(nets(rects)))"); end
    elseif command=="OVERLAPS"
        if isempty(args)
            lines=String[]
            for layer in sort!(unique([r.layer for r in values(w.rectangles)])); append!(lines,["$layer $s" for s in overlaplines(onlayer(w,layer))]); end
            report("overlaps all layers: $(length(lines))",lines)
        else; lines=overlaplines(requirelayer(w,args[1])); report("overlaps $(args[1]): $(length(lines))",lines); end
    elseif command in ("INTERSECT","ADJACENT","ENCLOSE","PATH")
        a,b=args; firstrect,secondrect=pair(w,a,b); r=relation(firstrect,secondrect)
        if command=="INTERSECT"
            detail=r.kind==0 ? "$(boxtext(r.box)) area $(r.ox*r.oy)" : r.kind==1 ? "segment $(boxtext(r.box)) length $(r.ox+r.oy)" : r.kind==2 ? "point $(pointtext(r.box[1],r.box[2]))" : "none, gap $(r.gap)"; println("intersect $a $b: $detail")
        elseif command=="ADJACENT"
            side=r.ox==0 ? (firstrect.box[3]==r.box[1] ? "west" : "east") : (firstrect.box[4]==r.box[2] ? "south" : "north"); detail=r.kind==0 ? "overlapping" : r.kind==1 ? "$a is $side of $b, edge $(boxtext(r.box)), length $(r.ox+r.oy)" : r.kind==2 ? "corner only at $(pointtext(r.box[1],r.box[2]))" : "not adjacent"; println("adjacent $a $b: $detail")
        elseif command=="ENCLOSE"
            p,q,r0,s=margins(firstrect,secondrect); minimumvalue=min(p,q,r0,s); text="margins left $p bottom $q right $r0 top $s"; println("enclose $a $b: ",minimumvalue>=0 ? "yes, $text, min $minimumvalue" : "no, $text")
        else
            check(firstrect.layer==secondrect.layer,"different layers"); rects=onlayer(w,firstrect.layer); distances=Dict(b=>0); queue=[b]; at=1
            while at<=length(queue)
                current=queue[at]; at+=1
                for other in rects; if !haskey(distances,other.name) && connected(w.rectangles[current],other); distances[other.name]=distances[current]+1; push!(queue,other.name); end; end
            end
            if !haskey(distances,a); println("path $a $b: none")
            else
                path=[a]
                while path[end]!=b; push!(path,first(s.name for s in rects if get(distances,s.name,-1)==distances[path[end]]-1 && connected(w.rectangles[path[end]],s))); end
                println("path $a $b: $(join(path," -> ")) ($(length(path)-1) steps)")
            end
        end
    elseif command=="AT"
        x,y=parse.(Int,args); found=String[]
        for r in sortedrects(w)
            a,b,c,f=r.box
            if a<=x<=c && b<=y<=f; sides=(x in (a,c))+(y in (b,f)); push!(found,"$(r.name) $(r.layer) $(("inside","edge","corner")[sides+1])"); end
        end
        println("at $(pointtext(x,y)): ",isempty(found) ? "none" : join(found,", "))
    elseif command=="NEAREST"
        r=getrect(w,args[1]); others=[s for s in onlayer(w,r.layer) if s.name!=r.name]
        if isempty(others); println("nearest $(r.name): none")
        else; gap,name=minimum((relation(r,s).gap,s.name) for s in others); println("nearest $(r.name): $name gap $gap"); end
    elseif command=="RULE"
        kind=lowercase(args[1]); layer=args[2]; other=kind=="enclose" ? args[3] : ""; value=parse(Int,args[end]); check(kind!="enclose" || layer!=other,"same layer $layer"); w.rules[(kind,layer,other)]=value; println("rule ",join([kind;args[2:end]],' '))
    elseif command=="CHECK"
        check(!isempty(w.rules),"no rules"); total=0
        for (kind,layer,other) in sort!(collect(keys(w.rules)))
            value=w.rules[(kind,layer,other)]; lines=ruleviolations(w,kind,layer,other,value); heading=kind=="enclose" ? "$kind $layer $other $value" : "$kind $layer $value"; report("$heading: $(length(lines)) violations",lines); total+=length(lines)
        end
        println("check: $total violations in $(length(w.rules)) rules")
    else
        minimumcount=command=="COVER" ? parse(Int,args[1]) : 1; layer=args[command=="COVER" ? 2 : 1]; rects=requirelayer(w,layer)
        if command=="DRC"; s=parse(Int,args[2]); lines=spacinglines(rects,s); report("drc $layer spacing $s: $(length(lines)) violations",lines)
        elseif command=="NETS"
            groups=nets(rects); println("nets $layer: $(length(groups))"); for (i,group) in enumerate(groups); println("net $i: $(namelist(group)) area $(coveragearea(Coverage(group)))"); end
        elseif command=="RENDER"
            x,y,u,v=parse.(Int,args[2:5]); check(x<u && y<v,"invalid window"); check(u-x<=60 && v-y<=40,"window too large"); println("render $layer $(boxtext((x,y,u,v)))")
            for j in v-1:-1:y; println(join([begin count=sum(r.box[1]<=i<r.box[3] && r.box[2]<=j<r.box[4] for r in rects); count==0 ? "." : count>=10 ? "*" : string(count) end for i in x:u-1])); end
        elseif command=="BBOX"
            bounds=bounding(rects); width=bounds[3]-bounds[1]; height=bounds[4]-bounds[2]; println("bbox $layer: $(boxtext(bounds)) $(width)x$height, $(length(rects)) rectangles, density $(percentage(coveragearea(Coverage(rects)),width*height))%")
        elseif command=="DENSITY"
            window=parse(Int,args[2]); x,y,u,v=bounding(rects); nc=cld(u-x,window); nr=cld(v-y,window); check(nc<=20 && nr<=20,"too many windows"); coverage=Coverage(rects,[x+i*window for i in 0:nc],[y+j*window for j in 0:nr]); tiles=zeros(Int,nc,nr)
            for i in axes(coverage.counts,1), j in axes(coverage.counts,2)
                if coverage.counts[i,j]>0; a=div(coverage.xs[i]-x,window)+1; b=div(coverage.ys[j]-y,window)+1; tiles[a,b]+=cellarea(coverage,i,j); end
            end
            println("density $layer window $window: $(nc)x$nr")
            for j in nr:-1:1; println(join([div(100tiles[i,j],window*window) for i in 1:nc],' ')); end
            for label in ("min","max")
                best=label=="min" ? minimum(tiles) : maximum(tiles); chosen=first((i,j) for j in 1:nr for i in 1:nc if tiles[i,j]==best); a,b=chosen; println("$label $(percentage(best,window*window))% at $(pointtext(x+(a-1)*window,y+(b-1)*window))")
            end
        else
            c=Coverage(rects)
            if command=="AREA"; println("area $layer: $(coveragearea(c))")
            elseif command=="COVER"; println("cover $layer >= $minimumcount: $(coveragearea(c,minimumcount))")
            elseif command=="PERIMETER"; println("perimeter $layer: $(perimeter(c))")
            elseif command=="EMPTY"
                box=largestempty(c); println("empty $layer: ",box===nothing ? "none" : "$(boxtext(box)) area $((box[3]-box[1])*(box[4]-box[2]))")
            elseif command=="HOLES"
                found=holes(c); println("holes $layer: $(length(found))"); for (i,(area,box)) in enumerate(found); println("hole $i: area $area, bbox $(boxtext(box))"); end
            elseif command=="MERGE"; found=pieces(c); report("merge $layer: $(length(found)) pieces",boxtext.(found)); end
        end
    end
    command in ("ADD","COPY","MOVE","RESIZE","SPLIT","LAYER","DELETE") && push!(w.history,(before,line))
end
function main()
    workbench=Layout(); n=parse(Int,readline())
    for _ in 1:n
        try; execute!(workbench,readline())
        catch e; e isa CommandError || rethrow(); println("error: $(e.message)"); end
    end
end
main()
