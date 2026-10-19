'use strict';

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function strictBase64(text) {
    if (text.length % 4 !== 0) return null;
    let end = text.length;
    while (end > 0 && text[end - 1] === '=') end--;
    if (text.length - end >= 3) return null;
    let bits = 0;
    let value = 0;
    let result = '';
    for (let index = 0; index < end; index++) {
        const digit = BASE64.indexOf(text[index]);
        if (digit < 0) return null;
        value = value * 64 + digit;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            const scale = 2 ** bits;
            result += String.fromCharCode(Math.floor(value / scale));
            value %= scale;
        }
    }
    return result;
}

function base64Body(text) {
    const decoded = strictBase64(text.replace(/[ \t\n]/g, ''));
    if (decoded === null) return null;
    const content = decoded.replace(/\r\n/g, '\n');
    for (const character of content) {
        const value = character.charCodeAt(0);
        if (value !== 9 && value !== 10 && (value < 32 || value > 126)) return null;
    }
    return content;
}

function quotedPrintable(text) {
    const lines = text.split('\n');
    let content = '';
    let error = false;
    for (let row = 0; row < lines.length; row++) {
        let line = lines[row].replace(/[ \t]+$/, '');
        const soft = line.endsWith('=');
        if (soft) line = line.slice(0, -1);
        for (let index = 0; index < line.length;) {
            if (line[index] !== '=') {
                content += line[index++];
                continue;
            }
            const pair = line.slice(index + 1, index + 3);
            if (/^[0-9A-Fa-f]{2}$/.test(pair)) {
                const value = parseInt(pair, 16);
                if (value === 9 || (value >= 32 && value <= 126)) {
                    content += String.fromCharCode(value);
                    index += 3;
                    continue;
                }
            }
            content += '=';
            index++;
            error = true;
        }
        if (!soft && row + 1 < lines.length) content += '\n';
    }
    return { content, error };
}

module.exports = { strictBase64, base64Body, quotedPrintable };
