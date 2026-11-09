include("canvas.jl")
include("primitives.jl")
include("clipping.jl")
include("fill.jl")
include("ppm_writer.jl")
using .RasterCanvas, .Primitives, .Clipping, .RasterFill, .PPMWriter

const Transform = NTuple{6,Int}
const StatePair = Tuple{Transform,Rect}
const IDENTITY = (1,0,0,1,0,0)
const PEN_COMMANDS = ("LINE","RECT","CIRCLE","ELLIPSE","POLYLINE","POLYGON","PATH")
const BRUSH_COMMANDS = ("FILLRECT","FILLCIRCLE","FILLELLIPSE","FILLPOLYGON","FILLPATH","FLOOD","TEXT")
const STATE_COMMANDS = ("TRANSLATE","SCALE","ROTATE","SAVE","RESTORE","CLIP","NOCLIP","USE")
const COMMANDS = (PEN_COMMANDS...,BRUSH_COMMANDS...,"ERASE",STATE_COMMANDS...)
const ERRORS = ("unknown_command","bad_arguments","unknown_style","unknown_symbol","unknown_glyph","bad_value","stack_empty")
const FIXED_FORMS = Dict("LINE"=>(5,2),"RECT"=>(5,2),"FILLRECT"=>(5,2),"CIRCLE"=>(4,2),"FILLCIRCLE"=>(4,2),"ELLIPSE"=>(5,2),"FILLELLIPSE"=>(5,2),"FLOOD"=>(3,2),"ERASE"=>(4,1),"TRANSLATE"=>(2,1),"SCALE"=>(2,1),"ROTATE"=>(1,1),"SAVE"=>(0,1),"RESTORE"=>(0,1),"NOCLIP"=>(0,1),"CLIP"=>(4,1),"USE"=>(3,2))
const PATH_ARITY = Dict('M'=>2,'L'=>2,'H'=>1,'V'=>1,'Q'=>4,'C'=>6,'Z'=>0)
struct Pen
    width::Int
    color::String
    on::Int
    off::Int
end
struct Brush
    colors::Vector{String}
    axis::Union{Nothing,String}
    rule::String
end
Base.@kwdef mutable struct Styles
    colors::Dict{String,Color} = Dict{String,Color}()
    pens::Dict{String,Pen} = Dict{String,Pen}()
    brushes::Dict{String,Brush} = Dict{String,Brush}()
end
struct Font
    width::Int
    height::Int
    glyphs::Dict{Char,Vector{Point}}
end
abstract type Item end
struct Command <: Item
    line::Int
    keyword::String
    arguments::Vector{String}
end
struct Repetition <: Item
    count::Int
    dx::Int
    dy::Int
    body::Vector{Item}
end
Base.@kwdef mutable struct Block
    name::String
    opacity::Int = 0
    mode::String = ""
    body::Vector{Item} = Item[]
    end_line::Int = 0
end
Base.@kwdef mutable struct Scene
    width::Int = 0
    height::Int = 0
    background::String = ""
    layers::Vector{Block} = Block[]
    symbols::Dict{String,Block} = Dict{String,Block}()
end
struct Probe
    kind::String
    values::Vector{Int}
end
struct PathCommand
    letter::Char
    values::Vector{Int}
end
Base.@kwdef mutable struct Subpath
    points::Vector{Point}
    closed::Bool = false
end
Base.@kwdef mutable struct Execution
    sequence::Int
    layer::Int
    command::Command
    kind::Symbol = :state
    error::Union{Nothing,String} = nothing
    pixels::Int = 0
    box::Union{Nothing,Rect} = nothing
end
mutable struct DrawingState
    screen::Rect
    matrix::Transform
    clip::Rect
    stack::Vector{StatePair}
end
DrawingState(screen) = DrawingState(screen, IDENTITY, screen, StatePair[])
snapshot(state) = (state.matrix, state.clip, copy(state.stack))
function rollback!(state, saved)
    state.matrix, state.clip, state.stack = saved[1], saved[2], copy(saved[3])
