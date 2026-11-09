import Foundation

func total<S: Sequence>(_ values: S) -> Double where S.Element == Double { var result = 0.0; for value in values { result += value }; return result }
func parentRow(_ parents: [Int], _ assignment: [Int], _ sizes: [Int]) -> Int { var row = 0; for parent in parents { row = row * sizes[parent] + assignment[parent] }; return row }
func countSamples(_ variable: Int, _ parents: [Int], _ samples: [[Int]], _ sizes: [Int]) -> [[Int]] { let rows = parents.reduce(1) { $0 * sizes[$1] }; var counts = Array(repeating: Array(repeating: 0, count: sizes[variable]), count: rows); for sample in samples { counts[parentRow(parents, sample, sizes)][sample[variable]] += 1 }; return counts }
func learn(_ counts: [[Int]], _ alpha: Double) -> [[Double]] { counts.map { row in let values = row.map { Double($0) + alpha }, denominator = total(values); return values.map { $0 / denominator } } }
func logLikelihood(_ counts: [[Int]], _ cpt: [[Double]]) -> Double { var likelihood = 0.0; for row in counts.indices { for state in counts[row].indices where counts[row][state] != 0 { likelihood += Double(counts[row][state]) * log(cpt[row][state]) } }; return likelihood }
func parameterCount(_ counts: [[Int]]) -> Int { (counts[0].count - 1) * counts.count }
func familyScore(_ variable: Int, _ parents: [Int], _ samples: [[Int]], _ sizes: [Int], _ alpha: Double) -> Double { let counts = countSamples(variable, parents.sorted(), samples, sizes), cpt = learn(counts, alpha); return logLikelihood(counts, cpt) - Double(parameterCount(counts)) * log(Double(samples.count)) / 2 }
