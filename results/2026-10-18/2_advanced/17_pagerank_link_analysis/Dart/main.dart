import 'dart:io';
import 'dart:math' as math;
import 'graph_io.dart';
import 'components.dart';
import 'pagerank.dart';
import 'hits.dart';
import 'report.dart';

const regionNames = ['CORE', 'IN', 'OUT', 'TUBE', 'IN_TENDRIL', 'OUT_TENDRIL', 'OTHER'];
const quantityNames = ['in_degree', 'pagerank', 'cheirank', 'authority', 'hub', 'trustrank', 'harmonic'];
const coreRegion = 0, inRegion = 1, outRegion = 2, tubeRegion = 3, inTendril = 4, outTendril = 5, otherRegion = 6;
double total(Iterable<double> values) => values.fold(0.0, (sum, value) => sum + value);
List<int> sequence(int count) => List.generate(count, (index) => index);
String integerText(Iterable<int> values) => values.join(' ');
List<String> joinBlocks(List<List<String>> blocks) => [for (var index = 0; index < blocks.length; index++) ...[if (index > 0) '', ...blocks[index]]];
List<int> rankOrder(List<double> values) => sequence(values.length)..sort((first, second) {
  final compared = scaled(values[second]).compareTo(scaled(values[first]));
  return compared != 0 ? compared : first.compareTo(second);
});
List<int> positions(List<int> order) {
  final rank = List.filled(order.length, 0);
  for (var index = 0; index < order.length; index++) {
    rank[order[index]] = index + 1;
  }
  return rank;
}
List<int> topList(List<double> values, int limit) => rankOrder(values).where((node) => scaled(values[node]) > 0).take(limit).toList();
List<int> rankedCounts(List<int> counts, int limit) {
  final nodes = sequence(counts.length).where((node) => counts[node] > 0).toList()..sort((first, second) {
    final compared = counts[second].compareTo(counts[first]);
    return compared != 0 ? compared : first.compareTo(second);
  });
  return nodes.take(limit).toList();
}
List<String> distributionLines(List<int> values) {
  final counts = <int, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return [for (final value in keys) '$value ${counts[value]}'];
}
PageRankResult runPageRank(List<List<WeightedEdge>> edges, List<int> teleport, double damping, Settings settings) =>
    powerIteration(edges, teleport, damping, settings.iterations, settings.tolerance);

(Set<Link>, List<(LinkRecord, String)>) classifyLinks(List<LinkRecord> records, Map<int, int> indexOf) {
  final accepted = <Link>{}, ignored = <(LinkRecord, String)>[];
  for (final record in records) {
    final source = indexOf[record.source], target = indexOf[record.target];
    String? reason;
    if (source == null || target == null) reason = 'unknown';
    else if (source == target) reason = 'self';
    else if (!accepted.add((source, target))) reason = 'duplicate';
    if (reason != null) ignored.add((record, reason));
  }
  return (accepted, ignored);
}

class Graph {
  final List<Page> pages;
  final List<Link> links;
  final Set<Link> linkSet;
  final List<List<int>> successors, predecessors;
  Graph(this.pages, Iterable<Link> input)
      : links = input.toList()..sort((first, second) {
          final compared = first.$1.compareTo(second.$1);
          return compared != 0 ? compared : first.$2.compareTo(second.$2);
        }), linkSet = input.toSet(), successors = List.generate(pages.length, (_) => []),
        predecessors = List.generate(pages.length, (_) => []) {
    for (final (source, target) in links) {
      successors[source].add(target);
      predecessors[target].add(source);
    }
  }
  bool intraHost(Link link) => pages[link.$1].host == pages[link.$2].host;
  List<Link> interHostLinks(List<Link> links) => links.where((link) => !intraHost(link)).toList();
  List<int> dangling() => sequence(pages.length).where((node) => successors[node].isEmpty).toList();
  List<int> ids(Iterable<int> nodes) => nodes.map((node) => pages[node].id).toList();
  List<List<WeightedEdge>> forwardEdges() => [for (final sources in predecessors) [for (final source in sources) (source, 1)]];
  List<List<WeightedEdge>> reverseEdges() => [for (final targets in successors) [for (final target in targets) (target, 1)]];
  String describe(int position, int node, List<String> values) => ['$position', '${pages[node].id}', ...values, pages[node].host, pages[node].title].join(' ');
}

List<int> kcoreNumbers(List<List<int>> neighbors) {
  final remaining = neighbors.map((group) => group.length).toList(), removed = List.filled(neighbors.length, false);
  final core = List.filled(neighbors.length, 0);
  var level = 0, left = neighbors.length;
  while (left > 0) {
    var candidate = -1;
    for (var node = 0; node < neighbors.length; node++) {
      if (!removed[node] && remaining[node] <= level) {
        candidate = node;
        break;
      }
    }
    if (candidate < 0) {
      level++;
      continue;
    }
    removed[candidate] = true;
    core[candidate] = level;
    left--;
    for (final next in neighbors[candidate]) {
      if (!removed[next]) remaining[next]--;
    }
  }
  return core;
}

