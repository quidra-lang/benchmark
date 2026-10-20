export type TermKind = 'unigrams' | 'bigrams';
export interface Tokens { raw: number; stopped: number; short: number; unigrams: string[]; pairs: string[]; bigrams: string[] }
export interface Document { tokens: Tokens }
export interface LabelledDocument extends Document { label: number }
export function tokenize(text: string, stopwords: Set<string>): Tokens {
  const words = (text.match(/[A-Za-z0-9]+/g) ?? []).map(w => w.toLowerCase());
  const unigrams: string[] = [], pairs: string[] = [];
  let stopped = 0, short = 0;
  for (const word of words) {
    if (stopwords.has(word)) stopped++;
    else if (word.length === 1) short++;
    else unigrams.push(word);
  }
  for (let i = 1; i < unigrams.length; i++) pairs.push(unigrams[i - 1] + '_' + unigrams[i]);
  return { raw: words.length, stopped, short, unigrams, pairs, bigrams: [...unigrams, ...pairs] };
}
