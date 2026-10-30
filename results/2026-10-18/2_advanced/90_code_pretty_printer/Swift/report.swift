enum Report {
    static func tree(_ document: Document, _ depth: Int, _ modes: [Int: String], _ out: inout [String]) {
        let prefix = String(repeating: " ", count: depth * 2)
        switch document {
            case .concat(let parts): for part in parts {
                tree(part, depth, modes, &out)
            }
            case .text(let string): out.append(prefix + "text \"\(string)\"")
            case .suffix(let string): out.append(prefix + "suffix \"\(string)\"")
            case .ifBreak(let a, let b): out.append(prefix + "if_break \"\(a)\" \"\(b)\"")
            case .group(let id, let child): out.append(prefix + "group \(modes[id]!)");
            tree(child, depth + 1, modes, &out)
            case .nest(let n, let child): out.append(prefix + "nest \(n)");
            tree(child, depth + 1, modes, &out)
            case .align(let child): out.append(prefix + "align");
            tree(child, depth + 1, modes, &out)
            case .line: out.append(prefix + "line")
            case .softline: out.append(prefix + "softline")
            case .hardline: out.append(prefix + "hardline")
            case .breakParent: out.append(prefix + "break_parent")
        }
    }
    static func diff(_ a: [String], _ b: [String]) -> [String] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in (0..<n).reversed() {
            for j in (0..<m).reversed() {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var i = 0, j = 0, deleted = 0, inserted = 0, hunks: [(Int, Int, Int, Int, [String])] = []
        while i < n || j < m {
            if i < n && j < m && a[i] == b[j] {
                i += 1;
                j += 1;
                continue
            }
            let i0 = i, j0 = j
            var d = 0, e = 0, lines: [String] = []
            while i < n || j < m {
                if i < n && j < m && a[i] == b[j] {
                    break
                }
                if j == m || i < n && lcs[i + 1][j] >= lcs[i][j + 1] {
                    lines.append("-" + a[i]);
                    i += 1;
                    d += 1
                }
                else {
                    lines.append("+" + b[j]);
                    j += 1;
                    e += 1
                }
            }
            deleted += d;
            inserted += e;
            hunks.append((i0, j0, d, e, lines))
        }
        var result = ["hunks=\(hunks.count) deleted=\(deleted) inserted=\(inserted)"]
        for (i, j, d, e, lines) in hunks {
            result.append("@@ -\(d > 0 ? i + 1 : i),\(d) +\(e > 0 ? j + 1 : j),\(e) @@");
            result += lines
        }
        return result
    }
}
