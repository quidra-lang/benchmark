const words = "listen stone night silent notes apple thing enlist earth onset heart tones".split(" ");
const groups = new Map();
for (const word of words) {
  const key = [...word].sort().join("");
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(word);
}
for (const group of groups.values()) console.log(group.join(" "));
