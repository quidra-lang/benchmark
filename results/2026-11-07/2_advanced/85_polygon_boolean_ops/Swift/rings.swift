import Foundation
typealias Ring = [Point]
typealias Rings = [Ring]
typealias Region = [Rings]
enum RingOps {
    static func inside(_ point: Point, _ ring: Ring) -> Bool {
        var odd = false
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            if (a.y * point.d > point.y * a.d) != (b.y * point.d > point.y * b.d) {
                let (lo, hi) = yLess(a, b) ? (a, b) : (b, a)
                if cross(lo, hi, point) > 0 {
                    odd.toggle()
                }
            }
        }
        return odd
    }
    static func interior(_ p: Point, _ rings: Rings) -> Bool {
        rings.filter {
            inside(p, $0)
        }.count % 2 == 1
    }
    static func boundary(_ p: Point, _ ring: Ring) -> Bool {
        ring.indices.contains {
            Intersections.on(ring[$0], ring[($0 + 1) % ring.count], p)
        }
    }
    static func rotate(_ ring: Ring) -> Ring {
        let i = ring.firstIndex(of: ring.min()!)!;
        return Array(ring[i...]) + ring[..<i]
    }
    static func ccw(_ ring: Ring) -> Bool {
        cross(ring.last!, ring[0], ring[1]) > 0
    }
    static func reverse(_ ring: Ring) -> Ring {
        [ring[0]] + ring.dropFirst().reversed()
    }
    static func canonical(_ input: Rings) -> Rings {
        var rings = input.enumerated().map {
            i, r -> Ring in let rotated = rotate(r);
            return ccw(rotated) == (i == 0) ? rotated : reverse(rotated)
        }
        rings = [rings[0]] + rings.dropFirst().sorted {
            $0[0] < $1[0]
        }
        return rings
    }
    static func assemble(_ input: Rings) -> Region {
        var rings = input.map(rotate)
        let depth = rings.indices.map {
            i in rings.indices.filter {
                $0 != i && inside(rings[i][0], rings[$0])
            }.count
        }
        for i in rings.indices where ccw(rings[i]) != (depth[i] % 2 == 0) {
            rings[i] = reverse(rings[i])
        }
        let outers = rings.indices.filter {
            depth[$0] % 2 == 0
        }.sorted {
            rings[$0][0] < rings[$1][0]
        }
        return outers.map {
            i in
            let holes = rings.indices.filter {
                depth[$0] == depth[i] + 1 && inside(rings[$0][0], rings[i])
            }.sorted {
                rings[$0][0] < rings[$1][0]
            }
            return [rings[i]] + holes.map {
                rings[$0]
            }
        }
    }
    static func area(_ ring: Ring) -> Double {
        var sum = 0.0
        for i in ring.indices {
            let (x, y) = ring[i].real, (u, v) = ring[(i + 1) % ring.count].real;
            sum += x * v - u * y
        }
        return sum / 2
    }
    static func perimeter(_ ring: Ring) -> Double {
        var sum = 0.0
        for i in ring.indices {
            let (x, y) = ring[i].real, (u, v) = ring[(i + 1) % ring.count].real;
            let dx = u - x, dy = v - y;
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum
    }
    static func totalArea(_ region: Region) -> Double {
        var sum = 0.0;
        for polygon in region {
            for ring in polygon {
                sum += area(ring)
            }
        };
        return sum
    }
}
