const SIDES=("top","right","bottom","left")
const INITIAL=Dict(
    "display"=>"block","position"=>"static","box-sizing"=>"content-box",
    "width"=>"auto","height"=>"auto","min-width"=>"0","min-height"=>"0","max-width"=>"none","max-height"=>"none",
    "flex-direction"=>"row","flex-wrap"=>"nowrap","justify-content"=>"start","align-items"=>"stretch","align-self"=>"auto",
    "row-gap"=>"0","column-gap"=>"0","order"=>"0","flex-grow"=>"0","flex-shrink"=>"1","flex-basis"=>"auto",
    "grid-template-columns"=>"none","grid-template-rows"=>"none","grid-column"=>"auto","grid-row"=>"auto")
for side in SIDES
    INITIAL[side]="auto"
    for kind in ("margin","padding","border"); INITIAL["$kind-$side"]="0"; end
end
const CHOICES=Dict(
    "display"=>("block","flex","grid","none"),"position"=>("static","relative","absolute"),"box-sizing"=>("content-box","border-box"),
    "flex-direction"=>("row","row-reverse","column","column-reverse"),"flex-wrap"=>("nowrap","wrap"),
    "justify-content"=>("start","end","center","space-between","space-around","space-evenly"),
    "align-items"=>("stretch","start","end","center"),"align-self"=>("auto","stretch","start","end","center"))
natural_token(s)=occursin(r"\A[0-9]{1,3}\z",s)
positive_token(s)=natural_token(s) && parse(Int,s)>0
signed_token(s)=natural_token(startswith(s,"-") ? s[2:end] : s)
percent_token(s)=endswith(s,"%") && natural_token(s[1:end-1])
fr_token(s)=endswith(s,"fr") && positive_token(s[1:end-2])
function gridline_valid(t)
    t==["auto"] && return true
    length(t)==1 && return positive_token(t[1])
    length(t)==2 && return t[1]=="span" && positive_token(t[2])
    length(t)==3 && return positive_token(t[1]) && t[2]=="/" && positive_token(t[3]) && parse(Int,t[1])<parse(Int,t[3])
    length(t)==4 && return positive_token(t[1]) && t[2]=="/" && t[3]=="span" && positive_token(t[4])
    false
end
known_property(p)=haskey(INITIAL,p) || p in ("margin","padding","border","gap")
function valid_longhand(p,t)
    if p in ("grid-template-columns","grid-template-rows"); return t==["none"] || all(s->s=="auto" || natural_token(s) || fr_token(s),t); end
    p in ("grid-column","grid-row") && return gridline_valid(t)
    length(t)==1 || return false; s=t[1]
    haskey(CHOICES,p) && return s in CHOICES[p]
    p in ("width","height","flex-basis") && return s=="auto" || natural_token(s) || percent_token(s)
    p in ("min-width","min-height") && return natural_token(s) || percent_token(s)
    p in ("max-width","max-height") && return s=="none" || natural_token(s) || percent_token(s)
    startswith(p,"border-") && return s in ("0","1")
    p in SIDES && return s=="auto" || signed_token(s)
    p=="order" && return signed_token(s)
    natural_token(s)
end
function expanddecl(p,value)
    t=String.(split(value,' '))
    if haskey(INITIAL,p); return valid_longhand(p,t) ? [p=>value] : nothing; end
    if p=="gap"
        1<=length(t)<=2 && all(natural_token,t) || return nothing
        return ["row-gap"=>t[1],"column-gap"=>t[end]]
    end
    if p in ("margin","padding","border")
        1<=length(t)<=4 && all(s->valid_longhand("$p-top",[s]),t) || return nothing
        picks=((1,1,1,1),(1,2,1,2),(1,2,3,2),(1,2,3,4))[length(t)]
        return ["$p-$(SIDES[i])"=>t[picks[i]] for i in 1:4]
    end
    nothing
end
mutable struct CssElement
    tag::String
    id::String
    classes::Vector{String}
    text::Union{Nothing,String}
    parent::Int
    depth::Int
    children::Vector{Int}
    style::Dict{String,String}
    displayed::Bool
    cw::Int
    ch::Int
    lines::Vector{String}
    rx::Int
    ry::Int
    x::Int
    y::Int
