import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { firstAsymmetry, componentCount, type Symmetry } from './grid.ts';
import { runs, shortRun, extractSlots, type Slot, type SlotLayout, type Axis } from './slots.ts';
import { compareText, validWord, validInteger, checkWordLine, checkClueLine, WordIndex, type WordEntry, type Clue, type Checked } from './word_index.ts';
import { slotPattern, attempt, type State, type Attempt } from './filler.ts';
import { decimal, gridLines, numberDiagram, listLine } from './render.ts';

interface Settings { node_budget: number; min_score: number; symmetry: Symmetry; relax_step: number; weak_score: number }
interface InvalidLine { line: number; reason: string }
interface Dictionary {
    lineCount: number; byWord: Map<string, WordEntry>; invalid: InvalidLine[];
    duplicates: { line: number; word: string; first: number }[]; index: WordIndex;
}
interface ClueStatistics { entries: number; valid: number; invalid: InvalidLine[]; unknown: { line: number; word: string }[]; words: number }
interface TemplateBlock { name: string; rows: string[]; options: string[] }
interface Template extends TemplateBlock, SlotLayout {
    h: number; w: number; settings: Settings; themeWords: string[]; initial: State; themeSlots: Set<number>;
}
interface FilledTemplate extends Template { attempts: Attempt[]; finalAttempt: Attempt; final: State }
interface TemplateError { name: string; error: string }
type TemplateResult = FilledTemplate | TemplateError;
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const letterPoints = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10];
const readLines = (name: string): string[] => readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
const orDash = (values: string[], separator = ' '): string => values.length ? values.join(separator) : '-';
const isSymmetry = (value: string): value is Symmetry => value === 'rot180' || value === 'mirror' || value === 'none';
function readSettings(): Settings {
    const values = new Map<string, string>();
    for (const line of readLines('params.txt')) if (line && !line.startsWith('#')) { const [key, value] = line.split(' '); values.set(key, value); }
    const symmetry = values.get('symmetry');
    if (!symmetry || !isSymmetry(symmetry)) throw new Error('Missing symmetry');
    return { node_budget: Number(values.get('node_budget')), min_score: Number(values.get('min_score')), symmetry, relax_step: Number(values.get('relax_step')), weak_score: Number(values.get('weak_score')) };
}
function readWords(): Dictionary {
    const lines = readLines('words.txt'), byWord = new Map<string, WordEntry>(), invalid: InvalidLine[] = [], duplicates: Dictionary['duplicates'] = [];
    lines.forEach((line, i) => {
        const parsed = checkWordLine(line);
        if ('error' in parsed) { invalid.push({ line: i + 1, reason: parsed.error }); return; }
        const previous = byWord.get(parsed.word);
        if (previous) duplicates.push({ line: i + 1, word: parsed.word, first: previous.line });
        else byWord.set(parsed.word, { ...parsed, line: i + 1, clues: [] });
    });
    return { lineCount: lines.length, byWord, invalid, duplicates, index: new WordIndex([...byWord.values()]) };
}
function readClues(dictionary: Dictionary): ClueStatistics {
    const result: ClueStatistics = { entries: 0, valid: 0, invalid: [], unknown: [], words: 0 };
    readLines('clues.txt').forEach((line, i) => {
        if (!line || line.startsWith('#')) return;
        result.entries++;
        const parsed = checkClueLine(line);
        if ('error' in parsed) { result.invalid.push({ line: i + 1, reason: parsed.error }); return; }
        const entry = dictionary.byWord.get(parsed.word);
        if (!entry) result.unknown.push({ line: i + 1, word: parsed.word });
        else { entry.clues.push({ text: parsed.clue, number: entry.clues.length + 1, uses: 0 }); result.valid++; }
    });
    result.words = dictionary.index.words.filter(entry => entry.clues.length > 0).length;
    return result;
}
function readTemplates(): TemplateBlock[] {
    const blocks: TemplateBlock[] = [];
    let current: TemplateBlock | null = null;
    for (const line of readLines('templates.txt')) {
        if (!current) { if (line && !line.startsWith('#')) current = { name: line.slice(9), rows: [], options: [] }; }
        else if (line === 'END') { blocks.push(current); current = null; }
        else if (line.includes(' ')) current.options.push(line);
        else current.rows.push(line);
    }
    return blocks;
}
function templateOptions(block: TemplateBlock, defaults: Settings): Checked<{ settings: Settings; themes: string[] }> {
    const settings = { ...defaults }, seen = new Set<string>(), themes: string[] = [];
    for (let i = 0; i < block.options.length; i++) {
        const line = block.options[i], space = line.indexOf(' '), key = line.slice(0, space), value = line.slice(space + 1);
        let valid = false;
        if (key === 'theme') { valid = validWord(value) && !themes.includes(value); if (valid) themes.push(value); }
        else if (!seen.has(key)) {
            if (key === 'node_budget' && validInteger(value, 100000)) { valid = true; settings.node_budget = Number(value); }
            if (key === 'min_score' && validInteger(value, 100)) { valid = true; settings.min_score = Number(value); }
            if (key === 'symmetry' && isSymmetry(value)) { valid = true; settings.symmetry = value; }
        }
        if (!valid) return { error: `bad option ${i + 1}` };
        seen.add(key);
    }
    return { settings, themes };
}
function placeThemes(template: Template, dictionary: Dictionary): string | null {
    const state = template.initial;
    for (let k = 0; k < template.themeWords.length; k++) {
        const text = template.themeWords[k], word = dictionary.byWord.get(text);
        if (!word) return `unknown theme ${k + 1}`;
        const chosen = template.slots.find(slot => state.assigned[slot.index] === null && slot.length === text.length && slot.cells.every((cell, i) => state.cells[cell] === '.' || state.cells[cell] === text[i]));
        if (!chosen) return `theme ${k + 1} does not fit`;
        state.assigned[chosen.index] = word; state.used.add(text);
        chosen.cells.forEach((cell, i) => { state.cells[cell] = text[i]; });
        template.themeSlots.add(chosen.index);
    }
    return null;
}
function checkTemplate(block: TemplateBlock, defaults: Settings, dictionary: Dictionary, names: Set<string>): Checked<Template> {
    const duplicate = names.has(block.name); names.add(block.name);
    if (!/^[a-z0-9_]{1,20}$/.test(block.name)) return { error: 'bad name' };
    if (duplicate) return { error: 'duplicate name' };
    const options = templateOptions(block, defaults);
    if ('error' in options) return options;
    const rows = block.rows, h = rows.length;
    if (h < 3 || h > 15) return { error: 'bad height' };
    const w = rows[0].length;
    for (let r = 0; r < h; r++) if (rows[r].length < 3 || rows[r].length > 15 || rows[r].length !== w || !/^[.#A-Z]+$/.test(rows[r])) return { error: `bad row ${r + 1}` };
    if (options.settings.symmetry !== 'none') {
        const cell = firstAsymmetry(rows, options.settings.symmetry);
        if (cell) return { error: `asymmetric at ${cell.r + 1},${cell.c + 1}` };
    }
    const components = componentCount(rows);
    if (components !== 1) return { error: `disconnected components=${components}` };
    const allRuns = runs(rows), short = shortRun(allRuns);
    if (short) return { error: `short slot at ${short.r + 1},${short.c + 1} ${short.axis === 'A' ? 'across' : 'down'}` };
    const layout = extractSlots(rows, allRuns);
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) if (rows[r][c] !== '#' && !layout.membership[r * w + c].length) return { error: `orphan cell ${r + 1},${c + 1}` };
    const template: Template = { ...block, h, w, ...layout, settings: options.settings, themeWords: options.themes, initial: { cells: rows.join('').split(''), assigned: layout.slots.map(() => null), used: new Set() }, themeSlots: new Set() };
    const error = placeThemes(template, dictionary);
    return error ? { error } : template;
}
function fillTemplate(template: Template, index: WordIndex, relaxStep: number): FilledTemplate {
    const attempts: Attempt[] = [];
    let minimum = template.settings.min_score;
    while (true) {
        const search = attempt(template.initial, template.slots, index, minimum, template.settings.node_budget);
        attempts.push(search);
        if (search.outcome === 'filled' || relaxStep === 0 || minimum === 1) return { ...template, attempts, finalAttempt: search, final: search.final };
        minimum = Math.max(minimum - relaxStep, 1);
    }
}
function assignedWord(template: FilledTemplate, slot: Slot): WordEntry {
    const entry = template.final.assigned[slot.index];
    if (!entry) throw new Error('Slot has no assignment');
    return entry;
}
function slotDescription(template: FilledTemplate, slot: Slot): string { const entry = assignedWord(template, slot); return `${slot.label}:${entry.word}:${entry.score}`; }
function totalScore(template: FilledTemplate): number { return template.final.assigned.reduce((sum, word) => sum + (word?.score ?? 0), 0); }
function qualityLines(template: FilledTemplate, weakScore: number, white: number): string[] {
    const state = template.final, slots = template.slots, total = totalScore(template);
    let weakest = slots[0];
    for (const slot of slots) if (assignedWord(template, slot).score < assignedWord(template, weakest).score) weakest = slot;
    const weak = slots.filter(slot => assignedWord(template, slot).score < weakScore), letters = new Set<string>();
    let points = 0;
    let crossing: { cell: number; across: Slot; down: Slot; score: number } | undefined;
    for (let cell = 0; cell < state.cells.length; cell++) {
        const letter = state.cells[cell];
        if (letter === '#') continue;
        letters.add(letter); points += letterPoints[letter.charCodeAt(0) - 65];
        const members = template.membership[cell];
        if (members.length !== 2) continue;
        const across = slots[members[0]].axis === 'A' ? slots[members[0]] : slots[members[1]], down = slots[members[0]].axis === 'D' ? slots[members[0]] : slots[members[1]];
        const score = assignedWord(template, across).score + assignedWord(template, down).score;
        if (!crossing || score < crossing.score) crossing = { cell, across, down, score };
    }
    let worst = '-';
    if (crossing) {
        const { cell, across, down, score } = crossing;
        worst = `${Math.floor(cell / template.w) + 1},${cell % template.w + 1} ${across.label}:${assignedWord(template, across).word}+${down.label}:${assignedWord(template, down).word}=${score}`;
    }
    const missing = [...alphabet].filter(letter => !letters.has(letter)).join('');
    return [`quality total=${total} average=${decimal(total, slots.length, 2)} weakest=${slotDescription(template, weakest)} weak=${orDash(weak.map(slot => slotDescription(template, slot)), ',')}`, `letters distinct=${letters.size} pangram=${letters.size === 26 ? 'yes' : 'no'} missing=${missing || '-'} scrabble=${decimal(points, white, 2)} worst_crossing=${worst}`];
}
function chooseClues(template: FilledTemplate): string[] {
    const lines = [`TEMPLATE ${template.name}`], axes: Axis[] = ['A', 'D'];
    let clued = 0, missing = 0, unfilled = 0;
    for (const axis of axes) {
        const slots = template.slots.filter(slot => slot.axis === axis);
        if (!slots.length) continue;
        lines.push(axis === 'A' ? 'ACROSS' : 'DOWN');
        for (const slot of slots) {
            const word = template.final.assigned[slot.index];
            let chosen: Clue | null = null;
            if (!word) unfilled++;
            else if (!word.clues.length) missing++;
            else { chosen = word.clues[0]; for (const clue of word.clues) if (clue.uses < chosen.uses) chosen = clue; chosen.uses++; clued++; }
            lines.push(listLine(slot, word, chosen?.text ?? null, slotPattern(slot, template.final), template.themeSlots.has(slot.index)));
        }
    }
    lines.push(`clued=${clued} missing=${missing} unfilled=${unfilled}`);
    return lines;
}
function gridParagraph(template: TemplateResult): string[] {
    if ('error' in template) return [`TEMPLATE ${template.name}`, `error ${template.error}`];
    return [`TEMPLATE ${template.name}`, `outcome=${template.finalAttempt.outcome} attempts=${template.attempts.length} min_score=${template.finalAttempt.minimum}`, ...gridLines(template, template.final), 'numbers', ...numberDiagram(template)];
}
function searchParagraph(template: FilledTemplate, index: WordIndex, weakScore: number): string[] {
    const { slots, finalAttempt: final, initial, settings } = template, cells = template.rows.join('');
    const blocks = [...cells].filter(c => c === '#').length, white = cells.length - blocks, givens = [...cells].filter(c => /[A-Z]/.test(c)).length;
    const kinds: Exclude<Symmetry, 'none'>[] = ['rot180', 'mirror'], symmetries = kinds.filter(kind => !firstAsymmetry(template.rows, kind));
    const counts = new Map<number, number>();
    for (const slot of slots) counts.set(slot.length, (counts.get(slot.length) ?? 0) + 1);
    const lengths = [...counts.keys()].sort((a, b) => a - b), across = slots.filter(s => s.axis === 'A').length;
    const tightest = slots.filter(s => !template.themeSlots.has(s.index)).map(slot => ({ slot, count: index.candidates(slotPattern(slot, initial), settings.min_score, initial.used).length })).sort((a, b) => a.count - b.count || a.slot.index - b.slot.index).slice(0, 3);
    const hotspots = slots.map(slot => ({ slot, count: final.failures[slot.index] })).filter(item => item.count > 0).sort((a, b) => b.count - a.count || a.slot.index - b.slot.index).slice(0, 3);
    const lines = [`TEMPLATE ${template.name}`, `grid size=${template.w}x${template.h} blocks=${blocks} white=${white} density=${decimal(100 * blocks, cells.length, 1)} givens=${givens} required=${settings.symmetry} symmetry=${symmetries.join(',') || 'none'}`, `slots across=${across} down=${slots.length - across} total=${slots.length} lengths=${lengths.map(length => `${length}:${counts.get(length)}`).join(',')} avg_length=${decimal(slots.reduce((sum, s) => sum + s.length, 0), slots.length, 2)} longest=${Math.max(...lengths)} unchecked=${template.membership.filter(members => members.length === 1).length}`];
    const themes = slots.filter(s => template.themeSlots.has(s.index));
    if (themes.length) lines.push(`themes ${themes.map(slot => slotDescription(template, slot)).join(' ')}`);
    lines.push(`coverage ${lengths.map(length => `${length}:${(index.byLength.get(length) ?? []).filter(word => word.score >= settings.min_score).length}`).join(' ')}`, `tightest ${orDash(tightest.map(item => `${item.slot.label}:${item.count}`))}`);
    template.attempts.forEach((item, i) => lines.push(`attempt ${i + 1} min_score=${item.minimum} budget=${item.budget} outcome=${item.outcome} nodes=${item.nodes} backtracks=${item.backtracks} prunes=${item.prunes} dead_ends=${item.deadEnds} max_depth=${item.maxDepth}`));
    lines.push(`trace ${orDash(final.trace)}`, `hotspots ${orDash(hotspots.map(item => `${item.slot.label}:${item.count}`))}`);
    if (final.outcome === 'filled') { lines.push(`order ${orDash(final.order.map(i => slots[i].label))}`, ...qualityLines(template, weakScore, white)); }
    else {
        const state = template.final, blocked = slots.filter(s => state.assigned[s.index] === null && index.candidates(slotPattern(s, state), final.minimum, state.used).length === 0);
        lines.push(`partial assigned=${state.assigned.filter(Boolean).length}/${slots.length} letters=${state.cells.filter(c => c !== '#' && c !== '.').length}/${white} blocked=${orDash(blocked.map(s => s.label), ',')}`);
    }
    return lines;
}
function overallParagraphs(templates: TemplateResult[]): string[][] {
    const valid = templates.filter((template): template is FilledTemplate => !('error' in template)), completed = valid.filter(t => t.finalAttempt.outcome === 'filled');
    const ranking = [...completed].sort((a, b) => totalScore(b) * a.slots.length - totalScore(a) * b.slots.length || compareText(a.name, b.name));
    const rankLines = ['RANKING', ...ranking.map((t, i) => `rank ${i + 1} ${t.name} average=${decimal(totalScore(t), t.slots.length, 2)} total=${totalScore(t)} entries=${t.slots.length}`)];
    const users = new Map<string, string[]>();
    for (const template of completed) for (const text of template.final.used) { const names = users.get(text) ?? []; names.push(template.name); users.set(text, names); }
    const reused = [...users].filter(([, names]) => names.length >= 2).sort((a, b) => b[1].length - a[1].length || compareText(a[0], b[0]));
    const reuseLines = ['REUSE', ...reused.map(([word, names]) => `reused ${word} ${names.length} ${names.join(',')}`)];
    const summary = `SUMMARY templates=${templates.length} invalid=${templates.length - valid.length} filled=${completed.length} unfillable=${valid.filter(t => t.finalAttempt.outcome === 'unfillable').length} budget=${valid.filter(t => t.finalAttempt.outcome === 'budget').length} attempts=${valid.reduce((sum, t) => sum + t.attempts.length, 0)} nodes=${valid.reduce((sum, t) => sum + t.attempts.reduce((s, a) => s + a.nodes, 0), 0)}`;
    return [rankLines, reuseLines, [summary]];
}
function wordlistReport(dictionary: Dictionary, clues: ClueStatistics): string[] {
    const { index, invalid, duplicates } = dictionary, words = index.words;
    const lines = [`WORDLIST lines=${dictionary.lineCount} valid=${words.length} invalid=${invalid.length} duplicates=${duplicates.length}`];
    for (const item of invalid) lines.push(`invalid ${item.line} ${item.reason}`);
    for (const item of duplicates) lines.push(`duplicate ${item.line} ${item.word} first=${item.first}`);
    for (const length of [...index.byLength.keys()].sort((a, b) => a - b)) {
        const entries = index.byLength.get(length);
        if (!entries) continue;
        lines.push(`length ${length} words=${entries.length} average=${decimal(entries.reduce((sum, word) => sum + word.score, 0), entries.length, 2)} best=${entries[0].word}:${entries[0].score}`);
    }
    const bands = [0, 0, 0, 0, 0];
    for (const entry of words) bands[Math.floor((entry.score - 1) / 20)]++;
    const rare = [...alphabet].map(letter => ({ letter, count: words.filter(entry => entry.word.includes(letter)).length })).sort((a, b) => a.count - b.count || compareText(a.letter, b.letter)).slice(0, 5);
    lines.push(`bands 1-20=${bands[0]} 21-40=${bands[1]} 41-60=${bands[2]} 61-80=${bands[3]} 81-100=${bands[4]}`, `top ${words.slice(0, 5).map(entry => `${entry.word}:${entry.score}`).join(' ')}`, `rare_letters ${rare.map(item => `${item.letter}:${item.count}`).join(' ')}`, `CLUES entries=${clues.entries} valid=${clues.valid} invalid=${clues.invalid.length} unknown=${clues.unknown.length} words=${clues.words}`);
    for (const item of clues.invalid) lines.push(`clue_invalid ${item.line} ${item.reason}`);
    for (const item of clues.unknown) lines.push(`clue_unknown ${item.line} ${item.word}`);
    let used = 0, unused = 0;
    const repeated: string[] = [];
    for (const entry of [...words].sort((a, b) => compareText(a.word, b.word))) for (const clue of entry.clues) {
        if (clue.uses) used++; else unused++;
        if (clue.uses >= 2) repeated.push(`repeated ${entry.word} clue=${clue.number} uses=${clue.uses}`);
    }
    return [...lines, `CLUE_USE used=${used} unused=${unused} repeated=${repeated.length}`, ...repeated];
}
function writeParagraphs(name: string, paragraphs: string[][]): void { writeFileSync(`output/${name}`, paragraphs.length ? paragraphs.map(lines => lines.join('\n')).join('\n\n') + '\n' : '', 'ascii'); }
function main(): void {
    const settings = readSettings(), dictionary = readWords(), clues = readClues(dictionary), names = new Set<string>(), templates: TemplateResult[] = [], clueParagraphs: string[][] = [], stats: string[][] = [];
    for (const block of readTemplates()) {
        const checked = checkTemplate(block, settings, dictionary, names);
        if ('error' in checked) { templates.push({ name: block.name, error: checked.error }); continue; }
        const template = fillTemplate(checked, dictionary.index, settings.relax_step);
        templates.push(template); stats.push(searchParagraph(template, dictionary.index, settings.weak_score)); clueParagraphs.push(chooseClues(template));
    }
    stats.push(...overallParagraphs(templates));
    mkdirSync('output', { recursive: true });
    writeParagraphs('grid.txt', templates.map(gridParagraph)); writeParagraphs('clues.txt', clueParagraphs); writeParagraphs('search_stats.txt', stats);
    writeFileSync('output/wordlist.txt', wordlistReport(dictionary, clues).join('\n') + '\n', 'ascii');
}
main();
