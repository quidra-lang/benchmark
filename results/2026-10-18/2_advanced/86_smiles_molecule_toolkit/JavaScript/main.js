'use strict';

const fs = require('node:fs');
const { MoleculeError, dataLines, readElements, Molecule, multiplicityTotal, needsPi, organicHydrogens } = require('./molecule');
const { parseSmiles } = require('./smiles_parser');
const { findRings, kekulize } = require('./rings_aromatic');
const { canonicalize } = require('./canonical');
const { readPatternAtom, moleculePattern, embeddings, fingerprint, similarity } = require('./search');

const TYPES = ['MATCH', 'CONTAINS', 'MATRIX', 'NEAREST', 'WITHIN', 'COMPARE', 'CLUSTER'];
const validName = text => typeof text === 'string' && /^[A-Za-z0-9_-]{1,32}$/.test(text);
const asciiCompare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const validNumber = (text, low, high) => /^(0|[1-9][0-9]*)$/.test(text) && Number(text) >= low && Number(text) <= high;
const fractionCompare = (a, b) => a.p * b.q - b.p * a.q;
const names = molecules => molecules.map(molecule => molecule.name).join(',');

function fractionText(value) {
  if (value.p === 0) return '0/1';
  let a = value.p, b = value.q;
  while (b !== 0) [a, b] = [b, a % b];
  return value.p / a + '/' + value.q / a;
}

function threshold(text) {
  const values = text.split('/');
  if (values.length !== 2 || !validNumber(values[0], 0, 99) || !validNumber(values[1], 1, 99) || Number(values[0]) > Number(values[1])) return null;
  return { p: Number(values[0]), q: Number(values[1]) };
}

function analyze(molecule) {
  findRings(molecule);
  for (const bond of molecule.bonds) {
    bond.type = bond.rawType === null ? molecule.atoms[bond.a].aromatic && molecule.atoms[bond.b].aromatic && bond.ring ? 4 : 1 : bond.rawType;
  }
  const needed = new Set(molecule.atoms.filter(atom => needsPi(atom)).map(atom => atom.index));
  kekulize(molecule, needed);
  for (const atom of molecule.atoms) {
    if (atom.bracket) {
      if (multiplicityTotal(atom) + atom.hydrogens > atom.element.maximum + Math.abs(atom.charge)) throw new MoleculeError('bad valence', atom.column);
    } else {
      const hydrogens = organicHydrogens(atom);
      if (hydrogens === null) throw new MoleculeError('bad valence', atom.column);
      atom.hydrogens = hydrogens;
    }
  }
}

function molecularProperties(molecule, elements) {
  const counts = new Map();
  let weight = 0, hydrogens = 0, heavy = 0, charge = 0, donors = 0, acceptors = 0, rotatable = 0;
  const heavyDegrees = molecule.atoms.map(atom => atom.neighbors.filter(neighbor => molecule.atoms[neighbor.atom].element.symbol !== 'H').length);
  const triples = molecule.atoms.map(atom => atom.neighbors.some(neighbor => neighbor.bond.multiplicity === 3));
  for (const atom of molecule.atoms) {
    const symbol = atom.element.symbol;
    counts.set(symbol, (counts.get(symbol) || 0) + 1); hydrogens += atom.hydrogens;
    weight += atom.mass === 0 ? atom.element.mass : atom.mass * 1000; charge += atom.charge;
    if (symbol !== 'H') heavy++;
    if (symbol === 'N' || symbol === 'O') {
      acceptors++;
      const attached = atom.hydrogens + atom.neighbors.filter(neighbor => molecule.atoms[neighbor.atom].element.symbol === 'H').length;
      if (attached > 0) donors++;
    }
  }
  if (hydrogens > 0) counts.set('H', (counts.get('H') || 0) + hydrogens);
  weight += hydrogens * elements.get('H').mass;
  let symbols = Array.from(counts.keys()).sort(asciiCompare);
  if (counts.has('C')) symbols = ['C', ...(counts.has('H') ? ['H'] : []), ...symbols.filter(symbol => symbol !== 'C' && symbol !== 'H')];
  const formula = symbols.map(symbol => symbol + (counts.get(symbol) === 1 ? '' : counts.get(symbol))).join('');
  for (const bond of molecule.bonds) {
    if (bond.multiplicity === 1 && !bond.ring && heavyDegrees[bond.a] >= 2 && heavyDegrees[bond.b] >= 2 && !triples[bond.a] && !triples[bond.b]) rotatable++;
  }
  const violations = Number(weight > 500000) + Number(donors > 5) + Number(acceptors > 10);
  return { formula, weight, weightText: Math.floor(weight / 1000) + '.' + String(weight % 1000).padStart(3, '0'), heavy,
    rings: molecule.rings.length, rotatable, donors, acceptors, lipinski: violations <= 1 ? 'pass' : 'fail', charge };
}

