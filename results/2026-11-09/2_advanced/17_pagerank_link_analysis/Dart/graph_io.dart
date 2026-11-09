import 'dart:io';

typedef Link = (int, int);
class Page {
  final int id;
  final String host, title;
  final List<String> words;
  Page(this.id, this.host, this.title) : words = title.split(' ');
}
class LinkRecord {
  final int line, source, target;
  LinkRecord(this.line, this.source, this.target);
}
class Query {
  final int number;
  final List<String> words;
  final List<int> seeds;
  Query(this.number, this.words, this.seeds);
}
class Settings {
  final double damping, tolerance, spamThreshold;
  final int iterations, spamTop, hitsIterations, topK, rootLimit, neighborLimit;
  final List<double> sweep;
  final List<int> trusted;
  Settings(Map<String, List<String>> entries)
      : damping = double.parse(entries['DAMPING']![0]), iterations = int.parse(entries['PAGERANK_ITERATIONS']![0]),
        tolerance = double.parse(entries['TOLERANCE']![0]), sweep = entries['DAMPING_SWEEP']!.map(double.parse).toList(),
        trusted = entries['TRUSTED']!.map(int.parse).toList(), spamTop = int.parse(entries['SPAM_TOP']![0]),
        spamThreshold = double.parse(entries['SPAM_THRESHOLD']![0]), hitsIterations = int.parse(entries['HITS_ITERATIONS']![0]),
        topK = int.parse(entries['TOP_K']![0]), rootLimit = int.parse(entries['ROOT_LIMIT']![0]),
        neighborLimit = int.parse(entries['NEIGHBOR_LIMIT']![0]);
}
class Input {
  final List<Page> pages;
  final List<LinkRecord> records;
  final List<Query> queries;
  final Settings settings;
  Input(this.pages, this.records, this.queries, this.settings);
}
List<String> readLines(String path) => File(path).readAsLinesSync();
Input readInput() {
  final pages = <Page>[], records = <LinkRecord>[], queries = <Query>[];
  for (final line in readLines('input/pages.csv').skip(1)) {
    final fields = line.split(',');
    pages.add(Page(int.parse(fields[0]), fields[1], fields[2]));
  }
  final links = readLines('input/links.csv');
  for (var index = 1; index < links.length; index++) {
    final fields = links[index].split(',');
    records.add(LinkRecord(index + 1, int.parse(fields[0]), int.parse(fields[1])));
  }
  final lines = readLines('input/queries.txt');
  for (var index = 0; index < lines.length; index++) {
    final parts = lines[index].split(' | ');
    queries.add(Query(index + 1, parts[0].split(' '), parts[1].split(' ').map(int.parse).toList()));
  }
  final entries = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    entries[fields[0]] = fields.sublist(1);
  }
  return Input(pages, records, queries, Settings(entries));
}
