func queens(_ size: Int) -> Formula {
    let variables = size * size
    var clauses = (0..<size).map { row in (1...size).map { row * size + $0 } }
    for first in 1...variables {
        let firstRow = (first - 1) / size
        let firstColumn = (first - 1) % size
        for second in (first + 1)..<(variables + 1) {
            let secondRow = (second - 1) / size
            let secondColumn = (second - 1) % size
            if firstRow == secondRow || firstColumn == secondColumn
                || abs(firstRow - secondRow) == abs(firstColumn - secondColumn) {
                clauses.append([-first, -second])
            }
        }
    }
    return Formula(variables: variables, clauses: clauses)
}

func pigeon(_ pigeons: Int, _ holes: Int) -> Formula {
    var clauses = (0..<pigeons).map { pigeon in (1...holes).map { pigeon * holes + $0 } }
    for pigeon in 0..<pigeons {
        for first in 1...holes {
            for second in (first + 1)..<(holes + 1) { clauses.append([-(pigeon * holes + first), -(pigeon * holes + second)]) }
        }
    }
    for hole in 1...holes {
        for first in 0..<pigeons {
            for second in (first + 1)..<pigeons { clauses.append([-(first * holes + hole), -(second * holes + hole)]) }
        }
    }
    return Formula(variables: pigeons * holes, clauses: clauses)
}

func coloring(_ graph: Graph, _ colors: Int) -> Formula {
    var clauses = (0..<graph.vertices).map { vertex in (1...colors).map { vertex * colors + $0 } }
    for vertex in 0..<graph.vertices {
        for first in 1...colors {
            for second in (first + 1)..<(colors + 1) { clauses.append([-(vertex * colors + first), -(vertex * colors + second)]) }
        }
    }
    for edge in graph.edges {
        for color in 1...colors { clauses.append([-((edge.first - 1) * colors + color), -((edge.second - 1) * colors + color)]) }
    }
    return Formula(variables: graph.vertices * colors, clauses: clauses)
}

func positions(_ model: [Bool], _ rows: Int, _ width: Int) -> [Int] {
    (0..<rows).map { row in (1...width).first { model[row * width + $0] }! }
}
