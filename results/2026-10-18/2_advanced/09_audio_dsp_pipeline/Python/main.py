import operator
import os
import re

import dynamics
import effects
import filters
from analysis import count_clipped, crest_fraction, pitch_lag, rms, zero_crossings
from signals import (
    MAX_SAMPLE, MIN_SAMPLE, Signal, format_signal, impulse, noise, peak, rdiv, read_signals, step,
)


SIGNALS_PATH = "input/signals.txt"
PIPELINE_PATH = "input/pipeline.txt"
OUTPUT_DIR = "output"
MAX_LENGTH = 20000
VALUE_LIMIT = 10000000
EXPECT_LIMIT = 1000000000
COEFFICIENT_LIMIT = 65536
FULL_SCALE = 32768
SAMPLE_SPAN = 65536
EXCERPT_GROUP = 8
METER_WIDTH = 40
HISTOGRAM_WIDTH = 50
PITCH_WIDTH = 40
ANALYSIS_HEADER = "signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"
NAME_PATTERN = re.compile(r"[a-z][a-z0-9_]{0,15}")
INTEGER_PATTERN = re.compile(r"-?(0|[1-9][0-9]{0,9})")
ARGUMENT_KINDS = {
    "dst": "name", "var": "name", "src": "signal", "metric": "metric", "op": "operator",
}
ARITHMETIC = {"+": operator.add, "-": operator.sub, "*": operator.mul, "/": operator.floordiv}
COMPARISONS = {
    "eq": operator.eq, "ne": operator.ne, "lt": operator.lt,
    "le": operator.le, "gt": operator.gt, "ge": operator.ge,
}
OPERATORS = {"SET": ARITHMETIC, "EXPECT": COMPARISONS}
METRICS = {
    "samples": len, "peak": peak, "rms": rms, "sum": sum,
    "zero_crossings": zero_crossings, "clipped": count_clipped,
}


class CommandError(Exception):
    pass


class Argument:
    def __init__(self, name, low=None, high=None):
        self.name = name
        self.kind = ARGUMENT_KINDS.get(name, "integer")
        self.low = low
        self.high = high


class Command:
    def __init__(self, arguments, repeated=(), repeat_min=0, repeat_max=0):
        self.arguments = list(arguments)
        self.repeated = list(repeated)
        self.repeat_min = repeat_min
        self.repeat_max = repeat_max

    def accepts(self, count):
        extra = count - len(self.arguments)
        if not self.repeated:
            return extra == 0
        size = len(self.repeated)
        return extra % size == 0 and self.repeat_min * size <= extra <= self.repeat_max * size

    def argument_at(self, index):
        if index < len(self.arguments):
            return self.arguments[index]
        return self.repeated[(index - len(self.arguments)) % len(self.repeated)]


DST = Argument("dst")
SRC = Argument("src")
RATE = Argument("rate", 1000, 48000)
COUNT = Argument("count", 1, MAX_LENGTH)
NUMERATOR = Argument("num", -COEFFICIENT_LIMIT, COEFFICIENT_LIMIT)
DENOMINATOR = Argument("den", 1, COEFFICIENT_LIMIT)
ATTACK = Argument("attack", 1, FULL_SCALE)
RELEASE = Argument("release", 1, FULL_SCALE)
MIN_HZ = Argument("min_hz", 1, "rate div 2 - 1")
MAX_HZ = Argument("max_hz", "min_hz + 1", "rate div 2")
START = Argument("start", 0, "L - 1")
TEST_SIGNAL = [
    DST, RATE, COUNT, Argument("pos", 0, "count - 1"), Argument("amp", MIN_SAMPLE, MAX_SAMPLE),
]
BIQUAD_SECTION = [
    Argument(name, -COEFFICIENT_LIMIT, COEFFICIENT_LIMIT) for name in ("b0", "b1", "b2", "a1", "a2")
]