function scaffold(molecule) {
  if (molecule.rings.length === 0) return null;
  const remaining = new Set(molecule.atoms.map(atom => atom.index));
  while (true) {
    const removable = molecule.atoms.find(atom => remaining.has(atom.index) && !atom.ring &&
      atom.neighbors.filter(neighbor => remaining.has(neighbor.atom)).length === 1);
    if (!removable) break;
    remaining.delete(removable.index);
  }
  const kept = new Set(remaining);
  for (const index of remaining) for (const neighbor of molecule.atoms[index].neighbors) {
    if (!remaining.has(neighbor.atom) && neighbor.bond.type === 2) kept.add(neighbor.atom);
  }
  const result = new Molecule(), renumber = new Map();
  for (const atom of molecule.atoms) if (kept.has(atom.index)) {
    const extra = atom.neighbors.filter(neighbor => !kept.has(neighbor.atom)).reduce((sum, neighbor) => sum + neighbor.bond.multiplicity, 0);
    const index = result.addAtom({ ...atom, hydrogens: atom.hydrogens + extra });
    renumber.set(atom.index, index); result.atoms[index].ring = atom.ring;
  }
  for (const original of molecule.bonds) if (kept.has(original.a) && kept.has(original.b)) {
    const bond = result.addBond(renumber.get(original.a), renumber.get(original.b), original.rawType);
    bond.type = original.type; bond.multiplicity = original.multiplicity; bond.ring = original.ring;
  }
  result.finalize();
  return canonicalize(result).smiles;
}

function ringSystems(molecule) {
  const rings = molecule.rings, sets = rings.map(ring => new Set(ring)), relations = new Map();
  const neighbors = rings.map(() => []);
  for (let i = 0; i < rings.length; i++) for (let j = i + 1; j < rings.length; j++) {
    const common = rings[i].filter(atom => sets[j].has(atom));
    if (common.length === 0) continue;
    const relation = common.length === 1 ? 'spiro' : common.length === 2 && molecule.bond(common[0], common[1]) ? 'fused' : 'bridged';
    neighbors[i].push(j); neighbors[j].push(i); relations.set(i + ',' + j, relation);
  }
  const visited = new Set(), systems = [];
  for (let i = 0; i < rings.length; i++) {
    if (visited.has(i)) continue;
    const component = [i]; visited.add(i);
    for (let front = 0; front < component.length; front++) for (const j of neighbors[component[front]]) if (!visited.has(j)) {
      visited.add(j); component.push(j);
    }
    component.sort((a, b) => a - b);
    let kind = component.length === 1 ? 'isolated' : 'spiro';
    for (let a = 0; a < component.length; a++) for (let b = a + 1; b < component.length; b++) {
      const relation = relations.get(component[a] + ',' + component[b]);
      if (relation === 'bridged') kind = 'bridged';
      else if (relation === 'fused' && kind !== 'bridged') kind = 'fused';
    }
    const atoms = new Set(component.flatMap(index => rings[index]));
    systems.push({ rings: component.map(index => index + 1), kind, atoms: atoms.size });
  }
  return systems;
}

