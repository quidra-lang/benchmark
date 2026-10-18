from fractions import Fraction
import sys


PROTOCOLS = ("SW", "GBN", "SR")
KEYS = (
    "PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY",
    "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE",
    "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL",
    "SNAPSHOT",
)
REQUIRED_KEYS = ("PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY")
LIST_KEYS = (
    "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"
)
DELAY_KEYS = ("DELAYDATA", "DELAYCTRL")
SWITCHES = ("ON", "OFF")
WORD_CHOICES = {
    "PROTOCOL": PROTOCOLS,
    "NAK": SWITCHES,
    "BACKOFF": SWITCHES,
    "CONGESTION": SWITCHES,
    "UNSAFE": SWITCHES,
    "TRACE": ("ALL", "SENDER", "RECEIVER", "NONE"),
}
INTEGER_RANGES = {
    "FRAMES": (1, 60),
    "WINDOW": (1, 32),
    "SEQBITS": (1, 6),
    "TIMEOUT": (1, 50),
    "DELAY": (1, 10),
    "INTERVAL": (0, 10),
    "MAXTICKS": (1, 2000),
    "DUPACK": (1, 10),
}
NUMBER_LIST_RANGES = {
    "LOSEDATA": (1, 9999),
    "LOSECTRL": (1, 9999),
    "CORRUPTDATA": (1, 9999),
    "CORRUPTCTRL": (1, 9999),
    "SNAPSHOT": (0, 2000),
}
TRANSMISSION_NUMBER_RANGE = (1, 9999)
EXTRA_DELAY_RANGE = (1, 50)
TRACE_SIDES = {
    "ALL": ("SENDER", "RECEIVER"),
    "SENDER": ("SENDER",),
    "RECEIVER": ("RECEIVER",),
    "NONE": (),
}
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647


class SettingsError(Exception):
    pass


def truncated(numerator, denominator, digits):
    scale = 10 ** digits
    value = numerator * scale // denominator
    return f"{value // scale}.{value % scale:0{digits}d}"


def tick_text(tick):
    return "-" if tick is None else str(tick)


def switch_text(flag):
    return "on" if flag else "off"


def in_range(value, bounds):
    low, high = bounds
    return low <= value <= high


def distinct(numbers):
    return len(set(numbers)) == len(numbers)


def delay_pair(text):
    number, extra = text.split(":")
    return int(number), int(extra)


def value_count_matches(key, count):
    if key == "RANDOM":
        return count == 3
    if key in LIST_KEYS:
        return count >= 1
    return count == 1


def valid_value(key, values):
    if key in WORD_CHOICES:
        return values[0] in WORD_CHOICES[key]
    if key in INTEGER_RANGES:
        return in_range(int(values[0]), INTEGER_RANGES[key])
    if key == "RANDOM":
        seed, loss, corruption = (int(value) for value in values)
        return (
            in_range(seed, (1, RANDOM_MODULUS - 1))
            and loss >= 0 and corruption >= 0 and loss + corruption <= 100
        )
    if key in DELAY_KEYS:
        pairs = [delay_pair(value) for value in values]
        for number, extra in pairs:
            if not in_range(number, TRANSMISSION_NUMBER_RANGE):
                return False
            if not in_range(extra, EXTRA_DELAY_RANGE):
                return False
        return distinct([number for number, _ in pairs])
    numbers = [int(value) for value in values]
    if not all(in_range(number, NUMBER_LIST_RANGES[key]) for number in numbers):
        return False
    return distinct(numbers)


def option(settings, key, default):
    return settings[key][0] if key in settings else default


def number_set(settings, key):
    return {int(value) for value in settings.get(key, [])}


def delay_map(settings, key):
    return dict(delay_pair(value) for value in settings.get(key, []))


