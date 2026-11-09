'use strict';

function queens(size) {
    const variables = size * size;
    const clauses = [];
    for (let row = 0; row < size; row++) clauses.push(Array.from({ length: size }, (_, column) => row * size + column + 1));
    for (let first = 1; first <= variables; first++) {
        const row = Math.floor((first - 1) / size);
        const column = (first - 1) % size;
        for (let second = first + 1; second <= variables; second++) {
            const otherRow = Math.floor((second - 1) / size);
            const otherColumn = (second - 1) % size;
            if (row === otherRow || column === otherColumn || Math.abs(row - otherRow) === Math.abs(column - otherColumn)) {
                clauses.push([-first, -second]);
            }
        }
    }
    return { variables, clauses };
}

function pigeon(pigeons, holes) {
    const clauses = [];
    const variable = (pigeon, hole) => (pigeon - 1) * holes + hole;
    for (let pigeon = 1; pigeon <= pigeons; pigeon++) {
        clauses.push(Array.from({ length: holes }, (_, hole) => variable(pigeon, hole + 1)));
    }
    for (let pigeon = 1; pigeon <= pigeons; pigeon++) {
        for (let first = 1; first <= holes; first++) {
            for (let second = first + 1; second <= holes; second++) clauses.push([-variable(pigeon, first), -variable(pigeon, second)]);
        }
    }
    for (let hole = 1; hole <= holes; hole++) {
        for (let first = 1; first <= pigeons; first++) {
            for (let second = first + 1; second <= pigeons; second++) clauses.push([-variable(first, hole), -variable(second, hole)]);
        }
    }
    return { variables: pigeons * holes, clauses };
}

function coloring(graph, colors) {
    const clauses = [];
    const variable = (vertex, color) => (vertex - 1) * colors + color;
    for (let vertex = 1; vertex <= graph.vertices; vertex++) {
        clauses.push(Array.from({ length: colors }, (_, color) => variable(vertex, color + 1)));
    }
    for (let vertex = 1; vertex <= graph.vertices; vertex++) {
        for (let first = 1; first <= colors; first++) {
            for (let second = first + 1; second <= colors; second++) clauses.push([-variable(vertex, first), -variable(vertex, second)]);
        }
    }
    for (const [first, second] of graph.edges) {
        for (let color = 1; color <= colors; color++) clauses.push([-variable(first, color), -variable(second, color)]);
    }
    return { variables: graph.vertices * colors, clauses };
}

function positions(model, rows, width) {
    const result = [];
    for (let row = 0; row < rows; row++) {
        for (let column = 1; column <= width; column++) {
            if (model[row * width + column]) {
                result.push(column);
                break;
            }
        }
    }
    return result;
}

module.exports = { queens, pigeon, coloring, positions };
