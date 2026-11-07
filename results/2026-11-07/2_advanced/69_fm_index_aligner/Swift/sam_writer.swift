import Foundation

func ratio(_ numerator: Int, _ denominator: Int) -> String { denominator == 0 ? "-" : String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(numerator) / Double(denominator)) }
func samHeader(_ references: [Reference]) -> [String] { ["@HD\tVN:1.6\tSO:unsorted"] + references.map { "@SQ\tSN:\($0.name)\tLN:\($0.bases.count)" } + ["@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0"] }
func samRecord(_ result: MappingResult, _ references: [Reference], _ maximumAlternatives: Int) -> String {
    let read = result.read
    guard let alignment = result.primary else { return [read.name, "4", "*", "0", "0", "*", "*", "0", "0", text(read.bases), text(read.quality), "YM:Z:" + result.reason].joined(separator: "\t") }
    let reverse = alignment.strand == 1
    var fields = [read.name, reverse ? "16" : "0", references[alignment.reference].name, String(alignment.position + 1), String(result.mapq), alignment.cigar, "*", "0", "0", text(reverse ? reverseComplement(read.bases) : read.bases), text(reverse ? Array(read.quality.reversed()) : read.quality), "NM:i:\(alignment.nm)", "MD:Z:\(alignment.md)", "AS:i:\(result.score)", "X0:i:\(result.x0)", "X1:i:\(result.x1)", "YM:Z:" + result.method]
    if !result.others.isEmpty && result.others.count <= maximumAlternatives { fields.append("XA:Z:" + result.others.map { "\(references[$0.reference].name),\($0.strand == 0 ? "+" : "-")\($0.position + 1),\($0.cigar),\($0.nm);" }.joined()) }
    return fields.joined(separator: "\t")
}
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
