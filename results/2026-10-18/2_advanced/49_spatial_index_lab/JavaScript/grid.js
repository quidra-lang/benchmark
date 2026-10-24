'use strict';

class Grid {
  constructor(points, world, size) {
    this.size = size;
    this.side = world / size;
    this.cells = [];
    for (let row = 0; row < this.side; row++) {
      for (let column = 0; column < this.side; column++) this.cells.push({ column, row, points: [] });
    }
    for (const point of points) this.insert(point);
  }

  cell(point) {
    return this.cells[Math.floor(point.y / this.size) * this.side + Math.floor(point.x / this.size)];
  }

  insert(point) {
    const cell = this.cell(point);
    cell.points.push(point);
    cell.points.sort((a, b) => a.id - b.id);
  }

  remove(point) {
    const cell = this.cell(point);
    cell.points.splice(cell.points.findIndex(held => held.id === point.id), 1);
  }
}

module.exports = { Grid };
