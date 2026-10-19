from object_parser import belongs, is_nobits


def align(value, alignment):
    return (value + alignment - 1) // alignment * alignment


class OutputSection:
    def __init__(self, name, segment):
        self.name = name
        self.segment = segment
        self.nobits = is_nobits(name)
        self.sections = []
        self.base_components = []
        self.components = []
        self.address = 0
        self.size = 0
        self.alignment = 1


class Segment:
    def __init__(self, name, base, length, fill, output_names):
        self.name = name
        self.base = base
        self.length = length
        self.fill = fill
        self.outputs = [OutputSection(output, self) for output in output_names]
        self.paddr = base
        self.filesz = 0
        self.memsz = 0
        self.used = 0
        self.image = bytearray()


def find_output(section_name, outputs):
    return next((output for output in outputs if belongs(section_name, output.name)), None)


def assign_segment(segment):
    cursor = segment.base
    segment.filesz = 0
    for output in segment.outputs:
        output.alignment = max((component.alignment for component in output.components), default=1)
        cursor = align(cursor, output.alignment)
        output.address = cursor
        for component in output.components:
            cursor = align(cursor, component.alignment)
            component.address = cursor
            cursor += component.size
        output.size = cursor - output.address
        if not output.nobits:
            segment.filesz = cursor - segment.base
    segment.memsz = cursor - segment.base
