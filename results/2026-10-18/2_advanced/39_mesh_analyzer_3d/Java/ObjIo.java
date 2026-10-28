import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;

final class ObjIo {
    record Polygon(int number, int line, String group, int[] v) {}
    record Error(int line, String kind) {}
    static final class Face {
        int triangle, polygon, line;
        String group;
        int[] v;
        Face(int triangle, int polygon, int line, String group, int[] v) {
            this.triangle = triangle;
            this.polygon = polygon;
            this.line = line;
            this.group = group;
            this.v = v;
        }
        Face copy() {
            return new Face(triangle, polygon, line, group, v.clone());
        }
    }
    static final class Model {
        int lines, ignored;
        List<Measure.Vec> vertices = new ArrayList<>();
        List<Polygon> polygons = new ArrayList<>();
        List<Error> errors = new ArrayList<>();
        Model() {
            vertices.add(new Measure.Vec(0, 0, 0));
        }
    }
    static boolean integer(String s) {
        return s.matches("-?[0-9]+");
    }
    static Model read() throws IOException {
        Model m = new Model();
        String group = "default";
        List<String> lines = Files.readAllLines(Path.of("input/model.obj"), StandardCharsets.US_ASCII);
        m.lines = lines.size();
        for (int i = 0; i < lines.size(); i++) {
            String text = lines.get(i);
            if (text.isEmpty() || text.startsWith("#"))
                continue;
            String[] w = text.split(" ", -1);
            String command = w[0];
            if (command.equals("v")) {
                if (w.length != 4 || !integer(w[1]) || !integer(w[2]) || !integer(w[3]))
                    m.errors.add(new Error(i + 1, "bad_vertex"));
                else
                    m.vertices.add(
                        new Measure.Vec(Long.parseLong(w[1]), Long.parseLong(w[2]), Long.parseLong(w[3])));
            } else if (command.equals("f")) {
                if (w.length < 4) {
                    m.errors.add(new Error(i + 1, "short_face"));
                    continue;
                }
                int[] v = new int[w.length - 1];
                String error = null;
                for (int j = 1; j < w.length; j++) {
                    String word = w[j].split("/", -1)[0];
                    if (!integer(word)) {
                        error = "bad_index";
                        break;
                    }
                    long number;
                    try {
                        number = Long.parseLong(word);
                    } catch (NumberFormatException ex) {
                        error = "out_of_range";
                        break;
                    }
                    if (number == 0) {
                        error = "bad_index";
                        break;
                    }
                    if (number < 0)
                        number = m.vertices.size() + number;
                    if (number < 1 || number >= m.vertices.size()) {
                        error = "out_of_range";
                        break;
                    }
                    v[j - 1] = (int)number;
                }
                if (error != null)
                    m.errors.add(new Error(i + 1, error));
                else
                    m.polygons.add(new Polygon(m.polygons.size() + 1, i + 1, group, v));
            } else if (command.equals("g"))
                group = w.length > 1 ? w[1] : "default";
            else if (Set.of("vt", "vn", "s", "o", "usemtl", "mtllib").contains(command))
                m.ignored++;
            else
                m.errors.add(new Error(i + 1, "unknown_keyword"));
        }
        return m;
    }
    static List<String> repaired(List<Measure.Vec> points, List<Face> faces) {
        List<String> result = new ArrayList<>();
        result.add("# vertices " + (points.size() - 1) + " faces " + faces.size());
        for (int i = 1; i < points.size(); i++)
            result.add("v " + points.get(i));
        String previous = "";
        for (Face f : faces) {
            if (!f.group.equals(previous)) {
                result.add("g " + f.group);
                previous = f.group;
            }
            result.add("f " + Main.numbers(f.v));
        }
        return result;
    }
}