class Config:
    def __init__(self, settings):
        self.protocol = settings["PROTOCOL"][0]
        self.frames = int(settings["FRAMES"][0])
        self.window = int(settings["WINDOW"][0])
        self.seqbits = int(settings["SEQBITS"][0])
        self.timeout = int(settings["TIMEOUT"][0])
        self.delay = int(settings["DELAY"][0])
        self.interval = int(option(settings, "INTERVAL", "0"))
        self.limit = int(option(settings, "MAXTICKS", "1000"))
        self.dupack = int(settings["DUPACK"][0]) if "DUPACK" in settings else None
        self.nak = option(settings, "NAK", "OFF") == "ON"
        self.backoff = option(settings, "BACKOFF", "OFF") == "ON"
        self.congestion = option(settings, "CONGESTION", "OFF") == "ON"
        self.unsafe = option(settings, "UNSAFE", "OFF") == "ON"
        self.trace = option(settings, "TRACE", "ALL")
        self.random = None
        if "RANDOM" in settings:
            self.random = tuple(int(value) for value in settings["RANDOM"])
        self.lose_data = number_set(settings, "LOSEDATA")
        self.lose_ctrl = number_set(settings, "LOSECTRL")
        self.corrupt_data = number_set(settings, "CORRUPTDATA")
        self.corrupt_ctrl = number_set(settings, "CORRUPTCTRL")
        self.delay_data = delay_map(settings, "DELAYDATA")
        self.delay_ctrl = delay_map(settings, "DELAYCTRL")
        self.snapshots = number_set(settings, "SNAPSHOT")

    def window_limit(self):
        if self.protocol == "SW":
            return 1
        if self.protocol == "GBN":
            return 2 ** self.seqbits - 1
        return 2 ** (self.seqbits - 1)

    def config_line(self):
        return (
            f"config: {self.protocol} n={self.frames} w={self.window} k={self.seqbits} "
            f"T={self.timeout} d={self.delay}"
        )

    def options_line(self):
        dupack = "off" if self.dupack is None else str(self.dupack)
        random = "off" if self.random is None else "/".join(str(value) for value in self.random)
        return (
            f"options: interval={self.interval} limit={self.limit} dupack={dupack} "
            f"nak={switch_text(self.nak)} backoff={switch_text(self.backoff)} "
            f"congestion={switch_text(self.congestion)} unsafe={switch_text(self.unsafe)} "
            f"trace={self.trace.lower()} random={random}"
        )


def check_settings(lines):
    settings = {}
    for key, values in lines:
        if key not in KEYS:
            raise SettingsError(f"unknown key {key}")
        if key in settings:
            raise SettingsError(f"duplicate key {key}")
        if not value_count_matches(key, len(values)):
            raise SettingsError(f"wrong number of values for {key}")
        settings[key] = values
    for key in REQUIRED_KEYS:
        if key not in settings:
            raise SettingsError(f"missing key {key}")
    for key in KEYS:
        if key in settings and not valid_value(key, settings[key]):
            raise SettingsError(f"bad value for {key}")
    config = Config(settings)
    if config.protocol == "SR" and config.dupack is not None:
        raise SettingsError("DUPACK not supported for SR")
    limit = config.window_limit()
    checked = config.protocol == "SW" or not config.unsafe
    if checked and config.window > limit:
        raise SettingsError(
            f"window {config.window} exceeds limit {limit} for {config.protocol}"
        )
    both = config.lose_data & config.corrupt_data
    if both:
        raise SettingsError(f"data #{min(both)} both lost and corrupted")
    both = config.lose_ctrl & config.corrupt_ctrl
    if both:
        raise SettingsError(f"control #{min(both)} both lost and corrupted")
    return config


class FrameRecord:
    def __init__(self):
        self.transmissions = 0
        self.first = None
        self.delivered = None
        self.acked = None


class Transmission:
    def __init__(self, number, kind, value, payload, outcome, arrival):
        self.number = number
        self.kind = kind
        self.value = value
        self.payload = payload
        self.outcome = outcome
        self.arrival = arrival


class LossGenerator:
    def __init__(self, seed, loss, corruption):
        self.state = seed
        self.loss = loss
        self.corruption = corruption

    def next_outcome(self):
        self.state = RANDOM_MULTIPLIER * self.state % RANDOM_MODULUS
        roll = self.state % 100
        if roll < self.loss:
            return "LOST"
        if roll < self.loss + self.corruption:
            return "CORRUPT"
        return "NORMAL"


