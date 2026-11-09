import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Dataset {
    record Box(long x1, long y1, long x2, long y2) {}
    record Obj(int id, Box box) {}
    record Command(String name, int[] values) {}
    record Data(List<Obj> points, List<Obj> rectangles, int world, int bucket, int maximum, int minimum,
                int grid, List<Command> commands) {}
    static Obj point(int id, int x, int y) {
        return new Obj(id, new Box(x, y, x, y));
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Data read() throws IOException {
        List<Obj> points = new ArrayList<>(), rectangles = new ArrayList<>();
        List<String> pointLines = lines("points.csv"), rectLines = lines("rects.csv");
        for (int i = 1; i < pointLines.size(); i++) {
            String[] w = pointLines.get(i).split(",");
            points.add(point(Integer.parseInt(w[0]), Integer.parseInt(w[1]), Integer.parseInt(w[2])));
        }
        for (int i = 1; i < rectLines.size(); i++) {
            String[] w = rectLines.get(i).split(",");
            rectangles.add(
                new Obj(Integer.parseInt(w[0]), new Box(Long.parseLong(w[1]), Long.parseLong(w[2]),
                                                        Long.parseLong(w[3]), Long.parseLong(w[4]))));
        }
        List<String> params = lines("params.txt");
        int world = Integer.parseInt(params.get(0).split(" ")[1]),
            bucket = Integer.parseInt(params.get(1).split(" ")[1]),
            maximum = Integer.parseInt(params.get(2).split(" ")[1]),
            minimum = Integer.parseInt(params.get(2).split(" ")[2]),
            grid = Integer.parseInt(params.get(3).split(" ")[1]);
        List<Command> commands = new ArrayList<>();
        for (String line : lines("queries.txt")) {
            String[] w = line.split(" ");
            int[] values = new int[w.length - 1];
            for (int i = 1; i < w.length; i++)
                values[i - 1] = Integer.parseInt(w[i]);
            commands.add(new Command(w[0], values));
        }
        return new Data(points, rectangles, world, bucket, maximum, minimum, grid, commands);
    }
}
