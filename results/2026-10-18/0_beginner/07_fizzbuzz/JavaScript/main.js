for (let n = 1; n <= 30; n++) {
  const text = (n % 3 === 0 ? "Fizz" : "") + (n % 5 === 0 ? "Buzz" : "");
  console.log(text || n);
}
