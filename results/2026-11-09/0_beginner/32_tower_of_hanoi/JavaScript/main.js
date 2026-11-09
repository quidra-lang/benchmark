function hanoi(n, source, target, auxiliary) {
  if (n === 0) return 0;
  const count = hanoi(n - 1, source, auxiliary, target);
  console.log(`move disk ${n} from ${source} to ${target}`);
  return count + 1 + hanoi(n - 1, auxiliary, target, source);
}

const moves = hanoi(4, "A", "C", "B");
console.log(`total moves: ${moves}`);
