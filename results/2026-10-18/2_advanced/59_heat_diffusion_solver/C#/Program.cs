using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly string[] SOLVERS = { "jacobi", "gauss_seidel", "sor", "sor_estimated" };
    public record Segment(string name, string edge, string kind, List<Mesh.FaceRef> faces, double coefficient,
                          double theta) {
    }
    public sealed class Source {
        public string name;
        public List<int> cells;
        public double power, weight;
        public List<int[]> intervals = new();
        public bool Operating(int time) {
            foreach (int[] interval in intervals)
                if (interval[0] <= time && time < interval[1])
                    return true;
            return false;
        }
        public double Duty(int end) {
            int duration = 0;
            foreach (int[] interval in intervals)
                duration += Math.Min(interval[1], end) - Math.Min(interval[0], end);
            return (double)duration / end;
        }
    }
    public record Run(string name, string method, int step) {
        public double Dt() {
            return step / 1000.0;
        }
    }
    public record Probe(string name, int cell) {
    }
    public sealed class Params {
        public double initial, tolerance, omega, alarm, limit;
        public int end, probeEvery, maximum;
        public int[] snapshots;
        public double[] bands;
        public string reference;
        public List<Probe> probes = new();
        public List<Run> runs = new();
    }
    public static Params ReadParams(Mesh mesh) {
        Params p = new Params();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt")).ToList()) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "initial":
                p.initial = double.Parse(w[1]);
                break;
            case "end_time":
                p.end = int.Parse(w[1]);
                break;
            case "probe_every":
                p.probeEvery = int.Parse(w[1]);
                break;
            case "max_iterations":
                p.maximum = int.Parse(w[1]);
                break;
            case "tolerance":
                p.tolerance = double.Parse(w[1]);
                break;
            case "omega":
                p.omega = double.Parse(w[1]);
                break;
            case "alarm":
                p.alarm = double.Parse(w[1]);
                break;
            case "limit":
                p.limit = double.Parse(w[1]);
                break;
            case "reference":
                p.reference = w[1];
                break;
            case "probe":
                p.probes.Add(new Probe(w[1], mesh.Cell(int.Parse(w[2]), int.Parse(w[3]))));
                break;
            case "run":
                p.runs.Add(new Run(w[1], w[2], int.Parse(w[3])));
                break;
            case "snapshots": {
                p.snapshots = new int[w.Length - 1];
                for (int i = 0; i < p.snapshots.Length; i++)
                    p.snapshots[i] = int.Parse(w[i + 1]);
                break;
            }
            case "bands": {
                p.bands = new double[w.Length - 1];
                for (int i = 0; i < p.bands.Length; i++)
                    p.bands[i] = double.Parse(w[i + 1]);
                break;
            }
            }
        }
        return p;
    }
    public sealed class Face {
        public int neighbor;
        public double g, theta;
        public bool boundary;
        public Face(int neighbor, double g) {
            this.neighbor = neighbor;
            this.g = g;
        }
    }
    public sealed class Thermal {
        public Mesh mesh;
        public List<Materials.Material> materials;
        public List<Segment> segments = new();
        public List<Source> sources = new();
        public int[] material;
        public List<List<int>> materialCells = new();
        public double[] capacity, diagonal, beta, all;
        public double power, maximumStep;
        public Face[][] faces;
        public Thermal(Mesh mesh, List<Materials.Material> materials) {
            this.mesh = mesh;
            this.materials = materials;
            foreach (string line in File.ReadAllLines(Path.Combine("input/boundary.txt")).ToList()) {
                string[] w = line.Split(' ');
                if (w[0].Equals("segment")) {
                    string kind = w[5];
                    double coefficient = kind.Equals("convective") ? double.Parse(w[6]) : 0,
                           theta = kind.Equals("fixed")        ? double.Parse(w[6])
                                   : kind.Equals("convective") ? double.Parse(w[7])
                                                               : 0;
                    segments.Add(new Segment(w[1], w[2], kind,
                                             mesh.Segment(w[2], int.Parse(w[3]), int.Parse(w[4])),
                                             coefficient, theta));
                } else {
                    Source source = new Source();
                    source.name = w[1];
                    source.cells =
                        mesh.Source(int.Parse(w[2]), int.Parse(w[3]), int.Parse(w[4]), int.Parse(w[5]));
                    source.power = double.Parse(w[6]);
                    source.weight = source.power / source.cells.Count;
                    for (int i = 7; i < w.Length; i += 2)
                        source.intervals.Add(new int[] { int.Parse(w[i]), int.Parse(w[i + 1]) });
                    sources.Add(source);
                }
            }
            int n = mesh.count;
            material = new int[n];
            capacity = new double[n];
            diagonal = new double[n];
            beta = new double[n];
            all = new double[n];
            faces = Enumerable.Range(0, n)
                        .Select(
                            _ => new Face[4])
                        .ToArray();
            for (int i = 0; i < materials.Count; i++)
                materialCells.Add(new());
            for (int p = 0; p < n; p++)
                for (int i = 0; i < materials.Count; i++)
                    if (materials[i].code == mesh.codes[p]) {
                        material[p] = i;
                        materialCells[i].Add(p);
                        capacity[p] = Materials.Capacity(materials[i], mesh.dx, mesh.thickness);
                        break;
                    }
            for (int p = 0; p < n; p++)
                for (int f = 0; f < 4; f++) {
                    int q = mesh.neighbors[p][f];
                    faces[p][f] =
                        new Face(q, q >= 0 ? Materials.Interior(materials[material[p]].k,
                                                                materials[material[q]].k, mesh.thickness)
                                           : 0);
                }
            foreach (Segment segment in segments)
                foreach (Mesh.FaceRef faceRef in segment.faces) {
                    Face face = faces[faceRef.point][faceRef.direction];
                    double k = materials[material[faceRef.point]].k;
                    if (!segment.kind.Equals("insulated")) {
                        face.boundary = true;
                        face.theta = segment.theta;
                        face.g = segment.kind.Equals("fixed")
                                     ? Materials.FixedFace(k, mesh.thickness)
                                     : Materials.Convective(k, segment.coefficient, mesh.dx, mesh.thickness);
                    }
                }
            maximumStep = double.MaxValue;
            for (int p = 0; p < n; p++) {
                foreach (Face face in faces[p]) {
                    diagonal[p] += face.g;
                    if (face.boundary)
                        beta[p] += face.g * face.theta;
                }
                maximumStep = Math.Min(maximumStep, capacity[p] / diagonal[p]);
            }
            foreach (Source source in sources) {
                power += source.power;
                foreach (int p in source.cells)
                    all[p] += source.weight;
            }
        }
    }
    public record Terms(double[] field, double power) {
    }
    public static Terms SourceTerms(Thermal s, int time) {
        double[] field = new double[s.mesh.count];
        double power = 0;
        foreach (Source source in s.sources)
            if (source.Operating(time)) {
                power += source.power;
                foreach (int p in source.cells)
                    field[p] += source.weight;
            }
        return new Terms(field, power);
    }
    public static int Hottest(double[] x) {
        int p = 0;
        for (int i = 1; i < x.Length; i++)
            if (x[i] > x[p])
                p = i;
        return p;
    }
    public static double Sum(double[] x) {
        double result = 0;
        foreach (double value in x)
            result += value;
        return result;
    }
    public static double Error(double[] x, double[] y) {
        double maximum = 0;
        for (int i = 0; i < x.Length; i++)
            maximum = Math.Max(maximum, Math.Abs(x[i] - y[i]));
        return maximum;
    }
    public static double Stored(Thermal s, double[] x, double initial, List<int> cells) {
        double value = 0;
        if (cells == null) {
            for (int p = 0; p < x.Length; p++)
                value += s.capacity[p] * (x[p] - initial);
        } else
            foreach (int p in cells)
                value += s.capacity[p] * (x[p] - initial);
        return value;
    }
    public static double SegmentFlow(Thermal s, Segment segment, double[] x) {
        double total = 0;
        if (!segment.kind.Equals("insulated"))
            foreach (Mesh.FaceRef faceRef in segment.faces) {
                Face f = s.faces[faceRef.point][faceRef.direction];
                total += f.g * (f.theta - x[faceRef.point]);
            }
        return total;
    }
    public static string Status(Run run, Thermal s, Params settings) {
        int d = run.step;
        if (settings.end % d != 0 || settings.probeEvery % d != 0)
            return "step";
        foreach (int t in settings.snapshots)
            if (t % d != 0)
                return "step";
        foreach (Source source in s.sources)
            foreach (int[] interval in source.intervals)
                if (interval[0] % d != 0 || interval[1] % d != 0)
                    return "step";
        return run.method.Equals("ftcs") && run.Dt() > s.maximumStep ? "unstable" : "accepted";
    }
    public record Frame(double[] field, double stored, double boundary, double generated) {
    }
    public record Sample(int time, double[] values) {
    }
    public sealed class Result {
        public Run run;
        public string status;
        public Dictionary<int, Frame> snapshots = new();
        public List<Sample> samples = new();
        public double[] segmentEnergy, field;
        public double generated, stored, boundary, peak = -double.MaxValue;
        public int steps, peakTime, peakCell, alarmTime = -1, alarmCell, above;
        public bool balanced;
        public Result(Run run, string status) {
            this.run = run;
            this.status = status;
        }
        public void Observe(Thermal s, Params settings, int time, double[] x) {
            int hs = Hottest(x);
            if (x[hs] > peak) {
                peak = x[hs];
                peakTime = time;
                peakCell = hs;
            }
            if (x[hs] >= settings.alarm) {
                if (alarmTime < 0) {
                    alarmTime = time;
                    alarmCell = hs;
                }
                if (time > 0)
                    above += run.step;
            }
            if (time % settings.probeEvery == 0) {
                double[] readings = new double[settings.probes.Count];
                for (int i = 0; i < readings.Length; i++)
                    readings[i] = x[settings.probes[i].cell];
                samples.Add(new Sample(time, readings));
            }
            foreach (int t in settings.snapshots)
                if (t == time)
                    snapshots[time] = new Frame(x.ToArray(), Program.Stored(s, x, settings.initial, null),
                                                Sum(segmentEnergy), generated);
        }
    }
    public static Result Simulate(Run run, Thermal s, Params settings) {
        string status = Status(run, s, settings);
        Result result = new Result(run, status);
        if (!status.Equals("accepted"))
            return result;
        result.steps = settings.end / run.step;
        result.segmentEnergy = new double[s.segments.Count];
        double[] field = new double[s.mesh.count];
        Array.Fill(field, settings.initial);
        result.Observe(s, settings, 0, field);
        for (int n = 0; n < result.steps; n++) {
            Terms terms = SourceTerms(s, n * run.step);
            Transient.Step step = Transient.Advance(run.method, s, field, terms.field, run.Dt());
            double[] next = step.field;
            for (int j = 0; j < s.segments.Count; j++) {
                Segment segment = s.segments[j];
                double flow = 0;
                if (!segment.kind.Equals("insulated"))
                    foreach (Mesh.FaceRef faceRef in segment.faces) {
                        int p = faceRef.point;
                        Face face = s.faces[p][faceRef.direction];
                        double temperature;
                        if (run.method.Equals("ftcs"))
                            temperature = field[p];
                        else if (segment.edge.Equals("left") || segment.edge.Equals("right"))
                            temperature = step.intermediate[p];
                        else if (run.method.Equals("backward_euler"))
                            temperature = next[p];
                        else
                            temperature = (field[p] + next[p]) / 2;
                        flow += face.g * (face.theta - temperature);
                    }
                result.segmentEnergy[j] += run.Dt() * flow;
            }
            result.generated += run.Dt() * terms.power;
            field = next;
            result.Observe(s, settings, (n + 1) * run.step, field);
        }
        result.field = field;
        result.stored = Stored(s, field, settings.initial, null);
        result.boundary = Sum(result.segmentEnergy);
        result.balanced =
            Math.Abs(result.stored - result.boundary - result.generated) <=
            0.000001 * (Math.Abs(result.stored) + Math.Abs(result.boundary) + Math.Abs(result.generated));
        return result;
    }
    public static string Summary(string prefix, Thermal s, double[] field) {
        int p = Hottest(field);
        double minimum = field[0];
        foreach (double value in field)
            minimum = Math.Min(minimum, value);
        return prefix + " max " + Report.Real(field[p], 2) + " at " + s.mesh.Coordinates(p) + " min " +
               Report.Real(minimum, 2) + " mean " + Report.Real(Sum(field) / field.Length, 2);
    }
    public static string Verdict(bool condition) {
        return condition ? "ok" : "failed";
    }
    public static string Rejected(Result result, double? maximum) {
        string text = "run " + result.run.name + " " + result.run.method + " dt " +
                      Report.Time(result.run.step) + " rejected " + result.status;
        if (result.status.Equals("unstable") && maximum != null)
            text += " max_dt " + Report.Real(maximum.Value, 4);
        return text;
    }
    public static List<Steady.Iteration> Iterations(Thermal s, Params settings, double[] solution,
                                                    double[] rhs) {
        List<Steady.Iteration> results = new();
        Steady.Iteration jacobi = Steady.Iterate(s, settings, "jacobi", 1);
        results.Add(jacobi);
        int k = jacobi.changes.Count;
        double rho = Math.Sqrt(jacobi.changes[k - 1] / jacobi.changes[k - 3]),
               omega = 2 / (1 + Math.Sqrt(1 - rho * rho));
        for (int i = 1; i < 4; i++)
            results.Add(Steady.Iterate(s, settings, SOLVERS[i], i == 3 ? omega : settings.omega));
        int[] factors = { 1000, 100, 10, 1 };
        foreach (Steady.Iteration result in results) {
            k = result.changes.Count;
            result.rate = Math.Sqrt(result.changes[k - 1] / result.changes[k - 3]);
            result.error = Error(result.field, solution);
            result.residual = Steady.Residual(s, result.field, rhs);
            for (int i = 0; i < 4; i++) {
                result.milestones[i] = "never";
                for (int j = 0; j < k; j++)
                    if (result.changes[j] < settings.tolerance * factors[i]) {
                        result.milestones[i] = Convert.ToString(j + 1);
                        break;
                    }
            }
        }
        return results;
    }

    public static List<string> SteadyLines(Thermal s, Params settings, List<double[]> solutions,
                                           List<Steady.Iteration> iterative) {
        double[] solution = solutions[0], baseline = solutions[1];
        List<string> lines = new();
        lines.Add(Summary("steady", s, solution));
        lines.AddRange(Report.Field(s.mesh, solution));
        for (int i = 0; i < s.materials.Count; i++) {
            Materials.Material material = s.materials[i];
            List<int> cells = s.materialCells[i];
            double minimum = double.MaxValue, maximum = -double.MaxValue, total = 0;
            foreach (int p in cells) {
                minimum = Math.Min(minimum, solution[p]);
                maximum = Math.Max(maximum, solution[p]);
                total += solution[p];
            }
            lines.Add("material " + material.code + " " + material.name + " cells " + cells.Count + " min " +
                      Report.Real(minimum, 2) + " max " + Report.Real(maximum, 2) + " mean " +
                      Report.Real(total / cells.Count, 2));
        }
        double[] duties = new double[s.sources.Count];
        for (int i = 0; i < s.sources.Count; i++) {
            Source source = s.sources[i];
            duties[i] = source.Duty(settings.end);
            double total = 0, maximum = -double.MaxValue;
            foreach (int p in source.cells) {
                total += solution[p];
                maximum = Math.Max(maximum, solution[p]);
            }
            lines.Add("source " + source.name + " power " + Report.Real(source.power, 4) + " duty " +
                      Report.Real(duties[i], 4) + " mean " + Report.Real(total / source.cells.Count, 2) +
                      " max " + Report.Real(maximum, 2));
        }
        foreach (Source source in s.sources)
            for (int i = 0; i < s.sources.Count; i++) {
                double total = 0;
                foreach (int p in source.cells)
                    total += solutions[i + 2][p];
                lines.Add("influence " + source.name + " " + s.sources[i].name + " " +
                          Report.Real(total / source.cells.Count, 4));
            }
        double[] combined = baseline.ToArray(), duty = baseline.ToArray();
        for (int p = 0; p < baseline.Length; p++)
            for (int i = 0; i < s.sources.Count; i++) {
                Source source = s.sources[i];
                combined[p] += source.power * solutions[i + 2][p];
                duty[p] += (duties[i] * source.power) * solutions[i + 2][p];
            }
        lines.Add("superposition " + Verdict(Error(combined, solution) <= 0.000001));
        for (int i = 0; i < s.sources.Count; i++)
            foreach (Segment segment in s.segments) {
                double total = 0;
                if (!segment.kind.Equals("insulated"))
                    foreach (Mesh.FaceRef faceRef in segment.faces)
                        total +=
                            s.faces[faceRef.point][faceRef.direction].g * solutions[i + 2][faceRef.point];
                lines.Add("path " + s.sources[i].name + " " + segment.name + " " + Report.Real(total, 4));
            }
        lines.Add(Summary("duty_steady", s, duty));
        for (int i = 0; i < s.sources.Count; i++) {
            Source source = s.sources[i];
            double[] response = solutions[i + 2];
            double minimum = double.MaxValue;
            int limiting = 0;
            for (int p = 0; p < solution.Length; p++) {
                double power = (settings.limit - (solution[p] - source.power * response[p])) / response[p];
                if (power < minimum) {
                    minimum = power;
                    limiting = p;
                }
            }
            lines.Add("headroom " + source.name + " max_power " + Report.Real(minimum, 4) + " at " +
                      s.mesh.Coordinates(limiting));
        }
        int materials = s.materials.Count;
        int[][] count = Enumerable.Range(0, materials)
                            .Select(
                                _ => new int[materials])
                            .ToArray();
        double[][] forward = Enumerable.Range(0, materials)
                                 .Select(
                                     _ => new double[materials])
                                 .ToArray(),
                   backward = Enumerable.Range(0, materials)
                                  .Select(
                                      _ => new double[materials])
                                  .ToArray();
        double gradient = -1;
        int first = 0, second = 0;
        for (int p = 0; p < solution.Length; p++)
            foreach (int direction in new int[] { 1, 3 }) {
                Face face = s.faces[p][direction];
                int q = face.neighbor;
                if (q < 0)
                    continue;
                double value = Math.Abs(solution[p] - solution[q]) / s.mesh.dx;
                if (value > gradient) {
                    gradient = value;
                    first = p;
                    second = q;
                }
                int a = s.material[p], b = s.material[q];
                if (a == b)
                    continue;
                double flow = face.g * (solution[p] - solution[q]);
                if (a > b) {
                    int swap = a;
                    a = b;
                    b = swap;
                    flow = -flow;
                }
                count[a][b]++;
                if (flow > 0)
                    forward[a][b] += flow;
                else if (flow < 0)
                    backward[a][b] += Math.Abs(flow);
            }
        for (int i = 0; i < materials; i++)
            for (int j = i + 1; j < materials; j++)
                if (count[i][j] > 0)
                    lines.Add("interface " + s.materials[i].code + " " + s.materials[j].code + " faces " +
                              count[i][j] + " forward " + Report.Real(forward[i][j], 4) + " backward " +
                              Report.Real(backward[i][j], 4));
        double totalFlow = 0, absoluteFlow = 0;
        foreach (Segment segment in s.segments) {
            double flow = SegmentFlow(s, segment, solution);
            totalFlow += flow;
            absoluteFlow += Math.Abs(flow);
            lines.Add("segment " + segment.name + " " + segment.edge + " " + segment.kind + " flow " +
                      Report.Real(flow, 4));
        }
        lines.Add("sources " + Report.Real(s.power, 4));
        lines.Add("balance " + Verdict(Math.Abs(totalFlow + s.power) <= 0.000001 * (absoluteFlow + s.power)));
        lines.Add("max_gradient " + Report.Real(gradient, 2) + " between " + s.mesh.Coordinates(first) +
                  " and " + s.mesh.Coordinates(second));
        foreach (Steady.Iteration result in iterative) {
            string prefix = "solver " + result.method;
            if (result.method.Equals("sor") || result.method.Equals("sor_estimated"))
                prefix += " omega " + Report.Real(result.omega, 4);
            lines.Add(prefix + " iterations " + result.changes.Count + " converged " +
                      (result.converged ? "yes" : "no") + " rate " + Report.Real(result.rate, 6) +
                      " milestones " + string.Join(" ", result.milestones));
        }
        return lines;
    }
    public static List<string> SnapshotLines(Thermal s, Params settings, List<Result> results) {
        List<string> lines = new();
        foreach (Result result in results) {
            if (!result.status.Equals("accepted")) {
                lines.Add(Rejected(result, s.maximumStep));
                continue;
            }
            foreach (int time in settings.snapshots) {
                double[] field = result.snapshots[time].field;
                string prefix = "run " + result.run.name + " " + result.run.method + " dt " +
                                Report.Time(result.run.step) + " time " + Report.Time(time);
                lines.Add(Summary(prefix, s, field));
                lines.AddRange(Report.Field(s.mesh, field));
            }
        }
        return lines;
    }
    public static List<string> ProbeLines(Params settings, List<Result> results) {
        List<string> lines = new();
        lines.Add("run,time,probe,temperature");
        foreach (Result result in results)
            if (result.status.Equals("accepted"))
                foreach (Sample sample in result.samples)
                    for (int i = 0; i < settings.probes.Count; i++)
                        lines.Add(result.run.name + "," + Report.Time(sample.time) + "," +
                                  settings.probes[i].name + "," + Report.Real(sample.values[i], 3));
        return lines;
    }
    public static List<string> Comparison(Thermal s, Params settings, List<Result> results, Result reference,
                                          List<double[]> solutions, double[] rhs,
                                          List<Steady.Iteration> iterative) {
        double[] solution = solutions[0];
        List<string> lines = new();
        lines.Add("ftcs_max_dt " + Report.Real(s.maximumStep, 4));
        foreach (Result result in results) {
            if (!result.status.Equals("accepted")) {
                lines.Add(Rejected(result, null));
                continue;
            }
            Run run = result.run;
            string name = run.name, alarm = result.alarmTime < 0 ? "never"
                                                                 : Report.Time(result.alarmTime) + " at " +
                                                                       s.mesh.Coordinates(result.alarmCell);
            lines.Add("run " + name + " " + run.method + " dt " + Report.Time(run.step) + " steps " +
                      result.steps + " peak " + Report.Real(result.peak, 2) + " time " +
                      Report.Time(result.peakTime) + " at " + s.mesh.Coordinates(result.peakCell) +
                      " alarm " + alarm + " above " + Report.Time(result.above));
            lines.Add("energy " + name + " stored " + Report.Real(result.stored, 2) + " boundary " +
                      Report.Real(result.boundary, 2) + " source " + Report.Real(result.generated, 2) +
                      " balance " + Verdict(result.balanced));
            foreach (int time in settings.snapshots) {
                Frame frame = result.snapshots[time];
                lines.Add("energy_at " + name + " time " + Report.Time(time) + " stored " +
                          Report.Real(frame.stored, 2) + " boundary " + Report.Real(frame.boundary, 2) +
                          " source " + Report.Real(frame.generated, 2));
            }
            for (int i = 0; i < s.materials.Count; i++)
                lines.Add("energy_material " + name + " " + s.materials[i].code + " " +
                          Report.Real(Stored(s, result.field, settings.initial, s.materialCells[i]), 2));
            for (int i = 0; i < s.segments.Count; i++)
                lines.Add("energy_segment " + name + " " + s.segments[i].name + " " +
                          Report.Real(result.segmentEnergy[i], 2));
            for (int i = 0; i < settings.probes.Count; i++) {
                double maximum = result.samples[0].values[i], minimum = maximum;
                int maximumTime = result.samples[0].time, minimumTime = maximumTime;
                foreach (Sample sample in result.samples) {
                    double value = sample.values[i];
                    if (value > maximum) {
                        maximum = value;
                        maximumTime = sample.time;
                    }
                    if (value < minimum) {
                        minimum = value;
                        minimumTime = sample.time;
                    }
                }
                lines.Add("probe_summary " + name + " " + settings.probes[i].name + " max " +
                          Report.Real(maximum, 3) + " time " + Report.Time(maximumTime) + " min " +
                          Report.Real(minimum, 3) + " time " + Report.Time(minimumTime));
            }
            if (result != reference)
                foreach (int time in settings.snapshots) {
                    double[] field = result.snapshots[time].field, other = reference.snapshots[time].field;
                    double squares = 0;
                    for (int p = 0; p < field.Length; p++) {
                        double e = Math.Abs(field[p] - other[p]);
                        squares += e * e;
                    }
                    lines.Add("compare " + name + " " + reference.run.name + " time " + Report.Time(time) +
                              " max_diff " + Report.Real(Error(field, other), 6) + " rms_diff " +
                              Report.Real(Math.Sqrt(squares / field.Length), 6));
                }
            lines.Add("final " + name + " steady_max_diff " + Report.Real(Error(result.field, solution), 6));
        }
        lines.Add("steady direct max_residual " + Report.Real(Steady.Residual(s, solution, rhs), 6));
        foreach (Steady.Iteration result in iterative)
            lines.Add("steady " + result.method + " iterations " + result.changes.Count + " max_diff " +
                      Report.Real(result.error, 6) + " max_residual " + Report.Real(result.residual, 6));
        double rho = iterative[0].rate, omega = iterative[3].omega;
        lines.Add("jacobi_spectral_radius " + Report.Real(rho, 6) + " squared " + Report.Real(rho * rho, 6));
        lines.Add("omega_estimated " + Report.Real(omega, 4));
        return lines;
    }
    public static void Map(List<string> lines, string prefix, Thermal s, double[] field, double[] bands) {
        Report.MapImage image = Report.Isotherm(s.mesh, field, bands);
        List<string> counts = new();
        foreach (int value in image.counts)
            counts.Add(Convert.ToString(value));
        lines.Add(prefix + " counts " + string.Join(" ", counts));
        lines.AddRange(image.lines);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Mesh mesh = new Mesh();
        Params settings = ReadParams(mesh);
        Thermal system = new Thermal(mesh, Materials.Read());
        List<double[]> vectors = new();
        double[] rhs = new double[mesh.count];
        for (int p = 0; p < rhs.Length; p++)
            rhs[p] = system.beta[p] + system.all[p];
        vectors.Add(rhs);
        vectors.Add(system.beta);
        foreach (Source source in system.sources) {
            double[] vector = new double[mesh.count];
            foreach (int p in source.cells)
                vector[p] = 1.0 / source.cells.Count;
            vectors.Add(vector);
        }
        List<double[]> solutions = Steady.Direct(system, vectors);
        List<Steady.Iteration> iterative = Iterations(system, settings, solutions[0], rhs);
        List<Result> results = new();
        Result reference = null;
        foreach (Run run in settings.runs) {
            Result result = Simulate(run, system, settings);
            results.Add(result);
            if (run.name.Equals(settings.reference))
                reference = result;
        }
        List<string> maps = new();
        Map(maps, "isotherms steady", system, solutions[0], settings.bands);
        foreach (int time in settings.snapshots)
            Map(maps, "isotherms " + reference.run.name + " time " + Report.Time(time), system,
                reference.snapshots[time].field, settings.bands);
        Report.Write("snapshots.txt", SnapshotLines(system, settings, results));
        Report.Write("probes.csv", ProbeLines(settings, results));
        Report.Write("steady_state.txt", SteadyLines(system, settings, solutions, iterative));
        Report.Write("solver_comparison.txt",
                     Comparison(system, settings, results, reference, solutions, rhs, iterative));
        Report.Write("isotherms.txt", maps);
    }
}