end
mutable struct Document
    width::Int
    height::Int
    elements::Vector{CssElement}
    intrinsic::Vector{Int}
end
edge(e,kind,side)=parse(Int,e.style["$kind-$side"])
function frame(e,horizontal)
    sides=horizontal ? ("left","right") : ("top","bottom")
    sum(edge(e,kind,side) for kind in ("padding","border") for side in sides)
end
outer(e,horizontal)=frame(e,horizontal)+sum(edge(e,"margin",side) for side in (horizontal ? ("left","right") : ("top","bottom")))
borderwidth(e)=e.cw+frame(e,true)
borderheight(e)=e.ch+frame(e,false)
flow(d,e)=[i for i in e.children if d.elements[i].displayed && d.elements[i].style["position"]!="absolute"]
items(d,e)=sort(flow(d,e);by=i->(parse(Int,d.elements[i].style["order"]),i))
function resolvedlength(e,p,reference,horizontal)
    s=e.style[p]; s in ("auto","none") && return nothing
    if endswith(s,"%"); reference===nothing && return nothing; result=div(reference*parse(Int,s[1:end-1]),100)
    else; result=parse(Int,s); end
    e.style["box-sizing"]=="border-box" ? max(0,result-frame(e,horizontal)) : result
end
function constrain(e,value,horizontal,reference)
    axis=horizontal ? "width" : "height"; lower=something(resolvedlength(e,"min-$axis",reference,horizontal),0); upper=resolvedlength(e,"max-$axis",reference,horizontal)
    max(lower,upper===nothing ? value : min(value,upper))
end
inset(e,side)=e.style[side]=="auto" ? nothing : parse(Int,e.style[side])
function wrapwords(text,width)
    result=String[]
    for word in split(text,' ')
        if !isempty(result) && length(result[end])+1+length(word)<=width; result[end]*=" "*word
        else; push!(result,String(word)); end
    end
    result
end
gaptotal(gap,n)=gap*max(0,n-1)
function distribute(total,weights)
    denominator=sum(weights); shares=[div(total*w,denominator) for w in weights]; remainder=total-sum(shares)
    for i in eachindex(weights); if remainder>0 && weights[i]>0; shares[i]+=1; remainder-=1; end; end
    shares
end
itemalign(e,child)=child.style["align-self"]=="auto" ? e.style["align-items"] : child.style["align-self"]
alignoffset(align,free)=free>0 ? (align=="end" ? free : align=="center" ? div(free,2) : 0) : 0
function placechild!(e,child,x,y)
    child.rx=edge(e,"border","left")+edge(e,"padding","left")+x; child.ry=edge(e,"border","top")+edge(e,"padding","top")+y
end
function gridrequest(value)
    t=split(value,' ')
    t==["auto"] && return (0,1)
    t[1]=="span" && return (0,parse(Int,t[2]))
    a=parse(Int,t[1]); length(t)==1 && return (a,1)
    (a,t[3]=="span" ? parse(Int,t[4]) : parse(Int,t[3])-a)
end
tracks(e,p)=e.style[p]=="none" ? String[] : String.(split(e.style[p],' '))
columns(e)=e.style["grid-template-columns"]=="none" ? ["auto"] : tracks(e,"grid-template-columns")
function gridplacement(d,e,ordered)
    requests=[(gridrequest(d.elements[i].style["grid-row"])...,gridrequest(d.elements[i].style["grid-column"])...) for i in ordered]
    nc=maximum([length(columns(e));[c==0 ? cs : c+cs-1 for (_,_,c,cs) in requests]])
    areas=fill((0,0,0,0),length(ordered)); occupied=Set{Tuple{Int,Int}}()
    fits(r,c,rs,cs)=all(!((y,x) in occupied) for y in r:r+rs-1 for x in c:c+cs-1)
    function occupy!(i,r,c)
        _,rs,_,cs=requests[i]; areas[i]=(r,c,rs,cs)
        for y in r:r+rs-1, x in c:c+cs-1; push!(occupied,(y,x)); end
    end
    for (i,(r,_,c,_)) in enumerate(requests); r!=0 && c!=0 && occupy!(i,r,c); end
    cr=1; cc=1
    for (i,(r,rs,c,cs)) in enumerate(requests)
        r!=0 && c!=0 && continue
        if r!=0
            c=1
            for candidate in 1:nc-cs+1; if fits(r,candidate,rs,cs); c=candidate; break; end; end
        elseif c!=0
            c<cc && (cr+=1); r=cr
            while !fits(r,c,rs,cs); r+=1; end
            cr=r; cc=c+cs
        else
            r=cr; c=cc
            while true
                if c+cs-1>nc; r+=1; c=1
                elseif !fits(r,c,rs,cs); c+=1
                else; break; end
            end
            cr=r; cc=c+cs
        end
        occupy!(i,r,c)
    end
    areas,nc
