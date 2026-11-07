#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using std::string;
using std::vector;

constexpr std::int64_t scale = std::int64_t{1} << 37;

int sex_index(char sex) {
    return sex == 'M' ? 0 : sex == 'F' ? 1 : 2;
}

string gendered(const string &kind, char sex) {
    static const std::map<string, std::array<string, 3>> terms = {
        {"parent", {"father", "mother", "parent"}},
        {"child", {"son", "daughter", "child"}},
        {"sibling", {"brother", "sister", "sibling"}},
        {"pibling", {"uncle", "aunt", "pibling"}},
        {"nibling", {"nephew", "niece", "nibling"}},
        {"spouse", {"husband", "wife", "spouse"}},
        {"late", {"late husband", "late wife", "late spouse"}},
        {"survivor", {"widower", "widow", "surviving spouse"}},
        {"ex", {"ex-husband", "ex-wife", "ex-spouse"}},
        {"stepparent", {"stepfather", "stepmother", "stepparent"}},
        {"stepchild", {"stepson", "stepdaughter", "stepchild"}},
        {"stepsibling", {"stepbrother", "stepsister", "stepsibling"}},
        {"stepgrandparent", {"stepgrandfather", "stepgrandmother", "stepgrandparent"}},
        {"stepgrandchild", {"stepgrandson", "stepgranddaughter", "stepgrandchild"}},
        {"parent-in-law", {"father-in-law", "mother-in-law", "parent-in-law"}},
        {"child-in-law", {"son-in-law", "daughter-in-law", "child-in-law"}},
        {"sibling-in-law", {"brother-in-law", "sister-in-law", "sibling-in-law"}},
    };
    return terms.at(kind)[sex_index(sex)];
}

string generation_prefix(int g) {
    if (g == 1)
        return "";
    string prefix;
    for (int i = 2; i < g; ++i)
        prefix += "great-";
    return prefix + "grand";
}

string ordinal(int k) {
    static const std::array<string, 10> words = {"first", "second",  "third",  "fourth", "fifth",
                                                 "sixth", "seventh", "eighth", "ninth",  "tenth"};
    if (k <= 10)
        return words[k - 1];
    string suffix = "th";
    if (k % 100 < 11 || k % 100 > 13) {
        if (k % 10 == 1)
            suffix = "st";
        if (k % 10 == 2)
            suffix = "nd";
        if (k % 10 == 3)
            suffix = "rd";
    }
    return std::to_string(k) + suffix;
}

string term(int da, int db, char sex) {
    if (da == 0 && db == 0)
        return "self";
    if (da == 0)
        return generation_prefix(db) + gendered("parent", sex);
    if (db == 0)
        return generation_prefix(da) + gendered("child", sex);
    if (da == 1 && db == 1)
        return gendered("sibling", sex);
    if (da == 1)
        return generation_prefix(db - 1) + gendered("pibling", sex);
    if (db == 1)
        return generation_prefix(da - 1) + gendered("nibling", sex);
    int removed = std::abs(da - db);
    string removal;
    if (removed == 1)
        removal = " once removed";
    else if (removed == 2)
        removal = " twice removed";
    else if (removed >= 3)
        removal = " " + std::to_string(removed) + " times removed";
    return ordinal(std::min(da, db) - 1) + " cousin" + removal;
}

string fraction(std::int64_t value) {
    std::int64_t divisor = std::gcd(value, scale);
    return std::to_string(value / divisor) + "/" + std::to_string(scale / divisor);
}

bool has(const vector<string> &ids, const string &id) {
    return std::find(ids.begin(), ids.end(), id) != ids.end();
}

string join(const vector<string> &parts, const string &separator) {
    string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i != 0)
            result += separator;
        result += parts[i];
    }
    return result;
}

struct Person {
    char sex;
    int birth;
    string name;
    int death = 0;
    vector<string> parents;

    string life() const {
        return std::to_string(birth) + "-" + (death ? std::to_string(death) : "");
    }
};

struct Marriage {
    string first, second;
    int start;
    int end = 0;
    string status = "current";
    string died;

