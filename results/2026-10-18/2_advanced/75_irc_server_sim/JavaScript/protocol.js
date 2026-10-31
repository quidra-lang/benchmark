'use strict';

function fold(text) {
  let result = '';
  for (const character of text) {
    const code = character.charCodeAt(0);
    if (code >= 65 && code <= 90) result += String.fromCharCode(code + 32);
    else if (character === '[') result += '{';
    else if (character === ']') result += '}';
    else if (character === '\\') result += '|';
    else if (character === '^') result += '~';
    else result += character;
  }
  return result;
}

function digits(text) {
  if (text.length === 0) return false;
  for (const character of text) {
    if (character < '0' || character > '9') return false;
  }
  return true;
}

function validNickname(text) {
  const special = '[]\\`_^{|}';
  const firstCharacter = character =>
    (character >= 'A' && character <= 'Z') ||
    (character >= 'a' && character <= 'z') || special.includes(character);
  if (text.length === 0 || !firstCharacter(text[0])) return false;
  for (let index = 1; index < text.length; index++) {
    const character = text[index];
    if (!firstCharacter(character) && character !== '-' &&
        !(character >= '0' && character <= '9')) return false;
  }
  return true;
}

function validChannel(text, maximum) {
  return text.length >= 2 && text.length <= maximum &&
    text[0] === '#' && !text.includes(':');
}

function parse(raw) {
  let position = 0;
  if (raw[0] === ':') {
    position = raw.indexOf(' ');
    if (position < 0) return null;
  }
  while (raw[position] === ' ') position++;
  const start = position;
  while (position < raw.length && raw[position] !== ' ') position++;
  if (position === start) return null;
  const command = raw.slice(start, position).toUpperCase();
  const parameters = [];
  while (position < raw.length) {
    while (raw[position] === ' ') position++;
    if (position === raw.length) break;
    if (raw[position] === ':') {
      parameters.push(raw.slice(position + 1));
      break;
    }
    if (parameters.length === 14) {
      parameters.push(raw.slice(position));
      break;
    }
    const beginning = position;
    while (position < raw.length && raw[position] !== ' ') position++;
    parameters.push(raw.slice(beginning, position));
  }
  return {command, parameters};
}

module.exports = {fold, digits, validNickname, validChannel, parse};
