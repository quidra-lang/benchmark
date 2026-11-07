struct Attribute: Hashable { var path: [Int]; var origin: String; var med: Int; var communities: Set<Community> }
struct Route: Equatable {
    var attribute: Attribute, localPref: Int, link: Int?
    static func local(_ origin: String, _ communities: Set<Community>) -> Self { Self(attribute: Attribute(path: [], origin: origin, med: 0, communities: communities), localPref: 0, link: nil) }
    var neighbor: Int { attribute.path[0] }
}
enum Decision {
    static func best(_ routes: [Route], _ topology: Topology) -> (Route, String) {
        var candidates = routes
        if candidates.count == 1 { return (candidates[0], "ONLY") }
        for stage in 0..<6 {
            func key(_ route: Route) -> Int {
                switch stage { case 0: return -route.localPref; case 1: return route.attribute.path.count; case 2: return ["IGP", "EGP", "INCOMPLETE"].firstIndex(of: route.attribute.origin)!; case 4: return topology.routers[route.neighbor]!; case 5: return route.link!; default: return 0 }
            }
            if stage == 3 { let original = candidates; candidates.removeAll { route in original.contains { $0.neighbor == route.neighbor && $0.attribute.med < route.attribute.med } } }
            else { let minimum = candidates.map(key).min()!; candidates.removeAll { key($0) != minimum } }
            if candidates.count == 1 { return (candidates[0], ["LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK"][stage]) }
        }
        fatalError()
    }
}
