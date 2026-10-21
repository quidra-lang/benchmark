import heapq
import itertools
import re
import sys
from collections import Counter
from dataclasses import dataclass
from functools import cached_property

GATE_TYPES = ('AND', 'OR', 'NAND', 'NOR', 'XOR', 'XNOR', 'NOT', 'BUF', 'MUX2', 'DFF')
INPUT_COUNTS = {
    'AND': (2, 8),
    'OR': (2, 8),
    'NAND': (2, 8),
    'NOR': (2, 8),
    'XOR': (2, 8),
    'XNOR': (2, 8),
    'NOT': (1, 1),
    'BUF': (1, 1),
    'MUX2': (3, 3),
    'DFF': (2, 2),
}
INVERTING_TYPES = {'NAND', 'NOR', 'XNOR', 'NOT'}
INVERTED = {'0': '1', '1': '0', 'X': 'X'}
VALUES = ('0', '1', 'X')
MAX_DELAY = 1000
MAX_TABLE_INPUTS = 8
OSCILLATION_LIMIT = 1000

ARGUMENT_COUNTS = {
    'BUILD': 1,
    'RESET': 0,
    'SET': 3,
    'APPLY': 2,
    'PULSE': 3,
    'CLOCK': 4,
    'RUN': 1,
    'WATCH': 1,
    'UNWATCH': 1,
    'SHOW': 0,
    'CHECK': 2,
    'PROBE': 1,
    'WAVE': 2,
    'HISTORY': 1,
    'ACTIVITY': 1,
    'STATUS': 0,
    'MODULES': 0,
    'NETLIST': 1,
    'HIERARCHY': 1,
    'STATS': 1,
    'TRUTHTABLE': 1,
    'EQUIV': 2,
    'FAULTS': 1,
    'CRITICAL': 1,
    'PERIOD': 1,
}
# These commands accept the listed number of arguments or more.
VARIADIC_COMMANDS = {'WATCH', 'UNWATCH', 'SHOW'}
SIMULATION_COMMANDS = {
    'RESET', 'SET', 'APPLY', 'PULSE', 'CLOCK', 'RUN', 'WATCH', 'UNWATCH',
    'SHOW', 'CHECK', 'PROBE', 'WAVE', 'HISTORY', 'ACTIVITY', 'STATUS',
}
BLOCKED_WHEN_HALTED = {'SET', 'APPLY', 'PULSE', 'CLOCK', 'RUN'}

NAME_PATTERN = re.compile(r'[a-z][a-z0-9_]{0,15}')
MODULE_NAME_PATTERN = re.compile(r'[A-Z][A-Z0-9_]{0,15}')
NUMBER_PATTERN = re.compile(r'0|[1-9][0-9]{0,8}')


class InputError(Exception):
    pass


def is_name(word):
    return NAME_PATTERN.fullmatch(word) is not None


def is_number(word):
    return NUMBER_PATTERN.fullmatch(word) is not None


def parse_number(word):
    if not is_number(word):
        raise InputError(f'bad number {word}')
    return int(word)


def parse_positive(word):
    value = parse_number(word)
    if value == 0:
        raise InputError(f'bad number {word}')
    return value


def parse_value(word):
    if word not in VALUES:
        raise InputError(f'bad value {word}')
    return word


def bit_string(row, width):
    return ''.join('1' if (row >> (width - 1 - i)) & 1 else '0' for i in range(width))


def trace_path(previous, end):
    path = [end]
    while path[-1] in previous:
        path.append(previous[path[-1]])
    return ' -> '.join(reversed(path))


def gate_value(kind, values):
    if kind in ('AND', 'NAND'):
        result = '0' if '0' in values else 'X' if 'X' in values else '1'
    elif kind in ('OR', 'NOR'):
        result = '1' if '1' in values else 'X' if 'X' in values else '0'
    elif kind in ('XOR', 'XNOR'):
        result = 'X' if 'X' in values else str(values.count('1') % 2)
    elif kind == 'MUX2':
        select, first, second = values
        if select == 'X':
            result = first if first == second else 'X'
        else:
            result = first if select == '0' else second
    else:
        result = values[0]
    return INVERTED[result] if kind in INVERTING_TYPES else result


@dataclass
class Gate:
    name: str
    kind: str
    inputs: list
    output: str
    delay: int


@dataclass
class Module:
    name: str
    inputs: list
    outputs: list
    body: list

    @cached_property
    def circuit(self):
        return Circuit(self)


