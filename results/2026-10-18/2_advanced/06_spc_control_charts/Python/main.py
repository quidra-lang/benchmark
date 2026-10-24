from math import sqrt
import os

from attribute_charts import ATTRIBUTE_CHARTS, COUNT_CHARTS, CenterLine, LotPoint
from capability import Capability
from dataset import control_constants, read_attributes, read_measurements, read_settings
from plot import cusum_band, limits_band, standard_band, width_band
from run_rules import Signal, Zones, check_rules
from variable_charts import (
    Limits, i_mr_limits, moving_ranges, real_sum, subgroup_statistics,
    xbar_r_limits, xbar_s_limits,
)


INPUT_DIR = "input"
OUTPUT_DIR = "output"
CHART_ORDER = ("XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA")
SHEWHART_CHARTS = ("XBAR_R", "R", "XBAR_S", "S", "I", "MR")
RULE_ORDER = ("1", "2", "3", "4", "5", "6", "7", "8", "UPPER", "LOWER")
SIDE_RULES = ("UPPER", "LOWER")
LOCATION_CHARTS = ("XBAR_R", "XBAR_S", "I", "CUSUM", "EWMA", "MA")
SAMPLE_CHARTS = ("I", "MR")
MEAN_CHARTS = ("XBAR_R", "XBAR_S")
EVENT_TYPES = ("SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN")
STANDARD_PICTURES = ("P_STD", "NP_STD", "C_STD", "U_STD")
STANDARD_LIMITS = Limits(-3.0, 0.0, 3.0)
CHART_FAMILIES = {
    "XBAR_R": ("XBAR_R", 0),
    "R": ("XBAR_R", 1),
    "XBAR_S": ("XBAR_S", 0),
    "S": ("XBAR_S", 1),
    "I": ("I_MR", 0),
    "MR": ("I_MR", 1),
}


def real(value):
    text = f"{value:.4f}"
    return "0.0000" if text == "-0.0000" else text


def number_list(numbers):
    if not numbers:
        return "none"
    return " ".join(str(number) for number in sorted(numbers))


def limits_text(label, limits):
    return f"{label} lcl {real(limits.lcl)} cl {real(limits.cl)} ucl {real(limits.ucl)}"


def status_text(converged):
    return "converged" if converged else "stopped"


def zone_name(zones, value):
    if value > zones.ucl:
        return "OUT+"
    if value < zones.lcl:
        return "OUT-"
    if value > zones.u2:
        return "A+"
    if value > zones.u1:
        return "B+"
    if value > zones.cl:
        return "C+"
    if value < zones.l2:
        return "A-"
    if value < zones.l1:
        return "B-"
    if value < zones.cl:
        return "C-"
    return "C0"


class Family:
    def __init__(self, name, labels, charts):
        self.name = name
        self.labels = labels
        self.charts = charts

    def pair_text(self, limits):
        first, second = limits
        return f"{limits_text(self.labels[0], first)} {limits_text(self.labels[1], second)}"


FAMILIES = (
    Family("XBAR_R", ("XBAR", "R"), ("XBAR_R", "R")),
    Family("XBAR_S", ("XBAR", "S"), ("XBAR_S", "S")),
    Family("I_MR", ("I", "MR"), ("I", "MR")),
)


class Series:
    def __init__(self, numbers, values):
        self.numbers = numbers
        self.values = values


class EstimationPass:
    def __init__(self, points, limits, outliers):
        self.points = points
        self.limits = limits
        self.outliers = outliers


class FamilyEstimate:
    def __init__(self, family):
        self.family = family
        self.passes = []
        self.converged = False
        self.limits = None
        self.retained = []
        self.removed = []


class PatternCheck:
    def __init__(self, chart, points, signals):
        self.chart = chart
        self.points = points
        self.signals = signals


class Proposal:
    def __init__(self, family, points, limits):
        self.family = family
        self.points = points
        self.limits = limits


class CusumPoint:
    def __init__(self, subgroup, upper, lower):
        self.subgroup = subgroup
        self.upper = upper
        self.lower = lower


class BandPoint:
    def __init__(self, subgroup, value, width, center):
        self.subgroup = subgroup
        self.value = value
        self.width = width
        self.lcl = center - width
        self.ucl = center + width