class Undirected {
  final List<List<int>> neighbors;
  final List<int> kcore;
  final int edgeCount, closed, possible, eligible, degeneracy, weakCount, weakLargest;
  final double averageClustering;
  Undirected._(this.neighbors, this.kcore, this.edgeCount, this.closed, this.possible,
      this.eligible, this.degeneracy, this.weakCount, this.weakLargest, this.averageClustering);
  factory Undirected(Graph graph) {
    final n = graph.pages.length, adjacent = List.generate(graph.pages.length, (_) => <int>{});
    for (final (source, target) in graph.links) {
      adjacent[source].add(target);
      adjacent[target].add(source);
    }
    final neighbors = [for (final group in adjacent) group.toList()..sort()];
    var edges = 0, closed = 0, possible = 0, eligible = 0, localSum = 0.0;
    for (final group in neighbors) {
      final degree = group.length;
      edges += degree;
      if (degree < 2) continue;
      var count = 0;
      for (var first = 0; first < degree; first++) {
        for (var second = first + 1; second < degree; second++) {
          if (adjacent[group[first]].contains(group[second])) count++;
        }
      }
      final pairs = degree * (degree - 1) ~/ 2;
      closed += count;
      possible += pairs;
      eligible++;
      localSum += count / pairs;
    }
    final core = kcoreNumbers(neighbors), labels = weakComponents(neighbors);
    final sizes = List.filled(n, 0);
    for (final label in labels) {
      sizes[label]++;
    }
    return Undirected._(neighbors, core, edges ~/ 2, closed, possible, eligible,
        core.reduce(math.max), labels.reduce(math.max) + 1, sizes.reduce(math.max), localSum / eligible);
  }
}

int longestPath(int count, List<Link> edges) {
  final successors = List.generate(count, (_) => <int>[]), pending = List.filled(count, 0), length = List.filled(count, 0);
  for (final (source, target) in edges) {
    successors[source].add(target);
    pending[target]++;
  }
  final ready = sequence(count).where((node) => pending[node] == 0).toList();
  while (ready.isNotEmpty) {
    final node = ready.removeLast();
    for (final target in successors[node]) {
      length[target] = math.max(length[target], length[node] + 1);
      if (--pending[target] == 0) ready.add(target);
    }
  }
  return length.reduce(math.max);
}

class ComponentTable {
  final List<List<int>> groups;
  final List<int> label, incoming, outgoing;
  final int edgeCount, depth, core, singletons;
  ComponentTable._(this.groups, this.label, this.incoming, this.outgoing, this.edgeCount, this.depth, this.core, this.singletons);
  factory ComponentTable(Graph graph) {
    final groups = strongComponents(graph.successors);
    for (final group in groups) {
      group.sort();
    }
    groups.sort((first, second) => first.first.compareTo(second.first));
    final labels = List.filled(graph.pages.length, 0), incoming = List.filled(groups.length, 0), outgoing = List.filled(groups.length, 0);
    var core = 0, singletons = 0;
    for (var number = 0; number < groups.length; number++) {
      for (final node in groups[number]) {
        labels[node] = number;
      }
      if (groups[number].length > groups[core].length) core = number;
      if (groups[number].length == 1) singletons++;
    }
    final edges = <Link>{};
    for (final (source, target) in graph.links) {
      final first = labels[source], second = labels[target];
      if (first != second) {
        outgoing[first]++;
        incoming[second]++;
        edges.add((first, second));
      }
    }
    return ComponentTable._(groups, labels, incoming, outgoing, edges.length,
        longestPath(groups.length, edges.toList()), core, singletons);
  }
}

List<int> bowtieRegions(Graph graph, List<int> corePages) {
  final forward = reachable(graph.successors, corePages), backward = reachable(graph.predecessors, corePages), inCore = corePages.toSet();
  final regions = List.filled(graph.pages.length, otherRegion), inPages = <int>[], outPages = <int>[];
  for (var node = 0; node < regions.length; node++) {
    if (inCore.contains(node)) regions[node] = coreRegion;
    else if (backward[node]) {
      regions[node] = inRegion;
      inPages.add(node);
    }
    else if (forward[node]) {
      regions[node] = outRegion;
      outPages.add(node);
    }
  }
  final fromIn = reachable(graph.successors, inPages), toOut = reachable(graph.predecessors, outPages);
  for (var node = 0; node < regions.length; node++) {
    if (inCore.contains(node) || backward[node] || forward[node]) continue;
    if (fromIn[node] && toOut[node]) regions[node] = tubeRegion;
    else if (fromIn[node]) regions[node] = inTendril;
    else if (toOut[node]) regions[node] = outTendril;
  }
  return regions;
}

