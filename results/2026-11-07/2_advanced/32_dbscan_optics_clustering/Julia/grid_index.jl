squared_distance(a,b) = (a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y)
struct GridIndex
    points::Vector{Point}
    eps::Int
    cells::Dict{Tuple{Int,Int},Vector{Int}}
end
function GridIndex(points,eps)
    cells = Dict{Tuple{Int,Int},Vector{Int}}()
    for (i,p) in enumerate(points)
        push!(get!(()->Int[],cells,(p.x÷eps,p.y÷eps)),i)
    end
    GridIndex(points,eps,cells)
end
function neighborhood(grid,index)
    p = grid.points[index]
    column,row = p.x÷grid.eps,p.y÷grid.eps
    neighbors = Int[]
    candidates = 0
    for gy in (row-1):(row+1),gx in (column-1):(column+1)
        for other in get(grid.cells,(gx,gy),Int[])
            candidates += 1
            squared_distance(p,grid.points[other]) <= grid.eps*grid.eps && push!(neighbors,other)
        end
    end
    neighbors,candidates
end
function busiest_cell(grid)
    cells = collect(keys(grid.cells))
    gx,gy = cells[argmin([(-length(grid.cells[cell]),cell[2],cell[1]) for cell in cells])]
    gx,gy,length(grid.cells[(gx,gy)])
end
brute_force_counts(points,eps) = [count(q->squared_distance(p,q) <= eps*eps,points) for p in points]
