import 'dart:io';

String fixed(double value, int places) {
    var scale = 1;
    for (var i = 0; i < places; i++)
        scale *= 10;
    final scaled = (value.abs() * scale + 0.5).floor();
    final sign = value < 0 ? '-' : '';
    if (places == 0)
        return '$sign$scaled';
    return '$sign${scaled ~/ scale}.${(scaled % scale).toString().padLeft(places, '0')}';
}

void main() {
    final out = StringBuffer();
    final points = [(3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6),
        (-6, -2), (2, -2), (7, -1), (-3, 4), (2, 8), (-6, 3)]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    int cross((int, int) o, (int, int) a, (int, int) b) => (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
    List<(int, int)> chain(Iterable<(int, int)> source) {
        final result = <(int, int)>[];
        for (final p in source) {
            while (result.length >= 2 && cross(result[result.length - 2], result.last, p) <= 0)
                result.removeLast();
            result.add(p);
        }
        return result;
    }
    final lower = chain(points)..removeLast(), upper = chain(points.reversed)..removeLast(), hull = [...lower,
        ...upper];
    out.writeln('hull: ${hull.length} points');
    var twice = 0;
    for (var i = 0; i < hull.length; i++) {
        final p = hull[i], q = hull[(i + 1) % hull.length];
        out.writeln('(${p.$1}, ${p.$2})');
        twice += p.$1 * q.$2 - q.$1 * p.$2;
    }
    out.writeln('area: ${fixed(twice/2,1)}');
    stdout.write(out);
}
