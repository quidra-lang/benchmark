"""Track, compare filters, evaluate associations, and write five reports."""

import csv
from bisect import bisect_right
from math import exp, floor, sqrt
from pathlib import Path

from association import optimal_assignment
from evaluation import continuity, distance, ospa, real, squared_distance
from imm import IMM
from kalman import Kalman, smooth
from matrix import inverse, quadratic2, total


FILTERS = ("cv", "ca", "abg", "imm", "rts")


def read_inputs():
    measurements, times, truth, params = {}, {}, {}, {}
    with Path("input/measurements.csv").open(encoding="ascii", newline="") as source:
        rows = csv.reader(source)
        next(rows)
        for scan, time, x, y in rows:
            scan = int(scan)
            times[scan] = float(time)
            measurements.setdefault(scan, []).append((float(x), float(y)))
    with Path("input/truth.csv").open(encoding="ascii", newline="") as source:
        rows = csv.reader(source)
        next(rows)
        for target, scan, x, y in rows:
            truth.setdefault(int(target), {})[int(scan)] = (float(x), float(y))
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        name, *values = line.split()
        if name == "MODEL":
            params[name] = values[0]
        else:
            convert = int if name in ("CONFIRM", "DELETE", "PLOT_SIZE") else float
            params[name] = tuple(map(convert, values))
    return measurements, times, truth, params


def listed(keyword, items):
    values = " ".join(map(str, items))
    return keyword + " " + (values or "none")


def optional(value):
    return "-" if value is None else str(value)


def groups(items):
    result = []
    for scan, label in items:
        if result and result[-1][1] + 1 == scan and result[-1][2] == label:
            result[-1] = result[-1][0], scan, label
        else:
            result.append((scan, scan, label))
    return result


def path_length(positions):
    return total(distance(positions[index - 1], positions[index]) for index in range(1, len(positions)))


def rmse(errors):
    return sqrt(total(errors) / len(errors))


def filter_scores(values):
    best = min(FILTERS, key=lambda name: float(real(values[name])))
    return " ".join(f"{name} {real(values[name])}" for name in FILTERS) + f" best {best}"


def framed(rows):
    border = "+" + "-" * len(rows[0]) + "+"
    return [border, *("|" + "".join(row) + "|" for row in rows), border]


def write_lines(path, lines):
    text = "\n".join(lines) + ("\n" if lines else "")
    Path(path).write_text(text, encoding="ascii", newline="\n")


class Track:
    def __init__(self, number, scan, measurement, kalman):
        self.number = number
        self.birth = self.last_hit = scan
        self.confirmed = self.deleted = None
        self.status = "tentative"
        self.hits = 1
        self.consecutive_misses = 0
        self.observations = {scan: measurement}
        self.nis = {}
        self.kalman = kalman
        self.target = None
        self.primary_matches = {}


