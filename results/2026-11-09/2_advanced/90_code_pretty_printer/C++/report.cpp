#include "formatter.hpp"
Lines docTree(const DocPtr &doc, int depth) {
    std::string prefix(2 * depth, ' ');
    Lines out;
    switch (doc->kind) {
    case DocKind::Text:
        out.push_back(prefix + "text \"" + doc->value + "\"");
        break;
    case DocKind::Suffix:
        out.push_back(prefix + "suffix \"" + doc->value + "\"");
        break;
    case DocKind::IfBreak:
        out.push_back(prefix + "if_break \"" + doc->value + "\" \"" + doc->other + "\"");
        break;
    case DocKind::Line:
        out.push_back(prefix + "line");
        break;
    case DocKind::Softline:
        out.push_back(prefix + "softline");
        break;
    case DocKind::Hardline:
        out.push_back(prefix + "hardline");
        break;
    case DocKind::BreakParent:
        out.push_back(prefix + "break_parent");
        break;
    case DocKind::Concat:
        for (const DocPtr &child : doc->children)
            append(out, docTree(child, depth));
        break;
    default: {
        std::string label = doc->kind == DocKind::Group
                                ? "group " + std::string(doc->mode == Mode::Flat    ? "flat"
                                                         : doc->mode == Mode::Break ? "break"
                                                                                    : "forced")
                            : doc->kind == DocKind::Nest ? text("nest ", doc->number)
                                                         : "align";
        out.push_back(prefix + label);
        append(out, docTree(doc->children[0], depth + 1));
        break;
    }
    }
    return out;
}
Lines diffLines(const Lines &before, const Lines &after) {
    int n = static_cast<int>(before.size()), m = static_cast<int>(after.size());
    std::vector<std::vector<int>> lcs(n + 1, std::vector<int>(m + 1));
    for (int i = n - 1; i >= 0; --i)
        for (int j = m - 1; j >= 0; --j)
            lcs[i][j] = before[i] == after[j] ? lcs[i + 1][j + 1] + 1
                                              : std::max(lcs[i + 1][j], lcs[i][j + 1]);
    struct Hunk {
        int oldLine, newLine, deletes = 0, inserts = 0;
        Lines operations;
    };
    std::vector<Hunk> hunks;
    int i = 0, j = 0, deletes = 0, inserts = 0;
    while (i < n || j < m) {
        if (i < n && j < m && before[i] == after[j]) {
            ++i;
            ++j;
            continue;
        }
        Hunk hunk{i, j, 0, 0, {}};
        while ((i < n || j < m) && !(i < n && j < m && before[i] == after[j])) {
            if (j == m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1])) {
                hunk.operations.push_back("-" + before[i++]);
                ++hunk.deletes;
            } else {
                hunk.operations.push_back("+" + after[j++]);
                ++hunk.inserts;
            }
        }
        deletes += hunk.deletes;
        inserts += hunk.inserts;
        hunks.push_back(std::move(hunk));
    }
    Lines out{text("hunks=", hunks.size(), " deleted=", deletes, " inserted=", inserts)};
    for (const Hunk &hunk : hunks) {
        out.push_back(text("@@ -", hunk.oldLine + (hunk.deletes ? 1 : 0), ",", hunk.deletes, " +",
                           hunk.newLine + (hunk.inserts ? 1 : 0), ",", hunk.inserts, " @@"));
        append(out, hunk.operations);
    }
    return out;
}