    bool contains(const string &id) const {
        return first == id || second == id;
    }
    string other(const string &id) const {
        return first == id ? second : first;
    }
};

struct Apex {
    string person;
    int da = 0, db = 0, shares = 0;

    explicit operator bool() const {
        return !person.empty();
    }
    string blood_term(char sex) const {
        string prefix = shares == 1 ? "half-" : shares >= 4 ? "double " : "";
        return prefix + term(da, db, sex);
    }
};

class Family {
    std::map<std::pair<string, bool>, std::map<string, int>> distance_cache;
    std::map<std::pair<string, string>, std::int64_t> coefficient_cache;

  public:
    std::map<string, Person> persons;
    vector<Marriage> marriages;

    Family snapshot() const {
        Family copy;
        copy.persons = persons;
        copy.marriages = marriages;
        return copy;
    }

    void invalidate() {
        distance_cache.clear();
        coefficient_cache.clear();
    }

    Person &person(const string &id) {
        auto it = persons.find(id);
        if (it == persons.end())
            throw std::runtime_error("UNKNOWN PERSON " + id);
        return it->second;
    }

    vector<string> ids() const {
        vector<string> result;
        for (const auto &[id, p] : persons)
            result.push_back(id);
        return result;
    }

    bool age_less(const string &a, const string &b) const {
        return std::tie(persons.at(a).birth, a) < std::tie(persons.at(b).birth, b);
    }

    vector<string> age_order(vector<string> ids) const {
        std::sort(ids.begin(), ids.end(),
                  [this](const string &a, const string &b) { return age_less(a, b); });
        return ids;
    }

    string person_list(const vector<string> &ids) const {
        return ids.empty() ? "-" : join(age_order(ids), " ");
    }

    vector<string> children(const string &x) const {
        vector<string> result;
        for (const auto &[id, p] : persons)
            if (has(p.parents, x))
                result.push_back(id);
        return result;
    }

    int common_parents(const string &a, const string &b) const {
        int count = 0;
        for (const string &p : persons.at(a).parents)
            if (has(persons.at(b).parents, p))
                ++count;
        return count;
    }

    bool are_siblings(const string &a, const string &b) const {
        return a != b && common_parents(a, b) > 0;
    }

    vector<string> siblings(const string &x) const {
        vector<string> result;
        for (const auto &[y, p] : persons)
            if (are_siblings(x, y))
                result.push_back(y);
        return result;
    }

    Marriage *current(const string &x) {
        for (Marriage &m : marriages)
            if (m.status == "current" && m.contains(x))
                return &m;
        return nullptr;
    }

    string spouse(const string &x) {
        Marriage *m = current(x);
        return m ? m->other(x) : "";
    }

    const Marriage *last(const string &a, const string &b) const {
        for (auto it = marriages.rbegin(); it != marriages.rend(); ++it)
            if (it->contains(a) && it->contains(b))
                return &*it;
        return nullptr;
    }

    std::set<string> partners(const string &x) const {
        std::map<string, const Marriage *> latest;
        for (const Marriage &m : marriages)
            if (m.contains(x))
                latest[m.other(x)] = &m;
        std::set<string> result;
        for (const auto &[y, m] : latest)
            if (m->status != "divorced")
                result.insert(y);
        return result;
    }

    bool step_related(const string &a, const string &b) const {
        for (const string &p : persons.at(a).parents) {
            std::set<string> partners_p = partners(p);
            for (const string &q : persons.at(b).parents)
                if (partners_p.count(q))
                    return true;
        }
        return false;
    }

    const std::map<string, int> &distances(const string &start, bool upward) {
        std::pair<string, bool> key{start, upward};
        auto cached = distance_cache.find(key);
        if (cached != distance_cache.end())
            return cached->second;
        std::map<string, int> result{{start, 0}};
        vector<string> queue{start};
        for (std::size_t i = 0; i < queue.size(); ++i) {
            string x = queue[i];
            vector<string> adjacent = upward ? persons.at(x).parents : children(x);
            for (const string &y : adjacent) {
                if (result.count(y))
                    continue;
                result[y] = result.at(x) + 1;
                queue.push_back(y);
            }
        }
        return distance_cache.emplace(key, std::move(result)).first->second;
    }

