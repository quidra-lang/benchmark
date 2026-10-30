include("lexer.jl")
include("parser.jl")
include("boxes.jl")
include("layout.jl")
include("canvas.jl")
const STACKED_COMMANDS = Set(["\\sum","\\prod","\\lim","\\max","\\min"])
const BRACE_ACCENTS = Set(["overbrace","underbrace"])
const DELIMITER_PAIRS = Dict("("=>")","["=>"]","|"=>"|","\\{"=>"\\}")
mutable struct Formula
    number::Int
    text::String
    nodes::Vector{FormulaNode}
    tag::Union{Nothing,FormulaToken}
    label::Union{Nothing,FormulaToken}
    tag_string::Union{Nothing,String}
    error::Union{Nothing,FormulaError}
    warnings::Vector{Tuple{Int,String}}
end
function read_formula(number,text)
    formula = Formula(number,text,FormulaNode[],nothing,nothing,nothing,nothing,Tuple{Int,String}[])
    try
        tokens = tokenize(text)
        check_braces(tokens)
        parser = FormulaParser(tokens,1,nothing,nothing)
        formula.nodes = parse_formula!(parser)
        formula.tag,formula.label = parser.tag,parser.label
    catch error
        error isa FormulaError || rethrow()
        formula.error = error
    end
    formula
end
function reference_table(formulas)
    counter = 0
    for formula in formulas
        formula.error === nothing || continue
        if formula.tag !== nothing
            formula.tag_string = "(" * formula.tag.value * ")"
        elseif formula.label !== nothing
            counter += 1
            formula.tag_string = "($counter)"
        end
    end
    references = Dict{String,String}()
    for formula in formulas
        (formula.error === nothing && formula.label !== nothing) || continue
        label = formula.label
        if haskey(references,label.value)
            push!(formula.warnings,(label.column,"duplicate label \"$(label.value)\""))
        else
            references[label.value] = formula.tag_string
        end
    end
    references
end
function collect_warnings!(formula,references)
    function visit(node)
        if node.kind == "identifier" && node.value in COMMAND_NAMES
            push!(formula.warnings,(node.column,"$(node.value) is a command name; write \\" * node.value))
        elseif node.kind == "reference" && !haskey(references,node.value)
            push!(formula.warnings,(node.column,"undefined reference \"$(node.value)\""))
        elseif node.kind == "delim"
            left,right = node.value
            if left != "." && right != "." && get(DELIMITER_PAIRS,left,"") != right
                push!(formula.warnings,(node.column,"\\left" * left * " closed by \\right" * right))
            end
        end
        if node.kind == "matrix"
            for row in node.children, cell in row
                visit(cell)
            end
        else
            for child in node.children
                child === nothing || visit(child)
            end
        end
    end
    foreach(visit,formula.nodes)
    sort!(formula.warnings;by=first)
end
center(box,width) = (width-box.width) ÷ 2
function draw_delimiter!(box,delimiter,x,height)
    for (y,character) in enumerate(delimiter_glyph(delimiter,height))
        draw_string!(box,character,x,y-1)
    end
end
delimiter_string(delimiter) = delimiter == "." ? "" : string(delimiter[end])
function delimit_box(body,left,right)
    wl,wr = left == "." ? 0 : 1,right == "." ? 0 : 1
    result = new_box(wl+body.width+wr,body.height,body.baseline,"delim $left $right")
    add_child!(result,body,wl,0)
    draw_delimiter!(result,left,0,body.height)
    draw_delimiter!(result,right,wl+body.width,body.height)
    result
end
function radical_box(body,index=nothing)
    height = body.height
    extra = index === nothing ? 0 : max(0,index.width-1)
    top = index === nothing ? 0 : max(0,index.height-height)
    result = new_box(extra+height+1+body.width,height+1+top,body.baseline+1+top,index === nothing ? "sqrt" : "root")
    draw_string!(result,repeat("_",body.width),extra+height+1,top)
    draw_string!(result,"\\",extra,height+top)
    for row in 1:height
        draw_string!(result,"/",extra+height-row+1,row+top)
    end
    if index === nothing
        add_child!(result,body,extra+height+1,1)
    else
        add_child!(result,index,0,height-index.height+top,"index: ")
        add_child!(result,body,extra+height+1,1+top,"body: ")
    end
    result