end
function tracksizes(specs,n,available,gap,contributions)
    specifications=[specs;fill("auto",n-length(specs))]; sizes=zeros(Int,n)
    for (i,s) in enumerate(specifications)
        if s=="auto" || (endswith(s,"fr") && available===nothing); sizes[i]=maximum((v for (start,span,v) in contributions if start==i && span==1);init=0)
        elseif !endswith(s,"fr"); sizes[i]=parse(Int,s); end
    end
    if available!==nothing
        leftover=available-sum(sizes)-gap*(n-1); weights=[endswith(s,"fr") ? parse(Int,s[1:end-2]) : 0 for s in specifications]
        all(==(0),weights) && (weights=Int[s=="auto" for s in specifications])
        leftover>0 && any(>(0),weights) && (sizes.+=distribute(leftover,weights))
    end
    sizes
end
spanstart(sizes,start,gap)=sum(@view sizes[1:start-1])+gap*(start-1)
spansize(sizes,start,span,gap)=sum(@view sizes[start:start+span-1])+gap*(span-1)
function maxcontent(d,i)
    d.intrinsic[i]>=0 && return d.intrinsic[i]; e=d.elements[i]
    if e.text!==nothing; result=length(e.text)
    elseif e.style["display"]=="flex" && e.style["flex-direction"] in ("row","row-reverse")
        children=flow(d,e); result=sum((contribution(d,j) for j in children);init=0)+gaptotal(parse(Int,e.style["column-gap"]),length(children))
    elseif e.style["display"]=="grid"
        ordered=items(d,e); areas,nc=gridplacement(d,e,ordered); gap=parse(Int,e.style["column-gap"]); contributions=[(a[2],a[4],contribution(d,j)) for (j,a) in zip(ordered,areas)]; result=sum(tracksizes(columns(e),nc,nothing,gap,contributions))+gaptotal(gap,nc)
    else; result=maximum((contribution(d,j) for j in flow(d,e));init=0); end
    d.intrinsic[i]=result; result
end
function contribution(d,i)
    e=d.elements[i]; width=resolvedlength(e,"width",nothing,true); width===nothing && (width=maxcontent(d,i)); constrain(e,width,true,nothing)+outer(e,true)
end
function layout!(d,i,cwref,chref,fw=nothing,fh=nothing)
    e=d.elements[i]
    if fw===nothing; width=resolvedlength(e,"width",cwref,true); fw=constrain(e,width===nothing ? max(0,cwref-outer(e,true)) : width,true,cwref); end
    if fh===nothing; height=resolvedlength(e,"height",chref,false); height!==nothing && (fh=constrain(e,height,false,chref)); end
    e.cw=fw
    if e.text!==nothing; e.lines=wrapwords(e.text,fw); naturalheight=length(e.lines)
    elseif e.style["display"]=="flex"; naturalheight=flexlayout!(d,i,fw,fh,chref)
    elseif e.style["display"]=="grid"; naturalheight=gridlayout!(d,i,fw,fh)
    else
        bottom=0; previous=0
        for j in flow(d,e); child=d.elements[j]; layout!(d,j,fw,fh); top=bottom+max(previous,edge(child,"margin","top")); placechild!(e,child,edge(child,"margin","left"),top); bottom=top+borderheight(child); previous=edge(child,"margin","bottom"); end
        naturalheight=bottom+previous
    end
    e.ch=fh===nothing ? constrain(e,naturalheight,false,chref) : fh; naturalheight
end
mutable struct FlexItem
    index::Int
    align::String
    outside::Int
    cross::Int
    base::Int
    hypothetical::Int
    size::Int
