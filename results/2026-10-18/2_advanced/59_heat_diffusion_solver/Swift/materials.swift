import Foundation

struct Material { let code: String; let name: String; let conductivity: Double; let density: Double; let specificHeat: Double }
func readMaterials() throws -> [Material] {
    try String(contentsOfFile: "input/materials.txt", encoding: .ascii).split(separator: "\n").map { line in let fields = line.components(separatedBy: " "); return Material(code: fields[0], name: fields[1], conductivity: Double(fields[2])!, density: Double(fields[3])!, specificHeat: Double(fields[4])!) }
}
func heatCapacity(_ material: Material, _ dx: Double, _ thickness: Double) -> Double { material.density * material.specificHeat * dx * dx * thickness }
func interiorConductance(_ first: Double, _ second: Double, _ thickness: Double) -> Double { 2 * first * second / (first + second) * thickness }
func fixedConductance(_ conductivity: Double, _ thickness: Double) -> Double { 2 * conductivity * thickness }
func convectiveConductance(_ conductivity: Double, _ coefficient: Double, _ dx: Double, _ thickness: Double) -> Double { 1 / (1 / (coefficient * dx * thickness) + 1 / (2 * conductivity * thickness)) }
