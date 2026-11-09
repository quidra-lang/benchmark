import Foundation

let pi = 3.141592653589793
func buckling(_ properties: Properties, _ geometry: Geometry, _ inertia: Double? = nil) -> Double { pi * pi * properties.young * (inertia ?? properties.inertia) / (geometry.length * geometry.length) }
func utilization(_ force: Double, _ properties: Properties, _ geometry: Geometry, _ section: Section? = nil) -> Double {
    let area = section?.area ?? properties.area, inertia = section?.inertia ?? properties.inertia
    return max(abs(force / area) / properties.yieldStress, max(0, -force) / buckling(properties, geometry, inertia))
}
func slenderness(_ properties: Properties, _ geometry: Geometry, _ section: Section? = nil) -> Double { geometry.length / sqrt((section?.inertia ?? properties.inertia) / (section?.area ?? properties.area)) }
func slendernessLimit(_ number: Int, _ combinations: [Result], _ limits: [Double]) -> Double { combinations.contains { $0.forces[number] < 0 } ? limits[0] : limits[1] }
func selectSection(_ members: [Int], _ sections: [Section], _ properties: [Properties], _ geometry: [Geometry], _ combinations: [Result], _ limits: [Double]) -> Int {
    for (number, section) in sections.enumerated() {
        var acceptable = true
        for member in members {
            if slenderness(properties[member], geometry[member], section) > limits[member] { acceptable = false; break }
            if combinations.contains(where: { utilization($0.forces[member], properties[member], geometry[member], section) > 1 }) { acceptable = false; break }
        }
        if acceptable { return number }
    }
    return sections.count - 1
}