@dataclass
class Instance:
    name: str
    module: Module
    connections: dict


def expand(module, prefix, ports, gates):
    def actual(signal):
        return ports.get(signal, prefix + signal)

    for item in module.body:
        if isinstance(item, Gate):
            inputs = [actual(signal) for signal in item.inputs]
            output = actual(item.output)
            gates.append(Gate(prefix + item.name, item.kind, inputs, output, item.delay))
        else:
            mapping = {port: actual(signal) for port, signal in item.connections.items()}
            expand(item.module, f'{prefix}{item.name}.', mapping, gates)


class Circuit:
    def __init__(self, module):
        self.name = module.name
        self.inputs = module.inputs
        self.outputs = module.outputs
        self.gates = []
        expand(module, '', {}, self.gates)
        self.signals = self.inputs + [gate.output for gate in self.gates]
        self.driver = {gate.output: gate for gate in self.gates}
        self.readers = {signal: [] for signal in self.signals}
        for gate in self.gates:
            for signal in dict.fromkeys(gate.inputs):
                self.readers[signal].append(gate)
        self.flip_flops = [gate for gate in self.gates if gate.kind == 'DFF']
        self.order = self.combinational_order()

    def combinational_order(self):
        # Topological order of the non-DFF gates, or None if they contain a loop.
        waiting = {}
        ready = []
        for gate in self.gates:
            if gate.kind == 'DFF':
                continue
            sources = {
                signal
                for signal in gate.inputs
                if signal in self.driver and self.driver[signal].kind != 'DFF'
            }
            waiting[gate.output] = len(sources)
            if not sources:
                ready.append(gate)
        order = []
        while ready:
            gate = ready.pop()
            order.append(gate)
            for reader in self.readers[gate.output]:
                if reader.kind != 'DFF':
                    waiting[reader.output] -= 1
                    if waiting[reader.output] == 0:
                        ready.append(reader)
        return order if len(order) == len(waiting) else None

    def depth(self):
        levels = dict.fromkeys(self.inputs, 0)
        levels.update(dict.fromkeys((gate.output for gate in self.flip_flops), 0))
        for gate in self.order:
            levels[gate.output] = max(levels[signal] for signal in gate.inputs) + 1
        return max(levels.values())

    def evaluate(self, bits, fault=None):
        stuck_signal, stuck_value = fault or (None, None)
        values = dict(zip(self.inputs, bits))
        if stuck_signal in values:
            values[stuck_signal] = stuck_value
        for gate in self.order:
            if gate.output == stuck_signal:
                values[gate.output] = stuck_value
            else:
                values[gate.output] = gate_value(gate.kind, [values[s] for s in gate.inputs])
        return ''.join(values[signal] for signal in self.outputs)

    def arrival_times(self, sources):
        latest = dict(sources)
        earliest = dict(sources)
        previous = {}
        for gate in self.order:
            arrived = [signal for signal in gate.inputs if signal in latest]
            if arrived:
                source = max(arrived, key=latest.get)
                latest[gate.output] = latest[source] + gate.delay
                earliest[gate.output] = min(earliest[signal] for signal in arrived) + gate.delay
                previous[gate.output] = source
        return latest, earliest, previous


def combinational_circuit(module):
    circuit = module.circuit
    if circuit.flip_flops:
        raise InputError(f'{module.name} is not combinational')
    if circuit.order is None:
        raise InputError(f'{module.name} has a combinational loop')
    if len(circuit.inputs) > MAX_TABLE_INPUTS:
        raise InputError(f'too many inputs {len(circuit.inputs)}')
    return circuit


def detecting_row(circuit, rows, expected, fault):
    for row, bits in enumerate(rows):
        if circuit.evaluate(bits, fault) != expected[row]:
            return row
    return None


def print_hierarchy(module, depth):
    for item in module.body:
        if isinstance(item, Instance):
            print('  ' * depth + f'{item.name} {item.module.name}')
            print_hierarchy(item.module, depth + 1)


