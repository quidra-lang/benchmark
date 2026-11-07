'use strict';

const fs = require('node:fs');
const { firstAsymmetry, componentCount } = require('./grid');
const { runs, shortRun, extractSlots } = require('./slots');
const { compareText, validWord, validInteger, checkWordLine, checkClueLine, WordIndex } = require('./word_index');
const { slotPattern, attempt } = require('./filler');
const { decimal, gridLines, numberDiagram, listLine } = require('./render');

const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const letterPoints = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10];
const readLines = name => fs.readFileSync('input/' + name, 'utf8').split('\n').slice(0, -1);
const orDash = (values, separator = ' ') => values.length === 0 ? '-' : values.join(separator);

function readSettings() {
    const settings = {};
    for (const line of readLines('params.txt')) {
        if (line === '' || line.startsWith('#')) continue;
        const [key, value] = line.split(' ');
        settings[key] = key === 'symmetry' ? value : Number(value);
    }
    return settings;
}

function readWords() {
    const lines = readLines('words.txt');
    const byWord = new Map();
    const invalid = [];
    const duplicates = [];
    for (let i = 0; i < lines.length; i++) {
        const parsed = checkWordLine(lines[i]);
        if (parsed.error) {
            invalid.push({ line: i + 1, reason: parsed.error });
        } else if (byWord.has(parsed.word)) {
            duplicates.push({ line: i + 1, word: parsed.word, first: byWord.get(parsed.word).line });
        } else {
            byWord.set(parsed.word, { ...parsed, line: i + 1, clues: [] });
        }
    }
    return { lineCount: lines.length, byWord, invalid, duplicates, index: new WordIndex([...byWord.values()]) };
}

function readClues(dictionary) {
    const lines = readLines('clues.txt');
    const result = { entries: 0, valid: 0, invalid: [], unknown: [] };
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line === '' || line.startsWith('#')) continue;
        result.entries++;
        const parsed = checkClueLine(line);
        if (parsed.error) {
            result.invalid.push({ line: i + 1, reason: parsed.error });
        } else if (!dictionary.byWord.has(parsed.word)) {
            result.unknown.push({ line: i + 1, word: parsed.word });
        } else {
            const entry = dictionary.byWord.get(parsed.word);
            entry.clues.push({ text: parsed.clue, number: entry.clues.length + 1, uses: 0 });
            result.valid++;
        }
    }
    result.words = dictionary.index.words.filter(entry => entry.clues.length > 0).length;
    return result;
}

function readTemplates() {
    const blocks = [];
    let current = null;
    for (const line of readLines('templates.txt')) {
        if (current === null) {
            if (line === '' || line.startsWith('#')) continue;
            current = { name: line.slice(9), rows: [], options: [] };
        } else if (line === 'END') {
            blocks.push(current);
            current = null;
        } else if (line.includes(' ')) {
            current.options.push(line);
        } else {
            current.rows.push(line);
        }
    }
    return blocks;
}

function templateOptions(block, defaults) {
    const settings = { ...defaults };
    const seen = new Set();
    const themes = [];
    for (let i = 0; i < block.options.length; i++) {
        const line = block.options[i];
        const space = line.indexOf(' ');
        const key = line.slice(0, space);
        const value = line.slice(space + 1);
        let valid = false;
        if (key === 'theme') {
            valid = validWord(value) && !themes.includes(value);
            if (valid) themes.push(value);
        } else if (!seen.has(key)) {
            if (key === 'node_budget') valid = validInteger(value, 100000);
            if (key === 'min_score') valid = validInteger(value, 100);
            if (key === 'symmetry') valid = ['rot180', 'mirror', 'none'].includes(value);
            if (valid) settings[key] = key === 'symmetry' ? value : Number(value);
        }
        if (!valid) return { error: 'bad option ' + (i + 1) };
        seen.add(key);
    }
    return { settings, themes };
}

