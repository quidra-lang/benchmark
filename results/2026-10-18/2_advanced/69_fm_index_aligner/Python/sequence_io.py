"""Read ordered FASTA/FASTQ records and integer settings."""

from collections import namedtuple
from pathlib import Path


Reference = namedtuple("Reference", "name bases masked")
Read = namedtuple("Read", "name bases quality")
COMPLEMENT = str.maketrans("ACGTN", "TGCAN")


def reverse_complement(sequence):
    return sequence.translate(COMPLEMENT)[::-1]


def read_fasta(path):
    references = []
    name, parts, masked = None, [], 0
    for line in Path(path).read_text(encoding="ascii").splitlines():
        if line.startswith(">"):
            if name is not None:
                references.append(Reference(name, "".join(parts), masked))
            name = line[1:].split(" ", 1)[0]
            parts, masked = [], 0
        else:
            masked += sum(base.islower() for base in line)
            parts.append(line.upper())
    if name is not None:
        references.append(Reference(name, "".join(parts), masked))
    return references


def read_fastq(path):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    return [Read(lines[index][1:], lines[index + 1], lines[index + 3])
            for index in range(0, len(lines), 4)]


def read_inputs():
    params = {}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        name, *values = line.split()
        params[name] = tuple(map(int, values))
    return read_fasta("input/reference.fasta"), read_fastq("input/reads.fastq"), params
