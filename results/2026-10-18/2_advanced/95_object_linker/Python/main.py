from collections import Counter
from pathlib import Path
import re
import sys

from archive import read_archive, scan
from layout import Segment, align, assign_segment, find_output
from object_parser import read_lines, read_object
from relocator import TYPES, WIDTHS, calculate, unpaired_hi16
from resolver import resolve_names


class Script:
    def __init__(self, lines):
        self.segments = []
        self.loads = []
        self.kept = set()
        self.sorted = set()
        self.wrapped = set()
        self.defines = []
        self.checksum = None
        self.inputs = []
        for line in lines:
            if line.startswith("define "):
                head, expression = line.split(" = ", 1)
                self.defines.append((head.split(" ")[1], expression))
                continue
            words = line.split(" ")
            kind = words[0]
            if kind == "entry":
                self.entry = words[1]
            elif kind == "gc":
                self.gc = words[1] == "on"
            elif kind == "segment":
                self.segments.append(Segment(words[1], int(words[2], 16), int(words[3], 16),
                                             int(words[4], 16), words[5:]))
            elif kind == "load":
                self.loads.append((words[1], words[2]))
            elif kind == "keep":
                self.kept.add(words[1])
            elif kind == "sort":
                self.sorted.add(words[1])
            elif kind == "wrap":
                self.wrapped.add(words[1])
            elif kind == "checksum":
                self.checksum = words[1], words[2]
            else:
                self.inputs.append((kind, words[1:]))
        self.segment_names = {segment.name: segment for segment in self.segments}
        self.outputs = [output for segment in self.segments for output in segment.outputs]
        self.output_names = {output.name: output for output in self.outputs}
        self.script_names = {name for name, expression in self.defines}


class MergedStrings:
    def __init__(self, sections):
        self.kind = "merged"
        self.sections = sections
        self.alignment = 1
        self.address = 0
        self.contents = bytearray()
        positions = {}
        self.strings = 0
        original_size = 0
        for section in sections:
            section.merged = self
            original_size += section.size
            start = 0
            while start < section.size:
                end = section.contents.index(0, start) + 1
                string = bytes(section.contents[start:end])
                if string not in positions:
                    positions[string] = len(self.contents)
                    self.contents.extend(string)
                section.merged_positions[start] = positions[string]
                self.strings += 1
                start = end
        self.size = len(self.contents)
        self.unique = len(positions)
        self.saved = original_size - self.size


class Veneer:
    def __init__(self, output, name):
        self.kind = "veneer"
        self.output = output
        self.name = name
        self.size = 8
        self.alignment = 4
        self.address = 0


class ScriptExpression:
    def __init__(self, text, outputs, values):
        self.tokens = re.findall(r"0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+-]", text)
        self.index = 0
        self.outputs = outputs
        self.values = values

    def take(self):
        token = self.tokens[self.index]
        self.index += 1
        return token

    def expression(self):
        value = self.term()
        while self.index < len(self.tokens) and self.tokens[self.index] in ("+", "-"):
            operator = self.take()
            right = self.term()
            value = value + right if operator == "+" else value - right
        return value

    def term(self):
        token = self.take()
        if token == "(":
            value = self.expression()
            self.take()
            return value
        if token[0].isdigit():
            return int(token, 16) if token.startswith("0x") else int(token)
        if self.index == len(self.tokens) or self.tokens[self.index] != "(":
            return self.values[token]
        self.take()
        if token == "align":
            value = self.expression()
            self.take()
            alignment = self.expression()
            self.take()
            return align(value, alignment)
        output = self.outputs[self.take()]
        self.take()
        if token == "start":
            return output.address
        if token == "end":
            return output.address + output.size
        if token == "size":
            return output.size
        return output.segment.paddr + output.address - output.segment.base


