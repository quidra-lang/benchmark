import re
import sys


BASES = "ACGT"
IUPAC = {
    "A": "A", "C": "C", "G": "G", "T": "T", "R": "AG",
    "Y": "CT", "W": "AT", "S": "CG", "K": "GT", "M": "AC",
    "B": "CGT", "D": "AGT", "H": "ACT", "V": "ACG", "N": "ACGT",
}
SYMBOL = {bases: symbol for symbol, bases in IUPAC.items()}
COMPLEMENT = str.maketrans("ACGTRYWSKMBVDHN", "TGCAYRWSMKVBHDN")
CODE_GROUPS = {
    "A": "GCT GCC GCA GCG", "C": "TGT TGC", "D": "GAT GAC",
    "E": "GAA GAG", "F": "TTT TTC", "G": "GGT GGC GGA GGG",
    "H": "CAT CAC", "I": "ATT ATC ATA", "K": "AAA AAG",
    "L": "TTA TTG CTT CTC CTA CTG", "M": "ATG", "N": "AAT AAC",
    "P": "CCT CCC CCA CCG", "Q": "CAA CAG",
    "R": "CGT CGC CGA CGG AGA AGG", "S": "TCT TCC TCA TCG AGT AGC",
    "T": "ACT ACC ACA ACG", "V": "GTT GTC GTA GTG", "W": "TGG",
    "Y": "TAT TAC", "*": "TAA TAG TGA",
}
CODE = {codon: amino for amino, codons in CODE_GROUPS.items() for codon in codons.split()}
AMINO_MASS = dict(zip(
    "ACDEFGHIKLMNPQRSTVWY",
    (71079, 103139, 115089, 129116, 147177, 57052, 137141,
     113160, 128174, 113160, 131193, 114104, 97117, 128131,
     156188, 87078, 101105, 99133, 186213, 163176),
))
BASE_MASS = dict(zip(BASES, (331222, 307197, 347221, 322208)))
ENZYMES = {
    "EcoRI": ("GAATTC", 1), "BamHI": ("GGATCC", 1),
    "HindIII": ("AAGCTT", 1), "PstI": ("CTGCAG", 5),
    "SmaI": ("CCCGGG", 3), "KpnI": ("GGTACC", 5),
    "XbaI": ("TCTAGA", 1), "NotI": ("GCGGCCGC", 2),
    "EcoRV": ("GATATC", 3), "HaeIII": ("GGCC", 2),
    "AluI": ("AGCT", 2), "TaqI": ("TCGA", 1),
    "Sau3AI": ("GATC", 0), "HincII": ("GTYRAC", 3),
    "AvaI": ("CYCGRG", 1),
}
ARITY = {
    "SEQ": (2, 2), "SLICE": (4, 4), "JOIN": (3, 9),
    "MUTATE": (3, 3), "DEL": (1, 1), "LIST": (0, 0),
    "REVCOMP": (1, 1), "COMPLEMENT": (1, 1), "REVERSE": (1, 1),
    "TRANSCRIBE": (1, 1), "TRANSLATE": (2, 2), "CODONS": (2, 2),
    "PROTEIN": (2, 2), "ORFS": (2, 2), "GC": (1, 1),
    "GCWINDOW": (3, 3), "SKEW": (1, 1), "KMERS": (3, 3),
    "FIND": (2, 2), "RESTRICT": (2, 7), "PALINDROMES": (3, 3),
    "REPEATS": (4, 4), "HAMMING": (2, 2), "ALIGN": (6, 6),
    "CONSENSUS": (2, 10), "TM": (1, 1), "MASS": (1, 1),
    "PRIMER": (1, 1), "FOLD": (2, 2), "ASSEMBLE": (4, 10),
    "PACK": (1, 1), "UNPACK": (3, 3),
}


class CommandError(Exception):
    pass


def revcomp(sequence):
    return sequence.translate(COMPLEMENT)[::-1]


def gc(sequence):
    return sequence.count("G") + sequence.count("C")


def fixed(value, places):
    scale = 10 ** places
    return f"{value // scale}.{value % scale:0{places}d}"


