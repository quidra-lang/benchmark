import { readFileSync } from 'node:fs';
import { bases, baseSets, readFasta, patterns, classify } from './alignment.ts';
import { models, tally, distance, matrix, type DistanceModel } from './distances.ts';
import { empty, connect, rooted, leaves, paths, patristic, splits, neighborJoining, type Tree } from './tree_building.ts';
import { branches, fitch, reconstruct, insert, nni } from './parsimony.ts';
import { real, symbol, ordered, newick, cladogram, write } from './tree_io.ts';

const sum = (values: number[]): number => values.reduce((a, b) => a + b, 0);
const ascii = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const popcount = (mask: number): number => { let count = 0; while (mask) { mask &= mask - 1; count++; } return count; };
const contains = (mask: number, subset: number): boolean => (mask & subset) === subset;
const lines = (name: string): string[] => readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
const fields = new Map(lines('params.txt').map((line): [string, string[]] => { const [key, ...values] = line.split(' '); return [key, values]; }));
const parameter = (key: string): string => fields.get(key)![0], numeric = (key: string): number => Number(parameter(key));
const records = readFasta(), length = records[0].sequence.length, seen = new Set<string>(), rejected: string[] = [], sequences: string[] = [], names: string[] = [];
for (const record of records) {
  let reason = ''; const bad = [...record.sequence].findIndex(c => baseSets[c] === undefined), missing = [...record.sequence].filter(c => c === '-' || c === 'N').length;
  if (seen.has(record.name)) reason = 'duplicate name';
  else if (bad >= 0) reason = `invalid character ${record.sequence[bad]} at column ${bad + 1}`;
  else if (record.sequence.length !== length) reason = `length mismatch ${record.sequence.length}`;
  else if (100 * missing > numeric('max_missing_percent') * length) reason = `too many missing ${missing}`;
  seen.add(record.name);
  if (reason) rejected.push(`REJECT line ${record.line} ${record.name} ${reason}`); else { names.push(record.name); sequences.push(record.sequence); }
}
const count = names.length, taxa = names.map((_, i) => i), outgroup = names.indexOf(parameter('outgroup')), ingroup = taxa.filter(i => i !== outgroup);
const model = parameter('model') as DistanceModel, replicates = numeric('replicates'), replacement = numeric('saturation_distance'), lowSites = numeric('low_sites');
const ingroupMask = ingroup.reduce((mask, i) => mask | 2 ** i, 0), symbols = (mask: number): string => symbol(mask, count);
const maskOrder = (a: number, b: number): number => ascii(symbols(a), symbols(b));
const grouped = patterns(sequences), columnPatterns = Array.from({ length }, (_, c) => sequences.map(s => s[c]).join(''));
const classification = columnPatterns.map(classify), compositionCounts = [...bases].map(base => sum(sequences.map(s => [...s].filter(c => c === base).length)));
const summary = [`INPUT records ${records.length} accepted ${count} rejected ${rejected.length} columns ${length}`, ...rejected];
sequences.forEach((sequence, i) => {
  const counts = [...bases].map(base => [...sequence].filter(c => c === base).length), baseCount = sum(counts), missing = [...sequence].filter(c => c === '-' || c === 'N').length;
  let unique = 0;
  for (let c = 0; c < length; c++) if (bases.includes(sequence[c]) && taxa.some(j => j !== i && bases.includes(sequences[j][c])) && taxa.every(j => j === i || sequences[j][c] !== sequence[c])) unique++;
  summary.push(`TAXON ${names[i]} bases ${baseCount} ambiguous ${length - baseCount - missing} missing ${missing} unique ${unique} gc ${real((counts[1] + counts[2]) / baseCount, 4)}`);
});
summary.push(`COLUMNS constant ${classification.filter(c => c.constant).length} variable ${classification.filter(c => c.variable).length} informative ${classification.filter(c => c.informative).length} gapped ${classification.filter(c => c.gapped).length} empty ${classification.filter(c => c.empty).length}`,
  `PATTERNS ${grouped.length}`, 'COMPOSITION ' + [...bases].map((base, i) => `${base} ${real(compositionCounts[i] / sum(compositionCounts), 4)}`).join(' '));
