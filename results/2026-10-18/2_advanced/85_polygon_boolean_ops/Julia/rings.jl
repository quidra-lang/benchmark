ring_edges(ring) = [(ring[i],ring[mod1(i+1,length(ring))]) for i in eachindex(ring)]
function inside_ring(ring, p)
    parity = false
    for (a,b) in ring_edges(ring)
        if (a[2] > p[2]) != (b[2] > p[2])
            low, high = a[2] < b[2] ? (a,b) : (b,a)
            cross(low,high,p) > 0 && (parity = !parity)
        end
    end
    return parity
end
interior(rings,p) = isodd(count(r -> inside_ring(r,p),rings))
boundary(ring,p) = any(on_segment(p,a,b) for (a,b) in ring_edges(ring))
function rotate_ring(ring)
    i = argmin(point_key,ring)
    index = findfirst(==(i),ring)
    return [ring[index:end];ring[1:index-1]]
end
counterclockwise(ring) = cross(ring[end],ring[1],ring[2]) > 0
reverse_ring(ring) = [ring[1:1];reverse(ring[2:end])]
function normalize_ring(ring, outer)
    result = rotate_ring(ring)
    return counterclockwise(result) == outer ? result : reverse_ring(result)
end
function assemble_rings(rings)
    rotated = rotate_ring.(rings)
    depths = [count(
        j -> j != i && inside_ring(rotated[j],rotated[i][1]),
        eachindex(rotated)
    ) for i in eachindex(rotated)]
    oriented = [counterclockwise(r) == iseven(d) ? r : reverse_ring(r) for (r,d) in zip(rotated,depths)]
    indices = sort([i for i in eachindex(depths) if iseven(depths[i])]; by=i -> point_key(oriented[i][1]))
    result = Vector{Vector{Point}}[]
    for i in indices
        holes = [oriented[j] for j in eachindex(oriented) if depths[j] == depths[i]+1 && inside_ring(
            oriented[i],
            oriented[j][1]
        )]
        sort!(holes; by=r -> point_key(r[1]))
        push!(result, [oriented[i:i];holes])
    end
    return result
end
function ring_area(ring)
    total = 0.0
    for (a,b) in ring_edges(ring)
        x1,y1,x2,y2 = coordinate_real(a[1]),coordinate_real(a[2]),coordinate_real(b[1]),coordinate_real(b[2])
        total += x1*y2-x2*y1
    end
    return total/2.0
end
function ring_perimeter(ring)
    total = 0.0
    for (a,b) in ring_edges(ring)
        dx,dy = coordinate_real(b[1])-coordinate_real(a[1]),coordinate_real(b[2])-coordinate_real(a[2])
        total += sqrt(dx*dx+dy*dy)
    end
    return total
end
