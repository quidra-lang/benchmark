import Foundation
typealias Tree = [String: String]
struct Problem: Error {
    let text: String
}
func fail(_ reason: String) throws -> Never {
    throw Problem(text: "error: " + reason)
}
struct Commit {
    let id: String, parents: [Int], tree: Tree, message: String
}
struct Stash {
    let label: String, base: Int, tree: Tree
}
func paths(_ trees: [Tree]) -> [String] {
    Set(trees.flatMap {
        $0.keys
    }).sorted()
}
func differences(_ a: Tree, _ b: Tree) -> [String] {
    paths([a,b]).filter {
        a[$0] != b[$0]
    }
}
func matchPath(_ target: inout Tree, _ source: Tree, _ p: String) {
    target[p] = source[p]
}
func changes(_ a: Tree, _ b: Tree) -> [String] {
    let result = differences(a,b).map {
        p -> String in
        if a[p] == nil {
            return "A \(p): \(b[p]!)"
        }
        if b[p] == nil {
            return "D \(p): \(a[p]!)"
        }
        return "M \(p): \(a[p]!) -> \(b[p]!)"
    }
    return result.isEmpty ? ["(no changes)"] : result
}
func threeWay(_ base: Tree, _ ours: Tree, _ theirs: Tree) -> (Tree, Tree) {
    var merged: Tree = [:], conflicts: Tree = [:]
    for p in paths([base,ours,theirs]) {
        let b = base[p], o = ours[p], t = theirs[p]
        if t == b || o == t {
            matchPath(&merged,ours,p)
        }
        else if o == b {
            matchPath(&merged,theirs,p)
        }
        else {
            matchPath(&merged,ours,p)
            conflicts[p] = "<<<<<<< \(o ?? "(deleted)") ======= \(t ?? "(deleted)") >>>>>>>"
        }
    }
    return (merged,conflicts)
}
func glob(_ pattern: String, _ path: String) -> Bool {
    let bytes = Array(path.utf8)
    var previous = Array(repeating: false, count: bytes.count + 1)
    previous[0] = true
    for c in pattern.utf8 {
        var next = Array(repeating: false, count: bytes.count + 1)
        if c == 42 {
            next[0] = previous[0]
        }
        for i in bytes.indices {
            next[i + 1] = c == 42 ? previous[i + 1] || next[i] : previous[i] && (c == 63 || c == bytes[i])
        }
        previous = next
    }
    return previous[bytes.count]
}
final class Repository {
    var commits: [Commit?] = [], branches: [String: Int] = [:], tags: [String: Int] = [:], head = 0, attached: String? = "main"
    var work: Tree = [:], index: Tree = [:], conflicts = Set<String>(), pending: (String,Int)? = nil, stashes: [Stash] = [], ignores: [String] = []
    init() {
        _ = create([],[:],"init")
        branches["main"] = 0
    }
    func commit(_ i: Int) -> Commit {
        commits[i]!
    }
    func h() -> Tree {
        commit(head).tree
    }
    func create(_ parents: [Int], _ tree: Tree, _ message: String) -> Int {
        let sequence = commits.count
        var text = "commit \(sequence)\n"
        for p in parents {
            text += "parent \(commit(p).id)\n"
        }
        for p in tree.keys.sorted() {
            text += "file \(p) \(tree[p]!)\n"
        }
        text += "message \(message)\n"
        let hash = text.utf8.reduce(Int64(0)) {
            ($0 * 131 + Int64($1)) % 2147483647
        }
        commits.append(Commit(id: String(format: "%08x", UInt32(hash)), parents: parents, tree: tree, message: message))
        return sequence
    }
    func moveHead(_ target: Int) {
        head = target
        if let attached {
            branches[attached] = target
        }
    }
    func record(_ parents: [Int], _ tree: Tree, _ message: String) -> String {
        let old = commit(parents[0]).tree
        var counts = [0,0,0]
        for p in differences(old,tree) {
            counts[old[p] == nil ? 0 : (tree[p] == nil ? 2 : 1)] += 1
        }
        let target = create(parents,tree,message)
        moveHead(target)
        return "[\(attached ?? "detached HEAD") \(commit(target).id)] \(message) (\(counts[0]) added, \(counts[1]) modified, \(counts[2]) deleted)"
    }
    func resolve(_ revision: String) throws -> Int {
        let parts = revision.components(separatedBy: "~"), anchor = parts[0], count = parts.count == 2 ? Int(parts[1])! : 0
        var target: Int? = anchor == "HEAD" ? head : (branches[anchor] ?? tags[anchor] ?? commits.firstIndex {
            $0?.id == anchor
        })
        for _ in 0..<count {
            target = target.flatMap {
                commit($0).parents.first
            }
        }
        guard let target else {
            try fail("unknown revision '\(revision)'")
        }
        return target
    }
    func distances(_ start: Int) -> [Int: Int] {
        var result = [start: 0], queue = [start], at = 0
        while at < queue.count {
            let i = queue[at]
            at += 1
            for p in commit(i).parents where result[p] == nil {
                result[p] = result[i]! + 1
                queue.append(p)
            }
        }
        return result
    }
    func ancestor(_ a: Int, _ b: Int) -> Bool {
        distances(b)[a] != nil
    }
    func mergeBase(_ x: Int, _ y: Int) -> Int {
        let a = distances(x), b = distances(y), common = Set(a.keys).intersection(b.keys)
        return common.filter {
            z in !common.contains {
                w in z != w && ancestor(z,w)
            }
        }.min {
            u,v in
            let du = max(a[u]!,b[u]!), dv = max(a[v]!,b[v]!)
            return du == dv ? u > v : du < dv
        }!
    }
    func inProgress() throws {
        if let (kind,_) = pending {
            try fail(kind + " in progress")
        }
    }
    func uncommitted() -> Bool {
        index != h() || index.keys.contains {
            work[$0] != index[$0]
        }
    }
    func clean() throws {
        if uncommitted() {
            try fail("uncommitted changes")
        }
    }
    func overwrite(_ selected: Set<String>) throws {
        for p in selected.sorted() {
            if index[p] != h()[p] || work[p] != h()[p] {
                try fail("local changes to '\(p)' would be overwritten")
            }
        }
    }
    func switchTree(_ tree: Tree) throws {
        let changed = differences(h(),tree)
        try overwrite(Set(changed))
        for p in changed {
            matchPath(&work,tree,p)
            matchPath(&index,tree,p)
        }
    }
    func ignored(_ p: String) -> Bool {
        index[p] == nil && !conflicts.contains(p) && ignores.contains {
            glob($0,p)
        }
    }
    func summary(_ i: Int) -> String {
        var refs: [String] = []
        if head == i {
            refs.append(attached.map {
                "HEAD -> " + $0
            } ?? "HEAD")
        }
        for b in branches.keys.sorted() where branches[b] == i && attached != b {
            refs.append(b)
        }
        for tag in tags.keys.sorted() where tags[tag] == i {
            refs.append("tag: " + tag)
        }
        return commit(i).id + (refs.isEmpty ? "" : " (" + refs.joined(separator: ", ") + ")") + " " + commit(i).message
    }
    func apply(_ base: Tree, _ theirs: Tree, _ kind: String, _ target: Int, _ message: String, _ parents: [Int], _ mergeBase: Int? = nil) throws -> [String] {
        let (merged,clashes) = threeWay(base,h(),theirs)
        try overwrite(Set(differences(h(),merged)).union(clashes.keys))
        var out: [String] = []
        if let mergeBase {
            out.append("Merge base " + commit(mergeBase).id)
        }
        if kind != "merge" && clashes.isEmpty && merged == h() {
            return out + ["nothing to commit"]
        }
        for p in differences(h(),merged) {
            matchPath(&work,merged,p)
            matchPath(&index,merged,p)
        }
        if clashes.isEmpty {
            out.append(record(parents,merged,message))
        }
        else {
            for p in clashes.keys.sorted() {
                work[p] = clashes[p]
                out.append("CONFLICT " + p)
            }
            conflicts = Set(clashes.keys)
            pending = (kind,target)
            out.append(kind == "merge" ? "Automatic merge failed; fix conflicts and then commit the result." : "error: could not \(kind == "revert" ? "revert" : "apply") \(commit(target).id)")
        }
        return out
    }
    func reachable(_ includeSaved: Bool) -> Set<Int> {
        var starts = [head] + Array(branches.values) + Array(tags.values)
        if includeSaved {
            starts += stashes.map(\.base)
            if let (_,i) = pending {
                starts.append(i)
            }
        }
        return Set(starts.flatMap {
            distances($0).keys
        })
    }
    func command(_ line: String) throws -> [String] {
        let words = line.components(separatedBy: " "), c = words[0], a = Array(words.dropFirst())
        var out: [String] = []
        switch c {
            case "WRITE": work[a[0]] = String(line.split(separator: " ", maxSplits: 2)[2])
            case "REMOVE": if work.removeValue(forKey: a[0]) == nil {
                try fail("no such file '\(a[0])'")
            }
            case "ADD":
            if a[0] == "ALL" {
                let selected = paths([work,index]).filter {
                    !ignored($0)
                }
                for p in selected {
                    matchPath(&index,work,p)
                }
                conflicts.removeAll()
            }
            else {
                let p = a[0]
                if work[p] != nil && ignored(p) {
                    try fail("path '\(p)' is ignored")
                }
                if work[p] == nil && index[p] == nil && !conflicts.contains(p) {
                    try fail("pathspec '\(p)' did not match any files")
                }
                matchPath(&index,work,p)
                conflicts.remove(p)
            }
            case "RM": if index.removeValue(forKey: a[0]) == nil {
                try fail("pathspec '\(a[0])' did not match any files")
            }
            work.removeValue(forKey: a[0])
            conflicts.remove(a[0])
            case "UNSTAGE": if index[a[0]] == nil && h()[a[0]] == nil {
                try fail("pathspec '\(a[0])' did not match any files")
            }
            matchPath(&index,h(),a[0])
            case "RESTORE":
            if a.count == 1 {
                guard let value = index[a[0]] else {
                    try fail("pathspec '\(a[0])' did not match any files")
                }
                work[a[0]] = value
            }
            else {
                let target = try resolve(a[1])
                guard let value = commit(target).tree[a[0]] else {
                    try fail("path '\(a[0])' does not exist in '\(a[1])'")
                }
                work[a[0]] = value
                index[a[0]] = value
                conflicts.remove(a[0])
            }
            case "IGNORE": ignores.append(a[0])
            case "COMMIT","AMEND":
            let message = String(line.split(separator: " ", maxSplits: 1)[1]), parents: [Int]
            if c == "AMEND" {
                try inProgress()
                if commit(head).parents.isEmpty {
                    try fail("cannot amend the root commit")
                }
                parents = commit(head).parents
            }
            else {
                if !conflicts.isEmpty {
                    try fail("unresolved conflicts")
                }
                if let (kind,i) = pending, kind == "merge" {
                    parents = [head,i]
                } else {
                    parents = [head]
                }
            }
            if c == "COMMIT" && parents.count != 2 && index == h() {
                out.append("nothing to commit")
            } else {
                out.append(record(parents,index,message))
                pending = nil
            }
            case "STATUS":
            out.append(attached.map {
                "On branch " + $0
            } ?? "HEAD detached at " + commit(head).id)
            if let (kind,i) = pending {
                out.append((kind == "merge" ? "Merging" : (kind == "revert" ? "Reverting" : "Cherry-picking")) + " " + commit(i).id)
            }
            let start = out.count
            for p in Set(paths([h(),index,work])).union(conflicts).sorted() {
                if conflicts.contains(p) {
                    out.append("UU " + p)
                }
                else if index[p] != nil {
                    let x = h()[p] == nil ? "A" : (h()[p] != index[p] ? "M" : "."), y = work[p] == nil ? "D" : (work[p] != index[p] ? "M" : ".")
                    if x != "." || y != "." {
                        out.append(x + y + " " + p)
                    }
                }
                else {
                    if h()[p] != nil {
                        out.append("D. " + p)
                    }
                    if work[p] != nil && !ignored(p) {
                        out.append("?? " + p)
                    }
                }
            }
            if out.count == start {
                out.append("nothing to commit, working tree clean")
            }
            case "LS","CAT":
            let revision = c == "LS" ? a.first : (a.count > 1 ? a[1] : nil), tree: Tree
            if let revision {
                tree = commit(try resolve(revision)).tree
            } else {
                tree = work
            }
            if c == "CAT" {
                guard let value = tree[a[0]] else {
                    if let revision {
                        try fail("path '\(a[0])' does not exist in '\(revision)'")
                    }
                    try fail("no such file '\(a[0])'")
                }
                out.append(value)
            }
            else {
                out = tree.isEmpty ? ["(empty)"] : tree.keys.sorted().map {
                    $0 + " " + tree[$0]!
                }
            }
            case "DIFF":
            if a.isEmpty {
                out = changes(index,work.filter {
                    index[$0.key] != nil
                })
            }
            else if a[0] == "STAGED" {
                out = changes(h(),index)
            }
            else {
                let x = try resolve(a[0]), y = try resolve(a[1])
                out = changes(commit(x).tree,commit(y).tree)
            }
            case "LOG":
            let limit = a.first.map {
                Int($0)!
            } ?? Int.max
            var current = head, count = 0
            while count < limit {
                out.append(summary(current))
                count += 1
                guard let p = commit(current).parents.first else {
                    break
                }
                current = p
            }
            case "SHOW":
            let target = try resolve(a.first ?? "HEAD"), original = commit(target)
            out = ["commit " + summary(target),"parents: " + (original.parents.isEmpty ? "none" : original.parents.map {
                commit($0).id
            }.joined(separator: " "))]
            out += changes(original.parents.first.map {
                commit($0).tree
            } ?? [:],original.tree)
            case "BLAME":
            guard let value = h()[a[0]] else {
                try fail("path '\(a[0])' does not exist in 'HEAD'")
            }
            var i = head
            while let p = commit(i).parents.first {
                if commit(p).tree[a[0]] != value {
                    break
                }
                i = p
            }
            out.append("\(commit(i).id) (\(commit(i).message)) \(value)")
            case "BRANCH","TAG":
            let branch = c == "BRANCH", noun = branch ? "branch" : "tag"
            var refs = branch ? branches : tags
            if a[0] == "-d" {
                let name = a[1]
                guard let target = refs[name] else {
                    try fail("no such \(noun) '\(name)'")
                }
                if branch && attached == name {
                    try fail("cannot delete current branch '\(name)'")
                }
                if branch && !ancestor(target,head) {
                    try fail("branch '\(name)' is not fully merged")
                }
                refs.removeValue(forKey: name)
                out.append("Deleted \(noun) \(name) (was \(commit(target).id))")
            }
            else {
                let name = a[0]
                if refs[name] != nil {
                    try fail("\(noun) '\(name)' already exists")
                }
                let target = try resolve(a.count > 1 ? a[1] : "HEAD")
                refs[name] = target
                out.append("Created \(noun) \(name) at \(commit(target).id)")
            }
            if branch {
                branches = refs
            } else {
                tags = refs
            }
            case "BRANCHES":
            if attached == nil {
                out.append("* (HEAD detached at \(commit(head).id))")
            }
            for b in branches.keys.sorted() {
                let i = branches[b]!
                out.append("\(attached == b ? "*" : " ") \(b) \(commit(i).id) \(commit(i).message)")
            }
            case "TAGS": out = tags.isEmpty ? ["(no tags)"] : tags.keys.sorted().map {
                "\($0) \(commit(tags[$0]!).id) \(commit(tags[$0]!).message)"
            }
            case "SWITCH":
            guard let target = branches[a[0]] else {
                try fail("no such branch '\(a[0])'")
            }
            if attached == a[0] {
                out.append("Already on '\(a[0])'")
            } else {
                try inProgress()
                try switchTree(commit(target).tree)
                attached = a[0]
                head = target
                out.append("Switched to branch '\(a[0])'")
            }
            case "DETACH": let target = try resolve(a[0])
            try inProgress()
            try switchTree(commit(target).tree)
            attached = nil
            head = target
            out.append("HEAD is now at \(commit(target).id) \(commit(target).message)")
            case "MERGE":
            let target = try resolve(a[0])
            try inProgress()
            if ancestor(target,head) {
                out.append("Already up to date")
            }
            else if ancestor(head,target) {
                let old = head
                try switchTree(commit(target).tree)
                moveHead(target)
                out.append("Fast-forward \(commit(old).id)..\(commit(target).id)")
            }
            else {
                try clean()
                let base = mergeBase(head,target)
                out = try apply(commit(base).tree,commit(target).tree,"merge",target,"Merge " + a[0],[head,target],base)
            }
            case "MERGEBASE": let x = try resolve(a[0]), y = try resolve(a[1])
            out.append(commit(mergeBase(x,y)).id)
            case "REBASE":
            let target = try resolve(a[0])
            try inProgress()
            if ancestor(target,head) {
                return ["Already up to date"]
            }
            try clean()
            var list: [Int] = [], current = head
            while !ancestor(current,target) {
                list.append(current)
                current = commit(current).parents[0]
            }
            list.reverse()
            var tree = commit(target).tree, planned: [Tree?] = []
            for i in list {
                let original = commit(i), (merged,clashes) = threeWay(commit(original.parents[0]).tree,tree,original.tree)
                if let p = clashes.keys.sorted().first {
                    try fail("could not rebase \(original.id): conflict in '\(p)'")
                }
                if merged == tree {
                    planned.append(nil)
                } else {
                    planned.append(merged)
                    tree = merged
                }
            }
            try switchTree(tree)
            var parent = target
            for (position,i) in list.enumerated() {
                let original = commit(i)
                if let picked = planned[position] {
                    let next = create([parent],picked,original.message)
                    out.append("pick \(original.id) -> \(commit(next).id) \(original.message)")
                    parent = next
                } else {
                    out.append("skip \(original.id) \(original.message)")
                }
            }
            moveHead(parent)
            out.append("HEAD is now at \(commit(parent).id) \(commit(parent).message)")
            case "RESET":
            let target = try resolve(a[1]), tree = commit(target).tree
            if a[0] == "HARD" {
                for p in Set(paths([index,tree])).union(conflicts) {
                    matchPath(&work,tree,p)
                }
            }
            if a[0] != "SOFT" {
                index = tree
            }
            moveHead(target)
            conflicts.removeAll()
            pending = nil
            out.append("HEAD is now at \(commit(target).id) \(commit(target).message)")
            case "REVERT","CHERRYPICK":
            let target = try resolve(a[0])
            try inProgress()
            try clean()
            let original = commit(target), parent = original.parents.first.map {
                commit($0).tree
            } ?? [:]
            if c == "REVERT" {
                out = try apply(original.tree,parent,"revert",target,"Revert \"\(original.message)\"",[head])
            }
            else {
                out = try apply(parent,original.tree,"cherry-pick",target,original.message,[head])
            }
            case "STASH":
            if a.isEmpty {
                try inProgress()
                if !uncommitted() {
                    out.append("No local changes to save")
                }
                else {
                    let all = paths([index,h()]), saved = work.filter {
                        all.contains($0.key)
                    }, tree = h()
                    for p in all {
                        matchPath(&work,tree,p)
                    }
                    index = tree
                    let label = "WIP on \(attached ?? "(no branch)"): \(commit(head).id) \(commit(head).message)"
                    stashes.insert(Stash(label: label,base: head,tree: saved),at: 0)
                    out.append("Saved stash@{0}: " + label)
                }
            } else if a[0] == "LIST" {
                out = stashes.isEmpty ? ["(no stash entries)"] : stashes.enumerated().map {
                    "stash@{\($0.offset)}: \($0.element.label)"
                }
            }
            else {
                guard let stash = stashes.first else {
                    try fail("no stash entries")
                }
                if a[0] == "DROP" {
                    stashes.removeFirst()
                    out.append("Dropped stash@{0}: " + stash.label)
                }
                else {
                    try inProgress()
                    try clean()
                    let (merged,clashes) = threeWay(commit(stash.base).tree,h(),stash.tree)
                    if let p = clashes.keys.sorted().first {
                        try fail("stash conflict in '\(p)'")
                    }
                    let changed = differences(h(),merged)
                    try overwrite(Set(changed))
                    for p in changed {
                        matchPath(&work,merged,p)
                    }
                    stashes.removeFirst()
                    out.append("Restored stash@{0}: " + stash.label)
                    out += changes(h(),merged)
                }
            }
            case "GRAPH":
            var lanes: [Int] = []
            for i in reachable(false).sorted(by: >) {
                if !lanes.contains(i) {
                    lanes.append(i)
                }
                let k = lanes.firstIndex(of: i)!
                let symbols = lanes.enumerated().map {
                    $0.offset == k ? "*" : ($0.element == i ? "/" : "|")
                }.joined(separator: " ")
                out.append(symbols + " " + summary(i))
                if lanes.count > k + 1 {
                    for j in stride(from: lanes.count - 1, through: k + 1, by: -1) where lanes[j] == i {
                        lanes.remove(at: j)
                    }
                }
                let parents = commit(i).parents
                if parents.isEmpty {
                    lanes.remove(at: k)
                } else {
                    lanes[k] = parents[0]
                    if parents.count == 2 && !lanes.contains(parents[1]) {
                        lanes.insert(parents[1],at: k + 1)
                    }
                }
            }
            case "DESCRIBE":
            let target = try resolve(a.first ?? "HEAD"), distance = distances(target)
            let choices: [(Int,String)] = tags.compactMap {
                tag,i in distance[i].map {
                    ($0,tag)
                }
            }
            guard let (d,tag) = choices.min(by: {
                $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0
            }) else {
                try fail("no tag can describe '\(commit(target).id)'")
            }
            out.append(d == 0 ? tag : "\(tag)-\(d)-g\(commit(target).id)")
            case "GC":
            let keep = reachable(true)
            var count = 0
            for i in commits.indices where commits[i] != nil && !keep.contains(i) {
                commits[i] = nil
                count += 1
            }
            out.append("Removed unreachable commits: \(count)")
            default: fatalError("unknown command")
        }
        return out
    }
}
let repository = Repository()
while let line = readLine() {
    if line == "EXIT" {
        break
    }
    do {
        for line in try repository.command(line) {
            print(line)
        }
    }
    catch let p as Problem {
        print(p.text)
    }
    catch {
        fatalError("unexpected error")
    }
}