end
function main_sizes!(d,line,lengthmain,gap,horizontal,reference)
    gaps=gaptotal(gap,length(line)); growing=sum(it.hypothetical+it.outside for it in line)+gaps<lengthmain
    weights=[parse(Int,d.elements[it.index].style[growing ? "flex-grow" : "flex-shrink"])*(growing ? 1 : it.base) for it in line]
    active=Int[]
    for (j,it) in enumerate(line); it.size=it.hypothetical; weights[j]>0 && (growing ? it.base<=it.hypothetical : it.base>=it.hypothetical) && push!(active,j); end
    while !isempty(active)
        free=lengthmain-gaps-sum((j in active ? it.base : it.size)+it.outside for (j,it) in enumerate(line)); shares=distribute(max(0,growing ? free : -free),weights[active]); violations=zeros(Int,length(line))
        for (j,share) in zip(active,shares); it=line[j]; tentative=it.base+(growing ? share : -share); it.size=constrain(d.elements[it.index],tentative,horizontal,reference); violations[j]=it.size-tentative; end
        total=sum(violations); active=total>0 ? [j for j in active if violations[j]<=0] : total<0 ? [j for j in active if violations[j]>=0] : Int[]
    end
end
function justifyspaces(justify,remaining,n)
    spaces=zeros(Int,n); remaining<=0 && return spaces
    if justify=="end"; spaces[1]=remaining
    elseif justify=="center"; spaces[1]=div(remaining,2)
    elseif justify!="start"
        ends,middle=justify=="space-between" ? (0,1) : justify=="space-around" ? (1,2) : (1,1); weights=[ends;fill(middle,n-1);ends]; sum(weights)>0 && (spaces=distribute(remaining,weights)[1:n])
    end
    spaces
end
function flexlayout!(d,index,cw,k,heightref)
    e=d.elements[index]; direction=e.style["flex-direction"]; horizontal=direction in ("row","row-reverse"); gap=parse(Int,e.style[horizontal ? "column-gap" : "row-gap"]); rowgap=parse(Int,e.style["row-gap"]); reference=horizontal ? cw : k; allitems=FlexItem[]
    for j in items(d,e)
        child=d.elements[j]; align=itemalign(e,child); cross=0
        if !horizontal
            room=max(0,cw-outer(child,true)); crossvalue=resolvedlength(child,"width",cw,true); crossvalue===nothing && (crossvalue=align=="stretch" ? room : min(maxcontent(d,j),room)); cross=constrain(child,crossvalue,true,cw)
        end
        base=resolvedlength(child,"flex-basis",reference,horizontal); base===nothing && (base=resolvedlength(child,horizontal ? "width" : "height",reference,horizontal))
        base===nothing && (base=horizontal ? maxcontent(d,j) : layout!(d,j,cw,k,cross)); hypothetical=constrain(child,base,horizontal,reference); push!(allitems,FlexItem(j,align,outer(child,horizontal),cross,base,hypothetical,0))
    end
    lengthmain=horizontal ? cw : k!==nothing ? k : constrain(e,sum((it.hypothetical+it.outside for it in allitems);init=0)+gaptotal(gap,length(allitems)),false,heightref)
    lines=Vector{FlexItem}[]
    if horizontal && e.style["flex-wrap"]=="wrap"
        for it in allitems
            if !isempty(lines) && sum(other.hypothetical+other.outside for other in lines[end])+gap*length(lines[end])+it.hypothetical+it.outside<=lengthmain; push!(lines[end],it)
            else; push!(lines,[it]); end
        end
    elseif !isempty(allitems); push!(lines,allitems); end
    crossstart=0; totalcross=0
    for line in lines
        main_sizes!(d,line,lengthmain,gap,horizontal,reference)
        if horizontal
            for it in line; layout!(d,it.index,cw,k,it.size); it.cross=d.elements[it.index].ch; end
            largest=maximum(it.cross+outer(d.elements[it.index],false) for it in line); lc=length(lines)>1 ? largest : k!==nothing ? k : constrain(e,largest,false,heightref)
        else; lc=cw; end
        remaining=lengthmain-sum(it.size+it.outside for it in line)-gaptotal(gap,length(line)); spaces=justifyspaces(e.style["justify-content"],remaining,length(line)); backwards=endswith(direction,"-reverse"); cursor=backwards ? lengthmain : 0
        for (it,space) in zip(line,spaces)
            child=d.elements[it.index]; amount=it.size+it.outside
            if backwards; cursor-=space+amount; mainposition=cursor; cursor-=gap
            else; cursor+=space; mainposition=cursor; cursor+=amount+gap; end
            mainposition+=edge(child,"margin",horizontal ? "left" : "top")
            if !horizontal; layout!(d,it.index,cw,k,it.cross,it.size)
            elseif it.align=="stretch" && child.style["height"]=="auto"; it.cross=constrain(child,max(0,lc-outer(child,false)),false,k); layout!(d,it.index,cw,k,it.size,it.cross)
            else; layout!(d,it.index,cw,k,it.size); end
            offset=alignoffset(it.align,lc-it.cross-outer(child,!horizontal))
            if horizontal; placechild!(e,child,mainposition,crossstart+offset+edge(child,"margin","top"))
            else; placechild!(e,child,crossstart+offset+edge(child,"margin","left"),mainposition); end
        end
        totalcross+=lc; crossstart+=lc+rowgap
    end
    horizontal ? totalcross+gaptotal(rowgap,length(lines)) : lengthmain
