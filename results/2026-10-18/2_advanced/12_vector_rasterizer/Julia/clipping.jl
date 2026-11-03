module Clipping
using ..RasterCanvas
export clip_segment, clip_polygon
function region_code(point, clip)
    x, y = point
    x0, y0, x1, y1 = clip
    (x < x0 ? 1 : 0) | (x > x1 ? 2 : 0) | (y < y0 ? 4 : 0) | (y > y1 ? 8 : 0)
end
function clip_segment(first, last, clip)
    x0, y0, x1, y1 = clip
    while true
        first_code, last_code = region_code(first,clip), region_code(last,clip)
        first_code == 0 && last_code == 0 && return (first,last)
        (first_code & last_code) != 0 && return nothing
        code, outside, other = first_code != 0 ? (first_code,first,last) : (last_code,last,first)
        ax, ay = outside
        bx, by = other
        if (code & 4) != 0
            point = (ax+round_ratio((bx-ax)*(y0-ay),by-ay),y0)
        elseif (code & 8) != 0
            point = (ax+round_ratio((bx-ax)*(y1-ay),by-ay),y1)
        elseif (code & 2) != 0
            point = (x1,ay+round_ratio((by-ay)*(x1-ax),bx-ax))
        else
            point = (x0,ay+round_ratio((by-ay)*(x0-ax),bx-ax))
        end
        if first_code != 0
            first = point
        else
            last = point
        end
    end
end
inside(point, axis, limit, minimum) = minimum ? point[axis] >= limit : point[axis] <= limit
function intersection(first, last, axis, limit)
    sx, sy = first
    ex, ey = last
    axis == 1 ? (limit,sy+round_ratio((limit-sx)*(ey-sy),ex-sx)) : (sx+round_ratio((limit-sy)*(ex-sx),ey-sy),limit)
end
function clip_polygon(vertices, clip)
    x0, y0, x1, y1 = clip
    for (axis, limit, minimum) in ((1,x0,true), (1,x1+1,false), (2,y0,true), (2,y1+1,false))
        output = Point[]
        for (i, last) in enumerate(vertices)
            first = vertices[i == 1 ? length(vertices) : i-1]
            if inside(last, axis, limit, minimum)
                !inside(first, axis, limit, minimum) && push!(output, intersection(first,last,axis,limit))
                push!(output, last)
            elseif inside(first, axis, limit, minimum)
                push!(output, intersection(first,last,axis,limit))
            end
        end
        vertices = output
    end
    vertices
end
end
