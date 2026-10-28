const LEFT,RIGHT,TOP,BOTTOM = 1,2,3,4
const EDGE_FACES = Dict("left"=>LEFT,"right"=>RIGHT,"top"=>TOP,"bottom"=>BOTTOM)
struct Mesh
    width::Int
    height::Int
    dx::Float64
    thickness::Float64
    count::Int
    codes::Vector{Char}
    neighbors::Matrix{Int}
end
cell(plate,row,column) = row*plate.width+column+1
coordinates(plate,point) = ((point-1)÷plate.width,(point-1)%plate.width)
function read_plate()
    rows = readlines(joinpath("input","plate.txt"))
    words = split(rows[1])
    width,height = parse.(Int,words[1:2])
    neighbors = zeros(Int,width*height,4)
    for r in 0:height-1,c in 0:width-1
        p = r*width+c+1
        neighbors[p,:] = [c>0 ? p-1 : 0,c+1<width ? p+1 : 0,r>0 ? p-width : 0,r+1<height ? p+width : 0]
    end
    Mesh(
        width,
        height,
        parse(Float64,words[3]),
        parse(Float64,words[4]),
        width*height,
        collect(join(rows[2:end])),
        neighbors
    )
end
function segment_faces(plate,edge,start,ending)
    face = EDGE_FACES[edge]
    if edge in ("top","bottom")
        row = edge=="top" ? 0 : plate.height-1
        return [(cell(plate,row,column),face) for column in start:ending]
    end
    column = edge=="left" ? 0 : plate.width-1
    [(cell(plate,row,column),face) for row in start:ending]
end
source_cells(plate,r1,c1,r2,c2) = [cell(plate,r,c) for r in r1:r2 for c in c1:c2]
