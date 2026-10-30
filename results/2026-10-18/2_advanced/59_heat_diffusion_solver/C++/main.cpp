#include "heat.hpp"
static void boundary(System &system) {
    std::ifstream input("input/boundary.txt");
    std::string text;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string kind;
        row >> kind;
        if (kind == "segment") {
            Segment segment;
            int start, end;
            row >> segment.name >> segment.edge >> start >> end >> segment.kind;
            if (segment.kind == "fixed")
                row >> segment.theta;
            else if (segment.kind == "convective")
                row >> segment.coefficient >> segment.theta;
            segment.faces = system.mesh.segment_faces(segment.edge, start, end);
            system.segments.push_back(segment);
        } else {
            Source source;
            int r1, c1, r2, c2;
            row >> source.name >> r1 >> c1 >> r2 >> c2 >> source.power;
            source.cells = system.mesh.source_cells(r1, c1, r2, c2);
            int on, off;
            while (row >> on >> off)
                source.intervals.emplace_back(on, off);
            system.sources.push_back(source);
        }
    }
}
static Params parameters(const Mesh &mesh) {
    Params out;
    std::ifstream input("input/params.txt");
    std::string text;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "initial")
            row >> out.initial;
        else if (key == "end_time")
            row >> out.end;
        else if (key == "probe_every")
            row >> out.probe_every;
        else if (key == "tolerance")
            row >> out.tolerance;
        else if (key == "max_iterations")
            row >> out.max_iterations;
        else if (key == "omega")
            row >> out.omega;
        else if (key == "alarm")
            row >> out.alarm;
        else if (key == "limit")
            row >> out.limit;
        else if (key == "reference")
            row >> out.reference;
        else if (key == "snapshots") {
            int time;
            while (row >> time)
                out.snapshots.push_back(time);
        } else if (key == "bands") {
            double value;
            while (row >> value)
                out.bands.push_back(value);
        } else if (key == "probe") {
            Probe probe;
            int r, c;
            row >> probe.name >> r >> c;
            probe.point = mesh.cell(r, c);
            out.probes.push_back(probe);
        } else if (key == "run") {
            Run run;
            row >> run.name >> run.method >> run.step;
            out.runs.push_back(run);
        }
    }
    return out;
}
bool Source::operating(int time) const {
    for (const auto &[on, off] : intervals)
        if (on <= time && time < off)
            return true;
    return false;
}
double Source::duty(int end) const {
    int duration = 0;
    for (const auto &[on, off] : intervals)
        duration += std::min(off, end) - std::min(on, end);
    return double(duration) / end;
}
static std::pair<Field, double> source_terms(const System &system, std::optional<int> time = {}) {
    Field out(system.mesh.count);
    double power = 0;
    for (const Source &source : system.sources) {
        if (time && !source.operating(*time))
            continue;
        power += source.power;
        const double weight = source.power / double(source.cells.size());
        for (int p : source.cells)
            out[p] += weight;
    }
    return {out, power};
}
static System load_system() {
    System out;
    out.mesh = read_mesh();
    out.materials = read_materials();
    boundary(out);
    const Mesh &mesh = out.mesh;
    out.cell_material.resize(mesh.count);
    out.material_cells.resize(out.materials.size());
    out.capacity.resize(mesh.count);
    out.faces.resize(mesh.count);
    out.diagonal.resize(mesh.count);
    out.beta.resize(mesh.count);
    for (int p = 0; p < mesh.count; ++p) {
        int m = 0;
        while (out.materials[m].code != mesh.codes[p])
            ++m;
        out.cell_material[p] = m;
        out.material_cells[m].push_back(p);
        out.capacity[p] = capacity(out.materials[m], mesh.dx, mesh.thickness);
    }
    for (int p = 0; p < mesh.count; ++p)
        for (int direction = 0; direction < 4; ++direction) {
            Face &face = out.faces[p][direction];
            face.neighbor = mesh.neighbors[p][direction];
            if (face.neighbor >= 0)
                face.g =
                    interior(out.materials[out.cell_material[p]].k,
                             out.materials[out.cell_material[face.neighbor]].k, mesh.thickness);
        }
    for (const Segment &segment : out.segments)
        for (const auto &[p, direction] : segment.faces) {
            Face &face = out.faces[p][direction];
            const double k = out.materials[out.cell_material[p]].k;
            if (segment.kind == "fixed") {
                face.g = fixed(k, mesh.thickness);
                face.theta = segment.theta;
            } else if (segment.kind == "convective") {
                face.g = convective(k, segment.coefficient, mesh.dx, mesh.thickness);
                face.theta = segment.theta;
            }
        }
    out.dt_max = std::numeric_limits<double>::infinity();
    for (int p = 0; p < mesh.count; ++p) {
        for (const Face &face : out.faces[p]) {
            out.diagonal[p] += face.g;
            if (face.theta)
                out.beta[p] += face.g * *face.theta;
        }
        out.dt_max = std::min(out.dt_max, out.capacity[p] / out.diagonal[p]);
    }
    const auto terms = source_terms(out);
    out.source_all = terms.first;
    out.total_power = terms.second;
    return out;
}
static std::string status(const System &system, const Params &params, const Run &run) {
    Ids times = params.snapshots;
    times.push_back(params.end);
    times.push_back(params.probe_every);
    for (const Source &source : system.sources)
        for (const auto &[on, off] : source.intervals) {
            times.push_back(on);
            times.push_back(off);
        }
    for (int time : times)
        if (time % run.step != 0)
            return "step";
    if (run.method == "ftcs" && double(run.step) / 1000 > system.dt_max)
        return "unstable";
    return "accepted";
}
static double stored(const System &system, const Field &field, double initial, const Ids &cells) {
    double out = 0;
    for (int p : cells)
        out += system.capacity[p] * (field[p] - initial);
    return out;
}
static double segment_flow(const System &system, const Segment &segment, const Field &field) {
    double out = 0;
    if (segment.kind == "insulated")
        return out;
    for (const auto &[p, direction] : segment.faces) {
        const Face &face = system.faces[p][direction];
        out += face.g * (*face.theta - field[p]);
    }
    return out;
}
static double maximum_difference(const Field &first, const Field &second) {
    double out = 0;
    for (int p = 0; p < int(first.size()); ++p)
        out = std::max(out, std::abs(first[p] - second[p]));
    return out;
}
static std::string balance_verdict(double u, double b, double q) {
    return std::abs(u - b - q) <= 0.000001 * (std::abs(u) + std::abs(b) + std::abs(q)) ? "ok"
                                                                                       : "failed";
}
struct Snapshot {
    int time;
    Field field;
    double u, b, q;
};
struct ProbeRow {
    int time;
    Field values;
};
struct Result {
    Run run;
    std::string status;
    Field field, boundaries;
    double source_energy = 0, stored = 0, boundary_energy = 0, peak = 0;
    int peak_time = 0, peak_cell = 0, above = 0;
    std::optional<std::pair<int, int>> alarm;
    std::vector<Snapshot> snapshots;
    std::vector<ProbeRow> probes;
};
static Result transient_run(const System &system, const Params &params, Run definition) {
    Result out;
    out.run = definition;
    out.status = status(system, params, definition);
    if (out.status != "accepted")
        return out;
    const int n = system.mesh.count;
    out.field.assign(n, params.initial);
    out.boundaries.resize(system.segments.size());
    out.peak = params.initial;
    Ids cells(n);
    std::iota(cells.begin(), cells.end(), 0);
    const double dt = double(definition.step) / 1000;
    auto observe = [&](int time) {
        const int hot = hottest(out.field);
        const double maximum = out.field[hot];
        if (maximum > out.peak) {
            out.peak = maximum;
            out.peak_time = time;
            out.peak_cell = hot;
        }
        if (maximum >= params.alarm) {
            if (!out.alarm)
                out.alarm = std::make_pair(time, hot);
            if (time > 0)
                out.above += definition.step;
        }
        if (time % params.probe_every == 0) {
            ProbeRow row{time, {}};
            for (const Probe &probe : params.probes)
                row.values.push_back(out.field[probe.point]);
            out.probes.push_back(row);
        }
        if (std::find(params.snapshots.begin(), params.snapshots.end(), time) !=
            params.snapshots.end())
            out.snapshots.push_back(
                {time, out.field, stored(system, out.field, params.initial, cells),
                 std::accumulate(out.boundaries.begin(), out.boundaries.end(), 0.0),
                 out.source_energy});
    };
    observe(0);
    for (int time = 0; time < params.end; time += definition.step) {
        const auto [source, power] = source_terms(system, time);
        const Field previous = out.field;
        const Step update = advance(system, previous, source, dt, definition.method);
        Field average;
        if (definition.method == "crank_nicolson") {
            average.resize(n);
            for (int p = 0; p < n; ++p)
                average[p] = (previous[p] + update.field[p]) / 2;
        }
        for (int j = 0; j < int(system.segments.size()); ++j) {
            const Segment &segment = system.segments[j];
            const bool horizontal = segment.edge == "left" || segment.edge == "right";
            const Field &field = definition.method == "ftcs"             ? previous
                                 : horizontal                            ? update.intermediate
                                 : definition.method == "backward_euler" ? update.field
                                                                         : average;
            out.boundaries[j] += dt * segment_flow(system, segment, field);
        }
        out.source_energy += dt * power;
        out.field = update.field;
        observe(time + definition.step);
    }
    out.stored = stored(system, out.field, params.initial, cells);
    out.boundary_energy = std::accumulate(out.boundaries.begin(), out.boundaries.end(), 0.0);
    return out;
}
static double rate(const Iteration &solver) {
    const int k = int(solver.changes.size());
    return std::sqrt(solver.changes[k - 1] / solver.changes[k - 3]);
}
static std::string milestones(const Iteration &solver, double tolerance) {
    std::string out;
    for (int factor : {1000, 100, 10, 1}) {
        int found = 0;
        for (int i = 0; i < int(solver.changes.size()); ++i)
            if (solver.changes[i] < tolerance * factor) {
                found = i + 1;
                break;
            }
        out += " " + (found ? std::to_string(found) : "never");
    }
    return out;
}
int main() {
    const System system = load_system();
    const Mesh &mesh = system.mesh;
    const Params params = parameters(mesh);
    Field rhs(mesh.count);
    for (int p = 0; p < mesh.count; ++p)
        rhs[p] = system.beta[p] + system.source_all[p];
    std::vector<Field> right_hand_sides{rhs, system.beta};
    for (const Source &source : system.sources) {
        Field unit(mesh.count);
        for (int p : source.cells)
            unit[p] = 1.0 / double(source.cells.size());
        right_hand_sides.push_back(unit);
    }
    const std::vector<Field> solutions = direct(system, right_hand_sides);
    const Field &steady = solutions[0], &base = solutions[1];
    std::vector<Iteration> solvers;
    solvers.push_back(iterate(system, params, "jacobi"));
    const double rho = rate(solvers[0]), omega_opt = 2 / (1 + std::sqrt(1 - rho * rho));
    solvers.push_back(iterate(system, params, "gauss_seidel"));
    solvers.push_back(iterate(system, params, "sor", params.omega));
    solvers.push_back(iterate(system, params, "sor_estimated", omega_opt));
    std::vector<Result> results;
    int reference = 0;
    for (const Run &run : params.runs) {
        if (run.name == params.reference)
            reference = int(results.size());
        results.push_back(transient_run(system, params, run));
    }
    Lines snapshots, probes{"run,time,probe,temperature"}, comparison;
    line(comparison, "ftcs_max_dt ", real(system.dt_max, 4));
    for (const Result &result : results) {
        const Run &run = result.run;
        const std::string prefix =
            "run " + run.name + " " + run.method + " dt " + time_text(run.step);
        if (result.status != "accepted") {
            line(snapshots, prefix, " rejected ", result.status,
                 result.status == "unstable" ? " max_dt " + real(system.dt_max, 4) : "");
            line(comparison, prefix, " rejected ", result.status);
            continue;
        }
        for (const Snapshot &snapshot : result.snapshots) {
            snapshots.push_back(
                summary(prefix + " time " + time_text(snapshot.time), mesh, snapshot.field));
            field_lines(snapshots, mesh, snapshot.field);
        }
        for (const ProbeRow &row : result.probes)
            for (int i = 0; i < int(params.probes.size()); ++i)
                line(probes, run.name, ",", time_text(row.time), ",", params.probes[i].name, ",",
                     real(row.values[i], 3));
        const std::string alarm = result.alarm ? time_text(result.alarm->first) + " at " +
                                                     mesh.coordinates(result.alarm->second)
                                               : "never";
        line(comparison, prefix, " steps ", params.end / run.step, " peak ", real(result.peak, 2),
             " time ", time_text(result.peak_time), " at ", mesh.coordinates(result.peak_cell),
             " alarm ", alarm, " above ", time_text(result.above));
        line(comparison, "energy ", run.name, " stored ", real(result.stored, 2), " boundary ",
             real(result.boundary_energy, 2), " source ", real(result.source_energy, 2),
             " balance ",
             balance_verdict(result.stored, result.boundary_energy, result.source_energy));
        for (const Snapshot &snapshot : result.snapshots)
            line(comparison, "energy_at ", run.name, " time ", time_text(snapshot.time), " stored ",
                 real(snapshot.u, 2), " boundary ", real(snapshot.b, 2), " source ",
                 real(snapshot.q, 2));
        for (int m = 0; m < int(system.materials.size()); ++m)
            line(comparison, "energy_material ", run.name, " ", system.materials[m].code, " ",
                 real(stored(system, result.field, params.initial, system.material_cells[m]), 2));
        for (int j = 0; j < int(system.segments.size()); ++j)
            line(comparison, "energy_segment ", run.name, " ", system.segments[j].name, " ",
                 real(result.boundaries[j], 2));
        for (int probe = 0; probe < int(params.probes.size()); ++probe) {
            double maximum = result.probes[0].values[probe], minimum = maximum;
            int max_time = 0, min_time = 0;
            for (const ProbeRow &row : result.probes) {
                if (row.values[probe] > maximum) {
                    maximum = row.values[probe];
                    max_time = row.time;
                }
                if (row.values[probe] < minimum) {
                    minimum = row.values[probe];
                    min_time = row.time;
                }
            }
            line(comparison, "probe_summary ", run.name, " ", params.probes[probe].name, " max ",
                 real(maximum, 3), " time ", time_text(max_time), " min ", real(minimum, 3),
                 " time ", time_text(min_time));
        }
        if (run.name != params.reference)
            for (int i = 0; i < int(result.snapshots.size()); ++i) {
                const Field &field = result.snapshots[i].field,
                            &other = results[reference].snapshots[i].field;
                double squared = 0;
                for (int p = 0; p < mesh.count; ++p) {
                    const double difference = std::abs(field[p] - other[p]);
                    squared += difference * difference;
                }
                line(comparison, "compare ", run.name, " ", params.reference, " time ",
                     time_text(result.snapshots[i].time), " max_diff ",
                     real(maximum_difference(field, other), 6), " rms_diff ",
                     real(std::sqrt(squared / mesh.count), 6));
            }
        line(comparison, "final ", run.name, " steady_max_diff ",
             real(maximum_difference(result.field, steady), 6));
    }
    line(comparison, "steady direct max_residual ", real(residual(system, steady, rhs), 6));
    for (const Iteration &solver : solvers)
        line(comparison, "steady ", solver.method, " iterations ", solver.changes.size(),
             " max_diff ", real(maximum_difference(solver.field, steady), 6), " max_residual ",
             real(residual(system, solver.field, rhs), 6));
    line(comparison, "jacobi_spectral_radius ", real(rho, 6), " squared ", real(rho * rho, 6));
    line(comparison, "omega_estimated ", real(omega_opt, 4));
    Lines report;
    report.push_back(summary("steady", mesh, steady));
    field_lines(report, mesh, steady);
    for (int m = 0; m < int(system.materials.size()); ++m) {
        const Material &material = system.materials[m];
        const Ids &cells = system.material_cells[m];
        double minimum = steady[cells[0]], maximum = minimum, total = 0;
        for (int p : cells) {
            minimum = std::min(minimum, steady[p]);
            maximum = std::max(maximum, steady[p]);
            total += steady[p];
        }
        line(report, "material ", material.code, " ", material.name, " cells ", cells.size(),
             " min ", real(minimum, 2), " max ", real(maximum, 2), " mean ",
             real(total / double(cells.size()), 2));
    }
    for (const Source &source : system.sources) {
        double total = 0, maximum = steady[source.cells[0]];
        for (int p : source.cells) {
            total += steady[p];
            maximum = std::max(maximum, steady[p]);
        }
        line(report, "source ", source.name, " power ", real(source.power, 4), " duty ",
             real(source.duty(params.end), 4), " mean ",
             real(total / double(source.cells.size()), 2), " max ", real(maximum, 2));
    }
    for (const Source &source : system.sources)
        for (int j = 0; j < int(system.sources.size()); ++j) {
            double total = 0;
            for (int p : source.cells)
                total += solutions[j + 2][p];
            line(report, "influence ", source.name, " ", system.sources[j].name, " ",
                 real(total / double(source.cells.size()), 4));
        }
    Field superposition = base, duty = base;
    for (int p = 0; p < mesh.count; ++p)
        for (int j = 0; j < int(system.sources.size()); ++j) {
            const Source &source = system.sources[j];
            superposition[p] += source.power * solutions[j + 2][p];
            duty[p] += (source.duty(params.end) * source.power) * solutions[j + 2][p];
        }
    line(report, "superposition ",
         maximum_difference(superposition, steady) <= 0.000001 ? "ok" : "failed");
    for (int j = 0; j < int(system.sources.size()); ++j)
        for (const Segment &segment : system.segments) {
            double value = 0;
            if (segment.kind != "insulated")
                for (const auto &[p, direction] : segment.faces)
                    value += system.faces[p][direction].g * solutions[j + 2][p];
            line(report, "path ", system.sources[j].name, " ", segment.name, " ", real(value, 4));
        }
    report.push_back(summary("duty_steady", mesh, duty));
    for (int j = 0; j < int(system.sources.size()); ++j) {
        double minimum = std::numeric_limits<double>::infinity();
        int cell = 0;
        for (int p = 0; p < mesh.count; ++p) {
            const double value =
                (params.limit - (steady[p] - system.sources[j].power * solutions[j + 2][p])) /
                solutions[j + 2][p];
            if (value < minimum) {
                minimum = value;
                cell = p;
            }
        }
        line(report, "headroom ", system.sources[j].name, " max_power ", real(minimum, 4), " at ",
             mesh.coordinates(cell));
    }
    struct Interface {
        int faces = 0;
        double forward = 0, backward = 0;
    };
    const int material_count = int(system.materials.size());
    std::vector<std::vector<Interface>> interfaces(material_count,
                                                   std::vector<Interface>(material_count));
    double gradient = -1;
    int gradient_first = 0, gradient_second = 0;
    for (int p = 0; p < mesh.count; ++p)
        for (int direction : {1, 3}) {
            const Face &face = system.faces[p][direction];
            const int q = face.neighbor;
            if (q < 0)
                continue;
            const double value = std::abs(steady[p] - steady[q]) / mesh.dx;
            if (value > gradient) {
                gradient = value;
                gradient_first = p;
                gradient_second = q;
            }
            const int a = system.cell_material[p], b = system.cell_material[q];
            if (a == b)
                continue;
            const double flow = face.g * (steady[p] - steady[q]), oriented = a < b ? flow : -flow;
            Interface &entry = interfaces[std::min(a, b)][std::max(a, b)];
            ++entry.faces;
            if (oriented > 0)
                entry.forward += oriented;
            else if (oriented < 0)
                entry.backward += -oriented;
        }
    for (int a = 0; a < material_count; ++a)
        for (int b = a + 1; b < material_count; ++b) {
            const Interface &entry = interfaces[a][b];
            if (entry.faces)
                line(report, "interface ", system.materials[a].code, " ", system.materials[b].code,
                     " faces ", entry.faces, " forward ", real(entry.forward, 4), " backward ",
                     real(entry.backward, 4));
        }
    double total_flow = 0, absolute_flow = 0;
    for (const Segment &segment : system.segments) {
        const double flow = segment_flow(system, segment, steady);
        total_flow += flow;
        absolute_flow += std::abs(flow);
        line(report, "segment ", segment.name, " ", segment.edge, " ", segment.kind, " flow ",
             real(flow, 4));
    }
    line(report, "sources ", real(system.total_power, 4));
    line(report, "balance ",
         std::abs(total_flow + system.total_power) <=
                 0.000001 * (absolute_flow + system.total_power)
             ? "ok"
             : "failed");
    line(report, "max_gradient ", real(gradient, 2), " between ", mesh.coordinates(gradient_first),
         " and ", mesh.coordinates(gradient_second));
    for (const Iteration &solver : solvers)
        line(report, "solver ", solver.method,
             (solver.method == "sor" || solver.method == "sor_estimated")
                 ? " omega " + real(solver.omega, 4)
                 : "",
             " iterations ", solver.changes.size(), " converged ", solver.converged ? "yes" : "no",
             " rate ", real(rate(solver), 6), " milestones", milestones(solver, params.tolerance));
    Lines maps;
    isotherms(maps, "isotherms steady", mesh, steady, params.bands);
    for (const Snapshot &snapshot : results[reference].snapshots)
        isotherms(maps, "isotherms " + params.reference + " time " + time_text(snapshot.time), mesh,
                  snapshot.field, params.bands);
    save("snapshots.txt", snapshots);
    save("probes.csv", probes);
    save("steady_state.txt", report);
    save("solver_comparison.txt", comparison);
    save("isotherms.txt", maps);
}
