#include "formatter.hpp"
DocPtr stringDoc(std::string value) {
    DocPtr out = std::make_shared<Doc>();
    out->value = std::move(value);
    return out;
}
DocPtr marker(DocKind kind) {
    DocPtr out = std::make_shared<Doc>();
    out->kind = kind;
    return out;
}
DocPtr cat(const Docs &docs) {
    Docs out;
    std::function<void(const DocPtr &)> add = [&](const DocPtr &doc) {
        if (!doc)
            return;
        if (doc->kind == DocKind::Concat) {
            for (const DocPtr &child : doc->children)
                add(child);
            return;
        }
        if (doc->kind == DocKind::Text) {
            if (doc->value.empty())
                return;
            if (!out.empty() && out.back()->kind == DocKind::Text) {
                out.back() = stringDoc(out.back()->value + doc->value);
                return;
            }
        }
        out.push_back(doc);
    };
    for (const DocPtr &doc : docs)
        add(doc);
    if (out.empty())
        return stringDoc("");
    if (out.size() == 1)
        return out[0];
    DocPtr result = marker(DocKind::Concat);
    result->children = std::move(out);
    return result;
}
static bool forceBroken(const DocPtr &doc) {
    if (doc->kind == DocKind::Hardline || doc->kind == DocKind::BreakParent)
        return true;
    for (const DocPtr &child : doc->children)
        if (forceBroken(child))
            return true;
    return false;
}
DocPtr group(const Docs &docs) {
    DocPtr out = marker(DocKind::Group);
    out->children = {cat(docs)};
    out->forced = forceBroken(out->children[0]);
    return out;
}
DocPtr nest(int amount, const Docs &docs) {
    DocPtr out = marker(DocKind::Nest);
    out->number = amount;
    out->children = {cat(docs)};
    return out;
}
DocPtr align(const Docs &docs) {
    DocPtr out = marker(DocKind::Align);
    out->children = {cat(docs)};
    return out;
}
DocPtr suffix(std::string value) {
    DocPtr out = marker(DocKind::Suffix);
    out->value = std::move(value);
    return out;
}
DocPtr ifBreak(std::string broken, std::string flat) {
    DocPtr out = marker(DocKind::IfBreak);
    out->value = std::move(broken);
    out->other = std::move(flat);
    return out;
}
GroupMetrics groupMetrics(const DocPtr &doc) {
    GroupMetrics out;
    if (doc->kind == DocKind::Group) {
        ++out.groups;
        if (doc->mode != Mode::Flat)
            ++out.broken;
        if (doc->mode == Mode::Forced)
            ++out.forced;
    }
    for (const DocPtr &child : doc->children) {
        GroupMetrics count = groupMetrics(child);
        out.groups += count.groups;
        out.broken += count.broken;
        out.forced += count.forced;
    }
    return out;
}
