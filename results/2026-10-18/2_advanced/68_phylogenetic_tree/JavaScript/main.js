'use strict';

const fs = require('node:fs');
const alignment = require('./alignment');
const distances = require('./distances');
const building = require('./tree_building');
const parsimony = require('./parsimony');
const { real, symbols, orderedRoot, newick, cladogram, writeLines } = require('./tree_io');

const MODELS = ['P', 'JC', 'K2P'];
const METHODS = ['NJ_P', 'NJ_JC', 'NJ_K2P', 'ME', 'MP', 'CONSENSUS'];
const ascii = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const linesOf = path => fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');

function parameters() {
    const fields = new Map(linesOf('input/params.txt').map(line => {
        const [key, ...values] = line.split(' ');
        return [key, values];
    }));
    return { model: fields.get('model')[0], outgroup: fields.get('outgroup')[0],
        replicates: Number(fields.get('replicates')[0]), seed: Number(fields.get('seed')[0]),
        missing: Number(fields.get('max_missing_percent')[0]),
        saturation: Number(fields.get('saturation_distance')[0]),
        exhaustive: fields.get('exhaustive_taxa'), lowSites: Number(fields.get('low_sites')[0]) };
}

function acceptRecords(records, params) {
    const length = records[0].sequence.length;
    const taxa = [];
    const rejected = [];
    const seen = new Set();
    for (const record of records) {
        let reason = seen.has(record.name) ? 'duplicate name' : null;
        seen.add(record.name);
        if (reason === null) {
            for (let c = 0; c < record.sequence.length; c++) {
                if (!Object.hasOwn(alignment.BASES, record.sequence[c])) {
                    reason = `invalid character ${record.sequence[c]} at column ${c + 1}`;
                    break;
                }
            }
        }
        if (reason === null && record.sequence.length !== length) reason = `length mismatch ${record.sequence.length}`;
        if (reason === null) {
            let missing = 0;
            for (const character of record.sequence) if (character === 'N' || character === '-') missing++;
            if (100 * missing > params.missing * length) reason = `too many missing ${missing}`;
        }
        if (reason === null) taxa.push(record);
        else rejected.push({ ...record, reason });
    }
    return { taxa, rejected, length };
}

function alignmentSummary(records, data, patterns, columns) {
    const { taxa, rejected, length } = data;
    const lines = [`INPUT records ${records.length} accepted ${taxa.length} rejected ${rejected.length} columns ${length}`];
    for (const record of rejected) lines.push(`REJECT line ${record.line} ${record.name} ${record.reason}`);
    const composition = [0, 0, 0, 0];
    let totalBases = 0;
    for (const taxon of taxa) {
        let bases = 0;
        let ambiguous = 0;
        let missing = 0;
        let unique = 0;
        let gc = 0;
        for (let c = 0; c < length; c++) {
            const character = taxon.sequence[c];
            const index = alignment.LETTERS.indexOf(character);
            if (index >= 0) {
                bases++;
                totalBases++;
                composition[index]++;
                if (character === 'C' || character === 'G') gc++;
                if (columns[c].counts[index] === 1 && columns[c].kinds >= 2) unique++;
            } else if (character === 'N' || character === '-') missing++;
            else ambiguous++;
        }
        lines.push(`TAXON ${taxon.name} bases ${bases} ambiguous ${ambiguous} missing ${missing} unique ${unique} gc ${real(gc / bases, 4)}`);
    }
    let constant = 0;
    let variable = 0;
    let informative = 0;
    let gapped = 0;
    let empty = 0;
    for (const column of columns) {
        if (column.kinds === 0) empty++;
        else if (column.kinds === 1) constant++;
        else variable++;
        if (column.informative) informative++;
        if (column.gapped) gapped++;
    }
    lines.push(`COLUMNS constant ${constant} variable ${variable} informative ${informative} gapped ${gapped} empty ${empty}`,
        `PATTERNS ${patterns.distinct.size}`,
        'COMPOSITION ' + Array.from(alignment.LETTERS, (base, i) => `${base} ${real(composition[i] / totalBases, 4)}`).join(' '));
    return lines;
}

