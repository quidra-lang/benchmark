rho(point,angle,trig,step) = fld(point[1]*trig[angle+1][1]+point[2]*trig[angle+1][2],16384step)
function circle_points(radius)
    points = Set{Tuple{Int,Int}}()
    a,b,error = radius,0,1-radius
    while a>=b
        union!(points,[(a,b),(b,a),(-b,a),(-a,b),(-a,-b),(-b,-a),(b,-a),(a,-b)])
        b += 1
        if error<0
            error += 2b+1
        else
            a -= 1
            error += 2*(b-a)+1
        end
    end
    points
end
function circle_votes(edges,width,height,params)
    cells = Dict{Int,Matrix{Int}}()
    outlines = Dict{Int,Set{Tuple{Int,Int}}}()
    for radius in params["circle_min_radius"][1]:params["circle_max_radius"][1]
        offsets = circle_points(radius)
        outlines[radius] = offsets
        votes = zeros(Int,height,width)
        for (x,y) in edges,(dx,dy) in offsets
            cx,cy = x+dx,y+dy
            0<=cx<width && 0<=cy<height && (votes[cy+1,cx+1]+=1)
        end
        cells[radius] = votes
    end
    cells,outlines
end
function circle_peaks(cells,outlines,width,height,minimum_percent)
    candidates,peaks = NamedTuple[],NamedTuple[]
    low,high = minimum(keys(cells)),maximum(keys(cells))
    for radius in low:high,y in 0:height-1,x in 0:width-1
        votes,n = cells[radius][y+1,x+1],length(outlines[radius])
        100votes<minimum_percent*n && continue
        cell = (radius=radius,x=x,y=y,votes=votes)
        push!(candidates,cell)
        peak = true
        for r in max(low,radius-2):min(
            high,
            radius+2
        ),yy in max(0,y-2):min(height-1,y+2),xx in max(0,x-2):min(width-1,x+2)
            (r,yy,xx)==(radius,y,x) && continue
            a,b = votes*length(outlines[r]),cells[r][yy+1,xx+1]*n
            if a<b || (a==b && (r,yy,xx)<(radius,y,x))
                peak = false
                break
            end
        end
        peak && push!(peaks,cell)
    end
    function earlier(a,b)
        left,right = a.votes*length(outlines[b.radius]),b.votes*length(outlines[a.radius])
        left==right ? (a.radius,a.y,a.x)<(b.radius,b.y,b.x) : left>right
    end
    sort!(peaks;lt=earlier)
    candidates,peaks
end
function line_votes(edges,trig,step)
    votes = Dict{Tuple{Int,Int},Int}()
    for p in edges,angle in 0:179
        key = (angle,rho(p,angle,trig,step))
        votes[key] = get(votes,key,0)+1
    end
    votes
end
function line_peaks(votes,threshold)
    peaks = NamedTuple[]
    for ((angle,radial),value) in votes
        value<threshold && continue
        peak = true
        for t in max(0,angle-2):min(179,angle+2),r in radial-2:radial+2
            (t,r)==(angle,radial) && continue
            other = get(votes,(t,r),0)
            if other>value || (other==value && (t,r)<(angle,radial))
                peak = false
                break
            end
        end
        peak && push!(peaks,(theta=angle,rho=radial,votes=value))
    end
    sort(peaks;by=p->(-p.votes,p.theta,p.rho))
end
