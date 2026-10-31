import Foundation

private final class Expander {
    let configuration: [String: Definition]
    let report: (Origin, String, String) -> Void
    var results: [String: String] = [:]
    var failures: Set<String> = []
    var inProgress: [String] = []
    var cycleKeys: Set<String> = []

    init(configuration: [String: Definition], report: @escaping (Origin, String, String) -> Void) {
        self.configuration = configuration
        self.report = report
    }

    func expand(_ key: String) -> String? {
        if let result = results[key] { return result }
        if failures.contains(key) { return nil }
        inProgress.append(key)
        let result = evaluate(key)
        inProgress.removeLast()
        if let result { results[key] = result }
        else { failures.insert(key) }
        return result
    }

    private func evaluate(_ key: String) -> String? {
        let definition = configuration[key]!
        let raw = Array(definition.raw.utf8)
        var result: [UInt8] = []
        var position = 0
        while position < raw.count {
            guard raw[position] == 36 && position + 1 < raw.count && raw[position + 1] == 123 else {
                result.append(raw[position] == literalDollar ? 36 : raw[position])
                position += 1
                continue
            }
            guard let close = raw[(position + 2)...].firstIndex(of: 125) else {
                report(definition.origin, "E_BAD_REF", "\(key): invalid reference")
                return nil
            }
            let reference = asciiText(Array(raw[(position + 2)..<close]))
            guard isSectionName(reference) else {
                report(definition.origin, "E_BAD_REF", "\(key): invalid reference")
                return nil
            }
            let target = reference.contains(".") ? reference : splitKey(key).section + "." + reference
            guard configuration[target] != nil else {
                report(definition.origin, "E_UNDEFINED", "\(key): undefined reference \(target)")
                return nil
            }
            let expanded: String?
            if let start = inProgress.firstIndex(of: target) {
                let path = Array(inProgress[start...]) + [target]
                cycleKeys.formUnion(path)
                report(configuration[target]!.origin, "E_CYCLE",
                       "interpolation cycle " + path.joined(separator: " -> "))
                expanded = nil
            } else {
                expanded = expand(target)
            }
            guard let expanded else {
                if !cycleKeys.contains(key) {
                    report(definition.origin, "E_DEPENDENCY", "\(key): depends on failed key \(target)")
                }
                return nil
            }
            result.append(contentsOf: expanded.utf8)
            position = close + 1
        }
        return asciiText(result)
    }
}

func expandConfiguration(_ configuration: [String: Definition],
                         report: @escaping (Origin, String, String) -> Void) -> [String: String] {
    let expander = Expander(configuration: configuration, report: report)
    for key in configuration.keys.sorted(by: keyLess) { _ = expander.expand(key) }
    return expander.results
}
