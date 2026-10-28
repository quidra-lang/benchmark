mutable struct GridCell
    column::Int
    row::Int
    box::NTuple{4,Int}
    points::Vector{Vector{Int}}
end
struct UniformGrid
    world::Int
    cell_size::Int
    side::Int
    cells::Vector{GridCell}
end
grid_position(grid,p) = (p[2]÷grid.cell_size,p[3]÷grid.cell_size)
function grid_cell(grid,p)
    c,r = grid_position(grid,p)
    grid.cells[r*grid.side+c+1]
end
function grid_insert!(grid,p)
    cell = grid_cell(grid,p)
    push!(cell.points,p)
    sort!(cell.points;by=first)
end
grid_delete!(grid,p) = filter!(q->q[1]!=p[1],grid_cell(grid,p).points)
function UniformGrid(world,cell_size,points)
    side = world÷cell_size
    cells = GridCell[]
    for r in 0:side-1,c in 0:side-1
        x,y = c*cell_size,r*cell_size
        push!(cells,GridCell(c,r,(x,y,x+cell_size-1,y+cell_size-1),Vector{Int}[]))
    end
    grid = UniformGrid(world,cell_size,side,cells)
    for p in points
        grid_insert!(grid,p)
    end
    grid
end