class DistanceStats {
  var pairs = 0, totalDistance = 0, diameter = 0, source = 0, target = 0;
  final List<int> histogram;
  final List<double> harmonic;
  DistanceStats(Graph graph) : histogram = List.filled(graph.pages.length, 0), harmonic = List.filled(graph.pages.length, 0.0) {
    for (var from = 0; from < graph.pages.length; from++) {
      final distance = bfsDistances(graph.successors, [from]);
      for (var to = 0; to < distance.length; to++) {
        final steps = distance[to];
        if (to == from || steps < 0) continue;
        pairs++;
        totalDistance += steps;
        histogram[steps]++;
        harmonic[to] += 1 / steps;
        if (steps > diameter) {
          diameter = steps;
          source = from;
          target = to;
        }
      }
    }
  }
  int effectiveDiameter() {
    var reached = 0;
    for (var steps = 1; steps <= diameter; steps++) {
      reached += histogram[steps];
      if (10 * reached >= 9 * pairs) return steps;
    }
    return diameter;
  }
}

class PageScores {
  final double damping;
  final PageRankResult pagerankRun, cheirankRun, trustrankRun;
  final List<double> pagerank, cheirank, trustrank, trustRatio, authority, hub, harmonic;
  final List<int> order, rank, cheirankRank, trustDistance;
  PageScores._(this.damping, this.pagerankRun, this.cheirankRun, this.trustrankRun, this.pagerank,
      this.cheirank, this.trustrank, this.trustRatio, this.authority, this.hub, this.harmonic,
      this.order, this.rank, this.cheirankRank, this.trustDistance);
  factory PageScores(Graph graph, Settings settings, List<int> trusted, List<double> harmonic) {
    final everyone = sequence(graph.pages.length), damping = settings.damping;
    final pagerank = runPageRank(graph.forwardEdges(), everyone, damping, settings);
    final cheirank = runPageRank(graph.reverseEdges(), everyone, damping, settings);
    final trustrank = runPageRank(graph.forwardEdges(), trusted, damping, settings);
    final order = rankOrder(pagerank.values);
    final (authority, hub) = hits(graph.pages.length, everyone, graph.interHostLinks(graph.links), settings.hitsIterations);
    return PageScores._(damping, pagerank, cheirank, trustrank, pagerank.values, cheirank.values, trustrank.values,
        [for (var node = 0; node < everyone.length; node++) trustrank.values[node] / pagerank.values[node]],
        authority, hub, harmonic, order, positions(order), positions(rankOrder(cheirank.values)), bfsDistances(graph.successors, trusted));
  }
  double contribution(Graph graph, int source) => damping * pagerank[source] / graph.successors[source].length;
  int representative(List<int> nodes) => nodes.reduce((first, second) => rank[first] < rank[second] ? first : second);
}

List<int> scaledValues(List<double> values) => [for (final value in values) scaled(value)];
String kendall(List<int> first, List<int> second) {
  var concordant = 0, discordant = 0;
  for (var one = 0; one < first.length; one++) {
    for (var two = one + 1; two < first.length; two++) {
      final dx = first[one] - first[two], dy = second[one] - second[two];
      if (dx == 0 || dy == 0) continue;
      if ((dx > 0) == (dy > 0)) concordant++;
      else discordant++;
    }
  }
  return fraction(concordant - discordant, first.length * (first.length - 1) ~/ 2);
}

class SweepResult {
  final double damping;
  final PageRankResult run;
  final int overlap, footrule, shift, shiftRank;
  final String correlation;
  final List<int> top;
  SweepResult._(this.damping, this.run, this.overlap, this.footrule, this.shift, this.shiftRank, this.correlation, this.top);
  factory SweepResult(double damping, Graph graph, PageScores scores, Settings settings) {
    final run = runPageRank(graph.forwardEdges(), sequence(graph.pages.length), damping, settings);
    final order = rankOrder(run.values);
    final rank = positions(order);
    var overlap = 0, footrule = 0, shift = 0;
    for (var node = 0; node < rank.length; node++) {
      if (rank[node] <= settings.topK && scores.rank[node] <= settings.topK) overlap++;
      footrule += (rank[node] - scores.rank[node]).abs();
      if ((rank[node] - scores.rank[node]).abs() > (rank[shift] - scores.rank[shift]).abs()) shift = node;
    }
    return SweepResult._(damping, run, overlap, footrule, shift, rank[shift],
        kendall(scaledValues(scores.pagerank), scaledValues(run.values)), order.take(settings.topK).toList());
  }
}

class SpamReport {
  final List<int> suspects;
  final List<String> hosts;
  final int removed;
  final PageRankResult? run;
  final List<int>? rank;
  SpamReport._(this.suspects, this.hosts, this.removed, this.run, this.rank);
  factory SpamReport(Graph graph, PageScores scores, Settings settings) {
    final suspects = scores.order.take(settings.spamTop).where((node) => scaled(scores.trustRatio[node], 4) / 10000 < settings.spamThreshold).toList();
    final hosts = suspects.map((node) => graph.pages[node].host).toSet().toList()..sort();
    if (suspects.isEmpty) return SpamReport._(suspects, hosts, 0, null, null);
    final kept = graph.links.where((link) => !(graph.intraHost(link) && hosts.contains(graph.pages[link.$1].host))).toList();
    final demoted = Graph(graph.pages, kept);
    final run = runPageRank(demoted.forwardEdges(), sequence(graph.pages.length), settings.damping, settings);
    return SpamReport._(suspects, hosts, graph.links.length - kept.length, run, positions(rankOrder(run.values)));
  }
}

