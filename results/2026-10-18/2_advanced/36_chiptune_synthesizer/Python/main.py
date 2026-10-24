import os

from instruments import clamp, envelope_value, note_frequency, oscillation, transpose
from mixer import fade_out, mix_tick
from report import adler32_text, hex_lines, peak, root_mean_square, zero_crossings
from sequencer import next_row, reachable_rows, samples_per_tick
from song_parser import CHANNEL_COUNT, ROWS_PER_PATTERN, note_name, read_params, read_song


SONG_PATH = "input/song.txt"
PARAMS_PATH = "input/params.txt"
OUTPUT_DIR = "output"
FMIN = 1000
LANE_LIMIT = 3375
EFFECT_ORDER = (
    "0", "1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D",
    "E1", "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V",
)
TONIC_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
MAJOR_WEIGHTS = (64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29)
MINOR_WEIGHTS = (64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32)


def hex2(value):
    return f"{value:02X}"


def hex1(value):
    return f"{value:X}"


def hex_list(values):
    return " ".join(hex2(value) for value in values) if values else "none"


def note_range(notes):
    if not notes:
        return "none"
    return f"{note_name(min(notes))}..{note_name(max(notes))}"


class NoteRecord:
    def __init__(self, serial, channel, position, row, instrument, note, start):
        self.serial = serial
        self.channel = channel
        self.position = position
        self.row = row
        self.instrument = instrument
        self.note = note
        self.start = start
        self.length = 0
        self.release = None
        self.reason = None


class PlayedRow:
    def __init__(self, position, row, start, speed, tempo, notes):
        self.position = position
        self.row = row
        self.start = start
        self.speed = speed
        self.tempo = tempo
        self.notes = notes


class Channel:
    def __init__(self, number):
        self.number = number
        self.instrument = None
        self.note = None
        self.frequency = 0
        self.target = 0
        self.portamento = 0
        self.slide = 0
        self.detune = 0
        self.vibrato_speed = 0
        self.vibrato_depth = 0
        self.vibrato_position = 0
        self.tremolo_speed = 0
        self.tremolo_depth = 0
        self.tremolo_position = 0
        self.volume = 15
        self.mode = 0
        self.phase = 0
        self.register = 1
        self.age = 0
        self.released = False
        self.release_age = 0
        self.release_level = 0
        self.envelope = 0
        self.output_frequency = 0
        self.output_volume = 0
        self.amplitude = 0
        self.increment = 0
        self.effect = None
        self.sounding = False
        self.record = None
        self.note_ons = 0
        self.retriggers = 0
        self.cuts = 0
        self.active = 0
        self.audible = 0

    def effect_name(self):
        return None if self.effect is None else self.effect.name

    def effect_value(self):
        return 0 if self.effect is None else self.effect.value

    def key_off(self):
        self.release_age = self.age
        self.release_level = self.envelope
        self.released = True

    def approach(self, step):
        if self.frequency < self.target:
            self.frequency = min(self.frequency + step, self.target)
        else:
            self.frequency = max(self.frequency - step, self.target)

    def volume_slide(self):
        self.volume = clamp(self.volume + self.effect.high() - self.effect.low(), 0, 15)

    def update_output(self, tick, rate):
        instrument = self.instrument
        name = self.effect_name()
        semitones = 0
        if name == "0":
            semitones = (0, self.effect.high(), self.effect.low())[tick % 3]
        if instrument.arpeggio:
            semitones += instrument.arpeggio[self.age % len(instrument.arpeggio)]
        frequency = transpose(self.frequency, semitones) + self.detune
        if name in ("4", "6"):
            frequency += oscillation(self.vibrato_position, self.vibrato_depth, 4)
        if instrument.vibrato is not None:
            delay, speed, depth = instrument.vibrato
            if self.age >= delay:
                frequency += oscillation((self.age - delay) * speed % 64, depth, 4)
        self.output_frequency = clamp(frequency, FMIN, 50 * rate)
        self.envelope = envelope_value(
            instrument, self.age, self.released, self.release_age, self.release_level
        )
        self.output_volume = self.volume
        if name == "7":
            tremolo = oscillation(self.tremolo_position, self.tremolo_depth, 255)
            self.output_volume = clamp(self.volume + tremolo, 0, 15)
        self.amplitude = self.envelope * self.output_volume
        self.increment = self.output_frequency * 65536 // (100 * rate)