const pairCounts = tally(sequences, Array<number>(length).fill(1)), matrices = new Map(models.map(m => [m, matrix(count, pairCounts, m, replacement)]));
const mainMatrix = matrices.get(model)!, njTrees = models.map(m => neighborJoining(matrices.get(m)!, taxa)), mainIndex = models.indexOf(model), mainTree = njTrees[mainIndex], mainName = 'NJ_' + model;
function bme(tree: Tree): number {
  const present = leaves(tree); let total = 0;
  present.forEach((i, position) => { const distances = paths(tree, i); for (const j of present.slice(position + 1)) total += mainMatrix[i][j] / 2 ** (distances.get(j)!.steps - 1); }); return total;
}
function star(list: number[]): Tree { const tree = empty(count), node = tree.next++; for (const i of list.slice(0, 3)) connect(tree, node, i); return tree; }
function stepwise(list: number[]) {
  let tree = star(list), score = fitch(tree, sequences, outgroup).score, evaluated = 0;
  const trace = [`START ${list.slice(0, 3).map(i => names[i]).join(' ')} score ${score}`];
  for (const taxon of list.slice(3)) {
    let best: Tree | undefined, bestScore = Infinity, bestMask = 0, ties = 0;
    for (const branch of branches(tree, outgroup)) {
      const candidate = insert(tree, branch, taxon), value = fitch(candidate, sequences, outgroup).score; evaluated++;
      if (value < bestScore) { best = candidate; bestScore = value; bestMask = branch.mask; ties = 1; } else if (value === bestScore) ties++;
    }
    tree = best!; score = bestScore; trace.push(`ADD ${names[taxon]} edge ${symbols(bestMask)} score ${score} ties ${ties}`);
  }
  trace.push(`STEPWISE score ${score} evaluated ${evaluated}`); return { tree, trace, score, evaluated };
}
function hillClimb(start: Tree, objective: (tree: Tree) => number, metric: 'score' | 'length') {
  let tree = start, value = objective(tree), moves = 0, evaluated = 0; const trace: string[] = [];
  search: for (;;) {
    for (const branch of branches(tree, outgroup).filter(b => tree.edges.get(b.u)!.size > 1 && tree.edges.get(b.v)!.size > 1)) {
      for (const swap of [1, 2] as const) {
        const candidate = nni(tree, branch, swap, outgroup), next = objective(candidate); evaluated++;
        if (next < value) { tree = candidate; value = next; moves++; trace.push(`NNI edge ${symbols(branch.mask)} swap ${swap} ${metric} ${metric === 'score' ? value : real(value, 5)}`); continue search; }
      }
    }
    break;
  }
  return { tree, value, moves, evaluated, trace };
}
const me = hillClimb(mainTree, bme, 'length'), addition = stepwise([outgroup, ...ingroup]), mpSearch = hillClimb(addition.tree, tree => fitch(tree, sequences, outgroup).score, 'score');
const mp = reconstruct(mpSearch.tree, sequences, outgroup), mpTree = mp.tree;
const exhaustiveTaxa = [outgroup, ...taxa.filter(i => i !== outgroup && fields.get('exhaustive_taxa')!.includes(names[i]))];
let exhaustiveTrees = [star(exhaustiveTaxa)];
for (const taxon of exhaustiveTaxa.slice(3)) exhaustiveTrees = exhaustiveTrees.flatMap(tree => branches(tree, outgroup).map(branch => insert(tree, branch, taxon)));
const exhaustive = exhaustiveTrees.map(tree => ({ tree, score: fitch(tree, sequences, outgroup).score, bme: bme(tree), text: newick(tree, outgroup, names), clades: splits(tree, outgroup) }));
const bestScore = Math.min(...exhaustive.map(tree => tree.score)), optimal = exhaustive.filter(tree => tree.score === bestScore).sort((a, b) => ascii(a.text, b.text));
const bmeOrder = [...exhaustive].sort((a, b) => a.bme - b.bme || ascii(a.text, b.text)), scoreCounts = new Map<number, number>();
for (const tree of exhaustive) scoreCounts.set(tree.score, (scoreCounts.get(tree.score) ?? 0) + 1);
function consensus(present: number[], clades: number[]): Tree {
  const tree = empty(count), root = tree.next++, all = present.filter(i => i !== outgroup).reduce((mask, i) => mask | 2 ** i, 0); connect(tree, root, outgroup);
  function fill(node: number, container: number): void {
    const proper = clades.filter(c => c !== container && contains(container, c)), maximal = proper.filter(c => !proper.some(d => c !== d && contains(d, c)));
    let covered = 0;
    for (const clade of maximal) { const child = tree.next++; connect(tree, node, child); covered |= clade; fill(child, clade); }
    for (const taxon of present) if (taxon !== outgroup && (container & 2 ** taxon) && !(covered & 2 ** taxon)) connect(tree, node, taxon);
  }
  fill(root, all); return tree;
}
const strictClades = [...optimal[0].clades].filter(mask => optimal.every(tree => tree.clades.has(mask))), strict = consensus(exhaustiveTaxa, strictClades);
const heuristicStart = stepwise(exhaustiveTaxa), heuristic = hillClimb(heuristicStart.tree, tree => fitch(tree, sequences, outgroup).score, 'score');
const minimumColumns = columnPatterns.map(pattern => {
  let minimum = 4; for (let set = 1; set < 16; set++) if ([...pattern].every(c => (set & baseSets[c]) !== 0)) minimum = Math.min(minimum, popcount(set)); return minimum - 1;
});
const minimum = sum(minimumColumns), maximum = sum(columnPatterns.map(pattern => Math.min(...[1, 2, 4, 8].map(base => [...pattern].filter(c => !(baseSets[c] & base)).length))));
const njScores = njTrees.map(tree => fitch(tree, sequences, outgroup));
function likelihood(tree: Tree): number[] {
  const view = rooted(tree, outgroup), children = ordered(view, names);
  return Array.from({ length }, (_, column) => {
    const partial = new Map<number, number[]>();
    for (const node of [...view.nodes].reverse()) {
      const next = children.get(node)!;
      if (!next.length) partial.set(node, [1, 2, 4, 8].map(base => baseSets[sequences[node][column]] & base ? 1 : 0));
      else partial.set(node, [0, 1, 2, 3].map(x => {
        let product = 1;
        for (const child of next) { const e = Math.exp(-(4 * tree.edges.get(node)!.get(child)!) / 3); let total = 0;
          for (let y = 0; y < 4; y++) total += (x === y ? 1 / 4 + (3 / 4) * e : 1 / 4 - (1 / 4) * e) * partial.get(child)![y]; product *= total;
        }
        return product;
      }));
    }
    return Math.log(sum(partial.get(view.root)!.map(value => (1 / 4) * value)));
  });
}
const siteLikelihoods = njTrees.map(likelihood), logLikelihoods = siteLikelihoods.map(sum);
const rf = (a: Set<number>, b: Set<number>): number => [...a].filter(c => !b.has(c)).length + [...b].filter(c => !a.has(c)).length;
let random = numeric('seed'); const support = new Map<number, number>(), bootstrap: string[] = [`BOOTSTRAP model ${model} replicates ${replicates} seed ${random}`], mainSplits = splits(mainTree, outgroup); let identical = 0;
for (let b = 1; b <= replicates; b++) {
  const weights = Array<number>(length).fill(0);
  for (let c = 0; c < length; c++) { random = 48271 * random % 2147483647; weights[random % length]++; }
  const tree = neighborJoining(matrix(count, tally(sequences, weights), model, replacement), taxa), clades = splits(tree, outgroup), difference = rf(clades, mainSplits);
  for (const mask of clades) support.set(mask, (support.get(mask) ?? 0) + 1);
  if (difference === 0) identical++;
  bootstrap.push(`REPLICATE ${b} distinct ${weights.filter(w => w > 0).length} rf ${difference}`);
}
const majority = consensus(taxa, [...support].filter(([, n]) => 2 * n > replicates).map(([mask]) => mask)), methods = ['NJ_P', 'NJ_JC', 'NJ_K2P', 'ME', 'MP', 'CONSENSUS'];
const trees = [...njTrees, me.tree, mpTree, majority], splitSets = trees.map(tree => splits(tree, outgroup));
bootstrap.push(`IDENTICAL ${identical}`, ...[...mainSplits].sort(maskOrder).map(mask => `SUPPORT ${symbols(mask)} ${support.get(mask) ?? 0}`),
  ...[...support].sort(([a, x], [b, y]) => y - x || maskOrder(a, b)).map(([mask, n]) => `SPLIT ${symbols(mask)} ${n}`), `CONSENSUS ${newick(majority, outgroup, names, 'support', support)}`);
