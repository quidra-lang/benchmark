'use strict';

function tokenize(text, stopwords) {
    const words = (text.match(/[A-Za-z0-9]+/g) ?? []).map(word => word.toLowerCase());
    const unigrams = [];
    let stopped = 0;
    let short = 0;
    for (const word of words) {
        if (stopwords.has(word)) stopped++;
        else if (word.length === 1) short++;
        else unigrams.push(word);
    }
    const pairs = [];
    for (let i = 1; i < unigrams.length; i++) pairs.push(unigrams[i - 1] + '_' + unigrams[i]);
    return { raw: words.length, stopped, short, unigrams, pairs, bigrams: [...unigrams, ...pairs] };
}

module.exports = { tokenize };