class Linker:
    def __init__(self, script):
        self.script = script
        self.objects = []
        self.entries = {}
        self.archives = {}
        self.comdats = {}
        self.extractions = []
        self.orphans = Counter()
        self.script_values = {}
        self.veneers = {}
        self.far_calls = set()
        self.applied = []
        self.relocation_counts = {type_name: Counter() for type_name in TYPES}

    def defined(self, name):
        return name in self.script.script_names or any(
            entry.kind in ("defined", "common") for entry in self.entries.get(name, ()))

    def undefined(self, name):
        if self.defined(name):
            return False
        return name == self.script.entry or any(entry.kind == "undefined" and entry.binding == "global"
                                               for entry in self.entries.get(name, ()))

    def load_object(self, object_):
        object_.order = len(self.objects)
        for signature, sections in object_.comdats:
            if signature in self.comdats:
                self.comdats[signature][1].append(object_.name)
                for section in sections:
                    section.discard_reason = "comdat"
            else:
                self.comdats[signature] = object_.name, []
        for symbol in object_.symbols:
            if symbol.binding != "local" and symbol.kind == "defined" and symbol.section.discard_reason == "comdat":
                symbol.kind = "undefined"
                symbol.section = None
        for symbol in object_.symbols:
            if symbol.kind == "undefined":
                if symbol.name in self.script.wrapped:
                    symbol.name = "__wrap_" + symbol.name
                elif symbol.name.startswith("__real_") and symbol.name[7:] in self.script.wrapped:
                    symbol.name = symbol.name[7:]
        object_.symbol_names = {symbol.name: symbol for symbol in object_.symbols}
        for symbol in object_.symbols:
            if symbol.binding != "local":
                self.entries.setdefault(symbol.name, []).append(symbol)
        self.objects.append(object_)

    def extract(self, object_, reason):
        referrer = next((entry.owner.name for entry in self.entries.get(reason, ())
                         if entry.kind == "undefined" and entry.binding == "global"), "*entry*")
        self.extractions.append((object_.name, referrer, reason))
        self.load_object(object_)

    def scan_archive(self, name):
        if name not in self.archives:
            self.archives[name] = read_archive(Path("input") / name)
        return scan(self.archives[name], self.undefined, self.extract)

    def load_inputs(self):
        for kind, names in self.script.inputs:
            if kind == "object":
                self.load_object(read_object(Path("input") / names[0]))
            elif kind == "library":
                self.scan_archive(names[0])
            else:
                while True:
                    extracted = 0
                    for name in names:
                        extracted += self.scan_archive(name)
                    if extracted == 0:
                        break
        self.names = resolve_names(self.entries, self.script.script_names)
        self.commons = [resolution for resolution in self.names.values() if resolution.kind == "common"]

    def assign_outputs(self):
        self.candidates = []
        for object_ in self.objects:
            for section in object_.sections:
                if section.discard_reason == "comdat":
                    continue
                section.output = find_output(section.name, self.script.outputs)
                if section.output is None:
                    section.discard_reason = "orphan"
                    self.orphans[section.name] += 1
                else:
                    section.output.sections.append(section)
                    self.candidates.append(section)

    def target(self, symbol):
        if symbol.binding == "local":
            return symbol.section
        resolution = self.names[symbol.name]
        if resolution.kind in ("global", "weak"):
            return resolution.definition.section
        if resolution.kind == "common":
            return resolution
        return None

    def collect_garbage(self):
        units = set(self.candidates + self.commons)
        if not self.script.gc:
            for unit in units:
                unit.live = True
        else:
            pending = [section for section in self.candidates if section.output.name in self.script.kept]
            entry = self.names.get(self.script.entry)
            if entry is not None:
                if entry.kind in ("global", "weak"):
                    pending.append(entry.definition.section)
                elif entry.kind == "common":
                    pending.append(entry)
            while pending:
                unit = pending.pop()
                if unit not in units or unit.live:
                    continue
                unit.live = True
                if unit.kind == "input":
                    pending.extend(self.target(relocation.symbol) for relocation in unit.relocations)
        for section in self.candidates:
            if not section.live:
                section.discard_reason = "gc"
        for object_ in self.objects:
            unresolved = set()
            for section in object_.sections:
                if not section.live:
                    continue
                for relocation in section.relocations:
                    symbol = relocation.symbol
                    if symbol.binding != "local" and self.names[symbol.name].kind == "undefined":
                        unresolved.add(symbol.name)
            for name in unresolved:
                self.names[name].unresolved_referrers.append(object_.name)

    def build_components(self):
        for output in self.script.outputs:
            sections = [section for section in output.sections if section.live]
            if output.name in self.script.sorted:
                def priority(section):
                    return 65536 if section.name == output.name else int(section.name[len(output.name) + 1:])
                sections.sort(key=priority)
            strings = [section for section in sections if section.string]
            merged = MergedStrings(strings) if strings else None
            components = []
            inserted = False
            for section in sections:
                if section.string:
                    if not inserted:
                        components.append(merged)
                        inserted = True
                else:
                    components.append(section)
            if output.name == ".bss":
                commons = [common for common in self.commons if common.live]
                components.extend(sorted(commons, key=lambda common: (-common.alignment, common.name)))
            output.base_components = components

    def location_address(self, section, offset):
        if section.string:
            return section.merged.address + section.merged_positions[offset]
        return section.address + offset

    def definition_address(self, resolution):
        definition = resolution.definition
        return self.location_address(definition.section, definition.offset)

    def find_far_calls(self):
        calls = set()
        for section in self.candidates:
            if not section.live:
                continue
            for relocation in section.relocations:
                symbol = relocation.symbol
                if relocation.type != "CALL24" or symbol.binding == "local":
                    continue
                resolution = self.names[symbol.name]
                if resolution.kind not in ("global", "weak"):
                    continue
                value = self.definition_address(resolution) + relocation.addend - section.address - relocation.offset
                if not -2**25 <= value < 2**25:
                    calls.add(relocation)
        return calls

    def perform_layout(self):
        self.build_components()
        while True:
            for output in self.script.outputs:
                veneers = [veneer for (owner, name), veneer in self.veneers.items() if owner is output]
                output.components = output.base_components + sorted(veneers, key=lambda veneer: veneer.name)
            for segment in self.script.segments:
                assign_segment(segment)
            far_calls = self.find_far_calls()
            new_pairs = {(relocation.section.output, relocation.symbol.name) for relocation in far_calls}
            new_pairs.difference_update(self.veneers)
            if not new_pairs:
                self.far_calls = far_calls
                break
            for output, name in new_pairs:
                self.veneers[output, name] = Veneer(output, name)

    def load_addresses(self):
        storage = {segment.name: segment.base + segment.memsz for segment in self.script.segments}
        for source, destination in self.script.loads:
            segment = self.script.segment_names[source]
            segment.paddr = align(storage[destination], 4)
            storage[destination] = segment.paddr + segment.filesz
        for segment in self.script.segments:
            segment.used = storage[segment.name] - segment.base

    def evaluate_defines(self):
        for name, text in self.script.defines:
            expression = ScriptExpression(text, self.script.output_names, self.script_values)
            self.script_values[name] = expression.expression()

    def symbol_value(self, symbol):
        if symbol.binding == "local":
            return self.location_address(symbol.section, symbol.offset)
        resolution = self.names[symbol.name]
        if resolution.kind in ("global", "weak"):
            return self.definition_address(resolution)
        if resolution.kind == "common":
            return resolution.address
        if resolution.kind == "script":
            return self.script_values[resolution.name]
        if resolution.kind == "weakundef":
            return 0
        return None

    def entry_address(self):
        entry = self.names.get(self.script.entry)
        if entry is not None:
            if entry.kind in ("global", "weak"):
                return self.definition_address(entry)
            if entry.kind == "common":
                return entry.address
        return 0

    def apply_relocations(self):
        gp = self.script_values.get("_gp", 0)
        for output in self.script.outputs:
            for section in output.components:
                if section.kind != "input":
                    continue
                for index, relocation in enumerate(section.relocations):
                    relocation.place = section.address + relocation.offset
                    relocation.unpaired = unpaired_hi16(section.relocations, index)
                    relocation.symbol_value = self.symbol_value(relocation.symbol)
                    relocation.value = None
                    relocation.field = None
                    if relocation.symbol_value is None:
                        relocation.status = "undefined"
                    else:
                        relocation.status = "ok"
                        if relocation in self.far_calls:
                            veneer = self.veneers[output, relocation.symbol.name]
                            relocation.symbol_value = veneer.address
                            relocation.status = "veneer"
                        value, field, within_range = calculate(relocation.type, relocation.symbol_value,
                                                              relocation.addend, relocation.place, gp)
                        relocation.value, relocation.field = value, field
                        if not within_range:
                            relocation.status = "overflow"
                        width = WIDTHS[relocation.type]
                        section.contents[relocation.offset:relocation.offset + width] = field.to_bytes(width, "little")
                    self.relocation_counts[relocation.type][relocation.status] += 1
                    self.applied.append(relocation)

    def build_images(self):
        for segment in self.script.segments:
            segment.image = bytearray([segment.fill]) * segment.filesz
            for output in segment.outputs:
                if output.nobits:
                    continue
                for component in output.components:
                    if component.kind == "veneer":
                        destination = self.definition_address(self.names[component.name])
                        contents = bytes((4, 240, 31, 229)) + destination.to_bytes(4, "little")
                    else:
                        contents = component.contents
                    start = component.address - segment.base
                    segment.image[start:start + component.size] = contents
        if self.script.checksum is not None:
            segment_name, symbol_name = self.script.checksum
            segment = self.script.segment_names[segment_name]
            offset = self.definition_address(self.names[symbol_name]) - segment.base
            segment.image[offset:offset + 4] = bytes(4)
            total = 0
            for start in range(0, segment.filesz, 4):
                total += int.from_bytes(segment.image[start:start + 4], "little")
            segment.image[offset:offset + 4] = (-total % 2**32).to_bytes(4, "little")

    def symbol_rows(self):
        rows = []
        for name, resolution in self.names.items():
            if resolution.kind in ("global", "weak") and resolution.definition.section.live:
                rows.append((self.definition_address(resolution), name, resolution.kind, resolution.definer))
            elif resolution.kind == "common" and resolution.live:
                rows.append((resolution.address, name, "common", resolution.definer))
            elif resolution.kind == "script":
                rows.append((self.script_values[name], name, "script", "*script*"))
        for output in self.script.outputs:
            for component in output.components:
                if component.kind == "veneer":
                    rows.append((component.address, "__veneer_" + component.name, "veneer", "*linker*"))
        return sorted(rows, key=lambda row: (row[0], row[1]))

    def diagnostics(self):
        lines = []
        for name, count in sorted(self.orphans.items()):
            lines.append(f"warning: orphan section {name} discarded from {count} object(s)")
        for name, resolution in self.names.items():
            if len(resolution.strong_definers) >= 2:
                lines.append(f"error: multiple definition of {name}: " + " ".join(resolution.strong_definers))
            if resolution.commons and resolution.kind in ("global", "script"):
                lines.append(f"warning: common symbol {name} overridden by {resolution.definer}")
            pairs = {(entry.size, entry.alignment) for entry in resolution.commons}
            if resolution.kind == "common" and len(pairs) >= 2:
                lines.append(f"warning: common symbol {name} merged to size {resolution.size} align {resolution.alignment}")
        entry = self.names.get(self.script.entry)
        if entry is None or entry.kind in ("undefined", "weakundef"):
            lines.append(f"error: entry symbol {self.script.entry} is undefined")
        for name, resolution in self.names.items():
            if resolution.kind == "undefined" and resolution.unresolved_referrers:
                lines.append(f"error: undefined symbol {name} referenced by " + " ".join(resolution.unresolved_referrers))
        for segment in self.script.segments:
            if segment.used > segment.length:
                lines.append(f"error: segment {segment.name} overflows its length by {segment.used - segment.length} bytes")
        for index, first in enumerate(self.script.segments):
            for second in self.script.segments[index + 1:]:
                if (first.memsz >= 1 and second.memsz >= 1 and first.base < second.base + second.memsz
                        and second.base < first.base + first.memsz):
                    lines.append(f"error: segments {first.name} and {second.name} overlap")
        for relocation in self.applied:
            location = relocation_location(relocation)
            if relocation.unpaired:
                lines.append(f"error: unpaired HI16 at {location} against {relocation.symbol.name}")
            if relocation.status == "overflow":
                lines.append(f"error: relocation overflow at {location}: {relocation.type} "
                             f"value {relocation.value} against {relocation.symbol.name}")
        errors = sum(line.startswith("error:") for line in lines)
        warnings = sum(line.startswith("warning:") for line in lines)
        lines.append(f"errors {errors} warnings {warnings}")
        return lines

    def link(self):
        self.load_inputs()
        self.assign_outputs()
        self.collect_garbage()
        self.perform_layout()
        self.load_addresses()
        self.evaluate_defines()
        self.apply_relocations()
        self.build_images()
        return {
            "image.hex": image_dump(self),
            "flash.ihex": intel_hex(self),
            "link.map": link_map(self),
            "xref.txt": cross_references(self),
            "relocations.txt": relocation_report(self),
            "diagnostics.txt": self.diagnostics(),
        }