for (const omitted of ingroup) {
  const reduced = taxa.filter(i => i !== omitted), tree = neighborJoining(mainMatrix, reduced), expected = new Set([...mainSplits].map(mask => mask & ~(2 ** omitted)).filter(mask => popcount(mask) >= 2 && popcount(mask) <= count - 3));
  bootstrap.push(`JACKKNIFE ${names[omitted]} rf ${rf(splits(tree, outgroup), expected)}`);
}
const matrixLines = (values: number[][]): string[] => { const width = Math.max(...names.map(name => name.length)); return names.map((name, i) => name.padEnd(width) + values[i].map(value => ' ' + real(value, 5)).join('')); };
const pairBlock = pairCounts.map(p => `PAIR ${names[p.i]} ${names[p.j]} sites ${p.n} transitions ${p.s} transversions ${p.v}`);
pairBlock.push(`TOTAL sites ${sum(pairCounts.map(p => p.n))} transitions ${sum(pairCounts.map(p => p.s))} transversions ${sum(pairCounts.map(p => p.v))}`);
const blocks = (groups: string[][]): string[] => groups.flatMap((group, i) => i ? ['', ...group] : group);
const distanceReport = blocks([pairBlock, ...models.map(m => [`MODEL ${m}`, ...matrixLines(matrices.get(m)!), ...pairCounts.filter(p => distance(p, m, replacement).saturated).map(p => `SATURATED ${names[p.i]} ${names[p.j]} sites ${p.n}`)]),
  [`PATRISTIC ${mainName}`, ...matrixLines(patristic(mainTree, taxa))], [`ME start ${mainName} length ${real(bme(mainTree), 5)}`, ...me.trace,
    `ME moves ${me.moves} evaluated ${me.evaluated} length ${real(me.value, 5)}`, `EXHAUSTIVE taxa ${exhaustiveTaxa.length} trees ${exhaustive.length} best ${real(bmeOrder[0].bme, 5)} second ${real(bmeOrder[1].bme, 5)}`,
    `BEST ${bmeOrder[0].text} parsimony ${bmeOrder[0].score}`]]);
