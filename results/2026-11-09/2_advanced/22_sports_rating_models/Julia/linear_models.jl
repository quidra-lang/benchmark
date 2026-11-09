function cholesky_solve(matrix::Matrix{Float64}, vector::Vector{Float64})
    size = length(vector)
    lower = zeros(size, size)
    for i in 1:size, j in 1:i
        total = 0.0
        for k in 1:(j - 1)
            total += lower[i, k] * lower[j, k]
        end
        lower[i, j] = j < i ? (matrix[i, j] - total) / lower[j, j] : sqrt(matrix[i, i] - total)
    end
    forward = zeros(size)
    for i in 1:size
        total = 0.0
        for k in 1:(i - 1)
            total += lower[i, k] * forward[k]
        end
        forward[i] = (vector[i] - total) / lower[i, i]
    end
    solution = zeros(size)
    for i in size:-1:1
        total = 0.0
        for k in (i + 1):size
            total += lower[k, i] * solution[k]
        end
        solution[i] = (forward[i] - total) / lower[i, i]
    end
    solution
end
function gaussian_solve!(matrix::Matrix{Float64}, vector::Vector{Float64})
    size = length(vector)
    for k in 1:size
        pivot = k
        for row in (k + 1):size
            abs(matrix[row, k]) > abs(matrix[pivot, k]) && (pivot = row)
        end
        for j in 1:size
            matrix[k, j], matrix[pivot, j] = matrix[pivot, j], matrix[k, j]
        end
        vector[k], vector[pivot] = vector[pivot], vector[k]
        for i in (k + 1):size
            factor = matrix[i, k] / matrix[k, k]
            for j in k:size
                matrix[i, j] -= factor * matrix[k, j]
            end
            vector[i] -= factor * vector[k]
        end
    end
    solution = zeros(size)
    for i in size:-1:1
        total = 0.0
        for j in (i + 1):size
            total += matrix[i, j] * solution[j]
        end
        solution[i] = (vector[i] - total) / matrix[i, i]
    end
    solution
end
function colley_ratings(count::Int, matches::Vector{Match})
    matrix = zeros(count, count)
    balance = zeros(Int, count)
    for team in 1:count
        matrix[team, team] = 2.0
    end
    for game in matches
        matrix[game.home, game.home] += 1
        matrix[game.away, game.away] += 1
        matrix[game.home, game.away] -= 1
        matrix[game.away, game.home] -= 1
        difference = sign(margin(game))
        balance[game.home] += difference
        balance[game.away] -= difference
    end
    cholesky_solve(matrix, [1 + value / 2 for value in balance])
end
function massey_ratings(count::Int, matches::Vector{Match})
    size = count + 1
    matrix = zeros(size, size)
    vector = zeros(size)
    for game in matches
        home, away = game.home, game.away
        matrix[home, home] += 1
        matrix[away, away] += 1
        matrix[home, away] -= 1
        matrix[away, home] -= 1
        matrix[home, size] += 1
        matrix[size, home] += 1
        matrix[away, size] -= 1
        matrix[size, away] -= 1
        matrix[size, size] += 1
        vector[home] += margin(game)
        vector[away] -= margin(game)
        vector[size] += margin(game)
    end
    for k in 1:count
        matrix[count, k] = 1.0
    end
    matrix[count, size] = 0.0
    vector[count] = 0.0
    solution = gaussian_solve!(matrix, vector)
    (solution[1:count], solution[size])
end