end
function gridlayout!(d,index,cw,k)
    e=d.elements[index]; ordered=items(d,e); areas,nc=gridplacement(d,e,ordered); cg=parse(Int,e.style["column-gap"]); rg=parse(Int,e.style["row-gap"]); colcontrib=[(a[2],a[4],contribution(d,j)) for (j,a) in zip(ordered,areas)]; cols=tracksizes(columns(e),nc,cw,cg,colcontrib); widths=Tuple{Int,Int}[]; rowcontrib=NTuple{3,Int}[]
    for (j,a) in zip(ordered,areas)
        child=d.elements[j]; aw=spansize(cols,a[2],a[4],cg); width=resolvedlength(child,"width",aw,true); gw=constrain(child,width===nothing ? max(0,aw-outer(child,true)) : width,true,aw); layout!(d,j,aw,nothing,gw); push!(widths,(aw,gw)); push!(rowcontrib,(a[1],a[3],child.ch+outer(child,false)))
    end
    specifications=tracks(e,"grid-template-rows"); nr=maximum([length(specifications);[a[1]+a[3]-1 for a in areas]]); rows=tracksizes(specifications,nr,k,rg,rowcontrib)
    for (j,a,(aw,gw)) in zip(ordered,areas,widths)
        child=d.elements[j]; ah=spansize(rows,a[1],a[3],rg); align=itemalign(e,child)
        if align=="stretch" && child.style["height"]=="auto"; fh=constrain(child,max(0,ah-outer(child,false)),false,ah); layout!(d,j,aw,ah,gw,fh)
        else; layout!(d,j,aw,ah,gw); end
        offset=alignoffset(align,ah-child.ch-outer(child,false)); placechild!(e,child,spanstart(cols,a[2],cg)+edge(child,"margin","left"),spanstart(rows,a[1],rg)+offset+edge(child,"margin","top"))
    end
    sum(rows)+gaptotal(rg,nr)
end
function ancestor(d,i)
    p=d.elements[i].parent
    while p!=0 && d.elements[p].style["position"]=="static"; p=d.elements[p].parent; end
    p
