const DIRECTIONS = ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(-1,1),(1,-1))
function path_costs(base,left,width,height,direction,p1,p2,gamma)
    rx,ry = direction
    rows = ry>=0 ? (0:height-1) : (height-1:-1:0)
    columns = rx>=0 ? (0:width-1) : (width-1:-1:0)
    result = zeros(Int,size(base))
    disparities = size(base,2)
    for y in rows,x in columns
        p,qx,qy = y*width+x+1,x-rx,y-ry
        if !(0<=qx<width && 0<=qy<height)
            result[p,:] = base[p,:]
            continue
        end
        q = qy*width+qx+1
        previous = result[q,:]
        smallest = minimum(previous)
        penalty = max(p1,p2*gamma÷(gamma+abs(left[p]-left[q])))
        for d in 1:disparities
            best = min(previous[d],smallest+penalty)
            d>1 && (best=min(best,previous[d-1]+p1))
            d<disparities && (best=min(best,previous[d+1]+p1))
            result[p,d] = base[p,d]+best-smallest
        end
    end
    result
end
function cumulative_costs(base,left,width,height,paths,p1,p2,gamma)
    total,result = zeros(Int,size(base)),Matrix{Int}[]
    for direction in DIRECTIONS[1:paths]
        total += path_costs(base,left,width,height,direction,p1,p2,gamma)
        push!(result,copy(total))
    end
    result
end
