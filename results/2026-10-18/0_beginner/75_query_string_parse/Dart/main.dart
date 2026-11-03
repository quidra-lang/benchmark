void main() {
  const queries = [
    'name=Alice+Smith&age=30&city=New%20York',
    'q=c%2B%2B+tutorial&page=2&sort=desc&page=3',
    'msg=50%25+off%21&debug&lang=en&ref=&lang=ja',
    'redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips',
  ];
  for (var k = 0; k < queries.length; k++) {
    final entries = <String, List<String>>{};
    for (final item in queries[k].split('&')) {
      final split = item.indexOf('=');
      final key = Uri.decodeQueryComponent(
        split < 0 ? item : item.substring(0, split),
      );
      final value = Uri.decodeQueryComponent(
        split < 0 ? '' : item.substring(split + 1),
      );
      entries.putIfAbsent(key, () => []).add(value);
    }
    final keys = entries.keys.toList()..sort();
    print('query ${k + 1}:');
    for (final key in keys) {
      print('  $key: ${entries[key]!.map((v) => '"$v"').join(', ')}');
    }
  }
}