end
function typeset(node,parameters,references,style="normal")
    kind = node.kind
    if kind in ATOM_KINDS || kind == "reference"
        description = kind == "text" ? "text \"$(node.value)\"" :
            kind == "reference" ? "eqref \"$(node.value)\"" : "atom \"$(node.value)\""
        display = kind == "reference" ? get(references,node.value,"(??)") :
            kind == "command" ? COMMAND_DISPLAY[node.value] : node.value
        if kind == "command" && haskey(LARGE_GLYPHS,node.value) && style == "normal"
            glyph = LARGE_GLYPHS[node.value]
            result = new_box(length(glyph[1]),3,1,description)
            for (y,text) in enumerate(glyph)
                draw_string!(result,text,0,y-1)
            end
        else
            result = new_box(length(display),1,0,description)
            draw_string!(result,display)
        end
        return result
    elseif kind == "row"
        _,gaps = spacing(node.children,style,parameters)
        return row_box([typeset(child,parameters,references,style) for child in node.children],gaps)
    elseif kind == "script"
        base_node,sub_node,sup_node = node.children
        base = typeset(base_node,parameters,references,style)
        sub = sub_node === nothing ? nothing : typeset(sub_node,parameters,references,"script")
        sup = sup_node === nothing ? nothing : typeset(sup_node,parameters,references,"script")
        sw,sh = sub === nothing ? (0,0) : (sub.width,sub.height)
        pw,ph = sup === nothing ? (0,0) : (sup.width,sup.height)
        stacked = style == "normal" && ((base_node.kind == "command" && base_node.value in STACKED_COMMANDS) ||
            (base_node.kind == "accent" && base_node.value in BRACE_ACCENTS))
        if stacked
            width = max(base.width,sw,pw)
            result = new_box(width,ph+base.height+sh,ph+base.baseline,"limits")
            add_child!(result,base,center(base,width),ph,"base: ")
            sub === nothing || add_child!(result,sub,center(sub,width),ph+base.height,"sub: ")
            sup === nothing || add_child!(result,sup,center(sup,width),0,"sup: ")
        else
            sup_top = (base.baseline == 0 ? -1 : 0)-ph+1
            sub_top = descent(base) == 0 ? base.height : base.height-1
            top = sup === nothing ? 0 : min(0,sup_top)
            bottom = sub === nothing ? base.height-1 : max(base.height-1,sub_top+sh-1)
            result = new_box(base.width+max(sw,pw),bottom-top+1,base.baseline-top,"scripts")
            add_child!(result,base,0,-top,"base: ")
            sub === nothing || add_child!(result,sub,base.width,sub_top-top,"sub: ")
            sup === nothing || add_child!(result,sup,base.width,sup_top-top,"sup: ")
        end
        return result
    elseif kind == "frac"
        numerator,denominator = [typeset(child,parameters,references,style) for child in node.children]
        if style == "normal"
            width = max(numerator.width,denominator.width)+2
            result = new_box(width,numerator.height+1+denominator.height,numerator.height,"frac")
            add_child!(result,numerator,center(numerator,width),0,"num: ")
            add_child!(result,denominator,center(denominator,width),numerator.height+1,"den: ")
            draw_string!(result,repeat("-",width),0,numerator.height)
            return result
        end
        node.children[1].kind in ("row","frac") && (numerator = delimit_box(numerator,"(",")"))
        node.children[2].kind in ("row","frac") && (denominator = delimit_box(denominator,"(",")"))
        slash = new_box(1,1,0,"atom \"/\"")
        draw_string!(slash,"/")
        return row_box([numerator,slash,denominator],[0,0],"slash",["num: ","","den: "])
    elseif kind == "binom"
        upper,lower = [typeset(child,parameters,references,style) for child in node.children]
        width,height = max(upper.width,lower.width),upper.height+1+lower.height
        result = new_box(width+2,height,upper.height,"binom")
        add_child!(result,upper,center(upper,width)+1,0,"upper: ")
        add_child!(result,lower,center(lower,width)+1,upper.height+1,"lower: ")
        draw_delimiter!(result,"(",0,height)
        draw_delimiter!(result,")",width+1,height)
        return result
    elseif kind in ("overset","underset")
        placed = typeset(node.children[1],parameters,references,"script")
        base = typeset(node.children[2],parameters,references,style)
        width = max(placed.width,base.width)
        result = new_box(width,placed.height+base.height,kind == "overset" ? placed.height+base.baseline : base.baseline,kind)
        if kind == "overset"
            add_child!(result,placed,center(placed,width),0,"over: ")
            add_child!(result,base,center(base,width),placed.height,"base: ")
        else
            add_child!(result,base,center(base,width),0,"base: ")
            add_child!(result,placed,center(placed,width),base.height,"under: ")
        end
        return result
    elseif kind == "sqrt"
        return radical_box(typeset(node.children[1],parameters,references,style))
    elseif kind == "root"
        index = typeset(node.children[1],parameters,references,"script")
        body = typeset(node.children[2],parameters,references,style)
        return radical_box(body,index)
    elseif kind == "delim"
        return delimit_box(typeset(node.children[1],parameters,references,style),node.value...)
    elseif kind == "matrix"
        cells = [[typeset(cell,parameters,references,style) for cell in row] for row in node.children]
        row_count,column_count = length(cells),length(cells[1])
        widths = [maximum(row[j].width for row in cells) for j in 1:column_count]
        ascents = [maximum(c.baseline for c in row) for row in cells]
        descents = [maximum(descent(c) for c in row) for row in cells]
        heights = ascents+descents .+ 1
        column_gap,row_gap = parameters["col_gap"],parameters["row_gap"]
        body_width,body_height = sum(widths)+column_gap*(column_count-1),sum(heights)+row_gap*(row_count-1)
        environment = node.value
        shift = environment == "matrix" ? 0 : 2
        extra = environment == "matrix" ? 0 : environment == "cases" ? 2 : 4
        result = new_box(body_width+extra,body_height,(body_height-1)÷2,"$environment rows=$row_count cols=$column_count")
        y = 0
        for (i,row) in enumerate(cells)
            x = shift
            for (j,cell) in enumerate(row)
                offset = environment == "cases" ? 0 : center(cell,widths[j])
                add_child!(result,cell,x+offset,y+ascents[i]-cell.baseline,"cell $i,$j: ")
                x += widths[j]+column_gap
            end
            y += heights[i]+row_gap
        end
        if environment == "cases"
            draw_delimiter!(result,"\\{",0,body_height)
        elseif environment != "matrix"
            left,right = Dict("pmatrix"=>("(",")"),"bmatrix"=>("[","]"),"vmatrix"=>("|","|"))[environment]
            draw_delimiter!(result,left,0,body_height)
            draw_delimiter!(result,right,body_width+3,body_height)
        end
        return result
    end
    body = typeset(node.children[1],parameters,references,style)
    name = node.value
    width = body.width
    name in ("hat","dot","tilde") && (width = max(width,1))
    name == "vec" && (width = max(width,2))
    name in BRACE_ACCENTS && (width += 2)
    baseline = name == "underbrace" ? body.baseline : body.baseline+1
    result = new_box(width,body.height+1,baseline,name)
    if name == "underbrace"
        add_child!(result,body,1,0)
        draw_string!(result,"\\" * repeat("-",body.width) * "/",0,body.height)
    elseif name == "overbrace"
        add_child!(result,body,1,1)
        draw_string!(result,"/" * repeat("-",body.width) * "\\")
    else
        add_child!(result,body,0,1)
        if name == "overline"
            draw_string!(result,repeat("_",width))
        elseif name == "vec"
            draw_string!(result,repeat("-",width-1) * ">")
        else
            draw_string!(result,Dict("hat"=>"^","dot"=>".","tilde"=>"~")[name],(width-1)÷2,0)
        end
    end
    result
