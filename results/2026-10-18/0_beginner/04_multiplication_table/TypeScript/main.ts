for (let row = 1; row <= 9; row++) {
  const products: string[] = [];
  for (let column = 1; column <= 9; column++) {
    products.push(String(row * column).padStart(3, " "));
  }
  console.log(products.join(""));
}
