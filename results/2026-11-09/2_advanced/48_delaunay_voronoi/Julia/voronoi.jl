function squared_radius(a,b,c)
    l1,l2,l3 = Float64(d2(a,b)),Float64(d2(b,c)),Float64(d2(c,a))
    area = Float64(orient(a,b,c))
    ((l1*l2)*l3)/((4*area)*area)
end
function center_position(center,points,hull)
    x,y,d = center
    on = false
    for i in eachindex(hull)
        u,v = points[hull[i]],points[hull[mod1(i+1,length(hull))]]
        sigma = (v[1]-u[1])*(y-u[2]*d)-(v[2]-u[2])*(x-u[1]*d)
        sigma<0 && return "outside"
        on |= sigma==0
    end
    on ? "on" : "inside"
end
function neighbor_order(s,neighbors,directed,hull_next)
    start = get(hull_next,s,minimum(neighbors))
    order = [start]
    while length(order)<length(neighbors)
        push!(order,directed[(s,order[end])])
    end
    order
end
function outward(points,u,v)
    dx,dy = points[v][1]-points[u][1],points[v][2]-points[u][2]
    reduce_direction(dy,-dx)
end
function bounded_area(site,centers)
    relative = [(x/d-site[1],y/d-site[2]) for (x,y,d) in centers]
    total = 0.0
    for i in eachindex(relative)
        u,w = relative[i]
        next_u,next_w = relative[mod1(i+1,length(relative))]
        total += u*next_w-next_u*w
    end
    total/2
end
function clipped_area(points,s,neighbors)
    polygon = [(0.0,0.0),(1000.0,0.0),(1000.0,1000.0),(0.0,1000.0)]
    xs,ys = points[s]
    for t in neighbors
        xt,yt = points[t]
        c1,c2,c3 = 2*(xt-xs),2*(yt-ys),xt*xt+yt*yt-xs*xs-ys*ys
        clipped = Tuple{Float64,Float64}[]
        for i in eachindex(polygon)
            p,q = polygon[i],polygon[mod1(i+1,length(polygon))]
            fp,fq = c1*p[1]+c2*p[2]-c3,c1*q[1]+c2*q[2]-c3
            fp<=0 && push!(clipped,p)
            if fp<0<fq || fq<0<fp
                lambda = fp/(fp-fq)
                push!(clipped,(p[1]+(q[1]-p[1])*lambda,p[2]+(q[2]-p[2])*lambda))
            end
        end
        polygon = clipped
    end
    total = 0.0
    for i in eachindex(polygon)
        p,q = polygon[i],polygon[mod1(i+1,length(polygon))]
        total += p[1]*q[2]-q[1]*p[2]
    end
    total/2
end