    bool ancestor(const string &a, const string &b) {
        return a != b && distances(b, true).count(a);
    }

    vector<string> grandparents(const string &x) {
        vector<string> result;
        for (const auto &[y, g] : distances(x, true))
            if (g == 2)
                result.push_back(y);
        return result;
    }

    Apex apex(const string &a, const string &b) {
        const std::map<string, int> &up_a = distances(a, true);
        const std::map<string, int> &up_b = distances(b, true);
        if (up_b.count(a))
            return {a, 0, up_b.at(a), 0};
        if (up_a.count(b))
            return {b, up_a.at(b), 0, 0};
        Apex best;
        for (const auto &[c, da] : up_a) {
            auto it = up_b.find(c);
            if (it == up_b.end())
                continue;
            int db = it->second;
            if (!best || std::make_tuple(da + db, da, c) <
                             std::make_tuple(best.da + best.db, best.da, best.person))
                best = {c, da, db, 0};
        }
        if (best)
            for (const auto &[c, da] : up_a) {
                auto it = up_b.find(c);
                if (it != up_b.end() && da == best.da && it->second == best.db)
                    ++best.shares;
            }
        return best;
    }

    vector<string> relationship(const string &a, const string &b, char sex) {
        if (a == b)
            return {"self"};
        vector<string> result;
        Apex top = apex(a, b);
        if (top)
            result.push_back(top.blood_term(sex));
        const Marriage *m = last(a, b);
        if (!m) {
            for (const auto &[id, p] : persons)
                if (has(p.parents, a) && has(p.parents, b)) {
                    result.push_back("co-parent");
                    break;
                }
        } else {
            string kind = "ex";
            if (m->status == "current")
                kind = "spouse";
            else if (m->status == "widowed")
                kind = m->died == a ? "late" : "survivor";
            result.push_back(gendered(kind, sex));
        }
        const vector<string> &pa = persons.at(a).parents;
        const vector<string> &pb = persons.at(b).parents;
        std::set<string> qa = partners(a), qb = partners(b);
        if (!has(pb, a))
            for (const string &p : pb)
                if (qa.count(p)) {
                    result.push_back(gendered("stepparent", sex));
                    break;
                }
        if (!has(pa, b))
            for (const string &p : pa)
                if (qb.count(p)) {
                    result.push_back(gendered("stepchild", sex));
                    break;
                }
        if (common_parents(a, b) == 0 && step_related(a, b))
            result.push_back(gendered("stepsibling", sex));
        if (!ancestor(a, b))
            for (const string &g : grandparents(b))
                if (qa.count(g)) {
                    result.push_back(gendered("stepgrandparent", sex));
                    break;
                }
        if (!ancestor(b, a))
            for (const string &g : grandparents(a))
                if (qb.count(g)) {
                    result.push_back(gendered("stepgrandchild", sex));
                    break;
                }
        for (const string &q : qb)
            if (has(persons.at(q).parents, a)) {
                result.push_back(gendered("parent-in-law", sex));
                break;
            }
        for (const string &q : qa)
            if (has(persons.at(q).parents, b)) {
                result.push_back(gendered("child-in-law", sex));
                break;
            }
        bool in_law = false;
        for (const string &q : qb)
            if (are_siblings(a, q))
                in_law = true;
        for (const string &q : qa)
            if (are_siblings(q, b))
                in_law = true;
        if (in_law)
            result.push_back(gendered("sibling-in-law", sex));
        return result;
    }

    string relationship_text(const string &a, const string &b) {
        vector<string> result = relationship(a, b, persons.at(a).sex);
        return result.empty() ? "no relation" : join(result, ", ");
    }

    std::int64_t coefficient(const string &a, const string &b) {
        std::pair<string, string> key{std::min(a, b), std::max(a, b)};
        auto cached = coefficient_cache.find(key);
        if (cached != coefficient_cache.end())
            return cached->second;
        std::int64_t value = 0;
        if (a == b)
            value = (scale + inbreeding(a)) / 2;
        else {
            string x = a, y = b;
            if (persons.at(b).birth > persons.at(a).birth)
                std::swap(x, y);
            for (const string &p : persons.at(x).parents)
                value += coefficient(p, y);
            value /= 2;
        }
        coefficient_cache[key] = value;
        return value;
    }