end
function transform(state, x, y)
    a,b,c,d,e,f = state.matrix
    (a*x+b*y+e,c*x+d*y+f)
end
function device_rect(state, x0, y0, x1, y1)
    ax,ay = transform(state,x0,y0)
    bx,by = transform(state,x1,y1)
    (min(ax,bx),min(ay,by),max(ax,bx),max(ay,by))
end
function device_radii(state, rx, ry)
    a,b,c,d,_,_ = state.matrix
    (abs(a)*rx+abs(b)*ry,abs(c)*rx+abs(d)*ry)
end
function translate_state!(state, dx, dy)
    a,b,c,d,e,f = state.matrix
    state.matrix = (a,b,c,d,e+a*dx+b*dy,f+c*dx+d*dy)
end
rect_intersection(a,b) = (max(a[1],b[1]),max(a[2],b[2]),min(a[3],b[3]),min(a[4],b[4]))
rect_empty(rect) = rect[1] > rect[3] || rect[2] > rect[4]
rect_contains(rect, point) = rect[1] <= point[1] <= rect[3] && rect[2] <= point[2] <= rect[4]
rect_pixels(rect) = Set{Point}((x,y) for y in rect[2]:rect[4] for x in rect[1]:rect[3])
function bounding_box(pixels)
    isempty(pixels) && return nothing
    xs = [p[1] for p in pixels]
    ys = [p[2] for p in pixels]
    (minimum(xs),minimum(ys),maximum(xs),maximum(ys))
end
box_text(box) = box === nothing ? "none" : join(box," ")
ranked(counts) = sort(collect(counts); by=item -> (-last(item),first(item)))
is_integer(word) = occursin(r"^-?[0-9]+$", word)
integers(words) = parse.(Int, words)
function parse_path(words)
    commands = PathCommand[]
    index = 1
    while index <= length(words)
        length(words[index]) == 1 || return nothing
        letter = words[index][1]
        upper = uppercase(letter)
        haskey(PATH_ARITY,upper) || return nothing
        count = PATH_ARITY[upper]
        index+count <= length(words) || return nothing
        values = words[index+1:index+count]
        all(is_integer,values) || return nothing
        starts = isempty(commands) || uppercase(commands[end].letter) == 'Z'
        starts && upper != 'M' && return nothing
        push!(commands,PathCommand(letter,integers(values)))
        index += count+1
    end
    isempty(commands) ? nothing : commands
end
function valid_form(keyword, args)
    if haskey(FIXED_FORMS,keyword)
        count,first_integer = FIXED_FORMS[keyword]
        return length(args) == count && all(is_integer,args[first_integer:end])
    elseif keyword == "TEXT"
        return length(args) == 5 && all(is_integer,args[2:3])
    elseif keyword in ("POLYLINE","POLYGON","FILLPOLYGON")
        return length(args) >= 2 && all(is_integer,args[2:end]) && length(args) == 2+2 * parse(Int,args[2])
    end
    length(args) >= 2 && is_integer(args[2]) && parse_path(args[3:end]) !== nothing
end
mutable struct Renderer
    scene::Scene
    styles::Styles
    font::Font
    screen::Rect
    layers::Vector{Layer}
    executions::Vector{Execution}
    state::DrawingState
end
function Renderer(scene,styles,font)
    screen = (0,0,scene.width-1,scene.height-1)
    Renderer(scene,styles,font,screen,Layer[],Execution[],DrawingState(screen))