class Player:
    def __init__(self, song, params):
        self.song = song
        self.params = params
        self.fmax = 50 * song.rate
        self.channels = [Channel(number) for number in range(1, CHANNEL_COUNT + 1)]
        self.lanes = [[] for _ in self.channels]
        self.samples = []
        self.speed = song.speed
        self.tempo = song.tempo
        self.delay = 0
        self.position = 0
        self.row = 0
        self.cells = []
        self.records = []
        self.warnings = []
        self.log = []
        self.played = []
        self.play_counts = {}
        self.first_starts = {}
        self.ticks = 0
        self.clipped = 0
        self.instrument_ticks = dict.fromkeys(song.instruments, 0)
        self.effect_counts = dict.fromkeys(EFFECT_ORDER, 0)
        self.end_reason = "finished"
        self.end_row = None
        self.loop_start = None

    def warn(self, channel, message):
        self.warnings.append(
            f"warning {hex2(self.position)}:{hex2(self.row)} ch{channel.number} {message}"
        )

    def clamp_frequency(self, frequency):
        return clamp(frequency, FMIN, self.fmax)

    def end_record(self, channel, reason):
        record = channel.record
        record.length = len(self.samples) - record.start
        record.reason = reason
        channel.record = None

    def note_on(self, channel, note):
        if channel.record is not None:
            self.end_record(channel, "next")
        channel.frequency = note_frequency(note)
        channel.target = channel.frequency
        channel.phase = 0
        channel.age = 0
        channel.vibrato_position = 0
        channel.tremolo_position = 0
        channel.released = False
        channel.note = note
        channel.note_ons += 1
        channel.record = NoteRecord(
            len(self.records) + 1, channel.number, self.position, self.row,
            channel.instrument, note, len(self.samples),
        )
        self.records.append(channel.record)

    def apply_cell(self, channel, cell, portamento):
        if cell.instrument is not None:
            instrument = self.song.instruments.get(cell.instrument)
            if instrument is None:
                self.warn(channel, f"undefined instrument {hex2(cell.instrument)}")
            else:
                channel.instrument = instrument
                channel.volume = 15
                channel.mode = instrument.mode
        if cell.volume is not None:
            channel.volume = cell.volume
        if cell.key_off:
            if channel.note is not None and not channel.released:
                channel.key_off()
                channel.record.release = len(self.samples) - channel.record.start
            else:
                self.warn(channel, "key off without note")
        elif cell.note is not None:
            if channel.instrument is None:
                self.warn(channel, "note without instrument")
            elif portamento and channel.note is not None:
                channel.target = note_frequency(cell.note)
                channel.note = cell.note
            else:
                if portamento:
                    self.warn(channel, "portamento without note")
                self.note_on(channel, cell.note)

    def note_slide(self, channel, effect):
        if channel.note is None:
            self.warn(channel, "slide without note")
            return
        if effect.name == "Q":
            channel.note = min(channel.note + effect.low(), 95)
        else:
            channel.note = max(channel.note - effect.low(), 12)
        channel.target = note_frequency(channel.note)
        channel.slide = 2 * effect.high() + 1

    def set_mode(self, channel, value):
        instrument = channel.instrument
        valid = instrument is not None and (
            instrument.wave == "PULSE" and value <= 3
            or instrument.wave == "NOISE" and value <= 1
        )
        if valid:
            channel.mode = value
        else:
            self.warn(channel, f"invalid mode {hex2(value)}")

    def start_effect(self, channel):
        effect = channel.effect
        name = effect.name
        value = effect.value
        if name == "3":
            if value > 0:
                channel.portamento = value
        elif name == "4":
            if effect.high() > 0:
                channel.vibrato_speed = effect.high()
            if effect.low() > 0:
                channel.vibrato_depth = effect.low()
        elif name == "7":
            if effect.high() > 0:
                channel.tremolo_speed = effect.high()
            if effect.low() > 0:
                channel.tremolo_depth = effect.low()
        elif name == "C":
            channel.volume = min(value, 15)
        elif name == "E1":
            channel.frequency = self.clamp_frequency(channel.frequency + 10 * value)
        elif name == "E2":
            channel.frequency = self.clamp_frequency(channel.frequency - 10 * value)
        elif name == "EA":
            channel.volume = min(channel.volume + value, 15)
        elif name == "EB":
            channel.volume = max(channel.volume - value, 0)
        elif name == "EE":
            self.delay = value
        elif name == "F":
            if 1 <= value <= 31:
                self.speed = value
            elif value >= 32:
                self.tempo = value
        elif name == "P":
            channel.detune = value - 128
        elif name in ("Q", "R"):
            self.note_slide(channel, effect)
        elif name == "V":
            self.set_mode(channel, value)

    def tick_effect(self, channel):
        name = channel.effect.name
        value = channel.effect.value
        if name == "1":
            channel.frequency = self.clamp_frequency(channel.frequency + 10 * value)
        elif name == "2":
            channel.frequency = self.clamp_frequency(channel.frequency - 10 * value)
        elif name == "3":
            channel.approach(10 * channel.portamento)
        elif name == "5":
            channel.approach(10 * channel.portamento)
            channel.volume_slide()
        elif name in ("6", "A"):
            channel.volume_slide()
        elif name in ("Q", "R"):
            if channel.slide != 0:
                channel.approach(10 * channel.slide)

    def start_row(self):
        self.delay = 0
        for channel, cell in zip(self.channels, self.cells):
            channel.effect = cell.effect
            channel.slide = 0
            if cell.effect is not None:
                self.effect_counts[cell.effect.name] += 1
            name = channel.effect_name()
            if not (name == "ED" and channel.effect_value() >= 1):
                self.apply_cell(channel, cell, name in ("3", "5"))
            if channel.effect is not None:
                self.start_effect(channel)

    def warn_beyond_row(self, ticks):
        for channel in self.channels:
            name = channel.effect_name()
            if name == "EC" and channel.effect_value() >= ticks:
                self.warn(channel, "cut beyond row")
            elif name == "ED" and channel.effect_value() >= ticks:
                self.warn(channel, "delay beyond row")

    def process_tick(self, tick):
        for channel, cell in zip(self.channels, self.cells):
            name = channel.effect_name()
            value = channel.effect_value()
            if channel.note is not None and channel.age >= 1 and channel.instrument.sweep != 0:
                sweep = 10 * channel.instrument.sweep
                channel.frequency = self.clamp_frequency(channel.frequency + sweep)
            if tick >= 1 and channel.effect is not None:
                self.tick_effect(channel)
            if name == "ED" and value >= 1 and tick == value:
                self.apply_cell(channel, cell, False)
            if name == "E9" and value >= 1 and tick >= 1 and tick % value == 0:
                if channel.note is not None:
                    channel.phase = 0
                    channel.age = 0
                    channel.released = False
                    channel.retriggers += 1
            if name == "EC" and tick == value and channel.note is not None:
                self.end_record(channel, "cut")
                channel.note = None
                channel.cuts += 1
            channel.sounding = channel.note is not None
            if channel.sounding:
                channel.update_output(tick, self.song.rate)
                channel.active += 1
                if channel.amplitude > 0:
                    channel.audible += 1
                self.instrument_ticks[channel.instrument.number] += 1

    def advance(self):
        for channel in self.channels:
            name = channel.effect_name()
            if channel.note is not None:
                channel.age += 1
            if name in ("4", "6"):
                channel.vibrato_position = (channel.vibrato_position + channel.vibrato_speed) % 64
            elif name == "7":
                channel.tremolo_position = (channel.tremolo_position + channel.tremolo_speed) % 64
        self.ticks += 1

    def channel_text(self, channel):
        effect = "..." if channel.effect is None else channel.effect.text
        if channel.note is None:
            return f"--- -- {'-':>7} - {hex1(channel.volume)} {effect}"
        return (
            f"{note_name(channel.note)} {hex2(channel.instrument.number)} "
            f"{channel.output_frequency:7d} {hex1(channel.envelope)} "
            f"{hex1(channel.output_volume)} {effect}"
        )

    def log_row(self, start):
        pattern = self.song.order[self.position]
        parts = [
            f"{hex2(self.position)} {hex2(pattern)} {hex2(self.row)} "
            f"{start:7d} {self.speed:2d} {self.tempo:3d}"
        ]
        parts.extend(self.channel_text(channel) for channel in self.channels)
        self.log.append(" | ".join(parts))
        notes = [channel.note for channel in self.channels]
        self.played.append(
            PlayedRow(self.position, self.row, start, self.speed, self.tempo, notes)
        )

    def log_tick(self, tick):
        parts = [f"  tick {tick:3d} {len(self.samples):7d}"]
        for channel in self.channels:
            if channel.sounding:
                parts.append(
                    f"{channel.output_frequency:7d} {channel.increment:5d} "
                    f"{hex1(channel.envelope)}{hex1(channel.output_volume)}"
                )
            else:
                parts.append(f"{'-':>7} {'-':>5} --")
        self.log.append(" | ".join(parts))

    def play_row(self, position, row):
        self.position = position
        self.row = row
        self.cells = self.song.cells(position, row)
        start = len(self.samples)
        self.first_starts.setdefault((position, row), start)
        self.start_row()
        ticks = self.speed * (1 + self.delay)
        self.warn_beyond_row(ticks)
        tick_samples = samples_per_tick(self.song.rate, self.tempo)
        traced = (position, row) in self.params.traces
        for tick in range(ticks):
            self.process_tick(tick)
            if tick == 0:
                self.log_row(start)
            if traced:
                self.log_tick(tick)
            count = min(tick_samples, self.params.max_samples - len(self.samples))
            self.clipped += mix_tick(
                self.channels, count, self.song.gain, self.params.muted,
                self.samples, self.lanes,
            )
            self.advance()
            if len(self.samples) == self.params.max_samples:
                return False
        return True

    def play(self):
        position, row = 0, 0
        while True:
            self.play_counts[(position, row)] = self.play_counts.get((position, row), 0) + 1
            if not self.play_row(position, row):
                self.end_reason = "limit"
                break
            following = next_row(self.song, position, row)
            if following is None:
                self.end_reason = "stop"
                self.end_row = (position, row)
                break
            position, row = following
            if position >= len(self.song.order):
                self.end_reason = "finished"
                break
            if self.play_counts.get(following, 0) >= self.params.loops:
                self.end_reason = "loop"
                self.end_row = following
                self.loop_start = self.first_starts[following]
                break
        for channel in self.channels:
            if channel.record is not None:
                self.end_record(channel, "end")
        if self.end_reason in ("limit", "loop") and self.params.fade > 0:
            fade_out(self.samples, self.params.fade)

    def end_text(self):
        if self.end_reason in ("stop", "loop"):
            position, row = self.end_row
            return f"{self.end_reason} order={hex2(position)} row={hex2(row)}"
        return self.end_reason