bool titleMatches(List<String> words, List<String> include, List<String> exclude) =>
    include.every(words.contains) && !exclude.any(words.contains);
List<bool> baseMembership(Graph graph, List<int> root, int limit) {
  final inBase = List.filled(graph.pages.length, false);
  for (final node in root) {
    inBase[node] = true;
    for (final next in graph.successors[node].take(limit)) {
      inBase[next] = true;
    }
    for (final next in graph.predecessors[node].take(limit)) {
      inBase[next] = true;
    }
  }
  return inBase;
}
List<double> salsaScores(int count, List<Link> links) {
  final degree = List.filled(count, 0), targets = List.generate(count, (_) => <int>[]), neighbors = List.generate(count, (_) => <int>[]);
  for (final (source, target) in links) {
    degree[target]++;
    targets[source].add(target);
  }
  for (final group in targets) {
    for (var index = 0; index + 1 < group.length; index++) {
      final first = group[index], second = group[index + 1];
      neighbors[first].add(second);
      neighbors[second].add(first);
    }
  }
  final labels = weakComponents(neighbors), size = List.filled(count, 0), mass = List.filled(count, 0);
  final side = sequence(count).where((node) => degree[node] > 0).toList();
  for (final node in side) {
    size[labels[node]]++;
    mass[labels[node]] += degree[node];
  }
  return [for (var node = 0; node < count; node++) degree[node] == 0 ? 0.0 :
    (size[labels[node]] * degree[node]) / (side.length * mass[labels[node]])];
}
List<int> cocitationCounts(Graph graph, int page) {
  final counts = List.filled(graph.pages.length, 0);
  for (final citing in graph.predecessors[page]) {
    for (final cited in graph.successors[citing]) {
      if (cited != page) counts[cited]++;
    }
  }
  return counts;
}
List<int> couplingCounts(Graph graph, int page) {
  final counts = List.filled(graph.pages.length, 0);
  for (final cited in graph.successors[page]) {
    for (final citing in graph.predecessors[cited]) {
      if (citing != page) counts[citing]++;
    }
  }
  return counts;
}
int overlap(List<int> first, List<int> second) => first.toSet().intersection(second.toSet()).length;

class SubgraphScores {
  final List<double> authority, hub, salsaAuthority, salsaHub;
  final List<int> authorityTop, hubTop, salsaAuthorityTop, salsaHubTop, cocitation, coupling, related, similar;
  final int authorityOverlap, hubOverlap, authorityHosts, cited, citing;
  SubgraphScores._(this.authority, this.hub, this.salsaAuthority, this.salsaHub, this.authorityTop,
      this.hubTop, this.salsaAuthorityTop, this.salsaHubTop, this.cocitation, this.coupling,
      this.related, this.similar, this.authorityOverlap, this.hubOverlap, this.authorityHosts, this.cited, this.citing);
  factory SubgraphScores(Graph graph, List<int> base, List<Link> links, Settings settings) {
    final (authority, hub) = hits(graph.pages.length, base, links, settings.hitsIterations);
    final salsaAuthority = salsaScores(graph.pages.length, links);
    final salsaHub = salsaScores(graph.pages.length, [for (final (source, target) in links) (target, source)]);
    final authorityTop = topList(authority, settings.topK), hubTop = topList(hub, settings.topK);
    final salsaAuthorityTop = topList(salsaAuthority, settings.topK), salsaHubTop = topList(salsaHub, settings.topK);
    final cited = authorityTop.first, citing = hubTop.first;
    final cocitation = cocitationCounts(graph, cited), coupling = couplingCounts(graph, citing);
    return SubgraphScores._(authority, hub, salsaAuthority, salsaHub, authorityTop, hubTop, salsaAuthorityTop, salsaHubTop,
        cocitation, coupling, rankedCounts(cocitation, settings.topK), rankedCounts(coupling, settings.topK),
        overlap(authorityTop, salsaAuthorityTop), overlap(hubTop, salsaHubTop),
        authorityTop.map((node) => graph.pages[node].host).toSet().length, cited, citing);
  }
}