class Event:
    def __init__(self, number, start):
        self.number = number
        self.start = start
        self.end = start
        self.signals = []
        self.location_up = 0
        self.location_down = 0
        self.spread_up = 0
        self.spread_down = 0
        self.pattern = 0
        self.kind = None
        self.onset = start
        self.shift = 0.0
        self.spread = 0.0
        self.out_of_spec = 0
        self.detection = []

    def length(self):
        return self.end - self.start + 1

    def contains(self, subgroup):
        return self.start <= subgroup <= self.end


class AttributePass:
    def __init__(self, lots, center, outliers):
        self.lots = lots
        self.center = center
        self.outliers = outliers


class AttributeChart:
    def __init__(self, chart):
        self.chart = chart
        self.passes = []
        self.converged = False
        self.retained = 0
        self.removed = []
        self.points = []
        self.signals = []


class CapabilityGroup:
    def __init__(self, name, subgroups, result):
        self.name = name
        self.subgroups = subgroups
        self.result = result


class RollingWindow:
    def __init__(self, first, last, result):
        self.first = first
        self.last = last
        self.result = result


class Analysis:
    def __init__(self, settings, values, lots):
        self.settings = settings
        self.values = values
        self.lots = lots
        self.size = settings.subgroup_size
        self.phase1 = settings.phase1_subgroups
        self.constants = control_constants(self.size)
        self.pair_constants = control_constants(2)
        self.subgroups = subgroup_statistics(values, self.size)
        self.estimates = {}
        self.pattern_checks = []
        self.mu0 = 0.0
        self.sigma = 0.0
        self.reference = 0.0
        self.interval = 0.0
        self.sbar = 0.0
        self.ewma_width = 0.0
        self.ma_width = 0.0
        self.signals = []
        self.cusum = []
        self.ewma = []
        self.moving_average = []
        self.events = []
        self.proposals = []
        self.attribute_charts = []
        self.capability_groups = []
        self.rolling = []

    def run(self):
        for family in FAMILIES:
            self.estimate_family(family)
        for family in FAMILIES:
            self.check_phase1(family)
        self.set_monitoring_parameters()
        for chart in SHEWHART_CHARTS:
            self.monitor_shewhart(chart)
        self.monitor_cusum()
        self.monitor_ewma()
        self.monitor_moving_average()
        self.sort_signals()
        self.build_events()
        self.propose_limits()
        for chart in ATTRIBUTE_CHARTS:
            self.estimate_attribute(chart)
        self.assess_capability()

    def phase2_subgroups(self):
        return self.subgroups[self.phase1:]

    def phase2_samples(self):
        return list(range(self.phase1 * self.size + 1, len(self.values) + 1))

    def samples_of(self, subgroup):
        return list(range((subgroup - 1) * self.size + 1, subgroup * self.size + 1))

    def signal_subgroup(self, signal):
        if signal.chart in SAMPLE_CHARTS:
            return (signal.end - 1) // self.size + 1
        return signal.end

    def has_signal(self, chart, end, rule=None):
        return any(
            signal.chart == chart and signal.end == end and (rule is None or signal.rule == rule)
            for signal in self.signals
        )

    def event_of(self, subgroup):
        for event in self.events:
            if event.contains(subgroup):
                return event
        return None

    def chart_limits(self, chart):
        family_name, index = CHART_FAMILIES[chart]
        return self.estimates[family_name].limits[index]

    def family_limits(self, family, numbers):
        if family.name == "I_MR":
            return i_mr_limits([self.values[t - 1] for t in numbers], self.pair_constants)
        chosen = [self.subgroups[i - 1] for i in numbers]
        if family.name == "XBAR_R":
            return xbar_r_limits(chosen, self.size, self.constants)
        return xbar_s_limits(chosen, self.size, self.constants)

    def family_series(self, family, numbers):
        if family.name == "I_MR":
            values = [self.values[t - 1] for t in numbers]
            return Series(numbers, values), Series(numbers[1:], moving_ranges(values))
        chosen = [self.subgroups[i - 1] for i in numbers]
        means = Series(numbers, [subgroup.mean for subgroup in chosen])
        if family.name == "XBAR_R":
            return means, Series(numbers, [subgroup.range for subgroup in chosen])
        return means, Series(numbers, [subgroup.sd for subgroup in chosen])

    def outliers(self, family, numbers, limits):
        found = set()
        for series, chart_limits in zip(self.family_series(family, numbers), limits):
            for number, value in zip(series.numbers, series.values):
                if chart_limits.outside(value):
                    found.add(number)
        return sorted(found)

    def estimate_family(self, family):
        if family.name == "I_MR":
            initial = list(range(1, self.phase1 * self.size + 1))
        else:
            initial = list(range(1, self.phase1 + 1))
        estimate = FamilyEstimate(family)
        points = initial
        for number in range(1, self.settings.max_passes + 1):
            limits = self.family_limits(family, points)
            outliers = self.outliers(family, points, limits)
            estimate.passes.append(EstimationPass(len(points), limits, outliers))
            estimate.limits = limits
            if not outliers:
                estimate.converged = True
                break
            if number == self.settings.max_passes:
                break
            removed = set(outliers)
            points = [point for point in points if point not in removed]
        retained = set(points)
        estimate.retained = points
        estimate.removed = [point for point in initial if point not in retained]
        self.estimates[family.name] = estimate

    def check_phase1(self, family):
        estimate = self.estimates[family.name]
        sequences = self.family_series(family, estimate.retained)
        for chart, series, limits in zip(family.charts, sequences, estimate.limits):
            signals = check_rules(
                chart, series.numbers, series.values, limits, self.settings.rules[chart]
            )
            self.pattern_checks.append(PatternCheck(chart, len(series.values), signals))

    def set_monitoring_parameters(self):
        means, ranges = self.estimates["XBAR_R"].limits
        self.mu0 = means.cl
        self.sigma = ranges.cl / self.constants.d2 / sqrt(self.size)
        self.reference = self.settings.cusum_k * self.sigma
        self.interval = self.settings.cusum_h * self.sigma
        self.sbar = self.estimates["XBAR_S"].limits[1].cl

    def phase2_series(self, chart):
        if chart in SAMPLE_CHARTS:
            samples = self.phase2_samples()
            if chart == "I":
                return Series(samples, [self.values[t - 1] for t in samples])
            return Series(samples, [abs(self.values[t - 1] - self.values[t - 2]) for t in samples])
        subgroups = self.phase2_subgroups()
        numbers = [subgroup.number for subgroup in subgroups]
        if chart in MEAN_CHARTS:
            return Series(numbers, [subgroup.mean for subgroup in subgroups])
        if chart == "R":
            return Series(numbers, [subgroup.range for subgroup in subgroups])
        return Series(numbers, [subgroup.sd for subgroup in subgroups])

    def monitor_shewhart(self, chart):
        series = self.phase2_series(chart)
        self.signals.extend(check_rules(
            chart, series.numbers, series.values, self.chart_limits(chart),
            self.settings.rules[chart],
        ))

    def monitor_cusum(self):
        upper = 0.0
        lower = 0.0
        upper_run = 0
        lower_run = 0
        for subgroup in self.phase2_subgroups():
            number = subgroup.number
            upper = max(0.0, upper + (subgroup.mean - self.mu0 - self.reference))
            lower = max(0.0, lower + (self.mu0 - subgroup.mean - self.reference))
            upper_run = upper_run + 1 if upper > 0 else 0
            lower_run = lower_run + 1 if lower > 0 else 0
            self.cusum.append(CusumPoint(number, upper, lower))
            if upper > self.interval:
                self.signals.append(
                    Signal("CUSUM", "UPPER", number - upper_run + 1, number, upper, "UP")
                )
                upper = 0.0
                upper_run = 0
            if lower > self.interval:
                self.signals.append(
                    Signal("CUSUM", "LOWER", number - lower_run + 1, number, lower, "DOWN")
                )
                lower = 0.0
                lower_run = 0

    def add_band_signal(self, chart, point, start):
        if point.value > point.ucl:
            self.signals.append(Signal(chart, "UPPER", start, point.subgroup, point.value, "UP"))
        elif point.value < point.lcl:
            self.signals.append(Signal(chart, "LOWER", start, point.subgroup, point.value, "DOWN"))

    def monitor_ewma(self):
        weight = self.settings.ewma_lambda
        spread = self.settings.ewma_l
        decay = (1 - weight) * (1 - weight)
        ratio = weight / (2 - weight)
        self.ewma_width = spread * self.sigma * sqrt(ratio)
        smoothed = self.mu0
        factor = 1.0
        for subgroup in self.phase2_subgroups():
            smoothed = weight * subgroup.mean + (1 - weight) * smoothed
            factor = factor * decay
            width = spread * self.sigma * sqrt(ratio * (1 - factor))
            point = BandPoint(subgroup.number, smoothed, width, self.mu0)
            self.ewma.append(point)
            self.add_band_signal("EWMA", point, subgroup.number)

    def monitor_moving_average(self):
        span = self.settings.ma_span
        self.ma_width = 3 * self.sigma / sqrt(span)
        for subgroup in self.phase2_subgroups():
            number = subgroup.number
            first = max(self.phase1 + 1, number - span + 1)
            count = number - first + 1
            total = sum(self.subgroups[i - 1].total for i in range(first, number + 1))
            width = 3 * self.sigma / sqrt(count)
            point = BandPoint(number, total / (self.size * count), width, self.mu0)
            self.moving_average.append(point)
            self.add_band_signal("MA", point, first)

    def sort_signals(self):
        self.signals.sort(key=lambda signal: (
            CHART_ORDER.index(signal.chart), signal.end, RULE_ORDER.index(signal.rule)
        ))

    def build_events(self):
        groups = sorted({self.signal_subgroup(signal) for signal in self.signals})
        for group in groups:
            if self.events and group - self.events[-1].end - 1 <= self.settings.event_gap:
                self.events[-1].end = group
            else:
                self.events.append(Event(len(self.events) + 1, group))
        for event in self.events:
            event.signals = [
                signal for signal in self.signals
                if event.contains(self.signal_subgroup(signal))
            ]
            self.characterize(event)

    def characterize(self, event):
        for signal in event.signals:
            if signal.direction == "NONE":
                event.pattern += 1
            elif signal.chart in LOCATION_CHARTS:
                if signal.direction == "UP":
                    event.location_up += 1
                else:
                    event.location_down += 1
            elif signal.direction == "UP":
                event.spread_up += 1
            else:
                event.spread_down += 1
        counts = [
            event.location_up, event.location_down, event.spread_up,
            event.spread_down, event.pattern,
        ]
        event.kind = EVENT_TYPES[counts.index(max(counts))]
        cusum_starts = [signal.start for signal in event.signals if signal.chart == "CUSUM"]
        if cusum_starts:
            event.onset = min(cusum_starts)
        covered = self.subgroups[event.start - 1:event.end]
        mean = sum(subgroup.total for subgroup in covered) / (self.size * event.length())
        event.shift = (mean - self.mu0) / self.sigma
        spread = real_sum(subgroup.sd for subgroup in covered) / event.length()
        event.spread = spread / self.sbar
        event.out_of_spec = sum(
            value < self.settings.lsl or value > self.settings.usl
            for subgroup in covered for value in subgroup.values
        )
        for chart in CHART_ORDER:
            groups = [
                self.signal_subgroup(signal) for signal in event.signals if signal.chart == chart
            ]
            event.detection.append(min(groups) if groups else None)

    def propose_limits(self):
        free = [
            subgroup.number for subgroup in self.phase2_subgroups()
            if self.event_of(subgroup.number) is None
        ]
        for family in FAMILIES:
            if family.name == "I_MR":
                added = [sample for subgroup in free for sample in self.samples_of(subgroup)]
            else:
                added = free
            points = self.estimates[family.name].retained + added
            limits = self.family_limits(family, points)
            self.proposals.append(Proposal(family, len(points), limits))

    def estimate_attribute(self, chart):
        result = AttributeChart(chart)
        lots = self.lots
        center = None
        for number in range(1, self.settings.max_passes + 1):
            center = CenterLine(chart, lots)
            outliers = [lot.number for lot in lots if LotPoint(lot, center).status != "ok"]
            result.passes.append(AttributePass(len(lots), center, outliers))
            if not outliers:
                result.converged = True
                break
            if number == self.settings.max_passes:
                break
            lots = [lot for lot in lots if lot.number not in outliers]
        retained = {lot.number for lot in lots}
        result.retained = len(lots)
        result.removed = [lot.number for lot in self.lots if lot.number not in retained]
        result.points = [LotPoint(lot, center) for lot in self.lots]
        result.signals = check_rules(
            chart, [lot.number for lot in self.lots], [point.z for point in result.points],
            STANDARD_LIMITS, self.settings.rules["STD"],
        )
        self.attribute_charts.append(result)

    def assess_capability(self):
        retained = [self.subgroups[i - 1] for i in self.estimates["XBAR_R"].retained]
        for name, subgroups in (("phase1", retained), ("phase2", self.phase2_subgroups())):
            result = Capability(subgroups, self.settings, self.constants)
            self.capability_groups.append(CapabilityGroup(name, subgroups, result))
        window = self.settings.rolling_window
        first = self.phase1 + 1
        while first + window - 1 <= len(self.subgroups):
            subgroups = self.subgroups[first - 1:first + window - 1]
            result = Capability(subgroups, self.settings, self.constants)
            self.rolling.append(RollingWindow(first, first + window - 1, result))
            first += self.settings.rolling_step

    def limits_lines(self):
        lines = [
            f"characteristic {self.settings.characteristic}",
            f"subgroup_size {self.size}",
            f"subgroups {len(self.subgroups)}",
            f"samples {len(self.values)}",
            f"phase1_subgroups {self.phase1}",
        ]
        for family in FAMILIES:
            estimate = self.estimates[family.name]
            lines.append(f"family {family.name}")
            for number, record in enumerate(estimate.passes, 1):
                lines.append(
                    f"pass {number} points {record.points} {family.pair_text(record.limits)} "
                    f"out {number_list(record.outliers)}"
                )
            lines.append(
                f"result {status_text(estimate.converged)} passes {len(estimate.passes)} "
                f"retained {len(estimate.retained)} removed {number_list(estimate.removed)}"
            )
        for check in self.pattern_checks:
            for signal in check.signals:
                lines.append(
                    f"phase1_signal {check.chart} {signal.rule} {signal.start} {signal.end} "
                    f"{real(signal.value)}"
                )
            lines.append(
                f"phase1_check {check.chart} points {check.points} signals {len(check.signals)}"
            )
        for proposal in self.proposals:
            lines.append(
                f"proposed {proposal.family.name} points {proposal.points} "
                f"{proposal.family.pair_text(proposal.limits)}"
            )
        target = f"target {real(self.mu0)} sigma {real(self.sigma)}"
        lines.append(f"cusum {target} k {real(self.reference)} h {real(self.interval)}")
        lines.append(
            f"ewma {target} lcl {real(self.mu0 - self.ewma_width)} "
            f"ucl {real(self.mu0 + self.ewma_width)}"
        )
        lines.append(
            f"ma {target} span {self.settings.ma_span} lcl {real(self.mu0 - self.ma_width)} "
            f"ucl {real(self.mu0 + self.ma_width)}"
        )
        for chart in CHART_ORDER:
            lines.append(self.phase2_summary(chart))
        return lines

    def phase2_summary(self, chart):
        signals = [signal for signal in self.signals if signal.chart == chart]
        if chart in SAMPLE_CHARTS:
            points = len(self.phase2_samples())
        else:
            points = len(self.phase2_subgroups())
        if chart in SHEWHART_CHARTS:
            rules = [str(rule) for rule in self.settings.rules[chart]]
        else:
            rules = SIDE_RULES
        ends = {signal.end for signal in signals}
        first = str(min(ends)) if ends else "none"
        counts = " ".join(
            f"{rule}:{sum(signal.rule == rule for signal in signals)}" for rule in rules
        )
        return (
            f"phase2 {chart} points {points} signals {len(signals)} signalled {len(ends)} "
            f"first {first} by_rule {counts}"
        )

    def signal_lines(self):
        lines = ["chart,rule,start,end,value,direction"]
        for signal in self.signals:
            lines.append(
                f"{signal.chart},{signal.rule},{signal.start},{signal.end},"
                f"{real(signal.value)},{signal.direction}"
            )
        return lines

    def event_lines(self):
        lines = [f"events {len(self.events)}"]
        for event in self.events:
            charts = ",".join(
                chart for chart, group in zip(CHART_ORDER, event.detection) if group is not None
            )
            lines.append(
                f"event {event.number} start {event.start} end {event.end} "
                f"length {event.length()} signals {len(event.signals)} charts {charts} "
                f"location_up {event.location_up} location_down {event.location_down} "
                f"spread_up {event.spread_up} spread_down {event.spread_down} "
                f"pattern {event.pattern} onset {event.onset} shift {real(event.shift)} "
                f"spread {real(event.spread)} out_of_spec {event.out_of_spec} type {event.kind}"
            )
            detection = " ".join(
                f"{chart}:{'-' if group is None else group}"
                for chart, group in zip(CHART_ORDER, event.detection)
            )
            lines.append(f"detection {event.number} {detection}")
        return lines

    def subgroup_lines(self):
        lines = ["subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"]
        estimate = self.estimates["XBAR_R"]
        zones = Zones(estimate.limits[0])
        removed = set(estimate.removed)
        for subgroup in self.subgroups:
            number = subgroup.number
            if number > self.phase1:
                index = number - self.phase1 - 1
                phase = "phase2"
                monitored = [
                    real(self.cusum[index].upper), real(self.cusum[index].lower),
                    real(self.ewma[index].value), real(self.moving_average[index].value),
                ]
            else:
                phase = "excluded" if number in removed else "phase1"
                monitored = ["-", "-", "-", "-"]
            count = sum(self.signal_subgroup(signal) == number for signal in self.signals)
            event = self.event_of(number)
            fields = [
                str(number), phase, real(subgroup.mean), zone_name(zones, subgroup.mean),
                str(subgroup.range), real(subgroup.sd), *monitored, str(count),
                "-" if event is None else str(event.number),
            ]
            lines.append(",".join(fields))
        return lines

    def attribute_lines(self):
        lines = []
        for result in self.attribute_charts:
            lines.append(f"chart {result.chart}")
            for number, record in enumerate(result.passes, 1):
                lines.append(
                    f"pass {number} lots {record.lots} center {real(record.center.value)} "
                    f"out {number_list(record.outliers)}"
                )
            lines.append(
                f"result {status_text(result.converged)} passes {len(result.passes)} "
                f"retained {result.retained} removed {number_list(result.removed)}"
            )
            for lot, point in zip(self.lots, result.points):
                if result.chart in COUNT_CHARTS:
                    value = str(point.value)
                else:
                    value = real(point.value)
                lines.append(
                    f"lot {lot.number} size {lot.inspected} value {value} lcl {real(point.lcl)} "
                    f"ucl {real(point.ucl)} z {real(point.z)} status {point.status}"
                )
            for signal in result.signals:
                lines.append(
                    f"signal {signal.rule} {signal.start} {signal.end} {real(signal.value)}"
                )
            lines.append(f"signals {len(result.signals)}")
        return lines

    def out_of_spec_lines(self, subgroups):
        lines = []
        for subgroup in subgroups:
            for position, value in enumerate(subgroup.values):
                if value < self.settings.lsl:
                    side = "low"
                elif value > self.settings.usl:
                    side = "high"
                else:
                    continue
                sample = (subgroup.number - 1) * self.size + position + 1
                lines.append(
                    f"out_of_spec sample {sample} subgroup {subgroup.number} "
                    f"value {value} side {side}"
                )
        return lines

    def capability_lines(self):
        lines = []
        for group in self.capability_groups:
            result = group.result
            lines.append(
                f"group {group.name} subgroups {len(group.subgroups)} values {result.count}"
            )
            measures = (
                ("mean", result.mean), ("sigma_within", result.sigma_within),
                ("sigma_sbar", result.sigma_sbar), ("sigma_overall", result.sigma_overall),
                ("cp", result.cp), ("cpu", result.cpu), ("cpl", result.cpl), ("cpk", result.cpk),
                ("pp", result.pp), ("ppu", result.ppu), ("ppl", result.ppl), ("ppk", result.ppk),
                ("cpm", result.cpm),
            )
            for name, value in measures:
                lines.append(f"{name} {real(value)}")
            for name, (lower, upper) in (
                ("cpk_ci", result.cpk_interval), ("ppk_ci", result.ppk_interval)
            ):
                lines.append(f"{name} {real(lower)} {real(upper)}")
            lines.append(f"below_lsl {result.below}")
            lines.append(f"above_usl {result.above}")
            lines.append(f"ppm {real(result.ppm)}")
            lines.extend(self.out_of_spec_lines(group.subgroups))
            lines.append(f"verdict {result.verdict}")
            for row in result.bins:
                parts = ["bin", str(row.lower), str(row.upper), str(row.frequency)]
                if row.length > 0:
                    parts.append("#" * row.length)
                parts.extend(row.marks)
                lines.append(" ".join(parts))
        for window in self.rolling:
            result = window.result
            lines.append(
                f"rolling {window.first} {window.last} mean {real(result.mean)} "
                f"sigma_within {real(result.sigma_within)} "
                f"sigma_overall {real(result.sigma_overall)} cpk {real(result.cpk)} "
                f"ppk {real(result.ppk)} verdict {result.verdict}"
            )
        return lines

    def limits_picture(self, name, chart, estimate, limits, values):
        lines = [limits_text(f"chart {name}", limits)]
        removed = set(estimate.removed)
        for subgroup, value in zip(self.subgroups, values):
            number = subgroup.number
            if number > self.phase1:
                mark = "2"
            elif number in removed:
                mark = "x"
            else:
                mark = "1"
            signalled = number > self.phase1 and self.has_signal(chart, number)
            band = limits_band(limits, value, signalled)
            lines.append(f"{number:3d} {mark} {band} {real(value)}")
        return lines

    def cusum_picture(self):
        lines = [f"chart CUSUM h {real(self.interval)}"]
        for point in self.cusum:
            band = cusum_band(
                point.upper, point.lower, self.interval,
                self.has_signal("CUSUM", point.subgroup, "UPPER"),
                self.has_signal("CUSUM", point.subgroup, "LOWER"),
            )
            lines.append(f"{point.subgroup:3d} {band} {real(point.upper)} {real(point.lower)}")
        return lines

    def band_picture(self, chart, points, scale):
        heading = Limits(self.mu0 - scale, self.mu0, self.mu0 + scale)
        lines = [limits_text(f"chart {chart}", heading)]
        for point in points:
            band = width_band(
                scale, point.width, point.value, self.mu0, self.has_signal(chart, point.subgroup)
            )
            values = f"{real(point.value)} {real(point.lcl)} {real(point.ucl)}"
            lines.append(f"{point.subgroup:3d} {band} {values}")
        return lines

    def standard_picture(self, name, result):
        lines = [limits_text(f"chart {name}", STANDARD_LIMITS)]
        for lot, point in zip(self.lots, result.points):
            band = standard_band(point.z, point.status == "ok")
            lines.append(f"{lot.number:3d} {band} {real(point.z)}")
        return lines

    def chart_lines(self):
        xbar_r = self.estimates["XBAR_R"]
        xbar_s = self.estimates["XBAR_S"]
        lines = []
        lines.extend(self.limits_picture(
            "XBAR", "XBAR_R", xbar_r, xbar_r.limits[0],
            [subgroup.mean for subgroup in self.subgroups],
        ))
        lines.extend(self.limits_picture(
            "R", "R", xbar_r, xbar_r.limits[1],
            [subgroup.range for subgroup in self.subgroups],
        ))
        lines.extend(self.limits_picture(
            "S", "S", xbar_s, xbar_s.limits[1],
            [subgroup.sd for subgroup in self.subgroups],
        ))
        lines.extend(self.cusum_picture())
        lines.extend(self.band_picture("EWMA", self.ewma, self.ewma_width))
        lines.extend(self.band_picture("MA", self.moving_average, self.ma_width))
        for name, result in zip(STANDARD_PICTURES, self.attribute_charts):
            lines.extend(self.standard_picture(name, result))
        return lines


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    settings = read_settings(os.path.join(INPUT_DIR, "spec.txt"))
    values = read_measurements(os.path.join(INPUT_DIR, "measurements.csv"))
    lots = read_attributes(os.path.join(INPUT_DIR, "attributes.csv"))
    analysis = Analysis(settings, values, lots)
    analysis.run()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("limits.txt", analysis.limits_lines())
    write_lines("signals.csv", analysis.signal_lines())
    write_lines("events.txt", analysis.event_lines())
    write_lines("subgroups.csv", analysis.subgroup_lines())
    write_lines("attribute_charts.txt", analysis.attribute_lines())
    write_lines("capability.txt", analysis.capability_lines())
    write_lines("charts.txt", analysis.chart_lines())


if __name__ == "__main__":
    main()