function scoreBounds(encoded) {
    const minima = [];
    let minimum = 0;
    let maximum = 0;
    for (let c = 0; c < encoded[0].length; c++) {
        let lower = 4;
        for (let mask = 1; mask <= 15; mask++) {
            const size = building.bitCount(mask);
            if (size < lower && encoded.every(sequence => (sequence[c] & mask) !== 0)) lower = size;
        }
        minima.push(lower - 1);
        minimum += lower - 1;
        let upper = encoded.length;
        for (const bit of [1, 2, 4, 8]) {
            let excludes = 0;
            for (const sequence of encoded) if ((sequence[c] & bit) === 0) excludes++;
            upper = Math.min(upper, excludes);
        }
        maximum += upper;
    }
    return { minimum, maximum, minima };
}

function bme(tree, matrix) {
    const taxa = building.leaves(tree);
    let total = 0;
    for (let i = 0; i < taxa.length; i++) {
        for (let j = i + 1; j < taxa.length; j++) {
            const edges = building.path(tree, taxa[i], taxa[j]).length;
            total += matrix[taxa[i]][taxa[j]] / (2 ** (edges - 1));
        }
    }
    return total;
}

function stepwise(taxa, count, outgroup, objective) {
    let tree = building.star(taxa.slice(0, 3), count);
    const initial = objective(tree);
    let value = initial;
    let evaluated = 0;
    const additions = [];
    for (const taxon of taxa.slice(3)) {
        let best = null;
        let ties = 0;
        for (const edge of parsimony.branches(tree, outgroup)) {
            const candidate = parsimony.insert(tree, edge, taxon);
            const score = objective(candidate);
            evaluated++;
            if (best === null || score < best.value) {
                best = { tree: candidate, value: score, mask: edge.mask };
                ties = 1;
            } else if (score === best.value) ties++;
        }
        tree = best.tree;
        value = best.value;
        additions.push({ taxon, mask: best.mask, value, ties });
    }
    return { tree, value, initial, first: taxa.slice(0, 3), additions, evaluated };
}

function hillClimb(start, initial, outgroup, objective) {
    let tree = start;
    let value = initial;
    let evaluated = 0;
    const moves = [];
    while (true) {
        let improvement = null;
        for (const candidate of parsimony.nniCandidates(tree, outgroup)) {
            const nextValue = objective(candidate.tree);
            evaluated++;
            if (nextValue < value) {
                improvement = candidate;
                value = nextValue;
                break;
            }
        }
        if (improvement === null) return { tree, value, moves, evaluated };
        tree = improvement.tree;
        moves.push({ mask: improvement.mask, swap: improvement.swap, value });
    }
}

function consensus(clades, taxa, count, outgroup) {
    const tree = building.emptyTree(count);
    const root = tree.next++;
    let ingroup = 0;
    for (const taxon of taxa) if (taxon !== outgroup) ingroup |= 2 ** taxon;
    const masks = Array.from(clades).sort((a, b) => a - b);
    const nodes = new Map(masks.map(mask => [mask, tree.next++]));
    function parentMask(mask, strict) {
        let best = ingroup;
        for (const candidate of masks) {
            if ((!strict || candidate !== mask) && (candidate & mask) === mask &&
                building.bitCount(candidate) < building.bitCount(best)) best = candidate;
        }
        return best;
    }
    for (const mask of masks) {
        const parent = parentMask(mask, true);
        building.connect(tree, parent === ingroup ? root : nodes.get(parent), nodes.get(mask));
    }
    for (const taxon of taxa) {
        const parent = taxon === outgroup ? ingroup : parentMask(2 ** taxon, false);
        building.connect(tree, parent === ingroup ? root : nodes.get(parent), taxon);
    }
    return tree;
}

