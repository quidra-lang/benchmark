const NEIGHBORS = [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]
function directions(gx,gy)
    direction = zeros(Int,size(gx))
    for i in eachindex(gx)
        ax,ay = abs(gx[i]),abs(gy[i])
        direction[i] = 29ay<=12ax ? 0 : 29ay>=70ax ? 90 : gx[i]*gy[i]<0 ? 45 : 135
    end
    direction
end
function suppress(magnitude,direction)
    height,width = size(magnitude)
    offsets = Dict(0=>(-1,0),45=>(1,-1),90=>(0,-1),135=>(-1,-1))
    output = zeros(Int,height,width)
    for y in 1:height-2,x in 1:width-2
        dx,dy = offsets[direction[y+1,x+1]]
        value = magnitude[y+1,x+1]
        if value>magnitude[y+dy+1,x+dx+1] && value>=magnitude[y-dy+1,x-dx+1]
            output[y+1,x+1] = value
        end
    end
    output
end
function hysteresis(nonmax,low,high)
    height,width = size(nonmax)
    strong = Set((x,y) for y in 0:height-1 for x in 0:width-1 if nonmax[y+1,x+1]>=high)
    weak = Set((x,y) for y in 0:height-1 for x in 0:width-1 if low<=nonmax[y+1,x+1]<high)
    edges = copy(strong)
    queue = sort(collect(strong);by=p->(p[2],p[1]))
    cursor = 1
    while cursor<=length(queue)
        x,y = queue[cursor]
        cursor += 1
        for (dx,dy) in NEIGHBORS
            p = (x+dx,y+dy)
            if p in weak && !(p in edges)
                push!(edges,p)
                push!(queue,p)
            end
        end
    end
    edges,strong,weak
end
function components(edges)
    waiting = copy(edges)
    found = Vector{Tuple{Int,Int}}[]
    for start in sort(collect(edges);by=p->(p[2],p[1]))
        start in waiting || continue
        delete!(waiting,start)
        queue = [start]
        cursor = 1
        while cursor<=length(queue)
            x,y = queue[cursor]
            cursor += 1
            for (dx,dy) in NEIGHBORS
                point = (x+dx,y+dy)
                if point in waiting
                    delete!(waiting,point)
                    push!(queue,point)
                end
            end
        end
        push!(found,queue)
    end
    found
end
