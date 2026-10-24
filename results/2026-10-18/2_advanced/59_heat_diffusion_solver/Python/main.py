"""Simulate and analyze the finite-volume plate using the specified file formats."""

from math import sqrt
from pathlib import Path

import materials
import mesh
import report
import steady
import transient
from transient import ordered_sum


SOLVER_ORDER = ("jacobi", "gauss_seidel", "sor", "sor_estimated")
MILESTONE_FACTORS = (1000, 100, 10, 1)


class Segment:
    def __init__(self, name, edge, start, end, kind, values, plate):
        self.name = name
        self.edge = edge
        self.kind = kind
        self.faces = plate.segment_faces(edge, start, end)
        self.coefficient = None
        self.theta = None
        if kind == "fixed":
            self.theta = float(values[0])
        elif kind == "convective":
            self.coefficient = float(values[0])
            self.theta = float(values[1])


class Source:
    def __init__(self, name, cells, power, intervals):
        self.name = name
        self.cells = cells
        self.power = power
        self.intervals = intervals
        self.weight = power / len(cells)

    def operating(self, time):
        return any(start <= time < stop for start, stop in self.intervals)

    def duty_ratio(self, end_time):
        duration = 0
        for start, stop in self.intervals:
            duration += min(stop, end_time) - min(start, end_time)
        return duration / end_time


class Run:
    def __init__(self, name, method, step):
        self.name = name
        self.method = method
        self.step = step
        self.dt = step / 1000


class Face:
    def __init__(self, neighbor, conductance=0.0, outside=None):
        self.neighbor = neighbor
        self.g = conductance
        self.theta = outside


def read_boundary(plate):
    segments = []
    sources = []
    with Path("input/boundary.txt").open(encoding="ascii") as source:
        for line in source:
            fields = line.split()
            if fields[0] == "segment":
                segments.append(Segment(
                    fields[1], fields[2], int(fields[3]), int(fields[4]),
                    fields[5], fields[6:], plate,
                ))
            else:
                cells = plate.source_cells(*map(int, fields[2:6]))
                times = list(map(int, fields[7:]))
                intervals = list(zip(times[::2], times[1::2]))
                sources.append(Source(fields[1], cells, float(fields[6]), intervals))
    return segments, sources


def read_parameters(plate):
    parameters = {"probes": [], "runs": []}
    integer_keys = {"end_time", "probe_every", "max_iterations"}
    real_keys = {"initial", "tolerance", "omega", "alarm", "limit"}
    with Path("input/params.txt").open(encoding="ascii") as source:
        for line in source:
            key, *values = line.split()
            if key in integer_keys:
                parameters[key] = int(values[0])
            elif key in real_keys:
                parameters[key] = float(values[0])
            elif key == "snapshots":
                parameters[key] = list(map(int, values))
            elif key == "bands":
                parameters[key] = list(map(float, values))
            elif key == "probe":
                point = plate.cell(int(values[1]), int(values[2]))
                parameters["probes"].append((values[0], point))
            elif key == "run":
                parameters["runs"].append(Run(values[0], values[1], int(values[2])))
            elif key == "reference":
                parameters[key] = values[0]
    return parameters


def source_terms(sources, cell_count, time=None):
    field = [0.0] * cell_count
    powers = []
    for source in sources:
        if time is not None and not source.operating(time):
            continue
        powers.append(source.power)
        for point in source.cells:
            field[point] += source.weight
    return field, ordered_sum(powers)