function placeThemes(template, dictionary) {
    const initial = { cells: template.rows.join('').split(''), assigned: template.slots.map(() => null), used: new Set() };
    const themeSlots = new Set();
    for (let k = 0; k < template.themeWords.length; k++) {
        const word = template.themeWords[k];
        if (!dictionary.byWord.has(word)) return 'unknown theme ' + (k + 1);
        let chosen = null;
        for (const slot of template.slots) {
            if (initial.assigned[slot.index] !== null || slot.length !== word.length) continue;
            let matches = true;
            for (let i = 0; i < slot.length; i++) {
                const cell = initial.cells[slot.cells[i]];
                if (cell !== '.' && cell !== word[i]) { matches = false; break; }
            }
            if (matches) { chosen = slot; break; }
        }
        if (chosen === null) return 'theme ' + (k + 1) + ' does not fit';
        initial.assigned[chosen.index] = dictionary.byWord.get(word);
        initial.used.add(word);
        for (let i = 0; i < chosen.length; i++) initial.cells[chosen.cells[i]] = word[i];
        themeSlots.add(chosen.index);
    }
    template.initial = initial;
    template.themeSlots = themeSlots;
    return null;
}

function checkTemplate(block, defaults, dictionary, names) {
    const duplicate = names.has(block.name);
    names.add(block.name);
    if (!/^[a-z0-9_]{1,20}$/.test(block.name)) return { ...block, error: 'bad name' };
    if (duplicate) return { ...block, error: 'duplicate name' };
    const options = templateOptions(block, defaults);
    if (options.error) return { ...block, error: options.error };
    const rows = block.rows;
    const h = rows.length;
    if (h < 3 || h > 15) return { ...block, error: 'bad height' };
    const w = rows[0].length;
    for (let r = 0; r < h; r++) {
        if (rows[r].length < 3 || rows[r].length > 15 || rows[r].length !== w || !/^[.#A-Z]+$/.test(rows[r])) {
            return { ...block, error: 'bad row ' + (r + 1) };
        }
    }
    if (options.settings.symmetry !== 'none') {
        const cell = firstAsymmetry(rows, options.settings.symmetry);
        if (cell !== null) return { ...block, error: `asymmetric at ${cell.r + 1},${cell.c + 1}` };
    }
    const components = componentCount(rows);
    if (components !== 1) return { ...block, error: 'disconnected components=' + components };
    const allRuns = runs(rows);
    const short = shortRun(allRuns);
    if (short !== null) {
        return { ...block, error: `short slot at ${short.r + 1},${short.c + 1} ${short.axis === 'A' ? 'across' : 'down'}` };
    }
    const extracted = extractSlots(rows, allRuns);
    for (let r = 0; r < h; r++) {
        for (let c = 0; c < w; c++) {
            if (rows[r][c] !== '#' && extracted.membership[r * w + c].length === 0) {
                return { ...block, error: `orphan cell ${r + 1},${c + 1}` };
            }
        }
    }
    const template = { ...block, h, w, ...extracted, settings: options.settings, themeWords: options.themes };
    const error = placeThemes(template, dictionary);
    if (error !== null) template.error = error;
    return template;
}

function fillTemplate(template, index, relaxStep) {
    const attempts = [];
    let minimum = template.settings.min_score;
    for (;;) {
        const search = attempt(template.initial, template.slots, index, minimum, template.settings.node_budget);
        attempts.push(search);
        if (search.outcome === 'filled' || relaxStep === 0 || minimum === 1) break;
        minimum = Math.max(minimum - relaxStep, 1);
    }
    template.attempts = attempts;
    template.finalAttempt = attempts.at(-1);
    template.outcome = template.finalAttempt.outcome;
    template.final = template.finalAttempt.final;
}

function templateStatistics(template, index) {
    let blocks = 0;
    let givens = 0;
    for (const row of template.rows) {
        for (const cell of row) {
            if (cell === '#') blocks++;
            else if (cell !== '.') givens++;
        }
    }
    const white = template.w * template.h - blocks;
    const symmetries = ['rot180', 'mirror'].filter(kind => firstAsymmetry(template.rows, kind) === null);
    const lengthCounts = new Map();
    let across = 0;
    let totalLength = 0;
    let longest = 0;
    for (const slot of template.slots) {
        if (slot.axis === 'A') across++;
        totalLength += slot.length;
        longest = Math.max(longest, slot.length);
        lengthCounts.set(slot.length, (lengthCounts.get(slot.length) ?? 0) + 1);
    }
    const lengths = [...lengthCounts.keys()].sort((a, b) => a - b);
    const supply = lengths.map(length => [length,
        (index.byLength.get(length) ?? []).filter(entry => entry.score >= template.settings.min_score).length]);
    const tightest = [];
    for (const slot of template.slots) {
        if (template.themeSlots.has(slot.index)) continue;
        const count = index.candidates(slotPattern(slot, template.initial), template.settings.min_score, template.initial.used).length;
        tightest.push({ slot, count });
    }
    tightest.sort((a, b) => a.count - b.count || a.slot.index - b.slot.index);
    const hotspots = template.slots.map(slot => ({ slot, count: template.finalAttempt.failures[slot.index] }))
        .filter(item => item.count > 0).sort((a, b) => b.count - a.count || a.slot.index - b.slot.index).slice(0, 3);
    return { blocks, white, givens, symmetries, across, down: template.slots.length - across,
        lengthCounts, lengths, totalLength, longest, supply, tightest: tightest.slice(0, 3), hotspots,
        unchecked: template.membership.filter(slots => slots.length === 1).length };
}

function filledQuality(template, weakScore) {
    const state = template.final;
    let total = 0;
    let weakest = template.slots[0];
    const weak = [];
    for (const slot of template.slots) {
        const word = state.assigned[slot.index];
        total += word.score;
        if (word.score < state.assigned[weakest.index].score) weakest = slot;
        if (word.score < weakScore) weak.push(slot);
    }
    const letters = new Set();
    let points = 0;
    let crossing = null;
    for (let r = 0; r < template.h; r++) {
        for (let c = 0; c < template.w; c++) {
            const cell = r * template.w + c;
            const letter = state.cells[cell];
            if (letter === '#') continue;
            letters.add(letter);
            points += letterPoints[letter.charCodeAt(0) - 65];
            const members = template.membership[cell];
            if (members.length !== 2) continue;
            const across = template.slots[members.find(index => template.slots[index].axis === 'A')];
            const down = template.slots[members.find(index => template.slots[index].axis === 'D')];
            const score = state.assigned[across.index].score + state.assigned[down.index].score;
            if (crossing === null || score < crossing.score) crossing = { r: r + 1, c: c + 1, across, down, score };
        }
    }
    return { total, weakest, weak, distinct: letters.size, missing: [...alphabet].filter(letter => !letters.has(letter)).join(''),
        points, crossing };
}

function partialStatus(template, index) {
    const state = template.final;
    const blocked = [];
    let assigned = 0;
    for (const slot of template.slots) {
        if (state.assigned[slot.index] !== null) assigned++;
        else if (index.candidates(slotPattern(slot, state), template.finalAttempt.minimum, state.used).length === 0) blocked.push(slot.label);
    }
    return { assigned, letters: state.cells.filter(cell => cell !== '#' && cell !== '.').length, blocked };
}

function chooseClues(template) {
    const lines = ['TEMPLATE ' + template.name];
    let clued = 0;
    let missing = 0;
    let unfilled = 0;
    for (const axis of ['A', 'D']) {
        const slots = template.slots.filter(slot => slot.axis === axis);
        if (slots.length === 0) continue;
        lines.push(axis === 'A' ? 'ACROSS' : 'DOWN');
        for (const slot of slots) {
            const word = template.final.assigned[slot.index];
            let chosen = null;
            if (word === null) {
                unfilled++;
            } else if (word.clues.length === 0) {
                missing++;
            } else {
                chosen = word.clues[0];
                for (const clue of word.clues) if (clue.uses < chosen.uses) chosen = clue;
                chosen.uses++;
                clued++;
            }
            lines.push(listLine(slot, word, chosen === null ? null : chosen.text,
                slotPattern(slot, template.final), template.themeSlots.has(slot.index)));
        }
    }
    lines.push(`clued=${clued} missing=${missing} unfilled=${unfilled}`);
    return lines;
}

function slotDescription(template, slot) {
    const entry = template.final.assigned[slot.index];
    return `${slot.label}:${entry.word}:${entry.score}`;
}

function gridParagraph(template) {
    const lines = ['TEMPLATE ' + template.name];
    if (template.error) return [...lines, 'error ' + template.error];
    lines.push(`outcome=${template.outcome} attempts=${template.attempts.length} min_score=${template.finalAttempt.minimum}`);
    return [...lines, ...gridLines(template, template.final), 'numbers', ...numberDiagram(template)];
}

function searchParagraph(template) {
    const stats = template.stats;
    const final = template.finalAttempt;
    const total = template.slots.length;
    const lines = ['TEMPLATE ' + template.name];
    lines.push(`grid size=${template.w}x${template.h} blocks=${stats.blocks} white=${stats.white}` +
        ` density=${decimal(100 * stats.blocks, template.w * template.h, 1)} givens=${stats.givens}` +
        ` required=${template.settings.symmetry} symmetry=${stats.symmetries.length === 0 ? 'none' : stats.symmetries.join(',')}`);
    const lengths = stats.lengths.map(length => length + ':' + stats.lengthCounts.get(length)).join(',');
    lines.push(`slots across=${stats.across} down=${stats.down} total=${total} lengths=${lengths}` +
        ` avg_length=${decimal(stats.totalLength, total, 2)} longest=${stats.longest} unchecked=${stats.unchecked}`);
    const themes = template.slots.filter(slot => template.themeSlots.has(slot.index));
    if (themes.length > 0) lines.push('themes ' + themes.map(slot => slotDescription(template, slot)).join(' '));
    lines.push('coverage ' + stats.supply.map(([length, count]) => length + ':' + count).join(' '));
    lines.push('tightest ' + orDash(stats.tightest.map(item => item.slot.label + ':' + item.count)));
    for (let i = 0; i < template.attempts.length; i++) {
        const item = template.attempts[i];
        lines.push(`attempt ${i + 1} min_score=${item.minimum} budget=${item.budget} outcome=${item.outcome}` +
            ` nodes=${item.nodes} backtracks=${item.backtracks} prunes=${item.prunes} dead_ends=${item.deadEnds} max_depth=${item.maxDepth}`);
    }
    lines.push('trace ' + orDash(final.trace));
    lines.push('hotspots ' + orDash(stats.hotspots.map(item => item.slot.label + ':' + item.count)));
    if (template.outcome === 'filled') {
        const quality = template.quality;
        lines.push('order ' + orDash(final.order.map(index => template.slots[index].label)));
        lines.push(`quality total=${quality.total} average=${decimal(quality.total, total, 2)}` +
            ` weakest=${slotDescription(template, quality.weakest)} weak=${orDash(quality.weak.map(slot => slotDescription(template, slot)), ',')}`);
        let crossing = '-';
        if (quality.crossing !== null) {
            const cell = quality.crossing;
            const across = template.final.assigned[cell.across.index].word;
            const down = template.final.assigned[cell.down.index].word;
            crossing = `${cell.r},${cell.c} ${cell.across.label}:${across}+${cell.down.label}:${down}=${cell.score}`;
        }
        lines.push(`letters distinct=${quality.distinct} pangram=${quality.distinct === 26 ? 'yes' : 'no'}` +
            ` missing=${quality.missing || '-'} scrabble=${decimal(quality.points, stats.white, 2)} worst_crossing=${crossing}`);
    } else {
        const partial = template.partial;
        lines.push(`partial assigned=${partial.assigned}/${total} letters=${partial.letters}/${stats.white} blocked=${orDash(partial.blocked, ',')}`);
    }
    return lines;
}

function overallParagraphs(templates) {
    const completed = templates.filter(template => template.outcome === 'filled');
    const ranking = completed.slice().sort((a, b) =>
        b.quality.total * a.slots.length - a.quality.total * b.slots.length || compareText(a.name, b.name));
    const rankLines = ['RANKING'];
    for (let i = 0; i < ranking.length; i++) {
        const template = ranking[i];
        rankLines.push(`rank ${i + 1} ${template.name} average=${decimal(template.quality.total, template.slots.length, 2)}` +
            ` total=${template.quality.total} entries=${template.slots.length}`);
    }
    const users = new Map();
    for (const template of completed) {
        for (const entry of template.final.assigned) {
            if (!users.has(entry.word)) users.set(entry.word, []);
            users.get(entry.word).push(template.name);
        }
    }
    const reused = [...users].filter(([, names]) => names.length >= 2)
        .sort((a, b) => b[1].length - a[1].length || compareText(a[0], b[0]));
    const reuseLines = ['REUSE', ...reused.map(([word, names]) => `reused ${word} ${names.length} ${names.join(',')}`)];
    const counts = { invalid: 0, filled: 0, unfillable: 0, budget: 0, attempts: 0, nodes: 0 };
    for (const template of templates) {
        if (template.error) { counts.invalid++; continue; }
        counts[template.outcome]++;
        counts.attempts += template.attempts.length;
        for (const item of template.attempts) counts.nodes += item.nodes;
    }
    const summary = `SUMMARY templates=${templates.length} invalid=${counts.invalid} filled=${counts.filled}` +
        ` unfillable=${counts.unfillable} budget=${counts.budget} attempts=${counts.attempts} nodes=${counts.nodes}`;
    return [rankLines, reuseLines, [summary]];
}

function wordlistReport(dictionary, clues) {
    const words = dictionary.index.words;
    const lines = [`WORDLIST lines=${dictionary.lineCount} valid=${words.length} invalid=${dictionary.invalid.length} duplicates=${dictionary.duplicates.length}`];
    for (const item of dictionary.invalid) lines.push(`invalid ${item.line} ${item.reason}`);
    for (const item of dictionary.duplicates) lines.push(`duplicate ${item.line} ${item.word} first=${item.first}`);
    const lengths = [...dictionary.index.byLength.keys()].sort((a, b) => a - b);
    for (const length of lengths) {
        const entries = dictionary.index.byLength.get(length);
        let total = 0;
        for (const entry of entries) total += entry.score;
        lines.push(`length ${length} words=${entries.length} average=${decimal(total, entries.length, 2)} best=${entries[0].word}:${entries[0].score}`);
    }
    const bands = [0, 0, 0, 0, 0];
    const letters = [...alphabet].map(letter => ({ letter, count: 0 }));
    for (const entry of words) {
        const band = entry.score <= 20 ? 0 : entry.score <= 40 ? 1 : entry.score <= 60 ? 2 : entry.score <= 80 ? 3 : 4;
        bands[band]++;
        for (const item of letters) if (entry.word.includes(item.letter)) item.count++;
    }
    letters.sort((a, b) => a.count - b.count || compareText(a.letter, b.letter));
    lines.push(`bands 1-20=${bands[0]} 21-40=${bands[1]} 41-60=${bands[2]} 61-80=${bands[3]} 81-100=${bands[4]}`);
    lines.push('top ' + words.slice(0, 5).map(entry => entry.word + ':' + entry.score).join(' '));
    lines.push('rare_letters ' + letters.slice(0, 5).map(item => item.letter + ':' + item.count).join(' '));
    lines.push(`CLUES entries=${clues.entries} valid=${clues.valid} invalid=${clues.invalid.length} unknown=${clues.unknown.length} words=${clues.words}`);
    for (const item of clues.invalid) lines.push(`clue_invalid ${item.line} ${item.reason}`);
    for (const item of clues.unknown) lines.push(`clue_unknown ${item.line} ${item.word}`);
    let used = 0;
    let unused = 0;
    const repeated = [];
    for (const entry of words.slice().sort((a, b) => compareText(a.word, b.word))) {
        for (const clue of entry.clues) {
            if (clue.uses === 0) unused++;
            else used++;
            if (clue.uses >= 2) repeated.push(`repeated ${entry.word} clue=${clue.number} uses=${clue.uses}`);
        }
    }
    lines.push(`CLUE_USE used=${used} unused=${unused} repeated=${repeated.length}`);
    return [...lines, ...repeated];
}

function writeParagraphs(name, paragraphs) {
    fs.writeFileSync('output/' + name, paragraphs.length === 0 ? '' : paragraphs.map(lines => lines.join('\n')).join('\n\n') + '\n', 'utf8');
}

function main() {
    const settings = readSettings();
    const dictionary = readWords();
    const clues = readClues(dictionary);
    const templates = [];
    const names = new Set();
    const clueParagraphs = [];
    for (const block of readTemplates()) {
        const template = checkTemplate(block, settings, dictionary, names);
        templates.push(template);
        if (template.error) continue;
        fillTemplate(template, dictionary.index, settings.relax_step);
        template.stats = templateStatistics(template, dictionary.index);
        if (template.outcome === 'filled') template.quality = filledQuality(template, settings.weak_score);
        else template.partial = partialStatus(template, dictionary.index);
        clueParagraphs.push(chooseClues(template));
    }
    const statistics = templates.filter(template => !template.error).map(searchParagraph);
    statistics.push(...overallParagraphs(templates));
    fs.mkdirSync('output', { recursive: true });
    writeParagraphs('grid.txt', templates.map(gridParagraph));
    writeParagraphs('clues.txt', clueParagraphs);
    writeParagraphs('search_stats.txt', statistics);
    fs.writeFileSync('output/wordlist.txt', wordlistReport(dictionary, clues).join('\n') + '\n', 'utf8');
}

main();
