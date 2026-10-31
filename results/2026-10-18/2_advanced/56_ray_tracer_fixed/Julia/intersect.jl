function slab(lo,hi,origin,direction)
    near,far = nothing,nothing
    near_axis,far_axis = 0,0
    for axis in 1:3
        component = direction[axis]
        if component==0
            (origin[axis]<lo[axis] || origin[axis]>hi[axis]) && return nothing
            continue
        end
        a,b = fld((lo[axis]-origin[axis])*S,component),fld((hi[axis]-origin[axis])*S,component)
        entry,exit = min(a,b),max(a,b)
        if isnothing(near) || entry>near
            near,near_axis = entry,axis
        end
        if isnothing(far) || exit<far
            far,far_axis = exit,axis
        end
    end
    near>far ? nothing : (near=near,near_axis=near_axis,far=far,far_axis=far_axis)
end
function candidate(object,origin,direction,epsilon)
    if object.kind=="sphere"
        oc = sub(origin,object.center)
        b = dot(oc,direction)
        tc = fld(-b*S,dot(direction,direction))
        h = add(oc,sc(direction,tc))
        q = fld(object.radius^2,S)-dot(h,h)
        q<0 && return nothing
        width = fld(isqrt(q*S)*S,vector_length(direction))
        t1,t2 = tc-width,tc+width
        distance = t1>epsilon ? t1 : t2
        return distance>epsilon ? (distance=distance,entering=false,axis=0) : nothing
    elseif object.kind=="plane"
        denominator = dot(direction,object.normal)
        denominator==0 && return nothing
        distance = fld(dot(sub(object.point,origin),object.normal)*S,denominator)
        return distance>epsilon ? (distance=distance,entering=false,axis=0) : nothing
    end
    interval = slab(object.lo,object.hi,origin,direction)
    isnothing(interval) && return nothing
    interval.near>epsilon && return (distance=interval.near,entering=true,axis=interval.near_axis)
    interval.far>epsilon && return (distance=interval.far,entering=false,axis=interval.far_axis)
    nothing
end
function outward_normal(object,point,direction,intersection)
    object.kind=="sphere" && return norm(sub(point,object.center))
    object.kind=="plane" && return object.normal
    sign = direction[intersection.axis]>0 ? 1 : -1
    intersection.entering && (sign=-sign)
    ntuple(a->a==intersection.axis ? sign*S : 0,3)
end
function object_bounds(object,margin)
    object.kind=="plane" && return nothing
    if object.kind=="sphere"
        radius = object.radius+margin
        return (ntuple(a->object.center[a]-radius,3),ntuple(a->object.center[a]+radius,3))
    end
    ntuple(a->object.lo[a]-margin,3),ntuple(a->object.hi[a]+margin,3)
end
