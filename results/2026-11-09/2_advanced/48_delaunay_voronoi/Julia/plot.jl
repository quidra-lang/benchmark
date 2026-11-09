struct Canvas
    width::Int
    height::Int
    rows::Matrix{Char}
end
Canvas(width,height) = Canvas(width,height,fill(' ',height,width))
function canvas_position(canvas,point)
    x,y = point[1:2]
    d = length(point)==3 ? point[3] : 1
    (fld(2*x*(canvas.width-1)+1000*d,2000*d),canvas.height-1-fld(2*y*(canvas.height-1)+1000*d,2000*d))
end
function mark!(canvas,point,character)
    c,r = canvas_position(canvas,point)
    canvas.rows[r+1,c+1] = character
end
function line!(canvas,a,b,character)
    x,y = canvas_position(canvas,a)
    end_x,end_y = canvas_position(canvas,b)
    dx,dy = abs(end_x-x),-abs(end_y-y)
    sx,sy = x<end_x ? 1 : -1,y<end_y ? 1 : -1
    error = dx+dy
    while true
        canvas.rows[y+1,x+1] = character
        x==end_x && y==end_y && break
        twice = 2*error
        if twice>=dy
            error += dy
            x += sx
        end
        if twice<=dx
            error += dx
            y += sy
        end
    end
end
function draw_voronoi!(canvas,points)
    horizontal,vertical = canvas.width-1,canvas.height-1
    owners = zeros(Int,canvas.height,canvas.width)
    for r in 0:vertical,c in 0:horizontal
        best = typemax(Int)
        for (s,(x,y)) in enumerate(points)
            dx,dy = (c*1000-x*horizontal)*vertical,((vertical-r)*1000-y*vertical)*horizontal
            distance = dx*dx+dy*dy
            if distance<best
                owners[r+1,c+1],best = s,distance
            end
        end
    end
    for r in 0:vertical,c in 0:horizontal
        owner = owners[r+1,c+1]
        if (c<horizontal && owner!=owners[r+1,c+2]) || (r<vertical && owner!=owners[r+2,c+1])
            canvas.rows[r+1,c+1] = '#'
        end
    end
    for point in points
        mark!(canvas,point,'o')
    end
end
function framed(canvas)
    border = "+"*repeat("-",canvas.width)*"+"
    vcat([border],["|"*join(canvas.rows[r,:])*"|" for r in 1:canvas.height],[border])
end