COMMANDS = {
    "SET": Command(
        [Argument("var"), Argument("value", -VALUE_LIMIT, VALUE_LIMIT)],
        [Argument("op"), Argument("operand", -VALUE_LIMIT, VALUE_LIMIT)], 0, 1,
    ),
    "IMPULSE": Command(TEST_SIGNAL),
    "STEP": Command(TEST_SIGNAL),
    "NOISE": Command([DST, RATE, COUNT, Argument("seed", 1, 2147483646)]),
    "GAIN": Command([DST, SRC, NUMERATOR, DENOMINATOR]),
    "MIX": Command(
        [DST, DENOMINATOR], [SRC, Argument("weight", -COEFFICIENT_LIMIT, COEFFICIENT_LIMIT)], 1, 8,
    ),
    "DELAY": Command([DST, SRC, Argument("samples", 0, MAX_LENGTH)]),
    "ECHO": Command([
        DST, SRC, Argument("delay", 1, MAX_LENGTH), NUMERATOR, DENOMINATOR,
        Argument("tail", 0, MAX_LENGTH),
    ]),
    "RESAMPLE": Command([DST, SRC, Argument("new_rate", 1000, 48000)]),
    "FADE": Command([DST, SRC, Argument("in", 0, "L"), Argument("out", 0, "L")]),
    "TRIM": Command([DST, SRC, START, Argument("count", 1, "L - start")]),
    "CONCAT": Command([DST], [SRC], 2, 8),
    "FIR": Command(
        [DST, SRC, Argument("divisor", 1, 1000000)], [Argument("tap", MIN_SAMPLE, MAX_SAMPLE)], 1, 64,
    ),
    "BIQUAD": Command([DST, SRC], BIQUAD_SECTION, 1, 4),
    "MOVAVG": Command([DST, SRC, Argument("width", 1, 1000)]),
    "DCBLOCK": Command([
        DST, SRC, Argument("num", 0, COEFFICIENT_LIMIT - 1),
        Argument("den", "num + 1", COEFFICIENT_LIMIT),
    ]),
    "NORMALIZE": Command([DST, SRC, Argument("target", 1, MAX_SAMPLE)]),
    "GATE": Command([DST, SRC, Argument("threshold", 1, FULL_SCALE), Argument("hold", 0, MAX_LENGTH)]),
    "ENVELOPE": Command([DST, SRC, ATTACK, RELEASE]),
    "COMPRESS": Command([
        DST, SRC, Argument("threshold", 1, MAX_SAMPLE), Argument("ratio_num", 1, 100),
        Argument("ratio_den", 1, "ratio_num"), ATTACK, RELEASE,
    ]),
    "ANALYZE": Command([SRC, MIN_HZ, MAX_HZ]),
    "COMPARE": Command([SRC, SRC]),
    "EXPECT": Command([
        SRC, Argument("metric"), Argument("op"), Argument("value", -EXPECT_LIMIT, EXPECT_LIMIT),
    ]),
    "SEGMENTS": Command([
        SRC, Argument("threshold", 1, FULL_SCALE), Argument("gap", 1, MAX_LENGTH),
        Argument("min_length", 1, MAX_LENGTH),
    ]),
    "ONSETS": Command([
        SRC, ATTACK, RELEASE, Argument("threshold", 1, MAX_SAMPLE), Argument("min_gap", 1, MAX_LENGTH),
    ]),
    "PITCHTRACK": Command([
        SRC, Argument("frame", 16, "L"), Argument("hop", 1, "frame"), MIN_HZ, MAX_HZ,
        Argument("threshold", 0, MAX_SAMPLE),
    ]),
    "EXCERPT": Command([SRC, START, Argument("count", 1, 1000)]),
    "PLOT": Command([
        SRC, START, Argument("count", 1, "L - start"), Argument("columns", 8, "min(120, count)"),
        Argument("half", 2, 20), ATTACK, RELEASE,
    ]),
    "METER": Command([SRC, Argument("block", 1, MAX_LENGTH)]),
    "HISTOGRAM": Command([SRC, Argument("bins", 2, 64)]),
    "TRACE": Command([SRC]),
    "SAVE": Command([SRC]),
}