function exhaustiveSearch(taxa, count, outgroup, names, objective, matrix) {
    let trees = [building.star(taxa.slice(0, 3), count)];
    for (const taxon of taxa.slice(3)) {
        const next = [];
        for (const tree of trees) {
            for (const edge of parsimony.branches(tree, outgroup)) next.push(parsimony.insert(tree, edge, taxon));
        }
        trees = next;
    }
    const entries = trees.map(tree => ({ tree, score: objective(tree), bme: bme(tree, matrix),
        newick: newick(tree, outgroup, names), splits: building.splitSet(tree, outgroup) }));
    const histogram = new Map();
    let bestScore = entries[0].score;
    let bestBme = entries[0];
    for (const entry of entries) {
        histogram.set(entry.score, (histogram.get(entry.score) || 0) + 1);
        bestScore = Math.min(bestScore, entry.score);
        if (entry.bme < bestBme.bme || (entry.bme === bestBme.bme && entry.newick < bestBme.newick)) bestBme = entry;
    }
    const optimal = entries.filter(entry => entry.score === bestScore).sort((a, b) => ascii(a.newick, b.newick));
    const strict = new Set(Array.from(optimal[0].splits).filter(mask => optimal.every(entry => entry.splits.has(mask))));
    let second = null;
    for (const entry of entries) if (entry !== bestBme && (second === null || entry.bme < second)) second = entry.bme;
    const heuristicStart = stepwise(taxa, count, outgroup, objective);
    const heuristic = hillClimb(heuristicStart.tree, heuristicStart.value, outgroup, objective);
    return { taxa, entries, histogram, bestScore, optimal, bestBme, second, heuristic,
        strict: consensus(strict, taxa, count, outgroup) };
}

function likelihood(tree, outgroup, names, encoded) {
    const rooted = orderedRoot(tree, outgroup, names);
    const transitions = new Map();
    for (const node of rooted.order) if (node !== rooted.root) {
        const e = Math.exp(-(4 * rooted.lengths.get(node)) / 3);
        transitions.set(node, [1 / 4 + (3 / 4) * e, 1 / 4 - (1 / 4) * e]);
    }
    const sites = [];
    let total = 0;
    for (let c = 0; c < encoded[0].length; c++) {
        const partial = new Map();
        let rootValues;
        for (let i = rooted.order.length - 1; i >= 0; i--) {
            const node = rooted.order[i];
            const values = [1, 1, 1, 1];
            for (let x = 0; x < 4; x++) {
                if (node < tree.count) values[x] = (encoded[node][c] & (2 ** x)) !== 0 ? 1 : 0;
                else for (const child of rooted.children.get(node)) values[x] *= partial.get(child)[x];
            }
            if (node === rooted.root) rootValues = values;
            else {
                const [same, different] = transitions.get(node);
                const adjusted = [0, 0, 0, 0];
                for (let x = 0; x < 4; x++) {
                    for (let y = 0; y < 4; y++) adjusted[x] += (x === y ? same : different) * values[y];
                }
                partial.set(node, adjusted);
            }
        }
        let probability = 0;
        for (let x = 0; x < 4; x++) probability += (1 / 4) * rootValues[x];
        const value = Math.log(probability);
        sites.push(value);
        total += value;
    }
    return { sites, total };
}

function rf(first, second) {
    let different = 0;
    for (const mask of first) if (!second.has(mask)) different++;
    for (const mask of second) if (!first.has(mask)) different++;
    return different;
}

function resample(taxa, all, main, params, outgroup, length) {
    const support = new Map();
    const replicates = [];
    let state = params.seed;
    for (let b = 1; b <= params.replicates; b++) {
        const weights = Array(length).fill(0);
        for (let c = 0; c < length; c++) {
            state = (48271 * state) % 2147483647;
            weights[state % length]++;
        }
        const pairs = distances.tallyPairs(taxa, weights);
        const matrix = distances.buildMatrix(taxa.length, pairs, params.model, params.saturation).matrix;
        const tree = building.neighborJoining(matrix, all, taxa.length);
        const splits = building.splitSet(tree, outgroup);
        for (const mask of splits) support.set(mask, (support.get(mask) || 0) + 1);
        replicates.push({ number: b, distinct: weights.filter(weight => weight > 0).length, rf: rf(splits, main.splits) });
    }
    const majority = new Set(Array.from(support.keys()).filter(mask => 2 * support.get(mask) > params.replicates));
    const jackknife = [];
    for (const taxon of all) if (taxon !== outgroup) {
        const tree = building.neighborJoining(main.matrix, all.filter(i => i !== taxon), taxa.length);
        const restricted = new Set();
        for (const mask of main.splits) {
            const reduced = mask & ~(2 ** taxon);
            const count = building.bitCount(reduced);
            if (count >= 2 && count <= taxa.length - 3) restricted.add(reduced);
        }
        jackknife.push({ taxon, rf: rf(building.splitSet(tree, outgroup), restricted) });
    }
    return { support, replicates, jackknife, tree: consensus(majority, all, taxa.length, outgroup) };
}