const treeReport = trees.map((tree, i) => `${methods[i]} ${newick(tree, outgroup, names, i === 3 ? 'plain' : i === 5 ? 'support' : 'length', support)}`);
const cladograms = blocks(trees.map((tree, i) => [`TREE ${methods[i]}`, ...cladogram(tree, outgroup, names, support)]));
const indices = (score: number): string => `ci ${real(minimum / score, 4)} ri ${real((maximum - score) / (maximum - minimum), 4)}`;
const parsimonyReport = [`BOUNDS minimum ${minimum} maximum ${maximum}`, ...njScores.map((fit, i) => `TREE ${methods[i]} score ${fit.score} ${indices(fit.score)}`),
  ...addition.trace, ...mpSearch.trace, `SEARCH moves ${mpSearch.moves} evaluated ${mpSearch.evaluated} score ${mp.score}`, `TREE MP score ${mp.score} ${indices(mp.score)}`, `MP ${newick(mpTree, outgroup, names, 'length')}`];
for (let k = 0; k <= Math.max(...mp.columns); k++) parsimonyReport.push(`CHANGES ${k} columns ${mp.columns.filter(n => n === k).length}`);
parsimonyReport.push(`HOMOPLASY columns ${mp.columns.filter((n, c) => n > minimumColumns[c]).length} extra ${mp.score - minimum}`);
const mpView = rooted(mpTree, outgroup);
for (const node of mpView.nodes.filter(v => mpView.children.get(v)!.length > 0).sort((a, b) => maskOrder(mpView.masks.get(a)!, mpView.masks.get(b)!))) parsimonyReport.push(`ANCESTOR ${symbols(mpView.masks.get(node)!)} ${mp.ancestors.get(node)!}`);
parsimonyReport.push('', `EXHAUSTIVE taxa ${exhaustiveTaxa.length} trees ${exhaustive.length} best ${bestScore} optimal ${optimal.length}`,
  ...[...scoreCounts].sort(([a], [b]) => a - b).map(([score, n]) => `SCORE ${score} trees ${n}`), ...optimal.map(tree => `OPTIMAL ${tree.text} bme ${real(tree.bme, 5)}`),
  `STRICT ${newick(strict, outgroup, names)}`, `HEURISTIC score ${heuristic.value} optimal ${heuristic.value === bestScore ? 'yes' : 'no'}`);