def note_lines(player):
    lines = []
    for record in player.records:
        lane = player.lanes[record.channel - 1]
        segment = lane[record.start:record.start + record.length]
        cycles = sum(
            previous < 0 <= current
            for previous, current in zip(segment, segment[1:])
        )
        release = "-" if record.release is None else str(record.release)
        lines.append(
            f"{record.serial:4d} ch={record.channel} "
            f"at={hex2(record.position)}:{hex2(record.row)} "
            f"ins={hex2(record.instrument.number)} note={note_name(record.note)} "
            f"start={record.start} length={record.length} release={release} "
            f"end={record.reason} peak={peak(segment, 0)} cycles={cycles}"
        )
    return lines


def roll_lines(played, start, rows):
    targets = played[start:start + rows]
    pitches = sorted(
        {note for row in targets for note in row.notes if note is not None},
        reverse=True,
    )
    lines = [f"ROLL start={start} rows={len(targets)} pitches={len(pitches)}"]
    for pitch in pitches:
        marks = []
        for row in targets:
            owners = [number for number, note in enumerate(row.notes, 1) if note == pitch]
            if not owners:
                marks.append(" ")
            elif len(owners) == 1:
                marks.append(str(owners[0]))
            else:
                marks.append("*")
        lines.append(f"{note_name(pitch)} |{''.join(marks)}|")
    ruler = "".join("+" if index % 16 == 0 else "-" for index in range(len(targets)))
    lines.append(f"    +{ruler}+")
    return lines