class QueryResult {
  final Query query;
  final List<int> matches, personalizedTop;
  final int rootSize, baseSize, dropped, reach, globalOverlap;
  final List<Link> subgraph;
  final PageRankResult personalized;
  final double seedMass;
  final SubgraphScores? scores;
  QueryResult._(this.query, this.matches, this.personalizedTop, this.rootSize, this.baseSize,
      this.dropped, this.reach, this.globalOverlap, this.subgraph, this.personalized, this.seedMass, this.scores);
  factory QueryResult(Query query, Graph graph, PageScores scores, Settings settings, Map<int, int> indexOf) {
    final include = query.words.where((word) => !word.startsWith('-')).toList();
    final exclude = query.words.where((word) => word.startsWith('-')).map((word) => word.substring(1)).toList();
    final matches = scores.order.where((node) => titleMatches(graph.pages[node].words, include, exclude)).toList();
    final root = matches.take(settings.rootLimit).toList();
    final inBase = baseMembership(graph, root, settings.neighborLimit);
    final base = sequence(graph.pages.length).where((node) => inBase[node]).toList();
    final inside = graph.links.where((link) => inBase[link.$1] && inBase[link.$2]).toList();
    final subgraph = graph.interHostLinks(inside);
    final seeds = query.seeds.map((id) => indexOf[id]!).toList()..sort();
    final personalized = runPageRank(graph.forwardEdges(), seeds, settings.damping, settings);
    final personalizedTop = topList(personalized.values, settings.topK);
    return QueryResult._(query, matches, personalizedTop, root.length, base.length, inside.length - subgraph.length,
        reachable(graph.successors, seeds).where((value) => value).length,
        personalizedTop.where((node) => scores.rank[node] <= settings.topK).length, subgraph,
        personalized, total(seeds.map((node) => personalized.values[node])),
        subgraph.isEmpty ? null : SubgraphScores(graph, base, subgraph, settings));
  }
}

class HostGraph {
  final List<String> names;
  final List<int> ofPage, internal, outgoing, incoming, rank;
  final List<List<int>> members, weight;
  final List<Link> edges, heavy;
  final int reciprocal, componentCount, largest;
  final PageRankResult run;
  HostGraph._(this.names, this.ofPage, this.internal, this.outgoing, this.incoming, this.rank,
      this.members, this.weight, this.edges, this.heavy, this.reciprocal, this.componentCount, this.largest, this.run);
  factory HostGraph(Graph graph, Settings settings) {
    final names = graph.pages.map((page) => page.host).toSet().toList()..sort();
    final count = names.length, index = {for (var number = 0; number < names.length; number++) names[number]: number};
    final ofPage = graph.pages.map((page) => index[page.host]!).toList(), members = List.generate(count, (_) => <int>[]);
    final weight = List.generate(count, (_) => List.filled(count, 0));
    final internal = List.filled(count, 0), outgoing = List.filled(count, 0), incoming = List.filled(count, 0);
    for (var node = 0; node < ofPage.length; node++) {
      members[ofPage[node]].add(node);
    }
    for (final (source, target) in graph.links) {
      final first = ofPage[source], second = ofPage[target];
      if (first == second) internal[first]++;
      else { weight[first][second]++; outgoing[first]++; incoming[second]++; }
    }
    final edges = <Link>[], adjacency = List.generate(count, (_) => <int>[]), inEdges = List.generate(count, (_) => <WeightedEdge>[]);
    var reciprocal = 0;
    for (var first = 0; first < count; first++) {
      for (var second = 0; second < count; second++) {
        if (weight[first][second] == 0) continue;
        edges.add((first, second));
        adjacency[first].add(second);
        inEdges[second].add((first, weight[first][second]));
        if (weight[second][first] > 0) reciprocal++;
      }
    }
    final components = strongComponents(adjacency);
    final run = runPageRank(inEdges, sequence(count), settings.damping, settings);
    final heavy = edges.toList()..sort((first, second) {
      final compared = weight[second.$1][second.$2].compareTo(weight[first.$1][first.$2]);
      if (compared != 0) return compared;
      final source = first.$1.compareTo(second.$1);
      return source != 0 ? source : first.$2.compareTo(second.$2);
    });
    return HostGraph._(names, ofPage, internal, outgoing, incoming, positions(rankOrder(run.values)), members, weight,
        edges, heavy.take(settings.topK).toList(), reciprocal, components.length, components.map((group) => group.length).reduce(math.max), run);
  }
}

class Analysis {
  final Input input;
  final Graph graph;
  final List<(LinkRecord, String)> ignored;
  final Undirected undirected;
  final ComponentTable components;
  final List<int> regions;
  final DistanceStats distances;
  final PageScores scores;
  final List<SweepResult> sweeps;
  final SpamReport spam;
  final List<QueryResult> queries;
  final HostGraph hosts;
  Analysis._(this.input, this.graph, this.ignored, this.undirected, this.components, this.regions,
      this.distances, this.scores, this.sweeps, this.spam, this.queries, this.hosts);
  factory Analysis(Input input) {
    input.pages.sort((first, second) => first.id.compareTo(second.id));
    final indexOf = {for (var node = 0; node < input.pages.length; node++) input.pages[node].id: node};
    final (links, ignored) = classifyLinks(input.records, indexOf);
    final graph = Graph(input.pages, links), settings = input.settings;
    final undirected = Undirected(graph), components = ComponentTable(graph);
    final regions = bowtieRegions(graph, components.groups[components.core]), distances = DistanceStats(graph);
    final trusted = settings.trusted.map((id) => indexOf[id]!).toList()..sort();
    final scores = PageScores(graph, settings, trusted, distances.harmonic);
    final sweeps = [for (final damping in settings.sweep) SweepResult(damping, graph, scores, settings)];
    final spam = SpamReport(graph, scores, settings);
    final queries = [for (final query in input.queries) QueryResult(query, graph, scores, settings, indexOf)];
    return Analysis._(input, graph, ignored, undirected, components, regions, distances,
        scores, sweeps, spam, queries, HostGraph(graph, settings));
  }

