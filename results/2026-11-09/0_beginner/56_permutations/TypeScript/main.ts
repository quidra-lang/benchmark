const letters = "ABCD", used = Array<boolean>(4).fill(false);
let count = 0;

function visit(prefix: string): void {
  if (prefix.length === letters.length) {
    console.log(`${++count}: ${prefix}`);
    return;
  }
  for (let i = 0; i < letters.length; i++) {
    if (!used[i]) {
      used[i] = true;
      visit(prefix + letters[i]);
      used[i] = false;
    }
  }
}

visit("");