def check_gate_line(words, driven, used_names):
    if len(words) < 5 or words[-3] != '->' or words.count('->') != 1:
        raise InputError('bad gate syntax')
    kind, name = words[0], words[1]
    inputs, output, delay = words[2:-3], words[-2], words[-1]
    if not is_name(name):
        raise InputError(f'bad name {name}')
    low, high = INPUT_COUNTS[kind]
    if not low <= len(inputs) <= high:
        raise InputError(f'bad input count {len(inputs)} for {kind}')
    for signal in inputs + [output]:
        if not is_name(signal):
            raise InputError(f'bad name {signal}')
    if not is_number(delay) or int(delay) > MAX_DELAY:
        raise InputError(f'bad delay {delay}')
    if name in used_names:
        raise InputError(f'duplicate name {name}')
    if output in driven:
        raise InputError(f'multiple drivers for {output}')
    used_names.add(name)
    driven.add(output)
    return Gate(name, kind, inputs, output, int(delay))


class Simulation:
    def __init__(self, circuit):
        self.circuit = circuit
        self.watch = []
        self.reset()

    def reset(self):
        self.values = dict.fromkeys(self.circuit.signals, 'X')
        self.time = 0
        self.queue = []
        self.sequence = itertools.count()
        self.history = {signal: [] for signal in self.circuit.signals}
        self.processed = 0
        self.halted = False

    def schedule(self, time, signal, value):
        heapq.heappush(self.queue, (time, next(self.sequence), signal, value))

    def assign(self, time, signal, value):
        previous = self.values[signal]
        self.values[signal] = value
        for gate in self.circuit.readers[signal]:
            if gate.kind != 'DFF':
                inputs = [self.values[source] for source in gate.inputs]
                self.schedule(time + gate.delay, gate.output, gate_value(gate.kind, inputs))
            elif signal == gate.inputs[0] and previous == '0' and value == '1':
                self.schedule(time + gate.delay, gate.output, self.values[gate.inputs[1]])

    def step(self, time):
        # Returns the numbers of events and glitches, or None when the step oscillates.
        original = {}
        events = 0
        while self.queue and self.queue[0][0] == time:
            if events == OSCILLATION_LIMIT:
                return None
            _, _, signal, value = heapq.heappop(self.queue)
            events += 1
            self.processed += 1
            if self.values[signal] != value:
                original.setdefault(signal, self.values[signal])
                self.assign(time, signal, value)
        glitches = 0
        for signal, start in original.items():
            if self.values[signal] == start:
                glitches += 1
            else:
                self.history[signal].append((time, self.values[signal]))
        for signal in self.watch:
            if signal in original and self.values[signal] != original[signal]:
                print(f'{time} {signal} {self.values[signal]}')
        return events, glitches

    def run(self, end):
        events = 0
        glitches = 0
        while self.queue and self.queue[0][0] < end:
            time = self.queue[0][0]
            result = self.step(time)
            if result is None:
                print(f'halted: oscillation at time {time}')
                self.queue.clear()
                self.time = time
                self.halted = True
                return
            events += result[0]
            glitches += result[1]
        self.time = end
        print(f'run {end} events {events} glitches {glitches} pending {len(self.queue)}')

    def waveform(self, signal, start, end):
        changes = self.history[signal]
        value = 'X'
        index = 0
        characters = []
        for time in range(start, end):
            while index < len(changes) and changes[index][0] <= time:
                value = changes[index][1]
                index += 1
            characters.append(value)
        return ''.join(characters)

    def describe(self, signals):
        return [f'{signal}={self.values[signal]}' for signal in signals]


