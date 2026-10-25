class SyntaxFault extends Error {
  declare position: any;
  constructor(position) { super('syntax error'); this.position = position; }
}

const KEYWORDS = new Set('BEGIN END function if else while for do break continue next exit return delete in getline print printf'.split(' '));
const BUILTINS = new Set('length substr index split sprintf toupper tolower close int'.split(' '));
const PAIRS = new Set('+= -= *= /= %= ^= == <= >= != ++ -- && || >>'.split(' '));
const ESCAPES = { n: '\n', t: '\t', '\\': '\\', '"': '"', '/': '/' };
const letter = character => character !== undefined && /[A-Za-z_]/.test(character);
const digit = character => character !== undefined && character >= '0' && character <= '9';

function tokenize(source) {
  const tokens = [];
  let index = 0, line = 1, column = 1;
  const advance = () => { if (source[index++] === '\n') { line++; column = 1; } else column++; };
  const append = (kind, text, position, value = text) => tokens.push({ kind, text, position, value });
  while (index < source.length) {
    const position = { line, column }, start = index, character = source[index], pair = source.slice(index, index + 2);
    if (character === ' ') { advance(); continue; }
    if (pair === '\\\n') { advance(); advance(); continue; }
    if (character === '#') { while (index < source.length && source[index] !== '\n') advance(); continue; }
    if (character === '\n') { append('newline', '\n', position); advance(); continue; }
    if (digit(character)) {
      while (digit(source[index])) advance();
      const text = source.slice(start, index); append('number', text, position, Number(text)); continue;
    }
    if (letter(character)) {
      while (letter(source[index]) || digit(source[index])) advance();
      const text = source.slice(start, index);
      const kind = KEYWORDS.has(text) ? 'keyword' : BUILTINS.has(text) ? 'builtin' : source[index] === '(' ? 'function' : 'name';
      append(kind, text, position); continue;
    }
    if (character === '"') {
      advance(); let value = '';
      while (index < source.length && source[index] !== '"') {
        if (source[index] === '\n') throw new SyntaxFault(position);
        if (source[index] === '\\') {
          if (!Object.hasOwn(ESCAPES, source[index + 1])) throw new SyntaxFault({ line, column });
          value += ESCAPES[source[index + 1]]; advance(); advance();
        } else { value += source[index]; advance(); }
      }
      if (index === source.length) throw new SyntaxFault(position);
      advance(); append('string', source.slice(start, index), position, value); continue;
    }
    if (PAIRS.has(pair)) { append('symbol', pair, position); advance(); advance(); continue; }
    if ('+-*/%^!><?:=()[]{} ,;$'.includes(character)) { append('symbol', character, position); advance(); continue; }
    throw new SyntaxFault(position);
  }
  append('eof', '', { line, column: 1 }); return tokens;
}

export { SyntaxFault, tokenize };
