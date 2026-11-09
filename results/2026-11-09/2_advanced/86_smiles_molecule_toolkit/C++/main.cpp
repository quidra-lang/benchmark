#include "chemistry.hpp"
#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <set>
#include <stdexcept>

using Paragraph = std::vector<std::string>;
using Paragraphs = std::vector<Paragraph>;
static bool validName(const std::string &value) {
    return !value.empty() && value.size() <= 32 &&
           std::all_of(value.begin(), value.end(), [](char c) {
               return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' ||
                      c == '_' || c == '-';
           });
}
static std::optional<ParseError> analyze(Molecule &m, const Elements &elements) {
    detectRings(m);
    for (Bond &bond : m.bonds) {
        bond.type = symbolType(bond.symbol);
        if (!bond.type)
            bond.type = bond.ring && m.atoms[bond.a].aromatic && m.atoms[bond.b].aromatic ? 4 : 1;
    }
    if (auto failure = kekulize(m, elements))
        return failure;
    for (int i = 0; i < static_cast<int>(m.atoms.size()); ++i) {
        Atom &atom = m.atoms[i];
        if (atom.bracket) {
            if (m.multiplicity(i) + atom.hydrogens >
                elements.at(atom.symbol).valences.back() + std::abs(atom.charge))
                return ParseError{"bad valence", atom.column};
        } else {
            std::optional<int> h = m.organicHydrogens(i, elements);
            if (!h)
                return ParseError{"bad valence", atom.column};
            atom.hydrogens = *h;
        }
    }
    return std::nullopt;
}
static void properties(Molecule &m, const Elements &elements) {
    std::map<std::string, int> counts;
    int hydrogens = 0;
    std::vector<int> heavyDegree(m.atoms.size());
    std::vector<bool> triple(m.atoms.size());
    for (int i = 0; i < static_cast<int>(m.atoms.size()); ++i) {
        const Atom &atom = m.atoms[i];
        ++counts[atom.symbol];
        hydrogens += atom.hydrogens;
        m.charge += atom.charge;
        m.weight += atom.mass ? atom.mass * 1000 : elements.at(atom.symbol).weight;
        m.heavy += atom.symbol != "H";
        int attached = atom.hydrogens;
        for (int e : m.adjacent[i]) {
            const Bond &bond = m.bonds[e];
            if (m.atoms[bond.other(i)].symbol == "H")
                ++attached;
            else
                ++heavyDegree[i];
            if (bond.multiplicity == 3)
                triple[i] = true;
        }
        if (atom.symbol == "N" || atom.symbol == "O") {
            ++m.acceptors;
            if (attached)
                ++m.donors;
        }
    }
    counts["H"] += hydrogens;
    m.weight += hydrogens * elements.at("H").weight;
    std::vector<std::string> order;
    if (counts["C"] > 0) {
        order.push_back("C");
        if (counts["H"] > 0)
            order.push_back("H");
    }
    for (const auto &entry : counts)
        if (entry.second > 0 && (counts["C"] == 0 || (entry.first != "C" && entry.first != "H")))
            order.push_back(entry.first);
    for (const std::string &symbol : order) {
        m.formula += symbol;
        if (counts[symbol] > 1)
            m.formula += std::to_string(counts[symbol]);
    }
    for (const Bond &bond : m.bonds)
        if (bond.multiplicity == 1 && !bond.ring && heavyDegree[bond.a] >= 2 &&
            heavyDegree[bond.b] >= 2 && !triple[bond.a] && !triple[bond.b])
            ++m.rotatable;
    int violations = (m.weight > 500000) + (m.donors > 5) + (m.acceptors > 10);
    m.lipinski = violations < 2 ? "pass" : "fail";
}
static std::string scaffold(const Molecule &m, const Elements &elements) {
    if (m.rings.empty())
        return "";
    std::vector<bool> remaining(m.atoms.size(), true);
    for (;;) {
        int remove = -1;
        for (int a = 0; a < static_cast<int>(m.atoms.size()); ++a) {
            if (!remaining[a] || m.ringAtoms[a])
                continue;
            int degree = 0;
            for (int e : m.adjacent[a])
                degree += remaining[m.bonds[e].other(a)];
            if (degree == 1) {
                remove = a;
                break;
            }
        }
        if (remove < 0)
            break;
        remaining[remove] = false;
    }
    std::vector<bool> keep = remaining;
    for (const Bond &bond : m.bonds)
        if (bond.multiplicity == 2) {
            if (remaining[bond.a])
                keep[bond.b] = true;
            if (remaining[bond.b])
                keep[bond.a] = true;
        }
    Molecule result;
    std::vector<int> renumber(m.atoms.size(), -1);
    for (int a = 0; a < static_cast<int>(m.atoms.size()); ++a)
        if (keep[a]) {
            Atom atom = m.atoms[a];
            for (int e : m.adjacent[a])
                if (!keep[m.bonds[e].other(a)])
                    atom.hydrogens += m.bonds[e].multiplicity;
            renumber[a] = static_cast<int>(result.atoms.size());
            result.atoms.push_back(std::move(atom));
        }
    for (const Bond &bond : m.bonds)
        if (keep[bond.a] && keep[bond.b]) {
            Bond copy = bond;
            copy.a = renumber[bond.a];
            copy.b = renumber[bond.b];
            result.bonds.push_back(copy);
        }
    result.build();
    canonicalRanks(result, elements);
    return canonicalSmiles(result, elements);
}
static std::string ringRelation(const Molecule &m, const std::vector<int> &a,
                                const std::vector<int> &b) {
    std::vector<int> common;
    for (int atom : a)
        if (std::find(b.begin(), b.end(), atom) != b.end())
            common.push_back(atom);
    if (common.size() == 1)
        return "spiro";
    if (common.size() == 2 && m.bond(common[0], common[1]))
        return "fused";
    return common.size() >= 2 ? "bridged" : "";
}
struct RingSystem {
    std::vector<int> rings;
    std::string kind;
    int atoms;
};
static std::vector<RingSystem> ringSystems(const Molecule &m) {
    std::vector<std::vector<int>> adjacency(m.rings.size());
    for (int i = 0; i < static_cast<int>(m.rings.size()); ++i)
        for (int j = i + 1; j < static_cast<int>(m.rings.size()); ++j)
            if (!ringRelation(m, m.rings[i], m.rings[j]).empty()) {
                adjacency[i].push_back(j);
                adjacency[j].push_back(i);
            }
    std::vector<bool> seen(m.rings.size());
    std::vector<RingSystem> result;
    for (int first = 0; first < static_cast<int>(m.rings.size()); ++first) {
        if (seen[first])
            continue;
        std::vector<int> queue = {first};
        seen[first] = true;
        for (std::size_t h = 0; h < queue.size(); ++h)
            for (int next : adjacency[queue[h]])
                if (!seen[next]) {
                    seen[next] = true;
                    queue.push_back(next);
                }
        std::sort(queue.begin(), queue.end());
        std::set<int> atoms;
        std::string kind = queue.size() == 1 ? "isolated" : "spiro";
        for (std::size_t i = 0; i < queue.size(); ++i) {
            atoms.insert(m.rings[queue[i]].begin(), m.rings[queue[i]].end());
            for (std::size_t j = i + 1; j < queue.size(); ++j) {
                std::string relation = ringRelation(m, m.rings[queue[i]], m.rings[queue[j]]);
                if (relation == "bridged")
                    kind = "bridged";
                else if (relation == "fused" && kind != "bridged")
                    kind = "fused";
            }
        }
        result.push_back({queue, kind, static_cast<int>(atoms.size())});
    }
    return result;
}
static bool ringAromatic(const Molecule &m, const std::vector<int> &ring) {
    for (int atom : ring)
        if (!m.atoms[atom].aromatic)
            return false;
    return true;
}
static std::string integers(const std::vector<int> &values, const std::string &separator,
                            int offset = 0) {
    std::vector<std::string> parts;
    for (int value : values)
        parts.push_back(std::to_string(value + offset));
    return join(parts, separator);
}
static std::string memberNames(const std::vector<Molecule> &molecules,
                               const std::vector<int> &indices) {
    std::vector<std::string> names;
    for (int i : indices)
        names.push_back(molecules[i].name);
    return join(names, ",");
}
static Paragraphs canonicalParagraphs(const std::vector<Molecule> &molecules) {
    std::map<std::string, std::vector<int>> canonGroups, formulaGroups, scaffoldGroups;
    std::vector<std::string> canonOrder, formulaOrder;
    int acyclic = 0;
    for (int i = 0; i < static_cast<int>(molecules.size()); ++i) {
        const Molecule &m = molecules[i];
        if (!canonGroups.count(m.canonical))
            canonOrder.push_back(m.canonical);
        canonGroups[m.canonical].push_back(i);
        if (!formulaGroups.count(m.formula))
            formulaOrder.push_back(m.formula);
        formulaGroups[m.formula].push_back(i);
        if (m.scaffold.empty())
            ++acyclic;
        else
            scaffoldGroups[m.scaffold].push_back(i);
    }
    Paragraph canonical = {
        text("CANONICAL molecules=", molecules.size(), " unique=", canonGroups.size())};
    for (const Molecule &m : molecules)
        canonical.push_back(text(m.name, " ", m.canonical, " classes=", m.classes,
                                 " charge=", m.charge > 0 ? "+" : "", m.charge));
    Paragraph duplicates, isomers;
    int duplicateCount = 0, duplicateMolecules = 0, isomerCount = 0;
    for (const std::string &key : canonOrder) {
        const std::vector<int> &indices = canonGroups.at(key);
        if (indices.size() < 2)
            continue;
        ++duplicateCount;
        duplicateMolecules += static_cast<int>(indices.size());
        duplicates.push_back(
            text("group ", duplicateCount, " ", key, " members=", memberNames(molecules, indices)));
    }
    duplicates.insert(duplicates.begin(), text("DUPLICATES groups=", duplicateCount,
                                               " molecules=", duplicateMolecules));
    for (const std::string &formula : formulaOrder) {
        const std::vector<int> &indices = formulaGroups.at(formula);
        std::set<std::string> forms;
        for (int i : indices)
            forms.insert(molecules[i].canonical);
        if (forms.size() < 2)
            continue;
        isomers.push_back(text("isomer ", ++isomerCount, " ", formula, " forms=", forms.size(),
                               " members=", memberNames(molecules, indices)));
    }
    isomers.insert(isomers.begin(), text("ISOMERS groups=", isomerCount));
    Paragraph scaffolds = {
        text("SCAFFOLDS distinct=", scaffoldGroups.size(), " acyclic=", acyclic)};
    std::vector<std::string> keys;
    for (const auto &entry : scaffoldGroups)
        keys.push_back(entry.first);
    std::sort(keys.begin(), keys.end(), [&](const std::string &a, const std::string &b) {
        return scaffoldGroups.at(a).size() != scaffoldGroups.at(b).size()
                   ? scaffoldGroups.at(a).size() > scaffoldGroups.at(b).size()
                   : a < b;
    });
    for (std::size_t i = 0; i < keys.size(); ++i)
        scaffolds.push_back(text("scaffold ", i + 1, " ", keys[i],
                                 " count=", scaffoldGroups.at(keys[i]).size(),
                                 " members=", memberNames(molecules, scaffoldGroups.at(keys[i]))));
    return {canonical, duplicates, isomers, scaffolds};
}
static Paragraphs ringParagraphs(const std::vector<Molecule> &molecules) {
    Paragraphs result;
    int cyclic = 0, total = 0, aromatic = 0;
    std::map<int, int> sizes;
    std::map<std::string, int> kinds;
    for (const Molecule &m : molecules) {
        if (m.rings.empty())
            continue;
        ++cyclic;
        total += static_cast<int>(m.rings.size());
        std::vector<RingSystem> systems = ringSystems(m);
        int aromaticCount = 0, ringBonds = 0,
            ringAtoms = static_cast<int>(std::count(m.ringAtoms.begin(), m.ringAtoms.end(), true));
        for (const Bond &bond : m.bonds)
            ringBonds += bond.ring;
        for (const std::vector<int> &ring : m.rings) {
            ++sizes[static_cast<int>(ring.size())];
            aromaticCount += ringAromatic(m, ring);
        }
        aromatic += aromaticCount;
        Paragraph paragraph = {text("MOLECULE ", m.name, " atoms=", m.atoms.size(),
                                    " bonds=", m.bonds.size(), " rings=", m.rings.size(),
                                    " aromatic=", aromaticCount, " systems=", systems.size(),
                                    " ring_atoms=", ringAtoms, " ring_bonds=", ringBonds)};
        for (std::size_t i = 0; i < m.rings.size(); ++i) {
            int hetero = 0;
            for (int atom : m.rings[i])
                hetero += m.atoms[atom].symbol != "C";
            paragraph.push_back(text("ring ", i + 1, " size=", m.rings[i].size(),
                                     " aromatic=", ringAromatic(m, m.rings[i]) ? "yes" : "no",
                                     " hetero=", hetero, " atoms=", integers(m.rings[i], "-", 1)));
        }
        for (std::size_t i = 0; i < systems.size(); ++i) {
            const RingSystem &s = systems[i];
            ++kinds[s.kind];
            paragraph.push_back(text("system ", i + 1, " kind=", s.kind,
                                     " rings=", integers(s.rings, ",", 1), " atoms=", s.atoms));
        }
        std::vector<std::string> doubleBonds;
        for (const Bond &bond : m.bonds)
            if (bond.type == 4 && bond.multiplicity == 2)
                doubleBonds.push_back(text(bond.a + 1, "=", bond.b + 1));
        paragraph.push_back("kekule " + (doubleBonds.empty() ? "-" : join(doubleBonds, " ")));
        result.push_back(std::move(paragraph));
    }
    std::string sizeLine = "sizes";
    for (const auto &entry : sizes)
        sizeLine += text(" ", entry.first, "=", entry.second);
    if (sizes.empty())
        sizeLine += " -";
    result.push_back({text("SUMMARY molecules=", molecules.size(), " cyclic=", cyclic,
                           " rings=", total, " aromatic=", aromatic),
                      sizeLine,
                      text("systems isolated=", kinds["isolated"], " fused=", kinds["fused"],
                           " spiro=", kinds["spiro"], " bridged=", kinds["bridged"])});
    return result;
}
struct Query {
    std::string kind, id;
    std::vector<std::string> arguments;
    Molecule pattern;
    Fraction threshold;
    int count = 0;
};
static bool number(const std::string &value, int low, int high) {
    if (value.empty() || value.size() > 2 || (value.size() > 1 && value[0] == '0') ||
        !std::all_of(value.begin(), value.end(), digit))
        return false;
    int n = std::stoi(value);
    return n >= low && n <= high;
}
static std::optional<Fraction> threshold(const std::string &value) {
    std::vector<std::string> a = split(value, '/');
    if (a.size() != 2 || !number(a[0], 0, 99) || !number(a[1], 1, 99))
        return std::nullopt;
    int n = std::stoi(a[0]), d = std::stoi(a[1]);
    return n <= d ? std::optional<Fraction>(Fraction(n, d)) : std::nullopt;
}
static std::pair<std::optional<Query>, std::string>
checkQuery(const std::vector<std::string> &tokens, std::set<std::string> &seen,
           const std::map<std::string, int> &byName, const Elements &elements) {
    static const std::set<std::string> kinds = {"MATCH",  "CONTAINS", "MATRIX", "NEAREST",
                                                "WITHIN", "COMPARE",  "CLUSTER"};
    const std::string &kind = tokens[0];
    if (!kinds.count(kind))
        return {std::nullopt, "unknown query"};
    if (tokens.size() == 1 || !validName(tokens[1]))
        return {std::nullopt, "bad id"};
    const std::string &id = tokens[1];
    if (!seen.insert(id).second)
        return {std::nullopt, "duplicate id"};
    std::vector<std::string> args(tokens.begin() + 2, tokens.end());
    bool length = kind == "MATCH" || kind == "CLUSTER" ? args.size() == 1
                  : kind == "MATRIX"                   ? args.size() >= 2 && args.size() <= 12
                                                       : args.size() == 2;
    if (!length)
        return {std::nullopt, "bad arguments"};
    Query q;
    q.kind = kind;
    q.id = id;
    q.arguments = args;
    if (kind == "MATCH") {
        Parsed parsed = parseSmiles(args[0], elements, true);
        if (parsed.error)
            return {std::nullopt, text("bad pattern ", parsed.error->reason, " at column ",
                                       parsed.error->column)};
        q.pattern = std::move(*parsed.molecule);
    } else if (kind == "CLUSTER") {
        std::optional<Fraction> value = threshold(args[0]);
        if (!value)
            return {std::nullopt, "bad threshold"};
        q.threshold = *value;
    } else if (kind == "CONTAINS" || kind == "MATRIX" || kind == "COMPARE") {
        for (const std::string &name : args)
            if (!byName.count(name))
                return {std::nullopt, "unknown molecule " + name};
        std::set<std::string> names(args.begin(), args.end());
        if (names.size() != args.size())
            return {std::nullopt, "repeated molecule"};
    } else {
        if (!byName.count(args[0]))
            return {std::nullopt, "unknown molecule " + args[0]};
        if (kind == "NEAREST") {
            if (!number(args[1], 1, 99))
                return {std::nullopt, "bad count"};
            q.count = std::stoi(args[1]);
        } else {
            std::optional<Fraction> value = threshold(args[1]);
            if (!value)
                return {std::nullopt, "bad threshold"};
            q.threshold = *value;
        }
    }
    return {std::move(q), ""};
}
static Paragraphs substructureParagraphs(const std::vector<Query> &queries,
                                         const std::vector<Molecule> &molecules,
                                         const std::map<std::string, int> &byName) {
    Paragraphs paragraphs;
    int patterns = 0, hits = 0, contains = 0, found = 0;
    for (const Query &q : queries) {
        if (q.kind == "MATCH") {
            ++patterns;
            Paragraph hitLines;
            int total = 0, topCount = 0;
            std::string top;
            for (const Molecule &m : molecules) {
                Embeddings result = embeddings(q.pattern, m);
                if (!result.count)
                    continue;
                ++hits;
                total += result.count;
                hitLines.push_back(text(m.name, " count=", result.count, " unique=", result.unique,
                                        " map=", integers(result.first, ",")));
                if (result.count > topCount) {
                    top = m.name;
                    topCount = result.count;
                }
            }
            Paragraph paragraph = {text("MATCH ", q.id, " ", q.arguments[0], " atoms=",
                                        q.pattern.atoms.size(), " bonds=", q.pattern.bonds.size(),
                                        " hits=", hitLines.size(), " embeddings=", total)};
            paragraph.insert(paragraph.end(), hitLines.begin(), hitLines.end());
            if (!top.empty())
                paragraph.push_back(text("top ", top, " count=", topCount));
            paragraphs.push_back(std::move(paragraph));
        } else if (q.kind == "CONTAINS") {
            ++contains;
            const Molecule &x = molecules[byName.at(q.arguments[0])],
                           &y = molecules[byName.at(q.arguments[1])];
            Embeddings result = embeddings(moleculePattern(x), y);
            std::string value = text("CONTAINS ", q.id, " ", x.name, " ", y.name, " result=");
            if (result.count) {
                ++found;
                value += text("yes count=", result.count, " unique=", result.unique,
                              " map=", integers(result.first, ","));
            } else
                value += "no";
            paragraphs.push_back({value});
        }
    }
    paragraphs.push_back({text("SUMMARY patterns=", patterns, " hits=", hits,
                               " contains=", contains, " found=", found)});
    return paragraphs;
}
static Paragraphs similarityParagraphs(const std::vector<Query> &queries,
                                       const std::vector<Molecule> &molecules,
                                       const std::map<std::string, int> &byName) {
    int n = static_cast<int>(molecules.size());
    std::vector<std::vector<Similarity>> matrix(n, std::vector<Similarity>(n));
    for (int i = 0; i < n; ++i)
        for (int j = i; j < n; ++j)
            matrix[i][j] = matrix[j][i] = similarity(molecules[i], molecules[j]);
    Paragraph fingerprints = {text("FINGERPRINTS molecules=", n, " size=1024 depth=5")};
    for (const Molecule &m : molecules)
        fingerprints.push_back(text(m.name, " bits=", m.bits.count(), " paths=", m.paths));
    Paragraphs output = {fingerprints};
    for (const Query &q : queries) {
        const std::vector<std::string> &args = q.arguments;
        Paragraph paragraph;
        if (q.kind == "MATRIX") {
            std::vector<int> indices;
            for (const std::string &name : args)
                indices.push_back(byName.at(name));
            paragraph.push_back(text("MATRIX ", q.id, " size=", args.size()));
            int bestI = 0, bestJ = 1;
            for (int i = 0; i < static_cast<int>(indices.size()); ++i) {
                std::vector<std::string> values;
                for (int j = 0; j < static_cast<int>(indices.size()); ++j) {
                    values.push_back(matrix[indices[i]][indices[j]].value.text());
                    if (i < j && matrix[indices[i]][indices[j]].value.compare(
                                     matrix[indices[bestI]][indices[bestJ]].value) > 0) {
                        bestI = i;
                        bestJ = j;
                    }
                }
                paragraph.push_back("row " + args[i] + " " + join(values, " "));
            }
            paragraph.push_back(text("best ", args[bestI], " ", args[bestJ], " ",
                                     matrix[indices[bestI]][indices[bestJ]].value.text()));
        } else if (q.kind == "NEAREST" || q.kind == "WITHIN") {
            int base = byName.at(args[0]);
            std::vector<int> order;
            for (int i = 0; i < n; ++i)
                if (i != base)
                    order.push_back(i);
            std::stable_sort(order.begin(), order.end(), [&](int a, int b) {
                return matrix[base][a].value.compare(matrix[base][b].value) > 0;
            });
            if (q.kind == "NEAREST") {
                if (order.size() > static_cast<std::size_t>(q.count))
                    order.resize(q.count);
                paragraph.push_back(text("NEAREST ", q.id, " ", args[0], " count=", order.size()));
            } else {
                order.erase(std::remove_if(order.begin(), order.end(),
                                           [&](int i) {
                                               return matrix[base][i].value.compare(q.threshold) <
                                                      0;
                                           }),
                            order.end());
                paragraph.push_back(text("WITHIN ", q.id, " ", args[0], " threshold=",
                                         q.threshold.text(), " count=", order.size()));
            }
            for (std::size_t i = 0; i < order.size(); ++i) {
                const Similarity &value = matrix[base][order[i]];
                paragraph.push_back(text(i + 1, " ", molecules[order[i]].name, " ",
                                         value.value.text(), " common=", value.common));
            }
        } else if (q.kind == "COMPARE") {
            int a = byName.at(args[0]), b = byName.at(args[1]);
            const Similarity &value = matrix[a][b];
            paragraph.push_back(text(
                "COMPARE ", q.id, " ", args[0], " ", args[1], " bits=", molecules[a].bits.count(),
                ",", molecules[b].bits.count(), " common=", value.common, " union=", value.total,
                " tanimoto=", value.value.text(),
                " identical=", molecules[a].canonical == molecules[b].canonical ? "yes" : "no"));
        } else if (q.kind == "CLUSTER") {
            std::vector<std::vector<int>> neighbors(n);
            std::vector<int> order(n);
            std::iota(order.begin(), order.end(), 0);
            for (int i = 0; i < n; ++i)
                for (int j = 0; j < n; ++j)
                    if (i != j && matrix[i][j].value.compare(q.threshold) >= 0)
                        neighbors[i].push_back(j);
            std::stable_sort(order.begin(), order.end(), [&](int a, int b) {
                return neighbors[a].size() > neighbors[b].size();
            });
            std::vector<bool> assigned(n);
            std::vector<std::vector<int>> clusters;
            int singletons = 0;
            for (int center : order) {
                if (assigned[center])
                    continue;
                std::vector<int> members = {center};
                assigned[center] = true;
                for (int neighbor : neighbors[center])
                    if (!assigned[neighbor]) {
                        members.push_back(neighbor);
                        assigned[neighbor] = true;
                    }
                singletons += members.size() == 1;
                clusters.push_back(std::move(members));
            }
            paragraph.push_back(text("CLUSTER ", q.id, " threshold=", q.threshold.text(),
                                     " clusters=", clusters.size(), " singletons=", singletons));
            int number = 0;
            for (const std::vector<int> &members : clusters)
                if (members.size() > 1)
                    paragraph.push_back(text(
                        "cluster ", ++number, " centroid=", molecules[members.front()].name,
                        " size=", members.size(), " members=", memberNames(molecules, members)));
        }
        if (!paragraph.empty())
            output.push_back(std::move(paragraph));
    }
    return output;
}
static void writeLines(const std::string &name, const Paragraph &lines) {
    std::ofstream file("output/" + name);
    if (!file)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        file << line << '\n';
}
static void writeParagraphs(const std::string &name, const Paragraphs &paragraphs) {
    Paragraph output;
    for (const Paragraph &paragraph : paragraphs)
        if (!paragraph.empty()) {
            if (!output.empty())
                output.push_back("");
            output.insert(output.end(), paragraph.begin(), paragraph.end());
        }
    writeLines(name, output);
}
int main() {
    Elements elements = readElements();
    std::vector<Molecule> molecules;
    std::map<std::string, int> byName, causes;
    std::set<std::string> seenNames;
    Paragraph moleculeErrors, queryErrors;
    int moleculeLines = 0, queryLines = 0;
    std::vector<std::string> source = readLines("input/molecules.smi");
    for (std::size_t i = 0; i < source.size(); ++i) {
        if (ignored(source[i]))
            continue;
        ++moleculeLines;
        std::vector<std::string> tokens = split(source[i], ' ');
        if (tokens.size() != 2 || tokens[0].empty() || !validName(tokens[1])) {
            moleculeErrors.push_back(text("line ", i + 1, ": bad line"));
            ++causes["bad line"];
            continue;
        }
        const std::string &name = tokens[1];
        if (!seenNames.insert(name).second) {
            moleculeErrors.push_back(text("line ", i + 1, " ", name, ": duplicate name"));
            ++causes["duplicate name"];
            continue;
        }
        Parsed parsed = parseSmiles(tokens[0], elements, false);
        if (!parsed.error)
            parsed.error = analyze(*parsed.molecule, elements);
        if (parsed.error) {
            moleculeErrors.push_back(text("line ", i + 1, " ", name, ": ", parsed.error->reason,
                                          " at column ", parsed.error->column));
            ++causes[parsed.error->reason];
            continue;
        }
        Molecule molecule = std::move(*parsed.molecule);
        molecule.name = name;
        properties(molecule, elements);
        canonicalRanks(molecule, elements);
        molecule.canonical = canonicalSmiles(molecule, elements);
        molecule.scaffold = scaffold(molecule, elements);
        fingerprint(molecule, elements);
        byName[name] = static_cast<int>(molecules.size());
        molecules.push_back(std::move(molecule));
    }
    std::vector<Query> queries;
    std::set<std::string> seenIds;
    source = readLines("input/queries.txt");
    for (std::size_t i = 0; i < source.size(); ++i) {
        if (ignored(source[i]))
            continue;
        ++queryLines;
        std::vector<std::string> tokens = split(source[i], ' ');
        auto checked = checkQuery(tokens, seenIds, byName, elements);
        if (!checked.second.empty()) {
            const std::string &reason = checked.second;
            std::string error = text("line ", i + 1);
            if (reason == "unknown query")
                error += ": unknown query";
            else if (reason == "bad id")
                error += " " + tokens[0] + ": bad id";
            else
                error += " " + tokens[0] + " " + tokens[1] + ": " + reason;
            queryErrors.push_back(error);
            std::string cause = reason;
            if (cause.compare(0, 12, "bad pattern ") == 0)
                cause = "bad pattern";
            if (cause.compare(0, 17, "unknown molecule ") == 0)
                cause = "unknown molecule";
            ++causes[cause];
        } else
            queries.push_back(std::move(*checked.first));
    }
    Paragraph propertiesLines = {
        "name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"};
    for (const Molecule &m : molecules) {
        std::ostringstream row;
        row << m.name << ',' << m.formula << ',' << m.weight / 1000 << '.' << std::setw(3)
            << std::setfill('0') << m.weight % 1000 << ',' << m.heavy << ',' << m.rings.size()
            << ',' << m.rotatable << ',' << m.donors << ',' << m.acceptors << ',' << m.lipinski;
        propertiesLines.push_back(row.str());
    }
    moleculeErrors.insert(moleculeErrors.begin(),
                          text("MOLECULES lines=", moleculeLines, " valid=", molecules.size(),
                               " errors=", moleculeErrors.size()));
    queryErrors.insert(queryErrors.begin(), text("QUERIES lines=", queryLines, " valid=",
                                                 queries.size(), " errors=", queryErrors.size()));
    std::vector<std::string> names;
    for (const auto &entry : causes)
        names.push_back(entry.first);
    std::sort(names.begin(), names.end(), [&](const std::string &a, const std::string &b) {
        return causes[a] != causes[b] ? causes[a] > causes[b] : a < b;
    });
    Paragraph causeLines = {text("CAUSES kinds=", causes.size())};
    for (const std::string &name : names)
        causeLines.push_back(text(name, "=", causes[name]));
    std::filesystem::create_directories("output");
    writeLines("properties.csv", propertiesLines);
    writeParagraphs("canonical.txt", canonicalParagraphs(molecules));
    writeParagraphs("rings.txt", ringParagraphs(molecules));
    writeParagraphs("substructure.txt", substructureParagraphs(queries, molecules, byName));
    writeParagraphs("similarity.txt", similarityParagraphs(queries, molecules, byName));
    writeParagraphs("errors.txt", {moleculeErrors, queryErrors, causeLines});
}
