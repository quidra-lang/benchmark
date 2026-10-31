const cache: string[] = [];
let hits = 0, misses = 0;
for (const key of "B A C B D A B E A D D C A E B".split(" ")) {
  const index = cache.indexOf(key);
  let result;
  if (index >= 0) {
    hits++;
    cache.splice(index, 1);
    result = "hit";
  } else {
    misses++;
    result = "miss";
    if (cache.length === 3) result += `, evict ${cache.pop()}`;
  }
  cache.unshift(key);
  console.log(`${key}: ${result} [${cache.join(" ")}]`);
}
console.log(`hits: ${hits} misses: ${misses}`);
