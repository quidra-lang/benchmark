import 'dart:io';

void main() {
    final out = StringBuffer();
    const queries = ['name=Alice+Smith&age=30&city=New%20York', 'q=c%2B%2B+tutorial&page=2&sort=desc&page=3',
        'msg=50%25+off%21&debug&lang=en&ref=&lang=ja', 'redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips'];
    String decode(String s) {
        final result = StringBuffer();
        for (var i = 0; i < s.length; i++) {
            if (s[i] == '+')
                result.write(' ');
            else if (s[i] == '%') {
                result.writeCharCode(int.parse(s.substring(i + 1, i + 3), radix: 16));
                i += 2;
            } else result.write(s[i]);
        }
        return result.toString();
    }
    for (var k = 0; k < queries.length; k++) {
        final entries = <String, List<String>>{};
        for (final item in queries[k].split('&')) {
            final split = item.indexOf('=');
            final key = decode(split < 0 ? item : item.substring(0, split)), value = decode(split < 0 ? '' : item.substring(split + 1));
            entries.putIfAbsent(key, () => []).add(value);
        }
        final keys = entries.keys.toList()..sort();
        out.writeln('query ${k+1}:');
        for (final key in keys)
            out.writeln('  $key: ${entries[key]!.map((v)=>'"$v"').join(', ')}');
    }
    stdout.write(out);
}
