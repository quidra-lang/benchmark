'use strict';

const compareText = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const validWord = word => /^[A-Z]{3,15}$/.test(word);
const validInteger = (text, maximum) => /^[1-9][0-9]*$/.test(text) && Number(text) <= maximum;
const rankOrder = (a, b) => b.score - a.score || compareText(a.word, b.word);

function checkWordLine(text) {
    const fields = text.split(' ');
    if (fields.length !== 2) return { error: 'bad format' };
    if (!validWord(fields[0])) return { error: 'bad word' };
    if (!validInteger(fields[1], 100)) return { error: 'bad score' };
    return { word: fields[0], score: Number(fields[1]) };
}

function checkClueLine(text) {
    const fields = text.split('|');
    if (fields.length !== 2) return { error: 'bad format' };
    if (!validWord(fields[0])) return { error: 'bad word' };
    const clue = fields[1];
    if (clue.length < 1 || clue.length > 60 || clue.startsWith(' ') || clue.endsWith(' ')) return { error: 'bad clue' };
    return { word: fields[0], clue };
}

class WordIndex {
    constructor(words) {
        this.words = words.slice().sort(rankOrder);
        this.byLength = new Map();
        this.byPosition = new Map();
        this.matches = new Map();
        for (const entry of this.words) {
            const length = entry.word.length;
            if (!this.byLength.has(length)) this.byLength.set(length, []);
            this.byLength.get(length).push(entry);
            for (let position = 0; position < length; position++) {
                const key = `${length}:${position}:${entry.word[position]}`;
                if (!this.byPosition.has(key)) this.byPosition.set(key, []);
                this.byPosition.get(key).push(entry);
            }
        }
    }

    candidates(pattern, minimum, used) {
        const key = minimum + ':' + pattern;
        if (!this.matches.has(key)) {
            let pool = this.byLength.get(pattern.length) ?? [];
            for (let position = 0; position < pattern.length; position++) {
                if (pattern[position] === '.') continue;
                const collection = this.byPosition.get(`${pattern.length}:${position}:${pattern[position]}`) ?? [];
                if (collection.length < pool.length) pool = collection;
            }
            const matching = [];
            for (const entry of pool) {
                if (entry.score < minimum) break;
                let agrees = true;
                for (let position = 0; position < pattern.length; position++) {
                    if (pattern[position] !== '.' && pattern[position] !== entry.word[position]) { agrees = false; break; }
                }
                if (agrees) matching.push(entry);
            }
            if (this.matches.size >= 20000) this.matches.clear();
            this.matches.set(key, matching);
        }
        return this.matches.get(key).filter(entry => !used.has(entry.word));
    }
}

module.exports = { compareText, validWord, validInteger, checkWordLine, checkClueLine, WordIndex };