class PlateSystem:
    def __init__(self, plate, material_list, segments, sources):
        self.mesh = plate
        self.materials = material_list
        self.segments = segments
        self.sources = sources
        material_numbers = {material.code: index for index, material in enumerate(material_list)}
        self.cell_material = [material_numbers[code] for code in plate.codes]
        self.material_cells = [[] for material in material_list]
        for point, index in enumerate(self.cell_material):
            self.material_cells[index].append(point)
        cell_materials = [material_list[index] for index in self.cell_material]
        self.capacity = [
            materials.heat_capacity(material, plate.dx, plate.thickness)
            for material in cell_materials
        ]
        self.faces = []
        for point, neighbors in enumerate(plate.neighbors):
            faces = []
            for neighbor in neighbors:
                conductance = 0.0
                if neighbor >= 0:
                    conductance = materials.interior_conductance(
                        cell_materials[point].k, cell_materials[neighbor].k, plate.thickness
                    )
                faces.append(Face(neighbor, conductance))
            self.faces.append(faces)
        for segment in segments:
            for point, direction in segment.faces:
                face = self.faces[point][direction]
                conductivity = cell_materials[point].k
                if segment.kind == "fixed":
                    face.g = materials.fixed_conductance(conductivity, plate.thickness)
                elif segment.kind == "convective":
                    face.g = materials.convective_conductance(
                        conductivity, segment.coefficient, plate.dx, plate.thickness
                    )
                face.theta = segment.theta
        self.diagonal = [ordered_sum(face.g for face in faces) for faces in self.faces]
        self.beta = [
            ordered_sum(face.g * face.theta for face in faces if face.theta is not None)
            for faces in self.faces
        ]
        self.source_all, self.total_power = source_terms(sources, plate.count)
        self.dt_max = min(
            capacity / diagonal for capacity, diagonal in zip(self.capacity, self.diagonal)
        )


def run_status(run, system, parameters):
    times = [parameters["end_time"], parameters["probe_every"]]
    times.extend(parameters["snapshots"])
    for source in system.sources:
        for start, stop in source.intervals:
            times.extend((start, stop))
    if any(time % run.step != 0 for time in times):
        return "step"
    if run.method == "ftcs" and run.dt > system.dt_max:
        return "unstable"
    return "accepted"


def hottest_cell(field):
    return max(range(len(field)), key=field.__getitem__)


def cell_text(plate, point):
    row, column = plate.coordinates(point)
    return f"{row} {column}"


def field_summary(prefix, plate, field):
    hottest = hottest_cell(field)
    mean = ordered_sum(field) / plate.count
    return (
        f"{prefix} max {report.real(field[hottest], 2)} at {cell_text(plate, hottest)} "
        f"min {report.real(min(field), 2)} mean {report.real(mean, 2)}"
    )


def stored_heat(system, field, initial, cells=None):
    if cells is None:
        cells = range(system.mesh.count)
    return ordered_sum(
        system.capacity[point] * (field[point] - initial) for point in cells
    )


def segment_flow(system, segment, field):
    if segment.kind == "insulated":
        return 0.0
    return ordered_sum(
        system.faces[point][direction].g
        * (system.faces[point][direction].theta - field[point])
        for point, direction in segment.faces
    )


def step_boundary_energy(system, segment, run, previous, updated, intermediate):
    if segment.kind == "insulated":
        return 0.0
    terms = []
    for point, direction in segment.faces:
        face = system.faces[point][direction]
        if run.method == "ftcs":
            temperature = previous[point]
        elif segment.edge in ("left", "right"):
            temperature = intermediate[point]
        elif run.method == "backward_euler":
            temperature = updated[point]
        else:
            temperature = (previous[point] + updated[point]) / 2
        terms.append(face.g * (face.theta - temperature))
    return run.dt * ordered_sum(terms)


class RunResult:
    def __init__(self, run, status):
        self.run = run
        self.status = status
        self.snapshots = {}
        self.probe_samples = []
        self.segment_energy = []
        self.generated = 0.0
        self.peak = None
        self.alarm = None
        self.above = 0

    def observe(self, system, parameters, time, field):
        hottest = hottest_cell(field)
        temperature = field[hottest]
        if self.peak is None or temperature > self.peak[0]:
            self.peak = temperature, time, hottest
        if temperature >= parameters["alarm"]:
            if self.alarm is None:
                self.alarm = time, hottest
            if time > 0:
                self.above += self.run.step
        if time % parameters["probe_every"] == 0:
            readings = [field[point] for name, point in parameters["probes"]]
            self.probe_samples.append((time, readings))
        if time in parameters["snapshots"]:
            self.snapshots[time] = {
                "field": field.copy(),
                "stored": stored_heat(system, field, parameters["initial"]),
                "boundary": ordered_sum(self.segment_energy),
                "source": self.generated,
            }


