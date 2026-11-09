from collections import deque
import re
import sys


NOTE_LETTERS = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
CHANNEL_TYPES = (
    "NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL",
    "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND",
)
NOTE_TYPES = ("NOTE_OFF", "NOTE_ON", "POLY_PRESSURE")
TEXT_KINDS = (
    "TEXT_EVENT", "COPYRIGHT", "TRACK_NAME", "INSTRUMENT_NAME",
    "LYRIC", "MARKER", "CUE_POINT",
)
META_NAMES = {
    0x00: "SEQUENCE_NUMBER", 0x01: "TEXT_EVENT", 0x02: "COPYRIGHT",
    0x03: "TRACK_NAME", 0x04: "INSTRUMENT_NAME", 0x05: "LYRIC",
    0x06: "MARKER", 0x07: "CUE_POINT", 0x20: "CHANNEL_PREFIX",
    0x2F: "END_OF_TRACK", 0x51: "TEMPO", 0x54: "SMPTE_OFFSET",
    0x58: "TIME_SIGNATURE", 0x59: "KEY_SIGNATURE", 0x7F: "SEQUENCER_SPECIFIC",
}
META_CODES = {name: code for code, name in META_NAMES.items()}
META_LENGTHS = {
    "SEQUENCE_NUMBER": 2, "CHANNEL_PREFIX": 1, "END_OF_TRACK": 0, "TEMPO": 3,
    "SMPTE_OFFSET": 5, "TIME_SIGNATURE": 4, "KEY_SIGNATURE": 2,
}
TYPE_NAMES = CHANNEL_TYPES + ("SYSEX", "SYSEX_ESCAPE", "META") + tuple(META_CODES)
MODES = ("major", "minor")
KEY_TABLES = (
    ("Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"),
    ("Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"),
)
DENOMINATORS = (1, 2, 4, 8, 16, 32, 64)
SYSEX_STATUS = 0xF0
ESCAPE_STATUS = 0xF7
META_STATUS = 0xFF
DEFAULT_TEMPO = 500000
MAX_TEMPO = 16777215
MAX_LENGTH = 1000000
MAX_TICK = 10000000
MAX_COLUMNS = 64


class CommandError(Exception):
    pass


class LineError(Exception):
    pass


def require(condition):
    if not condition:
        raise LineError("bad value")


