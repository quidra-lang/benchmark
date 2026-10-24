const MODE_NAMES = ["IRM","LNM","DECCKM","DECSCNM","DECOM","DECAWM","DECTCEM","DECKPAM","BRACKETED"]
const FLAG_NAMES = ["bold","dim","italic","underline","blink","reverse","hidden","strike"]
const ANSI_MODES = Dict(4=>"IRM",20=>"LNM")
const DEC_MODES = Dict(1=>"DECCKM",5=>"DECSCNM",6=>"DECOM",7=>"DECAWM",25=>"DECTCEM",2004=>"BRACKETED")
const GROUND, ESCAPE, ESC_INTERMEDIATE, CSI_ENTRY, CSI_PARAM, CSI_INTERMEDIATE, CSI_IGNORE, OSC_STRING = 0:7
struct Attributes
    flags::Int
    fg::String
    bg::String
end
Attributes() = Attributes(0,"","")
Base.:(==)(a::Attributes,b::Attributes) = a.flags == b.flags && a.fg == b.fg && a.bg == b.bg
struct Cell
    char::Char
    attr::Attributes
end
const BLANK = Cell(' ',Attributes())
struct SavedCursor
    row::Int
    column::Int
    attr::Attributes
    origin::Bool
    g0::Bool
    g1::Bool
    gl::Bool
end
Base.@kwdef mutable struct Terminal
    width::Int
    height::Int
    row::Int = 1
    column::Int = 1
    top::Int = 1
    bottom::Int = 1
    display::Int = 1
    shape::Int = 1
    pending::Bool = false
    attr::Attributes = Attributes()
    g0::Bool = false
    g1::Bool = false
    gl::Bool = false
    modes::Dict{String,Bool} = Dict{String,Bool}()
    screens::Vector{Vector{Vector{Cell}}} = Vector{Vector{Cell}}[]
    saved::Vector{Union{Nothing,SavedCursor}} = Union{Nothing,SavedCursor}[nothing,nothing]
    tabs::Set{Int} = Set{Int}()
    scrollback::Vector{String} = String[]
    title::Union{Nothing,String} = nothing
    lastchar::Union{Nothing,Char} = nothing
    state::Int = GROUND
    marker::String = ""
    parameters::String = ""
    intermediates::String = ""
    osc::String = ""
    bytes::Int = 0
    printed::Int = 0
    sequences::Int = 0
    bells::Int = 0
    replies::Int = 0
    dumps::Int = 0
    ignored::Vector{Int} = zeros(Int,4)
end
initial(name::String) = name in ("DECAWM","DECTCEM")
blankrow(t::Terminal) = fill(BLANK,t.width)
function clearscreen!(t::Terminal,display::Int)
    t.screens[display] = [blankrow(t) for _ in 1:t.height]
end
function clearsequence!(t::Terminal)
    t.marker,t.parameters,t.intermediates,t.osc = "","","",""
end
function reset!(t::Terminal)
    t.screens = [[blankrow(t) for _ in 1:t.height] for _ in 1:2]
    t.row,t.column,t.top,t.bottom,t.display,t.shape = 1,1,1,t.height,1,1
    t.pending = false
    t.attr = Attributes()
    t.g0,t.g1,t.gl = false,false,false
    t.modes = Dict(name=>initial(name) for name in MODE_NAMES)
    t.saved = Union{Nothing,SavedCursor}[nothing,nothing]
    t.tabs = Set(9:8:t.width)
    empty!(t.scrollback)
    t.title,t.lastchar = nothing,nothing
    t.state = GROUND
    clearsequence!(t)
end
rowtext(row::Vector{Cell}) = replace(join(cell.char for cell in row),r" +$"=>"")
function scrollup!(t::Terminal,top::Int,bottom::Int; history::Bool=false)
    rows = t.screens[t.display]
    removed = rows[top]
    for r in top:bottom-1
        rows[r] = rows[r+1]
    end
    rows[bottom] = blankrow(t)
    if history && t.display == 1 && top == 1
        push!(t.scrollback,rowtext(removed))
        length(t.scrollback) > 100 && popfirst!(t.scrollback)
    end
end
function scrolldown!(t::Terminal,top::Int,bottom::Int)
    rows = t.screens[t.display]
    for r in bottom:-1:top+1
        rows[r] = rows[r-1]
    end
    rows[top] = blankrow(t)