def pct(a, b):
    return fixed(10000 * a // b, 2)


def transition(a, b):
    return a != b and (a + b in ("AG", "GA", "CT", "TC"))


def counts(sequence):
    result = {}
    for item in sequence:
        result[item] = result.get(item, 0) + 1
    return result


def frequency_order(table):
    return sorted(table, key=lambda item: (-table[item], item))


def codons(sequence, frame):
    strand = sequence if frame > 0 else revcomp(sequence)
    start = abs(frame) - 1
    return [strand[i:i + 3] for i in range(start, len(strand) - 2, 3)]


def occurrences(sequence, motif):
    return [
        i + 1 for i in range(len(sequence) - len(motif) + 1)
        if all(base in IUPAC[symbol] for base, symbol in zip(sequence[i:], motif))
    ]


def repeat_count(sequence, start, width):
    unit = sequence[start:start + width]
    count = 0
    while sequence[start + count * width:start + (count + 1) * width] == unit:
        count += 1
    return count


def primitive(unit):
    return all(
        len(unit) % width != 0 or unit[:width] * (len(unit) // width) != unit
        for width in range(1, len(unit))
    )


def longest_palindrome(sequence):
    best = 0
    for center in range(1, len(sequence)):
        left, right = center - 1, center
        while left >= 0 and right < len(sequence) and revcomp(sequence[left]) == sequence[right]:
            best = max(best, right - left + 1)
            left -= 1
            right += 1
    return best


def temperature(sequence):
    n = len(sequence)
    amount = gc(sequence)
    if n < 14:
        return 10 * (2 * (n - amount) + 4 * amount)
    return (649 * n + 410 * amount - 6724) // n


def strand_mass(sequence):
    return sum(BASE_MASS[base] for base in sequence) - (len(sequence) - 1) * 18015


class Toolkit:
    def __init__(self):
        self.registry = {}
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def emit_list(self, label, values):
        self.emit(label, *(values if values else ["none"]))

    def number(self, text, minimum, maximum, nonzero=False):
        if not re.fullmatch(r"-?[0-9]{1,6}", text):
            raise CommandError("invalid number " + text)
        value = int(text)
        if value < minimum or value > maximum or (nonzero and value == 0):
            raise CommandError("invalid number " + text)
        return value

    def kinds(self, command, count):
        if command == "SEQ":
            return ["new", "sequence"]
        if command == "SLICE":
            return ["name", (1, "n"), (1, "n"), "new"]
        if command == "JOIN":
            return ["new"] + ["name"] * (count - 1)
        if command == "MUTATE":
            return ["name", (1, "n"), "base"]
        if command in ("TRANSLATE", "CODONS", "PROTEIN"):
            return ["name", (-3, 3, True)]
        if command == "ORFS":
            return ["name", (1, 200)]
        if command == "GCWINDOW":
            return ["name", (1, 500), (1, 500)]
        if command == "KMERS":
            return ["name", (1, 12), (1, 100)]
        if command == "FIND":
            return ["name", "motif"]
        if command == "RESTRICT":
            return ["name"] + ["enzyme"] * (count - 1)
        if command == "PALINDROMES":
            return ["name", (2, 20), (2, 20)]
        if command == "REPEATS":
            return ["name", (1, 6), (1, 6), (2, 50)]
        if command == "ALIGN":
            return ["name", "name", "mode", (1, 20), (-20, 0), (-20, -1)]
        if command == "FOLD":
            return ["name", (0, 10)]
        if command == "ASSEMBLE":
            return ["new", (1, 100)] + ["name"] * (count - 2)
        if command == "UNPACK":
            return ["new", (1, 500), "hex"]
        return ["name"] * count

    def validate(self, command, arguments):
        if command not in ARITY:
            raise CommandError("unknown command " + command)
        minimum, maximum = ARITY[command]
        if not minimum <= len(arguments) <= maximum:
            raise CommandError("wrong argument count")
        values = []
        seen_enzymes = set()
        for kind, text in zip(self.kinds(command, len(arguments)), arguments):
            value = text
            if isinstance(kind, tuple):
                upper = len(self.registry[arguments[0]]) if kind[1] == "n" else kind[1]
                value = self.number(text, kind[0], upper, len(kind) == 3)
            elif kind == "name":
                if text not in self.registry:
                    raise CommandError("unknown sequence " + text)
            elif kind == "new":
                if not re.fullmatch(r"[a-z][a-z0-9]{0,9}", text):
                    raise CommandError("invalid name " + text)
            elif kind == "sequence":
                for position, base in enumerate(text, 1):
                    if base not in BASES:
                        raise CommandError(f"invalid base {base} at {position}")
            elif kind == "base":
                if len(text) != 1 or text not in BASES:
                    raise CommandError("invalid base " + text)
            elif kind == "motif":
                if not 1 <= len(text) <= 30 or any(symbol not in IUPAC for symbol in text):
                    raise CommandError("invalid motif " + text)
            elif kind == "enzyme":
                if text not in ENZYMES:
                    raise CommandError("unknown enzyme " + text)
                if text in seen_enzymes:
                    raise CommandError("duplicate enzyme " + text)
                seen_enzymes.add(text)
            elif kind == "mode":
                if text not in ("GLOBAL", "LOCAL"):
                    raise CommandError("invalid mode " + text)
            elif kind == "hex":
                if len(text) != 2 * ((values[1] + 3) // 4) or not re.fullmatch(r"[0-9A-F]+", text):
                    raise CommandError("invalid hex")
            values.append(value)
        return values

    def store(self, name, sequence):
        if len(sequence) > 500:
            raise CommandError("too long")
        label = "replaced" if name in self.registry else "stored"
        self.registry[name] = sequence
        return f"{label} {name} {len(sequence)} nt"

    def translation(self, command, name, frame):
        triplets = codons(self.registry[name], frame)
        protein = "".join(CODE[codon] for codon in triplets)
        if command == "TRANSLATE":
            self.emit(protein or "none")
        elif command == "CODONS":
            table = counts(triplets)
            for codon in frequency_order(table):
                self.emit(codon, CODE[codon], table[codon])
            if not table:
                self.emit("none")
        else:
            protein = protein.split("*", 1)[0]
            if not protein:
                raise CommandError("empty protein")
            table = counts(protein)
            mass = sum(AMINO_MASS[amino] for amino in protein) + 18015
            charge = sum(protein.count(amino) for amino in "KR") - sum(protein.count(amino) for amino in "DE")
            self.emit(protein)
            self.emit("length", len(protein), "mass", fixed(mass, 3), "charge", f"+{charge}" if charge > 0 else charge)
            self.emit(*(f"{amino}={table[amino]}" for amino in frequency_order(table)))

    def orfs(self, sequence, minimum):
        results = []
        for frame in (1, 2, 3, -1, -2, -3):
            triplets = codons(sequence, frame)
            start = None
            for position, codon in enumerate(triplets):
                if start is None:
                    if codon == "ATG":
                        start = position
                elif CODE[codon] == "*":
                    if position - start >= minimum:
                        left = abs(frame) - 1 + 3 * start
                        right = abs(frame) - 1 + 3 * (position + 1)
                        if frame < 0:
                            left, right = len(sequence) - right, len(sequence) - left
                        protein = "".join(CODE[c] for c in triplets[start:position])
                        results.append((left + 1, right, frame, protein))
                    start = None
        for left, right, frame, protein in sorted(results):
            self.emit(f"{frame:+d}", left, right, len(protein), protein)
        if not results:
            self.emit("none")

    def restrict(self, sequence, enzymes):
        combined = set()
        for enzyme in enzymes:
            motif, offset = ENZYMES[enzyme]
            cuts = [p + offset - 1 for p in occurrences(sequence, motif) if 1 <= p + offset - 1 < len(sequence)]
            self.emit_list(enzyme, cuts)
            combined.update(cuts)
        endpoints = [0] + sorted(combined) + [len(sequence)]
        fragments = [(a + 1, b) for a, b in zip(endpoints, endpoints[1:])]
        self.emit_list("fragments", [f"{a}-{b}" for a, b in fragments])
        self.emit_list("sizes", sorted((b - a + 1 for a, b in fragments), reverse=True))

    def repeats(self, sequence, minimum, maximum, count):
        if minimum > maximum:
            raise CommandError("invalid range")
        results = []
        for width in range(minimum, maximum + 1):
            position = 0
            while position + width <= len(sequence):
                unit = sequence[position:position + width]
                repeated = repeat_count(sequence, position, width)
                if primitive(unit) and repeated >= count:
                    results.append((position, width, repeated, unit))
                    position += repeated * width
                else:
                    position += 1
        for position, width, repeated, unit in sorted(results):
            self.emit(f"{position + 1}-{position + width * repeated}", f"{unit}x{repeated}")
        if not results:
            self.emit("none")

    def align(self, a, b, mode, match, mismatch, gap):
        m, n = len(a), len(b)
        table = [[0] * (n + 1) for _ in range(m + 1)]
        local = mode == "LOCAL"
        if not local:
            for i in range(m + 1):
                table[i][0] = i * gap
            for j in range(n + 1):
                table[0][j] = j * gap
        best = 0
        end_i = end_j = 0
        for i in range(1, m + 1):
            for j in range(1, n + 1):
                diagonal = table[i - 1][j - 1] + (match if a[i - 1] == b[j - 1] else mismatch)
                value = max(diagonal, table[i - 1][j] + gap, table[i][j - 1] + gap)
                table[i][j] = max(0, value) if local else value
                if local and table[i][j] > best:
                    best = table[i][j]
                    end_i, end_j = i, j
        if not local:
            end_i, end_j = m, n
            best = table[m][n]
        if local and best == 0:
            self.emit("score", 0)
            return
        i, j = end_i, end_j
        row_a, row_b = [], []
        while (local and table[i][j] != 0) or (not local and (i != 0 or j != 0)):
            if i and j and table[i][j] == table[i - 1][j - 1] + (match if a[i - 1] == b[j - 1] else mismatch):
                row_a.append(a[i - 1])
                row_b.append(b[j - 1])
                i -= 1
                j -= 1
            elif i and table[i][j] == table[i - 1][j] + gap:
                row_a.append(a[i - 1])
                row_b.append("-")
                i -= 1
            else:
                row_a.append("-")
                row_b.append(b[j - 1])
                j -= 1
        row_a = "".join(reversed(row_a))
        row_b = "".join(reversed(row_b))
        middle = "".join("-" if "-" in (x, y) else "|" if x == y else "*" for x, y in zip(row_a, row_b))
        self.emit("score", best, "a", f"{i + 1}-{end_i}", "b", f"{j + 1}-{end_j}",
                  "identity", f"{middle.count('|')}/{len(middle)}", "gaps", middle.count("-"))
        self.emit(row_a)
        self.emit(middle)
        self.emit(row_b)

    def consensus(self, sequences):
        if any(len(s) != len(sequences[0]) for s in sequences):
            raise CommandError("length mismatch")
        profile = {base: [] for base in BASES}
        consensus, ambiguous = [], []
        for column in zip(*sequences):
            table = counts(column)
            for base in BASES:
                profile[base].append(table.get(base, 0))
            largest = max(table.values())
            tied = "".join(base for base in BASES if table.get(base, 0) == largest)
            consensus.append(tied[0])
            ambiguous.append(SYMBOL[tied])
        for base in BASES:
            self.emit(base, *profile[base])
        self.emit("consensus", "".join(consensus))
        self.emit("iupac", "".join(ambiguous))

    def primer(self, sequence):
        n = len(sequence)
        amount = gc(sequence)
        tm = temperature(sequence)
        clamp = gc(sequence[-5:])
        longest_run = run = 1
        for i in range(1, n):
            run = run + 1 if sequence[i] == sequence[i - 1] else 1
            longest_run = max(longest_run, run)
        repeated = max(
            (repeat_count(sequence, i, 2) for i in range(n - 1) if sequence[i] != sequence[i + 1]),
            default=0,
        )
        selfcomp = longest_palindrome(sequence)
        items = (
            ("length", n, 18 <= n <= 25),
            ("gc", pct(amount, n), 40 * n <= 100 * amount <= 60 * n),
            ("tm", fixed(tm, 1), 520 <= tm <= 620),
            ("clamp", clamp, 1 <= clamp <= 3),
            ("run", longest_run, longest_run <= 4),
            ("repeat", repeated, repeated <= 4),
            ("selfcomp", selfcomp, selfcomp <= 6),
        )
        failed = []
        for label, value, passed in items:
            self.emit(label, value, "OK" if passed else "FAIL")
            if not passed:
                failed.append(label)
        self.emit("FAIL" if failed else "PASS", *failed)

    def fold(self, sequence, loop):
        n = len(sequence)
        if n > 100:
            raise CommandError("too long")
        table = [[0] * n for _ in range(n)]

        def value(i, j):
            return 0 if i > j else table[i][j]

        def pair(i, j):
            return sequence[i] + sequence[j] in ("AT", "TA", "CG", "GC", "GT", "TG")

        for width in range(2, n + 1):
            for i in range(n - width + 1):
                j = i + width - 1
                best = value(i, j - 1)
                for k in range(i, j - loop):
                    if pair(k, j):
                        best = max(best, value(i, k - 1) + 1 + value(k + 1, j - 1))
                table[i][j] = best
        structure = ["."] * n
        pending = [(0, n - 1)]
        while pending:
            i, j = pending.pop()
            if value(i, j) == 0:
                continue
            if value(i, j) == value(i, j - 1):
                pending.append((i, j - 1))
                continue
            for k in range(i, j - loop):
                if pair(k, j) and value(i, k - 1) + 1 + value(k + 1, j - 1) == value(i, j):
                    structure[k], structure[j] = "(", ")"
                    pending.extend(((i, k - 1), (k + 1, j - 1)))
                    break
        self.emit("".join(structure))
        self.emit("pairs", table[0][n - 1])

    def assemble(self, name, minimum, sequences):
        unique = list(dict.fromkeys(sequences))
        fragments = [s for s in unique if not any(s != t and s in t for t in unique)]
        while len(fragments) >= 2:
            best = 0
            chosen = None
            for i, x in enumerate(fragments):
                for j, y in enumerate(fragments):
                    if i == j:
                        continue
                    overlap = 0
                    for width in range(min(len(x), len(y)) - 1, 0, -1):
                        if x[-width:] == y[:width]:
                            overlap = width
                            break
                    if chosen is None or overlap > best:
                        best = overlap
                        chosen = i, j
            if best < minimum:
                break
            i, j = chosen
            merged = fragments[i] + fragments[j][best:]
            fragments = [
                merged if k == i else fragment
                for k, fragment in enumerate(fragments)
                if k == i or (k != j and fragment not in merged)
            ]
        longest = max(fragments, key=len)
        registration = self.store(name, longest)
        self.emit("contigs", len(fragments))
        for fragment in fragments:
            self.emit(len(fragment), fragment)
        self.emit(registration)

    def command(self, command, a):
        if command == "SEQ":
            self.emit(self.store(a[0], a[1]))
            return
        if command == "UNPACK":
            codes = []
            for i in range(0, len(a[2]), 2):
                value = int(a[2][i:i + 2], 16)
                codes.extend((value // 64, value // 16 % 4, value // 4 % 4, value % 4))
            if any(codes[a[1]:]):
                raise CommandError("invalid padding")
            self.emit(self.store(a[0], "".join(BASES[code] for code in codes[:a[1]])))
            return
        if command == "JOIN":
            self.emit(self.store(a[0], "".join(self.registry[name] for name in a[1:])))
            return
        if command == "ASSEMBLE":
            self.assemble(a[0], a[1], [self.registry[name] for name in a[2:]])
            return
        if command == "LIST":
            for name in sorted(self.registry):
                self.emit(name, len(self.registry[name]), "nt")
            if not self.registry:
                self.emit("no sequences")
            return
        name = a[0]
        sequence = self.registry[name]
        n = len(sequence)
        if command == "SLICE":
            start, end = a[1:3]
            part = sequence[start - 1:end] if start <= end else revcomp(sequence[end - 1:start])
            self.emit(self.store(a[3], part))
        elif command == "MUTATE":
            position, base = a[1:]
            old = sequence[position - 1]
            if old == base:
                raise CommandError("no change")
            self.registry[name] = sequence[:position - 1] + base + sequence[position:]
            self.emit(name, f"{old}{position}{base}", "transition" if transition(old, base) else "transversion")
        elif command == "DEL":
            del self.registry[name]
            self.emit("deleted", name)
        elif command in ("REVCOMP", "COMPLEMENT", "REVERSE", "TRANSCRIBE"):
            result = {
                "REVCOMP": revcomp(sequence), "COMPLEMENT": sequence.translate(COMPLEMENT),
                "REVERSE": sequence[::-1], "TRANSCRIBE": sequence.replace("T", "U"),
            }[command]
            self.emit(result)
        elif command in ("TRANSLATE", "CODONS", "PROTEIN"):
            self.translation(command, name, a[1])
        elif command == "ORFS":
            self.orfs(sequence, a[1])
        elif command == "GC":
            self.emit(*(f"{base}={sequence.count(base)}" for base in BASES), f"GC={pct(gc(sequence), n)}%")
        elif command == "GCWINDOW":
            width, step = a[1:]
            if width > n:
                raise CommandError("window too large")
            for i in range(0, n - width + 1, step):
                self.emit(f"{i + 1}-{i + width}", pct(gc(sequence[i:i + width]), width) + "%")
        elif command == "SKEW":
            values = [0]
            for base in sequence:
                values.append(values[-1] + (base == "G") - (base == "C"))
            for label, extreme in (("min", min(values)), ("max", max(values))):
                self.emit(label, extreme, "at", *(i for i, value in enumerate(values) if value == extreme))
        elif command == "KMERS":
            width, limit = a[1:]
            if width > n:
                raise CommandError("k too large")
            table = counts(sequence[i:i + width] for i in range(n - width + 1))
            self.emit(n - width + 1, "windows", len(table), "distinct")
            for word in frequency_order(table)[:limit]:
                self.emit(word, table[word])
        elif command == "FIND":
            self.emit_list("forward", occurrences(sequence, a[1]))
            self.emit_list("reverse", occurrences(sequence, revcomp(a[1])))
        elif command == "RESTRICT":
            self.restrict(sequence, a[1:])
        elif command == "PALINDROMES":
            minimum, maximum = a[1:]
            if minimum > maximum:
                raise CommandError("invalid range")
            found = False
            for i in range(n):
                for width in range(minimum, min(maximum, n - i) + 1):
                    part = sequence[i:i + width]
                    if part == revcomp(part):
                        self.emit(i + 1, width, part)
                        found = True
            if not found:
                self.emit("none")
        elif command == "REPEATS":
            self.repeats(sequence, *a[1:])
        elif command == "HAMMING":
            other = self.registry[a[1]]
            if len(other) != n:
                raise CommandError("length mismatch")
            distance = sum(x != y for x, y in zip(sequence, other))
            transitions = sum(transition(x, y) for x, y in zip(sequence, other))
            self.emit("distance", distance, "transitions", transitions, "transversions", distance - transitions)
        elif command == "ALIGN":
            self.align(sequence, self.registry[a[1]], *a[2:])
        elif command == "CONSENSUS":
            self.consensus([self.registry[item] for item in a])
        elif command == "TM":
            self.emit("Tm", fixed(temperature(sequence), 1), "wallace" if n < 14 else "gc")
        elif command == "MASS":
            single = strand_mass(sequence)
            self.emit("ss", fixed(single, 3), "ds", fixed(single + strand_mass(revcomp(sequence)), 3))
        elif command == "PRIMER":
            self.primer(sequence)
        elif command == "FOLD":
            self.fold(sequence, a[1])
        elif command == "PACK":
            codes = [BASES.index(base) for base in sequence]
            codes.extend([0] * (-n % 4))
            encoded = "".join(f"{64 * codes[i] + 16 * codes[i + 1] + 4 * codes[i + 2] + codes[i + 3]:02X}" for i in range(0, len(codes), 4))
            self.emit(n, encoded)

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            values = self.validate(command, arguments)
            self.command(command, values)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    toolkit = Toolkit()
    count = int(sys.stdin.readline())
    for _ in range(count):
        toolkit.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(toolkit.output) + "\n")


if __name__ == "__main__":
    main()
