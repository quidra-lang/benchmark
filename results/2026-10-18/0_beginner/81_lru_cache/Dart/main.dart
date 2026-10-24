import 'dart:io';

void main() {
    final out = StringBuffer();
    final cache = <String>[];
    var hits = 0, misses = 0;
    for (final key in 'BACBDABEADDCAEB'.split('')) {
        final index = cache.indexOf(key);
        out.write('$key: ');
        if (index >= 0) {
            hits++;
            cache.removeAt(index);
            out.write('hit');
        } else {
            misses++;
            out.write('miss');
            if (cache.length == 3)
                out.write(', evict ${cache.removeLast()}');
        }
        cache.insert(0, key);
        out.writeln(' [${cache.join(' ')}]');
    }
    out.writeln('hits: $hits misses: $misses');
    stdout.write(out);
}