end
function build_lines(breaks,types,boxes,starts,parameters)
    result = Any[]
    position = 1
    alignment = nothing
    while position <= length(boxes)
        indentation = position == 1 ? 0 : alignment === nothing ? parameters["indent"] :
            types[position][1] == "relation" ? alignment[1] : alignment[1]+alignment[2]+parameters["rel_space"]
        ends = [sort([stop for stop in breaks if stop > position]);length(boxes)+1]
        candidates = [(stop=stop,width=starts[stop-1]+boxes[stop-1].width-starts[position]) for stop in ends]
        fitting = [candidate for candidate in candidates if indentation+candidate.width <= parameters["width"]]
        chosen = isempty(fitting) ? candidates[1] : fitting[end]
        push!(result,(first=position,stop=chosen.stop,indent=indentation,width=chosen.width))
        if position == 1
            for i in 1:chosen.stop-1
                if types[i][1] == "relation"
                    alignment = (starts[i],boxes[i].width)
                    break
                end
            end
        end
        position = chosen.stop
    end
    result
end
function place_formula(formula,parameters,references)
    nodes = formula.nodes
    types,gaps = spacing(nodes,"normal",parameters)
    boxes = [typeset(node,parameters,references) for node in nodes]
    starts = Int[]
    x = 0
    for (i,box) in enumerate(boxes)
        push!(starts,x)
        x += box.width
        i <= length(gaps) && (x += gaps[i])
    end
    relations = Set(i for i in 2:length(nodes) if types[i][1] == "relation")
    plus_minus = Set(i for i in 2:length(nodes) if nodes[i].kind == "symbol" && nodes[i].value in ("+","-") && types[i][1] == "binary")
    punctuation = Set(i for i in 2:length(nodes) if types[i-1][2] == "punctuation")
    plan = Any[]
    for breaks in (relations,union(relations,plus_minus),union(relations,plus_minus,punctuation))
        plan = build_lines(breaks,types,boxes,starts,parameters)
        all(entry.indent+entry.width <= parameters["width"] for entry in plan) && break
    end
    roots = Tuple{FormulaBox,Int,Int}[]
    overfull = Tuple{Int,Int}[]
    width,height = 0,0
    for (number,entry) in enumerate(plan)
        box = row_box(boxes[entry.first:entry.stop-1],gaps[entry.first:entry.stop-2],"line $number")
        push!(roots,(box,entry.indent,height))
        height += box.height
        width = max(width,entry.indent+box.width)
        entry.indent+entry.width > parameters["width"] && push!(overfull,(number,entry.indent+entry.width))
    end
    if formula.tag_string !== nothing
        tag = formula.tag_string
        tx = parameters["width"]-length(tag)
        last,last_x,last_y = roots[end]
        if tx >= last_x+last.width+2
            ty = last_y+last.baseline
        else
            ty = height
            height += 1
        end
        tag_box = new_box(length(tag),1,0,"tag \"$tag\"")
        draw_string!(tag_box,tag)
        push!(roots,(tag_box,tx,ty))
        width = max(width,tx+tag_box.width)
    end
    (roots=roots,lines=length(plan),width=width,height=height,overfull=overfull)