def simulate_run(run, system, parameters):
    result = RunResult(run, "accepted")
    result.steps = parameters["end_time"] // run.step
    result.segment_energy = [0.0] * len(system.segments)
    field = [parameters["initial"]] * system.mesh.count
    result.observe(system, parameters, 0, field)
    for step in range(result.steps):
        time = step * run.step
        sources, power = source_terms(system.sources, system.mesh.count, time)
        updated, intermediate = transient.advance(run.method, system, field, sources, run.dt)
        for index, segment in enumerate(system.segments):
            result.segment_energy[index] += step_boundary_energy(
                system, segment, run, field, updated, intermediate
            )
        result.generated += run.dt * power
        field = updated
        result.observe(system, parameters, (step + 1) * run.step, field)
    result.final = field
    result.stored = stored_heat(system, field, parameters["initial"])
    result.boundary = ordered_sum(result.segment_energy)
    result.balance = (
        abs(result.stored - result.boundary - result.generated)
        <= 0.000001 * (abs(result.stored) + abs(result.boundary) + abs(result.generated))
    )
    return result


def solve_steady(system):
    right_hand_side = [
        boundary + source for boundary, source in zip(system.beta, system.source_all)
    ]
    vectors = [right_hand_side, system.beta]
    for source in system.sources:
        vector = [0.0] * system.mesh.count
        value = 1 / len(source.cells)
        for point in source.cells:
            vector[point] = value
        vectors.append(vector)
    fields = steady.band_solve(system, vectors)
    return right_hand_side, fields[0], fields[1], fields[2:]


def run_iterative_methods(system, parameters, solution, right_hand_side):
    results = []
    jacobi = steady.iterate(
        system, parameters["initial"], parameters["tolerance"],
        parameters["max_iterations"], "jacobi",
    )
    results.append(jacobi)
    rho = sqrt(jacobi["changes"][-1] / jacobi["changes"][-3])
    omega_opt = 2 / (1 + sqrt(1 - rho * rho))
    for method in SOLVER_ORDER[1:]:
        omega = omega_opt if method == "sor_estimated" else parameters["omega"]
        results.append(steady.iterate(
            system, parameters["initial"], parameters["tolerance"],
            parameters["max_iterations"], method, omega,
        ))
    for result in results:
        changes = result["changes"]
        result["rate"] = sqrt(changes[-1] / changes[-3])
        milestones = []
        for factor in MILESTONE_FACTORS:
            milestone = "never"
            for iteration, change in enumerate(changes, 1):
                if change < parameters["tolerance"] * factor:
                    milestone = str(iteration)
                    break
            milestones.append(milestone)
        result["milestones"] = milestones
        result["error"] = max(
            abs(value - reference) for value, reference in zip(result["field"], solution)
        )
        result["residual"] = steady.maximum_residual(system, result["field"], right_hand_side)
    return results, rho, omega_opt


def material_lines(system, solution):
    lines = []
    for material, cells in zip(system.materials, system.material_cells):
        temperatures = [solution[point] for point in cells]
        mean = ordered_sum(temperatures) / len(cells)
        lines.append(
            f"material {material.code} {material.name} cells {len(cells)} "
            f"min {report.real(min(temperatures), 2)} max {report.real(max(temperatures), 2)} "
            f"mean {report.real(mean, 2)}"
        )
    return lines


def source_lines(system, parameters, solution, responses):
    lines = []
    duties = [source.duty_ratio(parameters["end_time"]) for source in system.sources]
    for source, duty in zip(system.sources, duties):
        temperatures = [solution[point] for point in source.cells]
        mean = ordered_sum(temperatures) / len(source.cells)
        lines.append(
            f"source {source.name} power {report.real(source.power, 4)} "
            f"duty {report.real(duty, 4)} mean {report.real(mean, 2)} "
            f"max {report.real(max(temperatures), 2)}"
        )
    for source in system.sources:
        for contributor, response in zip(system.sources, responses):
            coefficient = ordered_sum(response[point] for point in source.cells) / len(source.cells)
            lines.append(f"influence {source.name} {contributor.name} {report.real(coefficient, 4)}")
    return lines, duties