function readMolecules(elements, causes) {
  const records = dataLines('input/molecules.smi'), used = new Set(), molecules = [], errors = [], byName = new Map();
  const reject = (line, cause) => { errors.push(line); causes.set(cause, (causes.get(cause) || 0) + 1); };
  for (const record of records) {
    const fields = record.text.split(' ');
    if (fields.length !== 2 || fields[0] === '' || !validName(fields[1])) { reject(`line ${record.line}: bad line`, 'bad line'); continue; }
    const [text, name] = fields;
    if (used.has(name)) { reject(`line ${record.line} ${name}: duplicate name`, 'duplicate name'); continue; }
    used.add(name);
    try {
      const molecule = parseSmiles(text, elements); analyze(molecule);
      molecule.name = name; molecule.index = molecules.length; molecules.push(molecule); byName.set(name, molecule);
    } catch (error) {
      if (!(error instanceof MoleculeError)) throw error;
      reject(`line ${record.line} ${name}: ${error.reason} at column ${error.column}`, error.reason);
    }
  }
  for (const molecule of molecules) {
    molecule.properties = molecularProperties(molecule, elements);
    const canonical = canonicalize(molecule);
    molecule.canonical = canonical.smiles; molecule.classes = canonical.classes; molecule.scaffold = scaffold(molecule);
    molecule.systems = ringSystems(molecule); molecule.fingerprint = fingerprint(molecule);
  }
  return { records, molecules, byName, errors };
}

function readQueries(elements, molecules, causes) {
  const records = dataLines('input/queries.txt'), used = new Set(), queries = [], errors = [];
  const reject = (line, cause) => { errors.push(line); causes.set(cause, (causes.get(cause) || 0) + 1); };
  for (const record of records) {
    const [type, id, ...args] = record.text.split(' ');
    if (!TYPES.includes(type)) { reject(`line ${record.line}: unknown query`, 'unknown query'); continue; }
    if (!validName(id)) { reject(`line ${record.line} ${type}: bad id`, 'bad id'); continue; }
    const prefix = `line ${record.line} ${type} ${id}: `;
    if (used.has(id)) { reject(prefix + 'duplicate id', 'duplicate id'); continue; }
    used.add(id);
    const count = type === 'MATCH' || type === 'CLUSTER' ? args.length === 1 : type === 'MATRIX' ? args.length >= 2 && args.length <= 12 : args.length === 2;
    if (!count) { reject(prefix + 'bad arguments', 'bad arguments'); continue; }
    const query = { type, id, args };
    let reason = null, cause = null;
    if (type === 'MATCH') {
      try { query.pattern = parseSmiles(args[0], elements, readPatternAtom); }
      catch (error) {
        if (!(error instanceof MoleculeError)) throw error;
        reason = `bad pattern ${error.reason} at column ${error.column}`; cause = 'bad pattern';
      }
    } else if (type === 'CLUSTER') {
      query.threshold = threshold(args[0]);
      if (query.threshold === null) reason = cause = 'bad threshold';
    } else {
      const requested = type === 'NEAREST' || type === 'WITHIN' ? args.slice(0, 1) : args;
      const unknown = requested.find(name => !molecules.byName.has(name));
      if (unknown !== undefined) { reason = 'unknown molecule ' + unknown; cause = 'unknown molecule'; }
      else if (type === 'NEAREST') {
        if (!validNumber(args[1], 1, 99)) reason = cause = 'bad count';
        else query.count = Number(args[1]);
      } else if (type === 'WITHIN') {
        query.threshold = threshold(args[1]);
        if (query.threshold === null) reason = cause = 'bad threshold';
      } else if (new Set(args).size !== args.length) reason = cause = 'repeated molecule';
      if (reason === null) query.molecules = requested.map(name => molecules.byName.get(name));
    }
    if (reason !== null) reject(prefix + reason, cause);
    else queries.push(query);
  }
  return { records, queries, errors };
}

function groupBy(molecules, key) {
  const groups = new Map();
  for (const molecule of molecules) {
    const value = key(molecule);
    if (!groups.has(value)) groups.set(value, []);
    groups.get(value).push(molecule);
  }
  return groups;
}