  List<String> linkLines() {
    final reasons = <String, int>{};
    for (final (_, reason) in ignored) {
      reasons[reason] = (reasons[reason] ?? 0) + 1;
    }
    final intra = graph.links.where(graph.intraHost).length;
    final reciprocal = graph.links.where((link) => graph.linkSet.contains((link.$2, link.$1))).length;
    final inDegrees = graph.predecessors.map((group) => group.length).toList();
    final outDegrees = graph.successors.map((group) => group.length).toList();
    final noIn = sequence(graph.pages.length).where((node) => inDegrees[node] == 0).toList();
    final maxIn = inDegrees.reduce(math.max), maxOut = outDegrees.reduce(math.max), dangling = graph.dangling();
    String nodesLine(String heading, List<int> nodes) => [heading, if (nodes.isNotEmpty) integerText(graph.ids(nodes))].join(' ');
    return ['pages ${graph.pages.length}', 'hosts ${graph.pages.map((page) => page.host).toSet().length}',
      'link_rows ${input.records.length}', 'links ${graph.links.length}',
      'ignored_unknown ${reasons['unknown'] ?? 0}', 'ignored_self ${reasons['self'] ?? 0}',
      'ignored_duplicate ${reasons['duplicate'] ?? 0}',
      for (final (record, reason) in ignored) 'ignored line ${record.line} ${record.source},${record.target} $reason',
      'intra_host_links $intra', 'inter_host_links ${graph.links.length - intra}',
      'mean_degree ${fixed(graph.links.length / graph.pages.length, 4)}',
      'reciprocity ${fraction(reciprocal, graph.links.length)}', nodesLine('dangling ${dangling.length}', dangling),
      nodesLine('no_in_links ${noIn.length}', noIn),
      nodesLine('max_in_degree $maxIn pages', sequence(inDegrees.length).where((node) => inDegrees[node] == maxIn).toList()),
      nodesLine('max_out_degree $maxOut pages', sequence(outDegrees.length).where((node) => outDegrees[node] == maxOut).toList()),
      '', 'in_degree_distribution', ...distributionLines(inDegrees), '', 'out_degree_distribution', ...distributionLines(outDegrees)];
  }

  List<String> undirectedLines() => ['', 'undirected_links ${undirected.edgeCount}',
    'transitivity ${fraction(undirected.closed, undirected.possible)}',
    'average_clustering ${fixed(undirected.averageClustering, 4)} pages ${undirected.eligible}',
    'degeneracy ${undirected.degeneracy} pages ${undirected.kcore.where((number) => number == undirected.degeneracy).length}',
    'core_distribution', ...distributionLines(undirected.kcore)];

  List<String> componentLines() {
    final lines = ['', 'strong_components ${components.groups.length} largest ${components.groups[components.core].length} singletons ${components.singletons} condensation_links ${components.edgeCount}',
      'weak_components ${undirected.weakCount} largest ${undirected.weakLargest}', 'condensation_depth ${components.depth}'];
    for (var number = 0; number < components.groups.length; number++) {
      final group = components.groups[number];
      if (group.length < 2) continue;
      lines.add('scc ${number + 1} size ${group.length} min ${graph.pages[group.first].id} incoming ${components.incoming[number]} outgoing ${components.outgoing[number]} pagerank ${fixed(total(group.map((node) => scores.pagerank[node])))}${components.outgoing[number] == 0 ? ' sink' : ''}');
    }
    return lines;
  }

  List<String> bowtieLines() {
    final lines = ['', 'bowtie core_scc ${components.core + 1}'];
    for (var region = 0; region < regionNames.length; region++) {
      final members = sequence(regions.length).where((node) => regions[node] == region).toList();
      final parts = [regionNames[region], '${members.length}', 'pagerank', fixed(total(members.map((node) => scores.pagerank[node])))];
      if (members.isNotEmpty) parts.addAll(['top', '${graph.pages[scores.representative(members)].id}']);
      if (members.isNotEmpty && members.length <= 10) parts.addAll(['pages', integerText(graph.ids(members))]);
      lines.add(parts.join(' '));
    }
    final counts = List.generate(regionNames.length, (_) => List.filled(regionNames.length, 0));
    for (final (source, target) in graph.links) {
      counts[regions[source]][regions[target]]++;
    }
    lines.add('region_links');
    for (var first = 0; first < regionNames.length; first++) {
      for (var second = 0; second < regionNames.length; second++) {
        if (counts[first][second] > 0) lines.add('${regionNames[first]} ${regionNames[second]} ${counts[first][second]}');
      }
    }
    return lines;
  }

  List<String> distanceLines() => ['', 'distances', 'reachable_pairs ${distances.pairs}',
    'average ${fraction(distances.totalDistance, distances.pairs)}',
    'diameter ${distances.diameter} from ${graph.pages[distances.source].id} to ${graph.pages[distances.target].id}',
    'effective_diameter ${distances.effectiveDiameter()}', for (var steps = 1; steps <= distances.diameter; steps++) '$steps ${distances.histogram[steps]}'];
  List<String> graphStatsLines() => [...linkLines(), ...undirectedLines(), ...componentLines(), ...bowtieLines(), ...distanceLines()];

