module Primitives
using ..RasterCanvas
export bresenham, expand_square, circle_points, ellipse_points, bezier_points
function bresenham(first, last)
    x, y = first
    end_x, end_y = last
    dx, dy = abs(end_x-x), -abs(end_y-y)
    sx, sy = x < end_x ? 1 : -1, y < end_y ? 1 : -1
    error = dx+dy
    points = Point[]
    while true
        push!(points, (x, y))
        (x == end_x && y == end_y) && return points
        doubled = 2error
        if doubled >= dy
            error += dy
            x += sx
        end
        if doubled <= dx
            error += dx
            y += sy
        end
    end
end
function expand_square(x, y, width)
    low = -fld(width-1, 2)
    [(x+i, y+j) for j in low:low+width-1 for i in low:low+width-1]
end
function circle_points(radius)
    points = Set{Point}()
    a, b, error = radius, 0, 1-radius
    while a >= b
        union!(points, ((a,b), (b,a), (-b,a), (-a,b), (-a,-b), (-b,-a), (b,-a), (a,-b)))
        b += 1
        if error < 0
            error += 2b+1
        else
            a -= 1
            error += 2(b-a)+1
        end
    end
    points
end
quadrants!(points, x, y) = union!(points, ((x,y), (-x,y), (x,-y), (-x,-y)))
function ellipse_points(rx, ry)
    rx2, ry2 = rx*rx, ry*ry
    x, y = 0, ry
    points = Set{Point}([(0,ry), (0,-ry)])
    while ry2*x < rx2*y
        decision = 4ry2*(x+1)^2 + rx2*(2y-1)^2 - 4rx2*ry2
        x += 1
        decision >= 0 && (y -= 1)
        quadrants!(points, x, y)
    end
    while y > 0
        decision = ry2*(2x+1)^2 + 4rx2*(y-1)^2 - 4rx2*ry2
        y -= 1
        decision <= 0 && (x += 1)
        quadrants!(points, x, y)
    end
    points
end
function bezier_points(controls, segments)
    degree = length(controls)-1
    scale = segments^degree
    points = Point[]
    for i in 0:segments
        rest = segments-i
        weights = degree == 2 ? (rest^2, 2i*rest, i^2) : (rest^3, 3i*rest^2, 3i^2*rest, i^3)
        x = sum(weight*p[1] for (weight,p) in zip(weights, controls))
        y = sum(weight*p[2] for (weight,p) in zip(weights, controls))
        push!(points, (round_ratio(x,scale), round_ratio(y,scale)))
    end
    points
end
end