const likelihoodReport = [`LIKELIHOOD columns ${length} patterns ${grouped.length}`, ...logLikelihoods.map((value, i) => `TREE ${methods[i]} loglik ${real(value, 4)} per_site ${real(value / length, 4)}`)];
for (let a = 0; a < 3; a++) for (let b = a + 1; b < 3; b++) {
  const differences = siteLikelihoods[a].map((value, c) => value - siteLikelihoods[b][c]), difference = sum(differences), mean = difference / length, error = Math.sqrt((length / (length - 1)) * sum(differences.map(value => (value - mean) * (value - mean))));
  likelihoodReport.push(`KH ${methods[a]} ${methods[b]} difference ${real(difference, 4)} se ${real(error, 4)} z ${real(difference / error, 4)}`);
}
likelihoodReport.push(`LOWEST ${mainName} sites ${lowSites}`);
const lowColumns = Array.from({ length }, (_, c) => c).sort((a, b) => Number(real(siteLikelihoods[mainIndex][a], 4)) - Number(real(siteLikelihoods[mainIndex][b], 4)) || a - b).slice(0, lowSites);
for (const c of lowColumns) likelihoodReport.push(`SITE ${c + 1} loglik ${real(siteLikelihoods[mainIndex][c], 4)} changes ${njScores[mainIndex].columns[c]} pattern ${columnPatterns[c]}`);
const rateLines: string[] = []; let rejectedRates = 0;
for (let a = 0; a < ingroup.length; a++) for (const j of ingroup.slice(a + 1)) {
  const i = ingroup[a]; let m1 = 0, m2 = 0;
  for (let c = 0; c < length; c++) {
    const x = sequences[i][c], y = sequences[j][c], z = sequences[outgroup][c];
    if (!bases.includes(x) || !bases.includes(y) || !bases.includes(z) || x === y) continue;
    if (y === z) m1++; if (x === z) m2++;
  }
  const difference = m1 - m2, reject = 1000 * difference * difference > 3841 * (m1 + m2); if (reject) rejectedRates++;
  rateLines.push(`RRT ${names[i]} ${names[j]} m1 ${m1} m2 ${m2} chi2 ${real(m1 + m2 ? difference * difference / (m1 + m2) : null, 4)} ${reject ? 'reject' : 'ok'}`);
}
const rootDistances = paths(mainTree, rooted(mainTree, outgroup).root), tips = ingroup.map(i => rootDistances.get(i)!.length), tipMean = sum(tips) / ingroup.length;
const tipSd = Math.sqrt(sum(tips.map(value => (value - tipMean) * (value - tipMean))) / (ingroup.length - 1));
const clock = [`RELATIVE_RATE outgroup ${names[outgroup]} pairs ${rateLines.length} rejected ${rejectedRates}`, ...rateLines,
  `ROOT_TO_TIP ${mainName} mean ${real(tipMean, 5)} sd ${real(tipSd, 5)} cv ${real(tipSd / tipMean, 4)}`, ...ingroup.map((i, position) => `TIP ${names[i]} ${real(tips[position], 5)}`)];
