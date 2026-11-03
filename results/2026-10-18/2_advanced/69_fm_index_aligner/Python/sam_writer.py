"""SAM field order, ratio formatting and ASCII/LF file output."""

from pathlib import Path

from sequence_io import reverse_complement


def ratio(numerator, denominator):
    return format(numerator / denominator, ".4f") if denominator else "-"


def header(references):
    lines = ["@HD\tVN:1.6\tSO:unsorted"]
    lines.extend(f"@SQ\tSN:{reference.name}\tLN:{len(reference.bases)}" for reference in references)
    lines.append("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0")
    return lines


def record(result, references, maximum_alternatives):
    read = result["read"]
    if not result["mapped"]:
        return "\t".join((read.name, "4", "*", "0", "0", "*", "*", "0", "0",
                          read.bases, read.quality, "YM:Z:" + result["reason"]))
    alignment = result["primary"]
    reverse = alignment["strand"] == "-"
    fields = [read.name, "16" if reverse else "0", references[alignment["reference"]].name,
              str(alignment["position"] + 1), str(result["mapq"]), alignment["cigar"], "*", "0", "0",
              reverse_complement(read.bases) if reverse else read.bases,
              read.quality[::-1] if reverse else read.quality,
              f"NM:i:{alignment['nm']}", f"MD:Z:{alignment['md']}", f"AS:i:{result['score']}",
              f"X0:i:{result['x0']}", f"X1:i:{result['x1']}", f"YM:Z:{result['method']}"]
    others = result["others"]
    if 1 <= len(others) <= maximum_alternatives:
        alternative = "".join(f"{references[item['reference']].name},{item['strand']}{item['position'] + 1},"
                              f"{item['cigar']},{item['nm']};" for item in others)
        fields.append("XA:Z:" + alternative)
    return "\t".join(fields)


def write_lines(path, lines):
    text = "\n".join(lines) + ("\n" if lines else "")
    Path(path).write_text(text, encoding="ascii", newline="\n")