end
function check_command(renderer, command)
    key,args = command.keyword,command.arguments
    key in COMMANDS || return "unknown_command"
    valid_form(key,args) || return "bad_arguments"
    key in PEN_COMMANDS && !haskey(renderer.styles.pens,args[1]) && return "unknown_style"
    key in BRUSH_COMMANDS && !haskey(renderer.styles.brushes,args[1]) && return "unknown_style"
    if key == "USE"
        haskey(renderer.scene.symbols,args[1]) && renderer.scene.symbols[args[1]].end_line < command.line || return "unknown_symbol"
    end
    key == "TEXT" && !all(ch -> ch == '_' || haskey(renderer.font.glyphs,ch),args[5]) && return "unknown_glyph"
    key == "RESTORE" && isempty(renderer.state.stack) && return "stack_empty"
    valid = true
    if key in ("CIRCLE","FILLCIRCLE")
        valid = parse(Int,args[4]) >= 1
    elseif key in ("ELLIPSE","FILLELLIPSE")
        valid = parse(Int,args[4]) >= 1 && parse(Int,args[5]) >= 1
    elseif key in ("POLYLINE","POLYGON","FILLPOLYGON")
        valid = parse(Int,args[2]) >= (key == "POLYLINE" ? 2 : 3)
    elseif key in ("PATH","FILLPATH")
        valid = 1 <= parse(Int,args[2]) <= 32
    elseif key == "FLOOD"
        valid = rect_contains(renderer.state.clip,transform(renderer.state,integers(args[2:3])...))
    elseif key == "TEXT"
        valid = args[4] in ("left","center","right")
    elseif key == "SCALE"
        valid = parse(Int,args[1]) != 0 && parse(Int,args[2]) != 0
    elseif key == "CLIP"
        valid = !rect_empty(rect_intersection(device_rect(renderer.state,integers(args)...),renderer.state.clip))
    end
    valid ? nothing : "bad_value"
end
function apply_state!(renderer,command)
    state,key,args = renderer.state,command.keyword,command.arguments
    if key == "TRANSLATE"
        translate_state!(state,integers(args)...)
    elseif key == "SCALE"
        sx,sy = integers(args)
        a,b,c,d,e,f = state.matrix
        state.matrix = (a*sx,b*sy,c*sx,d*sy,e,f)
    elseif key == "ROTATE"
        for _ in 1:mod(parse(Int,args[1]),4)
            a,b,c,d,e,f = state.matrix
            state.matrix = (b,-a,d,-c,e,f)
        end
    elseif key == "SAVE"
        push!(state.stack,(state.matrix,state.clip))
    elseif key == "RESTORE"
        state.matrix,state.clip = pop!(state.stack)
    elseif key == "CLIP"
        state.clip = rect_intersection(device_rect(state,integers(args)...),state.clip)
    elseif key == "NOCLIP"
        state.clip = renderer.screen
    else
        saved = snapshot(state)
        translate_state!(state,integers(args[2:3])...)
        execute_body!(renderer,renderer.scene.symbols[args[1]].body)
        rollback!(state,saved)
    end
end
function execute_body!(renderer,body)
    for item in body
        if item isa Repetition
            saved = snapshot(renderer.state)
            for k in 0:item.count-1
                rollback!(renderer.state,saved)
                translate_state!(renderer.state,k*item.dx,k*item.dy)
                execute_body!(renderer,item.body)
            end
            rollback!(renderer.state,saved)
        else
            execute_command!(renderer,item)
        end
    end
end
function execute_command!(renderer,command)
    execution = Execution(sequence=length(renderer.executions)+1,layer=length(renderer.layers),command=command)
    push!(renderer.executions,execution)
    reason = check_command(renderer,command)
    if reason !== nothing
        execution.kind,execution.error = :error,reason
    elseif command.keyword in STATE_COMMANDS
        apply_state!(renderer,command)
    else
        pixels = draw_command!(renderer,command)
        execution.kind,execution.pixels,execution.box = :drawing,length(pixels),bounding_box(pixels)
    end
end
function run_renderer!(renderer)
    for block in renderer.scene.layers
        push!(renderer.layers,Layer(renderer.scene.width,renderer.scene.height,block.opacity,block.mode))
        renderer.state = DrawingState(renderer.screen)
        execute_body!(renderer,block.body)
    end
end
function segment_pairs(points,closed)
    pairs = Tuple{Point,Point}[(points[i],points[i+1]) for i in 1:length(points)-1]
    closed && push!(pairs,(points[end],points[1]))
    pairs
end
function expanded(renderer,points,width)
    pixels = Set{Point}()
    for (x,y) in points, point in expand_square(x,y,width)
        rect_contains(renderer.state.clip,point) && push!(pixels,point)
    end
    pixels