def path_line(played):
    positions = []
    for row in played:
        if not positions or positions[-1] != row.position:
            positions.append(row.position)
    return "path " + " ".join(hex2(position) for position in positions)


def timing_lines(played):
    lines = []
    previous = None
    for row in played:
        timing = (row.speed, row.tempo)
        if timing != previous:
            lines.append(
                f"timing sample={row.start} order={hex2(row.position)} "
                f"row={hex2(row.row)} speed={row.speed} tempo={row.tempo}"
            )
        previous = timing
    return lines


def channel_lines(player):
    lines = []
    for channel, lane in zip(player.channels, player.lanes):
        lines.append(
            f"channel {channel.number} notes={channel.note_ons} "
            f"retriggers={channel.retriggers} cuts={channel.cuts} "
            f"active={channel.active} audible={channel.audible} "
            f"peak={peak(lane, 0)} rms={root_mean_square(lane, 0)}"
        )
    return lines


def instrument_lines(player):
    lines = []
    for number, instrument in sorted(player.song.instruments.items()):
        records = [record for record in player.records if record.instrument is instrument]
        if records:
            average = sum(record.length for record in records) // len(records)
            summary = f"range={note_range([record.note for record in records])} average={average}"
        else:
            summary = "range=none average=-"
        lines.append(
            f"instrument {hex2(number)} {instrument.name} {instrument.wave} "
            f"notes={len(records)} ticks={player.instrument_ticks[number]} {summary}"
        )
    return lines


