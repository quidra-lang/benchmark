using Printf
mutable struct LayoutCanvas
    direction::String
    main_length::Int
    vertical::Bool
    rows::Int
    columns::Int
    lines::Matrix{UInt8}
    arrows::Matrix{Char}
    boxes::Matrix{Char}
    highlighted::BitMatrix
end
function new_canvas(direction,main_length,secondary_length)
    vertical = direction in ("TB","BT")
    rows,columns = vertical ? (main_length,secondary_length) : (secondary_length,main_length)
    LayoutCanvas(direction,main_length,vertical,rows,columns,zeros(UInt8,rows,columns),
        fill(' ',rows,columns),fill(' ',rows,columns),falses(rows,columns))
end
function canvas_cell(canvas,main,secondary)
    canvas.direction in ("BT","RL") && (main = canvas.main_length-1-main)
    canvas.vertical ? (main,secondary) : (secondary,main)
end
function add_line!(canvas,main,secondary,character)
    row,column = canvas_cell(canvas,main,secondary)
    bit = character == '|' ? UInt8(1) : character == '-' ? UInt8(2) : UInt8(4)
    canvas.lines[row+1,column+1] |= bit
end
function main_line!(canvas,start,stop,secondary)
    character = canvas.vertical ? '|' : '-'
    for main in start:stop
        add_line!(canvas,main,secondary,character)
    end
end
function draw_segment!(canvas,start,gap,a,b,offset)
    if a == b
        main_line!(canvas,start,start+gap-1,a)
        return
    end
    main_line!(canvas,start,start+offset-1,a)
    add_line!(canvas,start+offset,a,'+')
    add_line!(canvas,start+offset,b,'+')
    character = canvas.vertical ? '-' : '|'
    for secondary in (min(a,b)+1):(max(a,b)-1)
        add_line!(canvas,start+offset,secondary,character)
    end
    main_line!(canvas,start+offset+1,start+gap-1,b)
end
function draw_arrow!(canvas,point,reversed_edge)
    forward = Dict("TB"=>'v',"BT"=>'^',"LR"=>'>',"RL"=>'<')
    backward = Dict("TB"=>'^',"BT"=>'v',"LR"=>'<',"RL"=>'>')
    row,column = canvas_cell(canvas,point...)
    canvas.arrows[row+1,column+1] = (reversed_edge ? backward : forward)[canvas.direction]
end
function highlight_route!(canvas,points)
    for i in 1:length(points)-1
        a,b = points[i],points[i+1]
        row_step,column_step = sign(b[1]-a[1]),sign(b[2]-a[2])
        for step in 0:(abs(b[1]-a[1])+abs(b[2]-a[2]))
            canvas.highlighted[a[1]+step*row_step+1,a[2]+step*column_step+1] = true
        end
    end
end
function draw_box!(canvas,label,band,coordinate,left,on_path)
    text = on_path ? "{" * label * "}" : "[" * label * "]"
    if canvas.vertical
        row,column = canvas_cell(canvas,band,coordinate-left)
    elseif canvas.direction == "LR"
        row,column = coordinate,band
    else
        row,column = coordinate,canvas.main_length-band-length(text)
    end
    for (i,c) in enumerate(text)
        canvas.boxes[row+1,column+i] = c
    end
end
function canvas_character(canvas,row,column)
    canvas.boxes[row,column] != ' ' && return canvas.boxes[row,column]
    canvas.arrows[row,column] != ' ' && return canvas.arrows[row,column]
    canvas.highlighted[row,column] && return '#'
    bits = canvas.lines[row,column]
    bits == 0 && return ' '
    bits == 1 && return '|'
    bits == 2 && return '-'
    '+'
end
crossing_cells(canvas) = count(bits -> bits & 3 == 3,canvas.lines)
function drawing_lines(canvas)
    lines = ["    " * join([string(c % 10) for c in 0:canvas.columns-1])]
    for row in 1:canvas.rows
        text = @sprintf("%3d ",row-1) * String([canvas_character(canvas,row,c) for c in 1:canvas.columns])
        push!(lines,rstrip(c -> c == ' ',text))
    end
    lines
end
