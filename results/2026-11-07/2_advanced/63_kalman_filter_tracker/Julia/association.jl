function minimum_matching(costs)
    a,b = size(costs)
    (a==0 || b==0) && return Tuple{Int,Int}[]
    flipped = a>b
    matrix = flipped ? permutedims(costs) : costs
    rows,columns = size(matrix)
    u,v = zeros(rows+1),zeros(columns+1)
    matched,previous = zeros(Int,columns+1),zeros(Int,columns+1)
    for row in 1:rows
        matched[1],column = row,1
        distances,used = fill(Inf,columns+1),falses(columns+1)
        while true
            used[column] = true
            current_row = matched[column]
            delta,following = Inf,0
            for candidate in 2:columns+1
                used[candidate] && continue
                reduced = matrix[current_row,candidate-1]-u[current_row+1]-v[candidate]
                if reduced<distances[candidate]
                    distances[candidate],previous[candidate] = reduced,column
                end
                if distances[candidate]<delta
                    delta,following = distances[candidate],candidate
                end
            end
            for candidate in 1:columns+1
                if used[candidate]
                    u[matched[candidate]+1] += delta
                    v[candidate] -= delta
                else
                    distances[candidate] -= delta
                end
            end
            column = following
            matched[column]==0 && break
        end
        while column!=1
            following = previous[column]
            matched[column] = matched[following]
            column = following
        end
    end
    pairs = [(matched[column],column-1) for column in 2:columns+1 if matched[column]!=0]
    sort!(flipped ? [(column,row) for (row,column) in pairs] : pairs)
end
function optimal_assignment(rows,columns,usable)
    (rows==0 || columns==0 || isempty(usable)) && return Tuple{Int,Int}[]
    penalty = (min(rows,columns)+1)*(max(1.0,maximum(values(usable)))+1)
    costs = [get(usable,(row,column),penalty) for row in 1:rows,column in 1:columns]
    [pair for pair in minimum_matching(costs) if haskey(usable,pair)]
end