class Simulator:
    def __init__(self):
        self.modules = {}
        self.simulation = None

    def define_module(self, header_no, header, body_lines):
        line_no = header_no
        try:
            name, inputs, outputs = self.check_header(header.split(' '))
            driven = set(inputs)
            used_names = set()
            body = []
            reads = []
            for line_no, line in enumerate(body_lines, header_no + 1):
                words = line.split(' ')
                if words[0] in GATE_TYPES:
                    item = check_gate_line(words, driven, used_names)
                    reads.extend((line_no, signal) for signal in item.inputs)
                elif words[0] == 'INST':
                    item = self.check_instance_line(words, driven, used_names)
                    reads.extend(
                        (line_no, signal)
                        for port, signal in item.connections.items()
                        if port in item.module.inputs
                    )
                else:
                    raise InputError(f'unknown statement {words[0]}')
                body.append(item)
            reads.extend((header_no, signal) for signal in outputs)
            for line_no, signal in reads:
                if signal not in driven:
                    raise InputError(f'undriven signal {signal}')
        except InputError as error:
            print(f'error: line {line_no}: {error}')
            return
        self.modules[name] = Module(name, inputs, outputs, body)
        gate_count = sum(isinstance(item, Gate) for item in body)
        print(
            f'defined {name} inputs {len(inputs)} outputs {len(outputs)} '
            f'gates {gate_count} instances {len(body) - gate_count}'
        )

    def check_header(self, words):
        if (
            len(words) < 5
            or words[2] != 'IN'
            or words[3:].count('OUT') != 1
            or words[-1] == 'OUT'
        ):
            raise InputError('bad module header')
        name = words[1]
        if not MODULE_NAME_PATTERN.fullmatch(name):
            raise InputError(f'bad module name {name}')
        if name in self.modules:
            raise InputError(f'duplicate module {name}')
        split = words.index('OUT', 3)
        inputs, outputs = words[3:split], words[split + 1 :]
        seen = set()
        for port in inputs + outputs:
            if not is_name(port):
                raise InputError(f'bad name {port}')
            if port in seen:
                raise InputError(f'duplicate port {port}')
            seen.add(port)
        return name, inputs, outputs

    def check_instance_line(self, words, driven, used_names):
        if len(words) < 3:
            raise InputError('bad instance syntax')
        name, module_name = words[1], words[2]
        if not is_name(name):
            raise InputError(f'bad name {name}')
        module = self.modules.get(module_name)
        if module is None:
            raise InputError(f'unknown module {module_name}')
        connections = {}
        for word in words[3:]:
            port, _, signal = word.partition('=')
            if word.count('=') != 1 or not port or not signal:
                raise InputError(f'bad connection {word}')
            if port not in module.inputs and port not in module.outputs:
                raise InputError(f'unknown port {port}')
            if port in connections:
                raise InputError(f'duplicate connection {port}')
            if not is_name(signal):
                raise InputError(f'bad name {signal}')
            connections[port] = signal
        for port in module.inputs:
            if port not in connections:
                raise InputError(f'unconnected input {port}')
        if name in used_names:
            raise InputError(f'duplicate name {name}')
        for port, signal in connections.items():
            if port in module.outputs:
                if signal in driven:
                    raise InputError(f'multiple drivers for {signal}')
                driven.add(signal)
        used_names.add(name)
        return Instance(name, module, connections)

    def execute(self, line_no, words):
        name, arguments = words[0], words[1:]
        try:
            if name not in ARGUMENT_COUNTS:
                raise InputError(f'unknown command {name}')
            expected = ARGUMENT_COUNTS[name]
            if len(arguments) < expected or (
                name not in VARIADIC_COMMANDS and len(arguments) != expected
            ):
                raise InputError('wrong argument count')
            if name in SIMULATION_COMMANDS and self.simulation is None:
                raise InputError('no circuit')
            if name in BLOCKED_WHEN_HALTED and self.simulation.halted:
                raise InputError('simulation halted')
            getattr(self, f'command_{name.lower()}')(*arguments)
        except InputError as error:
            print(f'error: line {line_no}: {error}')

    def lookup(self, name):
        if name not in self.modules:
            raise InputError(f'unknown module {name}')
        return self.modules[name]

    def require_signal(self, signal):
        if signal not in self.simulation.values:
            raise InputError(f'unknown signal {signal}')

    def require_input(self, signal):
        if signal not in self.simulation.circuit.inputs:
            raise InputError(f'not an input {signal}')

    def parse_time(self, word):
        time = parse_number(word)
        if time < self.simulation.time:
            raise InputError(f'time {time} is in the past')
        return time

    def print_watch_list(self):
        print('watching', ' '.join(self.simulation.watch) or 'nothing')

    def command_modules(self):
        print(f'modules {len(self.modules)}')
        for module in self.modules.values():
            print(
                f'{module.name} inputs {len(module.inputs)} outputs {len(module.outputs)} '
                f'gates {len(module.circuit.gates)}'
            )

    def command_netlist(self, name):
        circuit = self.lookup(name).circuit
        print(f'netlist {name} gates {len(circuit.gates)} signals {len(circuit.signals)}')
        for gate in circuit.gates:
            print(gate.name, gate.kind, *gate.inputs, '->', gate.output, gate.delay)

    def command_hierarchy(self, name):
        module = self.lookup(name)
        print(name)
        print_hierarchy(module, 1)

    def command_stats(self, name):
        circuit = self.lookup(name).circuit
        depth = '-' if circuit.order is None else circuit.depth()
        print(
            f'stats {name} gates {len(circuit.gates)} signals {len(circuit.signals)} '
            f'depth {depth}'
        )
        counts = Counter(gate.kind for gate in circuit.gates)
        print('types', *(f'{kind} {counts[kind]}' for kind in GATE_TYPES if counts[kind]))
        busiest = max(circuit.signals, key=lambda signal: len(circuit.readers[signal]))
        print(f'max fanout {busiest} {len(circuit.readers[busiest])}')

    def command_truthtable(self, name):
        circuit = combinational_circuit(self.lookup(name))
        width = len(circuit.inputs)
        print(*circuit.inputs, '|', *circuit.outputs)
        for row in range(2**width):
            bits = bit_string(row, width)
            print(*bits, '|', *circuit.evaluate(bits))

    def command_equiv(self, first_name, second_name):
        first_module = self.lookup(first_name)
        second_module = self.lookup(second_name)
        first = combinational_circuit(first_module)
        second = combinational_circuit(second_module)
        if len(first.inputs) != len(second.inputs) or len(first.outputs) != len(second.outputs):
            raise InputError('port mismatch')
        width = len(first.inputs)
        for row in range(2**width):
            bits = bit_string(row, width)
            first_values = first.evaluate(bits)
            second_values = second.evaluate(bits)
            if first_values != second_values:
                print(f'not equivalent at {bits}: {first_values} vs {second_values}')
                return
        print('equivalent')

    def command_faults(self, name):
        circuit = combinational_circuit(self.lookup(name))
        width = len(circuit.inputs)
        rows = [bit_string(row, width) for row in range(2**width)]
        expected = [circuit.evaluate(bits) for bits in rows]
        undetected = []
        test_rows = set()
        for signal in circuit.signals:
            for value in '01':
                row = detecting_row(circuit, rows, expected, (signal, value))
                if row is None:
                    undetected.append(f'{signal}/{value}')
                else:
                    test_rows.add(row)
        total = 2 * len(circuit.signals)
        print(f'faults {total} detected {total - len(undetected)}')
        for fault in undetected:
            print(f'undetected {fault}')
        print('tests', *(rows[row] for row in sorted(test_rows)))

    def command_critical(self, name):
        circuit = self.lookup(name).circuit
        if circuit.order is None:
            raise InputError(f'{name} has a combinational loop')
        latest, earliest, previous = circuit.arrival_times(dict.fromkeys(circuit.inputs, 0))
        reached = []
        for port in circuit.outputs:
            if port in latest:
                print(f'{port} min {earliest[port]} max {latest[port]}')
                reached.append(port)
            else:
                print(f'{port} unreachable')
        if reached:
            end = max(reached, key=latest.get)
            print(f'critical {latest[end]}: {trace_path(previous, end)}')
        else:
            print('critical none')

    def command_period(self, name):
        circuit = self.lookup(name).circuit
        if not circuit.flip_flops:
            raise InputError(f'{name} has no flip-flops')
        if circuit.order is None:
            raise InputError(f'{name} has a combinational loop')
        sources = {gate.output: gate.delay for gate in circuit.flip_flops}
        latest, _, previous = circuit.arrival_times(sources)
        data_inputs = [gate.inputs[1] for gate in circuit.flip_flops if gate.inputs[1] in latest]
        count = len(circuit.flip_flops)
        if data_inputs:
            end = max(data_inputs, key=latest.get)
            print(f'flip-flops {count} period {latest[end]}: {trace_path(previous, end)}')
        else:
            print(f'flip-flops {count} period none')

    def command_build(self, name):
        circuit = self.lookup(name).circuit
        self.simulation = Simulation(circuit)
        print(f'built {name} signals {len(circuit.signals)} gates {len(circuit.gates)}')

    def command_reset(self):
        self.simulation.reset()
        print('reset')

    def command_set(self, time_word, signal, value):
        time = self.parse_time(time_word)
        self.require_input(signal)
        parse_value(value)
        self.simulation.schedule(time, signal, value)
        print(f'set {signal} {value} at {time}')

    def command_apply(self, time_word, bits):
        time = self.parse_time(time_word)
        inputs = self.simulation.circuit.inputs
        if len(bits) != len(inputs) or any(bit not in VALUES for bit in bits):
            raise InputError(f'bad vector {bits}')
        for signal, bit in zip(inputs, bits):
            self.simulation.schedule(time, signal, bit)
        print(f'apply {bits} at {time}')

    def command_pulse(self, signal, time_word, width_word):
        self.require_input(signal)
        time = self.parse_time(time_word)
        width = parse_positive(width_word)
        self.simulation.schedule(time, signal, '1')
        self.simulation.schedule(time + width, signal, '0')
        print(f'pulse {signal} {time} {time + width}')

    def command_clock(self, signal, start_word, half_word, count_word):
        self.require_input(signal)
        start = self.parse_time(start_word)
        half = parse_positive(half_word)
        count = parse_positive(count_word)
        for i in range(count):
            self.simulation.schedule(start + i * half, signal, '1' if i % 2 else '0')
        print(f'clock {signal} events {count} last {start + (count - 1) * half}')

    def command_run(self, time_word):
        end = parse_number(time_word)
        if end <= self.simulation.time:
            raise InputError(f'time {end} is not after {self.simulation.time}')
        self.simulation.run(end)

    def command_watch(self, *signals):
        watch = self.simulation.watch
        for i, signal in enumerate(signals):
            self.require_signal(signal)
            if signal in watch or signal in signals[:i]:
                raise InputError(f'already watched {signal}')
        watch.extend(signals)
        self.print_watch_list()

    def command_unwatch(self, *signals):
        simulation = self.simulation
        for i, signal in enumerate(signals):
            self.require_signal(signal)
            if signal not in simulation.watch or signal in signals[:i]:
                raise InputError(f'not watched {signal}')
        simulation.watch = [signal for signal in simulation.watch if signal not in signals]
        self.print_watch_list()

    def command_show(self, *signals):
        simulation = self.simulation
        for signal in signals:
            self.require_signal(signal)
        if signals:
            print(*simulation.describe(signals))
        else:
            circuit = simulation.circuit
            print(*simulation.describe(circuit.inputs), '|', *simulation.describe(circuit.outputs))

    def command_check(self, signal, value):
        self.require_signal(signal)
        parse_value(value)
        actual = self.simulation.values[signal]
        if actual == value:
            print(f'check {signal}={value} ok')
        else:
            print(f'check {signal}={value} failed ({actual})')

    def command_probe(self, signal):
        self.require_signal(signal)
        simulation = self.simulation
        circuit = simulation.circuit
        value = simulation.values[signal]
        if signal in circuit.inputs:
            print(f'{signal}={value} driven by input')
        else:
            gate = circuit.driver[signal]
            pins = ' '.join(simulation.describe(gate.inputs))
            print(f'{signal}={value} driven by {gate.name} {gate.kind} {pins} delay {gate.delay}')
        readers = circuit.readers[signal]
        print('fanout', len(readers), *(gate.name for gate in readers))

    def command_wave(self, start_word, end_word):
        simulation = self.simulation
        start = parse_number(start_word)
        end = parse_number(end_word)
        if not start < end <= simulation.time:
            raise InputError(f'bad range {start} {end}')
        if not simulation.watch:
            raise InputError('nothing watched')
        for signal in simulation.watch:
            print(signal, simulation.waveform(signal, start, end))

    def command_history(self, signal):
        self.require_signal(signal)
        changes = self.simulation.history[signal]
        records = (f'{time}:{value}' for time, value in changes)
        print('history', signal, 'changes', len(changes), *records)

    def command_activity(self, count_word):
        count = parse_positive(count_word)
        history = self.simulation.history
        ranked = sorted(history, key=lambda signal: (-len(history[signal]), signal))
        for signal in ranked[:count]:
            print(signal, len(history[signal]))

    def command_status(self):
        simulation = self.simulation
        halted = 'yes' if simulation.halted else 'no'
        print(
            f'circuit {simulation.circuit.name} time {simulation.time} '
            f'pending {len(simulation.queue)} events {simulation.processed} halted {halted}'
        )
        counts = Counter(simulation.values.values())
        print(f'values 0:{counts["0"]} 1:{counts["1"]} X:{counts["X"]}')


def main():
    lines = sys.stdin.read().splitlines()
    simulator = Simulator()
    index = 0
    while lines[index] != 'END':
        words = lines[index].split(' ')
        if words[0] == 'MODULE':
            end = lines.index('ENDMODULE', index)
            simulator.define_module(index + 1, lines[index], lines[index + 1 : end])
            index = end + 1
        else:
            simulator.execute(index + 1, words)
            index += 1


if __name__ == '__main__':
    main()