end
function linefeed!(t::Terminal)
    if t.row == t.bottom
        scrollup!(t,t.top,t.bottom; history=true)
    elseif t.row < t.height
        t.row += 1
    end
end
function reversefeed!(t::Terminal)
    if t.row == t.top
        scrolldown!(t,t.top,t.bottom)
    elseif t.row > 1
        t.row -= 1
    end
end
function tab!(t::Terminal,reverse::Bool=false)
    if reverse
        earlier = [stop for stop in t.tabs if stop < t.column]
        t.column = isempty(earlier) ? 1 : maximum(earlier)
    else
        later = [stop for stop in t.tabs if stop > t.column]
        t.column = isempty(later) ? t.width : minimum(later)
    end
end
address(t::Terminal,v::Int) = t.modes["DECOM"] ? min(t.top+v-1,t.bottom) : min(v,t.height)
function home!(t::Terminal)
    t.row,t.column = address(t,1),1
end
function savecursor!(t::Terminal)
    t.saved[t.display] = SavedCursor(t.row,t.column,t.attr,t.modes["DECOM"],t.g0,t.g1,t.gl)
end
function restorecursor!(t::Terminal)
    t.pending = false
    saved = t.saved[t.display]
    saved === nothing && (saved = SavedCursor(1,1,Attributes(),false,false,false,false))
    t.row,t.column,t.attr = saved.row,saved.column,saved.attr
    t.modes["DECOM"],t.g0,t.g1,t.gl = saved.origin,saved.g0,saved.g1,saved.gl
end
function insertcells!(t::Terminal,n::Int)
    row = t.screens[t.display][t.row]
    for c in t.width:-1:t.column+n
        row[c] = row[c-n]
    end
    for c in t.column:t.column+n-1
        row[c] = BLANK
    end
end
function deletecells!(t::Terminal,n::Int)
    row = t.screens[t.display][t.row]
    for c in t.column:t.width-n
        row[c] = row[c+n]
    end
    for c in t.width-n+1:t.width
        row[c] = BLANK
    end
end
function writechar!(t::Terminal,c::Char)
    t.printed += 1
    t.lastchar = c
    if t.pending
        t.pending = false
        t.column = 1
        linefeed!(t)
    end
    t.modes["IRM"] && insertcells!(t,1)
    t.screens[t.display][t.row][t.column] = Cell(c,t.attr)
    if t.column < t.width
        t.column += 1
    elseif t.modes["DECAWM"]
        t.pending = true
    end
end
function printchar!(t::Terminal,c::Char)
    graphics = t.gl ? t.g1 : t.g0
    if graphics
        replacement = Dict('`'=>'*','a'=>'#','j'=>'+','k'=>'+','l'=>'+','m'=>'+','n'=>'+',
                           't'=>'+','u'=>'+','v'=>'+','w'=>'+','q'=>'-','x'=>'|','~'=>'o')
        c = get(replacement,c,c)
    end
    writechar!(t,c)
end
function control!(t::Terminal,b::Int)
    if b == 7
        t.bells += 1
    elseif b == 8
        t.pending = false
        t.column = max(t.column-1,1)
    elseif b == 9
        t.pending = false
        tab!(t)
    elseif b in (10,11,12)
        t.pending = false
        linefeed!(t)
        t.modes["LNM"] && (t.column = 1)
    elseif b == 13
        t.pending = false
        t.column = 1
    elseif b == 14
        t.gl = true
    elseif b == 15
        t.gl = false
    end
end
function executeesc!(t::Terminal,key::String)
    if key == "7"
        savecursor!(t)
    elseif key == "8"
        restorecursor!(t)
    elseif key == "D"
        t.pending = false
        linefeed!(t)
    elseif key == "E"
        t.pending = false
        t.column = 1
        linefeed!(t)
    elseif key == "M"
        t.pending = false
        reversefeed!(t)
    elseif key == "H"
        push!(t.tabs,t.column)
    elseif key == "c"
        reset!(t)
    elseif key in ("=",">")
        t.modes["DECKPAM"] = key == "="
    elseif key == "\\"
        nothing
    elseif key in ("(0","(B")
        t.g0 = key == "(0"
    elseif key in (")0",")B")
        t.g1 = key == ")0"
    elseif key == "#8"
        t.pending = false
        t.screens[t.display] = [fill(Cell('E',Attributes()),t.width) for _ in 1:t.height]
        t.top,t.bottom,t.row,t.column = 1,t.height,1,1
        t.modes["DECOM"] = false
    else
        t.ignored[1] += 1
        return
    end
    t.sequences += 1
