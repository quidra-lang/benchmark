struct CommonPair: Hashable {
    let size: Int, alignment: Int
}
final class Resolution {
    var kind = "weakundef", definition: Reference?, definer = "-", size = 0, alignment = 1, strong: [Int] = [], common: [CommonPair] = [], referrers: [Int] = [], live = false, address = 0
}
enum Resolver {
    static func resolve(_ objects: [Object], _ entries: [Reference], _ script: Bool) -> Resolution {
        var strong: [Reference] = [], weakDefinitions: [Reference] = [], common: [(Reference, Int, Int)] = [], globalReference = false
        let result = Resolution()
        for entry in entries {
            let symbol = objects[entry.object].symbols[entry.index]
            switch symbol.definition {
                case .section:
                if symbol.binding == "global" {
                    strong.append(entry)
                } else {
                    weakDefinitions.append(entry)
                }
                case .common(let size, let alignment): common.append((entry, size, alignment))
                case .undefined: if !result.referrers.contains(entry.object) {
                    result.referrers.append(entry.object)
                };
                globalReference = globalReference || symbol.binding == "global"
            }
        }
        result.strong = strong.map(\.object);
        result.common = common.map {
            CommonPair(size: $0.1, alignment: $0.2)
        }
        if script {
            result.kind = "script";
            result.definer = "*script*";
            result.live = true
        }
        else if let entry = strong.first {
            result.kind = "global";
            result.definition = entry;
            result.definer = objects[entry.object].name
        }
        else if !common.isEmpty {
            result.kind = "common";
            result.size = common.map {
                $0.1
            }.max()!;
            result.alignment = common.map {
                $0.2
            }.max()!;
            result.definer = objects[common.first {
                $0.1 == result.size
            }!.0.object].name
        }
        else if let entry = weakDefinitions.first {
            result.kind = "weak";
            result.definition = entry;
            result.definer = objects[entry.object].name
        }
        else if globalReference {
            result.kind = "undefined"
        };
        return result
    }
}
