import { collapse, decodeWord, tokenize, type Token } from './headers.ts';

export interface Mailbox {
  kind: 'mailbox';
  name: string;
  address: string;
}
export interface Group {
  kind: 'group';
  members: Mailbox[];
}
export interface AddressList {
  addresses: (Mailbox | Group)[];
  error: boolean;
}
export function addresses(text: string): AddressList | undefined {
  const tokens = tokenize(text, 'address');
  if (!tokens?.length) return undefined;
  let index = 0;
  let error = false;
  const collect = (phrase: boolean): Token[] => {
    const result: Token[] = [];
    while (
      tokens[index]?.kind === 'word' ||
      tokens[index]?.kind === '.' ||
      (phrase && tokens[index]?.kind === 'quoted')
    ) {
      result.push(tokens[index++]);
    }
    return result;
  };
  const validPart = (part: Token[]) =>
    part.length > 0 &&
    part.length % 2 === 1 &&
    part.every((t, i) => t.kind === (i % 2 ? '.' : 'word'));
  const display = (phrase: Token[]): string => {
    let name = '';
    let previousSuccess = false;
    phrase.forEach((token, i) => {
      const decoded =
        token.kind === 'word'
          ? decodeWord(token.text)
          : { text: token.text, success: false, error: false };
      if (i && token.preceded && !(previousSuccess && decoded.success)) name += ' ';
      name += decoded.text;
      previousSuccess = decoded.success;
      error ||= decoded.error;
    });
    return collapse(name);
  };
  const readAddress = (inside: boolean): Mailbox | Group | undefined => {
    const phrase = collect(true);
    if (tokens[index]?.kind === ':' && phrase.length && !inside) {
      index++;
      const members: Mailbox[] = [];
      if (tokens[index]?.kind !== ';') {
        while (true) {
          const member = readAddress(true);
          if (!member || member.kind !== 'mailbox') return undefined;
          members.push(member);
          if (tokens[index]?.kind !== ',') break;
          index++;
        }
      }
      if (tokens[index]?.kind !== ';') return undefined;
      index++;
      return { kind: 'group', members };
    }
    let local: Token[];
    let name = '';
    let angle = false;
    if (tokens[index]?.kind === '<') {
      angle = true;
      index++;
      local = collect(false);
      name = display(phrase);
    } else if (tokens[index]?.kind === '@') local = phrase;
    else return undefined;
    if (!validPart(local) || tokens[index]?.kind !== '@') return undefined;
    index++;
    const domain = collect(false);
    if (!validPart(domain)) return undefined;
    if (angle) {
      if (tokens[index]?.kind !== '>') return undefined;
      index++;
    }
    return {
      kind: 'mailbox',
      name,
      address: (
        local.map((t) => t.text).join('') +
        '@' +
        domain.map((t) => t.text).join('')
      ).toLowerCase(),
    };
  };
  const result: (Mailbox | Group)[] = [];
  while (true) {
    const address = readAddress(false);
    if (!address) return undefined;
    result.push(address);
    if (index === tokens.length) return { addresses: result, error };
    if (tokens[index]?.kind !== ',') return undefined;
    index++;
  }
}
