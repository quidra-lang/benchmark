module RasterFill
using ..RasterCanvas
export fill_polygons, fill_shape, flood_fill
function crossing_start(first, last, y)
    xa, ya = first
    xb, yb = last
    d = yb-ya
    n = 2xa*d+(2y+1-2ya)*(xb-xa)
    d < 0 && ((n,d) = (-n,-d))
    fld(n-d, 2d)+1
end
function fill_polygons(sequences, rule, clip)
    edges = Tuple{Point,Point}[]
    for vertices in sequences
        for (i, first) in enumerate(vertices)
            last = vertices[i == length(vertices) ? 1 : i+1]
            first[2] != last[2] && push!(edges, (first,last))
        end
    end
    x0, y0, x1, y1 = clip
    pixels = Set{Point}()
    for y in y0:y1
        crossings = Tuple{Int,Int}[]
        for (first,last) in edges
            if min(first[2],last[2]) <= y < max(first[2],last[2])
                push!(crossings, (crossing_start(first,last,y), last[2] > first[2] ? 1 : -1))
            end
        end
        sort!(crossings)
        count = winding = 0
        index = 1
        for x in x0:x1
            while index <= length(crossings) && crossings[index][1] <= x
                count += 1
                winding += crossings[index][2]
                index += 1
            end
            (rule == "evenodd" ? isodd(count) : winding != 0) && push!(pixels, (x,y))
        end
    end
    pixels
end
function fill_shape(center, points, clip)
    extents = Dict{Int,Int}()
    for (dx,dy) in points
        extents[dy] = max(get(extents,dy,0), abs(dx))
    end
    cx, cy = center
    x0, y0, x1, y1 = clip
    pixels = Set{Point}()
    for (dy, extent) in extents
        y = cy+dy
        y0 <= y <= y1 || continue
        for x in max(x0,cx-extent):min(x1,cx+extent)
            push!(pixels, (x,y))
        end
    end
    pixels
end
function flood_fill(layer, seed, clip)
    target = color_at(layer, seed...)
    pixels = Set{Point}([seed])
    pending = [seed]
    x0, y0, x1, y1 = clip
    while !isempty(pending)
        x, y = pop!(pending)
        for neighbor in ((x+1,y), (x-1,y), (x,y+1), (x,y-1))
            nx, ny = neighbor
            (neighbor in pixels || !(x0 <= nx <= x1 && y0 <= ny <= y1)) && continue
            if color_at(layer, nx, ny) == target
                push!(pixels, neighbor)
                push!(pending, neighbor)
            end
        end
    end
    pixels
end
end