def ceil_div(numerator, denominator):
    return -(-numerator // denominator)


def milliseconds(index, rate):
    return index * 1000 // rate


def two_decimals(hundredths):
    return f"{hundredths // 100}.{hundredths % 100:02d}"


def frequency_text(rate, lag):
    return two_decimals(rdiv(100 * rate, lag))


def lag_range(rate, min_hz, max_hz):
    return ceil_div(rate, max_hz), rate // min_hz


def resolve_bound(bound, known, source):
    if isinstance(bound, int):
        return bound
    if bound == "count - 1":
        return known["count"] - 1
    if bound == "min(120, count)":
        return min(120, known["count"])
    if bound == "min_hz + 1":
        return known["min_hz"] + 1
    if bound == "num + 1":
        return known["num"] + 1
    if bound == "L":
        return len(source.samples)
    if bound == "L - 1":
        return len(source.samples) - 1
    if bound == "L - start":
        return len(source.samples) - known["start"]
    if bound == "rate div 2":
        return source.rate // 2
    if bound == "rate div 2 - 1":
        return source.rate // 2 - 1
    return known[bound]


def require_same_rate(sources):
    if any(source.rate != sources[0].rate for source in sources):
        raise CommandError("rate mismatch")


def make_impulse(arguments):
    rate, count, position, amplitude = arguments
    return rate, impulse(count, position, amplitude), []


def make_step(arguments):
    rate, count, position, amplitude = arguments
    return rate, step(count, position, amplitude), []


def make_noise(arguments):
    rate, count, seed = arguments
    return rate, noise(count, seed), []


def make_gain(arguments):
    source, num, den = arguments
    samples, clipped = effects.gain(source.samples, num, den)
    return source.rate, samples, [("clipped", clipped)]


def make_mix(arguments):
    den = arguments[0]
    sources = arguments[1::2]
    weights = arguments[2::2]
    require_same_rate(sources)
    samples, clipped = effects.mix([source.samples for source in sources], weights, den)
    return sources[0].rate, samples, [("clipped", clipped)]


def make_delay(arguments):
    source, count = arguments
    if len(source.samples) + count > MAX_LENGTH:
        raise CommandError("result too long")
    return source.rate, effects.delay(source.samples, count), []


def make_echo(arguments):
    source, delay_length, num, den, tail = arguments
    if abs(num) >= den:
        raise CommandError("unstable feedback")
    if len(source.samples) + tail > MAX_LENGTH:
        raise CommandError("result too long")
    samples, clipped = effects.echo(source.samples, delay_length, num, den, tail)
    return source.rate, samples, [("clipped", clipped)]


def make_resample(arguments):
    source, new_rate = arguments
    if effects.resampled_length(len(source.samples), source.rate, new_rate) > MAX_LENGTH:
        raise CommandError("result too long")
    return new_rate, effects.resample(source.samples, source.rate, new_rate), []


def make_fade(arguments):
    source, fade_in, fade_out = arguments
    return source.rate, effects.fade(source.samples, fade_in, fade_out), []


def make_trim(arguments):
    source, start, count = arguments
    return source.rate, source.samples[start:start + count], []


def make_concat(arguments):
    require_same_rate(arguments)
    if sum(len(source.samples) for source in arguments) > MAX_LENGTH:
        raise CommandError("result too long")
    samples = []
    for source in arguments:
        samples.extend(source.samples)
    return arguments[0].rate, samples, []


def make_fir(arguments):
    source, divisor, *taps = arguments
    samples, clipped = filters.fir(source.samples, divisor, taps)
    return source.rate, samples, [("clipped", clipped)]


def make_biquad(arguments):
    source, *coefficients = arguments
    sections = [coefficients[i:i + 5] for i in range(0, len(coefficients), 5)]
    samples, clipped = filters.biquad(source.samples, sections)
    return source.rate, samples, [("sections", len(sections)), ("clipped", clipped)]


def make_movavg(arguments):
    source, width = arguments
    return source.rate, filters.moving_average(source.samples, width), []


def make_dcblock(arguments):
    source, num, den = arguments
    samples, clipped = filters.dc_block(source.samples, num, den)
    return source.rate, samples, [("clipped", clipped)]


def make_normalize(arguments):
    source, target = arguments
    samples, source_peak = dynamics.normalize(source.samples, target)
    return source.rate, samples, [("source_peak", source_peak)]


def make_gate(arguments):
    source, threshold, hold = arguments
    samples, muted = dynamics.gate(source.samples, threshold, hold)
    return source.rate, samples, [("muted", muted)]


def make_envelope(arguments):
    source, attack, release = arguments
    return source.rate, dynamics.envelope(source.samples, attack, release), []


def make_compress(arguments):
    source, threshold, ratio_num, ratio_den, attack, release = arguments
    samples, min_gain, reduced = dynamics.compress(
        source.samples, threshold, ratio_num, ratio_den, attack, release
    )
    return source.rate, samples, [("min_gain", min_gain), ("reduced", reduced)]


GENERATORS = {
    "IMPULSE": make_impulse,
    "STEP": make_step,
    "NOISE": make_noise,
    "GAIN": make_gain,
    "MIX": make_mix,
    "DELAY": make_delay,
    "ECHO": make_echo,
    "RESAMPLE": make_resample,
    "FADE": make_fade,
    "TRIM": make_trim,
    "CONCAT": make_concat,
    "FIR": make_fir,
    "BIQUAD": make_biquad,
    "MOVAVG": make_movavg,
    "DCBLOCK": make_dcblock,
    "NORMALIZE": make_normalize,
    "GATE": make_gate,
    "ENVELOPE": make_envelope,
    "COMPRESS": make_compress,
}


def plot_row(value, scale, rows):
    return rdiv((scale - value) * (rows - 1), 2 * scale)


def plot_label(row, half, scale):
    if row == 0:
        return str(scale)
    if row == half:
        return "0"
    if row == 2 * half:
        return str(-scale)
    return ""


def waveform_plot(source, start, count, columns, half, attack, release):
    window = source.samples[start:start + count]
    levels = dynamics.envelope(source.samples, attack, release)[start:start + count]
    rows = 2 * half + 1
    scale = max(1, peak(window))
    grid = [[" "] * columns for _ in range(rows)]
    for column in range(columns):
        first = column * count // columns
        last = (column + 1) * count // columns
        top = plot_row(max(window[first:last]), scale, rows)
        bottom = plot_row(min(window[first:last]), scale, rows)
        level = min(scale, max(levels[first:last]))
        marks = (plot_row(level, scale, rows), plot_row(-level, scale, rows))
        for row in range(rows):
            if row in marks:
                grid[row][column] = "*"
            elif top <= row <= bottom:
                grid[row][column] = "#"
            elif row == half:
                grid[row][column] = "-"
    lines = [
        f"PLOT {source.name} rate={source.rate} start={start} count={count} columns={columns} "
        f"rows={rows} scale={scale} attack={attack} release={release}"
    ]
    for row in range(rows):
        lines.append(f"{plot_label(row, half, scale):>6} |{''.join(grid[row])}|")
    axis = "".join("+" if column % 10 == 0 else "-" for column in range(columns))
    lines.append(f"       +{axis}+")
    time_line = "    ms"
    for column in range(0, columns, 10):
        index = start + column * count // columns
        time_line = time_line.ljust(8 + column) + str(milliseconds(index, source.rate))
    lines.append(time_line)
    return lines


def meter_plot(source, block):
    samples = source.samples
    blocks = ceil_div(len(samples), block)
    lines = [
        f"METER {source.name} rate={source.rate} samples={len(samples)} block={block} blocks={blocks}"
    ]
    for index in range(blocks):
        part = samples[index * block:(index + 1) * block]
        part_peak = peak(part)
        part_rms = rms(part)
        peak_width = rdiv(part_peak * METER_WIDTH, FULL_SCALE)
        rms_width = rdiv(part_rms * METER_WIDTH, FULL_SCALE)
        bar = "".join(
            "#" if j < rms_width else "-" if j < peak_width else " " for j in range(METER_WIDTH)
        )
        lines.append(
            f"{milliseconds(index * block, source.rate):6d} |{bar}| "
            f"peak={part_peak} rms={part_rms} clipped={count_clipped(part)}"
        )
    return lines


def histogram_plot(source, bins):
    counts = [0] * bins
    for x in source.samples:
        counts[(x + FULL_SCALE) * bins // SAMPLE_SPAN] += 1
    edges = [ceil_div(b * SAMPLE_SPAN, bins) - FULL_SCALE for b in range(bins + 1)]
    largest = max(counts)
    lines = [
        f"HISTOGRAM {source.name} rate={source.rate} samples={len(source.samples)} "
        f"bins={bins} max={largest}"
    ]
    for b in range(bins):
        bar = "#" * rdiv(counts[b] * HISTOGRAM_WIDTH, largest)
        lines.append(f"{edges[b]:6d} {edges[b + 1] - 1:6d} {counts[b]:5d} |{bar}")
    return lines


def pitch_row(rate, start, level, lag, low, high):
    prefix = f"{milliseconds(start, rate):6d} |"
    if lag is None:
        return f"{prefix}{' ' * (PITCH_WIDTH + 1)}| unvoiced rms={level}"
    position = rdiv((high - lag) * PITCH_WIDTH, high - low) if high > low else 0
    scale = " " * position + "o" + " " * (PITCH_WIDTH - position)
    return f"{prefix}{scale}| lag={lag} hz={frequency_text(rate, lag)} rms={level}"


def trace_lines(signal, depth, lines):
    lines.append(f"{'  ' * depth}{signal.name} <- {signal.origin}")
    for ingredient in signal.ingredients:
        trace_lines(ingredient, depth + 1, lines)


class Pipeline:
    def __init__(self, loaded):
        self.signals = {}
        self.variables = {}
        self.log = []
        self.analysis = [ANALYSIS_HEADER]
        self.excerpts = []
        self.waveforms = []
        self.saved = []
        self.steps = 0
        self.errors = 0
        self.passed = 0
        self.failed = 0
        self.actions = {
            "SET": self.set_variable,
            "ANALYZE": self.analyze,
            "COMPARE": self.compare,
            "EXPECT": self.expect,
            "SEGMENTS": self.segments,
            "ONSETS": self.onsets,
            "PITCHTRACK": self.pitch_track,
            "EXCERPT": self.excerpt,
            "PLOT": self.plot,
            "METER": self.meter,
            "HISTOGRAM": self.histogram,
            "TRACE": self.trace,
            "SAVE": self.save,
        }
        for signal in loaded:
            self.signals[signal.name] = signal
            self.log.append(
                f"load {signal.name} rate={signal.rate} samples={len(signal.samples)} "
                f"peak={peak(signal.samples)}"
            )

    def integer_value(self, token):
        if token.startswith("$"):
            if token[1:] not in self.variables:
                raise CommandError(f"undefined variable {token}")
            return self.variables[token[1:]]
        if not INTEGER_PATTERN.fullmatch(token) or token == "-0":
            raise CommandError(f"bad integer {token}")
        return int(token)

    def parse_arguments(self, name, command, tokens):
        values = []
        sources = []
        known = {}
        for index, token in enumerate(tokens):
            argument = command.argument_at(index)
            if argument.kind == "name":
                if not NAME_PATTERN.fullmatch(token):
                    raise CommandError(f"bad name {token}")
                value = token
            elif argument.kind == "signal":
                if token not in self.signals:
                    raise CommandError(f"unknown signal {token}")
                value = self.signals[token]
                sources.append(value)
            elif argument.kind == "metric":
                if token not in METRICS:
                    raise CommandError(f"unknown metric {token}")
                value = token
            elif argument.kind == "operator":
                if token not in OPERATORS[name]:
                    raise CommandError(f"unknown operator {token}")
                value = token
            else:
                value = self.integer_value(token)
                source = sources[0] if sources else None
                low = resolve_bound(argument.low, known, source)
                high = resolve_bound(argument.high, known, source)
                if not low <= value <= high:
                    raise CommandError(f"{argument.name} out of range")
                known[argument.name] = value
            values.append(value)
        return values, sources

    def generate(self, number, name, values, sources):
        dst = values[0]
        rate, samples, extras = GENERATORS[name](values[1:])
        self.signals[dst] = Signal(dst, rate, samples, f"line {number} {name}", sources)
        details = f"{dst} rate={rate} samples={len(samples)} peak={peak(samples)} sum={sum(samples)}"
        return details + "".join(f" {key}={value}" for key, value in extras)

    def execute(self, number, name, tokens):
        if name not in COMMANDS:
            raise CommandError(f"unknown command {name}")
        command = COMMANDS[name]
        if not command.accepts(len(tokens)):
            raise CommandError("wrong number of arguments")
        values, sources = self.parse_arguments(name, command, tokens)
        if name in GENERATORS:
            return [self.generate(number, name, values, sources)]
        return self.actions[name](values)

    def run_line(self, number, line):
        name, *tokens = line.split(" ")
        try:
            lines = self.execute(number, name, tokens)
        except CommandError as error:
            self.log.append(f"line {number}: error: {error}")
            self.errors += 1
            return
        self.log.append(f"line {number}: {name} {lines[0]}")
        self.log.extend(lines[1:])
        self.steps += 1

    def set_variable(self, values):
        var, result = values[0], values[1]
        if len(values) == 4:
            op, operand = values[2], values[3]
            if op == "/" and operand == 0:
                raise CommandError("division by zero")
            result = ARITHMETIC[op](result, operand)
            if abs(result) > VALUE_LIMIT:
                raise CommandError("value out of range")
        self.variables[var] = result
        return [f"{var}={result}"]

    def analyze(self, values):
        source, min_hz, max_hz = values
        samples = source.samples
        low, high = lag_range(source.rate, min_hz, max_hz)
        if low > high:
            raise CommandError("empty lag range")
        if high >= len(samples):
            raise CommandError("signal too short")
        fraction = crest_fraction(samples)
        crest = "none" if fraction is None else f"{fraction[0]}/{fraction[1]}"
        lag = pitch_lag(samples, low, high)
        lag_text = "none" if lag is None else str(lag)
        hz_text = "none" if lag is None else frequency_text(source.rate, lag)
        fields = [
            source.name, peak(samples), rms(samples), zero_crossings(samples),
            count_clipped(samples), crest, lag_text, hz_text,
        ]
        self.analysis.append(",".join(str(field) for field in fields))
        return [f"{source.name} lags={low}-{high}"]

    def compare(self, values):
        first, second = values
        if first.rate != second.rate:
            raise CommandError("rate mismatch")
        length = max(len(first.samples), len(second.samples))
        a = first.samples + [0] * (length - len(first.samples))
        b = second.samples + [0] * (length - len(second.samples))
        differences = [p - q for p, q in zip(a, b)]
        differing = sum(1 for d in differences if d != 0)
        max_diff = max(abs(d) for d in differences)
        first_index = next((i for i, d in enumerate(differences) if d != 0), "none")
        error_energy = sum(d * d for d in differences)
        return [
            f"{first.name} {second.name} differing={differing} max_diff={max_diff} "
            f"first={first_index} error_energy={error_energy}"
        ]

    def expect(self, values):
        source, metric, op, value = values
        measured = METRICS[metric](source.samples)
        if COMPARISONS[op](measured, value):
            result = "pass"
            self.passed += 1
        else:
            result = "fail"
            self.failed += 1
        return [f"{source.name} {metric}={measured} {op} {value} {result}"]

    def segments(self, values):
        source, threshold, gap, min_length = values
        samples = source.samples
        found = []
        for i, x in enumerate(samples):
            if abs(x) < threshold:
                continue
            if found and i - found[-1][1] <= gap:
                found[-1] = (found[-1][0], i)
            else:
                found.append((i, i))
        reported = [(start, end) for start, end in found if end - start + 1 >= min_length]
        lines = [f"{source.name} segments={len(reported)}"]
        for number, (start, end) in enumerate(reported, 1):
            part = samples[start:end + 1]
            lines.append(
                f"  segment {number} start={start} end={end} "
                f"start_ms={milliseconds(start, source.rate)} end_ms={milliseconds(end, source.rate)} "
                f"peak={peak(part)} rms={rms(part)} crossings={zero_crossings(part)}"
            )
        return lines

    def onsets(self, values):
        source, attack, release, threshold, min_gap = values
        levels = dynamics.envelope(source.samples, attack, release)
        onsets = []
        for n, level in enumerate(levels):
            rising = level >= threshold and (n == 0 or levels[n - 1] < threshold)
            if rising and (not onsets or n - onsets[-1] >= min_gap):
                onsets.append(n)
        intervals = [later - earlier for earlier, later in zip(onsets, onsets[1:])]
        tempo = "none"
        if len(onsets) >= 2:
            middle = sorted(intervals)[(len(onsets) - 2) // 2]
            tempo = two_decimals(rdiv(6000 * source.rate, middle))
        lines = [f"{source.name} onsets={len(onsets)} tempo={tempo}"]
        for number, n in enumerate(onsets, 1):
            interval = "none" if number == 1 else intervals[number - 2]
            lines.append(
                f"  onset {number} sample={n} ms={milliseconds(n, source.rate)} interval={interval}"
            )
        return lines

    def pitch_track(self, values):
        source, frame, hop, min_hz, max_hz, threshold = values
        low, high = lag_range(source.rate, min_hz, max_hz)
        if low > high:
            raise CommandError("empty lag range")
        if high >= frame:
            raise CommandError("frame too short")
        count = (len(source.samples) - frame) // hop + 1
        rows = []
        voiced = 0
        for t in range(count):
            window = source.samples[t * hop:t * hop + frame]
            level = rms(window)
            lag = None if level < threshold else pitch_lag(window, low, high)
            if lag is not None:
                voiced += 1
            rows.append(pitch_row(source.rate, t * hop, level, lag, low, high))
        self.waveforms.append(
            f"PITCHTRACK {source.name} rate={source.rate} frame={frame} hop={hop} "
            f"lags={low}-{high} threshold={threshold} frames={count} voiced={voiced}"
        )
        self.waveforms.extend(rows)
        return [f"{source.name} frames={count} voiced={voiced}"]

    def excerpt(self, values):
        source, start, count = values
        length = min(count, len(source.samples) - start)
        part = source.samples[start:start + length]
        self.excerpts.append(
            f"EXCERPT {source.name} rate={source.rate} samples={len(source.samples)} "
            f"start={start} count={length}"
        )
        for offset in range(0, length, EXCERPT_GROUP):
            group = "".join(f" {x:6d}" for x in part[offset:offset + EXCERPT_GROUP])
            self.excerpts.append(f"{start + offset:5d}:{group}")
        return [f"{source.name} start={start} count={length}"]

    def plot(self, values):
        source, start, count, columns, half, attack, release = values
        self.waveforms.extend(waveform_plot(source, start, count, columns, half, attack, release))
        return [f"{source.name} start={start} count={count} columns={columns} rows={2 * half + 1}"]

    def meter(self, values):
        source, block = values
        self.waveforms.extend(meter_plot(source, block))
        return [f"{source.name} block={block}"]

    def histogram(self, values):
        source, bins = values
        self.waveforms.extend(histogram_plot(source, bins))
        return [f"{source.name} bins={bins}"]

    def trace(self, values):
        source = values[0]
        lines = [source.name]
        trace_lines(source, 1, lines)
        return lines

    def save(self, values):
        source = values[0]
        self.saved.extend(format_signal(source))
        return [f"{source.name} samples={len(source.samples)}"]

    def finish(self):
        for name in sorted(self.signals):
            signal = self.signals[name]
            self.log.append(
                f"signal {name} rate={signal.rate} samples={len(signal.samples)} "
                f"peak={peak(signal.samples)} rms={rms(signal.samples)}"
            )
        self.log.append(
            f"summary steps={self.steps} errors={self.errors} signals={len(self.signals)} "
            f"passed={self.passed} failed={self.failed}"
        )


def write_lines(path, lines):
    with open(path, "w") as file:
        file.write("".join(line + "\n" for line in lines))


def main():
    pipeline = Pipeline(read_signals(SIGNALS_PATH))
    with open(PIPELINE_PATH) as file:
        lines = file.read().splitlines()
    for number, line in enumerate(lines, 1):
        if line and not line.startswith("#"):
            pipeline.run_line(number, line)
    pipeline.finish()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines(os.path.join(OUTPUT_DIR, "log.txt"), pipeline.log)
    write_lines(os.path.join(OUTPUT_DIR, "analysis.csv"), pipeline.analysis)
    write_lines(os.path.join(OUTPUT_DIR, "excerpts.txt"), pipeline.excerpts)
    write_lines(os.path.join(OUTPUT_DIR, "waveforms.txt"), pipeline.waveforms)
    write_lines(os.path.join(OUTPUT_DIR, "signals_out.txt"), pipeline.saved)


if __name__ == "__main__":
    main()
