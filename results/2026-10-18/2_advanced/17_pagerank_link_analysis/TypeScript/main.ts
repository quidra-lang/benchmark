import { readInput, type Input, type LinkRecord } from './graph_io.ts';
import { strongComponents, reachable, distances, weakComponents } from './components.ts';
import { pageRank, type WeightedGraph, type PageRankResult } from './pagerank.ts';
import { hits } from './hits.ts';
import { real, roundedInteger, fraction, writeReports } from './report.ts';

type Edge = [source: number, destination: number, weight: number];
type IgnoreReason = 'unknown' | 'self' | 'duplicate';
interface GraphData extends Input {
  all: number[]; pageIndex: Map<number, number>; hosts: string[]; edges: Edge[]; interEdges: Edge[];
  ignored: (LinkRecord & { reason: IgnoreReason })[]; ignoredCounts: Record<IgnoreReason, number>;
  graph: WeightedGraph; interGraph: WeightedGraph; intraCount: number; reciprocal: number;
}
interface Ranking { values: number[]; rounded: number[]; order: number[]; position: number[] }
interface IterationRun { heading: string; run: PageRankResult }
interface Demotion { hosts: string[]; removed: number; ranking: Ranking }
interface RelatedPage { node: number; count: number }
type UndirectedStatistics = ReturnType<typeof undirectedStatistics>;
interface Statistics {
  undirected: UndirectedStatistics;
  components: ReturnType<typeof componentStatistics>;
  distances: ReturnType<typeof distanceStatistics>;
}
type ScoreState = ReturnType<typeof calculateScores>;
type QueryResult = ReturnType<typeof queryAnalyses>[number];
type HostResult = ReturnType<typeof hostAnalysis>;
const SCORE_NAMES = ['pagerank', 'cheirank', 'authority', 'hub', 'trustrank', 'harmonic'] as const;
type ScoreName = typeof SCORE_NAMES[number];
const REGIONS = ['CORE', 'IN', 'OUT', 'TUBE', 'IN_TENDRIL', 'OUT_TENDRIL', 'OTHER'];
const QUANTITIES: ('in_degree' | ScoreName)[] = ['in_degree', ...SCORE_NAMES];