function canonicalReport(molecules) {
  const byCanonical = groupBy(molecules, molecule => molecule.canonical), byFormula = groupBy(molecules, molecule => molecule.properties.formula);
  const canonical = [`CANONICAL molecules=${molecules.length} unique=${byCanonical.size}`];
  for (const molecule of molecules) {
    const charge = molecule.properties.charge;
    canonical.push(`${molecule.name} ${molecule.canonical} classes=${molecule.classes} charge=${charge > 0 ? '+' : ''}${charge}`);
  }
  const duplicateGroups = Array.from(byCanonical).filter(([, members]) => members.length >= 2);
  const duplicates = [`DUPLICATES groups=${duplicateGroups.length} molecules=${duplicateGroups.reduce((sum, [, members]) => sum + members.length, 0)}`];
  duplicateGroups.forEach(([smiles, members], i) => duplicates.push(`group ${i + 1} ${smiles} members=${names(members)}`));
  const isomerGroups = Array.from(byFormula).map(([formula, members]) => ({ formula, members, forms: new Set(members.map(molecule => molecule.canonical)).size }))
    .filter(group => group.forms >= 2);
  const isomers = [`ISOMERS groups=${isomerGroups.length}`];
  isomerGroups.forEach((group, i) => isomers.push(`isomer ${i + 1} ${group.formula} forms=${group.forms} members=${names(group.members)}`));
  const cyclic = molecules.filter(molecule => molecule.scaffold !== null), byScaffold = groupBy(cyclic, molecule => molecule.scaffold);
  const scaffoldGroups = Array.from(byScaffold).sort((a, b) => b[1].length - a[1].length || asciiCompare(a[0], b[0]));
  const scaffolds = [`SCAFFOLDS distinct=${byScaffold.size} acyclic=${molecules.length - cyclic.length}`];
  scaffoldGroups.forEach(([smiles, members], i) => scaffolds.push(`scaffold ${i + 1} ${smiles} count=${members.length} members=${names(members)}`));
  return [canonical, duplicates, isomers, scaffolds];
}

function ringsReport(molecules) {
  const paragraphs = [], sizes = new Map(), kinds = { isolated: 0, fused: 0, spiro: 0, bridged: 0 };
  let ringCount = 0, aromaticCount = 0;
  for (const molecule of molecules) {
    if (molecule.rings.length === 0) continue;
    const descriptions = molecule.rings.map(ring => ({ ring, aromatic: ring.every(index => molecule.atoms[index].aromatic),
      hetero: ring.filter(index => molecule.atoms[index].element.symbol !== 'C').length }));
    const aromatic = descriptions.filter(ring => ring.aromatic).length;
    const ringAtoms = molecule.atoms.filter(atom => atom.ring).length, ringBonds = molecule.bonds.filter(bond => bond.ring).length;
    const lines = [`MOLECULE ${molecule.name} atoms=${molecule.atoms.length} bonds=${molecule.bonds.length} rings=${molecule.rings.length} aromatic=${aromatic} systems=${molecule.systems.length} ring_atoms=${ringAtoms} ring_bonds=${ringBonds}`];
    descriptions.forEach((description, i) => {
      const { ring, aromatic, hetero } = description;
      lines.push(`ring ${i + 1} size=${ring.length} aromatic=${aromatic ? 'yes' : 'no'} hetero=${hetero} atoms=${ring.map(index => index + 1).join('-')}`);
      sizes.set(ring.length, (sizes.get(ring.length) || 0) + 1);
    });
    molecule.systems.forEach((system, i) => {
      lines.push(`system ${i + 1} kind=${system.kind} rings=${system.rings.join(',')} atoms=${system.atoms}`); kinds[system.kind]++;
    });
    const kekule = molecule.bonds.filter(bond => bond.type === 4 && bond.multiplicity === 2).map(bond => `${bond.a + 1}=${bond.b + 1}`);
    lines.push('kekule ' + (kekule.length ? kekule.join(' ') : '-'));
    paragraphs.push(lines); ringCount += molecule.rings.length; aromaticCount += aromatic;
  }
  const sizeText = Array.from(sizes.keys()).sort((a, b) => a - b).map(size => size + '=' + sizes.get(size));
  paragraphs.push([`SUMMARY molecules=${molecules.length} cyclic=${paragraphs.length} rings=${ringCount} aromatic=${aromaticCount}`,
    'sizes ' + (sizeText.length ? sizeText.join(' ') : '-'),
    `systems isolated=${kinds.isolated} fused=${kinds.fused} spiro=${kinds.spiro} bridged=${kinds.bridged}`]);
  return paragraphs;
}