end
function tree_notation(node)
    kind = node.kind
    kind in ("identifier","number","command") && return node.value
    kind == "symbol" && return "'" * node.value * "'"
    kind == "text" && return "\"" * node.value * "\""
    kind == "reference" && return "(eqref \"$(node.value)\")"
    kind == "row" && return "(row" * join([" " * tree_notation(c) for c in node.children]) * ")"
    if kind == "matrix"
        rows = ["[" * join(tree_notation.(row)," ") * "]" for row in node.children]
        return "(" * node.value * " " * join(rows," ") * ")"
    elseif kind == "delim"
        delimiters = [length(value) == 1 ? "'" * value * "'" : value for value in node.value]
        return "(delim " * join(delimiters," ") * " " * tree_notation(node.children[1]) * ")"
    elseif kind == "script"
        base,sub,sup = node.children
        name = sub === nothing ? "sup" : sup === nothing ? "sub" : "subsup"
        children = [child for child in (base,sub,sup) if child !== nothing]
    else
        name = kind == "accent" ? node.value : kind
        children = node.children
    end
    "(" * name * " " * join(tree_notation.(children)," ") * ")"
end
function linear_row(nodes,parameters,references,style)
    _,gaps = spacing(nodes,style,parameters)
    parts = String[]
    for (i,node) in enumerate(nodes)
        i > 1 && push!(parts,repeat(" ",gaps[i-1]))
        push!(parts,linear_notation(node,parameters,references,style))
    end
    join(parts)
end
function parenthesize(node,parameters,references,style,kinds)
    value = linear_notation(node,parameters,references,style)
    node.kind in kinds ? "(" * value * ")" : value