function quartetTopologies(splits, count) {
    const result = [];
    for (let a = 0; a < count; a++) for (let b = a + 1; b < count; b++) {
        for (let c = b + 1; c < count; c++) for (let d = c + 1; d < count; d++) {
            const partitions = [[a, b, c, d], [a, c, b, d], [a, d, b, c]];
            let topology = 0;
            for (let i = 0; i < partitions.length && topology === 0; i++) {
                const [p, q, r, s] = partitions[i];
                const first = (2 ** p) | (2 ** q);
                const second = (2 ** r) | (2 ** s);
                for (const mask of splits) {
                    if (((mask & first) === first && (mask & second) === 0) ||
                        ((mask & second) === second && (mask & first) === 0)) {
                        topology = i + 1;
                        break;
                    }
                }
            }
            result.push(topology);
        }
    }
    return result;
}

function sortedMasks(masks, count) {
    return Array.from(masks).sort((a, b) => ascii(symbols(a, count), symbols(b, count)));
}

function matrixLines(matrix, names) {
    const width = Math.max(...names.map(name => name.length));
    return names.map((name, i) => name.padEnd(width) + ' ' + matrix[i].map(value => real(value, 5)).join(' '));
}

function distanceReport(pairs, models, chosen, me, exhaustive, names) {
    const lines = [];
    let sites = 0;
    let transitions = 0;
    let transversions = 0;
    for (const pair of pairs) {
        lines.push(`PAIR ${names[pair.i]} ${names[pair.j]} sites ${pair.n} transitions ${pair.s} transversions ${pair.v}`);
        sites += pair.n;
        transitions += pair.s;
        transversions += pair.v;
    }
    lines.push(`TOTAL sites ${sites} transitions ${transitions} transversions ${transversions}`);
    for (const model of models) {
        lines.push('', `MODEL ${model.model}`, ...matrixLines(model.matrix, names));
        for (const pair of model.saturated) lines.push(`SATURATED ${names[pair.i]} ${names[pair.j]} sites ${pair.n}`);
    }
    lines.push('', `PATRISTIC ${chosen.name}`, ...matrixLines(chosen.patristic, names),
        '', `ME start ${chosen.name} length ${real(chosen.bme, 5)}`);
    for (const move of me.moves) lines.push(`NNI edge ${symbols(move.mask, names.length)} swap ${move.swap} length ${real(move.value, 5)}`);
    lines.push(`ME moves ${me.moves.length} evaluated ${me.evaluated} length ${real(me.value, 5)}`,
        `EXHAUSTIVE taxa ${exhaustive.taxa.length} trees ${exhaustive.entries.length} best ${real(exhaustive.bestBme.bme, 5)} second ${real(exhaustive.second, 5)}`,
        `BEST ${exhaustive.bestBme.newick} parsimony ${exhaustive.bestBme.score}`);
    return lines;
}

