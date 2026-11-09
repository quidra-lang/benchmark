'use strict';

class Canvas {
    constructor(width, height) {
        this.width = width;
        this.height = height;
        this.cells = Array.from({ length: height }, () => Array(width).fill(' '));
    }

    position(point) {
        const X = point.X === undefined ? point.x : point.X;
        const Y = point.Y === undefined ? point.y : point.Y;
        const D = point.D === undefined ? 1 : point.D;
        return [Math.floor((2 * X * (this.width - 1) + 1000 * D) / (2000 * D)),
            this.height - 1 - Math.floor((2 * Y * (this.height - 1) + 1000 * D) / (2000 * D))];
    }

    point(point, character) {
        const [column, row] = this.position(point);
        this.cells[row][column] = character;
    }

    line(start, end, character) {
        let [x, y] = this.position(start);
        const [x1, y1] = this.position(end);
        const dx = Math.abs(x1 - x), dy = -Math.abs(y1 - y);
        const sx = x < x1 ? 1 : -1, sy = y < y1 ? 1 : -1;
        let error = dx + dy;
        while (true) {
            this.cells[y][x] = character;
            if (x === x1 && y === y1) break;
            const doubled = 2 * error;
            if (doubled >= dy) { error += dy; x += sx; }
            if (doubled <= dx) { error += dx; y += sy; }
        }
    }

    frame() {
        const border = '+' + '-'.repeat(this.width) + '+';
        return [border, ...this.cells.map(row => '|' + row.join('') + '|'), border];
    }
}

function voronoiPlot(width, height, points) {
    const canvas = new Canvas(width, height);
    const owners = Array.from({ length: height }, () => Array(width).fill(0));
    for (let row = 0; row < height; row++) for (let column = 0; column < width; column++) {
        let best = Infinity;
        for (let site = 1; site < points.length; site++) {
            const x = (column * 1000 - points[site].x * (width - 1)) * (height - 1);
            const y = ((height - 1 - row) * 1000 - points[site].y * (height - 1)) * (width - 1);
            const distance = x * x + y * y;
            if (distance < best) { best = distance; owners[row][column] = site; }
        }
    }
    for (let row = 0; row < height; row++) for (let column = 0; column < width; column++)
        if (column < width - 1 && owners[row][column] !== owners[row][column + 1]
            || row < height - 1 && owners[row][column] !== owners[row + 1][column]) canvas.cells[row][column] = '#';
    for (let site = 1; site < points.length; site++) canvas.point(points[site], 'o');
    return canvas.frame();
}

module.exports = { Canvas, voronoiPlot };
