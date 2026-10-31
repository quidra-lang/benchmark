function harris_corners(gx,gy,window,threshold,maximum_count)
    height,width = size(gx)
    half = window÷2
    response = zeros(Int,height,width)
    for y in 0:height-1,x in 0:width-1
        xx = yy = xy = 0
        for dy in -half:half,dx in -half:half
            a,b = clamped(gx,x+dx,y+dy),clamped(gy,x+dx,y+dy)
            xx += a*a
            yy += b*b
            xy += a*b
        end
        response[y+1,x+1] = xx*yy-xy*xy-fld((xx+yy)^2,25)
    end
    candidates = NamedTuple[]
    for y in 0:height-1,x in 0:width-1
        value = response[y+1,x+1]
        value<threshold && continue
        keep = true
        for (dx,dy) in NEIGHBORS
            nx,ny = x+dx,y+dy
            0<=nx<width && 0<=ny<height || continue
            other = response[ny+1,nx+1]
            if other>value || (other==value && (ny,nx)<(y,x))
                keep = false
                break
            end
        end
        keep && push!(candidates,(x=x,y=y,response=value))
    end
    sort!(candidates;by=c->(-c.response,c.y,c.x))
    chosen = NamedTuple[(;corner...,number=i) for (i,corner) in enumerate(candidates[1:min(
        maximum_count,
        length(candidates)
    )])]
    response,candidates,chosen
end