end
function stroke(renderer,pen,segments)
    points = Point[]
    for (first,last) in segments
        clipped = clip_segment(first,last,renderer.state.clip)
        clipped !== nothing && append!(points,bresenham(clipped...))
    end
    if pen.off > 0
        points = [point for (i,point) in enumerate(points) if mod(i-1,pen.on+pen.off) < pen.on]
    end
    expanded(renderer,points,pen.width)
end
function vertices(renderer,args)
    values = integers(args[2:end])
    [transform(renderer.state,values[i],values[i+1]) for i in 1:2:length(values)]
end
function shape(renderer,key,values)
    center = transform(renderer.state,values[1:2]...)
    if key in ("CIRCLE","FILLCIRCLE")
        rx,ry = device_radii(renderer.state,values[3],values[3])
        rx == ry && return (center,circle_points(rx))
    else
        rx,ry = device_radii(renderer.state,values[3],values[4])
    end
    center,ellipse_points(rx,ry)
end
function build_subpaths(renderer,commands,segments)
    subpaths = Subpath[]
    current = start = (0,0)
    for command in commands
        kind = uppercase(command.letter)
        if kind == 'Z'
            subpaths[end].closed = true
            current = start
            continue
        end
        ox,oy = islowercase(command.letter) ? current : (0,0)
        values = command.values
        if kind == 'H'
            points = [(values[1]+ox,current[2])]
        elseif kind == 'V'
            points = [(current[1],values[1]+oy)]
        else
            points = [(values[i]+ox,values[i+1]+oy) for i in 1:2:length(values)]
        end
        device = [transform(renderer.state,point...) for point in points]
        if kind == 'M'
            push!(subpaths,Subpath(points=[device[1]]))
            start = points[1]
        elseif kind in ('L','H','V')
            push!(subpaths[end].points,device[1])
        else
            controls = vcat([subpaths[end].points[end]],device)
            append!(subpaths[end].points,bezier_points(controls,segments)[2:end])
        end
        current = points[end]
    end
    subpaths
end
function pen_coverage(renderer,key,pen,args)
    if key in ("CIRCLE","ELLIPSE")
        (cx,cy),points = shape(renderer,key,integers(args))
        return expanded(renderer,[(cx+dx,cy+dy) for (dx,dy) in points],pen.width)
    elseif key == "LINE"
        values = integers(args)
        segments = [(transform(renderer.state,values[1:2]...),transform(renderer.state,values[3:4]...))]
    elseif key == "RECT"
        x0,y0,x1,y1 = device_rect(renderer.state,integers(args)...)
        segments = segment_pairs([(x0,y0),(x1,y0),(x1,y1),(x0,y1)],true)
    elseif key in ("POLYLINE","POLYGON")
        segments = segment_pairs(vertices(renderer,args),key == "POLYGON")
    else
        subpaths = build_subpaths(renderer,parse_path(args[2:end]),parse(Int,args[1]))
        segments = Tuple{Point,Point}[]
        for path in subpaths
            append!(segments,segment_pairs(path.points,path.closed))
        end
    end
    stroke(renderer,pen,segments)
end
function text_coverage(renderer,x,y,alignment,text)
    advance = renderer.font.width+1
    extent = length(text)*advance-1
    left = alignment == "left" ? x : alignment == "center" ? x-fld(extent,2) : x-extent+1
    pixels = Set{Point}()
    for (i,ch) in enumerate(text)
        ch == '_' && continue
        origin = left+(i-1)*advance
        for (column,row) in renderer.font.glyphs[ch]
            x0,y0 = transform(renderer.state,origin+column,y+row)
            x1,y1 = transform(renderer.state,origin+column+1,y+row+1)
            for py in min(y0,y1):max(y0,y1)-1, px in min(x0,x1):max(x0,x1)-1
                point = (px,py)
                rect_contains(renderer.state.clip,point) && push!(pixels,point)
            end
        end
    end
    pixels
