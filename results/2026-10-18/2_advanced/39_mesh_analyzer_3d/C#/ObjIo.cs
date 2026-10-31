using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class ObjIo {
    public static bool Matches(this string s, string pattern) => Regex.IsMatch(s,
                                                                               "\\A(?:" + pattern + ")\\z");
    public sealed record Polygon(int number, int line, string group, int[] v);
    public sealed record Error(int line, string kind);
    public sealed class Face {
        public int triangle, polygon, line;
        public string group;
        public int[] v;
        public Face(int triangle, int polygon, int line, string group, int[] v) {
            this.triangle = triangle;
            this.polygon = polygon;
            this.line = line;
            this.group = group;
            this.v = v;
        }
        public Face Copy() {
            return new Face(triangle, polygon, line, group, v.ToArray());
        }
    }
    public sealed class Model {
        public int lines, ignored;
        public List<Measure.Vec> vertices = new();
        public List<Polygon> polygons = new();
        public List<Error> errors = new();
        public Model() {
            vertices.Add(new Measure.Vec(0, 0, 0));
        }
    }
    public static bool Integer(string s) {
        return s.Matches("-?[0-9]+");
    }
    public static Model Read() {
        Model m = new Model();
        string group = "default";
        List<string> lines = File.ReadAllLines(Path.Combine("input/model.obj"), Encoding.ASCII).ToList();
        m.lines = lines.Count;
        for (int i = 0; i < lines.Count; i++) {
            string text = lines[i];
            if (text.Length == 0 || text.StartsWith("#"))
                continue;
            string[] w = text.Split(' ');
            string command = w[0];
            if (command.Equals("v")) {
                if (w.Length != 4 || !Integer(w[1]) || !Integer(w[2]) || !Integer(w[3]))
                    m.errors.Add(new Error(i + 1, "bad_vertex"));
                else
                    m.vertices.Add(new Measure.Vec(long.Parse(w[1]), long.Parse(w[2]), long.Parse(w[3])));
            } else if (command.Equals("f")) {
                if (w.Length < 4) {
                    m.errors.Add(new Error(i + 1, "short_face"));
                    continue;
                }
                int[] v = new int[w.Length - 1];
                string error = null;
                for (int j = 1; j < w.Length; j++) {
                    string word = w[j].Split('/')[0];
                    if (!Integer(word)) {
                        error = "bad_index";
                        break;
                    }
                    long number;
                    try {
                        number = long.Parse(word);
                    } catch (Exception ex) when (ex is FormatException or OverflowException) {
                        error = "out_of_range";
                        break;
                    }
                    if (number == 0) {
                        error = "bad_index";
                        break;
                    }
                    if (number < 0)
                        number = m.vertices.Count + number;
                    if (number < 1 || number >= m.vertices.Count) {
                        error = "out_of_range";
                        break;
                    }
                    v[j - 1] = (int)number;
                }
                if (error != null)
                    m.errors.Add(new Error(i + 1, error));
                else
                    m.polygons.Add(new Polygon(m.polygons.Count + 1, i + 1, group, v));
            } else if (command.Equals("g"))
                group = w.Length > 1 ? w[1] : "default";
            else if (new HashSet<string> { "vt", "vn", "s", "o", "usemtl", "mtllib" }.Contains(command))
                m.ignored++;
            else
                m.errors.Add(new Error(i + 1, "unknown_keyword"));
        }
        return m;
    }
    public static List<string> Repaired(List<Measure.Vec> points, List<Face> faces) {
        List<string> result = new();
        result.Add("# vertices " + (points.Count - 1) + " faces " + faces.Count);
        for (int i = 1; i < points.Count; i++)
            result.Add("v " + points[i]);
        string previous = "";
        foreach (Face f in faces) {
            if (!f.group.Equals(previous)) {
                result.Add("g " + f.group);
                previous = f.group;
            }
            result.Add("f " + Program.Numbers(f.v));
        }
        return result;
    }
}