def pattern_lines(song):
    lines = []
    for number, pattern in sorted(song.patterns.items()):
        rows = sum(
            not all(cell.is_empty() for cell in cells) for cells in pattern.rows
        )
        notes = sum(cell.has_note() for cells in pattern.rows for cell in cells)
        lines.append(
            f"pattern {hex2(number)} rows={rows} notes={notes} orders={song.order.count(number)}"
        )
    return lines


def order_lines(player):
    song = player.song
    reached = reachable_rows(song)
    lines = []
    for position, pattern in enumerate(song.order):
        starts = [row.start for row in player.played if row.position == position]
        first = str(starts[0]) if starts else "-"
        dead = sum(
            (position, row) not in reached
            and any(cell.has_note() for cell in song.cells(position, row))
            for row in range(ROWS_PER_PATTERN)
        )
        lines.append(
            f"order {hex2(position)} pattern={hex2(pattern)} rows={len(starts)} "
            f"first={first} dead={dead}"
        )
    return lines


def note_count_lines(records):
    counts = {}
    for record in records:
        counts[record.note] = counts.get(record.note, 0) + 1
    return [f"note {note_name(note)} count={count}" for note, count in sorted(counts.items())]


def effects_line(counts):
    used = [f"{name}={counts[name]}" for name in EFFECT_ORDER if counts[name] > 0]
    return "effects " + (" ".join(used) if used else "none")


