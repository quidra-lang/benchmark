export interface Cell {
  row: number;
  column: number;
}
export function grid(width: number, height: number): string[][] {
  return Array.from({ length: height }, () => Array(width).fill(' '));
}
export function frame(rows: string[][]): string[] {
  const border = '+' + '-'.repeat(rows[0].length) + '+';
  return [border, ...rows.map((row) => '|' + row.join('') + '|'), border];
}
export function biplotCell(
  x: number,
  y: number,
  mx: number,
  my: number,
  width: number,
  height: number,
): Cell {
  return {
    column: Math.min(Math.floor(((x + mx) / (2 * mx)) * width), width - 1),
    row: Math.min(Math.floor(((my - y) / (2 * my)) * height), height - 1),
  };
}
export function diagnosticCell(
  t2: number,
  spe: number,
  mx: number,
  my: number,
  width: number,
  height: number,
): Cell {
  return {
    column: Math.min(Math.floor((t2 / mx) * width), width - 1),
    row: height - 1 - Math.min(Math.floor((spe / my) * height), height - 1),
  };
}
export function shaft(origin: Cell, tip: Cell): (Cell & { character: string })[] {
  const dc = tip.column - origin.column;
  const dr = tip.row - origin.row;
  const steps = Math.max(Math.abs(dc), Math.abs(dr));
  const character =
    2 * Math.abs(dr) <= Math.abs(dc)
      ? '-'
      : 2 * Math.abs(dc) <= Math.abs(dr)
        ? '|'
        : dc * dr < 0
          ? '/'
          : '\\';
  const cells: (Cell & { character: string })[] = [];
  for (let s = 1; s < steps; s++) {
    cells.push({
      column:
        origin.column + Math.sign(dc) * Math.floor((2 * s * Math.abs(dc) + steps) / (2 * steps)),
      row: origin.row + Math.sign(dr) * Math.floor((2 * s * Math.abs(dr) + steps) / (2 * steps)),
      character,
    });
  }
  return cells;
}
export function scree(width: number, bar: number, broken: number, kaiser: number): string {
  let text = '';
  for (let p = 1; p <= width; p++) {
    text += p === broken ? 'o' : p === kaiser ? ':' : p <= bar ? '#' : ' ';
  }
  return text;
}
