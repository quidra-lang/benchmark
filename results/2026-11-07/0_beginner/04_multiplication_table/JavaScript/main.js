for (let row = 1; row <= 9; row++) {
  console.log(Array.from({ length: 9 }, (_, column) => String(row * (column + 1)).padStart(3)).join(""));
}