def superposition_check(system, solution, base, responses):
    maximum = 0.0
    for point in range(system.mesh.count):
        temperature = base[point]
        for source, response in zip(system.sources, responses):
            temperature += source.power * response[point]
        maximum = max(maximum, abs(temperature - solution[point]))
    return maximum <= 0.000001


def escape_path_lines(system, responses):
    lines = []
    for source, response in zip(system.sources, responses):
        for segment in system.segments:
            value = 0.0
            if segment.kind != "insulated":
                value = ordered_sum(
                    system.faces[point][direction].g * response[point]
                    for point, direction in segment.faces
                )
            lines.append(f"path {source.name} {segment.name} {report.real(value, 4)}")
    return lines


def duty_field(system, base, responses, duties):
    field = []
    for point in range(system.mesh.count):
        temperature = base[point]
        for source, response, duty in zip(system.sources, responses, duties):
            temperature += (duty * source.power) * response[point]
        field.append(temperature)
    return field


def headroom_lines(system, parameters, solution, responses):
    lines = []
    for source, response in zip(system.sources, responses):
        limiting_cell = 0
        minimum = None
        for point in range(system.mesh.count):
            power = (parameters["limit"] - (solution[point] - source.power * response[point])) / response[point]
            if minimum is None or power < minimum:
                minimum = power
                limiting_cell = point
        lines.append(
            f"headroom {source.name} max_power {report.real(minimum, 4)} "
            f"at {cell_text(system.mesh, limiting_cell)}"
        )
    return lines


def interface_lines(system, solution):
    pairs = {}
    for point, faces in enumerate(system.faces):
        for direction in (mesh.RIGHT, mesh.BOTTOM):
            face = faces[direction]
            if face.neighbor < 0:
                continue
            first = system.cell_material[point]
            second = system.cell_material[face.neighbor]
            if first == second:
                continue
            flow = face.g * (solution[point] - solution[face.neighbor])
            if first > second:
                first, second = second, first
                flow = -flow
            values = pairs.setdefault((first, second), [0, 0.0, 0.0])
            values[0] += 1
            if flow > 0:
                values[1] += flow
            elif flow < 0:
                values[2] += abs(flow)
    lines = []
    for (first, second), (count, forward, backward) in sorted(pairs.items()):
        lines.append(
            f"interface {system.materials[first].code} {system.materials[second].code} "
            f"faces {count} forward {report.real(forward, 4)} backward {report.real(backward, 4)}"
        )
    return lines


def maximum_gradient(system, solution):
    maximum = -1.0
    selected = None
    for point, faces in enumerate(system.faces):
        for direction in (mesh.RIGHT, mesh.BOTTOM):
            neighbor = faces[direction].neighbor
            if neighbor >= 0:
                gradient = abs(solution[point] - solution[neighbor]) / system.mesh.dx
                if gradient > maximum:
                    maximum = gradient
                    selected = point, neighbor
    return maximum, selected


def solver_lines(results):
    lines = []
    for result in results:
        prefix = f"solver {result['method']}"
        if result["method"] in ("sor", "sor_estimated"):
            prefix += f" omega {report.real(result['omega'], 4)}"
        converged = "yes" if result["converged"] else "no"
        milestones = " ".join(result["milestones"])
        lines.append(
            f"{prefix} iterations {result['iterations']} converged {converged} "
            f"rate {report.real(result['rate'], 6)} milestones {milestones}"
        )
    return lines