function quartets(clades: Set<number>): number[] {
  const topologies: number[] = [];
  const separates = (left: number, right: number): boolean => [...clades].some(mask => (contains(mask, left) && !(mask & right)) || (contains(mask, right) && !(mask & left)));
  for (let a = 0; a < count; a++) for (let b = a + 1; b < count; b++) for (let c = b + 1; c < count; c++) for (let d = c + 1; d < count; d++) {
    const x = 2 ** a, y = 2 ** b, z = 2 ** c, w = 2 ** d;
    topologies.push(separates(x | y, z | w) ? 1 : separates(x | z, y | w) ? 2 : separates(x | w, y | z) ? 3 : 0);
  }
  return topologies;
}
const quartetTopologies = splitSets.map(quartets), mainBranches = new Map(branches(mainTree, outgroup).map(b => [b.mask, b.length]));
const comparison = trees.map((tree, i) => {
  const score = i === 5 ? null : i < 3 ? njScores[i].score : fitch(tree, sequences, outgroup).score, clades = splitSets[i];
  let sse: number | null = null, totalLength: number | null = null;
  if (i < 3) { const fitted = patristic(tree, taxa); sse = sum(pairCounts.map(p => { const residual = matrices.get(models[i])![p.i][p.j] - fitted[p.i][p.j]; return residual * residual; })); totalLength = sum(branches(tree, outgroup).map(b => b.length)); }
  if (i === 4) totalLength = mp.score / length;
  return `TREE ${methods[i]} splits ${clades.size} supported ${[...clades].filter(mask => 2 * (support.get(mask) ?? 0) > replicates).length} parsimony ${score ?? '-'} bme ${i === 5 ? '-' : real(bme(tree), 5)} length ${real(totalLength, 5)} negative ${i < 3 ? tree.negative : '-'} sse ${real(sse, 6)} loglik ${i < 3 ? real(logLikelihoods[i], 4) : '-'}`;
});
comparison.push('RF ' + methods.join(' '), ...methods.map((method, a) => method + ' ' + splitSets.map(b => rf(splitSets[a], b)).join(' ')),
  'QUARTET ' + methods.join(' '), ...methods.map((method, a) => method + ' ' + quartetTopologies.map(b => quartetTopologies[a].filter((value, q) => value !== b[q]).length).join(' ')));
const allClades = [...new Set(splitSets.flatMap(set => [...set]))].sort(maskOrder);
for (const mask of allClades) comparison.push(`CLADE ${symbols(mask)} support ${support.get(mask) ?? 0} trees ${splitSets.map(set => set.has(mask) ? '+' : '-').join('')} length ${real(mainBranches.get(mask) ?? null, 5)} changes ${mp.changes.get(mask) ?? '-'}`);
const hypotheses: string[] = [], exhaustiveIngroupMask = exhaustiveTaxa.filter(i => i !== outgroup).reduce((mask, i) => mask | 2 ** i, 0);
for (const line of lines('clades.txt')) {
  const [name, ...requested] = line.split(' '), unknown = requested.find(taxon => !names.includes(taxon));
  if (unknown !== undefined) { hypotheses.push(`INVALID ${name} unknown taxon ${unknown}`); continue; }
  if (requested.includes(names[outgroup])) { hypotheses.push(`INVALID ${name} contains outgroup`); continue; }
  const mask = requested.reduce((mask, taxon) => mask | 2 ** names.indexOf(taxon), 0);
  hypotheses.push(`CLADE ${name} taxa ${popcount(mask)} support ${support.get(mask) ?? 0}`);
  splitSets.forEach((clades, i) => {
    const common = [...clades, ingroupMask].filter(clade => contains(clade, mask)).sort((a, b) => popcount(a) - popcount(b))[0];
    const intruders = taxa.filter(i => (common & 2 ** i) && !(mask & 2 ** i)).map(i => names[i]);
    hypotheses.push(`TEST ${name} ${methods[i]} monophyletic ${common === mask ? 'yes' : 'no'} mrca ${popcount(common)} intruders ${intruders.length ? intruders.join(',') : '-'}`);
  });
  const subset = mask & exhaustiveIngroupMask, size = popcount(subset);
  if (size < 2 || size >= popcount(exhaustiveIngroupMask)) hypotheses.push(`SUBSET ${name} untestable`);
  else {
    const withClade = exhaustive.filter(tree => tree.clades.has(subset)), without = exhaustive.filter(tree => !tree.clades.has(subset));
    hypotheses.push(`SUBSET ${name} taxa ${size} with ${Math.min(...withClade.map(tree => tree.score))} without ${Math.min(...without.map(tree => tree.score))} bme_with ${real(Math.min(...withClade.map(tree => tree.bme)), 5)} bme_without ${real(Math.min(...without.map(tree => tree.bme)), 5)}`);
  }
}
write('summary.txt', summary); write('distances.txt', distanceReport); write('trees.nwk', treeReport); write('cladograms.txt', cladograms);
write('parsimony.txt', parsimonyReport); write('likelihood.txt', likelihoodReport); write('bootstrap.txt', bootstrap); write('clock.txt', clock);
write('comparison.txt', comparison); write('hypotheses.txt', hypotheses);