function substructureReport(molecules, queries) {
  const paragraphs = [];
  let patterns = 0, hits = 0, contains = 0, found = 0;
  for (const query of queries) {
    if (query.type === 'MATCH') {
      patterns++;
      const matches = [], lines = [];
      let total = 0, top = null;
      for (const molecule of molecules) {
        const result = embeddings(query.pattern, molecule);
        if (result.count === 0) continue;
        const match = { molecule, ...result }; matches.push(match); total += result.count;
        if (top === null || result.count > top.count) top = match;
      }
      hits += matches.length;
      lines.push(`MATCH ${query.id} ${query.args[0]} atoms=${query.pattern.atoms.length} bonds=${query.pattern.bonds.length} hits=${matches.length} embeddings=${total}`);
      for (const match of matches) lines.push(`${match.molecule.name} count=${match.count} unique=${match.unique} map=${match.first.join(',')}`);
      if (top !== null) lines.push(`top ${top.molecule.name} count=${top.count}`);
      paragraphs.push(lines);
    } else if (query.type === 'CONTAINS') {
      contains++;
      const [first, second] = query.molecules, result = embeddings(moleculePattern(first), second);
      const prefix = `CONTAINS ${query.id} ${first.name} ${second.name} result=`;
      if (result.count > 0) {
        found++; paragraphs.push([prefix + `yes count=${result.count} unique=${result.unique} map=${result.first.join(',')}`]);
      } else paragraphs.push([prefix + 'no']);
    }
  }
  paragraphs.push([`SUMMARY patterns=${patterns} hits=${hits} contains=${contains} found=${found}`]);
  return paragraphs;
}

