const board = [
  "MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
  "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"
];
const directions = [
  {name: "E", dr: 0, dc: 1}, {name: "SE", dr: 1, dc: 1},
  {name: "S", dr: 1, dc: 0}, {name: "SW", dr: 1, dc: -1},
  {name: "W", dr: 0, dc: -1}, {name: "NW", dr: -1, dc: -1},
  {name: "N", dr: -1, dc: 0}, {name: "NE", dr: -1, dc: 1}
];

function find(word) {
  for (let row = 0; row < board.length; row++) {
    for (let column = 0; column < board[0].length; column++) {
      for (const {name, dr, dc} of directions) {
        const matches = [...word].every((char, i) => {
          const r = row + dr * i, c = column + dc * i;
          return r >= 0 && r < board.length && c >= 0 && c < board[0].length && board[r][c] === char;
        });
        if (matches) return `(${row}, ${column}) ${name}`;
      }
    }
  }
  return "not found";
}

for (const word of ["TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"]) {
  console.log(`${word}: ${find(word)}`);
}