end
function brush_coverage(renderer,key,brush,args)
    clip = renderer.state.clip
    if key == "FILLRECT"
        return rect_pixels(rect_intersection(device_rect(renderer.state,integers(args)...),clip))
    elseif key in ("FILLCIRCLE","FILLELLIPSE")
        center,points = shape(renderer,key,integers(args))
        return fill_shape(center,points,clip)
    elseif key == "FILLPOLYGON"
        return fill_polygons([clip_polygon(vertices(renderer,args),clip)],brush.rule,clip)
    elseif key == "FILLPATH"
        subpaths = build_subpaths(renderer,parse_path(args[2:end]),parse(Int,args[1]))
        return fill_polygons([clip_polygon(path.points,clip) for path in subpaths],brush.rule,clip)
    elseif key == "FLOOD"
        return flood_fill(renderer.layers[end],transform(renderer.state,integers(args)...),clip)
    end
    text_coverage(renderer,parse(Int,args[1]),parse(Int,args[2]),args[3],args[4])
end
function gradient_color(first,second,axis,box,x,y)
    offset,size = axis == "x" ? (x-box[1],box[3]-box[1]) : (y-box[2],box[4]-box[2])
    size == 0 ? first : ntuple(c -> first[c]+round_ratio((second[c]-first[c])*offset,size),4)
end
function draw_command!(renderer,command)
    key,args,layer = command.keyword,command.arguments,renderer.layers[end]
    if key == "ERASE"
        rect = rect_intersection(device_rect(renderer.state,integers(args)...),renderer.state.clip)
        return Set{Point}((x,y) for y in rect[2]:rect[4] for x in rect[1]:rect[3] if erase!(layer,x,y))
    elseif key in PEN_COMMANDS
        pen = renderer.styles.pens[args[1]]
        pixels = pen_coverage(renderer,key,pen,args[2:end])
        color = renderer.styles.colors[pen.color]
        for (x,y) in pixels
            paint!(layer,x,y,color,command.line)
        end
    else
        brush = renderer.styles.brushes[args[1]]
        pixels = brush_coverage(renderer,key,brush,args[2:end])
        first = renderer.styles.colors[brush.colors[1]]
        box = bounding_box(pixels)
        for (x,y) in pixels
            color = brush.axis === nothing ? first : gradient_color(first,renderer.styles.colors[brush.colors[2]],brush.axis,box,x,y)
            paint!(layer,x,y,color,command.line)
        end
    end
    pixels
end
function read_styles(lines)
    styles = Styles()
    for line in lines
        (isempty(line) || startswith(line,"#")) && continue
        fields = String.(split(line))
        kind,name,values = fields[1],fields[2],fields[3:end]
        if kind == "color"
            styles.colors[name] = Tuple(integers(values))
        elseif kind == "pen"
            styles.pens[name] = Pen(parse(Int,values[1]),values[2],parse(Int,values[3]),parse(Int,values[4]))
        elseif kind == "brush"
            styles.brushes[name] = Brush([values[1]],nothing,values[2])
        else
            styles.brushes[name] = Brush(values[1:2],values[3],values[4])
        end
    end
    styles
end
function read_font(lines)
    header = split(lines[1])
    width,height = parse(Int,header[2]),parse(Int,header[3])
    glyphs = Dict{Char,Vector{Point}}()
    index = 2
    while index <= length(lines)
        ch = split(lines[index])[2][1]
        dots = Point[]
        for row in 0:height-1
            for (column,mark) in enumerate(lines[index+row+1])
                mark == '#' && push!(dots,(column-1,row))
            end
        end
        glyphs[ch] = dots
        index += height+1
    end
    Font(width,height,glyphs)