class Channel:
    def __init__(self, delay, losses, corruptions, extra_delays):
        self.delay = delay
        self.losses = losses
        self.corruptions = corruptions
        self.extra_delays = extra_delays
        self.sent = 0
        self.lost = 0
        self.corrupted = 0
        self.in_transit = []

    def send(self, kind, value, payload, tick, generator):
        self.sent += 1
        number = self.sent
        outcome = "NORMAL" if generator is None else generator.next_outcome()
        if number in self.losses:
            outcome = "LOST"
        elif number in self.corruptions:
            outcome = "CORRUPT"
        arrival = tick + self.delay + self.extra_delays.get(number, 0)
        item = Transmission(number, kind, value, payload, outcome, arrival)
        self.in_transit.append(item)
        return item

    def arrivals(self, tick):
        arrived = [item for item in self.in_transit if item.arrival == tick]
        self.in_transit = [item for item in self.in_transit if item.arrival != tick]
        return arrived

    def count_damage(self, item):
        if item.outcome == "LOST":
            self.lost += 1
        else:
            self.corrupted += 1


class Simulation:
    def __init__(self, config):
        self.config = config
        self.selective = config.protocol == "SR"
        self.modulus = 2 ** config.seqbits
        self.visible = TRACE_SIDES[config.trace]
        self.generator = None if config.random is None else LossGenerator(*config.random)
        self.data_channel = Channel(
            config.delay, config.lose_data, config.corrupt_data, config.delay_data
        )
        self.control_channel = Channel(
            config.delay, config.lose_ctrl, config.corrupt_ctrl, config.delay_ctrl
        )
        self.records = [FrameRecord() for _ in range(config.frames)]
        self.lines = []
        self.tick = 0
        self.base = 0
        self.frames_sent = 0
        self.next_frame = 0
        self.timer_length = config.timeout
        self.timer = None
        self.duplicates = 0
        self.acked = [False] * config.frames
        self.timers = [None] * config.frames
        self.queue = []
        self.cwnd = 1
        self.ssthresh = config.window
        self.round_acks = 0
        self.expected = 0
        self.nak_sent = False
        self.buffer = {}
        self.resent = 0
        self.naks = 0
        self.timeouts = 0
        self.fast_retransmits = 0
        self.delivered = 0
        self.errors = 0
        self.discarded = 0
        self.max_buffer = 0
        self.completion = None

    def emit(self, *parts):
        self.lines.append(" ".join(str(part) for part in (self.tick,) + parts))

    def trace(self, side, *parts):
        if side in self.visible:
            self.emit(*parts)

    def frame_of(self, value):
        return self.base + (value - self.base) % self.modulus

    def effective_window(self):
        if self.config.congestion:
            return min(self.config.window, self.cwnd)
        return self.config.window

    def run(self):
        for tick in range(self.config.limit + 1):
            self.tick = tick
            for item in self.data_channel.arrivals(tick):
                if item.outcome == "NORMAL":
                    self.receive_data(item)
                else:
                    self.report_damage(self.data_channel, item, "RECEIVER")
            for item in self.control_channel.arrivals(tick):
                if item.outcome == "NORMAL":
                    self.receive_control(item)
                else:
                    self.report_damage(self.control_channel, item, "SENDER")
            completed = self.base == self.config.frames
            if not completed:
                self.process_timeouts()
                self.send_data()
            if tick in self.config.snapshots:
                self.snapshot()
            if completed:
                self.completion = tick
                self.emit("DONE")
                return
        self.emit("ABORT")

    def report_damage(self, channel, item, side):
        channel.count_damage(item)
        self.trace(side, item.outcome, item.kind, f"#{item.number}")

    def receive_data(self, item):
        self.trace("RECEIVER", "RECV", f"seq={item.value}", f"#{item.number}")
        if self.selective:
            self.selective_receive(item.value, item.payload)
        else:
            self.go_back_n_receive(item.value, item.payload)

    def go_back_n_receive(self, seq, payload):
        if seq == self.expected % self.modulus:
            self.deliver(payload)
            self.send_control("ack", seq)
            return
        self.discard(seq)
        if self.config.nak and not self.nak_sent:
            self.send_control("nak", self.expected % self.modulus)
            self.nak_sent = True
        elif self.expected > 0:
            self.send_control("ack", (self.expected - 1) % self.modulus)

    def selective_receive(self, seq, payload):
        window = self.config.window
        offset = (seq - self.expected) % self.modulus
        if offset >= window:
            self.discard(seq)
            if (self.expected - seq) % self.modulus <= window:
                self.send_control("ack", seq)
            return
        position = self.expected + offset
        if position in self.buffer:
            self.discard(seq)
            self.send_control("ack", seq)
        elif offset == 0:
            self.deliver(payload)
            while self.expected in self.buffer:
                self.deliver(self.buffer.pop(self.expected))
            self.send_control("ack", seq)
        else:
            self.buffer[position] = payload
            self.max_buffer = max(self.max_buffer, len(self.buffer))
            self.trace("RECEIVER", "BUFFER", f"f={position}")
            self.send_control("ack", seq)
            if self.config.nak and not self.nak_sent:
                self.send_control("nak", self.expected % self.modulus)
                self.nak_sent = True

    def deliver(self, payload):
        position = self.expected
        if payload == position:
            self.delivered += 1
            self.records[payload].delivered = self.tick
            self.trace("RECEIVER", "DELIVER", f"f={position}")
        else:
            self.errors += 1
            self.trace("RECEIVER", "DELIVER", f"f={position}", f"wrong={payload}")
        self.expected += 1
        self.nak_sent = False

    def discard(self, seq):
        self.discarded += 1
        self.trace("RECEIVER", "DISCARD", f"seq={seq}")

    def send_control(self, kind, value):
        item = self.control_channel.send(kind, value, None, self.tick, self.generator)
        if kind == "nak":
            self.naks += 1
        self.trace("RECEIVER", kind.upper(), f"a={value}", f"#{item.number}")

    def receive_control(self, item):
        before = (self.cwnd, self.ssthresh)
        if item.kind == "ack" and self.selective:
            self.selective_ack(item)
        elif item.kind == "ack":
            self.go_back_n_ack(item)
        elif self.selective:
            self.selective_nak(item)
        else:
            self.go_back_n_nak(item)
        self.report_window(before)

    def control_line(self, item, accepted):
        parts = [("GOT" if accepted else "OLD") + item.kind.upper(), f"a={item.value}"]
        parts.append(f"#{item.number}")
        if accepted:
            parts.append(f"base={self.base}")
        self.trace("SENDER", *parts)

    def go_back_n_ack(self, item):
        frame = self.frame_of(item.value)
        if frame < self.frames_sent:
            self.grow_window(frame - self.base + 1)
            self.move_base(frame + 1)
            if self.next_frame < self.base:
                self.next_frame = self.base
            if self.base == self.next_frame:
                self.timer = None
            else:
                self.timer = self.tick + self.timer_length
            self.control_line(item, True)
            return
        self.control_line(item, False)
        dupack = self.config.dupack
        if dupack is None or self.base < 1:
            return
        if item.value == (self.base - 1) % self.modulus:
            self.duplicates += 1
            if self.duplicates == dupack:
                self.fast_retransmits += 1
                self.trace("SENDER", "FASTRETX", f"f={self.base}")
                self.go_back()
                self.halve_window()

    def go_back_n_nak(self, item):
        frame = self.frame_of(item.value)
        if frame > self.frames_sent:
            self.control_line(item, False)
            return
        self.grow_window(frame - self.base)
        self.move_base(frame)
        self.go_back()
        self.halve_window()
        self.control_line(item, True)

    def selective_ack(self, item):
        frame = self.frame_of(item.value)
        if frame >= self.frames_sent or self.acked[frame]:
            self.control_line(item, False)
            return
        self.acked[frame] = True
        self.records[frame].acked = self.tick
        self.timers[frame] = None
        if frame in self.queue:
            self.queue.remove(frame)
        self.grow_window(1)
        previous = self.base
        while self.base < self.frames_sent and self.acked[self.base]:
            self.base += 1
        if self.base > previous:
            self.timer_length = self.config.timeout
        self.control_line(item, True)

    def selective_nak(self, item):
        frame = self.frame_of(item.value)
        if frame >= self.frames_sent or self.acked[frame]:
            self.control_line(item, False)
            return
        self.timers[frame] = None
        if frame not in self.queue:
            self.queue.append(frame)
        self.halve_window()
        self.control_line(item, True)

    def move_base(self, new_base):
        if new_base <= self.base:
            return
        for frame in range(self.base, new_base):
            self.records[frame].acked = self.tick
        self.base = new_base
        self.timer_length = self.config.timeout
        self.duplicates = 0

    def go_back(self):
        self.next_frame = self.base
        self.timer = None
        self.duplicates = 0

    def grow_window(self, count):
        if not self.config.congestion:
            return
        for _ in range(count):
            if self.cwnd >= self.config.window:
                continue
            if self.cwnd < self.ssthresh:
                self.cwnd += 1
            else:
                self.round_acks += 1
                if self.round_acks == self.cwnd:
                    self.cwnd += 1
                    self.round_acks = 0

    def halve_window(self):
        if self.config.congestion:
            self.ssthresh = max(self.cwnd // 2, 1)
            self.cwnd = self.ssthresh
            self.round_acks = 0

    def collapse_window(self):
        if self.config.congestion:
            self.ssthresh = max(self.cwnd // 2, 1)
            self.cwnd = 1
            self.round_acks = 0

    def report_window(self, before):
        if (self.cwnd, self.ssthresh) != before:
            self.trace("SENDER", "CWND", self.cwnd, f"ssthresh={self.ssthresh}")

    def process_timeouts(self):
        if self.selective:
            for frame in range(self.base, self.frames_sent):
                if self.timers[frame] == self.tick:
                    self.timers[frame] = None
                    self.queue.append(frame)
                    self.time_out(frame)
        elif self.timer == self.tick:
            self.time_out(self.base)
            self.go_back()

    def time_out(self, frame):
        before = (self.cwnd, self.ssthresh)
        self.timeouts += 1
        self.trace("SENDER", "TIMEOUT", f"f={frame}")
        if self.config.backoff:
            self.timer_length = min(2 * self.timer_length, 8 * self.config.timeout)
        self.collapse_window()
        self.report_window(before)

    def may_send_new(self, frame):
        return (
            frame < self.config.frames
            and frame < self.base + self.effective_window()
            and frame * self.config.interval <= self.tick
        )

    def send_data(self):
        if self.selective:
            self.selective_send()
        else:
            self.go_back_n_send()

    def go_back_n_send(self):
        frame = self.next_frame
        if frame >= self.config.frames or frame >= self.base + self.effective_window():
            return
        if frame >= self.frames_sent and frame * self.config.interval > self.tick:
            return
        self.transmit(frame)
        self.frames_sent = max(self.frames_sent, frame + 1)
        self.next_frame += 1
        if self.timer is None:
            self.timer = self.tick + self.timer_length

    def selective_send(self):
        if self.queue:
            frame = self.queue.pop(0)
        elif self.may_send_new(self.frames_sent):
            frame = self.frames_sent
            self.frames_sent += 1
        else:
            return
        self.transmit(frame)
        self.timers[frame] = self.tick + self.timer_length

    def transmit(self, frame):
        record = self.records[frame]
        seq = frame % self.modulus
        item = self.data_channel.send("data", seq, frame, self.tick, self.generator)
        record.transmissions += 1
        if record.transmissions == 1:
            record.first = self.tick
            label = "SEND"
        else:
            self.resent += 1
            label = "RESEND"
        self.trace("SENDER", label, f"f={frame}", f"seq={seq}", f"#{item.number}")

    def sender_mark(self, frame):
        if self.selective:
            acknowledged = self.acked[frame]
            waiting = frame in self.queue
            sent = frame < self.frames_sent
        else:
            acknowledged = frame < self.base
            waiting = self.next_frame <= frame < self.frames_sent
            sent = frame < self.next_frame
        if acknowledged:
            return "A"
        if waiting:
            return "R"
        if sent:
            return "O"
        if frame < self.base + self.effective_window():
            return "W"
        return "."

    def receiver_mark(self, position):
        if position < self.expected:
            return "D"
        if self.selective:
            if position in self.buffer:
                return "B"
            if position < self.expected + self.config.window:
                return "W"
        elif position == self.expected:
            return "W"
        return "."

    def snapshot(self):
        frames = range(self.config.frames)
        sender = "".join(self.sender_mark(frame) for frame in frames)
        receiver = "".join(self.receiver_mark(position) for position in frames)
        self.emit("SNAPSHOT", f"sender={sender}", f"receiver={receiver}")

    def data_count(self):
        return self.data_channel.sent

    def goodput_text(self):
        return truncated(self.delivered, self.completion, 2)

    def efficiency_text(self):
        return truncated(100 * self.delivered, self.data_count(), 1)

    def latency_text(self):
        if self.delivered == 0:
            return "-"
        total = sum(
            record.delivered - record.first
            for record in self.records if record.delivered is not None
        )
        return truncated(total, self.delivered, 2)

    def report(self):
        lines = []
        for frame, record in enumerate(self.records):
            lines.append(
                f"frame {frame}: seq={frame % self.modulus} tx={record.transmissions} "
                f"first={tick_text(record.first)} delivered={tick_text(record.delivered)} "
                f"acked={tick_text(record.acked)}"
            )
        data, control = self.data_channel, self.control_channel
        lines.append(
            f"totals: data={data.sent} resent={self.resent} control={control.sent} "
            f"nak={self.naks} timeouts={self.timeouts} fastretx={self.fast_retransmits}"
        )
        lines.append(
            f"channel: lost_data={data.lost} lost_ctrl={control.lost} "
            f"corrupt_data={data.corrupted} corrupt_ctrl={control.corrupted}"
        )
        lines.append(
            f"receiver: delivered={self.delivered} errors={self.errors} "
            f"discarded={self.discarded} max_buffer={self.max_buffer}"
        )
        if self.completion is None:
            completion = goodput = "-"
        else:
            completion = str(self.completion)
            goodput = self.goodput_text()
        utilization = truncated(100 * data.sent, self.tick + 1, 1)
        lines.append(
            f"result: completion={completion} goodput={goodput} "
            f"efficiency={self.efficiency_text()}% utilization={utilization}% "
            f"latency={self.latency_text()}"
        )
        return lines


class Scenario:
    def __init__(self, name, settings):
        self.name = name
        self.settings = settings
        self.config = None
        self.simulation = None

    def completed(self):
        return self.simulation is not None and self.simulation.completion is not None

    def status(self):
        return "invalid" if self.simulation is None else "aborted"

    def execute(self, output):
        output.append(f"== {self.name} ==")
        try:
            self.config = check_settings(self.settings)
        except SettingsError as error:
            output.append(f"error: {error}")
            return
        output.append(self.config.config_line())
        output.append(self.config.options_line())
        self.simulation = Simulation(self.config)
        self.simulation.run()
        output.extend(self.simulation.lines)
        output.extend(self.simulation.report())


def ranking_order(scenario):
    simulation = scenario.simulation
    goodput = Fraction(simulation.delivered, simulation.completion)
    efficiency = Fraction(simulation.delivered, simulation.data_count())
    return -goodput, -efficiency


def ranking_lines(scenarios):
    lines = ["== ranking =="]
    completed = sorted(
        (scenario for scenario in scenarios if scenario.completed()), key=ranking_order
    )
    for rank, scenario in enumerate(completed, 1):
        simulation = scenario.simulation
        lines.append(
            f"{rank}. {scenario.name} {scenario.config.protocol} "
            f"goodput={simulation.goodput_text()} efficiency={simulation.efficiency_text()}%"
        )
    for scenario in scenarios:
        if not scenario.completed():
            lines.append(f"- {scenario.name} {scenario.status()}")
    return lines


def protocol_lines(scenarios):
    lines = ["== protocols =="]
    for protocol in PROTOCOLS:
        runs = [
            scenario.simulation for scenario in scenarios
            if scenario.completed() and scenario.config.protocol == protocol
        ]
        if not runs:
            continue
        delivered = sum(run.delivered for run in runs)
        ticks = sum(run.completion for run in runs)
        data = sum(run.data_count() for run in runs)
        lines.append(
            f"{protocol}: runs={len(runs)} goodput={truncated(delivered, ticks, 2)} "
            f"efficiency={truncated(100 * delivered, data, 1)}%"
        )
    return lines


def read_scenarios(lines):
    count = int(lines[0])
    index = 1
    scenarios = []
    for _ in range(count):
        name = lines[index].split(" ")[1]
        index += 1
        settings = []
        while lines[index] != "END":
            key, *values = lines[index].split(" ")
            settings.append((key, values))
            index += 1
        index += 1
        scenarios.append(Scenario(name, settings))
    return scenarios


def main():
    scenarios = read_scenarios(sys.stdin.read().splitlines())
    output = []
    for scenario in scenarios:
        scenario.execute(output)
    output.extend(ranking_lines(scenarios))
    output.extend(protocol_lines(scenarios))
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
