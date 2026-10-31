import java.nio.file.*;
import java.util.*;

public final class Main {
    static final String[] SOLVERS = {"jacobi", "gauss_seidel", "sor", "sor_estimated"};
    record Segment(String name, String edge, String kind, List<Mesh.FaceRef> faces, double coefficient,
                   double theta) {}
    static final class Source {
        String name;
        List<Integer> cells;
        double power, weight;
        List<int[]> intervals = new ArrayList<>();
        boolean operating(int time) {
            for (int[] interval : intervals)
                if (interval[0] <= time && time < interval[1])
                    return true;
            return false;
        }
        double duty(int end) {
            int duration = 0;
            for (int[] interval : intervals)
                duration += Math.min(interval[1], end) - Math.min(interval[0], end);
            return (double)duration / end;
        }
    }
    record Run(String name, String method, int step) {
        double dt() {
            return step / 1000.0;
        }
    }
    record Probe(String name, int cell) {}
    static final class Params {
        double initial, tolerance, omega, alarm, limit;
        int end, probeEvery, maximum;
        int[] snapshots;
        double[] bands;
        String reference;
        List<Probe> probes = new ArrayList<>();
        List<Run> runs = new ArrayList<>();
    }
    static Params readParams(Mesh mesh) throws Exception {
        Params p = new Params();
        for (String line : Files.readAllLines(Path.of("input/params.txt"))) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "initial" -> p.initial = Double.parseDouble(w[1]);
            case "end_time" -> p.end = Integer.parseInt(w[1]);
            case "probe_every" -> p.probeEvery = Integer.parseInt(w[1]);
            case "max_iterations" -> p.maximum = Integer.parseInt(w[1]);
            case "tolerance" -> p.tolerance = Double.parseDouble(w[1]);
            case "omega" -> p.omega = Double.parseDouble(w[1]);
            case "alarm" -> p.alarm = Double.parseDouble(w[1]);
            case "limit" -> p.limit = Double.parseDouble(w[1]);
            case "reference" -> p.reference = w[1];
            case "probe" ->
                p.probes.add(new Probe(w[1], mesh.cell(Integer.parseInt(w[2]), Integer.parseInt(w[3]))));
            case "run" -> p.runs.add(new Run(w[1], w[2], Integer.parseInt(w[3])));
            case "snapshots" -> {
                p.snapshots = new int[w.length - 1];
                for (int i = 0; i < p.snapshots.length; i++)
                    p.snapshots[i] = Integer.parseInt(w[i + 1]);
            }
            case "bands" -> {
                p.bands = new double[w.length - 1];
                for (int i = 0; i < p.bands.length; i++)
                    p.bands[i] = Double.parseDouble(w[i + 1]);
            }
            }
        }
        return p;
    }
    static final class Face {
        int neighbor;
        double g, theta;
        boolean boundary;
        Face(int neighbor, double g) {
            this.neighbor = neighbor;
            this.g = g;
        }
    }
    static final class Thermal {
        Mesh mesh;
        List<Materials.Material> materials;
        List<Segment> segments = new ArrayList<>();
        List<Source> sources = new ArrayList<>();
        int[] material;
        List<List<Integer>> materialCells = new ArrayList<>();
        double[] capacity, diagonal, beta, all;
        double power, maximumStep;
        Face[][] faces;
        Thermal(Mesh mesh, List<Materials.Material> materials) throws Exception {
            this.mesh = mesh;
            this.materials = materials;
            for (String line : Files.readAllLines(Path.of("input/boundary.txt"))) {
                String[] w = line.split(" ");
                if (w[0].equals("segment")) {
                    String kind = w[5];
                    double coefficient = kind.equals("convective") ? Double.parseDouble(w[6]) : 0,
                           theta = kind.equals("fixed")        ? Double.parseDouble(w[6])
                                   : kind.equals("convective") ? Double.parseDouble(w[7])
                                                               : 0;
                    segments.add(new Segment(
                        w[1], w[2], kind, mesh.segment(w[2], Integer.parseInt(w[3]), Integer.parseInt(w[4])),
                        coefficient, theta));
                } else {
                    Source source = new Source();
                    source.name = w[1];
                    source.cells = mesh.source(Integer.parseInt(w[2]), Integer.parseInt(w[3]),
                                               Integer.parseInt(w[4]), Integer.parseInt(w[5]));
                    source.power = Double.parseDouble(w[6]);
                    source.weight = source.power / source.cells.size();
                    for (int i = 7; i < w.length; i += 2)
                        source.intervals.add(new int[] {Integer.parseInt(w[i]), Integer.parseInt(w[i + 1])});
                    sources.add(source);
                }
            }
            int n = mesh.count;
            material = new int[n];
            capacity = new double[n];
            diagonal = new double[n];
            beta = new double[n];
            all = new double[n];
            faces = new Face[n][4];
            for (int i = 0; i < materials.size(); i++)
                materialCells.add(new ArrayList<>());
            for (int p = 0; p < n; p++)
                for (int i = 0; i < materials.size(); i++)
                    if (materials.get(i).code() == mesh.codes[p]) {
                        material[p] = i;
                        materialCells.get(i).add(p);
                        capacity[p] = Materials.capacity(materials.get(i), mesh.dx, mesh.thickness);
                        break;
                    }
            for (int p = 0; p < n; p++)
                for (int f = 0; f < 4; f++) {
                    int q = mesh.neighbors[p][f];
                    faces[p][f] = new Face(q, q >= 0 ? Materials.interior(materials.get(material[p]).k(),
                                                                          materials.get(material[q]).k(),
                                                                          mesh.thickness)
                                                     : 0);
                }
            for (Segment segment : segments)
                for (Mesh.FaceRef ref : segment.faces()) {
                    Face face = faces[ref.point()][ref.direction()];
                    double k = materials.get(material[ref.point()]).k();
                    if (!segment.kind().equals("insulated")) {
                        face.boundary = true;
                        face.theta = segment.theta();
                        face.g =
                            segment.kind().equals("fixed")
                                ? Materials.fixedFace(k, mesh.thickness)
                                : Materials.convective(k, segment.coefficient(), mesh.dx, mesh.thickness);
                    }
                }
            maximumStep = Double.MAX_VALUE;
            for (int p = 0; p < n; p++) {
                for (Face face : faces[p]) {
                    diagonal[p] += face.g;
                    if (face.boundary)
                        beta[p] += face.g * face.theta;
                }
                maximumStep = Math.min(maximumStep, capacity[p] / diagonal[p]);
            }
            for (Source source : sources) {
                power += source.power;
                for (int p : source.cells)
                    all[p] += source.weight;
            }
        }
    }
    record Terms(double[] field, double power) {}
    static Terms terms(Thermal s, int time) {
        double[] field = new double[s.mesh.count];
        double power = 0;
        for (Source source : s.sources)
            if (source.operating(time)) {
                power += source.power;
                for (int p : source.cells)
                    field[p] += source.weight;
            }
        return new Terms(field, power);
    }
    static int hottest(double[] x) {
        int p = 0;
        for (int i = 1; i < x.length; i++)
            if (x[i] > x[p])
                p = i;
        return p;
    }
    static double sum(double[] x) {
        double result = 0;
        for (double value : x)
            result += value;
        return result;
    }
    static double error(double[] x, double[] y) {
        double maximum = 0;
        for (int i = 0; i < x.length; i++)
            maximum = Math.max(maximum, Math.abs(x[i] - y[i]));
        return maximum;
    }
    static double stored(Thermal s, double[] x, double initial, List<Integer> cells) {
        double value = 0;
        if (cells == null) {
            for (int p = 0; p < x.length; p++)
                value += s.capacity[p] * (x[p] - initial);
        } else
            for (int p : cells)
                value += s.capacity[p] * (x[p] - initial);
        return value;
    }
    static double segmentFlow(Thermal s, Segment segment, double[] x) {
        double total = 0;
        if (!segment.kind().equals("insulated"))
            for (Mesh.FaceRef ref : segment.faces()) {
                Face f = s.faces[ref.point()][ref.direction()];
                total += f.g * (f.theta - x[ref.point()]);
            }
        return total;
    }
    static String status(Run run, Thermal s, Params settings) {
        int d = run.step();
        if (settings.end % d != 0 || settings.probeEvery % d != 0)
            return "step";
        for (int t : settings.snapshots)
            if (t % d != 0)
                return "step";
        for (Source source : s.sources)
            for (int[] interval : source.intervals)
                if (interval[0] % d != 0 || interval[1] % d != 0)
                    return "step";
        return run.method().equals("ftcs") && run.dt() > s.maximumStep ? "unstable" : "accepted";
    }
    record Frame(double[] field, double stored, double boundary, double generated) {}
    record Sample(int time, double[] values) {}
    static final class Result {
        Run run;
        String status;
        Map<Integer, Frame> snapshots = new HashMap<>();
        List<Sample> samples = new ArrayList<>();
        double[] segmentEnergy, field;
        double generated, stored, boundary, peak = -Double.MAX_VALUE;
        int steps, peakTime, peakCell, alarmTime = -1, alarmCell, above;
        boolean balanced;
        Result(Run run, String status) {
            this.run = run;
            this.status = status;
        }
        void observe(Thermal s, Params settings, int time, double[] x) {
            int hs = hottest(x);
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
                    above += run.step();
            }
            if (time % settings.probeEvery == 0) {
                double[] readings = new double[settings.probes.size()];
                for (int i = 0; i < readings.length; i++)
                    readings[i] = x[settings.probes.get(i).cell()];
                samples.add(new Sample(time, readings));
            }
            for (int t : settings.snapshots)
                if (t == time)
                    snapshots.put(time, new Frame(x.clone(), Main.stored(s, x, settings.initial, null),
                                                  sum(segmentEnergy), generated));
        }
    }
    static Result simulate(Run run, Thermal s, Params settings) {
        String status = status(run, s, settings);
        Result result = new Result(run, status);
        if (!status.equals("accepted"))
            return result;
        result.steps = settings.end / run.step();
        result.segmentEnergy = new double[s.segments.size()];
        double[] field = new double[s.mesh.count];
        Arrays.fill(field, settings.initial);
        result.observe(s, settings, 0, field);
        for (int n = 0; n < result.steps; n++) {
            Terms terms = terms(s, n * run.step());
            Transient.Step step = Transient.advance(run.method(), s, field, terms.field(), run.dt());
            double[] next = step.field();
            for (int j = 0; j < s.segments.size(); j++) {
                Segment segment = s.segments.get(j);
                double flow = 0;
                if (!segment.kind().equals("insulated"))
                    for (Mesh.FaceRef ref : segment.faces()) {
                        int p = ref.point();
                        Face face = s.faces[p][ref.direction()];
                        double temperature;
                        if (run.method().equals("ftcs"))
                            temperature = field[p];
                        else if (segment.edge().equals("left") || segment.edge().equals("right"))
                            temperature = step.intermediate()[p];
                        else if (run.method().equals("backward_euler"))
                            temperature = next[p];
                        else
                            temperature = (field[p] + next[p]) / 2;
                        flow += face.g * (face.theta - temperature);
                    }
                result.segmentEnergy[j] += run.dt() * flow;
            }
            result.generated += run.dt() * terms.power();
            field = next;
            result.observe(s, settings, (n + 1) * run.step(), field);
        }
        result.field = field;
        result.stored = stored(s, field, settings.initial, null);
        result.boundary = sum(result.segmentEnergy);
        result.balanced =
            Math.abs(result.stored - result.boundary - result.generated) <=
            0.000001 * (Math.abs(result.stored) + Math.abs(result.boundary) + Math.abs(result.generated));
        return result;
    }
    static String summary(String prefix, Thermal s, double[] field) {
        int p = hottest(field);
        double minimum = field[0];
        for (double value : field)
            minimum = Math.min(minimum, value);
        return prefix + " max " + Report.real(field[p], 2) + " at " + s.mesh.coordinates(p) + " min " +
            Report.real(minimum, 2) + " mean " + Report.real(sum(field) / field.length, 2);
    }
    static String verdict(boolean condition) {
        return condition ? "ok" : "failed";
    }
    static String rejected(Result result, Double maximum) {
        String text = "run " + result.run.name() + " " + result.run.method() + " dt " +
                      Report.time(result.run.step()) + " rejected " + result.status;
        if (result.status.equals("unstable") && maximum != null)
            text += " max_dt " + Report.real(maximum, 4);
        return text;
    }
    static List<Steady.Iteration> iterations(Thermal s, Params settings, double[] solution, double[] rhs) {
        List<Steady.Iteration> results = new ArrayList<>();
        Steady.Iteration jacobi = Steady.iterate(s, settings, "jacobi", 1);
        results.add(jacobi);
        int k = jacobi.changes.size();
        double rho = Math.sqrt(jacobi.changes.get(k - 1) / jacobi.changes.get(k - 3)),
               omega = 2 / (1 + Math.sqrt(1 - rho * rho));
        for (int i = 1; i < 4; i++)
            results.add(Steady.iterate(s, settings, SOLVERS[i], i == 3 ? omega : settings.omega));
        int[] factors = {1000, 100, 10, 1};
        for (Steady.Iteration result : results) {
            k = result.changes.size();
            result.rate = Math.sqrt(result.changes.get(k - 1) / result.changes.get(k - 3));
            result.error = error(result.field, solution);
            result.residual = Steady.residual(s, result.field, rhs);
            for (int i = 0; i < 4; i++) {
                result.milestones[i] = "never";
                for (int j = 0; j < k; j++)
                    if (result.changes.get(j) < settings.tolerance * factors[i]) {
                        result.milestones[i] = Integer.toString(j + 1);
                        break;
                    }
            }
        }
        return results;
    }

    static List<String> steadyLines(Thermal s, Params settings, List<double[]> solutions,
                                    List<Steady.Iteration> iterative) {
        double[] solution = solutions.get(0), base = solutions.get(1);
        List<String> lines = new ArrayList<>();
        lines.add(summary("steady", s, solution));
        lines.addAll(Report.field(s.mesh, solution));
        for (int i = 0; i < s.materials.size(); i++) {
            Materials.Material material = s.materials.get(i);
            List<Integer> cells = s.materialCells.get(i);
            double minimum = Double.MAX_VALUE, maximum = -Double.MAX_VALUE, total = 0;
            for (int p : cells) {
                minimum = Math.min(minimum, solution[p]);
                maximum = Math.max(maximum, solution[p]);
                total += solution[p];
            }
            lines.add("material " + material.code() + " " + material.name() + " cells " + cells.size() +
                      " min " + Report.real(minimum, 2) + " max " + Report.real(maximum, 2) + " mean " +
                      Report.real(total / cells.size(), 2));
        }
        double[] duties = new double[s.sources.size()];
        for (int i = 0; i < s.sources.size(); i++) {
            Source source = s.sources.get(i);
            duties[i] = source.duty(settings.end);
            double total = 0, maximum = -Double.MAX_VALUE;
            for (int p : source.cells) {
                total += solution[p];
                maximum = Math.max(maximum, solution[p]);
            }
            lines.add("source " + source.name + " power " + Report.real(source.power, 4) + " duty " +
                      Report.real(duties[i], 4) + " mean " + Report.real(total / source.cells.size(), 2) +
                      " max " + Report.real(maximum, 2));
        }
        for (Source source : s.sources)
            for (int i = 0; i < s.sources.size(); i++) {
                double total = 0;
                for (int p : source.cells)
                    total += solutions.get(i + 2)[p];
                lines.add("influence " + source.name + " " + s.sources.get(i).name + " " +
                          Report.real(total / source.cells.size(), 4));
            }
        double[] combined = base.clone(), duty = base.clone();
        for (int p = 0; p < base.length; p++)
            for (int i = 0; i < s.sources.size(); i++) {
                Source source = s.sources.get(i);
                combined[p] += source.power * solutions.get(i + 2)[p];
                duty[p] += (duties[i] * source.power) * solutions.get(i + 2)[p];
            }
        lines.add("superposition " + verdict(error(combined, solution) <= 0.000001));
        for (int i = 0; i < s.sources.size(); i++)
            for (Segment segment : s.segments) {
                double total = 0;
                if (!segment.kind().equals("insulated"))
                    for (Mesh.FaceRef ref : segment.faces())
                        total += s.faces[ref.point()][ref.direction()].g * solutions.get(i + 2)[ref.point()];
                lines.add("path " + s.sources.get(i).name + " " + segment.name() + " " +
                          Report.real(total, 4));
            }
        lines.add(summary("duty_steady", s, duty));
        for (int i = 0; i < s.sources.size(); i++) {
            Source source = s.sources.get(i);
            double[] response = solutions.get(i + 2);
            double minimum = Double.MAX_VALUE;
            int limiting = 0;
            for (int p = 0; p < solution.length; p++) {
                double power = (settings.limit - (solution[p] - source.power * response[p])) / response[p];
                if (power < minimum) {
                    minimum = power;
                    limiting = p;
                }
            }
            lines.add("headroom " + source.name + " max_power " + Report.real(minimum, 4) + " at " +
                      s.mesh.coordinates(limiting));
        }
        int materials = s.materials.size();
        int[][] count = new int[materials][materials];
        double[][] forward = new double[materials][materials], backward = new double[materials][materials];
        double gradient = -1;
        int first = 0, second = 0;
        for (int p = 0; p < solution.length; p++)
            for (int direction : new int[] {1, 3}) {
                Face face = s.faces[p][direction];
                int q = face.neighbor;
                if (q < 0)
                    continue;
                double value = Math.abs(solution[p] - solution[q]) / s.mesh.dx;
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
                    backward[a][b] += Math.abs(flow);
            }
        for (int i = 0; i < materials; i++)
            for (int j = i + 1; j < materials; j++)
                if (count[i][j] > 0)
                    lines.add("interface " + s.materials.get(i).code() + " " + s.materials.get(j).code() +
                              " faces " + count[i][j] + " forward " + Report.real(forward[i][j], 4) +
                              " backward " + Report.real(backward[i][j], 4));
        double totalFlow = 0, absoluteFlow = 0;
        for (Segment segment : s.segments) {
            double flow = segmentFlow(s, segment, solution);
            totalFlow += flow;
            absoluteFlow += Math.abs(flow);
            lines.add("segment " + segment.name() + " " + segment.edge() + " " + segment.kind() + " flow " +
                      Report.real(flow, 4));
        }
        lines.add("sources " + Report.real(s.power, 4));
        lines.add("balance " + verdict(Math.abs(totalFlow + s.power) <= 0.000001 * (absoluteFlow + s.power)));
        lines.add("max_gradient " + Report.real(gradient, 2) + " between " + s.mesh.coordinates(first) +
                  " and " + s.mesh.coordinates(second));
        for (Steady.Iteration result : iterative) {
            String prefix = "solver " + result.method;
            if (result.method.equals("sor") || result.method.equals("sor_estimated"))
                prefix += " omega " + Report.real(result.omega, 4);
            lines.add(prefix + " iterations " + result.changes.size() + " converged " +
                      (result.converged ? "yes" : "no") + " rate " + Report.real(result.rate, 6) +
                      " milestones " + String.join(" ", result.milestones));
        }
        return lines;
    }
    static List<String> snapshotLines(Thermal s, Params settings, List<Result> results) {
        List<String> lines = new ArrayList<>();
        for (Result result : results) {
            if (!result.status.equals("accepted")) {
                lines.add(rejected(result, s.maximumStep));
                continue;
            }
            for (int time : settings.snapshots) {
                double[] field = result.snapshots.get(time).field();
                String prefix = "run " + result.run.name() + " " + result.run.method() + " dt " +
                                Report.time(result.run.step()) + " time " + Report.time(time);
                lines.add(summary(prefix, s, field));
                lines.addAll(Report.field(s.mesh, field));
            }
        }
        return lines;
    }
    static List<String> probeLines(Params settings, List<Result> results) {
        List<String> lines = new ArrayList<>();
        lines.add("run,time,probe,temperature");
        for (Result result : results)
            if (result.status.equals("accepted"))
                for (Sample sample : result.samples)
                    for (int i = 0; i < settings.probes.size(); i++)
                        lines.add(result.run.name() + "," + Report.time(sample.time()) + "," +
                                  settings.probes.get(i).name() + "," + Report.real(sample.values()[i], 3));
        return lines;
    }
    static List<String> comparison(Thermal s, Params settings, List<Result> results, Result reference,
                                   List<double[]> solutions, double[] rhs, List<Steady.Iteration> iterative) {
        double[] solution = solutions.get(0);
        List<String> lines = new ArrayList<>();
        lines.add("ftcs_max_dt " + Report.real(s.maximumStep, 4));
        for (Result result : results) {
            if (!result.status.equals("accepted")) {
                lines.add(rejected(result, null));
                continue;
            }
            Run run = result.run;
            String name = run.name(), alarm = result.alarmTime < 0 ? "never"
                                                                   : Report.time(result.alarmTime) + " at " +
                                                                         s.mesh.coordinates(result.alarmCell);
            lines.add("run " + name + " " + run.method() + " dt " + Report.time(run.step()) + " steps " +
                      result.steps + " peak " + Report.real(result.peak, 2) + " time " +
                      Report.time(result.peakTime) + " at " + s.mesh.coordinates(result.peakCell) +
                      " alarm " + alarm + " above " + Report.time(result.above));
            lines.add("energy " + name + " stored " + Report.real(result.stored, 2) + " boundary " +
                      Report.real(result.boundary, 2) + " source " + Report.real(result.generated, 2) +
                      " balance " + verdict(result.balanced));
            for (int time : settings.snapshots) {
                Frame frame = result.snapshots.get(time);
                lines.add("energy_at " + name + " time " + Report.time(time) + " stored " +
                          Report.real(frame.stored(), 2) + " boundary " + Report.real(frame.boundary(), 2) +
                          " source " + Report.real(frame.generated(), 2));
            }
            for (int i = 0; i < s.materials.size(); i++)
                lines.add("energy_material " + name + " " + s.materials.get(i).code() + " " +
                          Report.real(stored(s, result.field, settings.initial, s.materialCells.get(i)), 2));
            for (int i = 0; i < s.segments.size(); i++)
                lines.add("energy_segment " + name + " " + s.segments.get(i).name() + " " +
                          Report.real(result.segmentEnergy[i], 2));
            for (int i = 0; i < settings.probes.size(); i++) {
                double maximum = result.samples.get(0).values()[i], minimum = maximum;
                int maximumTime = result.samples.get(0).time(), minimumTime = maximumTime;
                for (Sample sample : result.samples) {
                    double value = sample.values()[i];
                    if (value > maximum) {
                        maximum = value;
                        maximumTime = sample.time();
                    }
                    if (value < minimum) {
                        minimum = value;
                        minimumTime = sample.time();
                    }
                }
                lines.add("probe_summary " + name + " " + settings.probes.get(i).name() + " max " +
                          Report.real(maximum, 3) + " time " + Report.time(maximumTime) + " min " +
                          Report.real(minimum, 3) + " time " + Report.time(minimumTime));
            }
            if (result != reference)
                for (int time : settings.snapshots) {
                    double[] field = result.snapshots.get(time).field(),
                             other = reference.snapshots.get(time).field();
                    double squares = 0;
                    for (int p = 0; p < field.length; p++) {
                        double e = Math.abs(field[p] - other[p]);
                        squares += e * e;
                    }
                    lines.add("compare " + name + " " + reference.run.name() + " time " + Report.time(time) +
                              " max_diff " + Report.real(error(field, other), 6) + " rms_diff " +
                              Report.real(Math.sqrt(squares / field.length), 6));
                }
            lines.add("final " + name + " steady_max_diff " + Report.real(error(result.field, solution), 6));
        }
        lines.add("steady direct max_residual " + Report.real(Steady.residual(s, solution, rhs), 6));
        for (Steady.Iteration result : iterative)
            lines.add("steady " + result.method + " iterations " + result.changes.size() + " max_diff " +
                      Report.real(result.error, 6) + " max_residual " + Report.real(result.residual, 6));
        double rho = iterative.get(0).rate, omega = iterative.get(3).omega;
        lines.add("jacobi_spectral_radius " + Report.real(rho, 6) + " squared " + Report.real(rho * rho, 6));
        lines.add("omega_estimated " + Report.real(omega, 4));
        return lines;
    }
    static void map(List<String> lines, String prefix, Thermal s, double[] field, double[] bands) {
        Report.MapImage image = Report.isotherm(s.mesh, field, bands);
        List<String> counts = new ArrayList<>();
        for (int value : image.counts())
            counts.add(Integer.toString(value));
        lines.add(prefix + " counts " + String.join(" ", counts));
        lines.addAll(image.lines());
    }
    public static void main(String[] args) throws Exception {
        Mesh mesh = new Mesh();
        Params settings = readParams(mesh);
        Thermal system = new Thermal(mesh, Materials.read());
        List<double[]> vectors = new ArrayList<>();
        double[] rhs = new double[mesh.count];
        for (int p = 0; p < rhs.length; p++)
            rhs[p] = system.beta[p] + system.all[p];
        vectors.add(rhs);
        vectors.add(system.beta);
        for (Source source : system.sources) {
            double[] vector = new double[mesh.count];
            for (int p : source.cells)
                vector[p] = 1.0 / source.cells.size();
            vectors.add(vector);
        }
        List<double[]> solutions = Steady.direct(system, vectors);
        List<Steady.Iteration> iterative = iterations(system, settings, solutions.get(0), rhs);
        List<Result> results = new ArrayList<>();
        Result reference = null;
        for (Run run : settings.runs) {
            Result result = simulate(run, system, settings);
            results.add(result);
            if (run.name().equals(settings.reference))
                reference = result;
        }
        List<String> maps = new ArrayList<>();
        map(maps, "isotherms steady", system, solutions.get(0), settings.bands);
        for (int time : settings.snapshots)
            map(maps, "isotherms " + reference.run.name() + " time " + Report.time(time), system,
                reference.snapshots.get(time).field(), settings.bands);
        Report.write("snapshots.txt", snapshotLines(system, settings, results));
        Report.write("probes.csv", probeLines(settings, results));
        Report.write("steady_state.txt", steadyLines(system, settings, solutions, iterative));
        Report.write("solver_comparison.txt",
                     comparison(system, settings, results, reference, solutions, rhs, iterative));
        Report.write("isotherms.txt", maps);
    }
}