def unused_lines(player):
    song = player.song
    used_instruments = {record.instrument.number for record in player.records}
    played_positions = {row.position for row in player.played}
    instruments = [number for number in sorted(song.instruments) if number not in used_instruments]
    patterns = [number for number in sorted(song.patterns) if number not in song.order]
    positions = [
        position for position in range(len(song.order)) if position not in played_positions
    ]
    return [
        f"unused_instruments={hex_list(instruments)}",
        f"unused_patterns={hex_list(patterns)}",
        f"unreached_orders={hex_list(positions)}",
    ]


def pitch_classes(records):
    totals = [0] * 12
    for record in records:
        if record.instrument.wave != "NOISE":
            totals[record.note % 12] += record.length
    return totals


def estimate_key(totals):
    keys = []
    for weights, mode in ((MAJOR_WEIGHTS, "major"), (MINOR_WEIGHTS, "minor")):
        for tonic in range(12):
            score = sum(weights[(pitch - tonic) % 12] * totals[pitch] for pitch in range(12))
            keys.append((f"{TONIC_NAMES[tonic]} {mode}", score))
    keys.sort(key=lambda key: key[1], reverse=True)
    return keys[0], keys[1]


def usage_lines(player):
    lines = []
    numbers = sorted(player.song.instruments)
    for channel in player.channels:
        records = [record for record in player.records if record.channel == channel.number]
        notes = [record.note for record in records]
        parts = [f"usage ch{channel.number} range={note_range(notes)}"]
        for number in numbers:
            count = sum(record.instrument.number == number for record in records)
            parts.append(f"{hex2(number)}={count}")
        lines.append(" ".join(parts))
    return lines


def stats_lines(player):
    song = player.song
    samples = player.samples
    total = len(samples)
    lines = [
        f"title={song.title}",
        f"rate={song.rate}",
        f"samples={total}",
        f"duration_ms={total * 1000 // song.rate}",
        f"end={player.end_text()}",
    ]
    if player.end_reason == "loop":
        lines.append(f"loop_start={player.loop_start}")
        lines.append(f"loop_length={total - player.loop_start}")
    else:
        lines.extend(("loop_start=-", "loop_length=-"))
    lines.extend((
        f"rows={len(player.played)}",
        f"ticks={player.ticks}",
        f"clipped={player.clipped}",
        f"peak={peak(samples, 128)}",
        f"min={min(samples)}",
        f"max={max(samples)}",
        f"rms={root_mean_square(samples, 128)}",
        f"zero_crossings={zero_crossings(samples)}",
        f"adler32={adler32_text(samples)}",
        path_line(player.played),
    ))
    lines.extend(timing_lines(player.played))
    lines.extend(channel_lines(player))
    lines.extend(instrument_lines(player))
    lines.extend(pattern_lines(song))
    lines.extend(order_lines(player))
    lines.extend(note_count_lines(player.records))
    lines.append(effects_line(player.effect_counts))
    lines.extend(unused_lines(player))
    totals = pitch_classes(player.records)
    classes = " ".join(f"{name}={value}" for name, value in zip(TONIC_NAMES, totals))
    lines.append(f"pitch_classes {classes}")
    (best, best_score), (runner_up, runner_up_score) = estimate_key(totals)
    lines.append(f"key={best} score={best_score} runner_up={runner_up} score={runner_up_score}")
    lines.extend(usage_lines(player))
    lines.extend(player.warnings)
    return lines


def plot_row(value, low, high, height):
    return (2 * (high - value) * (height - 1) + (high - low)) // (2 * (high - low))