  List<String> pagerankCSVLines() => ['id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance',
    for (var node = 0; node < graph.pages.length; node++) [graph.pages[node].id, graph.predecessors[node].length,
      graph.successors[node].length, components.label[node] + 1, regionNames[regions[node]], undirected.kcore[node],
      fixed(scores.harmonic[node]), fixed(scores.pagerank[node]), scores.rank[node], fixed(scores.cheirank[node]),
      scores.cheirankRank[node], fixed(scores.authority[node]), fixed(scores.hub[node]), fixed(scores.trustrank[node]),
      fixed(scores.trustRatio[node], 4), scores.trustDistance[node]].join(',')];

  List<String> rankLines(List<int> nodes, List<double> values) => [for (var position = 0; position < nodes.length; position++)
    graph.describe(position + 1, nodes[position], [fixed(values[nodes[position]])])];
  List<String> scoreBlock(String name, List<double> values) => ['$name top ${input.settings.topK}', ...rankLines(topList(values, input.settings.topK), values)];
  List<String> pagerankBlock() {
    final lines = scoreBlock('pagerank', scores.pagerank);
    lines.add('dangling_mass ${fixed(total(graph.dangling().map((node) => scores.pagerank[node])))}');
    for (final node in topList(scores.pagerank, input.settings.topK)) {
      final contributors = graph.predecessors[node].toList()..sort((first, second) {
        final compared = scaled(scores.contribution(graph, second)).compareTo(scaled(scores.contribution(graph, first)));
        return compared != 0 ? compared : first.compareTo(second);
      });
      lines.add(['contributors', '${graph.pages[node].id}', for (final source in contributors.take(3))
        '${graph.pages[source].id} ${fixed(scores.contribution(graph, source))}'].join(' '));
    }
    return lines;
  }

  List<String> correlationBlock() {
    final series = [graph.predecessors.map((sources) => sources.length).toList(),
      scaledValues(scores.pagerank), scaledValues(scores.cheirank), scaledValues(scores.authority),
      scaledValues(scores.hub), scaledValues(scores.trustrank), scaledValues(scores.harmonic)];
    return ['correlation', for (var first = 0; first < quantityNames.length; first++)
      for (var second = first + 1; second < quantityNames.length; second++)
        '${quantityNames[first]} ${quantityNames[second]} ${kendall(series[first], series[second])}'];
  }
  List<String> sweepBlock() => ['damping_sweep', for (final sweep in sweeps) ...[
    'damping ${fixed(sweep.damping, 4)} overlap ${sweep.overlap} footrule ${sweep.footrule} kendall ${sweep.correlation} largest_shift ${graph.pages[sweep.shift].id} ${scores.rank[sweep.shift]} ${sweep.shiftRank}',
    'top ${integerText(graph.ids(sweep.top))}']];

  List<String> spamBlock() {
    final settings = input.settings;
    final lines = ['spam top ${settings.spamTop} threshold ${fixed(settings.spamThreshold, 4)}',
      for (final node in spam.suspects) 'suspect ${graph.pages[node].id} rank ${scores.rank[node]} pagerank ${fixed(scores.pagerank[node])} trustrank ${fixed(scores.trustrank[node])} trust_ratio ${fixed(scores.trustRatio[node], 4)} trust_distance ${scores.trustDistance[node]} kcore ${undirected.kcore[node]} ${graph.pages[node].host}',
      'count ${spam.suspects.length}', 'trust_by_distance'];
    final distances = scores.trustDistance.where((distance) => distance >= 0).toSet().toList()..sort();
    if (scores.trustDistance.contains(-1)) distances.add(-1);
    for (final distance in distances) {
      final members = sequence(graph.pages.length).where((node) => scores.trustDistance[node] == distance).toList();
      lines.add('${distance < 0 ? 'unreachable' : distance} pages ${members.length} trustrank ${fixed(total(members.map((node) => scores.trustrank[node])))} pagerank ${fixed(total(members.map((node) => scores.pagerank[node])))}');
    }
    return lines;
  }
  List<String> demotionBlock() {
    final run = spam.run;
    if (run == null) return ['demotion none'];
    final top = topList(run.values, input.settings.topK);
    return ['demotion hosts ${spam.hosts.join(' ')} removed_links ${spam.removed}',
      for (var position = 0; position < top.length; position++) graph.describe(position + 1, top[position], [fixed(run.values[top[position]]), 'was', '${scores.rank[top[position]]}']),
      for (final node in spam.suspects) 'suspect ${graph.pages[node].id} before ${scores.rank[node]} after ${spam.rank![node]}'];
  }
  List<String> hostGraphBlock() => ['host_graph hosts ${hosts.names.length} links ${hosts.edges.length} reciprocal ${hosts.reciprocal} strong_components ${hosts.componentCount} largest ${hosts.largest}',
    'host_links top ${input.settings.topK}', for (final (source, target) in hosts.heavy)
      '${hosts.names[source]} ${hosts.names[target]} ${hosts.weight[source][target]}'];
  List<String> rankingsLines() => joinBlocks([pagerankBlock(), scoreBlock('cheirank', scores.cheirank),
    scoreBlock('authority', scores.authority), scoreBlock('hub', scores.hub), scoreBlock('trustrank', scores.trustrank),
    scoreBlock('harmonic', scores.harmonic), correlationBlock(), sweepBlock(), spamBlock(), demotionBlock(), hostGraphBlock()]);

