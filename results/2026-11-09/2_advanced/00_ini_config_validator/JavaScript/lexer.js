function segment(quoted) {
  return { quoted, text: '', literals: new Set() };
}

function logicalLines(text) {
  const physical = text.split('\n').slice(0, -1);
  const result = [];
  for (let row = 0; row < physical.length; row++) {
    const line = row + 1;
    const segments = [segment(false)];
    let current = segments[0], source = physical[row], position = 0;
    let inside = false, error = null;
    while (position < source.length) {
      const character = source[position];
      if (character === '\\' && position + 1 === source.length) {
        source = physical[++row].replace(/^ +/, '');
        position = 0;
        continue;
      }
      if (!inside && (character === ';' || character === '#')) break;
      if (character === '"') {
        inside = !inside;
        current = segment(inside);
        segments.push(current);
        position++;
        continue;
      }
      if (inside && character === '\\') {
        const escaped = source[position + 1];
        const replacements = { '\\': '\\', '"': '"', n: '\n', t: '\t', $: '$' };
        if (Object.hasOwn(replacements, escaped)) {
          if (escaped === '$') current.literals.add(current.text.length);
          current.text += replacements[escaped];
        } else if (error === null) {
          error = { code: 'E_ESCAPE', message: `invalid escape sequence \\${escaped}` };
        }
        position += 2;
      } else {
        current.text += character;
        position++;
      }
    }
    if (inside && error === null) error = { code: 'E_UNTERMINATED', message: 'unterminated string' };
    result.push({ line, segments, error });
  }
  return result;
}

module.exports = { logicalLines };
