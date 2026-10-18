import 'dart:io';
import 'dart:math' as math;

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
    const polygons = [[(0, 0), (5, 0), (6, 4), (1, 3)], [(2, 1), (0, 4), (3, 7), (7, 6), (8, 2)],
        [(0, 0), (8, 0), (8, 6), (5, 6), (4, 3), (3, 6), (0, 6)]];
    for (var k = 0; k < polygons.length; k++) {
        final points = polygons[k];
        var cross = 0, perimeter = 0.0;
        for (var i = 0; i < points.length; i++) {
            final a = points[i], b = points[(i + 1) % points.length];
            cross += a.$1 * b.$2 - b.$1 * a.$2;
            final dx = a.$1 - b.$1, dy = a.$2 - b.$2;
            perimeter += math.sqrt(dx * dx + dy * dy);
        }
        out.writeln('polygon ${k+1}: area=${fixed(cross.abs()/2,1)} perimeter=${fixed(perimeter,3)}');
    }
    stdout.write(out);
}
