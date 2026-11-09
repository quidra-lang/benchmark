import java.util.*;
final class Matrix {
    static final int DATA = 0, FUNCTION = 1, FORMAT = 2, VERSION = 3;
    record Point(int x, int y) {}
    record Positions(List<Point> first, List<Point> second) {}
    record Built(int[][] symbol, int[][] areas, List<Point> order) {}
    static Positions formatPositions(int size) {
        List<Point> first = new ArrayList<>(), second = new ArrayList<>();
        for (int i = 0; i < 15; i++) {
            first.add(i < 6    ? new Point(8, i)
                      : i == 6 ? new Point(8, 7)
                      : i == 7 ? new Point(8, 8)
                      : i == 8 ? new Point(7, 8)
                               : new Point(14 - i, 8));
            second.add(i < 8 ? new Point(size - 1 - i, 8) : new Point(8, size - 15 + i));
        }
        return new Positions(first, second);
    }
    static Positions versionPositions(int size) {
        List<Point> first = new ArrayList<>(), second = new ArrayList<>();
        for (int i = 0; i < 18; i++) {
            first.add(new Point(size - 11 + i % 3, i / 3));
            second.add(new Point(i / 3, size - 11 + i % 3));
        }
        return new Positions(first, second);
    }
    static int remainder(int value, int divisor) {
        int degree = 31 - Integer.numberOfLeadingZeros(divisor);
        while (value != 0 && 31 - Integer.numberOfLeadingZeros(value) >= degree)
            value ^= divisor << (31 - Integer.numberOfLeadingZeros(value) - degree);
        return value;
    }
    static int formatInformation(String level, int mask) {
        int indicator = switch (level) {
            case "L" -> 1;
            case "M" -> 0;
            case "Q" -> 3;
            default -> 2;
        };
        int shifted = (8 * indicator + mask) << 10;
        return (shifted + remainder(shifted, 0x537)) ^ 0x5412;
    }
    static int versionInformation(int version) {
        int shifted = version << 12;
        return shifted + remainder(shifted, 0x1F25);
    }
    static void writeValue(int[][] symbol, List<Point> positions, int value) {
        for (int i = 0; i < positions.size(); i++) {
            Point point = positions.get(i);
            symbol[point.y()][point.x()] = (value >>> i) & 1;
        }
    }
    static int readValue(int[][] symbol, List<Point> positions) {
        int value = 0;
        for (int i = 0; i < positions.size(); i++) {
            Point point = positions.get(i);
            value |= symbol[point.y()][point.x()] << i;
        }
        return value;
    }
    static int[][] copy(int[][] symbol) {
        int[][] result = new int[symbol.length][];
        for (int y = 0; y < symbol.length; y++)
            result[y] = symbol[y].clone();
        return result;
    }
    static Built build(int version, int[] alignments) {
        int size = 17 + 4 * version;
        int[][] symbol = new int[size][size], areas = new int[size][size];
        for (Point center :
             List.of(new Point(3, 3), new Point(size - 4, 3), new Point(3, size - 4)))
            for (int dy = -4; dy <= 4; dy++)
                for (int dx = -4; dx <= 4; dx++) {
                    int x = center.x() + dx, y = center.y() + dy;
                    if (x < 0 || x >= size || y < 0 || y >= size)
                        continue;
                    int distance = Math.max(Math.abs(dx), Math.abs(dy));
                    symbol[y][x] = distance == 0 || distance == 1 || distance == 3 ? 1 : 0;
                    areas[y][x] = FUNCTION;
                }
        for (int i = 8; i <= size - 9; i++) {
            symbol[i][6] = symbol[6][i] = i % 2 == 0 ? 1 : 0;
            areas[i][6] = areas[6][i] = FUNCTION;
        }
        for (int yi = 0; yi < alignments.length; yi++)
            for (int xi = 0; xi < alignments.length; xi++) {
                if (yi == 0 && (xi == 0 || xi == alignments.length - 1) ||
                    yi == alignments.length - 1 && xi == 0)
                    continue;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++) {
                        int x = alignments[xi] + dx, y = alignments[yi] + dy;
                        symbol[y][x] = Math.max(Math.abs(dx), Math.abs(dy)) != 1 ? 1 : 0;
                        areas[y][x] = FUNCTION;
                    }
            }
        symbol[size - 8][8] = 1;
        areas[size - 8][8] = FUNCTION;
        Positions format = formatPositions(size);
        for (List<Point> positions : List.of(format.first(), format.second()))
            for (Point point : positions)
                areas[point.y()][point.x()] = FORMAT;
        if (version >= 7) {
            Positions information = versionPositions(size);
            for (List<Point> positions : List.of(information.first(), information.second())) {
                for (Point point : positions)
                    areas[point.y()][point.x()] = VERSION;
                writeValue(symbol, positions, versionInformation(version));
            }
        }
        return new Built(symbol, areas, readingOrder(areas));
    }
    static List<Point> readingOrder(int[][] areas) {
        int size = areas.length, pair = 0;
        List<Point> order = new ArrayList<>();
        for (int right = size - 1; right >= 1; right -= 2) {
            if (right == 6)
                right = 5;
            for (int i = 0; i < size; i++) {
                int y = pair % 2 == 0 ? size - 1 - i : i;
                for (int x = right; x >= right - 1; x--)
                    if (areas[y][x] == DATA)
                        order.add(new Point(x, y));
            }
            pair++;
        }
        return order;
    }
}
