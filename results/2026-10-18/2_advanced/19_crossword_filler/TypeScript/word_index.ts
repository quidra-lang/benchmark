export interface Clue { text: string; number: number; uses: number }
export interface WordEntry { word: string; score: number; line: number; clues: Clue[] }
export type Checked<T> = { error: string } | T;
export const compareText = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
export const validWord = (word: string): boolean => /^[A-Z]{3,15}$/.test(word);
export const validInteger = (text: string, maximum: number): boolean => /^[1-9][0-9]*$/.test(text) && Number(text) <= maximum;
export const rankOrder = (a: WordEntry, b: WordEntry): number => b.score - a.score || compareText(a.word, b.word);
export function checkWordLine(text: string): Checked<{ word: string; score: number }> {
    const fields = text.split(' ');
    if (fields.length !== 2) return { error: 'bad format' };
    if (!validWord(fields[0])) return { error: 'bad word' };
    if (!validInteger(fields[1], 100)) return { error: 'bad score' };
    return { word: fields[0], score: Number(fields[1]) };
}
export function checkClueLine(text: string): Checked<{ word: string; clue: string }> {
    const fields = text.split('|');
    if (fields.length !== 2) return { error: 'bad format' };
    if (!validWord(fields[0])) return { error: 'bad word' };
    const clue = fields[1];
    if (clue.length < 1 || clue.length > 60 || clue.startsWith(' ') || clue.endsWith(' ')) return { error: 'bad clue' };
    return { word: fields[0], clue };
}
export class WordIndex {
    readonly words: WordEntry[];
    readonly byLength = new Map<number, WordEntry[]>();
    readonly byPosition = new Map<string, WordEntry[]>();
    private readonly matches = new Map<string, WordEntry[]>();
    constructor(words: WordEntry[]) {
        this.words = [...words].sort(rankOrder);
        for (const entry of this.words) {
            const length = entry.word.length, collection = this.byLength.get(length) ?? [];
            collection.push(entry); this.byLength.set(length, collection);
            for (let position = 0; position < length; position++) {
                const key = `${length}:${position}:${entry.word[position]}`, entries = this.byPosition.get(key) ?? [];
                entries.push(entry); this.byPosition.set(key, entries);
            }
        }
    }
    candidates(pattern: string, minimum: number, used: ReadonlySet<string>): WordEntry[] {
        const key = `${minimum}:${pattern}`;
        let matching = this.matches.get(key);
        if (!matching) {
            let pool = this.byLength.get(pattern.length) ?? [];
            for (let position = 0; position < pattern.length; position++) if (pattern[position] !== '.') {
                const entries = this.byPosition.get(`${pattern.length}:${position}:${pattern[position]}`) ?? [];
                if (entries.length < pool.length) pool = entries;
            }
            matching = pool.filter(entry => entry.score >= minimum && [...pattern].every((letter, i) => letter === '.' || letter === entry.word[i]));
            if (this.matches.size >= 20000) this.matches.clear();
            this.matches.set(key, matching);
        }
        return matching.filter(entry => !used.has(entry.word));
    }
}