def plot_lines(values, low, high, middle, height, width):
    length = len(values)
    middle_row = plot_row(middle, low, high, height)
    columns = []
    for column in range(width):
        covered = values[column * length // width:(column + 1) * length // width]
        top = plot_row(max(covered), low, high, height)
        bottom = plot_row(min(covered), low, high, height)
        columns.append((top, bottom))
    lines = []
    for row in range(height):
        if row == 0:
            label = str(high)
        elif row == middle_row:
            label = str(middle)
        elif row == height - 1:
            label = str(low)
        else:
            label = ""
        marks = []
        for top, bottom in columns:
            if top <= row <= bottom:
                marks.append("#")
            elif row == middle_row:
                marks.append("-")
            else:
                marks.append(" ")
        lines.append(f"{label:>5} |{''.join(marks)}|")
    return lines


def axis_lines(start, length, width, rate):
    ruler = "".join("+" if column % 10 == 0 else "-" for column in range(width))
    labels = "    ms"
    for column in range(0, width, 10):
        milliseconds = (start + column * length // width) * 1000 // rate
        labels = labels.ljust(7 + column) + str(milliseconds)
    return [f"      +{ruler}+", labels]


def waveform_lines(player):
    params = player.params
    start = params.window_start
    length = params.window_length
    width = params.window_width
    end = start + length
    axes = axis_lines(start, length, width, player.song.rate)
    lines = [f"MIX start={start} length={length} width={width} height={params.window_height}"]
    lines.extend(plot_lines(player.samples[start:end], 0, 255, 128, params.window_height, width))
    lines.extend(axes)
    for channel, lane in zip(player.channels, player.lanes):
        lines.append(f"CHANNEL {channel.number}")
        lines.extend(plot_lines(
            lane[start:end], -LANE_LIMIT, LANE_LIMIT, 0, params.window_scope, width
        ))
    lines.extend(axes)
    return lines


def preview_lines(song, params, instrument):
    channel = Channel(1)
    channel.instrument = instrument
    channel.mode = instrument.mode
    channel.note = params.preview_note
    channel.frequency = note_frequency(params.preview_note)
    channel.target = channel.frequency
    channel.sounding = True
    tick_samples = samples_per_tick(song.rate, song.tempo)
    fmax = 50 * song.rate
    samples = []
    envelopes = []
    frequencies = []
    for tick in range(params.preview_ticks):
        channel.age = tick
        if tick == params.preview_release:
            channel.key_off()
        if tick >= 1 and instrument.sweep != 0:
            channel.frequency = clamp(channel.frequency + 10 * instrument.sweep, FMIN, fmax)
        channel.update_output(tick, song.rate)
        envelopes.append(hex1(channel.envelope))
        frequencies.append(str(channel.output_frequency))
        mix_tick([channel], tick_samples, song.gain, [False], samples, [[]])
    return [
        f"instrument {hex2(instrument.number)} {instrument.name} wave={instrument.wave} "
        f"samples={len(samples)} peak={peak(samples, 128)} "
        f"rms={root_mean_square(samples, 128)} adler32={adler32_text(samples)}",
        "  env " + "".join(envelopes),
        "  freq " + " ".join(frequencies),
    ]


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as file:
        file.write("".join(line + "\n" for line in lines))


def main():
    song = read_song(SONG_PATH)
    params = read_params(PARAMS_PATH)
    player = Player(song, params)
    player.play()
    previews = []
    for _, instrument in sorted(song.instruments.items()):
        previews.extend(preview_lines(song, params, instrument))
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("samples.txt", hex_lines(player.samples))
    write_lines("channel_log.txt", player.log)
    write_lines("notes.txt", note_lines(player))
    write_lines("roll.txt", roll_lines(player.played, params.roll_start, params.roll_rows))
    write_lines("stats.txt", stats_lines(player))
    write_lines("waveform.txt", waveform_lines(player))
    write_lines("instruments.txt", previews)


if __name__ == "__main__":
    main()