end
borderbox(e)=(e.x,e.y,borderwidth(e),borderheight(e))
marginbox(e)=(e.x-edge(e,"margin","left"),e.y-edge(e,"margin","top"),e.cw+outer(e,true),e.ch+outer(e,false))
paddingbox(e)=(e.x+edge(e,"border","left"),e.y+edge(e,"border","top"),e.cw+edge(e,"padding","left")+edge(e,"padding","right"),e.ch+edge(e,"padding","top")+edge(e,"padding","bottom"))
contentbox(e)=(e.x+edge(e,"border","left")+edge(e,"padding","left"),e.y+edge(e,"border","top")+edge(e,"padding","top"),e.cw,e.ch)
absoffset(start,finish,ms,me,free)=start!==nothing ? start+ms : finish!==nothing ? free-finish-me : ms
relshift(start,finish)=start!==nothing ? start : finish!==nothing ? -finish : 0
function performlayout!(d)
    fill!(d.intrinsic,-1)
    for e in d.elements; e.displayed=e.style["display"]!="none" && (e.parent==0 || d.elements[e.parent].displayed); end
    root=d.elements[1]
    if root.displayed && root.style["position"]!="absolute"; layout!(d,1,d.width,d.height); root.rx=edge(root,"margin","left"); root.ry=edge(root,"margin","top"); end
    for (i,e) in enumerate(d.elements)
        e.displayed && e.style["position"]=="absolute" || continue; p=ancestor(d,i); bw=p==0 ? d.width : paddingbox(d.elements[p])[3]; bh=p==0 ? d.height : paddingbox(d.elements[p])[4]; top,right,bottom,left=(inset(e,side) for side in SIDES); width=resolvedlength(e,"width",bw,true)
        if width===nothing; room=max(0,bw-something(left,0)-something(right,0)-outer(e,true)); width=left!==nothing && right!==nothing ? room : min(maxcontent(d,i),room); end
        fw=constrain(e,width,true,bw); fh=nothing
        if e.style["height"]=="auto" && top!==nothing && bottom!==nothing; fh=constrain(e,max(0,bh-top-bottom-outer(e,false)),false,bh); end
        layout!(d,i,bw,bh,fw,fh); e.rx=absoffset(left,right,edge(e,"margin","left"),edge(e,"margin","right"),bw-borderwidth(e)); e.ry=absoffset(top,bottom,edge(e,"margin","top"),edge(e,"margin","bottom"),bh-borderheight(e))
    end
    for (i,e) in enumerate(d.elements)
        e.displayed || continue; p=e.style["position"]=="absolute" ? ancestor(d,i) : e.parent
        ox,oy=p==0 ? (0,0) : e.style["position"]=="absolute" ? paddingbox(d.elements[p])[1:2] : (d.elements[p].x,d.elements[p].y); e.x=ox+e.rx; e.y=oy+e.ry
        if e.style["position"]=="relative"; e.x+=relshift(inset(e,"left"),inset(e,"right")); e.y+=relshift(inset(e,"top"),inset(e,"bottom")); end
    end
end
snapshot(d)=[e.displayed ? borderbox(e) : nothing for e in d.elements]
function changes(d,before)
    ids=[e.id for (e,old,new) in zip(d.elements,before,snapshot(d)) if old!=new]; isempty(ids) ? "no change" : join(ids,' ')
end
boxtext(box)=join(box,' ')
function overflows(d,e)
    e.text!==nothing && return maximum(length,e.lines)>e.cw || length(e.lines)>e.ch
    x,y,w,h=contentbox(e)
    for j in flow(d,e); a,b,c,f=marginbox(d.elements[j]); (a<x || b<y || a+c>x+w || b+f>y+h) && return true; end
    false
end
function render(d)
    screen=fill('.',d.height,d.width)
    for e in d.elements
        e.displayed || continue; x,y,w,h=borderbox(e)
        for yy in max(0,y):min(d.height,y+h)-1, xx in max(0,x):min(d.width,x+w)-1
            onrow=(edge(e,"border","top")==1 && yy==y) || (edge(e,"border","bottom")==1 && yy==y+h-1); oncol=(edge(e,"border","left")==1 && xx==x) || (edge(e,"border","right")==1 && xx==x+w-1); screen[yy+1,xx+1]=onrow ? (oncol ? '+' : '-') : (oncol ? '|' : ' ')
        end
        if e.text!==nothing
            tx,ty,_,_=contentbox(e)
            for (row,text) in enumerate(e.lines), (col,c) in enumerate(text); xx=tx+col-1; yy=ty+row-1; 0<=xx<d.width && 0<=yy<d.height && (screen[yy+1,xx+1]=c); end
        end
    end
    println("render $(d.width)x$(d.height)"); boundary=repeat("#",d.width+2); println(boundary)
    for row in eachrow(screen); println("#",join(row),"#"); end
    println(boundary)
