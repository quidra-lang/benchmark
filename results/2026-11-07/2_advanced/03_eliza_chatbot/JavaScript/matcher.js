function wildcard(element) {
  return element === '*' || element === '#' || element.startsWith('@');
}

function match(pattern, words, groups) {
  const failed = new Set();
  function visit(elementIndex, wordIndex) {
    if (elementIndex === pattern.length) return wordIndex === words.length ? [] : null;
    const key = `${elementIndex}:${wordIndex}`;
    if (failed.has(key)) return null;
    const element = pattern[elementIndex];
    if (element === '*') {
      for (let end = wordIndex; end <= words.length; end += 1) {
        const rest = visit(elementIndex + 1, end);
        if (rest !== null) return [words.slice(wordIndex, end), ...rest];
      }
    } else if (wordIndex < words.length) {
      const accepts = element === '#' || element === words[wordIndex]
        || element.startsWith('@') && groups.get(element.slice(1))?.members.has(words[wordIndex]);
      if (accepts) {
        const rest = visit(elementIndex + 1, wordIndex + 1);
        if (rest !== null) return wildcard(element) ? [[words[wordIndex]], ...rest] : rest;
      }
    }
    failed.add(key);
    return null;
  }
  return visit(0, 0);
}

function covers(previous, pattern, groups) {
  const failed = new Set();
  function accepts(first, second) {
    if (first === '#') return second !== '*';
    if (!first.startsWith('@')) return first === second;
    const members = groups.get(first.slice(1)).members;
    if (second.startsWith('@')) {
      return [...groups.get(second.slice(1)).members].every(word => members.has(word));
    }
    return members.has(second);
  }
  function visit(firstIndex, secondIndex) {
    if (firstIndex === previous.length) return secondIndex === pattern.length;
    const key = `${firstIndex}:${secondIndex}`;
    if (failed.has(key)) return false;
    if (previous[firstIndex] === '*') {
      for (let end = secondIndex; end <= pattern.length; end += 1) {
        if (visit(firstIndex + 1, end)) return true;
      }
    } else if (secondIndex < pattern.length && accepts(previous[firstIndex], pattern[secondIndex])
               && visit(firstIndex + 1, secondIndex + 1)) {
      return true;
    }
    failed.add(key);
    return false;
  }
  return visit(0, 0);
}

module.exports = { wildcard, match, covers };
