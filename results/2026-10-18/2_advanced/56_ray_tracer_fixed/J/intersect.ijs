slab =: 3 : 0
    'low high origin direction' =. y
    near =. 0x
    far =. 0x
    near_axis =. _1
    far_axis =. _1
    for_axis. i.3 do.
        component =. axis{direction
        if. component=0 do.
            if. ((axis{origin)<axis{low)+.(axis{origin)>axis{high do.
                i.0x return.
            end.
        else.
            a =. (((axis{low)-axis{origin)*S)floor_div component
            b =. (((axis{high)-axis{origin)*S)floor_div component
            entry =. a<.b
            leave =. a>.b
            if. (near_axis<0)+.entry>near do.
                near =. entry
                near_axis =. axis
            end.
            if. (far_axis<0)+.leave<far do.
                far =. leave
                far_axis =. axis
            end.
        end.
    end.
    if. near>far do.
        i.0x
    else.
        near,near_axis,far,far_axis
    end.
)
candidate =: 4 : 0
    'geometry origin direction epsilon' =. y
    if. x-:'sphere' do.
        oc =. origin-3{.geometry
        b =. oc vdot direction
        center_t =. ((-b)*S)floor_div direction vdot direction
        h =. oc+direction vscale center_t
        q =. ((*:3{geometry)floor_div S)-h vdot h
        if. q<0 do.
            i.0x return.
        end.
        width =. ((isqrt q*S)*S)floor_div vlength direction
        distance =. center_t-width
        if. distance<:epsilon do.
            distance =. center_t+width
        end.
        if. distance>epsilon do.
            distance,0,_1 return.
        end.
    elseif. x-:'plane' do.
        denominator =. direction vdot 3}.geometry
        if. denominator=0 do.
            i.0x return.
        end.
        distance =. ((((3{.geometry)-origin)vdot 3}.geometry)*S)floor_div denominator
        if. distance>epsilon do.
            distance,0,_1 return.
        end.
    else.
        interval =. slab (<3{.geometry),(<3}.geometry),(<origin),<direction
        if. #interval do.
            if. (0{interval)>epsilon do.
                (0{interval),1,1{interval return.
            elseif. (2{interval)>epsilon do.
                (2{interval),0,3{interval return.
            end.
        end.
    end.
    i.0x
)
outward_normal =: 4 : 0
    'geometry point direction hit' =. y
    if. x-:'sphere' do.
        vnorm point-3{.geometry return.
    elseif. x-:'plane' do.
        3}.geometry return.
    end.
    axis =. 2{hit
    sign =. _1
    if. (axis{direction)>0 do.
        sign =. 1
    end.
    if. 1{hit do.
        sign =. -sign
    end.
    (sign*S)axis}3$0x
)
object_bounds =: 4 : 0
    'geometry margin' =. y
    if. x-:'plane' do.
        0 3$0x return.
    elseif. x-:'sphere' do.
        radius =. (3{geometry)+margin
        ((3{.geometry)-radius),:(3{.geometry)+radius
    else.
        ((3{.geometry)-margin),:(3}.geometry)+margin
    end.
)