function similarityReport(molecules, queries) {
  const fingerprints = [`FINGERPRINTS molecules=${molecules.length} size=1024 depth=5`];
  for (const molecule of molecules) fingerprints.push(`${molecule.name} bits=${molecule.fingerprint.bits.size} paths=${molecule.fingerprint.paths}`);
  const paragraphs = [fingerprints], cache = new Map();
  const coefficient = (first, second) => {
    const key = Math.min(first.index, second.index) * molecules.length + Math.max(first.index, second.index);
    if (!cache.has(key)) cache.set(key, similarity(first.fingerprint, second.fingerprint));
    return cache.get(key);
  };
  for (const query of queries) {
    const { type, id } = query;
    if (type === 'MATCH' || type === 'CONTAINS') continue;
    const lines = [];
    if (type === 'MATRIX') {
      const requested = query.molecules;
      lines.push(`MATRIX ${id} size=${requested.length}`);
      for (const molecule of requested) lines.push('row ' + molecule.name + ' ' + requested.map(other => fractionText(coefficient(molecule, other))).join(' '));
      let best = null;
      for (let i = 0; i < requested.length; i++) for (let j = i + 1; j < requested.length; j++) {
        const value = coefficient(requested[i], requested[j]);
        if (best === null || fractionCompare(value, best.value) > 0) best = { first: requested[i], second: requested[j], value };
      }
      lines.push(`best ${best.first.name} ${best.second.name} ${fractionText(best.value)}`);
    } else if (type === 'NEAREST' || type === 'WITHIN') {
      const source = query.molecules[0];
      let results = molecules.filter(molecule => molecule !== source).map(molecule => ({ molecule, value: coefficient(source, molecule) }));
      results.sort((a, b) => -fractionCompare(a.value, b.value) || a.molecule.index - b.molecule.index);
      results = type === 'NEAREST' ? results.slice(0, query.count) : results.filter(result => fractionCompare(result.value, query.threshold) >= 0);
      lines.push(`${type} ${id} ${source.name}` + (type === 'WITHIN' ? ' threshold=' + fractionText(query.threshold) : '') + ' count=' + results.length);
      results.forEach((result, i) => lines.push(`${i + 1} ${result.molecule.name} ${fractionText(result.value)} common=${result.value.common}`));
    } else if (type === 'COMPARE') {
      const [first, second] = query.molecules, value = coefficient(first, second);
      lines.push(`COMPARE ${id} ${first.name} ${second.name} bits=${first.fingerprint.bits.size},${second.fingerprint.bits.size} common=${value.common} union=${value.union} tanimoto=${fractionText(value)} identical=${first.canonical === second.canonical ? 'yes' : 'no'}`);
    } else {
      const neighbors = molecules.map(molecule => molecules.filter(other => other !== molecule && fractionCompare(coefficient(molecule, other), query.threshold) >= 0));
      const order = molecules.slice().sort((a, b) => neighbors[b.index].length - neighbors[a.index].length || a.index - b.index);
      const assigned = new Set(), clusters = [];
      for (const center of order) if (!assigned.has(center.index)) {
        const members = [center, ...neighbors[center.index].filter(molecule => !assigned.has(molecule.index))];
        for (const molecule of members) assigned.add(molecule.index);
        clusters.push({ center, members });
      }
      const singletons = clusters.filter(cluster => cluster.members.length === 1).length;
      lines.push(`CLUSTER ${id} threshold=${fractionText(query.threshold)} clusters=${clusters.length} singletons=${singletons}`);
      let number = 0;
      for (const cluster of clusters) if (cluster.members.length >= 2) {
        lines.push(`cluster ${++number} centroid=${cluster.center.name} size=${cluster.members.length} members=${names(cluster.members)}`);
      }
    }
    paragraphs.push(lines);
  }
  return paragraphs;
}

function errorsReport(molecules, queries, causes) {
  const first = [`MOLECULES lines=${molecules.records.length} valid=${molecules.molecules.length} errors=${molecules.errors.length}`, ...molecules.errors];
  const second = [`QUERIES lines=${queries.records.length} valid=${queries.queries.length} errors=${queries.errors.length}`, ...queries.errors];
  const ordered = Array.from(causes).sort((a, b) => b[1] - a[1] || asciiCompare(a[0], b[0]));
  const third = [`CAUSES kinds=${causes.size}`, ...ordered.map(([cause, count]) => cause + '=' + count)];
  return [first, second, third];
}

function main() {
  const elements = readElements('input/elements.txt'), causes = new Map();
  const moleculeData = readMolecules(elements, causes), queryData = readQueries(elements, moleculeData, causes);
  const molecules = moleculeData.molecules, queries = queryData.queries;
  const properties = ['name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski'];
  for (const molecule of molecules) {
    const value = molecule.properties;
    properties.push([molecule.name, value.formula, value.weightText, value.heavy, value.rings, value.rotatable, value.donors, value.acceptors, value.lipinski].join(','));
  }
  const reports = [
    ['canonical.txt', canonicalReport(molecules)], ['rings.txt', ringsReport(molecules)],
    ['substructure.txt', substructureReport(molecules, queries)], ['similarity.txt', similarityReport(molecules, queries)],
    ['errors.txt', errorsReport(moleculeData, queryData, causes)],
  ];
  fs.mkdirSync('output', { recursive: true });
  fs.writeFileSync('output/properties.csv', properties.join('\n') + '\n', 'ascii');
  for (const [name, paragraphs] of reports) fs.writeFileSync('output/' + name, paragraphs.map(lines => lines.join('\n')).join('\n\n') + '\n', 'ascii');
}

main();
