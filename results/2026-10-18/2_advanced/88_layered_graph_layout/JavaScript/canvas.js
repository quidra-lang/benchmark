'use strict';

class Canvas {
  constructor(direction, mainLength, secondaryLength) {
    this.direction = direction;
    this.mainLength = mainLength;
    this.vertical = direction === 'TB' || direction === 'BT';
    this.rows = this.vertical ? mainLength : secondaryLength;
    this.columns = this.vertical ? secondaryLength : mainLength;
    this.lines = new Uint8Array(this.rows * this.columns);
    this.arrows = Array(this.lines.length).fill('');
    this.boxes = Array(this.lines.length).fill('');
    this.highlighted = new Uint8Array(this.lines.length);
  }

  map(main, secondary) {
    const m = this.direction === 'BT' || this.direction === 'RL' ? this.mainLength - 1 - main : main;
    return this.vertical ? [m, secondary] : [secondary, m];
  }

  index(main, secondary) {
    const [row, column] = this.map(main, secondary);
    return row * this.columns + column;
  }

  line(main, secondary, character) {
    this.lines[this.index(main, secondary)] |= character === '|' ? 1 : character === '-' ? 2 : 4;
  }

  mainLine(first, last, secondary) {
    for (let main = first; main <= last; main++) this.line(main, secondary, this.vertical ? '|' : '-');
  }

  bent(first, length, offset, upper, lower) {
    this.mainLine(first, first + offset - 1, upper);
    this.line(first + offset, upper, '+');
    this.line(first + offset, lower, '+');
    for (let secondary = Math.min(upper, lower) + 1; secondary < Math.max(upper, lower); secondary++) {
      this.line(first + offset, secondary, this.vertical ? '-' : '|');
    }
    this.mainLine(first + offset + 1, first + length - 1, lower);
  }

  arrow(main, secondary, reversed) {
    const normal = {TB: 'v', BT: '^', LR: '>', RL: '<'};
    const backward = {TB: '^', BT: 'v', LR: '<', RL: '>'};
    this.arrows[this.index(main, secondary)] = (reversed ? backward : normal)[this.direction];
  }

  highlight(route) {
    for (let i = 1; i < route.length; i++) {
      let [row, column] = route[i - 1];
      const [endRow, endColumn] = route[i];
      const rowStep = Math.sign(endRow - row);
      const columnStep = Math.sign(endColumn - column);
      while (true) {
        this.highlighted[row * this.columns + column] = 1;
        if (row === endRow && column === endColumn) break;
        row += rowStep;
        column += columnStep;
      }
    }
  }

  box(row, column, text) {
    for (let i = 0; i < text.length; i++) this.boxes[row * this.columns + column + i] = text[i];
  }

  crossingCells() {
    let count = 0;
    for (const kinds of this.lines) if ((kinds & 3) === 3) count++;
    return count;
  }

  render() {
    let ruler = '    ';
    for (let column = 0; column < this.columns; column++) ruler += column % 10;
    const result = [ruler];
    for (let row = 0; row < this.rows; row++) {
      let text = String(row).padStart(3, ' ') + ' ';
      for (let column = 0; column < this.columns; column++) {
        const index = row * this.columns + column;
        const kinds = this.lines[index];
        let character = kinds === 0 ? ' ' : kinds === 1 ? '|' : kinds === 2 ? '-' : '+';
        if (this.highlighted[index]) character = '#';
        if (this.arrows[index] !== '') character = this.arrows[index];
        if (this.boxes[index] !== '') character = this.boxes[index];
        text += character;
      }
      result.push(text.replace(/ +$/, ''));
    }
    return result;
  }
}

module.exports = {Canvas};
