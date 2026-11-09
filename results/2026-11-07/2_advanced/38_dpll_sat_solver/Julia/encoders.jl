function queens(n)
    variables = n*n
    clauses = [[(r-1)*n+c for c in 1:n] for r in 1:n]
    for a in 1:variables
        row_a,col_a = divrem(a-1,n)
        for b in a+1:variables
            row_b,col_b = divrem(b-1,n)
            if row_a == row_b || col_a == col_b || abs(row_a-row_b) == abs(col_a-col_b)
                push!(clauses,[-a,-b])
            end
        end
    end
    variables,clauses
end
function pigeon(pigeons,holes)
    clauses = [[(p-1)*holes+h for h in 1:holes] for p in 1:pigeons]
    for p in 1:pigeons, first in 1:holes, second in first+1:holes
        push!(clauses,[-((p-1)*holes+first),-((p-1)*holes+second)])
    end
    for hole in 1:holes, first in 1:pigeons, second in first+1:pigeons
        push!(clauses,[-((first-1)*holes+hole),-((second-1)*holes+hole)])
    end
    pigeons*holes,clauses
end
function coloring(graph,colors)
    vertices = graph[:vertices]
    clauses = [[(v-1)*colors+c for c in 1:colors] for v in 1:vertices]
    for v in 1:vertices, first in 1:colors, second in first+1:colors
        push!(clauses,[-((v-1)*colors+first),-((v-1)*colors+second)])
    end
    for (a,b) in graph[:edges], color in 1:colors
        push!(clauses,[-((a-1)*colors+color),-((b-1)*colors+color)])
    end
    vertices*colors,clauses
end
positions(model,rows,width) = [findfirst(c->model[(row-1)*width+c],1:width) for row in 1:rows]
function queens_symmetries(columns)
    n = length(columns)
    transforms = (
        (r,c)->(r,c),(r,c)->(c,n+1-r),(r,c)->(n+1-r,n+1-c),(r,c)->(n+1-c,r),
        (r,c)->(r,n+1-c),(r,c)->(n+1-r,c),(r,c)->(c,r),(r,c)->(n+1-c,n+1-r)
    )
    result = Tuple[]
    for transform in transforms
        current = zeros(Int,n)
        for (row,column) in enumerate(columns)
            r,c = transform(row,column)
            current[r] = c
        end
        push!(result,Tuple(current))
    end
    result
end
function canonical_coloring(colors)
    numbers = Dict{Int,Int}()
    output = Int[]
    for color in colors
        push!(output,get!(numbers,color,length(numbers)+1))
    end
    Tuple(output)
end