def note_name(pitch):
    return NOTE_LETTERS[pitch % 12] + str(pitch // 12 - 1)


def signed_byte(value):
    return value - 256 if value >= 128 else value


def tempo_data(usec):
    return list(usec.to_bytes(3, "big"))


def scaled_tempo(usec, numerator, denominator):
    return (2 * usec * denominator + numerator) // (2 * numerator)


def quantize_delta(tick, grid, strength):
    lower = tick // grid * grid
    upper = lower + grid
    target = lower if tick - lower <= upper - tick else upper
    return (2 * (target - tick) * strength + 100) // 200


def argument(text, low, high):
    value = int(text)
    if not low <= value <= high:
        raise CommandError("bad argument")
    return value


class Event:
    def __init__(self, tick, status, data, meta_type=None):
        self.tick = tick
        self.status = status
        self.data = data
        self.meta_type = meta_type

    def copy(self):
        return Event(self.tick, self.status, list(self.data), self.meta_type)

    def is_channel(self):
        return self.status < SYSEX_STATUS

    def channel(self):
        return self.status % 16 + 1

    def type_name(self):
        if self.is_channel():
            return CHANNEL_TYPES[self.status // 16 - 8]
        if self.status == SYSEX_STATUS:
            return "SYSEX"
        if self.status == ESCAPE_STATUS:
            return "SYSEX_ESCAPE"
        return META_NAMES.get(self.meta_type, "META")

    def is_meta(self, name):
        return self.status == META_STATUS and META_NAMES.get(self.meta_type) == name

    def is_note_on(self):
        return self.type_name() == "NOTE_ON" and self.data[1] > 0

    def is_note_off(self):
        name = self.type_name()
        return name == "NOTE_OFF" or (name == "NOTE_ON" and self.data[1] == 0)

    def tempo(self):
        return int.from_bytes(bytes(self.data), "big")


def end_of_track(tick):
    return Event(tick, META_STATUS, [], META_CODES["END_OF_TRACK"])


def blob_fields(data):
    if not data:
        return ["0"]
    return [str(len(data)), bytes(data).hex().upper()]


def event_fields(event):
    name = event.type_name()
    data = event.data
    if event.is_channel():
        fields = [str(event.channel())]
        if name == "PITCH_BEND":
            fields.append(str(data[0] + 128 * data[1] - 8192))
        elif name in NOTE_TYPES:
            fields += [note_name(data[0]), str(data[1])]
        else:
            fields += [str(value) for value in data]
        return fields
    if name in TEXT_KINDS:
        return ['"' + bytes(data).decode("ascii") + '"']
    if name == "SEQUENCE_NUMBER":
        return [str(data[0] * 256 + data[1])]
    if name == "CHANNEL_PREFIX":
        return [str(data[0] + 1)]
    if name == "END_OF_TRACK":
        return []
    if name == "TEMPO":
        return [str(event.tempo())]
    if name == "SMPTE_OFFSET":
        return [str(value) for value in data]
    if name == "TIME_SIGNATURE":
        return [f"{data[0]}/{DENOMINATORS[data[1]]}", str(data[2]), str(data[3])]
    if name == "KEY_SIGNATURE":
        return [KEY_TABLES[data[1]][signed_byte(data[0]) + 7], MODES[data[1]]]
    if name == "META":
        return [f"{event.meta_type:02X}"] + blob_fields(data)
    return blob_fields(data)


def event_line(event, track):
    return " ".join([str(event.tick), str(track), event.type_name()] + event_fields(event))


class OrderedEvent:
    def __init__(self, order, track, event):
        self.order = order
        self.track = track
        self.event = event


class Song:
    def __init__(self, song_format, division, tracks):
        self.format = song_format
        self.division = division
        self.tracks = tracks

    def copy(self):
        tracks = [[event.copy() for event in track] for track in self.tracks]
        return Song(self.format, self.division, tracks)

    def event_count(self):
        return sum(len(track) for track in self.tracks)

    def length(self):
        return max(track[-1].tick for track in self.tracks)

    def summary(self):
        return (
            f"format {self.format} tracks {len(self.tracks)} "
            f"division {self.division} events {self.event_count()}"
        )

    def global_order(self):
        keys = [
            (event.tick, number, index)
            for number, track in enumerate(self.tracks)
            for index, event in enumerate(track)
        ]
        keys.sort()
        return [
            OrderedEvent(order, number, self.tracks[number][index])
            for order, (_, number, index) in enumerate(keys)
        ]


class Note:
    def __init__(self, placed):
        event = placed.event
        self.placed = placed
        self.start = event.tick
        self.channel = event.channel()
        self.pitch = event.data[0]
        self.velocity = event.data[1]
        self.off = None
        self.length = 0

    def finish(self, event):
        self.off = event
        self.length = event.tick - self.start


class Pairing:
    def __init__(self, song):
        self.notes = []
        self.unmatched = []
        queues = {}
        for placed in song.global_order():
            event = placed.event
            if not event.is_note_on() and not event.is_note_off():
                continue
            queue = queues.setdefault((event.channel(), event.data[0]), deque())
            if event.is_note_on():
                queue.append(Note(placed))
            elif queue:
                note = queue.popleft()
                note.finish(event)
                self.notes.append(note)
            else:
                self.unmatched.append(placed)
        self.pending = [note for queue in queues.values() for note in queue]
        self.unmatched.extend(note.placed for note in self.pending)
        self.unmatched.sort(key=lambda placed: placed.order)
        self.notes.sort(key=lambda note: (note.start, note.channel, note.pitch, note.placed.order))


class Timeline:
    def __init__(self, song):
        self.division = song.division
        events = [placed.event for placed in song.global_order()]
        self.tempos = [event for event in events if event.is_meta("TEMPO")]
        self.signatures = [event for event in events if event.is_meta("TIME_SIGNATURE")]

    def clock(self, tick):
        total = 0
        last = 0
        usec = DEFAULT_TEMPO
        for event in self.tempos:
            if event.tick > tick:
                break
            total += (event.tick - last) * usec
            last = event.tick
            usec = event.tempo()
        total += (tick - last) * usec
        micros = total // self.division
        return f"{micros // 1000}.{micros % 1000:03d}"

    def position(self, tick):
        start = 0
        bar = 1
        numerator = 4
        beat = self.division
        for event in self.signatures:
            if event.tick > tick:
                break
            size = numerator * beat
            bar += (event.tick - start + size - 1) // size
            start = event.tick
            numerator = event.data[0]
            beat = self.division * 4 // DENOMINATORS[event.data[1]]
        offset = tick - start
        size = numerator * beat
        return f"{bar + offset // size}:{offset % size // beat + 1}:{offset % beat}"


def polyphony(notes):
    changes = []
    for note in notes:
        if note.length > 0:
            changes.append((note.start, 1))
            changes.append((note.start + note.length, -1))
    changes.sort()
    current = 0
    peak = 0
    peak_tick = 0
    for tick, change in changes:
        current += change
        if current > peak:
            peak = current
            peak_tick = tick
    return peak, peak_tick


def pitch_range(notes):
    pitches = [note.pitch for note in notes]
    return note_name(min(pitches)) + " " + note_name(max(pitches))


def roll_cell(notes, low, step):
    if any(low <= note.start < low + step for note in notes):
        return "#"
    if any(note.start <= low < note.start + note.length for note in notes):
        return "="
    return "."


def sort_track(track):
    end = track[-1]
    events = sorted(track[:-1], key=lambda event: event.tick)
    if events:
        end.tick = max(end.tick, events[-1].tick)
    return events + [end]


def valid_meta_data(name, data):
    if name == "TEMPO":
        return int.from_bytes(bytes(data), "big") > 0
    if name == "CHANNEL_PREFIX":
        return data[0] <= 15
    if name == "TIME_SIGNATURE":
        return data[0] > 0 and data[1] <= 6
    if name == "KEY_SIGNATURE":
        return -7 <= signed_byte(data[0]) <= 7 and data[1] <= 1
    return True


class SmfParser:
    def __init__(self, data):
        self.data = data
        self.position = 0
        self.limit = 0
        self.event_start = 0

    def fail(self, position, reason):
        raise CommandError(f"byte {position}: {reason}")

    def word(self, position, size):
        return int.from_bytes(self.data[position:position + size], "big")

    def chunk(self, position, ident):
        if len(self.data) - position < 8:
            self.fail(position, "truncated chunk")
        if self.data[position:position + 4] != ident:
            self.fail(position, "bad chunk id")
        length = self.word(position + 4, 4)
        if position + 8 + length > len(self.data):
            self.fail(position, "truncated chunk")
        return length

    def parse(self):
        if self.chunk(0, b"MThd") != 6:
            self.fail(4, "bad header length")
        song_format = self.word(8, 2)
        if song_format > 2:
            self.fail(8, "bad format")
        count = self.word(10, 2)
        if count == 0 or (song_format == 0 and count != 1):
            self.fail(10, "bad track count")
        division = self.word(12, 2)
        if division >= 0x8000:
            self.fail(12, "smpte timing not supported")
        if division == 0:
            self.fail(12, "bad division")
        tracks = []
        position = 14
        for _ in range(count):
            if position == len(self.data):
                self.fail(position, "missing track")
            length = self.chunk(position, b"MTrk")
            tracks.append(self.track(position + 8, position + 8 + length))
            position += 8 + length
        if position < len(self.data):
            self.fail(position, "extra data")
        return Song(song_format, division, tracks)

    def next_byte(self):
        if self.position >= self.limit:
            self.fail(self.event_start, "truncated event")
        value = self.data[self.position]
        self.position += 1
        return value

    def quantity(self):
        start = self.position
        value = 0
        for _ in range(4):
            byte = self.next_byte()
            value = value * 128 + byte % 128
            if byte < 0x80:
                return value
        self.fail(start, "variable-length value too long")

    def payload(self):
        length = self.quantity()
        if self.limit - self.position < length:
            self.fail(self.event_start, "truncated event")
        data = list(self.data[self.position:self.position + length])
        self.position += length
        return data

    def track(self, start, end):
        self.position = start
        self.limit = end
        events = []
        tick = 0
        running = None
        while self.position < end:
            self.event_start = self.position
            if events and events[-1].is_meta("END_OF_TRACK"):
                self.fail(self.position, "event after end of track")
            tick += self.quantity()
            event = self.event(tick, running)
            running = event.status if event.is_channel() else None
            events.append(event)
        if not events or not events[-1].is_meta("END_OF_TRACK"):
            self.fail(end, "missing end of track")
        return events

    def event(self, tick, running):
        status_position = self.position
        if status_position >= self.limit:
            self.fail(self.event_start, "truncated event")
        status = self.data[status_position]
        if status < 0x80:
            if running is None:
                self.fail(status_position, "data byte without running status")
            status = running
        else:
            self.position += 1
        if status < SYSEX_STATUS:
            data = []
            for _ in range(1 if status // 16 in (0xC, 0xD) else 2):
                position = self.position
                value = self.next_byte()
                if value >= 0x80:
                    self.fail(position, "bad data byte")
                data.append(value)
            return Event(tick, status, data)
        if status in (SYSEX_STATUS, ESCAPE_STATUS):
            return Event(tick, status, self.payload())
        if status == META_STATUS:
            meta_type = self.next_byte()
            data = self.payload()
            name = META_NAMES.get(meta_type)
            if name in META_LENGTHS and len(data) != META_LENGTHS[name]:
                self.fail(status_position, "bad meta length")
            if not valid_meta_data(name, data):
                self.fail(status_position, "bad meta data")
            return Event(tick, status, data, meta_type)
        self.fail(status_position, "unknown status byte")


def number(text, low, high):
    require(re.fullmatch(r"-?[0-9]+", text) is not None)
    value = int(text)
    require(low <= value <= high)
    return value


def note_number(text):
    for pitch in range(128):
        if note_name(pitch) == text:
            return pitch
    raise LineError("bad value")


def parse_blob(fields):
    require(1 <= len(fields) <= 2)
    length = number(fields[0], 0, MAX_LENGTH)
    if len(fields) == 1:
        require(length == 0)
        return []
    text = fields[1]
    require(length > 0 and len(text) == 2 * length)
    require(re.fullmatch(r"[0-9A-F]+", text) is not None)
    return list(bytes.fromhex(text))


def parse_channel_message(tick, name, fields):
    status = 0x80 + 16 * CHANNEL_TYPES.index(name)
    if name == "PITCH_BEND":
        require(len(fields) == 2)
        channel = number(fields[0], 1, 16)
        value = number(fields[1], -8192, 8191) + 8192
        return Event(tick, status + channel - 1, [value % 128, value // 128])
    require(len(fields) == (2 if name in ("PROGRAM", "CHANNEL_PRESSURE") else 3))
    channel = number(fields[0], 1, 16)
    if name in NOTE_TYPES:
        data = [note_number(fields[1]), number(fields[2], 0, 127)]
    else:
        data = [number(text, 0, 127) for text in fields[1:]]
    return Event(tick, status + channel - 1, data)


def parse_meta_data(name, fields):
    if name in TEXT_KINDS:
        require(len(fields) == 1)
        text = fields[0]
        require(len(text) >= 2 and text[0] == '"' and text[-1] == '"')
        require('"' not in text[1:-1])
        return list(text[1:-1].encode("ascii"))
    if name == "SEQUENCER_SPECIFIC":
        return parse_blob(fields)
    if name == "END_OF_TRACK":
        require(len(fields) == 0)
        return []
    if name == "SMPTE_OFFSET":
        require(len(fields) == 5)
        return [number(text, 0, 255) for text in fields]
    if name == "TIME_SIGNATURE":
        require(len(fields) == 3)
        parts = fields[0].split("/")
        require(len(parts) == 2)
        numerator = number(parts[0], 1, 255)
        denominator = number(parts[1], 1, 64)
        require(denominator in DENOMINATORS)
        exponent = DENOMINATORS.index(denominator)
        return [numerator, exponent, number(fields[1], 0, 255), number(fields[2], 0, 255)]
    if name == "KEY_SIGNATURE":
        require(len(fields) == 2 and fields[1] in MODES)
        mode = MODES.index(fields[1])
        require(fields[0] in KEY_TABLES[mode])
        return [(KEY_TABLES[mode].index(fields[0]) - 7) % 256, mode]
    require(len(fields) == 1)
    if name == "SEQUENCE_NUMBER":
        value = number(fields[0], 0, 65535)
        return [value // 256, value % 256]
    if name == "CHANNEL_PREFIX":
        return [number(fields[0], 1, 16) - 1]
    return tempo_data(number(fields[0], 1, MAX_TEMPO))


def parse_event(tick, name, fields):
    if name in CHANNEL_TYPES:
        return parse_channel_message(tick, name, fields)
    if name == "SYSEX":
        return Event(tick, SYSEX_STATUS, parse_blob(fields))
    if name == "SYSEX_ESCAPE":
        return Event(tick, ESCAPE_STATUS, parse_blob(fields))
    if name == "META":
        require(len(fields) >= 1 and re.fullmatch(r"[0-9A-F]{2}", fields[0]) is not None)
        meta_type = int(fields[0], 16)
        require(meta_type not in META_NAMES)
        return Event(tick, META_STATUS, parse_blob(fields[1:]), meta_type)
    return Event(tick, META_STATUS, parse_meta_data(name, fields), META_CODES[name])


def valid_header(words):
    if len(words) != 4 or words[0] != "HEADER":
        return False
    song_format, count, division = (int(word) for word in words[1:])
    if song_format == 0 and count != 1:
        return False
    return 0 <= song_format <= 2 and 1 <= count <= 65535 and 1 <= division <= 32767


class TextReader:
    def __init__(self, lines):
        self.lines = lines
        self.track_count = 0
        self.tracks = [[]]

    def read(self):
        header = self.lines[0].split(" ")
        if not valid_header(header):
            raise CommandError("line 1: bad header")
        song_format, self.track_count, division = (int(word) for word in header[1:])
        for number, line in enumerate(self.lines[1:], 2):
            try:
                self.add(line)
            except LineError as error:
                raise CommandError(f"line {number}: {error}")
        if len(self.tracks) < self.track_count or not self.finished():
            raise CommandError(f"line {len(self.lines) + 1}: missing end of track")
        return Song(song_format, division, self.tracks)

    def finished(self):
        current = self.tracks[-1]
        return len(current) > 0 and current[-1].is_meta("END_OF_TRACK")

    def add(self, line):
        parts = line.split(" ", 3)
        tick = int(parts[0])
        track = int(parts[1])
        name = parts[2]
        if name not in TYPE_NAMES:
            raise LineError("unknown event type")
        if len(parts) < 4:
            fields = []
        elif name in TEXT_KINDS:
            fields = [parts[3]]
        else:
            fields = parts[3].split(" ")
        event = parse_event(tick, name, fields)
        if track >= self.track_count:
            raise LineError("bad track")
        current = len(self.tracks) - 1
        finished = self.finished()
        if track < current:
            raise LineError("out of order")
        if track > current and (not finished or track > current + 1):
            raise LineError("missing end of track")
        if track == current and finished:
            raise LineError("event after end of track")
        if track == current + 1:
            self.tracks.append([])
        elif self.tracks[-1] and tick < self.tracks[-1][-1].tick:
            raise LineError("out of order")
        self.tracks[-1].append(event)


def quantity_bytes(value):
    groups = [value % 128]
    value //= 128
    while value > 0:
        groups.append(value % 128 + 0x80)
        value //= 128
    return bytes(reversed(groups))


def encode_track(track, running_status, zero_note_off):
    body = bytearray()
    previous_tick = 0
    previous_status = None
    for event in track:
        body += quantity_bytes(event.tick - previous_tick)
        previous_tick = event.tick
        if event.is_channel():
            status = event.status
            data = event.data
            if zero_note_off and event.type_name() == "NOTE_OFF":
                status += 0x10
                data = [data[0], 0]
            if not running_status or status != previous_status:
                body.append(status)
            body += bytes(data)
            previous_status = status
        else:
            previous_status = None
            body.append(event.status)
            if event.status == META_STATUS:
                body.append(event.meta_type)
            body += quantity_bytes(len(event.data))
            body += bytes(event.data)
    return body


def encode_song(song, running_status, zero_note_off):
    data = bytearray(b"MThd") + (6).to_bytes(4, "big")
    for value in (song.format, len(song.tracks), song.division):
        data += value.to_bytes(2, "big")
    for track in song.tracks:
        body = encode_track(track, running_status, zero_note_off)
        data += b"MTrk" + len(body).to_bytes(4, "big") + body
    return data


class Workbench:
    def __init__(self):
        self.songs = {}
        self.running_status = True
        self.zero_note_off = False
        self.output = []
        self.handlers = {
            "DECODE": self.decode,
            "ENCODE": self.encode,
            "TIMING": self.timing,
            "NOTES": self.show_notes,
            "STATS": self.stats,
            "ROLL": self.roll,
            "TRANSPOSE": self.transpose,
            "QUANTIZE": self.quantize,
            "VELOCITY": self.velocity,
            "TEMPO": self.scale_tempo,
            "FILTER": self.filter_channels,
            "MERGE": self.merge,
            "SPLIT": self.split,
            "COPY": self.copy_song,
            "LIST": self.list_songs,
            "RUNNING": self.set_running,
            "NOTEOFF": self.set_note_off,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def song(self, name):
        if name not in self.songs:
            raise CommandError(f"no song {name}")
        return self.songs[name]

    def timed_song(self, name):
        song = self.song(name)
        if song.format == 2:
            raise CommandError("format 2 not supported")
        return song

    def register(self, name, song):
        self.songs[name] = song
        self.emit("loaded", name, song.summary())

    def load_hex(self, arguments, lines):
        data = bytes.fromhex(" ".join(lines))
        self.register(arguments[0], SmfParser(data).parse())

    def load_text(self, arguments, lines):
        self.register(arguments[0], TextReader(lines).read())

    def decode(self, arguments):
        song = self.song(arguments[0])
        self.emit("HEADER", song.format, len(song.tracks), song.division)
        for number, track in enumerate(song.tracks):
            for event in track:
                self.emit(event_line(event, number))

    def encode(self, arguments):
        song = self.song(arguments[0])
        data = encode_song(song, self.running_status, self.zero_note_off)
        for offset in range(0, len(data), 16):
            row = " ".join(f"{byte:02X}" for byte in data[offset:offset + 16])
            self.emit(f"{offset:04X}: {row}")
        self.emit(len(data), "bytes")

    def timing(self, arguments):
        song = self.timed_song(arguments[0])
        timeline = Timeline(song)
        for placed in song.global_order():
            tick = placed.event.tick
            self.emit(
                tick, placed.track, placed.event.type_name(),
                timeline.clock(tick), timeline.position(tick),
            )
        length = song.length()
        self.emit("end", length, timeline.clock(length), timeline.position(length))

    def show_notes(self, arguments):
        pairing = Pairing(self.song(arguments[0]))
        self.emit("notes", len(pairing.notes), "unmatched", len(pairing.unmatched))
        for note in pairing.notes:
            self.emit(note.start, note.length, note.channel, note_name(note.pitch), note.velocity)
        for placed in pairing.unmatched:
            event = placed.event
            word = "on" if event.is_note_on() else "off"
            self.emit(
                "unmatched", word, event.tick, placed.track,
                event.channel(), note_name(event.data[0]),
            )

    def stats(self, arguments):
        song = self.timed_song(arguments[0])
        pairing = Pairing(song)
        notes = pairing.notes
        self.emit(song.summary())
        self.emit("notes", len(notes), "unmatched", len(pairing.unmatched))
        for channel in sorted({note.channel for note in notes}):
            channel_notes = [note for note in notes if note.channel == channel]
            self.emit(
                "channel", channel, "notes", len(channel_notes),
                "range", pitch_range(channel_notes),
            )
        self.emit("range", pitch_range(notes) if notes else "none")
        length = song.length()
        self.emit("length", length, "ticks", Timeline(song).clock(length), "ms")
        peak, peak_tick = polyphony(notes)
        if peak == 0:
            self.emit("polyphony", 0)
        else:
            self.emit("polyphony", peak, "at", peak_tick)

    def roll(self, arguments):
        song = self.song(arguments[0])
        start = argument(arguments[1], 0, MAX_TICK)
        stop = argument(arguments[2], 1, MAX_TICK)
        step = argument(arguments[3], 1, MAX_TICK)
        columns = (stop - start + step - 1) // step
        if stop <= start or columns > MAX_COLUMNS:
            raise CommandError("bad argument")
        by_pitch = {}
        for note in Pairing(song).notes:
            by_pitch.setdefault(note.pitch, []).append(note)
        printed = False
        for pitch in sorted(by_pitch, reverse=True):
            cells = "".join(
                roll_cell(by_pitch[pitch], start + column * step, step)
                for column in range(columns)
            )
            if "#" in cells or "=" in cells:
                self.emit(f"{note_name(pitch):<4} {cells}")
                printed = True
        if not printed:
            self.emit("empty")

    def transpose(self, arguments):
        song = self.song(arguments[0])
        shift = argument(arguments[1], -127, 127)
        channel = argument(arguments[2], 1, 16) if len(arguments) == 3 else None
        kept = 0
        dropped = []
        tracks = []
        for number, track in enumerate(song.tracks):
            remaining = []
            for event in track:
                selected = channel is None or event.channel() == channel
                if event.type_name() in NOTE_TYPES and selected:
                    pitch = event.data[0] + shift
                    if not 0 <= pitch <= 127:
                        dropped.append((number, event))
                        continue
                    event.data[0] = pitch
                    kept += 1
                remaining.append(event)
            tracks.append(remaining)
        song.tracks = tracks
        self.emit("transposed", kept, "dropped", len(dropped))
        for number, event in dropped:
            self.emit(
                "dropped", event.tick, number, event.type_name(),
                event.channel(), note_name(event.data[0]),
            )

    def quantize(self, arguments):
        song = self.song(arguments[0])
        grid = argument(arguments[1], 1, 1000000)
        strength = argument(arguments[2], 0, 100)
        pairing = Pairing(song)
        targets = pairing.notes + pairing.pending
        moved = 0
        for note in targets:
            delta = quantize_delta(note.start, grid, strength)
            if delta != 0:
                moved += 1
                note.placed.event.tick += delta
                if note.off is not None:
                    note.off.tick += delta
        song.tracks = [sort_track(track) for track in song.tracks]
        self.emit("quantized", len(targets), "moved", moved)

    def velocity(self, arguments):
        song = self.song(arguments[0])
        percent = argument(arguments[1], 0, 1000)
        offset = argument(arguments[2], -127, 127)
        converted = 0
        clamped = 0
        for track in song.tracks:
            for event in track:
                if event.is_note_on():
                    value = (event.data[1] * percent + 50) // 100 + offset
                    if not 1 <= value <= 127:
                        clamped += 1
                    event.data[1] = min(127, max(1, value))
                    converted += 1
        self.emit("velocity", converted, "clamped", clamped)

    def scale_tempo(self, arguments):
        song = self.song(arguments[0])
        numerator = argument(arguments[1], 1, 1000)
        denominator = argument(arguments[2], 1, 1000)
        tempos = [event for track in song.tracks for event in track if event.is_meta("TEMPO")]
        values = [scaled_tempo(event.tempo(), numerator, denominator) for event in tempos]
        inserted = None
        if all(event.tick != 0 for event in tempos):
            inserted = scaled_tempo(DEFAULT_TEMPO, numerator, denominator)
        checked = values if inserted is None else values + [inserted]
        if any(not 1 <= value <= MAX_TEMPO for value in checked):
            raise CommandError("tempo out of range")
        for event, value in zip(tempos, values):
            event.data = tempo_data(value)
        self.emit("scaled", len(tempos))
        if inserted is not None:
            event = Event(0, META_STATUS, tempo_data(inserted), META_CODES["TEMPO"])
            song.tracks[0].insert(0, event)
            self.emit("inserted", event_line(event, 0))

    def filter_channels(self, arguments):
        song = self.song(arguments[0])
        channels = [argument(text, 1, 16) for text in arguments[1:]]
        removed = 0
        tracks = []
        for track in song.tracks:
            kept = [
                event for event in track
                if not event.is_channel() or event.channel() in channels
            ]
            removed += len(track) - len(kept)
            tracks.append(kept)
        song.tracks = tracks
        self.emit("removed", removed)

    def merge(self, arguments):
        song = self.song(arguments[0])
        if song.format != 1:
            raise CommandError("not format 1")
        count = len(song.tracks)
        events = [
            placed.event for placed in song.global_order()
            if not placed.event.is_meta("END_OF_TRACK")
        ]
        events.append(end_of_track(song.length()))
        song.tracks = [events]
        song.format = 0
        self.emit("merged", count, "tracks", "events", song.event_count())

    def split(self, arguments):
        song = self.song(arguments[0])
        if song.format != 0:
            raise CommandError("not format 0")
        original = song.tracks[0]
        events = original[:-1]
        tracks = [[event for event in events if not event.is_channel()]]
        for channel in sorted({event.channel() for event in events if event.is_channel()}):
            tracks.append([
                event for event in events
                if event.is_channel() and event.channel() == channel
            ])
        for track in tracks:
            track.append(end_of_track(original[-1].tick))
        song.tracks = tracks
        song.format = 1
        self.emit("split", "tracks", len(tracks), "events", song.event_count())

    def copy_song(self, arguments):
        name, dest = arguments
        self.songs[dest] = self.song(name).copy()
        self.emit("copied", name, "to", dest)

    def list_songs(self, arguments):
        if not self.songs:
            self.emit("no songs")
        for name in sorted(self.songs):
            self.emit(name, self.songs[name].summary())

    def set_running(self, arguments):
        word = arguments[0]
        if word not in ("ON", "OFF"):
            raise CommandError("bad argument")
        self.running_status = word == "ON"
        self.emit("running", word.lower())

    def set_note_off(self, arguments):
        word = arguments[0]
        if word not in ("ZERO", "KEEP"):
            raise CommandError("bad argument")
        self.zero_note_off = word == "ZERO"
        self.emit("noteoff", word.lower())

    def execute(self, words, lines):
        command, arguments = words[0], words[1:]
        try:
            if command == "HEX":
                self.load_hex(arguments, lines)
            elif command == "TEXT":
                self.load_text(arguments, lines)
            elif command in self.handlers:
                self.handlers[command](arguments)
            else:
                raise CommandError("unknown command")
        except CommandError as error:
            self.emit("error:", error)


def main():
    workbench = Workbench()
    count = int(sys.stdin.readline())
    for _ in range(count):
        words = sys.stdin.readline().rstrip("\n").split(" ")
        lines = []
        if words[0] in ("HEX", "TEXT"):
            lines = [sys.stdin.readline().rstrip("\n") for _ in range(int(words[2]))]
        workbench.execute(words, lines)
    sys.stdout.write("\n".join(workbench.output) + "\n")


if __name__ == "__main__":
    main()