function parsimonyReport(models, bounds, added, mp, ancestors, exhaustive, names, outgroup, length) {
    const { minimum: M, maximum: G } = bounds;
    const statistics = score => `score ${score} ci ${real(M / score, 4)} ri ${real((G - score) / (G - M), 4)}`;
    const lines = [`BOUNDS minimum ${M} maximum ${G}`];
    for (const model of models) lines.push(`TREE ${model.name} ${statistics(model.parsimony.total)}`);
    lines.push(`START ${added.first.map(i => names[i]).join(' ')} score ${added.initial}`);
    for (const addition of added.additions) {
        lines.push(`ADD ${names[addition.taxon]} edge ${symbols(addition.mask, names.length)} score ${addition.value} ties ${addition.ties}`);
    }
    lines.push(`STEPWISE score ${added.value} evaluated ${added.evaluated}`);
    for (const move of mp.moves) lines.push(`NNI edge ${symbols(move.mask, names.length)} swap ${move.swap} score ${move.value}`);
    lines.push(`SEARCH moves ${mp.moves.length} evaluated ${mp.evaluated} score ${mp.value}`,
        `TREE MP ${statistics(mp.value)}`, `MP ${newick(mp.tree, outgroup, names, { lengths: true })}`);
    const histogram = Array(Math.max(...ancestors.columns) + 1).fill(0);
    let homoplasy = 0;
    for (let c = 0; c < length; c++) {
        histogram[ancestors.columns[c]]++;
        if (ancestors.columns[c] > bounds.minima[c]) homoplasy++;
    }
    histogram.forEach((columns, changes) => lines.push(`CHANGES ${changes} columns ${columns}`));
    lines.push(`HOMOPLASY columns ${homoplasy} extra ${mp.value - M}`);
    const nodes = Array.from(ancestors.ancestors.keys()).sort((a, b) => ascii(
        symbols(ancestors.rooted.masks.get(a), names.length), symbols(ancestors.rooted.masks.get(b), names.length)));
    for (const node of nodes) {
        lines.push(`ANCESTOR ${symbols(ancestors.rooted.masks.get(node), names.length)} ${ancestors.ancestors.get(node)}`);
    }
    lines.push('', `EXHAUSTIVE taxa ${exhaustive.taxa.length} trees ${exhaustive.entries.length} best ${exhaustive.bestScore} optimal ${exhaustive.optimal.length}`);
    for (const score of Array.from(exhaustive.histogram.keys()).sort((a, b) => a - b)) {
        lines.push(`SCORE ${score} trees ${exhaustive.histogram.get(score)}`);
    }
    for (const entry of exhaustive.optimal) lines.push(`OPTIMAL ${entry.newick} bme ${real(entry.bme, 5)}`);
    lines.push(`STRICT ${newick(exhaustive.strict, outgroup, names)}`,
        `HEURISTIC score ${exhaustive.heuristic.value} optimal ${exhaustive.heuristic.value === exhaustive.bestScore ? 'yes' : 'no'}`);
    return lines;
}

function likelihoodReport(models, chosen, patterns, length, lowSites) {
    const lines = [`LIKELIHOOD columns ${length} patterns ${patterns.distinct.size}`];
    for (const model of models) {
        lines.push(`TREE ${model.name} loglik ${real(model.likelihood.total, 4)} per_site ${real(model.likelihood.total / length, 4)}`);
    }
    for (let a = 0; a < models.length; a++) {
        for (let b = a + 1; b < models.length; b++) {
            const deltas = [];
            let difference = 0;
            for (let c = 0; c < length; c++) {
                const delta = models[a].likelihood.sites[c] - models[b].likelihood.sites[c];
                deltas.push(delta);
                difference += delta;
            }
            const mean = difference / length;
            let squares = 0;
            for (const delta of deltas) {
                const error = delta - mean;
                squares += error * error;
            }
            const se = Math.sqrt((length / (length - 1)) * squares);
            lines.push(`KH ${models[a].name} ${models[b].name} difference ${real(difference, 4)} se ${real(se, 4)} z ${real(difference / se, 4)}`);
        }
    }
    const selected = Array.from({ length }, (_, c) => c).sort((a, b) =>
        Number(real(chosen.likelihood.sites[a], 4)) - Number(real(chosen.likelihood.sites[b], 4)) || a - b).slice(0, lowSites);
    lines.push(`LOWEST ${chosen.name} sites ${lowSites}`);
    for (const c of selected) {
        lines.push(`SITE ${c + 1} loglik ${real(chosen.likelihood.sites[c], 4)} changes ${chosen.parsimony.columns[c]} pattern ${patterns.columns[c]}`);
    }
    return lines;
}