end
function read_scene(lines)
    scene = Scene()
    block = nothing
    bodies = Vector{Item}[]
    for (number,line) in enumerate(lines)
        words = String.(split(line))
        (isempty(words) || startswith(words[1],"#")) && continue
        key,args = words[1],words[2:end]
        if key == "CANVAS"
            scene.width,scene.height = integers(args[1:2])
            scene.background = args[3]
        elseif key == "LAYER"
            block = Block(name=args[1],opacity=parse(Int,args[2]),mode=args[3])
            push!(scene.layers,block)
            bodies = [block.body]
        elseif key == "SYMBOL"
            block = Block(name=args[1])
            scene.symbols[block.name] = block
            bodies = [block.body]
        elseif key == "END"
            block.end_line = number
            empty!(bodies)
        elseif key == "REPEAT"
            count,dx,dy = integers(args)
            repetition = Repetition(count,dx,dy,Item[])
            push!(bodies[end],repetition)
            push!(bodies,repetition.body)
        elseif key == "ENDREPEAT"
            pop!(bodies)
        else
            push!(bodies[end],Command(number,key,args))
        end
    end
    scene
end
function read_probes(lines)
    probes = Probe[]
    for line in lines[2:parse(Int,lines[1])+1]
        fields = String.(split(line))
        push!(probes,Probe(fields[1],integers(fields[2:end])))
    end
    probes
end
function command_lines(executions)
    lines = String[]
    for e in executions
        head = "cmd $(e.sequence) line $(e.command.line) $(e.command.keyword)"
        suffix = e.kind == :error ? "error $(e.error)" : e.kind == :drawing ? "pixels $(e.pixels) box $(box_text(e.box))" : "ok"
        push!(lines,"$head $suffix")
    end
    lines
end
function visible_counts(layers,width,height)
    counts = zeros(Int,length(layers))
    for y in 0:height-1, x in 0:width-1
        covered = false
        for i in length(layers):-1:1
            alpha = alpha_at(layers[i],x,y)
            alpha > 0 && !covered && (counts[i] += 1)
            alpha == 255 && (covered = true)
        end
    end
    counts
end
function layer_lines(renderer)
    scene,layers,executions = renderer.scene,renderer.layers,renderer.executions
    visible = visible_counts(layers,scene.width,scene.height)
    lines = ["layers $(length(layers))"]
    for (i,(block,layer)) in enumerate(zip(scene.layers,layers))
        own = filter(e -> e.layer == i,executions)
        errors = count(e -> e.kind == :error,own)
        painted = Point[]
        counts = Dict{Color,Int}()
        for y in 0:layer.height-1, x in 0:layer.width-1
            color = color_at(layer,x,y)
            if color !== nothing
                push!(painted,(x,y))
                counts[color] = get(counts,color,0)+1
            end
        end
        push!(lines,"layer $i $(block.name) opacity $(block.opacity) mode $(block.mode) commands $(length(own)) errors $errors pixels $(length(painted)) box $(box_text(bounding_box(painted))) visible $(visible[i]) colors $(length(counts))")
        for (color,n) in ranked(counts)[1:min(5,length(counts))]
            push!(lines,"color $(join(color," ")) pixels $n")
        end
    end
    lines
end
function symbol_uses(scene,executions)
    uses = Dict(name=>0 for name in keys(scene.symbols))
    for e in executions
        if e.kind == :state && e.command.keyword == "USE"
            uses[e.command.arguments[1]] += 1
        end
    end
    uses
end
function unused_items(scene,styles,executions)
    pens,brushes = Set{String}(),Set{String}()
    for e in executions
        e.kind == :drawing || continue
        key,args = e.command.keyword,e.command.arguments
        key in PEN_COMMANDS && push!(pens,args[1])
        key in BRUSH_COMMANDS && push!(brushes,args[1])
    end
    colors = Set([scene.background])
    for name in pens
        push!(colors,styles.pens[name].color)
    end
    for name in brushes
        union!(colors,styles.brushes[name].colors)
    end
    uses = symbol_uses(scene,executions)
    unused = Tuple{String,String}[]
    for (kind,table,used) in (("color",styles.colors,colors),("pen",styles.pens,pens),("brush",styles.brushes,brushes))
        for name in sort!(collect(keys(table)))
            !(name in used) && push!(unused,(kind,name))
        end
    end
    for name in sort!(collect(keys(scene.symbols)))
        uses[name] == 0 && push!(unused,("symbol",name))
    end
    unused