end
function execute!(d,line)
    p=String.(split(line,' ';limit=4)); command=p[1]
    if command=="LAYOUT"
        println("layout $(d.width)x$(d.height)"); for e in d.elements; println(repeat("  ",e.depth),e.id," ",e.displayed ? boxtext(borderbox(e)) : "none"); end
    elseif command=="BOX"
        i=findfirst(e->e.id==p[2],d.elements)
        if i===nothing; println("error: unknown element $(p[2])")
        elseif !d.elements[i].displayed; println("box $(p[2]): none")
        else; e=d.elements[i]; println("box $(e.id)"); for (kind,box) in (("margin",marginbox(e)),("border",borderbox(e)),("padding",paddingbox(e)),("content",contentbox(e))); println(kind," ",boxtext(box)); end; end
    elseif command=="RENDER"; render(d)
    elseif command=="HIT"
        x=parse(Int,p[2]); y=parse(Int,p[3])
        if x>=d.width || y>=d.height; println("error: point $x $y outside viewport"); return; end
        target=0
        for (i,e) in enumerate(d.elements); a,b,w,h=borderbox(e); e.displayed && a<=x<a+w && b<=y<b+h && (target=i); end
        path=String[]
        while target!=0; pushfirst!(path,d.elements[target].id); target=d.elements[target].parent; end
        println("hit $x $y: ",isempty(path) ? "none" : join(path," > "))
    elseif command=="SET"
        id,property,value=p[2:4]; i=findfirst(e->e.id==id,d.elements)
        if i===nothing; println("error: unknown element $id"); return; end
        if !known_property(property); println("error: unknown property $property"); return; end
        declarations=expanddecl(property,value)
        if declarations===nothing; println("error: invalid value for $property: $value"); return; end
        before=snapshot(d); merge!(d.elements[i].style,Dict(declarations)); performlayout!(d); println("set $id $property $value: $(changes(d,before))")
    elseif command=="VIEWPORT"
        w=parse(Int,p[2]); h=parse(Int,p[3])
        if !(1<=w<=80 && 1<=h<=40); println("error: invalid viewport $w $h"); return; end
        before=snapshot(d); d.width=w; d.height=h; performlayout!(d); println("viewport $w $h: $(changes(d,before))")
    elseif command=="OVERFLOW"
        ids=[e.id for e in d.elements if e.displayed && overflows(d,e)]; println("overflow: ",isempty(ids) ? "none" : join(ids,' '))
    else; println("error: unknown command $command"); end
end
function main()
    w,h=parse.(Int,split(readline())); rules=Tuple{Vector{String},Vector{Pair{String,String}}}[]
    while true
        line=readline(); line=="---" && break; selectors,body=split(line," { ";limit=2); declarations=Pair{String,String}[]
        for declaration in split(body[1:end-2],"; "); property,value=String.(split(declaration,": ";limit=2)); expanded=expanddecl(property,value); expanded!==nothing && append!(declarations,expanded); end
        push!(rules,(String.(split(selectors,", ")),declarations))
    end
    elements=CssElement[]; stack=Int[]
    while true
        line=readline(); line=="===" && break; head=lstrip(line,' '); depth=div(length(line)-length(head),2); pieces=split(head,' ';limit=2); tag,names=split(pieces[1],'#'); names=String.(split(names,'.')); text=length(pieces)==2 ? String(pieces[2][2:end-1]) : nothing; resize!(stack,depth); parent=isempty(stack) ? 0 : stack[end]
        e=CssElement(String(tag),names[1],names[2:end],text,parent,depth,Int[],copy(INITIAL),false,0,0,String[],0,0,0,0); winners=Dict{String,Int}()
        for (selectors,declarations) in rules
            specificity=-1
            for selector in selectors; score=startswith(selector,"#") ? (selector[2:end]==e.id ? 2 : -1) : startswith(selector,".") ? (selector[2:end] in e.classes ? 1 : -1) : (selector==e.tag ? 0 : -1); specificity=max(specificity,score); end
            specificity<0 && continue
            for (property,value) in declarations; if specificity>=get(winners,property,-1); winners[property]=specificity; e.style[property]=value; end; end
        end
        push!(elements,e); parent!=0 && push!(elements[parent].children,length(elements)); push!(stack,length(elements))
    end
    document=Document(w,h,elements,fill(-1,length(elements))); performlayout!(document)
    while true; line=readline(); line=="END" && break; execute!(document,line); end
end
main()
