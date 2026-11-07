function on_segment(p, a, b)
    return cross(a,b,p) == 0 && min(a[1],b[1]) <= p[1] <= max(a[1],b[1]) && min(a[2],b[2]) <= p[2] <= max(
        a[2],
        b[2]
    )
end
function segments_touch(a,b,c,d)
    proper = cross(a,b,c)*cross(a,b,d) < 0 && cross(c,d,a)*cross(c,d,b) < 0
    return proper || on_segment(c,a,b) || on_segment(d,a,b) || on_segment(a,c,d) || on_segment(b,c,d)
end
function segments_overlap(a,b,c,d)
    (cross(a,b,c) != 0 || cross(a,b,d) != 0) && return false
    axis = a[1] != b[1] ? 1 : 2
    return max(min(a[axis],b[axis]),min(c[axis],d[axis])) < min(max(a[axis],b[axis]),max(c[axis],d[axis]))
end
function edge_crossing(a,b,c,d)
    rx, ry, sx, sy = b[1]-a[1], b[2]-a[2], d[1]-c[1], d[2]-c[2]
    den = rx*sy-ry*sx
    den == 0 && return nothing
    gx, gy = c[1]-a[1], c[2]-a[2]
    t, u = (gx*sy-gy*sx)/den, (gx*ry-gy*rx)/den
    (0 < t < 1 && 0 < u < 1) || return nothing
    return (t=t,u=u,point=along(a,b,t))
end
clipping_point(a,b,ca,cb) = along(a,b,ca/(ca-cb))
