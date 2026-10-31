'use strict';

const { strictBase64 } = require('./mime');

function strip(text) {
    return text.replace(/^[ \t]+|[ \t]+$/g, '');
}

function words(text) {
    const value = strip(text);
    return value === '' ? [] : value.split(/[ \t]+/);
}

function normalize(text) {
    return strip(text.replace(/[ \t]+/g, ' '));
}

function parseFields(lines) {
    const fields = [];
    const invalid = [];
    let current = null;
    for (const line of lines) {
        if (/^[ \t]/.test(line.text)) {
            if (current !== null) current.value += line.text;
            else invalid.push(line.number);
            continue;
        }
        const colon = line.text.indexOf(':');
        const name = line.text.slice(0, colon);
        if (colon < 1 || !/^[!-~]+$/.test(name)) {
            invalid.push(line.number);
            current = null;
        } else {
            current = { name: name.toLowerCase(), value: line.text.slice(colon + 1) };
            fields.push(current);
        }
    }
    for (const field of fields) field.value = strip(field.value);
    return { fields, invalid };
}

function firstFields(fields) {
    const values = new Map();
    for (const field of fields) if (!values.has(field.name)) values.set(field.name, field.value);
    return values;
}

function removeComments(text) {
    let depth = 0;
    let result = '';
    for (let index = 0; index < text.length; index++) {
        const character = text[index];
        if (depth === 0) {
            if (character === '(') {
                depth = 1;
                result += ' ';
            } else result += character;
        } else if (character === '\\') index++;
        else if (character === '(') depth++;
        else if (character === ')') depth--;
    }
    return depth === 0 ? result : null;
}

function encodedWord(word) {
    const original = { text: word, decoded: false, error: false };
    if (word.length < 4 || !word.startsWith('=?') || !word.endsWith('?=')) return original;
    const pieces = word.slice(2, -2).split('?');
    if (pieces.length !== 3 || pieces.some(piece => piece === '')) return original;
    const [charset, encoding, text] = pieces;
    const failure = { text: word, decoded: false, error: true };
    if (charset.toLowerCase() !== 'us-ascii' || !/^[QBqb]$/.test(encoding)) return failure;
    let decoded = '';
    if (encoding.toLowerCase() === 'b') {
        decoded = strictBase64(text);
        if (decoded === null) return failure;
    } else {
        for (let index = 0; index < text.length; index++) {
            if (text[index] === '_') decoded += ' ';
            else if (text[index] === '=') {
                const pair = text.slice(index + 1, index + 3);
                if (!/^[0-9A-Fa-f]{2}$/.test(pair)) return failure;
                decoded += String.fromCharCode(parseInt(pair, 16));
                index += 2;
            } else decoded += text[index];
        }
    }
    for (const character of decoded) {
        if (character.charCodeAt(0) < 32 || character.charCodeAt(0) > 126) return failure;
    }
    return { text: decoded, decoded: true, error: false };
}

function unstructured(text) {
    let value = '';
    let previousDecoded = false;
    let error = false;
    words(text).forEach((word, index) => {
        const current = encodedWord(word);
        if (index > 0 && !(previousDecoded && current.decoded)) value += ' ';
        value += current.text;
        previousDecoded = current.decoded;
        error ||= current.error;
    });
    return { value: normalize(value), error };
}

const ADDRESS_PUNCTUATION = "!#$%&'*+-/=?^_`{|}~";
const MIME_FORBIDDEN = new Set([40, 41, 60, 62, 64, 44, 59, 58, 92, 34, 47, 91, 93, 63, 61]);

function tokenize(text, variant) {
    const special = variant === 'addresses' ? '<>:;@,.' : '/;=';
    function isWord(character) {
        if (variant === 'addresses') return /^[A-Za-z0-9]$/.test(character) || ADDRESS_PUNCTUATION.includes(character);
        const code = character.charCodeAt(0);
        return code >= 33 && code <= 126 && !MIME_FORBIDDEN.has(code);
    }
    const tokens = [];
    let index = 0;
    let space = false;
    while (index < text.length) {
        const character = text[index];
        if (character === ' ' || character === '\t') {
            space = true;
            index++;
            continue;
        }
        if (character === '(') {
            let depth = 1;
            index++;
            while (index < text.length && depth > 0) {
                if (text[index] === '\\') index += 2;
                else {
                    if (text[index] === '(') depth++;
                    if (text[index] === ')') depth--;
                    index++;
                }
            }
            if (depth !== 0) return null;
            space = true;
            continue;
        }
        let kind;
        let value = '';
        if (character === '"') {
            kind = 'quoted';
            index++;
            let closed = false;
            while (index < text.length) {
                if (text[index] === '"') {
                    index++;
                    closed = true;
                    break;
                }
                if (text[index] === '\\') {
                    index++;
                    if (index === text.length) break;
                }
                value += text[index++];
            }
            if (!closed) return null;
        } else if (special.includes(character)) {
            kind = character;
            value = character;
            index++;
        } else if (isWord(character)) {
            kind = 'word';
            while (index < text.length && isWord(text[index])) value += text[index++];
        } else return null;
        tokens.push({ kind, text: value, space });
        space = false;
    }
    return tokens;
}

function valueWithParameters(text, withSubtype) {
    const tokens = tokenize(text, 'mime');
    if (tokens === null || tokens[0]?.kind !== 'word') return null;
    const type = tokens[0].text.toLowerCase();
    let subtype = '';
    let position = 1;
    if (withSubtype) {
        if (tokens[1]?.kind !== '/' || tokens[2]?.kind !== 'word') return null;
        subtype = tokens[2].text.toLowerCase();
        position = 3;
    }
    const parameters = new Map();
    while (position < tokens.length) {
        if (tokens[position].kind !== ';' || tokens[position + 1]?.kind !== 'word'
            || tokens[position + 2]?.kind !== '='
            || !['word', 'quoted'].includes(tokens[position + 3]?.kind)) return null;
        const name = tokens[position + 1].text.toLowerCase();
        if (!parameters.has(name)) parameters.set(name, tokens[position + 3].text);
        position += 4;
    }
    return { type, subtype, parameters };
}

module.exports = { strip, words, normalize, parseFields, firstFields, removeComments, encodedWord, unstructured, tokenize, valueWithParameters };
