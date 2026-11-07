using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public sealed class Layout {
    public record Key(string section, string end);
    public record Beyond(string kind, string name);
    public record Buffer(string name, string section, string end, int row, int column);
    public record Boundary(string name, string section, string end);
    public record Label(int row, int column, string text);
    public sealed class Section {
        public string name, routeLock;
        public int length, row, first, last, occupiedSeconds, lockedSeconds;
        public bool failed;
        public List<string> occupants = new();
        public HashSet<string> trains = new(), overlapLocks = new();
        public Section(string name, int length, int row, int first, int last) {
            this.name = name;
            this.length = length;
            this.row = row;
            this.first = first;
            this.last = last;
        }
    }
    public sealed class Point {
        public string name, side, common, normal, reverse, position = "N", target;
        public int row, column, throwsCount, lockedSeconds, movingSeconds;
        public int? completion;
        public bool moving, failed;
        public HashSet<Interlocking.PointLock> locks = new();
        public Point(string[] f) {
            name = f[1];
            side = f[2];
            common = f[3];
            normal = f[4];
            reverse = f[5];
            row = int.Parse(f[6]);
            column = int.Parse(f[7]);
        }
        public bool Detected() => !moving && !failed;
    }
    public sealed class Signal {
        public string name, section, direction, aspect = "RED";
        public int row, column, passes;
        public Dictionary<string, int> seconds = new();
        public Signal(string[] f) {
            name = f[1];
            section = f[2];
            direction = f[3];
            row = int.Parse(f[4]);
            column = int.Parse(f[5]);
        }
    }
    public Dictionary<string, Section> sections = new();
    public Dictionary<string, Point> points = new();
    public Dictionary<string, Signal> signals = new();
    public Dictionary<string, Buffer> buffers = new();
    public Dictionary<string, Boundary> boundaries = new();
    public List<Label> labels = new();
    public Dictionary<Key, Beyond> ends = new();
    public Dictionary<Key, Signal> signalsAt = new();
    public Layout() {
        foreach (string line in File.ReadAllLines("input/layout.txt", Encoding.ASCII)) {
            string[] f = line.Split(' ');
            switch (f[0]) {
            case "SECTION":
                sections[f[1]] =
                    new(f[1], int.Parse(f[2]), int.Parse(f[3]), int.Parse(f[4]), int.Parse(f[5]));
                break;
            case "JOINT":
                ends[new(f[1], "R")] = new("section", f[2]);
                ends[new(f[2], "L")] = new("section", f[1]);
                break;
            case "POINT": {
                Point p = new(f);
                points[p.name] = p;
                ends[new(p.common, p.side)] = new("point", p.name);
                string other = p.side == "R" ? "L" : "R";
                ends[new(p.normal, other)] = new("point", p.name);
                ends[new(p.reverse, other)] = new("point", p.name);
                break;
            }
            case "SIGNAL": {
                Signal signal = new(f);
                signals[signal.name] = signal;
                signalsAt[new(signal.section, signal.direction)] = signal;
                break;
            }
            case "BUFFER":
                buffers[f[1]] = new(f[1], f[2], f[3], int.Parse(f[4]), int.Parse(f[5]));
                ends[new(f[2], f[3])] = new("buffer", f[1]);
                break;
            case "BOUNDARY":
                boundaries[f[1]] = new(f[1], f[2], f[3]);
                ends[new(f[2], f[3])] = new("boundary", f[1]);
                break;
            case "LABEL":
                labels.Add(new(int.Parse(f[1]), int.Parse(f[2]), f[3]));
                break;
            }
        }
    }
    public Beyond GetBeyond(string section, string direction) {
        Beyond beyond = ends[new(section, direction == "UP" ? "R" : "L")];
        if (beyond.kind != "point")
            return beyond;
        Point point = points[beyond.name];
        string branch = point.position == "N" ? point.normal : point.reverse;
        if (point.moving || section != point.common && section != branch)
            return new("impassable", null);
        return new("section", section == point.common ? branch : point.common);
    }
}