end
function executeosc!(t::Terminal)
    if startswith(t.osc,"0;") || startswith(t.osc,"2;")
        t.title = t.osc[3:end]
        t.sequences += 1
    else
        t.ignored[1] += 1
    end
end
function palette(number::Int)
    names = ["black","red","green","yellow","blue","magenta","cyan","white"]
    number < 8 && return names[number+1]
    number < 16 && return "bright-"*names[number-7]
    return string(number)
end
function sgr!(t::Terminal,params::Vector{Int})
    values = isempty(params) ? [0] : params
    flags,fg,bg = t.attr.flags,t.attr.fg,t.attr.bg
    on = Dict(1=>0,2=>1,3=>2,4=>3,5=>4,7=>5,8=>6,9=>7)
    off = Dict(23=>2,24=>3,25=>4,27=>5,28=>6,29=>7)
    index = 1
    while index <= length(values)
        v = values[index]
        if v == 0
            flags,fg,bg = 0,"",""
        elseif haskey(on,v)
            flags |= 1 << on[v]
        elseif v == 22
            flags &= ~3
        elseif haskey(off,v)
            flags &= ~(1 << off[v])
        elseif 30 <= v <= 37
            fg = palette(v-30)
        elseif 90 <= v <= 97
            fg = palette(v-82)
        elseif 40 <= v <= 47
            bg = palette(v-40)
        elseif 100 <= v <= 107
            bg = palette(v-92)
        elseif v == 39
            fg = ""
        elseif v == 49
            bg = ""
        elseif v in (38,48)
            color = ""
            if index+2 <= length(values) && values[index+1] == 5 && values[index+2] <= 255
                color = palette(values[index+2])
                index += 2
            elseif index+4 <= length(values) && values[index+1] == 2 && maximum(values[index+2:index+4]) <= 255
                color = "#"*join(lpad(string(value; base=16),2,'0') for value in values[index+2:index+4])
                index += 4
            else
                return false
            end
            if v == 38
                fg = color
            else
                bg = color
            end
        else
            return false
        end
        index += 1
    end
    t.attr = Attributes(flags,fg,bg)
    return true
end
function setmodes!(t::Terminal,params::Vector{Int},dec::Bool,enabled::Bool)
    values = isempty(params) ? [0] : params
    allowed = dec ? (1,5,6,7,25,47,1047,1048,1049,2004) : (4,20)
    all(v -> v in allowed,values) || return false
    for v in values
        if !dec
            t.modes[ANSI_MODES[v]] = enabled
        elseif haskey(DEC_MODES,v)
            (v == 6 || v == 7 && !enabled) && (t.pending = false)
            t.modes[DEC_MODES[v]] = enabled
            v == 6 && home!(t)
        elseif v == 1048
            enabled ? savecursor!(t) : restorecursor!(t)
        else
            t.pending = false
            if enabled && t.display == 1
                v == 1049 && savecursor!(t)
                t.display = 2
                v == 1049 && clearscreen!(t,2)
            elseif !enabled && t.display == 2
                v == 1047 && clearscreen!(t,2)
                t.display = 1
                v == 1049 && restorecursor!(t)
            end
        end
    end
    return true
end
function erase!(t::Terminal,row::Int,first::Int,last::Int)
    for c in first:last
        t.screens[t.display][row][c] = BLANK
    end
end
function moveup!(t::Terminal,n::Int)
    limit = t.row >= t.top ? t.top : 1
    t.row = max(t.row-n,limit)
end
function movedown!(t::Terminal,n::Int)
    limit = t.row <= t.bottom ? t.bottom : t.height
    t.row = min(t.row+n,limit)
end
function reply!(t::Terminal,text::String)
    t.replies += 1
    println("REPLY ",text)