end
function linear_notation(node,parameters,references,style="normal")
    kind = node.kind
    kind in ("identifier","number","symbol","text") && return node.value
    kind == "command" && return COMMAND_DISPLAY[node.value]
    kind == "reference" && return get(references,node.value,"(??)")
    kind == "row" && return linear_row(node.children,parameters,references,style)
    if kind == "frac"
        return join([parenthesize(c,parameters,references,style,("row","frac")) for c in node.children],"/")
    elseif kind == "script"
        base,sub,sup = node.children
        result = parenthesize(base,parameters,references,style,("row","frac","script"))
        sub === nothing || (result *= "_" * parenthesize(sub,parameters,references,"script",("row","frac")))
        sup === nothing || (result *= "^" * parenthesize(sup,parameters,references,"script",("row","frac")))
        return result
    elseif kind == "delim"
        left,right = node.value
        return delimiter_string(left) * linear_notation(node.children[1],parameters,references,style) * delimiter_string(right)
    elseif kind == "matrix"
        rows = [join([linear_notation(c,parameters,references,style) for c in row],", ") for row in node.children]
        return node.value * "[" * join(rows,"; ") * "]"
    elseif kind in ("root","overset","underset")
        return kind * "(" * linear_notation(node.children[1],parameters,references,"script") * ", " *
            linear_notation(node.children[2],parameters,references,style) * ")"
    end
    name = kind == "accent" ? node.value : kind
    name * "(" * join([linear_notation(c,parameters,references,style) for c in node.children],", ") * ")"
end
function diagnostic(formula,column,message;warning=false)
    prefix = warning ? "warning: " : ""
    ["formula $(formula.number), column $column: $prefix$message","  " * formula.text,repeat(" ",column+1) * "^"]
end
function main()
    parameters = Dict{String,Int}()
    for text in readlines("input/params.txt")
        name,value = split(text)
        parameters[String(name)] = parse(Int,value)
    end
    formulas = [read_formula(i,text) for (i,text) in enumerate(readlines("input/formulas.txt"))]
    references = reference_table(formulas)
    rendered,boxes,trees,errors = String[],String[],String[],String[]
    box_kinds = Dict{String,Int}()
    total_boxes,max_depth,valid_count,error_count,warning_count,overfull_count = 0,0,0,0,0,0
    for formula in formulas
        formula.number > 1 && push!(rendered,"")
        push!(rendered,"formula $(formula.number)")
        if formula.error !== nothing
            error_count += 1
            push!(rendered,"(error)")
            push!(boxes,"formula $(formula.number): error")
            push!(trees,"formula $(formula.number): error")
            append!(errors,diagnostic(formula,formula.error.column,formula.error.message))
            continue
        end
        valid_count += 1
        collect_warnings!(formula,references)
        placement = place_formula(formula,parameters,references)
        append!(rendered,draw_boxes(placement.roots,placement.width,placement.height))
        entries = box_lines(placement.roots)
        depth = maximum(entry.level for entry in entries)+1
        total_boxes += length(entries)
        max_depth = max(max_depth,depth)
        push!(boxes,"formula $(formula.number): lines=$(placement.lines) width=$(placement.width) height=$(placement.height) boxes=$(length(entries)) depth=$depth")
        for entry in entries
            push!(boxes,entry.text)
            box_kinds[entry.kind] = get(box_kinds,entry.kind,0)+1
        end
        push!(trees,"formula $(formula.number): " * join(tree_notation.(formula.nodes)," "))
        linear = rstrip(c -> c == ' ',linear_row(formula.nodes,parameters,references,"normal"))
        push!(trees,"  linear:" * (isempty(linear) ? "" : " " * linear))
        formula.tag_string === nothing || push!(trees,"  tag: " * formula.tag_string)
        warning_count += length(formula.warnings)
        for (column,message) in formula.warnings
            append!(errors,diagnostic(formula,column,message;warning=true))
        end
        overfull_count += length(placement.overfull)
        for (number,occupied) in placement.overfull
            push!(errors,"formula $(formula.number): line $number is overfull (width $occupied > $(parameters["width"]))")
        end
    end
    push!(boxes,"summary: boxes=$total_boxes max_depth=$max_depth")
    append!(boxes,["  $kind: $(box_kinds[kind])" for kind in sort(collect(keys(box_kinds)))])
    push!(errors,"formulas=$(length(formulas)) rendered=$valid_count errors=$error_count warnings=$warning_count overfull=$overfull_count")
    mkpath("output")
    for (name,lines) in [("rendered.txt",rendered),("boxes.txt",boxes),("trees.txt",trees),("errors.txt",errors)]
        write(joinpath("output",name),join(lines,"\n") * "\n")
    end
end
main()
