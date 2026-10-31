import Foundation

struct Reference { let name: String; let bases: [UInt8]; let masked: Int }
struct Read { let name: String; let bases: [UInt8]; let quality: [UInt8] }
struct Settings {
    let maximumMismatches: Int, minimumLength: Int, trimQuality: Int, seedLength: Int, seedStep: Int, maximumSeedHits: Int, bandWidth: Int, match: Int, mismatch: Int, gapOpen: Int, gapExtend: Int, minimumScore: Int, maximumAlternatives: Int, occurrenceInterval: Int, sampleInterval: Int, directLimit: Int, coverageWindow: Int, coverageMapq: Int, variantDepth: Int, variantQuality: Int, variantPercent: Int, homozygousPercent: Int
    init(_ values: [String: [Int]]) { maximumMismatches = values["MAX_MISMATCHES"]![0]; minimumLength = values["MIN_READ_LENGTH"]![0]; trimQuality = values["TRIM_QUALITY"]![0]; seedLength = values["SEED_LENGTH"]![0]; seedStep = values["SEED_STEP"]![0]; maximumSeedHits = values["MAX_SEED_HITS"]![0]; bandWidth = values["BAND_WIDTH"]![0]; let scores = values["SCORES"]!; match = scores[0]; mismatch = scores[1]; gapOpen = scores[2]; gapExtend = scores[3]; minimumScore = values["MIN_SCORE_PERCENT"]![0]; maximumAlternatives = values["MAX_ALT_HITS"]![0]; occurrenceInterval = values["OCC_INTERVAL"]![0]; sampleInterval = values["SA_SAMPLE_INTERVAL"]![0]; directLimit = values["DIRECT_SORT_LIMIT"]![0]; coverageWindow = values["COVERAGE_WINDOW"]![0]; coverageMapq = values["COVERAGE_MIN_MAPQ"]![0]; let variants = values["VARIANTS"]!; variantDepth = variants[0]; variantQuality = variants[1]; variantPercent = variants[2]; homozygousPercent = variants[3] }
}
func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func reverseComplement(_ sequence: [UInt8]) -> [UInt8] { sequence.reversed().map { base in switch base { case 65: return 84; case 67: return 71; case 71: return 67; case 84: return 65; default: return 78 } } }
func readInputs() throws -> (references: [Reference], reads: [Read], settings: Settings) {
    var references: [Reference] = [], name: String?, bases: [UInt8] = [], masked = 0
    for line in try inputLines("reference.fasta") { if line.first == ">" { if let name { references.append(Reference(name: name, bases: bases, masked: masked)) }; name = String(line.dropFirst().split(separator: " ", maxSplits: 1)[0]); bases = []; masked = 0 } else { for base in line.utf8 { if base >= 97 && base <= 122 { bases.append(base - 32); masked += 1 } else { bases.append(base) } } } }
    references.append(Reference(name: name!, bases: bases, masked: masked))
    let lines = try inputLines("reads.fastq")
    var reads: [Read] = [], values: [String: [Int]] = [:]
    for index in stride(from: 0, to: lines.count, by: 4) { reads.append(Read(name: String(lines[index].dropFirst()), bases: Array(lines[index + 1].utf8), quality: Array(lines[index + 3].utf8))) }
    for line in try inputLines("params.txt") { let fields = line.split(separator: " "); values[String(fields[0])] = fields.dropFirst().map { Int($0)! } }
    return (references, reads, Settings(values))
}