def steady_state_lines(system, parameters, solution, base, responses, iterative):
    lines = [field_summary("steady", system.mesh, solution)]
    lines.extend(report.temperature_lines(system.mesh, solution))
    lines.extend(material_lines(system, solution))
    sources, duties = source_lines(system, parameters, solution, responses)
    lines.extend(sources)
    check = "ok" if superposition_check(system, solution, base, responses) else "failed"
    lines.append(f"superposition {check}")
    lines.extend(escape_path_lines(system, responses))
    average_field = duty_field(system, base, responses, duties)
    lines.append(field_summary("duty_steady", system.mesh, average_field))
    lines.extend(headroom_lines(system, parameters, solution, responses))
    lines.extend(interface_lines(system, solution))
    flows = []
    for segment in system.segments:
        flow = segment_flow(system, segment, solution)
        flows.append(flow)
        lines.append(
            f"segment {segment.name} {segment.edge} {segment.kind} flow {report.real(flow, 4)}"
        )
    lines.append(f"sources {report.real(system.total_power, 4)}")
    balanced = (
        abs(ordered_sum(flows) + system.total_power)
        <= 0.000001 * (ordered_sum(abs(flow) for flow in flows) + system.total_power)
    )
    lines.append(f"balance {'ok' if balanced else 'failed'}")
    gradient, (point, neighbor) = maximum_gradient(system, solution)
    lines.append(
        f"max_gradient {report.real(gradient, 2)} between {cell_text(system.mesh, point)} "
        f"and {cell_text(system.mesh, neighbor)}"
    )
    lines.extend(solver_lines(iterative))
    return lines


def rejected_run_line(result, maximum_step=None):
    run = result.run
    line = f"run {run.name} {run.method} dt {report.time(run.step)} rejected {result.status}"
    if result.status == "unstable" and maximum_step is not None:
        line += f" max_dt {report.real(maximum_step, 4)}"
    return line


def snapshot_lines(system, parameters, results):
    lines = []
    for result in results:
        if result.status != "accepted":
            lines.append(rejected_run_line(result, system.dt_max))
            continue
        run = result.run
        for time in parameters["snapshots"]:
            field = result.snapshots[time]["field"]
            prefix = (
                f"run {run.name} {run.method} dt {report.time(run.step)} time {report.time(time)}"
            )
            lines.append(field_summary(prefix, system.mesh, field))
            lines.extend(report.temperature_lines(system.mesh, field))
    return lines


def probe_lines(parameters, results):
    lines = ["run,time,probe,temperature"]
    for result in results:
        if result.status == "accepted":
            for time, temperatures in result.probe_samples:
                for (name, point), temperature in zip(parameters["probes"], temperatures):
                    lines.append(
                        f"{result.run.name},{report.time(time)},{name},{report.real(temperature, 3)}"
                    )
    return lines


def probe_summary_lines(parameters, result):
    lines = []
    for index, (name, point) in enumerate(parameters["probes"]):
        first_time, first_values = result.probe_samples[0]
        maximum = minimum = first_values[index]
        maximum_time = minimum_time = first_time
        for time, values in result.probe_samples[1:]:
            if values[index] > maximum:
                maximum = values[index]
                maximum_time = time
            if values[index] < minimum:
                minimum = values[index]
                minimum_time = time
        lines.append(
            f"probe_summary {result.run.name} {name} max {report.real(maximum, 3)} "
            f"time {report.time(maximum_time)} min {report.real(minimum, 3)} "
            f"time {report.time(minimum_time)}"
        )
    return lines


def energy_lines(system, parameters, result):
    name = result.run.name
    balance = "ok" if result.balance else "failed"
    lines = [
        f"energy {name} stored {report.real(result.stored, 2)} "
        f"boundary {report.real(result.boundary, 2)} source {report.real(result.generated, 2)} "
        f"balance {balance}"
    ]
    for time in parameters["snapshots"]:
        snapshot = result.snapshots[time]
        lines.append(
            f"energy_at {name} time {report.time(time)} stored {report.real(snapshot['stored'], 2)} "
            f"boundary {report.real(snapshot['boundary'], 2)} source {report.real(snapshot['source'], 2)}"
        )
    for material, cells in zip(system.materials, system.material_cells):
        value = stored_heat(system, result.final, parameters["initial"], cells)
        lines.append(f"energy_material {name} {material.code} {report.real(value, 2)}")
    for segment, value in zip(system.segments, result.segment_energy):
        lines.append(f"energy_segment {name} {segment.name} {report.real(value, 2)}")
    return lines


