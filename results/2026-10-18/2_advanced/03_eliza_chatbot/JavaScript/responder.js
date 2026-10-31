function reflect(words, substitutions) {
  return words.flatMap(word => substitutions.get(word)?.replacement ?? [word]);
}

function buildReply(template, bindings, substitutions) {
  let text = template.replace(/\(([0-9])\)/g, (reference, digit) => {
    const binding = bindings[Number(digit) - 1] ?? [];
    return reflect(binding, substitutions).join(' ');
  });
  text = text.split(' ').filter(word => word !== '').join(' ');
  if (/^[a-z]/.test(text)) text = text[0].toUpperCase() + text.slice(1);
  return text;
}

function restate(arguments_, bindings) {
  const words = [];
  for (const argument of arguments_) {
    if (/^\([0-9]\)$/.test(argument)) {
      words.push(...(bindings[Number(argument[1]) - 1] ?? []));
    } else {
      words.push(argument);
    }
  }
  return words;
}

function wrapReply(text) {
  const words = text.split(' ').filter(word => word !== '');
  if (words.length === 0) return ['ELIZA:'];
  const lines = [];
  let line = `ELIZA: ${words[0]}`;
  for (const word of words.slice(1)) {
    if (line.length + 1 + word.length <= 72) {
      line += ` ${word}`;
    } else {
      lines.push(line);
      line = `       ${word}`;
    }
  }
  lines.push(line);
  return lines;
}

module.exports = { reflect, buildReply, restate, wrapReply };