end
modestate(enabled::Bool) = enabled ? 1 : 2
# 0 is executed; 1 is unsupported; 4 is invalid.
function csi!(t::Terminal,key::String,params::Vector{Int})
    p1 = isempty(params) ? 0 : params[1]
    p2 = length(params) < 2 ? 0 : params[2]
    n = max(p1,1)
    conditions = Dict("J"=>(0,1,2,3),"K"=>(0,1,2),"g"=>(0,3)," q"=>(0,1,2,3,4,5,6),
                      "n"=>(5,6),"?n"=>(6,),"c"=>(0,),">c"=>(0,),"t"=>(18,))
    haskey(conditions,key) && !(p1 in conditions[key]) && return 1
    length(key) == 1 && first(key) in "ABCDEFGHIJKLMPSTXZ`adef@" && (t.pending = false)
    if key == "A"
        moveup!(t,n)
    elseif key in ("B","e")
        movedown!(t,n)
    elseif key in ("C","a")
        t.column = min(t.column+n,t.width)
    elseif key == "D"
        t.column = max(t.column-n,1)
    elseif key == "E"
        movedown!(t,n)
        t.column = 1
    elseif key == "F"
        moveup!(t,n)
        t.column = 1
    elseif key in ("G","`")
        t.column = min(n,t.width)
    elseif key in ("H","f")
        t.row,t.column = address(t,n),min(max(p2,1),t.width)
    elseif key == "d"
        t.row = address(t,n)
    elseif key in ("I","Z")
        for _ in 1:n
            tab!(t,key == "Z")
        end
    elseif key == "J"
        if p1 == 0
            erase!(t,t.row,t.column,t.width)
            for r in t.row+1:t.height
                erase!(t,r,1,t.width)
            end
        elseif p1 == 1
            for r in 1:t.row-1
                erase!(t,r,1,t.width)
            end
            erase!(t,t.row,1,t.column)
        elseif p1 == 2
            clearscreen!(t,t.display)
        else
            empty!(t.scrollback)
        end
    elseif key == "K"
        firstcol = p1 in (1,2) ? 1 : t.column
        lastcol = p1 == 1 ? t.column : t.width
        erase!(t,t.row,firstcol,lastcol)
    elseif key == "X"
        erase!(t,t.row,t.column,min(t.column+n-1,t.width))
    elseif key == "@"
        insertcells!(t,min(n,t.width-t.column+1))
    elseif key == "P"
        deletecells!(t,min(n,t.width-t.column+1))
    elseif key in ("L","M")
        if t.top <= t.row <= t.bottom
            for _ in 1:min(n,t.bottom-t.row+1)
                key == "L" ? scrolldown!(t,t.row,t.bottom) : scrollup!(t,t.row,t.bottom)
            end
            t.column = 1
        end
    elseif key in ("S","T")
        for _ in 1:min(n,t.bottom-t.top+1)
            key == "S" ? scrollup!(t,t.top,t.bottom; history=true) : scrolldown!(t,t.top,t.bottom)
        end
    elseif key == "b"
        if t.lastchar !== nothing
            c = t.lastchar
            for _ in 1:n
                writechar!(t,c)
            end
        end
    elseif key == "g"
        p1 == 0 ? delete!(t.tabs,t.column) : empty!(t.tabs)
    elseif key == "m"
        sgr!(t,params) || return 1
    elseif key in ("h","l","?h","?l")
        setmodes!(t,params,startswith(key,"?"),endswith(key,"h")) || return 1
    elseif key == " q"
        t.shape = n
    elseif key == "r"
        bottom = min(p2 == 0 ? t.height : p2,t.height)
        n < bottom || return 4
        t.pending = false
        t.top,t.bottom = n,bottom
        home!(t)
    elseif key == "s"
        savecursor!(t)
    elseif key == "u"
        restorecursor!(t)
    elseif key == "!p"
        t.pending = false
        for name in ("IRM","DECCKM","DECOM","DECAWM","DECTCEM","DECKPAM")
            t.modes[name] = initial(name)
        end
        t.top,t.bottom = 1,t.height
        t.attr = Attributes()
        t.g0,t.g1,t.gl = false,false,false
        t.saved[t.display] = nothing
    elseif key in ("n","?n")
        r = t.modes["DECOM"] ? max(t.row-t.top+1,1) : t.row
        text = key == "?n" ? "^[[?$r;$(t.column);1R" : p1 == 5 ? "^[[0n" : "^[[$r;$(t.column)R"
        reply!(t,text)
    elseif key == "c"
        reply!(t,"^[[?1;2c")
    elseif key == ">c"
        reply!(t,"^[[>0;95;0c")
    elseif key == "t"
        reply!(t,"^[[8;$(t.height);$(t.width)t")
    elseif key in ("\$p","?\$p")
        state,prefix = 0,""
        if key == "\$p"
            haskey(ANSI_MODES,p1) && (state = modestate(t.modes[ANSI_MODES[p1]]))
        else
            prefix = "?"
            if haskey(DEC_MODES,p1)
                state = modestate(t.modes[DEC_MODES[p1]])
            elseif p1 in (47,1047,1049)
                state = modestate(t.display == 2)
            end
        end
        reply!(t,"^[[$prefix$p1;$state\$y")
    else
        return 1
    end
    return 0