function bootstrapReport(sampled, chosen, params, names, outgroup) {
    const { support, replicates, jackknife } = sampled;
    const lines = [`BOOTSTRAP model ${params.model} replicates ${params.replicates} seed ${params.seed}`];
    for (const replicate of replicates) lines.push(`REPLICATE ${replicate.number} distinct ${replicate.distinct} rf ${replicate.rf}`);
    lines.push(`IDENTICAL ${replicates.filter(replicate => replicate.rf === 0).length}`);
    for (const mask of sortedMasks(chosen.splits, names.length)) {
        lines.push(`SUPPORT ${symbols(mask, names.length)} ${support.get(mask) || 0}`);
    }
    const splits = Array.from(support.keys()).sort((a, b) => support.get(b) - support.get(a) ||
        ascii(symbols(a, names.length), symbols(b, names.length)));
    for (const mask of splits) lines.push(`SPLIT ${symbols(mask, names.length)} ${support.get(mask)}`);
    lines.push(`CONSENSUS ${newick(sampled.tree, outgroup, names, { support })}`);
    for (const item of jackknife) lines.push(`JACKKNIFE ${names[item.taxon]} rf ${item.rf}`);
    return lines;
}

function clockReport(taxa, ingroup, outgroup, chosen, length) {
    const pairs = [];
    let rejected = 0;
    for (let a = 0; a < ingroup.length; a++) {
        for (let b = a + 1; b < ingroup.length; b++) {
            const i = ingroup[a];
            const j = ingroup[b];
            let m1 = 0;
            let m2 = 0;
            for (let c = 0; c < length; c++) {
                const x = taxa[i].sequence[c];
                const y = taxa[j].sequence[c];
                const o = taxa[outgroup].sequence[c];
                if (![x, y, o].every(base => alignment.LETTERS.includes(base)) || x === y) continue;
                if (y === o) m1++;
                if (x === o) m2++;
            }
            const difference = m1 - m2;
            const reject = 1000 * difference * difference > 3841 * (m1 + m2);
            if (reject) rejected++;
            const chi = m1 + m2 > 0 ? real(difference * difference / (m1 + m2), 4) : '-';
            pairs.push(`RRT ${taxa[i].name} ${taxa[j].name} m1 ${m1} m2 ${m2} chi2 ${chi} ${reject ? 'reject' : 'ok'}`);
        }
    }
    const root = building.rootTree(chosen.tree, outgroup).root;
    const tips = ingroup.map(taxon => building.pathDistance(chosen.tree, root, taxon));
    let total = 0;
    for (const distance of tips) total += distance;
    const mean = total / tips.length;
    let squares = 0;
    for (const distance of tips) {
        const difference = distance - mean;
        squares += difference * difference;
    }
    const sd = Math.sqrt(squares / (tips.length - 1));
    const lines = [`RELATIVE_RATE outgroup ${taxa[outgroup].name} pairs ${pairs.length} rejected ${rejected}`, ...pairs,
        `ROOT_TO_TIP ${chosen.name} mean ${real(mean, 5)} sd ${real(sd, 5)} cv ${real(sd / mean, 4)}`];
    for (let i = 0; i < ingroup.length; i++) lines.push(`TIP ${taxa[ingroup[i]].name} ${real(tips[i], 5)}`);
    return lines;
}