def relocation_location(relocation):
    return f"{relocation.section.owner.name} {relocation.section.name}+{relocation.offset}"


def segment_heading(segment):
    return (f"segment {segment.name} vaddr {segment.base:08x} paddr {segment.paddr:08x} "
            f"filesz {segment.filesz} memsz {segment.memsz}")


def image_dump(linker):
    lines = [f"entry {linker.entry_address():08x} {linker.script.entry}"]
    for segment in linker.script.segments:
        lines.append(segment_heading(segment))
        for start in range(0, segment.filesz, 16):
            chunk = segment.image[start:start + 16]
            lines.append(f"{segment.base + start:08x} " + " ".join(f"{byte:02x}" for byte in chunk))
    return lines


def hex_record(type_number, address, data):
    record = bytes((len(data), address // 256, address % 256, type_number)) + bytes(data)
    checksum = -sum(record) % 256
    return ":" + (record + bytes((checksum,))).hex().upper()


def intel_hex(linker):
    lines = []
    upper = 0
    for segment in sorted(linker.script.segments, key=lambda segment: segment.paddr):
        start = 0
        while start < segment.filesz:
            address = segment.paddr + start
            count = min(16, segment.filesz - start, 65536 - address % 65536)
            if address // 65536 != upper:
                upper = address // 65536
                lines.append(hex_record(4, 0, upper.to_bytes(2, "big")))
            lines.append(hex_record(0, address % 65536, segment.image[start:start + count]))
            start += count
    lines.append(hex_record(5, 0, linker.entry_address().to_bytes(4, "big")))
    lines.append(hex_record(1, 0, b""))
    return lines


def component_line(component):
    if component.kind == "input":
        return (f"input {component.address:08x} {component.size} {component.alignment} "
                f"{component.owner.name} {component.name}")
    if component.kind == "merged":
        return (f"merged {component.address:08x} {component.size} sections {len(component.sections)} "
                f"strings {component.strings} unique {component.unique} saved {component.saved}")
    if component.kind == "common":
        return (f"common {component.address:08x} {component.size} {component.alignment} "
                f"{component.definer} {component.name}")
    return f"veneer {component.address:08x} 8 {component.name}"


def link_map(linker):
    lines = [f"member {name} {referrer} {reason}" for name, referrer, reason in linker.extractions]
    for signature, (keeper, discarded) in linker.comdats.items():
        lines.append(f"comdat {signature} {keeper} " + (",".join(discarded) or "-"))
    for segment in linker.script.segments:
        usage = 100 * segment.used // segment.length
        lines.append(segment_heading(segment) + f" used {segment.used} length {segment.length} {usage}%")
        for output in segment.outputs:
            lines.append(f"section {output.name} {output.address:08x} {output.size} {output.alignment}")
            lines.extend(component_line(component) for component in output.components)
    for object_ in linker.objects:
        for section in object_.sections:
            if section.discard_reason is not None:
                lines.append(f"discard {object_.name} {section.name} {section.size} {section.discard_reason}")
    for common in sorted(linker.commons, key=lambda common: common.name):
        if not common.live:
            lines.append(f"discard {common.definer} COMMON({common.name}) {common.size} gc")
    for address, name, kind, definer in linker.symbol_rows():
        lines.append(f"symbol {address:08x} {name} {kind} {definer}")
    return lines


def cross_references(linker):
    lines = []
    for name, resolution in linker.names.items():
        if resolution.kind in ("global", "weak"):
            status = "kept" if resolution.definition.section.live else "discarded"
        elif resolution.kind == "common":
            status = "kept" if resolution.live else "discarded"
        elif resolution.kind == "script":
            status = "kept"
        else:
            status = "-"
        referrers = ",".join(resolution.referrers) or "-"
        lines.append(f"{name} {resolution.kind} {status} {resolution.definer} {referrers}")
    return lines


def relocation_report(linker):
    lines = []
    for relocation in linker.applied:
        prefix = (f"{relocation.place:08x} {relocation_location(relocation)} {relocation.type} "
                  f"{relocation.symbol.name} {relocation.addend}")
        if relocation.status == "undefined":
            values = "- - -"
        else:
            digits = WIDTHS[relocation.type] * 2
            values = f"{relocation.symbol_value:08x} {relocation.value} {relocation.field:0{digits}x}"
        lines.append(prefix + " " + values + " " + relocation.status)
    for type_name in TYPES:
        counts = linker.relocation_counts[type_name]
        line = f"summary {type_name} total {sum(counts.values())}"
        for status in ("ok", "veneer", "overflow", "undefined"):
            line += f" {status} {counts[status]}"
        lines.append(line)
    return lines


def main():
    sys.setrecursionlimit(1000000)
    linker = Linker(Script(read_lines(Path("input/link.txt"))))
    output = Path("output")
    output.mkdir(exist_ok=True)
    for name, lines in linker.link().items():
        (output / name).write_text("".join(line + "\n" for line in lines), encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