    std::int64_t inbreeding(const string &x) {
        const vector<string> &parents = persons.at(x).parents;
        return parents.size() == 2 ? coefficient(parents[0], parents[1]) : 0;
    }

    int lineage_length(const string &x, std::map<string, int> &memo) {
        auto it = memo.find(x);
        if (it != memo.end())
            return it->second;
        int length = 1;
        for (const string &p : persons.at(x).parents)
            length = std::max(length, 1 + lineage_length(p, memo));
        memo[x] = length;
        return length;
    }

    vector<std::pair<int, string>> lineage(const string &x, bool upward) {
        vector<std::pair<int, string>> result;
        for (const auto &[y, g] : distances(x, upward))
            if (y != x)
                result.emplace_back(g, y);
        std::sort(result.begin(), result.end());
        return result;
    }

    string modify(const string &command, const vector<string> &args);
    vector<string> query(const string &command, const vector<string> &args);
};

string Family::modify(const string &command, const vector<string> &args) {
    const string &x = args[0];
    if (command == "PERSON") {
        if (persons.count(x))
            throw std::runtime_error("DUPLICATE PERSON " + x);
        persons.emplace(x, Person{args[1][0], std::stoi(args[2]), args[3]});
        return "ADDED " + x + " " + args[3] + " " + args[1] + " " + args[2];
    }
    Person &p = person(x);
    if (command == "PARENT" || command == "UNPARENT" || command == "SPOUSE" || command == "DIVORCE")
        person(args[1]);
    if (command == "DEATH") {
        int year = std::stoi(args[1]);
        if (p.death)
            throw std::runtime_error("ALREADY DECEASED " + x);
        bool bad = year < p.birth;
        for (const Marriage &m : marriages)
            if (m.contains(x) && (year < m.start || (m.end && year < m.end)))
                bad = true;
        if (bad)
            throw std::runtime_error("BAD YEAR " + x);
        for (const string &child : children(x))
            if (persons.at(child).birth > year + 1)
                throw std::runtime_error("AFTER DEATH " + child + " " + x);
        p.death = year;
        Marriage *m = current(x);
        string output = "DIED " + x + " " + std::to_string(year);
        if (m) {
            m->end = year;
            m->status = "widowed";
            m->died = x;
            output += " spouse=" + m->other(x);
        }
        return output;
    }
    if (command == "REMOVE") {
        for (auto &[id, person] : persons) {
            vector<string> &parents = person.parents;
            parents.erase(std::remove(parents.begin(), parents.end(), x), parents.end());
        }
        marriages.erase(std::remove_if(marriages.begin(), marriages.end(),
                                       [&x](const Marriage &m) { return m.contains(x); }),
                        marriages.end());
        persons.erase(x);
        return "REMOVED " + x;
    }
    const string &y = args[1];
    if (command == "PARENT") {
        Person &parent = persons.at(y);
        if (x == y)
            throw std::runtime_error("SAME PERSON " + x);
        if (has(p.parents, y))
            throw std::runtime_error("ALREADY PARENT " + x + " " + y);
        if (p.parents.size() == 2)
            throw std::runtime_error("TOO MANY PARENTS " + x);
        if (ancestor(x, y))
            throw std::runtime_error("CYCLE " + x + " " + y);
        if (parent.birth + 12 > p.birth)
            throw std::runtime_error("AGE GAP " + x + " " + y);
        if (parent.death && parent.death + 1 < p.birth)
            throw std::runtime_error("AFTER DEATH " + x + " " + y);
        p.parents.push_back(y);
        return "LINKED " + x + " " + y + " " + gendered("parent", parent.sex);
    }
    if (command == "UNPARENT") {
        if (!has(p.parents, y))
            throw std::runtime_error("NOT PARENT " + x + " " + y);
        p.parents.erase(std::find(p.parents.begin(), p.parents.end(), y));
        return "UNLINKED " + x + " " + y;
    }
    int year = std::stoi(args[2]);
    if (command == "SPOUSE") {
        if (x == y)
            throw std::runtime_error("SAME PERSON " + x);
        for (const string &a : {x, y})
            if (persons.at(a).death)
                throw std::runtime_error("DECEASED " + a);
        for (const string &a : {x, y})
            if (!spouse(a).empty())
                throw std::runtime_error("ALREADY MARRIED " + a);
        if (ancestor(x, y) || ancestor(y, x) || are_siblings(x, y))
            throw std::runtime_error("CLOSE KIN " + x + " " + y);
        for (const string &a : {x, y})
            if (year < persons.at(a).birth + 16)
                throw std::runtime_error("TOO YOUNG " + a);
        for (const string &a : {x, y})
            for (const Marriage &m : marriages)
                if (m.contains(a) && m.end && m.end >= year)
                    throw std::runtime_error("BAD YEAR " + a);
        marriages.push_back(Marriage{x, y, year});
        return "MARRIED " + x + " " + y + " " + std::to_string(year);
    }
    if (spouse(x) != y)
        throw std::runtime_error("NOT MARRIED " + x + " " + y);
    Marriage *m = current(x);
    if (year <= m->start)
        throw std::runtime_error("BAD YEAR " + x);
    m->end = year;
    m->status = "divorced";
    return "DIVORCED " + x + " " + y + " " + std::to_string(year);
}