end
function color_counts(image)
    counts = Dict{RGB,Int}()
    for color in image
        counts[color] = get(counts,color,0)+1
    end
    counts
end
function summary_lines(renderer,image)
    scene,styles,executions = renderer.scene,renderer.styles,renderer.executions
    background = styles.colors[scene.background]
    lines = ["canvas $(scene.width) $(scene.height)","background $(join(background[1:3]," "))","layers $(length(scene.layers))","symbols $(length(scene.symbols))","commands $(length(executions))",
        "drawing $(count(e -> e.kind == :drawing,executions))","state $(count(e -> e.kind == :state,executions))","errors $(count(e -> e.kind == :error,executions))"]
    for name in ERRORS
        push!(lines,"error $name $(count(e -> e.error == name,executions))")
    end
    painted = erased = 0
    tallies = Dict{String,Vector{Int}}()
    for e in executions
        key = e.command.keyword
        tally = get!(tallies,key,[0,0,0])
        tally[1] += 1
        if e.kind == :error
            tally[2] += 1
        elseif e.kind == :drawing
            tally[3] += e.pixels
            if key == "ERASE"
                erased += e.pixels
            else
                painted += e.pixels
            end
        end
    end
    push!(lines,"painted $painted","erased $erased")
    counts = color_counts(image)
    push!(lines,"colors $(length(counts))")
    for (rank,(color,n)) in enumerate(ranked(counts)[1:min(8,length(counts))])
        push!(lines,"top $rank $(join(color," ")) pixels $n")
    end
    uses = symbol_uses(scene,executions)
    for name in sort!(collect(keys(scene.symbols)))
        push!(lines,"symbol $name uses $(uses[name])")
    end
    for key in sort!(collect(keys(tallies)))
        executed,errors,pixels = tallies[key]
        push!(lines,"keyword $key executed $executed errors $errors pixels $pixels")
    end
    unused = unused_items(scene,styles,executions)
    push!(lines,"unused $(length(unused))")
    for (kind,name) in unused
        push!(lines,"unused $kind $name")
    end
    lines
end
function probe_lines(probes,image,layers)
    lines = String[]
    for (number,probe) in enumerate(probes)
        if probe.kind == "point"
            x,y = probe.values
            rgb = image[y+1,x+1]
            stack = ["$i:$(layer.lines[y+1,x+1])" for (i,layer) in enumerate(layers) if alpha_at(layer,x,y) > 0]
            overlap = isempty(stack) ? "none" : join(stack," ")
            push!(lines,"point $number $x $y rgb $(join(rgb," ")) layers $(length(stack)) stack $overlap")
        else
            x0,y0,x1,y1 = probe.values
            totals,cover,colors = zeros(Int,3),zeros(Int,length(layers)),Set{RGB}()
            for y in y0:y1, x in x0:x1
                color = image[y+1,x+1]
                push!(colors,color)
                for c in 1:3
                    totals[c] += color[c]
                end
                for (i,layer) in enumerate(layers)
                    cover[i] += alpha_at(layer,x,y) > 0
                end
            end
            n = (x1-x0+1)*(y1-y0+1)
            means = join(fld.(totals,n)," ")
            push!(lines,"area $number $x0 $y0 $x1 $y1 pixels $n mean $means colors $(length(colors)) cover $(join(cover," "))")
        end
    end
    lines
end
function main()
    styles = read_styles(readlines("input/styles.txt"))
    font = read_font(readlines("input/font.txt"))
    scene = read_scene(readlines("input/scene.txt"))
    probes = read_probes(readlines("input/probes.txt"))
    renderer = Renderer(scene,styles,font)
    run_renderer!(renderer)
    image = composite(renderer.layers,styles.colors[scene.background],scene.width,scene.height)
    mkpath("output")
    write_ppm("output/image.ppm",image)
    write_preview("output/preview.txt",image)
    names = ["commands.txt","layers.txt","summary.txt","probes.txt"]
    reports = [command_lines(renderer.executions),layer_lines(renderer),summary_lines(renderer,image),probe_lines(probes,image,renderer.layers)]
    for (name,lines) in zip(names,reports)
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
