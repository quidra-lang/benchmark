final class Container {
    let id: String
    var message: Message?
    weak var parent: Container?
    var children: [Container] = []
    var subject: String?
    init(_ id: String) { self.id = id }
    func ancestorOrSelf(_ other: Container) -> Bool {
        var current: Container? = other
        while let node = current { if node === self { return true }; current = node.parent }
        return false
    }
}
private func adopt(_ parent: Container, _ child: Container) { child.parent = parent; parent.children.append(child) }
private func prune(_ containers: [Container], _ atRoot: Bool) -> [Container] {
    var result: [Container] = []
    for container in containers {
        container.children = prune(container.children, false)
        if container.message != nil || atRoot && container.children.count >= 2 { result.append(container) }
        else {
            for child in container.children { child.parent = atRoot ? nil : container.parent }
            result += container.children
        }
    }
    return result
}
private func containerKey(_ container: Container) -> (Int, Int, String, Int) {
    if let message = container.message { return message.sortKey }
    return container.children.map(containerKey).min { $0 < $1 }!
}
private func sortContainers(_ containers: [Container]) -> [Container] {
    for container in containers { container.children = sortContainers(container.children) }
    return containers.sorted { containerKey($0) < containerKey($1) }
}
func rootSubject(_ root: Container) -> String { (root.message ?? root.children[0].message!).baseSubject }
func buildThreads(_ messages: [Message]) -> [Container] {
    var table: [String: Container] = [:]
    var containers: [Container] = []
    func containerOf(_ id: String) -> Container {
        if let container = table[id] { return container }
        let container = Container(id); table[id] = container; containers.append(container); return container
    }
    for message in messages {
        let container: Container
        if message.id.isEmpty { container = Container(""); containers.append(container) }
        else { container = containerOf(message.id) }
        container.message = message
        let references = message.references.map(containerOf)
        if references.count >= 2 {
            for index in 0..<(references.count - 1) {
                let current = references[index], following = references[index + 1]
                if following.parent == nil && !following.ancestorOrSelf(current) { adopt(current, following) }
            }
        }
        if let parent = container.parent { parent.children.removeAll { $0 === container }; container.parent = nil }
        if let last = references.last, !container.ancestorOrSelf(last) { adopt(last, container) }
    }
    let roots = sortContainers(prune(containers.filter { $0.parent == nil }, true))
    var groups: [String: [Container]] = [:]
    for root in roots { let subject = rootSubject(root); if !subject.isEmpty { groups[subject, default: []].append(root) } }
    var merged = roots.filter { let subject = rootSubject($0); return subject.isEmpty || groups[subject]!.count == 1 }
    for subject in groups.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
        let group = groups[subject]!
        if group.count < 2 { continue }
        let originals = group.filter { $0.message != nil && !$0.message!.reply }
        let target: Container
        if let missing = group.first(where: { $0.message == nil }) { target = missing }
        else if originals.count == 1 { target = originals[0] }
        else { target = Container(""); target.subject = subject }
        for root in group where root !== target {
            if root.message != nil { adopt(target, root) }
            else { for child in root.children { adopt(target, child) } }
        }
        merged.append(target)
    }
    return sortContainers(merged)
}
