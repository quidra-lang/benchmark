local Canvas=require('canvas')
local Primitives=require('primitives')
local Clipping=require('clipping')
local Fill=require('fill')
local Writer=require('ppm_writer')
local fmt=string.format
local min,max=math.min,math.max
local function words(line) local result={}; for word in line:gmatch('[^ ]+') do result[#result+1]=word end; return result end
local function read_lines(path) local lines={}; for line in io.lines(path) do lines[#lines+1]=line end; return lines end
local function extend(a,b) for _,value in ipairs(b) do a[#a+1]=value end end
local function rectangle(x0,y0,x1,y1) return {x0=x0,y0=y0,x1=x1,y1=y1} end
local function copy_matrix(m) return {a=m.a,b=m.b,c=m.c,d=m.d,e=m.e,f=m.f} end
local function copy_clip(c) return rectangle(c.x0,c.y0,c.x1,c.y1) end
local function transform(m,p) return {x=m.a*p.x+m.b*p.y+m.e,y=m.c*p.x+m.d*p.y+m.f} end
local function translate(m,x,y) m.e=m.e+m.a*x+m.b*y; m.f=m.f+m.c*x+m.d*y end
local function device_rectangle(m,p,q) p,q=transform(m,p),transform(m,q); return rectangle(min(p.x,q.x),min(p.y,q.y),max(p.x,q.x),max(p.y,q.y)) end
local function clone_state(state)
    local copy={matrix=copy_matrix(state.matrix),clip=copy_clip(state.clip),stack={}}
    for _,pair in ipairs(state.stack) do copy.stack[#copy.stack+1]={matrix=copy_matrix(pair.matrix),clip=copy_clip(pair.clip)} end
    return copy
end
local function restore_state(state,snapshot) local copy=clone_state(snapshot); state.matrix,state.clip,state.stack=copy.matrix,copy.clip,copy.stack end
local function parse_body(lines,position,ending)
    local nodes={}
    while true do
        local source=lines[position]; position=position+1
        if source.keyword==ending then return nodes,position,source.number end
        local node={source=source}
        if source.keyword=='REPEAT' then node.repeating=true; node.count=tonumber(source.arguments[1]); node.dx=tonumber(source.arguments[2]); node.dy=tonumber(source.arguments[3]); node.body,position=parse_body(lines,position,'ENDREPEAT') end
        nodes[#nodes+1]=node
    end
end
local function read_scene()
    local s={colors={},pens={},brushes={},symbols={},layers={},probes={},sequence=0,drawing=0,state=0,errors=0,painted=0,erased=0,error_counts={},keywords={},log={}}
    for line in io.lines('input/styles.txt') do
        if line~='' and line:sub(1,1)~='#' then
            local p=words(line)
            if p[1]=='color' then s.colors[p[2]]={value={tonumber(p[3]),tonumber(p[4]),tonumber(p[5]),tonumber(p[6])}}
            elseif p[1]=='pen' then s.pens[p[2]]={width=tonumber(p[3]),color=s.colors[p[4]],on=tonumber(p[5]),off=tonumber(p[6])}
            elseif p[1]=='brush' then s.brushes[p[2]]={first=s.colors[p[3]],rule=p[4]}
            elseif p[1]=='gradient' then s.brushes[p[2]]={first=s.colors[p[3]],second=s.colors[p[4]],axis=p[5],rule=p[6]} end
        end
    end
    local lines=read_lines('input/font.txt'); local header=words(lines[1]); s.font={width=tonumber(header[2]),height=tonumber(header[3]),glyphs={}}
    local at=2
    while at<=#lines do local character=lines[at]:sub(7); local glyph={}; for j=1,s.font.height do glyph[j]=lines[at+j] end; s.font.glyphs[character]=glyph; at=at+s.font.height+1 end
    local source={}
    for number,line in ipairs(read_lines('input/scene.txt')) do local trimmed=line:gsub('^ +',''); if trimmed~='' and trimmed:sub(1,1)~='#' then local p=words(trimmed); local keyword=table.remove(p,1); source[#source+1]={number=number,keyword=keyword,arguments=p} end end
    local canvas=source[1].arguments; s.width=tonumber(canvas[1]); s.height=tonumber(canvas[2]); s.background=s.colors[canvas[3]]; s.background.used=true
    local position=2
    while position<=#source do local line=source[position]; local body,next_position,end_line=parse_body(source,position+1,'END'); position=next_position; local args=line.arguments; if line.keyword=='SYMBOL' then s.symbols[args[1]]={body=body,end_line=end_line,uses=0} else s.layers[#s.layers+1]={name=args[1],surface=Canvas.layer(s.width,s.height,tonumber(args[2]),args[3]),body=body,commands=0,errors=0} end end
    lines=read_lines('input/probes.txt')
    for i=2,tonumber(lines[1])+1 do local p=words(lines[i]); local probe={point=p[1]=='point'}; if probe.point then local x,y=tonumber(p[2]),tonumber(p[3]); probe.area=rectangle(x,y,x,y) else probe.area=rectangle(tonumber(p[2]),tonumber(p[3]),tonumber(p[4]),tonumber(p[5])) end; s.probes[#s.probes+1]=probe end
    return s
end
local function integer_word(word) if word:sub(1,1)=='-' then word=word:sub(2) end; return word~='' and word:match('^[0-9]+$')~=nil end
local path_counts={M=2,L=2,H=1,V=1,Q=4,C=6,Z=0}
local function path_data(input)
    if #input==0 then return nil end
    local result={}; local at,expect_move=1,true
    while at<=#input do
        local kind=input[at]; at=at+1; local upper=kind:upper(); local count=path_counts[upper]
        if #kind~=1 or count==nil or expect_move and upper~='M' or at+count-1>#input then return nil end
        local values={}; for i=0,count-1 do if not integer_word(input[at+i]) then return nil end; values[#values+1]=tonumber(input[at+i]) end
        result[#result+1]={kind=kind,values=values}; at=at+count; expect_move=upper=='Z'
    end
    return result
end
local pen_commands={LINE=true,RECT=true,CIRCLE=true,ELLIPSE=true,POLYLINE=true,POLYGON=true,PATH=true}
local brush_commands={FILLRECT=true,FILLCIRCLE=true,FILLELLIPSE=true,FILLPOLYGON=true,FILLPATH=true,FLOOD=true,TEXT=true}
local state_commands={TRANSLATE=true,SCALE=true,ROTATE=true,SAVE=true,RESTORE=true,CLIP=true,NOCLIP=true,USE=true}
local function tail(args,start) local result={}; for i=start,#args do result[#result+1]=args[i] end; return result end
local function validate(s,line,state)
    local name,args=line.keyword,line.arguments
    if not pen_commands[name] and not brush_commands[name] and not state_commands[name] and name~='ERASE' then return 'unknown_command' end
    local expected,start,finish=nil,1,#args
    if name=='LINE' or name=='RECT' or name=='FILLRECT' or name=='ELLIPSE' or name=='FILLELLIPSE' then expected,start=5,2
    elseif name=='CIRCLE' or name=='FILLCIRCLE' then expected,start=4,2
    elseif name=='FLOOD' then expected,start=3,2
    elseif name=='TEXT' then expected,start,finish=5,2,3
    elseif name=='ERASE' or name=='CLIP' then expected=4
    elseif name=='TRANSLATE' or name=='SCALE' then expected=2
    elseif name=='ROTATE' then expected=1
    elseif name=='SAVE' or name=='RESTORE' or name=='NOCLIP' then expected=0
    elseif name=='USE' then expected,start=3,2
    elseif name=='POLYLINE' or name=='POLYGON' or name=='FILLPOLYGON' then start=2
    elseif name=='PATH' or name=='FILLPATH' then start,finish=2,2 end
    if expected and #args~=expected or not expected and #args<2 then return 'bad_arguments' end
    for i=start,finish do if not integer_word(args[i]) then return 'bad_arguments' end end
    if name=='POLYLINE' or name=='POLYGON' or name=='FILLPOLYGON' then if #args~=2+2*tonumber(args[2]) then return 'bad_arguments' end end
    if name=='PATH' or name=='FILLPATH' then if not path_data(tail(args,3)) then return 'bad_arguments' end end
    if pen_commands[name] and not s.pens[args[1]] or brush_commands[name] and not s.brushes[args[1]] then return 'unknown_style' end
    if name=='USE' then local symbol=s.symbols[args[1]]; if not symbol or symbol.end_line>line.number then return 'unknown_symbol' end end
    if name=='TEXT' then for i=1,#args[5] do local character=args[5]:sub(i,i); if character~='_' and not s.font.glyphs[character] then return 'unknown_glyph' end end end
    local bad=false
    if name=='CIRCLE' or name=='FILLCIRCLE' then bad=tonumber(args[4])<1
    elseif name=='ELLIPSE' or name=='FILLELLIPSE' then bad=tonumber(args[4])<1 or tonumber(args[5])<1
    elseif name=='POLYLINE' then bad=tonumber(args[2])<2
    elseif name=='POLYGON' or name=='FILLPOLYGON' then bad=tonumber(args[2])<3
    elseif name=='PATH' or name=='FILLPATH' then bad=tonumber(args[2])<1 or tonumber(args[2])>32
    elseif name=='FLOOD' then bad=not Canvas.contains(state.clip,transform(state.matrix,{x=tonumber(args[2]),y=tonumber(args[3])}))
    elseif name=='TEXT' then bad=args[4]~='left' and args[4]~='center' and args[4]~='right'
    elseif name=='SCALE' then bad=tonumber(args[1])==0 or tonumber(args[2])==0
    elseif name=='CLIP' then bad=Canvas.empty(Canvas.intersection(state.clip,device_rectangle(state.matrix,{x=tonumber(args[1]),y=tonumber(args[2])},{x=tonumber(args[3]),y=tonumber(args[4])}))) end
    if bad then return 'bad_value' end
    if name=='RESTORE' and #state.stack==0 then return 'stack_empty' end
end
local function build_subpaths(commands,segments,matrix)
    local subpaths={}; local current,start={x=0,y=0},{x=0,y=0}
    for _,command in ipairs(commands) do
        local kind=command.kind:upper(); local relative=command.kind~=kind; local values=command.values
        if kind=='Z' then subpaths[#subpaths].closed=true; current=start
        else
            local points={}
            if kind=='H' then points={{x=values[1]+(relative and current.x or 0),y=current.y}}
            elseif kind=='V' then points={{x=current.x,y=values[1]+(relative and current.y or 0)}}
            else for i=1,#values,2 do points[#points+1]={x=values[i]+(relative and current.x or 0),y=values[i+1]+(relative and current.y or 0)} end end
            current=points[#points]
            if kind=='M' then start=current; subpaths[#subpaths+1]={points={transform(matrix,current)}}
            else
                local subpath=subpaths[#subpaths]
                if kind=='Q' or kind=='C' then local controls={subpath.points[#subpath.points]}; for _,p in ipairs(points) do controls[#controls+1]=transform(matrix,p) end; local curve=Primitives.bezier(controls,segments); for i=2,#curve do subpath.points[#subpath.points+1]=curve[i] end
                else subpath.points[#subpath.points+1]=transform(matrix,current) end
            end
        end
    end
    return subpaths
end
local function add_rectangle(pixels,r) for y=r.y0,r.y1 do for x=r.x0,r.x1 do Primitives.add(pixels,x,y) end end end
local function pen_coverage(segments,pen,clip)
    local pixels={}; local index=0
    for _,segment in ipairs(segments) do
        local first,last=Clipping.segment(segment[1],segment[2],clip)
        if first then for _,p in ipairs(Primitives.bresenham(first,last)) do local keep=pen.off==0 or index%(pen.on+pen.off)<pen.on; index=index+1; if keep then for _,pixel in ipairs(Primitives.square(p,pen.width)) do if Canvas.contains(clip,pixel) then Primitives.add(pixels,pixel.x,pixel.y) end end end end end
    end
    return pixels
end
local function bounds(pixels)
    local box
    for _,p in pairs(pixels) do if not box then box=rectangle(p.x,p.y,p.x,p.y) else box.x0=min(box.x0,p.x); box.y0=min(box.y0,p.y); box.x1=max(box.x1,p.x); box.y1=max(box.y1,p.y) end end
    return box
end
local function box_text(pixels) local box=bounds(pixels); return box and fmt('%d %d %d %d',box.x0,box.y0,box.x1,box.y1) or 'none' end
local function coverage(s,line,state,layer)
    local name,args=line.keyword,line.arguments; local matrix,clip=state.matrix,state.clip; local points,segments,pixels={},{},{}
    if name=='LINE' then segments={{transform(matrix,{x=tonumber(args[2]),y=tonumber(args[3])}),transform(matrix,{x=tonumber(args[4]),y=tonumber(args[5])})}}
    elseif name=='RECT' or name=='FILLRECT' or name=='ERASE' then
        local offset=name=='ERASE' and 1 or 2; local r=device_rectangle(matrix,{x=tonumber(args[offset]),y=tonumber(args[offset+1])},{x=tonumber(args[offset+2]),y=tonumber(args[offset+3])})
        if name=='RECT' then points={{x=r.x0,y=r.y0},{x=r.x1,y=r.y0},{x=r.x1,y=r.y1},{x=r.x0,y=r.y1}}; for i,p in ipairs(points) do segments[#segments+1]={p,points[i%4+1]} end
        else add_rectangle(pixels,Canvas.intersection(r,clip)); if name=='ERASE' then for key,p in pairs(pixels) do if not layer:at(p) then pixels[key]=nil end end end; return pixels end
    elseif name=='POLYLINE' or name=='POLYGON' or name=='FILLPOLYGON' then
        for i=3,#args,2 do points[#points+1]=transform(matrix,{x=tonumber(args[i]),y=tonumber(args[i+1])}) end
        if name=='FILLPOLYGON' then return Fill.polygons({Clipping.polygon(points,clip)},s.brushes[args[1]].rule,clip) end
        for i=1,#points-1 do segments[#segments+1]={points[i],points[i+1]} end
        if name=='POLYGON' then segments[#segments+1]={points[#points],points[1]} end
    elseif name=='CIRCLE' or name=='FILLCIRCLE' or name=='ELLIPSE' or name=='FILLELLIPSE' then
        local center=transform(matrix,{x=tonumber(args[2]),y=tonumber(args[3])}); local rx,ry=tonumber(args[4]),tonumber(args[4]); if name=='ELLIPSE' or name=='FILLELLIPSE' then ry=tonumber(args[5]) end
        rx,ry=math.abs(matrix.a)*rx+math.abs(matrix.b)*ry,math.abs(matrix.c)*rx+math.abs(matrix.d)*ry
        local shape
        if (name=='CIRCLE' or name=='FILLCIRCLE') and rx==ry then shape=Primitives.circle(rx) else shape=Primitives.ellipse(rx,ry) end
        if name=='FILLCIRCLE' or name=='FILLELLIPSE' then return Fill.shape(center,shape,clip) end
        local pen=s.pens[args[1]]; for _,p in pairs(shape) do for _,pixel in ipairs(Primitives.square({x=center.x+p.x,y=center.y+p.y},pen.width)) do if Canvas.contains(clip,pixel) then Primitives.add(pixels,pixel.x,pixel.y) end end end
        return pixels
    elseif name=='FLOOD' then return Fill.flood(layer,transform(matrix,{x=tonumber(args[2]),y=tonumber(args[3])}),clip)
    elseif name=='TEXT' then
        local text=args[5]; local x,y=tonumber(args[2]),tonumber(args[3]); local extent=#text*(s.font.width+1)-1; if args[4]=='center' then x=x-extent//2 elseif args[4]=='right' then x=x-extent+1 end
        for i=1,#text do
            local character=text:sub(i,i)
            if character~='_' then local ox=x+(i-1)*(s.font.width+1); for j,row in ipairs(s.font.glyphs[character]) do for k=1,#row do if row:sub(k,k)=='#' then local r=device_rectangle(matrix,{x=ox+k-1,y=y+j-1},{x=ox+k,y=y+j}); r.x1=r.x1-1; r.y1=r.y1-1; add_rectangle(pixels,Canvas.intersection(r,clip)) end end end end
        end
        return pixels
    elseif name=='PATH' or name=='FILLPATH' then
        local subpaths=build_subpaths(path_data(tail(args,3)),tonumber(args[2]),matrix); local sequences={}
        for _,subpath in ipairs(subpaths) do
            if name=='FILLPATH' then sequences[#sequences+1]=Clipping.polygon(subpath.points,clip)
            else for i=1,#subpath.points-1 do segments[#segments+1]={subpath.points[i],subpath.points[i+1]} end; if subpath.closed then segments[#segments+1]={subpath.points[#subpath.points],subpath.points[1]} end end
        end
        if name=='FILLPATH' then return Fill.polygons(sequences,s.brushes[args[1]].rule,clip) end
    end
    return pen_coverage(segments,s.pens[args[1]],clip)
end
local execute
local function execute_block(s,layer,nodes,state)
    for _,node in ipairs(nodes) do
        if node.repeating then local snapshot=clone_state(state); for k=0,node.count-1 do restore_state(state,snapshot); translate(state.matrix,k*node.dx,k*node.dy); execute_block(s,layer,node.body,state) end; restore_state(state,snapshot)
        else execute(s,layer,node.source,state) end
    end
end
execute=function(s,layer,line,state)
    s.sequence=s.sequence+1; layer.commands=layer.commands+1; local name,args=line.keyword,line.arguments; local total=s.keywords[name]
    if not total then total={executed=0,errors=0,pixels=0}; s.keywords[name]=total end
    total.executed=total.executed+1; local prefix=fmt('cmd %d line %d %s',s.sequence,line.number,name); local reason=validate(s,line,state)
    if reason then s.errors=s.errors+1; layer.errors=layer.errors+1; s.error_counts[reason]=(s.error_counts[reason] or 0)+1; total.errors=total.errors+1; s.log[#s.log+1]=prefix..' error '..reason; return end
    if pen_commands[name] or brush_commands[name] or name=='ERASE' then
        local pixels=coverage(s,line,state,layer.surface); local count=Primitives.count(pixels); s.drawing=s.drawing+1; total.pixels=total.pixels+count
        if name=='ERASE' then s.erased=s.erased+count; for _,p in pairs(pixels) do layer.surface:erase(p) end
        else
            s.painted=s.painted+count
            if pen_commands[name] then local pen=s.pens[args[1]]; pen.used=true; pen.color.used=true; for _,p in pairs(pixels) do layer.surface:paint(p,pen.color.value,line.number) end
            else
                local brush=s.brushes[args[1]]; brush.used=true; brush.first.used=true; if brush.second then brush.second.used=true end; local box=bounds(pixels)
                for _,p in pairs(pixels) do
                    local color={}; for k=1,4 do color[k]=brush.first.value[k] end
                    if brush.second then local t,length=p.x-box.x0,box.x1-box.x0; if brush.axis=='y' then t,length=p.y-box.y0,box.y1-box.y0 end; if length>0 then for k=1,4 do color[k]=color[k]+Canvas.round((brush.second.value[k]-color[k])*t,length) end end end
                    layer.surface:paint(p,color,line.number)
                end
            end
        end
        s.log[#s.log+1]=fmt('%s pixels %d box %s',prefix,count,box_text(pixels)); return
    end
    s.state=s.state+1; s.log[#s.log+1]=prefix..' ok'; local m=state.matrix
    if name=='TRANSLATE' then translate(m,tonumber(args[1]),tonumber(args[2]))
    elseif name=='SCALE' then local x,y=tonumber(args[1]),tonumber(args[2]); m.a=m.a*x; m.c=m.c*x; m.b=m.b*y; m.d=m.d*y
    elseif name=='ROTATE' then for _=1,tonumber(args[1])%4 do m.a,m.b,m.c,m.d=m.b,-m.a,m.d,-m.c end
    elseif name=='SAVE' then state.stack[#state.stack+1]={matrix=copy_matrix(m),clip=copy_clip(state.clip)}
    elseif name=='RESTORE' then local pair=table.remove(state.stack); state.matrix,state.clip=pair.matrix,pair.clip
    elseif name=='CLIP' then state.clip=Canvas.intersection(state.clip,device_rectangle(m,{x=tonumber(args[1]),y=tonumber(args[2])},{x=tonumber(args[3]),y=tonumber(args[4])}))
    elseif name=='NOCLIP' then state.clip=rectangle(0,0,s.width-1,s.height-1)
    elseif name=='USE' then local symbol=s.symbols[args[1]]; symbol.uses=symbol.uses+1; local snapshot=clone_state(state); translate(m,tonumber(args[2]),tonumber(args[3])); execute_block(s,layer,symbol.body,state); restore_state(state,snapshot) end
end
local function sorted_keys(values) local keys={}; for key in pairs(values) do keys[#keys+1]=key end; table.sort(keys); return keys end
local function color_counts(counts)
    local entries={}; for _,entry in pairs(counts) do entries[#entries+1]=entry end
    table.sort(entries,function(a,b) if a.count~=b.count then return a.count>b.count end; for k=1,#a.color do if a.color[k]~=b.color[k] then return a.color[k]<b.color[k] end end; return false end)
    return entries
end
local function add_color(counts,color)
    local key=table.concat(color,','); local entry=counts[key]
    if entry then entry.count=entry.count+1 else counts[key]={color=color,count=1} end
end
local function write_text(name,lines)
    local file=assert(io.open('output/'..name,'w')); if #lines>0 then file:write(table.concat(lines,'\n'),'\n') end; file:close()
end
local function output(s,image)
    Writer.image(image,s.width,s.height); Writer.preview(image,s.width,s.height); write_text('commands.txt',s.log); local layers={fmt('layers %d',#s.layers)}
    for i,layer in ipairs(s.layers) do
        local pixels,counts={},{}; local visible=0
        for y=0,s.height-1 do for x=0,s.width-1 do local p={x=x,y=y}; local pixel=layer.surface:at(p); if pixel then
            Primitives.add(pixels,x,y); add_color(counts,pixel.color)
            if layer.surface:alpha(p)>0 then local covered=false; for j=i+1,#s.layers do if s.layers[j].surface:alpha(p)==255 then covered=true; break end end; if not covered then visible=visible+1 end end
        end end end
        local colors=color_counts(counts)
        layers[#layers+1]=fmt('layer %d %s opacity %d mode %s commands %d errors %d pixels %d box %s visible %d colors %d',i,layer.name,layer.surface.opacity,layer.surface.mode,layer.commands,layer.errors,Primitives.count(pixels),box_text(pixels),visible,#colors)
        for k=1,min(5,#colors) do local entry=colors[k]; local c=entry.color; layers[#layers+1]=fmt('color %d %d %d %d pixels %d',c[1],c[2],c[3],c[4],entry.count) end
    end
    write_text('layers.txt',layers)
    local summary={fmt('canvas %d %d',s.width,s.height),fmt('background %d %d %d',s.background.value[1],s.background.value[2],s.background.value[3]),'layers '..#s.layers,'symbols '..#sorted_keys(s.symbols),'commands '..s.sequence,'drawing '..s.drawing,'state '..s.state,'errors '..s.errors}
    for _,reason in ipairs({'unknown_command','bad_arguments','unknown_style','unknown_symbol','unknown_glyph','bad_value','stack_empty'}) do summary[#summary+1]=fmt('error %s %d',reason,s.error_counts[reason] or 0) end
    local counts={}; for _,rgb in ipairs(image) do add_color(counts,rgb) end; local colors=color_counts(counts)
    extend(summary,{'painted '..s.painted,'erased '..s.erased,'colors '..#colors})
    for i=1,min(8,#colors) do local entry=colors[i]; local c=entry.color; summary[#summary+1]=fmt('top %d %d %d %d pixels %d',i,c[1],c[2],c[3],entry.count) end
    for _,name in ipairs(sorted_keys(s.symbols)) do summary[#summary+1]=fmt('symbol %s uses %d',name,s.symbols[name].uses) end
    for _,name in ipairs(sorted_keys(s.keywords)) do local total=s.keywords[name]; summary[#summary+1]=fmt('keyword %s executed %d errors %d pixels %d',name,total.executed,total.errors,total.pixels) end
    local unused={}
    for _,name in ipairs(sorted_keys(s.colors)) do if not s.colors[name].used then unused[#unused+1]='unused color '..name end end
    for _,name in ipairs(sorted_keys(s.pens)) do if not s.pens[name].used then unused[#unused+1]='unused pen '..name end end
    for _,name in ipairs(sorted_keys(s.brushes)) do if not s.brushes[name].used then unused[#unused+1]='unused brush '..name end end
    for _,name in ipairs(sorted_keys(s.symbols)) do if s.symbols[name].uses==0 then unused[#unused+1]='unused symbol '..name end end
    summary[#summary+1]='unused '..#unused; extend(summary,unused); write_text('summary.txt',summary)
    local probes={}
    for i,probe in ipairs(s.probes) do
        local r=probe.area
        if probe.point then
            local p={x=r.x0,y=r.y0}; local rgb=image[p.y*s.width+p.x+1]; local stack={}
            for j,layer in ipairs(s.layers) do if layer.surface:alpha(p)>0 then stack[#stack+1]=j..':'..layer.surface:at(p).line end end
            probes[#probes+1]=fmt('point %d %d %d rgb %d %d %d layers %d stack %s',i,p.x,p.y,rgb[1],rgb[2],rgb[3],#stack,#stack>0 and table.concat(stack,' ') or 'none')
        else
            local count=(r.x1-r.x0+1)*(r.y1-r.y0+1); local sums,colors,cover={0,0,0},{},{}; for j=1,#s.layers do cover[j]=0 end
            for y=r.y0,r.y1 do for x=r.x0,r.x1 do local p={x=x,y=y}; local rgb=image[y*s.width+x+1]; colors[table.concat(rgb,',')]=true; for k=1,3 do sums[k]=sums[k]+rgb[k] end; for j,layer in ipairs(s.layers) do if layer.surface:alpha(p)>0 then cover[j]=cover[j]+1 end end end end
            local line=fmt('area %d %d %d %d %d pixels %d mean %d %d %d colors %d cover',i,r.x0,r.y0,r.x1,r.y1,count,sums[1]//count,sums[2]//count,sums[3]//count,#sorted_keys(colors)); for _,n in ipairs(cover) do line=line..' '..n end; probes[#probes+1]=line
        end
    end
    write_text('probes.txt',probes)
end
local scene=read_scene()
local surfaces={}
for i,layer in ipairs(scene.layers) do local state={matrix={a=1,b=0,c=0,d=1,e=0,f=0},clip=rectangle(0,0,scene.width-1,scene.height-1),stack={}}; execute_block(scene,layer,layer.body,state); surfaces[i]=layer.surface end
local image=Canvas.composite(surfaces,scene.background.value,scene.width,scene.height)
os.execute('mkdir -p output')
output(scene,image)