end
function executecsi!(t::Terminal,finalchar::Char)
    fields = isempty(t.parameters) ? SubString{String}[] : split(t.parameters,';'; keepempty=true)
    if length(fields) > 16
        t.ignored[4] += 1
        return
    end
    params = Int[]
    for field in fields
        value = 0
        for digit in field
            value = min(9999,value*10+Int(digit-'0'))
        end
        push!(params,value)
    end
    reason = csi!(t,t.marker*t.intermediates*string(finalchar),params)
    if reason == 0
        t.sequences += 1
    else
        t.ignored[reason] += 1
    end
end
isintermediate(b::Int) = 0x20 <= b <= 0x2f
isfinal(b::Int) = 0x40 <= b <= 0x7e
function receive!(t::Terminal,b::Int)
    t.bytes += 1
    if b < 0x20
        if b == 27
            if t.state == OSC_STRING
                executeosc!(t)
            elseif t.state != GROUND
                t.ignored[3] += 1
            end
            clearsequence!(t)
            t.state = ESCAPE
        elseif b in (24,26)
            if t.state != GROUND
                t.ignored[3] += 1
                t.state = GROUND
            end
        elseif t.state == OSC_STRING
            if b == 7
                executeosc!(t)
                t.state = GROUND
            end
        else
            control!(t,b)
        end
        return
    end
    c = Char(b)
    if t.state == GROUND
        printchar!(t,c)
    elseif t.state in (ESCAPE,ESC_INTERMEDIATE)
        if isintermediate(b)
            t.intermediates *= string(c)
            t.state = ESC_INTERMEDIATE
        elseif t.state == ESCAPE && c == '['
            t.state = CSI_ENTRY
        elseif t.state == ESCAPE && c == ']'
            t.state = OSC_STRING
        else
            executeesc!(t,t.intermediates*string(c))
            t.state = GROUND
        end
    elseif t.state == OSC_STRING
        t.osc *= string(c)
    elseif t.state == CSI_IGNORE
        if isfinal(b)
            t.ignored[2] += 1
            t.state = GROUND
        end
    elseif t.state == CSI_INTERMEDIATE
        if isintermediate(b)
            t.intermediates *= string(c)
        elseif isfinal(b)
            executecsi!(t,c)
            t.state = GROUND
        else
            t.state = CSI_IGNORE
        end
    elseif t.state == CSI_ENTRY && 0x3c <= b <= 0x3f
        t.marker = string(c)
        t.state = CSI_PARAM
    elseif '0' <= c <= '9' || c == ';'
        t.parameters *= string(c)
        t.state = CSI_PARAM
    elseif isintermediate(b)
        t.intermediates *= string(c)
        t.state = CSI_INTERMEDIATE
    elseif isfinal(b)
        executecsi!(t,c)
        t.state = GROUND
    else
        t.state = CSI_IGNORE
    end
end
function keystring(t::Terminal,name::String)
    cursor = Dict("UP"=>"A","DOWN"=>"B","RIGHT"=>"C","LEFT"=>"D","HOME"=>"H","END"=>"F")
    haskey(cursor,name) && return (t.modes["DECCKM"] ? "^[O" : "^[[")*cursor[name]
    fixed = Dict("INSERT"=>"^[[2~","DELETE"=>"^[[3~","PAGEUP"=>"^[[5~","PAGEDOWN"=>"^[[6~",
                 "F1"=>"^[OP","F2"=>"^[OQ","F3"=>"^[OR","F4"=>"^[OS","F5"=>"^[[15~","F6"=>"^[[17~",
                 "F7"=>"^[[18~","F8"=>"^[[19~","F9"=>"^[[20~","F10"=>"^[[21~","F11"=>"^[[23~","F12"=>"^[[24~",
                 "TAB"=>"^I","BACKSPACE"=>"^?","ESCAPE"=>"^[")
    haskey(fixed,name) && return fixed[name]
    enter = t.modes["LNM"] ? "^M^J" : "^M"
    name == "ENTER" && return enter
    if name == "KPENTER"
        return t.modes["DECKPAM"] ? "^[OM" : enter
    end
    digit = parse(Int,name[3:end])
    return t.modes["DECKPAM"] ? "^[O"*string(Char(0x70+digit)) : string(digit)