vector<string> Family::query(const string &command, const vector<string> &args) {
    if (command == "TERM")
        return {"TERM " + join(args, " ") + " " +
                term(std::stoi(args[0]), std::stoi(args[1]), args[2][0])};
    if (command == "STATS") {
        int living = 0, links = 0, couples = 0, founders = 0, longest = 0;
        std::map<string, int> memo;
        for (const auto &[x, p] : persons) {
            if (!p.death)
                ++living;
            links += static_cast<int>(p.parents.size());
            if (p.parents.empty())
                ++founders;
            longest = std::max(longest, lineage_length(x, memo));
        }
        for (const Marriage &m : marriages)
            if (m.status == "current")
                ++couples;
        return {"STATS persons=" + std::to_string(persons.size()) +
                " living=" + std::to_string(living) + " links=" + std::to_string(links) +
                " couples=" + std::to_string(couples) + " founders=" + std::to_string(founders) +
                " generations=" + std::to_string(longest)};
    }
    if (command == "AUDIT") {
        vector<string> lines;
        for (const Marriage &m : marriages) {
            Apex top = apex(m.first, m.second);
            if (top)
                lines.push_back("  marriage " + m.first + " " + m.second + " " +
                                top.blood_term(persons.at(m.first).sex));
        }
        for (const auto &[x, p] : persons) {
            std::int64_t value = inbreeding(x);
            if (value)
                lines.push_back("  inbred " + x + " " + fraction(value));
        }
        lines.insert(lines.begin(), "AUDIT " + std::to_string(lines.size()));
        return lines;
    }
    if (command == "CENSUS") {
        int year = std::stoi(args[0]);
        vector<string> residents;
        for (const auto &[x, p] : persons)
            if (p.birth <= year && (!p.death || p.death > year))
                residents.push_back(x);
        vector<string> lines{"CENSUS " + args[0] + " " + std::to_string(residents.size())};
        for (const string &x : age_order(residents)) {
            const Marriage *last = nullptr;
            for (const Marriage &m : marriages)
                if (m.contains(x) && m.start <= year)
                    last = &m;
            string status = "single";
            if (last)
                status =
                    !last->end || last->end > year ? "married " + last->other(x) : last->status;
            lines.push_back("  " + x + " " + std::to_string(year - persons.at(x).birth) + " " +
                            status);
        }
        return lines;
    }
    const string &x = args[0];
    Person &p = person(x);
    if (command == "RELATION" || command == "KINSHIP" || command == "PATH" || command == "COMMON")
        person(args[1]);
    if (command == "INFO") {
        vector<string> lines{"INFO " + x + " " + p.name + " " + p.sex + " " + p.life(),
                             "  parents: " + person_list(p.parents)};
        for (const Marriage &m : marriages)
            if (m.contains(x))
                lines.push_back("  marriage: " + m.other(x) + " " + std::to_string(m.start) + "-" +
                                (m.end ? std::to_string(m.end) : "") + " " + m.status);
        lines.push_back("  children: " + person_list(children(x)));
        lines.push_back("  siblings: " + person_list(siblings(x)));
        lines.push_back("  inbreeding: " + fraction(inbreeding(x)));
        return lines;
    }
    if (command == "RELATION")
        return {"RELATION " + x + " " + args[1] + ": " + relationship_text(x, args[1])};
    if (command == "KINSHIP")
        return {"KINSHIP " + x + " " + args[1] + " " + fraction(coefficient(x, args[1]))};
    if (command == "RELATIVES" || command == "WHO") {
        vector<string> lines;
        string query = join(vector<string>(args.begin() + 1, args.end()), " ");
        for (const auto &[y, py] : persons) {
            if (y == x)
                continue;
            vector<string> actual = relationship(y, x, py.sex);
            if (command == "RELATIVES") {
                if (!actual.empty())
                    lines.push_back("  " + y + ": " + join(actual, ", "));
            } else {
                vector<string> neutral = relationship(y, x, 'X');
                for (std::size_t i = 0; i < actual.size(); ++i)
                    if (actual[i] == query || neutral[i] == query) {
                        lines.push_back("  " + y + ": " + actual[i]);
                        break;
                    }
            }
        }
        string header = command + " " + x + (command == "WHO" ? " " + query : "") + " " +
                        std::to_string(lines.size());
        lines.insert(lines.begin(), header);
        return lines;
    }
    if (command == "PATH") {
        const string &y = args[1];
        Apex top = apex(x, y);
        if (!top)
            return {"PATH " + x + " " + y + " none"};
        const std::map<string, int> &depths = distances(top.person, false);
        auto upward = [&](string current) {
            vector<string> path{current};
            while (current != top.person) {
                vector<string> choices;
                for (const string &parent : persons.at(current).parents)
                    if (depths.count(parent) && depths.at(parent) == depths.at(current) - 1)
                        choices.push_back(parent);
                current = *std::min_element(choices.begin(), choices.end());
                path.push_back(current);
            }
            return path;
        };
        vector<string> route = upward(x), descent = upward(y);
        for (int i = static_cast<int>(descent.size()) - 2; i >= 0; --i)
            route.push_back(descent[i]);
        return {"PATH " + x + " " + y + " " + std::to_string(top.da + top.db) + ": " +
                join(route, " ")};
    }
    if (command == "COMMON") {
        const string &y = args[1];
        const std::map<string, int> &a = distances(x, true);
        const std::map<string, int> &b = distances(y, true);
        std::set<string> shared;
        for (const auto &[c, g] : a)
            if (b.count(c))
                shared.insert(c);
        vector<string> nearest;
        for (const string &c : shared) {
            vector<string> offspring = children(c);
            if (std::none_of(offspring.begin(), offspring.end(),
                             [&](const string &child) { return shared.count(child); }))
                nearest.push_back(c);
        }
        std::sort(nearest.begin(), nearest.end(), [&](const string &c, const string &d) {
            return std::make_pair(a.at(c) + b.at(c), c) < std::make_pair(a.at(d) + b.at(d), d);
        });
        vector<string> lines{"COMMON " + x + " " + y + " " + std::to_string(nearest.size())};
        for (const string &c : nearest)
            lines.push_back("  " + c + " " + std::to_string(a.at(c)) + " " +
                            std::to_string(b.at(c)));
        return lines;
    }
    if (command == "ANCESTORS" || command == "DESCENDANTS") {
        bool upward = command == "ANCESTORS";
        vector<std::pair<int, string>> entries = lineage(x, upward);
        vector<string> lines{command + " " + x + " " + std::to_string(entries.size())};
        for (const auto &[g, y] : entries)
            lines.push_back("  " + std::to_string(g) + " " + y + " " +
                            term(upward ? 0 : g, upward ? g : 0, persons.at(y).sex));
        return lines;
    }
    if (command == "COUSINS") {
        vector<std::tuple<int, string, string>> matches;
        for (const auto &[y, py] : persons) {
            if (x == y)
                continue;
            Apex top = apex(y, x);
            if (top && top.da >= 2 && top.db >= 2 &&
                std::min(top.da, top.db) - 1 == std::stoi(args[1]))
                matches.emplace_back(std::abs(top.da - top.db), y, top.blood_term(py.sex));
        }
        std::sort(matches.begin(), matches.end());
        vector<string> lines{"COUSINS " + x + " " + args[1] + " " + std::to_string(matches.size())};
        for (const auto &[removed, y, blood] : matches)
            lines.push_back("  " + y + " " + blood);
        return lines;
    }
    if (command == "SIBLINGS") {
        vector<string> lines;
        int earlier = 0;
        for (const string &y : age_order(ids())) {
            if (x == y)
                continue;
            int common = common_parents(x, y);
            string kind = common == 2          ? "full"
                          : common == 1        ? "half"
                          : step_related(x, y) ? "step"
                                               : "";
            if (kind.empty())
                continue;
            if (common > 0 && age_less(y, x))
                ++earlier;
            lines.push_back("  " + y + " " + kind + " " + std::to_string(persons.at(y).birth));
        }
        lines.insert(lines.begin(), "SIBLINGS " + x + " " + std::to_string(lines.size()) +
                                        " order=" + std::to_string(earlier + 1));
        return lines;
    }
    if (command == "GENERATIONS") {
        std::map<int, vector<string>> groups;
        for (const auto &[g, y] : lineage(x, false))
            groups[g].push_back(y);
        vector<string> lines{"GENERATIONS " + x + " " + std::to_string(groups.size())};
        for (const auto &[g, members] : groups) {
            int low = 2025, high = 1800, living = 0;
            for (const string &y : members) {
                const Person &py = persons.at(y);
                low = std::min(low, py.birth);
                high = std::max(high, py.birth);
                if (!py.death)
                    ++living;
            }
            lines.push_back("  " + std::to_string(g) + " " + std::to_string(members.size()) + " " +
                            std::to_string(living) + " " + std::to_string(low) + "-" +
                            std::to_string(high));
        }
        return lines;
    }
    if (command == "TREE") {
        vector<string> lines{"TREE " + x + " " + std::to_string(lineage(x, false).size())};
        std::set<string> visited;
        std::function<void(const string &, int)> visit = [&](const string &y, int depth) {
            string indent(2 * (depth + 1), ' ');
            if (!visited.insert(y).second) {
                lines.push_back(indent + y + " (see above)");
                return;
            }
            const Person &py = persons.at(y);
            string line = indent + y + " " + py.name + " " + py.life();
            string partner = spouse(y);
            if (!partner.empty())
                line += " = " + partner;
            lines.push_back(line);
            for (const string &child : age_order(children(y)))
                visit(child, depth + 1);
        };
        visit(x, 0);
        return lines;
    }
    if (command == "PEDIGREE") {
        int depth = std::stoi(args[1]);
        vector<string> lines;
        std::set<string> entered;
        std::function<void(const string &, int, int)> enter = [&](const string &y, int number,
                                                                  int generation) {
            const Person &py = persons.at(y);
            lines.push_back(string(2 * (generation + 1), ' ') + std::to_string(number) + " " + y +
                            " " + py.name + " " + py.life());
            entered.insert(y);
            if (generation >= depth)
                return;
            vector<string> parents = py.parents;
            std::sort(parents.begin(), parents.end(), [&](const string &a, const string &b) {
                return std::make_pair(sex_index(persons.at(a).sex), a) <
                       std::make_pair(sex_index(persons.at(b).sex), b);
            });
            for (std::size_t i = 0; i < parents.size(); ++i)
                enter(parents[i], 2 * number + static_cast<int>(i), generation + 1);
        };
        enter(x, 1, 0);
        lines.insert(lines.begin(), "PEDIGREE " + x + " " + args[1] +
                                        " entries=" + std::to_string(lines.size()) +
                                        " distinct=" + std::to_string(entered.size()));
        return lines;
    }
    if (command == "TIMELINE") {
        using Event = std::tuple<int, int, string, string>;
        vector<Event> events{{p.birth, 0, "", "born"}};
        for (const Marriage &m : marriages)
            if (m.contains(x)) {
                string y = m.other(x);
                events.emplace_back(m.start, 1, y, "married " + y);
                if (m.status == "divorced")
                    events.emplace_back(m.end, 3, y, "divorced " + y);
                else if (m.status == "widowed" && m.died == y)
                    events.emplace_back(m.end, 4, y, "widowed " + y);
            }
        vector<string> offspring = children(x);
        for (const string &y : offspring)
            events.emplace_back(persons.at(y).birth, 2, y, "child " + y);
        for (const auto &[label, relatives] : vector<std::pair<string, vector<string>>>{
                 {"parent", p.parents}, {"child", offspring}}) {
            for (const string &y : relatives) {
                int death = persons.at(y).death;
                if (death && death >= p.birth && (!p.death || death <= p.death))
                    events.emplace_back(death, 5, y, "lost " + label + " " + y);
            }
        }
        if (p.death)
            events.emplace_back(p.death, 6, "", "died");
        std::sort(events.begin(), events.end());
        vector<string> lines{"TIMELINE " + x + " " + std::to_string(events.size())};
        for (const auto &[year, rank, counterpart, text] : events)
            lines.push_back("  " + std::to_string(year) + " " + text);
        return lines;
    }
    if (command == "FIND") {
        static const std::map<string, std::pair<string, char>> steps = {
            {"parent", {"parent", 0}},    {"father", {"parent", 'M'}},
            {"mother", {"parent", 'F'}},  {"child", {"child", 0}},
            {"son", {"child", 'M'}},      {"daughter", {"child", 'F'}},
            {"sibling", {"sibling", 0}},  {"brother", {"sibling", 'M'}},
            {"sister", {"sibling", 'F'}}, {"spouse", {"spouse", 0}},
            {"husband", {"spouse", 'M'}}, {"wife", {"spouse", 'F'}}};
        std::set<string> current{x};
        std::istringstream route(args[1]);
        string step;
        while (std::getline(route, step, '.')) {
            const auto &[kind, sex] = steps.at(step);
            std::set<string> next;
            for (const string &y : current) {
                vector<string> targets;
                if (kind == "parent")
                    targets = persons.at(y).parents;
                else if (kind == "child")
                    targets = children(y);
                else if (kind == "sibling")
                    targets = siblings(y);
                else {
                    string partner = spouse(y);
                    if (!partner.empty())
                        targets.push_back(partner);
                }
                for (const string &z : targets)
                    if (!sex || persons.at(z).sex == sex)
                        next.insert(z);
            }
            current = std::move(next);
        }
        current.erase(x);
        vector<string> lines{"FIND " + x + " " + args[1] + " " + std::to_string(current.size())};
        for (const string &y : current)
            lines.push_back("  " + y + ": " + relationship_text(y, x));
        return lines;
    }
    throw std::logic_error("unknown command");
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    string line;
    std::getline(std::cin, line);
    Family family;
    vector<std::pair<string, Family>> history;
    const std::set<string> modifying{"PERSON",   "DEATH",  "REMOVE", "PARENT",
                                     "UNPARENT", "SPOUSE", "DIVORCE"};
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        std::istringstream input(line);
        string command, word;
        input >> command;
        vector<string> args;
        while (input >> word)
            args.push_back(word);
        try {
            if (command == "UNDO") {
                if (history.empty())
                    throw std::runtime_error("NOTHING TO UNDO");
                string undone = history.back().first;
                family = std::move(history.back().second);
                history.pop_back();
                std::cout << "UNDONE " << undone << '\n';
            } else if (modifying.count(command)) {
                Family saved = family.snapshot();
                string output = family.modify(command, args);
                history.emplace_back(line, std::move(saved));
                family.invalidate();
                std::cout << output << '\n';
            } else {
                for (const string &output : family.query(command, args))
                    std::cout << output << '\n';
            }
        } catch (const std::runtime_error &error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