function sum(values: number[]): number;
function sum<T>(values: T[], valueOf: (value: T) => number): number;
function sum<T>(values: T[], valueOf?: (value: T) => number): number {
  let result = 0;
  for (const value of values) {
    if (valueOf) result += valueOf(value);
    else if (typeof value === 'number') result += value;
  }
  return result;
}
function distribution(values: number[]) {
  const counts = new Map<number, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts].sort((first, second) => first[0] - second[0]);
}
function makeGraph(count: number, edges: Edge[]): WeightedGraph {
  const weights = Array.from({ length: count }, () => new Map<number, number>());
  for (const [source, destination, weight] of edges)
    weights[source].set(destination, (weights[source].get(destination) ?? 0) + weight);
  const outgoing = weights.map(row => [...row.keys()].sort((first, second) => first - second));
  const incoming = Array.from({ length: count }, (): number[] => []);
  outgoing.forEach((row, source) => { for (const destination of row) incoming[destination].push(source); });
  const totals = outgoing.map((row, source) => sum(row, destination => weights[source].get(destination)!));
  return { out: outgoing, in: incoming, weights, totals };
}
function buildGraph(input: Input): GraphData {
  const all = input.pages.map((_, index) => index), pageIndex = new Map(input.pages.map((page, index) => [page.id, index]));
  const hosts = [...new Set(input.pages.map(page => page.host))].sort(), edges: Edge[] = [];
  const ignored: GraphData['ignored'] = [], ignoredCounts = { unknown: 0, self: 0, duplicate: 0 }, accepted = new Set<string>();
  for (const record of input.records) {
    const key = `${record.source},${record.destination}`;
    let reason: IgnoreReason | null = null;
    if (!pageIndex.has(record.source) || !pageIndex.has(record.destination)) reason = 'unknown';
    else if (record.source === record.destination) reason = 'self';
    else if (accepted.has(key)) reason = 'duplicate';
    if (reason !== null) { ignored.push({ ...record, reason }); ignoredCounts[reason]++; }
    else { accepted.add(key); edges.push([pageIndex.get(record.source)!, pageIndex.get(record.destination)!, 1]); }
  }
  const graph = makeGraph(input.pages.length, edges);
  const interEdges = edges.filter(([source, destination]) => input.pages[source].host !== input.pages[destination].host);
  const interGraph = makeGraph(input.pages.length, interEdges), intraCount = edges.length - interEdges.length;
  const reciprocal = edges.filter(([source, destination]) => graph.weights[destination].has(source)).length;
  return { ...input, all, pageIndex, hosts, edges, ignored, ignoredCounts, graph, interEdges, interGraph, intraCount, reciprocal };
}
function undirectedStatistics(data: GraphData) {
  const adjacent = data.all.map(node => [...new Set([...data.graph.out[node], ...data.graph.in[node]])]
    .sort((first, second) => first - second));
  const sets = adjacent.map(row => new Set(row)), degree = adjacent.map(row => row.length);
  let closedTriples = 0, triples = 0, clustering = 0, eligible = 0;
  for (const node of data.all) {
    if (degree[node] < 2) continue;
    let count = 0;
    const neighbours = adjacent[node];
    for (let i = 0; i < neighbours.length; i++) for (let j = i + 1; j < neighbours.length; j++)
      if (sets[neighbours[i]].has(neighbours[j])) count++;
    const pairs = degree[node] * (degree[node] - 1) / 2;
    closedTriples += count; triples += pairs; clustering += count / pairs; eligible++;
  }
  const remaining = new Set(data.all), remainingDegree = degree.slice(), kcore: number[] = Array(data.pages.length).fill(0);
  let level = 0;
  while (remaining.size > 0) {
    const node = data.all.find(candidate => remaining.has(candidate) && remainingDegree[candidate] <= level);
    if (node === undefined) { level++; continue; }
    remaining.delete(node); kcore[node] = level;
    for (const neighbour of adjacent[node]) if (remaining.has(neighbour)) remainingDegree[neighbour]--;
  }
  return { adjacent, edgeCount: sum(degree) / 2, closedTriples, triples,
    clustering: clustering / eligible, eligible, kcore, degeneracy: Math.max(...kcore) };
}
function componentStatistics(data: GraphData, undirected: UndirectedStatistics) {
  const result = strongComponents(data.graph.out), { groups, component } = result;
  let core = 0;
  for (let index = 1; index < groups.length; index++) if (groups[index].length > groups[core].length) core = index;
  const incoming: number[] = Array(groups.length).fill(0), outgoing: number[] = Array(groups.length).fill(0);
  const condensed = groups.map(() => new Set<number>());
  for (const [source, destination] of data.edges) {
    const from = component[source], to = component[destination];
    if (from === to) continue;
    outgoing[from]++; incoming[to]++; condensed[from].add(to);
  }
  const adjacency = condensed.map(row => [...row].sort((first, second) => first - second));
  const indegree: number[] = Array(groups.length).fill(0), depth: number[] = Array(groups.length).fill(0);
  for (const row of adjacency) for (const node of row) indegree[node]++;
  const pending = groups.map((_, index) => index).filter(index => indegree[index] === 0);
  for (let head = 0; head < pending.length; head++) for (const next of adjacency[pending[head]]) {
    depth[next] = Math.max(depth[next], depth[pending[head]] + 1);
    if (--indegree[next] === 0) pending.push(next);
  }
  const weak = weakComponents(undirected.adjacent), toCore = reachable(groups[core], data.graph.in), fromCore = reachable(groups[core], data.graph.out);
  const inPages = data.all.filter(node => component[node] !== core && toCore.has(node));
  const outPages = data.all.filter(node => component[node] !== core && fromCore.has(node));
  const fromIn = reachable(inPages, data.graph.out), toOut = reachable(outPages, data.graph.in);
  const region = data.all.map(node => {
    if (component[node] === core) return 0;
    if (toCore.has(node)) return 1;
    if (fromCore.has(node)) return 2;
    if (fromIn.has(node) && toOut.has(node)) return 3;
    if (fromIn.has(node)) return 4;
    if (toOut.has(node)) return 5;
    return 6;
  });
  const regions = REGIONS.map((_, index) => data.all.filter(node => region[node] === index));
  const regionLinks: number[][] = REGIONS.map(() => Array(REGIONS.length).fill(0));
  for (const [source, destination] of data.edges) regionLinks[region[source]][region[destination]]++;
  return { ...result, core, incoming, outgoing, condensedEdges: sum(adjacency, row => row.length),
    depth: Math.max(...depth), weak, region, regions, regionLinks };
}
function distanceStatistics(data: GraphData) {
  const harmonic: number[] = Array(data.pages.length).fill(0), counts: number[] = Array(data.pages.length).fill(0);
  let pairs = 0, distanceSum = 0, diameter = 0, first = 0, second = 0;
  for (const source of data.all) {
    const row = distances([source], data.graph.out);
    for (const destination of data.all) {
      if (destination === source || row[destination] < 0) continue;
      const distance = row[destination];
      pairs++; distanceSum += distance; counts[distance]++; harmonic[destination] += 1 / distance;
      if (distance > diameter) { diameter = distance; first = source; second = destination; }
    }
  }
  let cumulative = 0, effective = 0;
  for (let distance = 1; distance <= diameter; distance++) {
    cumulative += counts[distance];
    if (10 * cumulative >= 9 * pairs) { effective = distance; break; }
  }
  return { harmonic, counts, pairs, distanceSum, diameter, first, second, effective };
}
function rankScores(values: number[]): Ranking {
  const rounded = values.map(value => roundedInteger(value));
  const order = values.map((_, index) => index).sort((first, second) => rounded[second] - rounded[first] || first - second);
  const position: number[] = Array(values.length);
  order.forEach((node, index) => { position[node] = index + 1; });
  return { values, rounded, order, position };
}
function topList(ranking: Ranking, limit: number) { return ranking.order.filter(node => ranking.rounded[node] > 0).slice(0, limit); }
function kendall(first: number[], second: number[]) {
  let concordant = 0, discordant = 0;
  for (let i = 0; i < first.length; i++) for (let j = i + 1; j < first.length; j++) {
    const x = first[i] - first[j], y = second[i] - second[j];
    if ((x > 0 && y > 0) || (x < 0 && y < 0)) concordant++;
    else if ((x > 0 && y < 0) || (x < 0 && y > 0)) discordant++;
  }
  return fraction(concordant - discordant, first.length * (first.length - 1) / 2);
}
function compareRankings(original: Ranking, comparison: Ranking, limit: number) {
  let overlap = 0, footrule = 0, largest = -1, shifted = 0;
  for (let node = 0; node < original.values.length; node++) {
    if (original.position[node] <= limit && comparison.position[node] <= limit) overlap++;
    const difference = Math.abs(comparison.position[node] - original.position[node]);
    footrule += difference;
    if (difference > largest) { largest = difference; shifted = node; }
  }
  return { overlap, footrule, shifted, correlation: kendall(original.rounded, comparison.rounded) };
}
function calculateScores(data: GraphData, statistics: Statistics) {
  const settings = data.settings;
  const compute = (graph: WeightedGraph, seeds: number[], damping = settings.damping) =>
    pageRank(graph, seeds, damping, settings.iterations, settings.tolerance);
  const pagerank = compute(data.graph, data.all);
  const reversed = makeGraph(data.pages.length, data.edges.map(([source, destination, weight]) => [destination, source, weight]));
  const cheirank = compute(reversed, data.all);
  const trusted = settings.trusted.map(id => data.pageIndex.get(id)!).sort((first, second) => first - second);
  const trustrank = compute(data.graph, trusted), globalHits = hits(data.interGraph, data.all, settings.hitsIterations);
  const scores: Record<ScoreName, number[]> = { pagerank: pagerank.values, cheirank: cheirank.values,
    authority: globalHits.authority, hub: globalHits.hub, trustrank: trustrank.values, harmonic: statistics.distances.harmonic };
  const ranks: Record<ScoreName, Ranking> = {
    pagerank: rankScores(scores.pagerank), cheirank: rankScores(scores.cheirank), authority: rankScores(scores.authority),
    hub: rankScores(scores.hub), trustrank: rankScores(scores.trustrank), harmonic: rankScores(scores.harmonic),
  };
  const dampingText = real(settings.damping, 4);
  const runs: IterationRun[] = [
    { heading: `pagerank damping ${dampingText}`, run: pagerank },
    { heading: `cheirank damping ${dampingText}`, run: cheirank },
    { heading: `trustrank damping ${dampingText} seeds ${trusted.length}`, run: trustrank },
  ];
  const sweeps = settings.sweep.map(damping => {
    const run = compute(data.graph, data.all, damping), ranking = rankScores(run.values);
    runs.push({ heading: `sweep damping ${real(damping, 4)}`, run });
    return { damping, ranking, comparison: compareRankings(ranks.pagerank, ranking, settings.top) };
  });
  const trustRatio = data.all.map(node => scores.trustrank[node] / scores.pagerank[node]), trustDistance = distances(trusted, data.graph.out);
  const suspects = ranks.pagerank.order.slice(0, settings.spamTop)
    .filter(node => Number(real(trustRatio[node], 4)) < settings.spamThreshold);
  let demotion: Demotion | null = null;
  if (suspects.length > 0) {
    const hosts = [...new Set(suspects.map(node => data.pages[node].host))].sort(), hostSet = new Set(hosts);
    const edges = data.edges.filter(([source, destination]) =>
      data.pages[source].host !== data.pages[destination].host || !hostSet.has(data.pages[source].host));
    const run = compute(makeGraph(data.pages.length, edges), data.all);
    demotion = { hosts, removed: data.edges.length - edges.length, ranking: rankScores(run.values) };
    runs.push({ heading: `demoted damping ${dampingText}`, run });
  }
  return { scores, ranks, runs, sweeps, trustRatio, trustDistance, suspects, demotion };
}
function salsaSide(graph: WeightedGraph, authoritySide: boolean) {
  const degree = (authoritySide ? graph.in : graph.out).map(row => row.length);
  const nodes = degree.map((_, index) => index).filter(node => degree[node] > 0), adjacent = degree.map(() => new Set<number>());
  for (const row of authoritySide ? graph.out : graph.in) for (let i = 0; i < row.length; i++) for (let j = i + 1; j < row.length; j++) {
    adjacent[row[i]].add(row[j]); adjacent[row[j]].add(row[i]);
  }
  const adjacency = adjacent.map(row => [...row].sort((first, second) => first - second)), groups = weakComponents(adjacency, nodes);
  const values: number[] = Array(degree.length).fill(0);
  for (const group of groups) {
    const edges = sum(group, node => degree[node]);
    for (const node of group) values[node] = (group.length * degree[node]) / (nodes.length * edges);
  }
  return values;
}
function queryAnalyses(data: GraphData, state: ScoreState) {
  return data.queries.map((query, index) => {
    const settings = data.settings, seeds = query.seeds.map(id => data.pageIndex.get(id)!).sort((first, second) => first - second);
    const matches = state.ranks.pagerank.order.filter(node => query.words.every(word =>
      word.startsWith('-') ? !data.pages[node].words.has(word.slice(1)) : data.pages[node].words.has(word)));
    const root = matches.slice(0, settings.rootLimit), baseSet = new Set(root);
    for (const node of root) {
      for (const next of data.graph.out[node].slice(0, settings.neighborLimit)) baseSet.add(next);
      for (const next of data.graph.in[node].slice(0, settings.neighborLimit)) baseSet.add(next);
    }
    const base = [...baseSet].sort((first, second) => first - second), edges: Edge[] = [];
    let dropped = 0;
    for (const edge of data.edges) {
      const [source, destination] = edge;
      if (!baseSet.has(source) || !baseSet.has(destination)) continue;
      if (data.pages[source].host === data.pages[destination].host) dropped++;
      else edges.push(edge);
    }
    const personalized = pageRank(data.graph, seeds, settings.damping, settings.iterations, settings.tolerance);
    state.runs.push({ heading: `personalized query ${index + 1} damping ${real(settings.damping, 4)}`, run: personalized });
    const personalRank = rankScores(personalized.values), personalTop = topList(personalRank, settings.top);
    const result = { query, matches, root, base, edgeCount: edges.length, dropped, personalRank, personalTop,
      reach: reachable(seeds, data.graph.out).size, seedMass: sum(seeds, node => personalized.values[node]),
      overlap: personalTop.filter(node => state.ranks.pagerank.position[node] <= settings.top).length };
    if (edges.length === 0) return { ...result, linkAnalysis: null };
    const subgraph = makeGraph(data.pages.length, edges), hitScores = hits(subgraph, base, settings.hitsIterations);
    const hitAuthority = rankScores(hitScores.authority), hitHub = rankScores(hitScores.hub);
    const salsaAuthority = rankScores(salsaSide(subgraph, true)), salsaHub = rankScores(salsaSide(subgraph, false));
    const authorities = topList(hitAuthority, settings.top), hubs = topList(hitHub, settings.top);
    const salsaAuthorities = new Set(topList(salsaAuthority, settings.top)), salsaHubs = new Set(topList(salsaHub, settings.top));
    const relatedTo = authorities[0], citing = data.graph.in[relatedTo], coupledTo = hubs[0], cited = data.graph.out[coupledTo];
    const related: RelatedPage[] = data.all.filter(node => node !== relatedTo).map(node => ({
      node, count: sum(citing, source => data.graph.weights[source].has(node) ? 1 : 0),
    })).filter(record => record.count > 0).sort((first, second) => second.count - first.count || first.node - second.node).slice(0, settings.top);
    const similar: RelatedPage[] = data.all.filter(node => node !== coupledTo).map(node => ({
      node, count: sum(cited, destination => data.graph.weights[node].has(destination) ? 1 : 0),
    })).filter(record => record.count > 0).sort((first, second) => second.count - first.count || first.node - second.node).slice(0, settings.top);
    return { ...result, linkAnalysis: { hitAuthority, hitHub, salsaAuthority, salsaHub,
      authorityOverlap: authorities.filter(node => salsaAuthorities.has(node)).length,
      hubOverlap: hubs.filter(node => salsaHubs.has(node)).length,
      authorityHosts: new Set(authorities.map(node => data.pages[node].host)).size,
      relatedTo, citing, related, coupledTo, cited, similar } };
  });
}
function hostAnalysis(data: GraphData, statistics: Statistics, state: ScoreState) {
  const hostIndex = new Map(data.hosts.map((host, index) => [host, index])), hostOf = data.pages.map(page => hostIndex.get(page.host)!);
  const graph = makeGraph(data.hosts.length, data.interEdges.map(([source, destination]) => [hostOf[source], hostOf[destination], 1]));
  const nodes = data.hosts.map((_, index) => index), run = pageRank(graph, nodes, data.settings.damping, data.settings.iterations, data.settings.tolerance);
  state.runs.push({ heading: `host_pagerank damping ${real(data.settings.damping, 4)} hosts ${nodes.length}`, run });
  const ranking = rankScores(run.values);
  const records = data.hosts.map((name, index) => {
    const members = data.all.filter(node => hostOf[node] === index);
    return { name, members, internal: 0, outgoing: 0, incoming: 0,
      core: members.filter(node => statistics.components.region[node] === 0).length,
      dangling: members.filter(node => data.graph.out[node].length === 0).length,
      pageScore: sum(members, node => state.scores.pagerank[node]),
      representative: state.ranks.pagerank.order.find(node => hostOf[node] === index)! };
  });
  for (const [source, destination] of data.edges) {
    if (hostOf[source] === hostOf[destination]) records[hostOf[source]].internal++;
    else { records[hostOf[source]].outgoing++; records[hostOf[destination]].incoming++; }
  }
  const edges: { source: number; destination: number; weight: number }[] = [];
  let reciprocal = 0;
  for (const source of nodes) for (const destination of graph.out[source]) {
    edges.push({ source, destination, weight: graph.weights[source].get(destination)! });
    if (graph.weights[destination].has(source)) reciprocal++;
  }
  const groups = strongComponents(graph.out).groups;
  const heavy = edges.slice().sort((first, second) => second.weight - first.weight
    || first.source - second.source || first.destination - second.destination).slice(0, data.settings.top);
  return { records, ranking, edges: edges.length, reciprocal, groups, heavy };
}
function rankLines(data: GraphData, nodes: number[], values: number[]) {
  return nodes.map((node, index) => {
    const page = data.pages[node];
    return `${index + 1} ${page.id} ${real(values[node])} ${page.host} ${page.title}`;
  });
}
function pageIds(data: GraphData, nodes: number[]) { return nodes.map(node => data.pages[node].id); }
function graphReport(data: GraphData, statistics: Statistics, state: ScoreState) {
  const incoming = data.graph.in.map(row => row.length), outgoing = data.graph.out.map(row => row.length);
  const dangling = data.all.filter(node => outgoing[node] === 0), noIncoming = data.all.filter(node => incoming[node] === 0);
  const maximumIn = Math.max(...incoming), maximumOut = Math.max(...outgoing);
  const lines = [`pages ${data.pages.length}`, `hosts ${data.hosts.length}`, `link_rows ${data.records.length}`, `links ${data.edges.length}`,
    `ignored_unknown ${data.ignoredCounts.unknown}`, `ignored_self ${data.ignoredCounts.self}`, `ignored_duplicate ${data.ignoredCounts.duplicate}`];
  for (const record of data.ignored) lines.push(`ignored line ${record.line} ${record.source},${record.destination} ${record.reason}`);
  lines.push(`intra_host_links ${data.intraCount}`, `inter_host_links ${data.interEdges.length}`, `mean_degree ${real(data.edges.length / data.pages.length, 4)}`,
    `reciprocity ${fraction(data.reciprocal, data.edges.length)}`,
    [`dangling ${dangling.length}`, ...pageIds(data, dangling)].join(' '),
    [`no_in_links ${noIncoming.length}`, ...pageIds(data, noIncoming)].join(' '),
    [`max_in_degree ${maximumIn} pages`, ...pageIds(data, data.all.filter(node => incoming[node] === maximumIn))].join(' '),
    [`max_out_degree ${maximumOut} pages`, ...pageIds(data, data.all.filter(node => outgoing[node] === maximumOut))].join(' '));
  const degreeTables: [string, number[]][] = [['in_degree_distribution', incoming], ['out_degree_distribution', outgoing]];
  for (const [name, degrees] of degreeTables) {
    lines.push('', name);
    for (const [degree, count] of distribution(degrees)) lines.push(`${degree} ${count}`);
  }
  const undirected = statistics.undirected;
  lines.push('', `undirected_links ${undirected.edgeCount}`, `transitivity ${fraction(undirected.closedTriples, undirected.triples)}`,
    `average_clustering ${real(undirected.clustering, 4)} pages ${undirected.eligible}`,
    `degeneracy ${undirected.degeneracy} pages ${undirected.kcore.filter(value => value === undirected.degeneracy).length}`, 'core_distribution');
  for (const [core, count] of distribution(undirected.kcore)) lines.push(`${core} ${count}`);
  const components = statistics.components;
  lines.push('', `strong_components ${components.groups.length} largest ${components.groups[components.core].length} `
    + `singletons ${components.groups.filter(group => group.length === 1).length} condensation_links ${components.condensedEdges}`,
    `weak_components ${components.weak.length} largest ${Math.max(...components.weak.map(group => group.length))}`, `condensation_depth ${components.depth}`);
  components.groups.forEach((group, index) => {
    if (group.length < 2) return;
    lines.push(`scc ${index + 1} size ${group.length} min ${data.pages[group[0]].id} incoming ${components.incoming[index]} `
      + `outgoing ${components.outgoing[index]} pagerank ${real(sum(group, node => state.scores.pagerank[node]))}`
      + (components.outgoing[index] === 0 ? ' sink' : ''));
  });
  lines.push('', `bowtie core_scc ${components.core + 1}`);
  components.regions.forEach((nodes, index) => {
    let line = `${REGIONS[index]} ${nodes.length} pagerank ${real(sum(nodes, node => state.scores.pagerank[node]))}`;
    if (nodes.length > 0) {
      const first = state.ranks.pagerank.order.find(node => components.region[node] === index)!;
      line += ` top ${data.pages[first].id}`;
      if (nodes.length <= 10) line += ` pages ${pageIds(data, nodes).join(' ')}`;
    }
    lines.push(line);
  });
  lines.push('region_links');
  REGIONS.forEach((from, source) => REGIONS.forEach((to, destination) => {
    const count = components.regionLinks[source][destination];
    if (count > 0) lines.push(`${from} ${to} ${count}`);
  }));
  const distance = statistics.distances;
  lines.push('', 'distances', `reachable_pairs ${distance.pairs}`, `average ${fraction(distance.distanceSum, distance.pairs)}`,
    `diameter ${distance.diameter} from ${data.pages[distance.first].id} to ${data.pages[distance.second].id}`, `effective_diameter ${distance.effective}`);
  for (let value = 1; value <= distance.diameter; value++) lines.push(`${value} ${distance.counts[value]}`);
  return lines;
}
function pageReport(data: GraphData, statistics: Statistics, state: ScoreState) {
  const lines = ['id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance'];
  for (const node of data.all) lines.push([data.pages[node].id, data.graph.in[node].length, data.graph.out[node].length,
    statistics.components.component[node] + 1, REGIONS[statistics.components.region[node]], statistics.undirected.kcore[node],
    real(state.scores.harmonic[node]), real(state.scores.pagerank[node]), state.ranks.pagerank.position[node],
    real(state.scores.cheirank[node]), state.ranks.cheirank.position[node], real(state.scores.authority[node]),
    real(state.scores.hub[node]), real(state.scores.trustrank[node]), real(state.trustRatio[node], 4), state.trustDistance[node]].join(','));
  return lines;
}
function rankingReport(data: GraphData, statistics: Statistics, state: ScoreState, hosts: HostResult) {
  const limit = data.settings.top, pagerankTop = topList(state.ranks.pagerank, limit);
  const lines = [`pagerank top ${limit}`, ...rankLines(data, pagerankTop, state.scores.pagerank)];
  const dangling = data.all.filter(node => data.graph.out[node].length === 0);
  lines.push(`dangling_mass ${real(sum(dangling, node => state.scores.pagerank[node]))}`);
  for (const node of pagerankTop) {
    const contributors = data.graph.in[node].map(source => {
      const value = (data.settings.damping * state.scores.pagerank[source]) / data.graph.out[source].length;
      return { source, value, rounded: roundedInteger(value) };
    }).sort((first, second) => second.rounded - first.rounded || first.source - second.source).slice(0, 3);
    const parts: (string | number)[] = ['contributors', data.pages[node].id];
    for (const contributor of contributors) parts.push(data.pages[contributor.source].id, real(contributor.value));
    lines.push(parts.join(' '));
  }
  for (const name of SCORE_NAMES.slice(1))
    lines.push('', `${name} top ${limit}`, ...rankLines(data, topList(state.ranks[name], limit), state.scores[name]));
  lines.push('', 'correlation');
  const quantities = QUANTITIES.map(name => name === 'in_degree' ? data.graph.in.map(row => row.length) : state.ranks[name].rounded);
  for (let first = 0; first < QUANTITIES.length; first++) for (let second = first + 1; second < QUANTITIES.length; second++)
    lines.push(`${QUANTITIES[first]} ${QUANTITIES[second]} ${kendall(quantities[first], quantities[second])}`);
  lines.push('', 'damping_sweep');
  for (const sweep of state.sweeps) {
    const comparison = sweep.comparison, node = comparison.shifted;
    lines.push(`damping ${real(sweep.damping, 4)} overlap ${comparison.overlap} footrule ${comparison.footrule} `
      + `kendall ${comparison.correlation} largest_shift ${data.pages[node].id} ${state.ranks.pagerank.position[node]} ${sweep.ranking.position[node]}`);
    lines.push(['top', ...pageIds(data, sweep.ranking.order.slice(0, limit))].join(' '));
  }
  lines.push('', `spam top ${data.settings.spamTop} threshold ${real(data.settings.spamThreshold, 4)}`);
  for (const node of state.suspects) lines.push(`suspect ${data.pages[node].id} rank ${state.ranks.pagerank.position[node]} `
    + `pagerank ${real(state.scores.pagerank[node])} trustrank ${real(state.scores.trustrank[node])} `
    + `trust_ratio ${real(state.trustRatio[node], 4)} trust_distance ${state.trustDistance[node]} kcore ${statistics.undirected.kcore[node]} ${data.pages[node].host}`);
  lines.push(`count ${state.suspects.length}`, 'trust_by_distance');
  const trustLevels = [...new Set(state.trustDistance.filter(value => value >= 0))].sort((first, second) => first - second);
  if (state.trustDistance.includes(-1)) trustLevels.push(-1);
  for (const distance of trustLevels) {
    const nodes = data.all.filter(node => state.trustDistance[node] === distance);
    lines.push(`${distance === -1 ? 'unreachable' : distance} pages ${nodes.length} `
      + `trustrank ${real(sum(nodes, node => state.scores.trustrank[node]))} pagerank ${real(sum(nodes, node => state.scores.pagerank[node]))}`);
  }
  lines.push('');
  if (state.demotion === null) lines.push('demotion none');
  else {
    const demotion = state.demotion;
    lines.push(`demotion hosts ${demotion.hosts.join(' ')} removed_links ${demotion.removed}`);
    topList(demotion.ranking, limit).forEach((node, index) => {
      const page = data.pages[node];
      lines.push(`${index + 1} ${page.id} ${real(demotion.ranking.values[node])} was ${state.ranks.pagerank.position[node]} ${page.host} ${page.title}`);
    });
    for (const node of state.suspects) lines.push(`suspect ${data.pages[node].id} before ${state.ranks.pagerank.position[node]} after ${demotion.ranking.position[node]}`);
  }
  lines.push('', `host_graph hosts ${data.hosts.length} links ${hosts.edges} reciprocal ${hosts.reciprocal} `
    + `strong_components ${hosts.groups.length} largest ${Math.max(...hosts.groups.map(group => group.length))}`, `host_links top ${limit}`);
  for (const edge of hosts.heavy) lines.push(`${data.hosts[edge.source]} ${data.hosts[edge.destination]} ${edge.weight}`);
  return lines;
}
function convergenceReport(data: GraphData, state: ScoreState) {
  const lines = [`iterations ${data.settings.iterations} tolerance ${real(data.settings.tolerance, 10)}`];
  for (const { heading, run } of state.runs) {
    lines.push('', heading);
    for (let iteration = 10; iteration <= data.settings.iterations; iteration += 10)
      lines.push(`iteration ${iteration} l1 ${real(run.changes[iteration - 1], 10)}`);
    lines.push(`converged_at ${run.convergedAt ?? 'none'}`);
  }
  return lines;
}
function queriesReport(data: GraphData, state: ScoreState, results: QueryResult[]) {
  const lines: string[] = [];
  results.forEach((result, index) => {
    if (index > 0) lines.push('');
    const query = result.query;
    lines.push(`query ${index + 1} words ${query.words.join(' ')} seeds ${query.seeds.join(' ')}`,
      `matched ${result.matches.length} root ${result.root.length} base ${result.base.length} links ${result.edgeCount} dropped_intra_host ${result.dropped}`,
      'results', ...rankLines(data, result.matches.slice(0, data.settings.top), state.scores.pagerank),
      `personalized reach ${result.reach} seed_mass ${real(result.seedMass)}`, ...rankLines(data, result.personalTop, result.personalRank.values),
      `overlap_with_global ${result.overlap}`);
    const analysis = result.linkAnalysis;
    if (analysis === null) { lines.push('hits none'); return; }
    const lists: [string, Ranking][] = [['hits authorities', analysis.hitAuthority], ['hits hubs', analysis.hitHub],
      ['salsa authorities', analysis.salsaAuthority], ['salsa hubs', analysis.salsaHub]];
    for (const [heading, ranking] of lists) lines.push(heading, ...rankLines(data, topList(ranking, data.settings.top), ranking.values));
    lines.push(`hits_salsa_overlap authorities ${analysis.authorityOverlap} hubs ${analysis.hubOverlap} authority_hosts ${analysis.authorityHosts}`,
      `related_to ${data.pages[analysis.relatedTo].id} citing ${analysis.citing.length}`);
    analysis.related.forEach((record, rank) => {
      const page = data.pages[record.node];
      lines.push(`${rank + 1} ${page.id} ${record.count} ${page.host} ${page.title}`);
    });
    lines.push(`coupled_to ${data.pages[analysis.coupledTo].id} cited ${analysis.cited.length}`);
    analysis.similar.forEach((record, rank) => {
      const page = data.pages[record.node];
      lines.push(`${rank + 1} ${page.id} ${record.count} ${page.host} ${page.title}`);
    });
  });
  return lines;
}
function hostsReport(data: GraphData, hosts: HostResult) {
  const lines = ['host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank'];
  hosts.records.forEach((host, index) => {
    const count = host.members.length, density = count < 2 ? 0 : host.internal / (count * (count - 1));
    lines.push([host.name, count, host.core, host.internal, real(density, 4), host.outgoing, host.incoming,
      host.dangling, real(host.pageScore), data.pages[host.representative].id, real(hosts.ranking.values[index]), hosts.ranking.position[index]].join(','));
  });
  return lines;
}
function main() {
  const data = buildGraph(readInput()), undirected = undirectedStatistics(data);
  const statistics: Statistics = { undirected, components: componentStatistics(data, undirected), distances: distanceStatistics(data) };
  const state = calculateScores(data, statistics), queries = queryAnalyses(data, state), hosts = hostAnalysis(data, statistics, state);
  writeReports({
    'graph_stats.txt': graphReport(data, statistics, state), 'pagerank.csv': pageReport(data, statistics, state),
    'rankings.txt': rankingReport(data, statistics, state, hosts), 'convergence.txt': convergenceReport(data, state),
    'queries.txt': queriesReport(data, state, queries), 'hosts.csv': hostsReport(data, hosts),
  });
}
main();
