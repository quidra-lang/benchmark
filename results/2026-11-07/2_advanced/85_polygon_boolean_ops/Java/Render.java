import java.util.*;
final class Render {
    record Picture(List<String> lines, int result, int a, int b, int both) {}
    static Picture grid(List<Rings.Polygon> polygons, List<List<Rational.Point>> first,
                        List<List<Rational.Point>> second, int x0, int y0, int width, int height,
                        int columns, int rows) {
        List<List<Rational.Point>> resultRings = Rings.flatten(polygons);
        List<String> lines = new ArrayList<>();
        int result = 0, a = 0, b = 0, both = 0;
        for (int row = 0; row < rows; row++) {
            StringBuilder cells = new StringBuilder();
            Rational.Fraction y = new Rational.Fraction(y0).add(
                new Rational.Fraction((2L * (rows - 1 - row) + 1) * height, 2));
            for (int column = 0; column < columns; column++) {
                Rational.Fraction x = new Rational.Fraction(x0).add(
                    new Rational.Fraction((2L * column + 1) * width, 2));
                Rational.Point point = new Rational.Point(x, y);
                char glyph;
                if (Rings.interior(resultRings, point)) {
                    glyph = '#';
                    result++;
                } else if (first != null) {
                    boolean inA = Rings.interior(first, point), inB = Rings.interior(second, point);
                    glyph = inA && inB ? '+' : inA ? 'a' : inB ? 'b' : '.';
                    if (glyph == '+')
                        both++;
                    else if (glyph == 'a')
                        a++;
                    else if (glyph == 'b')
                        b++;
                } else
                    glyph = '.';
                cells.append(glyph);
            }
            lines.add(cells.toString());
        }
        return new Picture(lines, result, a, b, both);
    }
}
