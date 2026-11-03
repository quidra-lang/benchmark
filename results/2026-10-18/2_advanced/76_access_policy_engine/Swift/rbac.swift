import Foundation

struct Permission: Hashable, Comparable {
    let action: String
    let type: String
    static func < (a: Permission, b: Permission) -> Bool {
        a.action == b.action ? a.type < b.type : a.action < b.action
    }
}

struct Grant: Hashable, Comparable {
    let role: String
    let permission: Permission
    static func < (a: Grant, b: Grant) -> Bool {
        a.role == b.role ? a.permission < b.permission : a.role < b.role
    }
}

struct DutyConstraint {
    let name: String
    let cardinality: Int
    let roles: Set<String>
}

struct Assignment {
    let user: String
    let role: String
    let first: Int
    let last: Int
}

final class RBAC {
    var roles: Set<String> = []
    var inherits: [String: Set<String>] = [:]
    var permissions: [String: Set<Permission>] = [:]
    var ssd: [DutyConstraint] = [], dsd: [DutyConstraint] = []
    var assignments: [Assignment] = []
    var diagnostics: [(Int, String, String)] = []
    var grants: Set<Grant> = []

    init() throws {
        let lines = try readLines("input/rbac.txt").enumerated().map {
            ($0.offset + 1, $0.element.split(separator: " ").map(String.init))
        }
        for keyword in ["ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN"] {
            for (number, fields) in lines where fields[0] == keyword {
                if let reason = accept(keyword, Array(fields.dropFirst())) {
                    diagnostics.append((number, keyword, reason))
                }
            }
        }
        diagnostics.sort { $0.0 < $1.0 }
    }

    func closure(_ initial: Set<String>) -> Set<String> {
        var reached = initial, pending = Array(initial)
        while let role = pending.popLast() {
            for junior in inherits[role, default: []] where reached.insert(junior).inserted { pending.append(junior) }
        }
        return reached
    }

    func path(_ start: String, _ finish: String) -> [String]? {
        var failed: Set<String> = []
        func visit(_ role: String) -> [String]? {
            if role == finish { return [role] }
            if failed.contains(role) { return nil }
            for junior in inherits[role, default: []].sorted() {
                if let suffix = visit(junior) { return [role] + suffix }
            }
            failed.insert(role)
            return nil
        }
        return visit(start)
    }

    func assigned(_ user: String, _ day: Int) -> Set<String> {
        Set(assignments.filter { $0.user == user && $0.first <= day && day <= $0.last }.map(\.role))
    }

    func authorized(_ user: String, _ day: Int) -> Set<String> { closure(assigned(user, day)) }

    func accept(_ keyword: String, _ f: [String]) -> String? {
        switch keyword {
        case "ROLE":
            if roles.contains(f[0]) { return "duplicate role " + f[0] }
            roles.insert(f[0])
            inherits[f[0]] = []
            permissions[f[0]] = []
        case "INHERITS":
            let senior = f[0], junior = f[1]
            for role in [senior, junior] where !roles.contains(role) { return "unknown role " + role }
            if inherits[senior]!.contains(junior) { return "duplicate inheritance \(senior) \(junior)" }
            if closure([junior]).contains(senior) {
                return "cycle " + ([senior] + path(junior, senior)!).joined(separator: " > ")
            }
            inherits[senior]!.insert(junior)
        case "PERMIT":
            let role = f[0], permission = Permission(action: f[1], type: f[2])
            if !roles.contains(role) { return "unknown role " + role }
            if permissions[role]!.contains(permission) { return "duplicate permission \(role) \(f[1]) \(f[2])" }
            permissions[role]!.insert(permission)
            grants.insert(Grant(role: role, permission: permission))
        case "SSD", "DSD":
            let name = f[0], cardinality = Int(f[1])!, listed = f[2].components(separatedBy: ",")
            if (keyword == "SSD" ? ssd : dsd).contains(where: { $0.name == name }) {
                return "duplicate constraint " + name
            }
            for role in listed where !roles.contains(role) { return "unknown role " + role }
            if cardinality < 2 || cardinality > listed.count { return "bad cardinality \(name) \(cardinality)" }
            let constraint = DutyConstraint(name: name, cardinality: cardinality, roles: Set(listed))
            if keyword == "SSD" { ssd.append(constraint) } else { dsd.append(constraint) }
        default:
            let user = f[0], role = f[1], first = Int(f[2])!, last = Int(f[3])!
            if !roles.contains(role) { return "unknown role " + role }
            if !(1 <= first && first <= last && last <= 365) { return "bad range \(first) \(last)" }
            for constraint in ssd {
                for day in first...last {
                    let overlap = constraint.roles.intersection(closure(assigned(user, day).union([role])))
                    if overlap.count >= constraint.cardinality {
                        return "ssd \(constraint.name) day \(day) roles " + overlap.sorted().joined(separator: ",")
                    }
                }
            }
            assignments.append(Assignment(user: user, role: role, first: first, last: last))
        }
        return nil
    }
}