end
function screenoutput(t::Terminal,label::String)
    name = t.display == 1 ? "main" : "alt"
    println("$label $name cursor $(t.row),$(t.column) scrollback $(length(t.scrollback))",t.pending ? " pending" : "")
    for row in t.screens[t.display]
        println("|",rowtext(row))
    end
end
function describe(attr::Attributes)
    parts = [name for (bit,name) in enumerate(FLAG_NAMES) if attr.flags & (1 << (bit-1)) != 0]
    !isempty(attr.fg) && push!(parts,"fg="*attr.fg)
    !isempty(attr.bg) && push!(parts,"bg="*attr.bg)
    return join(parts," ")
end
function finish!(t::Terminal)
    if t.state != GROUND
        t.ignored[3] += 1
        t.state = GROUND
    end
    screenoutput(t,"FINAL")
    println("TITLE ",t.title === nothing ? "none" : "\""*t.title*"\"")
    modes = [name*"="*(t.modes[name] ? "on" : "off") for name in MODE_NAMES if t.modes[name] != initial(name)]
    t.g0 && push!(modes,"G0=graphics")
    t.g1 && push!(modes,"G1=graphics")
    t.gl && push!(modes,"GL=G1")
    t.shape != 1 && push!(modes,"CURSOR=$(t.shape)")
    println("MODES ",isempty(modes) ? "default" : join(modes," "))
    println("REGION $(t.top)-$(t.bottom)")
    println("TABS ",isempty(t.tabs) ? "none" : join(sort(collect(t.tabs)),","))
    println("SCROLLBACK ",length(t.scrollback))
    for text in t.scrollback[max(1,length(t.scrollback)-4):end]
        println("|",text)
    end
    runs = String[]
    for (r,row) in enumerate(t.screens[t.display])
        start = 1
        while start <= t.width
            stop = start
            while stop < t.width && row[stop+1].attr == row[start].attr
                stop += 1
            end
            row[start].attr != Attributes() && push!(runs,"row $r col $start-$stop $(describe(row[start].attr))")
            start = stop+1
        end
    end
    println("ATTRS ",length(runs))
    foreach(println,runs)
    println("BELL ",t.bells)
    println("REPLIES ",t.replies)
    println("STATS bytes=$(t.bytes) printed=$(t.printed) sequences=$(t.sequences)")
    v = t.ignored
    println("IGNORED $(sum(v)) unsupported=$(v[1]) malformed=$(v[2]) canceled=$(v[3]) invalid=$(v[4])")
end
function main()
    lines = readlines()
    width,height = parse.(Int,split(lines[1]))
    terminal = Terminal(width=width,height=height)
    reset!(terminal)
    caret = Dict('@'=>0,'G'=>7,'H'=>8,'I'=>9,'J'=>10,'K'=>11,'L'=>12,'M'=>13,'N'=>14,'O'=>15,'X'=>24,'Z'=>26,'['=>27,'^'=>94)
    for line in lines[2:end]
        line == "%%END" && break
        if line == "%%DUMP"
            terminal.dumps += 1
            screenoutput(terminal,"DUMP $(terminal.dumps)")
        elseif startswith(line,"%%KEY ")
            name = line[7:end]
            println("KEY $name $(keystring(terminal,name))")
        elseif startswith(line,"%%PASTE ")
            sent = replace(line[9:end],"^"=>"^^")
            terminal.modes["BRACKETED"] && (sent = "^[[200~"*sent*"^[[201~")
            println("PASTE ",sent)
        else
            index = 1
            while index <= length(line)
                if line[index] == '^'
                    receive!(terminal,caret[line[index+1]])
                    index += 2
                else
                    receive!(terminal,Int(line[index]))
                    index += 1
                end
            end
        end
    end
    finish!(terminal)
end
main()