function comparisonReport(methods, chosen, mp, sampled, outgroup, names, length) {
    const lines = [];
    const clades = new Set();
    for (let i = 0; i < methods.length; i++) {
        const method = methods[i];
        for (const mask of method.splits) clades.add(mask);
        const supported = Array.from(method.splits).filter(mask => 2 * (sampled.support.get(mask) || 0) > sampled.replicates.length).length;
        let treeLength = '-';
        let negative = '-';
        let sse = '-';
        let loglik = '-';
        if (i < 3) {
            let total = 0;
            for (const edge of parsimony.branches(method.tree, outgroup)) total += edge.length;
            treeLength = real(total, 5);
            negative = method.tree.negative;
            let residual = 0;
            for (let a = 0; a < names.length; a++) {
                for (let b = a + 1; b < names.length; b++) {
                    const difference = method.matrix[a][b] - method.patristic[a][b];
                    residual += difference * difference;
                }
            }
            sse = real(residual, 6);
            loglik = real(method.likelihood.total, 4);
        } else if (i === 4) treeLength = real(method.parsimony.total / length, 5);
        lines.push(`TREE ${method.name} splits ${method.splits.size} supported ${supported} parsimony ${i === 5 ? '-' : method.parsimony.total} bme ${i === 5 ? '-' : real(method.bme, 5)} length ${treeLength} negative ${negative} sse ${sse} loglik ${loglik}`);
    }
    lines.push('RF ' + METHODS.join(' '));
    for (const method of methods) lines.push(method.name + ' ' + methods.map(other => rf(method.splits, other.splits)).join(' '));
    const quartets = methods.map(method => quartetTopologies(method.splits, names.length));
    lines.push('QUARTET ' + METHODS.join(' '));
    for (let i = 0; i < methods.length; i++) {
        const counts = quartets.map(other => {
            let count = 0;
            for (let q = 0; q < other.length; q++) if (quartets[i][q] !== other[q]) count++;
            return count;
        });
        lines.push(methods[i].name + ' ' + counts.join(' '));
    }
    const lengths = new Map(parsimony.branches(chosen.tree, outgroup).map(edge => [edge.mask, edge.length]));
    for (const mask of sortedMasks(clades, names.length)) {
        const marks = methods.map(method => method.splits.has(mask) ? '+' : '-').join('');
        const branchLength = lengths.has(mask) ? real(lengths.get(mask), 5) : '-';
        const changes = mp.branchChanges.has(mask) ? mp.branchChanges.get(mask) : '-';
        lines.push(`CLADE ${symbols(mask, names.length)} support ${sampled.support.get(mask) || 0} trees ${marks} length ${branchLength} changes ${changes}`);
    }
    return lines;
}

function hypothesisReport(methods, sampled, exhaustive, names, ingroup, outgroup) {
    const lines = [];
    const indices = new Map(names.map((name, i) => [name, i]));
    let allIngroup = 0;
    let exhaustiveIngroup = 0;
    for (const taxon of ingroup) allIngroup |= 2 ** taxon;
    for (const taxon of exhaustive.taxa) if (taxon !== outgroup) exhaustiveIngroup |= 2 ** taxon;
    for (const line of linesOf('input/clades.txt')) {
        const [name, ...taxa] = line.split(' ');
        const unknown = taxa.find(taxon => !indices.has(taxon));
        if (unknown !== undefined) {
            lines.push(`INVALID ${name} unknown taxon ${unknown}`);
            continue;
        }
        if (taxa.includes(names[outgroup])) {
            lines.push(`INVALID ${name} contains outgroup`);
            continue;
        }
        let mask = 0;
        for (const taxon of taxa) mask |= 2 ** indices.get(taxon);
        lines.push(`CLADE ${name} taxa ${taxa.length} support ${sampled.support.get(mask) || 0}`);
        for (const method of methods) {
            let common = allIngroup;
            for (const candidate of method.splits) {
                if ((candidate & mask) === mask && building.bitCount(candidate) < building.bitCount(common)) common = candidate;
            }
            const intruders = ingroup.filter(taxon => (common & (2 ** taxon)) !== 0 && (mask & (2 ** taxon)) === 0);
            lines.push(`TEST ${name} ${method.name} monophyletic ${common === mask ? 'yes' : 'no'} mrca ${building.bitCount(common)} intruders ${intruders.map(i => names[i]).join(',') || '-'}`);
        }
        const subset = mask & exhaustiveIngroup;
        const count = building.bitCount(subset);
        if (count < 2 || count >= building.bitCount(exhaustiveIngroup)) {
            lines.push(`SUBSET ${name} untestable`);
            continue;
        }
        const minima = [{ score: null, bme: null }, { score: null, bme: null }];
        for (const entry of exhaustive.entries) {
            const bucket = minima[entry.splits.has(subset) ? 0 : 1];
            if (bucket.score === null || entry.score < bucket.score) bucket.score = entry.score;
            if (bucket.bme === null || entry.bme < bucket.bme) bucket.bme = entry.bme;
        }
        lines.push(`SUBSET ${name} taxa ${count} with ${minima[0].score} without ${minima[1].score} bme_with ${real(minima[0].bme, 5)} bme_without ${real(minima[1].bme, 5)}`);
    }
    return lines;
}