def reference_comparison_lines(system, parameters, result, reference):
    lines = []
    for time in parameters["snapshots"]:
        field = result.snapshots[time]["field"]
        reference_field = reference.snapshots[time]["field"]
        errors = [abs(value - other) for value, other in zip(field, reference_field)]
        rms = sqrt(ordered_sum(error * error for error in errors) / system.mesh.count)
        lines.append(
            f"compare {result.run.name} {reference.run.name} time {report.time(time)} "
            f"max_diff {report.real(max(errors), 6)} rms_diff {report.real(rms, 6)}"
        )
    return lines


def comparison_lines(system, parameters, results, reference, solution, rhs, iterative, rho, omega_opt):
    lines = [f"ftcs_max_dt {report.real(system.dt_max, 4)}"]
    for result in results:
        if result.status != "accepted":
            lines.append(rejected_run_line(result))
            continue
        run = result.run
        temperature, peak_time, peak_cell = result.peak
        alarm = "never"
        if result.alarm is not None:
            alarm_time, alarm_cell = result.alarm
            alarm = f"{report.time(alarm_time)} at {cell_text(system.mesh, alarm_cell)}"
        lines.append(
            f"run {run.name} {run.method} dt {report.time(run.step)} steps {result.steps} "
            f"peak {report.real(temperature, 2)} time {report.time(peak_time)} "
            f"at {cell_text(system.mesh, peak_cell)} alarm {alarm} above {report.time(result.above)}"
        )
        lines.extend(energy_lines(system, parameters, result))
        lines.extend(probe_summary_lines(parameters, result))
        if result is not reference:
            lines.extend(reference_comparison_lines(system, parameters, result, reference))
        difference = max(abs(value - other) for value, other in zip(result.final, solution))
        lines.append(f"final {run.name} steady_max_diff {report.real(difference, 6)}")
    residual = steady.maximum_residual(system, solution, rhs)
    lines.append(f"steady direct max_residual {report.real(residual, 6)}")
    for result in iterative:
        lines.append(
            f"steady {result['method']} iterations {result['iterations']} "
            f"max_diff {report.real(result['error'], 6)} max_residual {report.real(result['residual'], 6)}"
        )
    lines.append(f"jacobi_spectral_radius {report.real(rho, 6)} squared {report.real(rho * rho, 6)}")
    lines.append(f"omega_estimated {report.real(omega_opt, 4)}")
    return lines


def isotherm_output(system, parameters, solution, reference):
    counts, grid_lines = report.isotherm_lines(system.mesh, solution, parameters["bands"])
    lines = ["isotherms steady counts " + " ".join(map(str, counts))]
    lines.extend(grid_lines)
    for time in parameters["snapshots"]:
        field = reference.snapshots[time]["field"]
        counts, grid_lines = report.isotherm_lines(system.mesh, field, parameters["bands"])
        lines.append(
            f"isotherms {reference.run.name} time {report.time(time)} counts "
            + " ".join(map(str, counts))
        )
        lines.extend(grid_lines)
    return lines


def main():
    plate = mesh.read_plate()
    material_list = materials.read_materials()
    segments, sources = read_boundary(plate)
    parameters = read_parameters(plate)
    system = PlateSystem(plate, material_list, segments, sources)
    rhs, solution, base, responses = solve_steady(system)
    iterative, rho, omega_opt = run_iterative_methods(system, parameters, solution, rhs)
    results = []
    for run in parameters["runs"]:
        status = run_status(run, system, parameters)
        if status == "accepted":
            results.append(simulate_run(run, system, parameters))
        else:
            results.append(RunResult(run, status))
    reference = next(result for result in results if result.run.name == parameters["reference"])
    outputs = {
        "snapshots.txt": snapshot_lines(system, parameters, results),
        "probes.csv": probe_lines(parameters, results),
        "steady_state.txt": steady_state_lines(system, parameters, solution, base, responses, iterative),
        "solver_comparison.txt": comparison_lines(
            system, parameters, results, reference, solution, rhs, iterative, rho, omega_opt
        ),
        "isotherms.txt": isotherm_output(system, parameters, solution, reference),
    }
    for filename, lines in outputs.items():
        report.write_lines(filename, lines)


if __name__ == "__main__":
    main()