class Analysis:
    def __init__(self, measurements, times, truth, params):
        self.measurements, self.times = measurements, times
        self.truth, self.params = truth, params
        self.scans = max(measurements)
        self.targets = sorted(truth)
        self.primary = params["MODEL"].lower()
        self.tracks = []
        self.track_rows = ["track,scan,x,y,vx,vy,status"]
        self.association_log = []
        self.conflict_measurements = 0
        self.conflict_tracks = 0
        self.greedy_differences = 0

    def parameter(self, name):
        return self.params[name][0]

    def make_kalman(self, model, measurement):
        return Kalman(model, self.parameter("Q_" + model), self.parameter("SIGMA"),
                      self.parameter("INIT_VELOCITY_VARIANCE"),
                      self.parameter("INIT_ACCELERATION_VARIANCE"), measurement)

    def track_all_scans(self):
        required_hits, window = self.params["CONFIRM"]
        for scan in range(1, self.scans + 1):
            live = [track for track in self.tracks if track.status != "deleted"]
            measurements = self.measurements[scan]
            if scan > 1:
                interval = self.times[scan] - self.times[scan - 1]
                for track in live:
                    track.kalman.predict(interval)
            usable, innovations = {}, {}
            row_gates = [0] * len(live)
            column_gates = [0] * len(measurements)
            for row, track in enumerate(live):
                for column, measurement in enumerate(measurements):
                    innovation = track.kalman.innovation(measurement)
                    if innovation[3] <= self.parameter("GATE"):
                        usable[row, column] = innovation[3]
                        innovations[row, column] = innovation
                        row_gates[row] += 1
                        column_gates[column] += 1
            assigned = optimal_assignment(len(live), len(measurements), usable)
            greedy, used_rows, used_columns = [], set(), set()
            for row, column in sorted(usable, key=lambda pair: (
                usable[pair], live[pair[0]].number, pair[1])):
                if row not in used_rows and column not in used_columns:
                    greedy.append((row, column))
                    used_rows.add(row)
                    used_columns.add(column)
            greedy.sort()
            self.greedy_differences += assigned != greedy
            matches = dict(assigned)
            missed, confirmed, deleted = [], [], []
            for row, track in enumerate(live):
                if row in matches:
                    column = matches[row]
                    measurement = measurements[column]
                    track.kalman.update(measurement, innovations[row, column])
                    track.observations[scan] = measurement
                    track.nis[scan] = usable[row, column]
                    track.last_hit = scan
                    track.hits += 1
                    track.consecutive_misses = 0
                else:
                    track.observations[scan] = None
                    track.consecutive_misses += 1
                    missed.append(track.number)
                if track.status == "confirmed":
                    if track.consecutive_misses >= self.parameter("DELETE"):
                        track.status = "deleted"
                        track.deleted = scan
                        deleted.append(track.number)
                elif track.hits >= required_hits:
                    track.status = "confirmed"
                    track.confirmed = scan
                    confirmed.append(track.number)
                elif scan - track.birth + 1 >= window:
                    track.status = "deleted"
                    track.deleted = scan
                    deleted.append(track.number)
            used_columns = {column for _, column in assigned}
            new = []
            for column, measurement in enumerate(measurements):
                if column in used_columns:
                    continue
                track = Track(len(self.tracks) + 1, scan, measurement,
                              self.make_kalman(self.params["MODEL"], measurement))
                self.tracks.append(track)
                new.append((track, column))
            conflicts_m = sum(count >= 2 for count in column_gates)
            conflicts_t = sum(count >= 2 for count in row_gates)
            self.conflict_measurements += conflicts_m
            self.conflict_tracks += conflicts_t
            self.association_log.extend([
                f"scan {scan} tracks {len(live)} measurements {len(measurements)}",
                listed("gate", (f"{live[row].number}:{column + 1}={real(usable[row, column])}"
                                for row, column in sorted(usable))),
                listed("assign", (f"{live[row].number}:{column + 1}" for row, column in assigned)),
                listed("greedy", (f"{live[row].number}:{column + 1}" for row, column in greedy)),
                listed("missed", missed),
                listed("new", (f"{track.number}:{column + 1}" for track, column in new)),
                listed("confirmed", confirmed), listed("deleted", deleted),
                f"status tentative {sum(t.status == 'tentative' for t in self.tracks)} "
                f"confirmed {sum(t.status == 'confirmed' for t in self.tracks)}",
                f"conflicts measurements {conflicts_m} tracks {conflicts_t}",
            ])
            for track in live + [track for track, _ in new]:
                values = [str(track.number), str(scan), *map(real, track.kalman.x[:4]), track.status]
                self.track_rows.append(",".join(values))
        self.evaluated = [track for track in self.tracks if track.confirmed is not None]

    def abg_estimates(self, track):
        alpha, beta, gamma = self.params["ABG"]
        state = list(track.observations[track.birth]) + [0.0] * 4
        estimates = {}
        for scan in track.span:
            if scan > track.birth:
                interval = self.times[scan] - self.times[scan - 1]
                measurement = track.observations[scan]
                for axis in range(2):
                    position, velocity, acceleration = state[axis], state[axis + 2], state[axis + 4]
                    position = position + interval * velocity + interval * interval * acceleration / 2
                    velocity = velocity + interval * acceleration
                    if measurement is not None:
                        residual = measurement[axis] - position
                        position = position + alpha * residual
                        velocity = velocity + beta * residual / interval
                        acceleration = acceleration + 2 * gamma * residual / (interval * interval)
                    state[axis], state[axis + 2], state[axis + 4] = position, velocity, acceleration
            estimates[scan] = state[:4]
        return estimates

    def compare_filters(self):
        for track in self.evaluated:
            track.span = list(range(track.birth, track.last_hit + 1))
            track.estimates = {name: {} for name in FILTERS}
            track.model_logs = {}
            histories = {}
            for name in ("cv", "ca"):
                kalman = self.make_kalman(name.upper(), track.observations[track.birth])
                history, likelihood = [], 0.0
                for scan in track.span:
                    if scan > track.birth:
                        kalman.predict(self.times[scan] - self.times[scan - 1])
                        measurement = track.observations[scan]
                        if measurement is not None:
                            _, value, _ = kalman.update(measurement)
                            likelihood += value
                    track.estimates[name][scan] = kalman.x[:4]
                    history.append(kalman.snapshot())
                histories[name] = history
                track.model_logs[name] = likelihood
            track.estimates["abg"] = self.abg_estimates(track)
            primary_history = histories[self.primary]
            track.primary_covariances = {scan: state["P"] for scan, state in zip(track.span, primary_history)}
            track.estimates["rts"] = {scan: state[:4] for scan, state in zip(track.span, smooth(primary_history))}
            imm = IMM(self.params["IMM_Q"], self.params["IMM_TRANSITION"], self.params["IMM_INITIAL"],
                      self.parameter("SIGMA"), self.parameter("INIT_VELOCITY_VARIANCE"),
                      track.observations[track.birth])
            track.high = {}
            for scan in track.span:
                if scan > track.birth:
                    imm.step(self.times[scan] - self.times[scan - 1], track.observations[scan])
                track.estimates["imm"][scan] = imm.estimate()
                track.high[scan] = imm.probabilities[1]
            track.nis_values = [track.nis[scan] for scan in track.span if scan in track.nis]
            gap = longest = 0
            for scan in track.span:
                gap = gap + 1 if track.observations[scan] is None else 0
                longest = max(longest, gap)
            track.longest_gap = longest
            track.path = path_length([track.estimates["rts"][scan] for scan in track.span])

    def evaluate_scans(self):
        self.labels = {name: {target: {} for target in self.targets} for name in FILTERS}
        self.ospa_values = {name: [] for name in FILTERS}
        self.scan_sizes = []
        threshold = self.parameter("MATCH_DISTANCE")
        cutoff = self.parameter("OSPA_CUTOFF")
        for scan in range(1, self.scans + 1):
            tracks = [track for track in self.evaluated if track.birth <= scan <= track.last_hit]
            targets = [target for target in self.targets if scan in self.truth[target]]
            self.scan_sizes.append((len(targets), len(tracks)))
            true_positions = [self.truth[target][scan] for target in targets]
            for name in FILTERS:
                estimates = [track.estimates[name][scan] for track in tracks]
                usable = {}
                for row, estimate in enumerate(estimates):
                    for column, point in enumerate(true_positions):
                        value = distance(estimate, point)
                        if value <= threshold:
                            usable[row, column] = value
                pairs = optimal_assignment(len(tracks), len(targets), usable)
                for row, column in pairs:
                    track, target = tracks[row], targets[column]
                    self.labels[name][target][scan] = track.number
                    if name == self.primary:
                        track.primary_matches[scan] = target
                self.ospa_values[name].append(ospa(estimates, true_positions, cutoff))
        self.continuities = {name: {} for name in FILTERS}
        for name in FILTERS:
            for target in self.targets:
                labels = [self.labels[name][target].get(scan) for scan in sorted(self.truth[target])]
                self.continuities[name][target] = continuity(labels)

    def match_tracks(self):
        cutoff = self.parameter("OSPA_CUTOFF")
        usable, details = {}, {}
        for row, track in enumerate(self.evaluated):
            for column, target in enumerate(self.targets):
                positions = self.truth[target]
                common = sorted(set(track.span).intersection(positions))
                if not common:
                    continue
                distances = {scan: distance(track.estimates[self.primary][scan], positions[scan])
                             for scan in common}
                if not any(value < cutoff for value in distances.values()):
                    continue
                union = sorted(set(track.span).union(positions))
                cost = total(min(cutoff, distances[scan]) if scan in distances else cutoff
                             for scan in union) / len(union)
                usable[row, column] = cost
                details[row, column] = common
        self.matched_tracks = {}
        for row, column in optimal_assignment(len(self.evaluated), len(self.targets), usable):
            track, target = self.evaluated[row], self.targets[column]
            track.target = target
            track.common = details[row, column]
            track.mean_distance = usable[row, column]
            self.matched_tracks[target] = track

    def evaluate_errors(self):
        self.target_results = {}
        overall_position = {name: [] for name in FILTERS}
        overall_velocity = {name: [] for name in FILTERS}
        for target in self.targets:
            if target not in self.matched_tracks:
                continue
            track = self.matched_tracks[target]
            positions = self.truth[target]
            velocities = {}
            for scan in track.common:
                if scan - 1 in positions and scan + 1 in positions:
                    interval = self.times[scan + 1] - self.times[scan - 1]
                    velocities[scan] = tuple((positions[scan + 1][a] - positions[scan - 1][a]) / interval
                                             for a in range(2))
            position_rmse, velocity_rmse = {}, {}
            for name in FILTERS:
                position_errors = [squared_distance(track.estimates[name][scan], positions[scan])
                                   for scan in track.common]
                velocity_errors = [squared_distance(track.estimates[name][scan][2:4], velocities[scan])
                                   for scan in sorted(velocities)]
                position_rmse[name] = rmse(position_errors)
                velocity_rmse[name] = rmse(velocity_errors)
                overall_position[name].extend(position_errors)
                overall_velocity[name].extend(velocity_errors)
            nees = []
            for scan in track.common:
                estimate = track.estimates[self.primary][scan]
                error = [estimate[a] - positions[scan][a] for a in range(2)]
                covariance = [row[:2] for row in track.primary_covariances[scan][:2]]
                nees.append(quadratic2(error, inverse(covariance)))
            self.target_results[target] = {"track": track, "position": position_rmse,
                                           "velocity": velocity_rmse, "velocity_count": len(velocities),
                                           "nees": nees}
        self.overall_position = {name: rmse(overall_position[name]) for name in FILTERS}
        self.overall_velocity = {name: rmse(overall_velocity[name]) for name in FILTERS}

    def summary_section(self):
        return [
            "summary", f"scans {self.scans}",
            f"measurements {sum(len(values) for values in self.measurements.values())}",
            f"targets {len(self.targets)}", f"tracks_created {len(self.tracks)}",
            f"tracks_confirmed {len(self.evaluated)}",
            f"false_tracks {sum(not track.primary_matches for track in self.evaluated)}",
            f"missed_targets {len(self.targets) - len(self.matched_tracks)}",
            f"measurements_used {sum(track.hits for track in self.evaluated)}",
            f"conflict_measurements {self.conflict_measurements}",
            f"conflict_tracks {self.conflict_tracks}",
            f"greedy_differences {self.greedy_differences}",
        ]

    def targets_section(self):
        lines = ["targets"]
        for target in self.targets:
            scans = sorted(self.truth[target])
            length = path_length([self.truth[target][scan] for scan in scans])
            speed = length / (self.times[scans[-1]] - self.times[scans[0]])
            lines.append(f"target {target} first {scans[0]} last {scans[-1]} scans {len(scans)} "
                         f"path {real(length)} mean_speed {real(speed)}")
        return lines

    def tracks_section(self):
        lines = ["tracks"]
        bound = self.parameter("CONSISTENCY_BOUND")
        for track in self.evaluated:
            count = len(track.nis_values)
            mean_nis = total(track.nis_values) / count
            inside = sum(value <= bound for value in track.nis_values)
            lines.append(f"track {track.number} birth {track.birth} confirmed {track.confirmed} "
                         f"end {track.last_hit} deleted {optional(track.deleted)} hits {track.hits} "
                         f"misses {len(track.span) - track.hits} longest_gap {track.longest_gap} "
                         f"path {real(track.path)} nis {real(mean_nis)} nis_inside {inside}/{count}")
        return lines

    def matching_section(self):
        lines = ["matching"]
        for track in self.evaluated:
            line = f"track {track.number} target {optional(track.target)}"
            if track.target is not None:
                line += f" common {len(track.common)} mean_distance {real(track.mean_distance)}"
            line += f" matched_scans {len(track.primary_matches)} "
            segments = groups(sorted(track.primary_matches.items()))
            line += listed("segments", (f"{first}-{last}:{target}" for first, last, target in segments))
            lines.append(line)
        return lines

    def rmse_section(self):
        lines = ["rmse"]
        for target in self.targets:
            result = self.target_results.get(target)
            if result is None:
                lines.append(f"target {target} track -")
                continue
            track = result["track"]
            lines.append(f"target {target} track {track.number} common {len(track.common)} "
                         + filter_scores(result["position"]))
            lines.append(f"target {target} velocity {result['velocity_count']} "
                         + filter_scores(result["velocity"]))
        lines.append("overall position " + filter_scores(self.overall_position))
        lines.append("overall velocity " + filter_scores(self.overall_velocity))
        return lines

    def consistency_section(self):
        lines = ["consistency"]
        bound = self.parameter("CONSISTENCY_BOUND")
        for target in self.targets:
            result = self.target_results.get(target)
            if result is None:
                lines.append(f"target {target} track -")
                continue
            values = result["nees"]
            inside = sum(value <= bound for value in values)
            lines.append(f"target {target} track {result['track'].number} "
                         f"nees {real(total(values) / len(values))} inside {inside}/{len(values)}")
        values = [value for track in self.evaluated for value in track.nis_values]
        edges = self.params["NIS_EDGES"]
        observed = [0] * (len(edges) + 1)
        for value in values:
            observed[bisect_right(edges, value)] += 1
        expected = []
        lower = 0.0
        for upper in (*edges, None):
            upper_probability = 0.0 if upper is None else exp(-upper / 2)
            expected.append(len(values) * (exp(-lower / 2) - upper_probability))
            lower = upper
        lines.append(f"nis_histogram total {len(values)} observed " + " ".join(map(str, observed))
                     + " expected " + " ".join(map(real, expected)))
        return lines

    def models_section(self):
        lines = ["models"]
        for track in self.evaluated:
            cv, ca = track.model_logs["cv"], track.model_logs["ca"]
            better = "cv" if cv >= ca else "ca"
            lines.append(f"track {track.number} updates {len(track.nis_values)} "
                         f"cv {real(cv)} ca {real(ca)} better {better}")
        return lines

    def ospa_section(self):
        lines = [f"ospa cutoff {real(self.parameter('OSPA_CUTOFF'))} order 2",
                 "scan targets tracks cv ca abg imm rts"]
        for index, (targets, tracks) in enumerate(self.scan_sizes):
            values = " ".join(real(self.ospa_values[name][index]) for name in FILTERS)
            lines.append(f"{index + 1} {targets} {tracks} {values}")
        lines.append("mean " + " ".join(real(total(self.ospa_values[name]) / self.scans) for name in FILTERS))
        return lines

    def continuity_section(self):
        lines = ["continuity"]
        for name in FILTERS:
            values = self.continuities[name]
            totals = " ".join(f"{key} {sum(values[target][key] for target in self.targets)}"
                              for key in ("covered", "breaks", "swaps"))
            lines.append(f"{name} {totals}")
            for target in self.targets:
                result = values[target]
                lines.append(f"  target {target} scans {len(self.truth[target])} "
                             f"covered {result['covered']} breaks {result['breaks']} "
                             f"swaps {result['swaps']} delay {optional(result['delay'])}")
        return lines

    def imm_section(self):
        lines = ["imm"]
        for track in self.evaluated:
            mean = total(track.high[scan] for scan in track.span) / len(track.span)
            maximum_scan = max(track.span, key=track.high.__getitem__)
            high_scans = [scan for scan in track.span if track.high[scan] > 0.5]
            segments = groups((scan, True) for scan in high_scans)
            lines.append(f"track {track.number} mean_high {real(mean)} "
                         f"max_high {real(track.high[maximum_scan])} at {maximum_scan} "
                         f"high_scans {len(high_scans)} "
                         + listed("segments", (f"{first}-{last}" for first, last, _ in segments)))
        return lines

    def evaluation_lines(self):
        lines = []
        sections = (self.summary_section, self.targets_section, self.tracks_section,
                    self.matching_section, self.rmse_section, self.consistency_section,
                    self.models_section, self.ospa_section, self.continuity_section, self.imm_section)
        for section in sections:
            if lines:
                lines.append("")
            lines.extend(section())
        return lines

    def plot_cell(self, point):
        xmin, xmax = self.params["PLOT_X"]
        ymin, ymax = self.params["PLOT_Y"]
        width, height = self.params["PLOT_SIZE"]
        dx, dy = (xmax - xmin) / width, (ymax - ymin) / height
        column = floor((point[0] - xmin) / dx)
        row = floor((ymax - point[1]) / dy)
        return (row, column) if 0 <= column < width and 0 <= row < height else None

    def plot_lines(self):
        width, height = self.params["PLOT_SIZE"]
        xmin, xmax = self.params["PLOT_X"]
        ymin, ymax = self.params["PLOT_Y"]
        characters = {track.number: chr(ord("A") + index) if index < 26 else chr(ord("a") + index - 26)
                      for index, track in enumerate(self.evaluated)}
        trajectory = [[" "] * width for _ in range(height)]
        for target in self.targets:
            for scan in sorted(self.truth[target]):
                cell = self.plot_cell(self.truth[target][scan])
                if cell is not None:
                    trajectory[cell[0]][cell[1]] = "."
        for track in self.evaluated:
            for scan in track.span:
                cell = self.plot_cell(track.estimates["rts"][scan])
                if cell is not None:
                    trajectory[cell[0]][cell[1]] = characters[track.number]
        lines = [f"tracks x {real(xmin)} {real(xmax)} y {real(ymin)} {real(ymax)} size {width} {height}"]
        lines.extend(framed(trajectory))
        for track in self.evaluated:
            lines.append(f"{characters[track.number]} track {track.number} target {optional(track.target)}")
        counts = [[0] * width for _ in range(height)]
        for scan in range(1, self.scans + 1):
            for measurement in self.measurements[scan]:
                cell = self.plot_cell(measurement)
                if cell is not None:
                    counts[cell[0]][cell[1]] += 1
        density = [[" " if count == 0 else str(count) if count < 10 else "#" for count in row]
                   for row in counts]
        lines.extend(("", "measurements"))
        lines.extend(framed(density))
        lines.extend(("", "timeline"))
        for target in self.targets:
            timeline = []
            labels = self.labels[self.primary][target]
            for scan in range(1, self.scans + 1):
                if scan not in self.truth[target]:
                    timeline.append(" ")
                elif scan not in labels:
                    timeline.append(".")
                else:
                    timeline.append(characters[labels[scan]])
            lines.append(f"{target} |{''.join(timeline)}|")
        cutoff = self.parameter("OSPA_CUTOFF")
        heights = [floor(10 * value / cutoff) for value in self.ospa_values[self.primary]]
        bars = [["#" if value >= 10 - row else " " for value in heights] for row in range(10)]
        lines.extend(("", f"ospa {self.primary}"))
        lines.extend(framed(bars))
        return lines

    def write(self):
        output = Path("output")
        output.mkdir(parents=True, exist_ok=True)
        smoothed = ["track,scan,x,y,vx,vy"]
        for track in self.evaluated:
            for scan in track.span:
                values = [str(track.number), str(scan), *map(real, track.estimates["rts"][scan])]
                smoothed.append(",".join(values))
        write_lines(output / "tracks.csv", self.track_rows)
        write_lines(output / "smoothed.csv", smoothed)
        write_lines(output / "association_log.txt", self.association_log)
        write_lines(output / "evaluation.txt", self.evaluation_lines())
        write_lines(output / "track_plot.txt", self.plot_lines())


def main():
    analysis = Analysis(*read_inputs())
    analysis.track_all_scans()
    analysis.compare_filters()
    analysis.evaluate_scans()
    analysis.match_tracks()
    analysis.evaluate_errors()
    analysis.write()


if __name__ == "__main__":
    main()