function main() {
    const params = parameters();
    const records = alignment.readFasta('input/alignment.fasta');
    const data = acceptRecords(records, params);
    const { taxa, length } = data;
    const names = taxa.map(taxon => taxon.name);
    const count = taxa.length;
    const all = Array.from({ length: count }, (_, i) => i);
    const outgroup = names.indexOf(params.outgroup);
    const ingroup = all.filter(i => i !== outgroup);
    const encoded = alignment.encode(taxa);
    const patterns = alignment.patterns(taxa, length);
    const columns = alignment.classifyColumns(taxa, length);
    const pairs = distances.tallyPairs(taxa, Array(length).fill(1));
    const models = MODELS.map(model => {
        const result = distances.buildMatrix(count, pairs, model, params.saturation);
        const tree = building.neighborJoining(result.matrix, all, count);
        return { ...result, model, name: 'NJ_' + model, tree, splits: building.splitSet(tree, outgroup),
            parsimony: parsimony.score(tree, encoded, outgroup), patristic: building.patristic(tree),
            likelihood: likelihood(tree, outgroup, names, encoded) };
    });
    const chosen = models[MODELS.indexOf(params.model)];
    for (const model of models) model.bme = bme(model.tree, chosen.matrix);
    const objective = tree => parsimony.score(tree, encoded, outgroup).total;
    const me = hillClimb(chosen.tree, chosen.bme, outgroup, tree => bme(tree, chosen.matrix));
    const added = stepwise([outgroup, ...ingroup], count, outgroup, objective);
    const mp = hillClimb(added.tree, added.value, outgroup, objective);
    const ancestors = parsimony.reconstruct(mp.tree, encoded, outgroup);
    const exhaustiveTaxa = [outgroup, ...ingroup.filter(i => params.exhaustive.includes(names[i]))];
    const exhaustive = exhaustiveSearch(exhaustiveTaxa, count, outgroup, names, objective, chosen.matrix);
    const sampled = resample(taxa, all, chosen, params, outgroup, length);
    const methods = [...models,
        { name: 'ME', tree: me.tree, parsimony: parsimony.score(me.tree, encoded, outgroup), bme: me.value },
        { name: 'MP', tree: mp.tree, parsimony: ancestors, bme: bme(mp.tree, chosen.matrix) },
        { name: 'CONSENSUS', tree: sampled.tree }];
    for (const method of methods.slice(3)) method.splits = building.splitSet(method.tree, outgroup);
    fs.mkdirSync('output', { recursive: true });
    writeLines('summary.txt', alignmentSummary(records, data, patterns, columns));
    writeLines('distances.txt', distanceReport(pairs, models, chosen, me, exhaustive, names));
    writeLines('trees.nwk', methods.map((method, i) => method.name + ' ' + newick(method.tree, outgroup, names,
        { lengths: i < 3 || i === 4, support: i === 5 ? sampled.support : null })));
    const diagrams = [];
    for (const method of methods) {
        if (diagrams.length > 0) diagrams.push('');
        diagrams.push(`TREE ${method.name}`, ...cladogram(method.tree, outgroup, names, sampled.support));
    }
    writeLines('cladograms.txt', diagrams);
    writeLines('parsimony.txt', parsimonyReport(models, scoreBounds(encoded), added, mp, ancestors, exhaustive, names, outgroup, length));
    writeLines('likelihood.txt', likelihoodReport(models, chosen, patterns, length, params.lowSites));
    writeLines('bootstrap.txt', bootstrapReport(sampled, chosen, params, names, outgroup));
    writeLines('clock.txt', clockReport(taxa, ingroup, outgroup, chosen, length));
    writeLines('comparison.txt', comparisonReport(methods, chosen, ancestors, sampled, outgroup, names, length));
    writeLines('hypotheses.txt', hypothesisReport(methods, sampled, exhaustive, names, ingroup, outgroup));
}

main();
