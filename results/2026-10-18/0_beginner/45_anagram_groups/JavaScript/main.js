const words = "listen stone night silent notes apple thing enlist earth onset heart tones".split(" ");
const groups = Map.groupBy(words, word => [...word].sort().join(""));
for (const group of groups.values()) console.log(group.join(" "));