  List<String> convergenceBlock(String heading, PageRankResult run) => ['', heading,
    for (var step = 10; step <= run.changes.length; step += 10) 'iteration $step l1 ${fixed(run.changes[step - 1], 10)}',
    'converged_at ${run.convergedAt ?? 'none'}'];
  List<String> convergenceLines() {
    final settings = input.settings, damping = fixed(input.settings.damping, 4);
    return ['iterations ${settings.iterations} tolerance ${fixed(settings.tolerance, 10)}',
      ...convergenceBlock('pagerank damping $damping', scores.pagerankRun),
      ...convergenceBlock('cheirank damping $damping', scores.cheirankRun),
      ...convergenceBlock('trustrank damping $damping seeds ${settings.trusted.length}', scores.trustrankRun),
      for (final sweep in sweeps) ...convergenceBlock('sweep damping ${fixed(sweep.damping, 4)}', sweep.run),
      if (spam.run != null) ...convergenceBlock('demoted damping $damping', spam.run!),
      for (final result in queries) ...convergenceBlock('personalized query ${result.query.number} damping $damping', result.personalized),
      ...convergenceBlock('host_pagerank damping $damping hosts ${hosts.names.length}', hosts.run)];
  }

  List<String> queryBlock(QueryResult result) {
    final query = result.query, limit = input.settings.topK;
    final lines = ['query ${query.number} words ${query.words.join(' ')} seeds ${integerText(query.seeds)}',
      'matched ${result.matches.length} root ${result.rootSize} base ${result.baseSize} links ${result.subgraph.length} dropped_intra_host ${result.dropped}',
      'results', ...rankLines(result.matches.take(limit).toList(), scores.pagerank),
      'personalized reach ${result.reach} seed_mass ${fixed(result.seedMass)}',
      ...rankLines(result.personalizedTop, result.personalized.values), 'overlap_with_global ${result.globalOverlap}'];
    final sub = result.scores;
    if (sub == null) return [...lines, 'hits none'];
    lines.addAll(['hits authorities', ...rankLines(sub.authorityTop, sub.authority),
      'hits hubs', ...rankLines(sub.hubTop, sub.hub), 'salsa authorities', ...rankLines(sub.salsaAuthorityTop, sub.salsaAuthority),
      'salsa hubs', ...rankLines(sub.salsaHubTop, sub.salsaHub),
      'hits_salsa_overlap authorities ${sub.authorityOverlap} hubs ${sub.hubOverlap} authority_hosts ${sub.authorityHosts}',
      'related_to ${graph.pages[sub.cited].id} citing ${graph.predecessors[sub.cited].length}',
      for (var position = 0; position < sub.related.length; position++) graph.describe(position + 1, sub.related[position], ['${sub.cocitation[sub.related[position]]}']),
      'coupled_to ${graph.pages[sub.citing].id} cited ${graph.successors[sub.citing].length}',
      for (var position = 0; position < sub.similar.length; position++) graph.describe(position + 1, sub.similar[position], ['${sub.coupling[sub.similar[position]]}'])]);
    return lines;
  }
  List<String> queriesLines() => joinBlocks([for (final result in queries) queryBlock(result)]);
  List<String> hostsCSVLines() {
    final lines = ['host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank'];
    for (var number = 0; number < hosts.names.length; number++) {
      final members = hosts.members[number], size = hosts.members[number].length;
      final density = size >= 2 ? hosts.internal[number] / (size * (size - 1)) : 0.0;
      lines.add([hosts.names[number], size, members.where((node) => regions[node] == coreRegion).length,
        hosts.internal[number], fixed(density, 4), hosts.outgoing[number], hosts.incoming[number],
        members.where((node) => graph.successors[node].isEmpty).length,
        fixed(total(members.map((node) => scores.pagerank[node]))), graph.pages[scores.representative(members)].id,
        fixed(hosts.run.values[number]), hosts.rank[number]].join(','));
    }
    return lines;
  }
}

void main() {
  final analysis = Analysis(readInput());
  Directory('output').createSync(recursive: true);
  final files = {'graph_stats.txt': analysis.graphStatsLines(), 'pagerank.csv': analysis.pagerankCSVLines(),
    'rankings.txt': analysis.rankingsLines(), 'convergence.txt': analysis.convergenceLines(),
    'queries.txt': analysis.queriesLines(), 'hosts.csv': analysis.hostsCSVLines()};
  for (final entry in files.entries) {
    writeLines(entry.key, entry.value);
  }
}
