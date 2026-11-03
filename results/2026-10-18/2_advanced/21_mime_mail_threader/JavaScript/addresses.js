'use strict';

const { tokenize, encodedWord, normalize } = require('./headers');

class AddressError extends Error {}

function parseAddresses(text) {
    const tokens = tokenize(text, 'addresses');
    if (tokens === null || tokens.length === 0) return null;
    let position = 0;
    let encodedError = false;
    function expect(kind) {
        if (tokens[position]?.kind !== kind) throw new AddressError();
        position++;
    }
    function take(kinds) {
        const result = [];
        while (position < tokens.length && kinds.includes(tokens[position].kind)) result.push(tokens[position++]);
        return result;
    }
    function addressPart(parts) {
        if (parts.length === 0 || parts.length % 2 === 0) throw new AddressError();
        for (let index = 0; index < parts.length; index++) {
            if (parts[index].kind !== (index % 2 === 0 ? 'word' : '.')) throw new AddressError();
        }
        return parts.map(token => token.text).join('');
    }
    function displayName(phrase) {
        let name = '';
        let previousDecoded = false;
        phrase.forEach((token, index) => {
            const current = token.kind === 'word' ? encodedWord(token.text)
                : { text: token.text, decoded: false, error: false };
            if (index > 0 && token.space && !(previousDecoded && current.decoded)) name += ' ';
            name += current.text;
            previousDecoded = current.decoded;
            encodedError ||= current.error;
        });
        return normalize(name);
    }
    function address(inGroup) {
        const phrase = take(['word', 'quoted', '.']);
        const next = tokens[position]?.kind;
        if (next === ':' && phrase.length > 0 && !inGroup) {
            position++;
            const mailboxes = [];
            if (tokens[position]?.kind !== ';') {
                mailboxes.push(address(true));
                while (tokens[position]?.kind === ',') {
                    position++;
                    mailboxes.push(address(true));
                }
            }
            expect(';');
            return { group: true, mailboxes };
        }
        let local;
        let domain;
        let name = '';
        if (next === '<') {
            position++;
            local = addressPart(take(['word', '.']));
            expect('@');
            domain = addressPart(take(['word', '.']));
            expect('>');
            name = displayName(phrase);
        } else if (next === '@') {
            local = addressPart(phrase);
            position++;
            domain = addressPart(take(['word', '.']));
        } else throw new AddressError();
        return { group: false, address: `${local}@${domain}`.toLowerCase(), name };
    }
    try {
        const addresses = [address(false)];
        while (tokens[position]?.kind === ',') {
            position++;
            addresses.push(address(false));
        }
        if (position !== tokens.length) return null;
        return { addresses, encodedError };
    } catch (error) {
        if (error instanceof AddressError) return null;
        throw error;
    }
}

module.exports = { parseAddresses };
