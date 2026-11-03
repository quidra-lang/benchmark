#include "policy.hpp"
Roles bit(int role) { return Roles(1) << role; }
int cardinality(Roles roles) {
    int count = 0;
    while (roles) {
        roles &= roles - 1;
        ++count;
    }
    return count;
}
int RBAC::find(const std::string &name) const {
    for (int i = 0; i < int(roles.size()); ++i)
        if (roles[i] == name)
            return i;
    return -1;
}
Roles RBAC::closure(Roles source) const {
    Roles previous;
    do {
        previous = source;
        for (int i = 0; i < int(roles.size()); ++i)
            if (source & bit(i))
                source |= inherits[i];
    } while (source != previous);
    return source;
}
Roles RBAC::assigned(const std::string &user, int day) const {
    Roles result = 0;
    for (const Assignment &a : assignments)
        if (a.user == user && a.first <= day && day <= a.last)
            result |= bit(a.role);
    return result;
}
Roles RBAC::authorized(const std::string &user, int day) const {
    return closure(assigned(user, day));
}
std::vector<int> RBAC::ordered(Roles source) const {
    std::vector<int> result;
    for (int i = 0; i < int(roles.size()); ++i)
        if (source & bit(i))
            result.push_back(i);
    std::sort(result.begin(), result.end(), [&](int a, int b) { return roles[a] < roles[b]; });
    return result;
}
Names RBAC::names(Roles source) const {
    Names result;
    for (int role : ordered(source))
        result.push_back(roles[role]);
    return result;
}
bool RBAC::permits(int role, const std::string &action, const std::string &type) const {
    for (const Grant &g : grants)
        if (g.role == role && g.action == action && g.type == type)
            return true;
    return false;
}
std::string RBAC::path(int from, int to) const {
    if (from == to)
        return roles[to];
    for (int junior : ordered(inherits[from]))
        if (closure(bit(junior)) & bit(to))
            return roles[from] + " > " + path(junior, to);
    return "";
}
std::string RBAC::accept(const Names &f) {
    const std::string &keyword = f[0];
    if (keyword == "ROLE") {
        if (find(f[1]) >= 0)
            return "duplicate role " + f[1];
        roles.push_back(f[1]);
    } else if (keyword == "INHERITS") {
        int senior = find(f[1]), junior = find(f[2]);
        if (senior < 0)
            return "unknown role " + f[1];
        if (junior < 0)
            return "unknown role " + f[2];
        if (inherits[senior] & bit(junior))
            return text("duplicate inheritance ", f[1], " ", f[2]);
        if (closure(bit(junior)) & bit(senior))
            return "cycle " + f[1] + " > " + path(junior, senior);
        inherits[senior] |= bit(junior);
    } else if (keyword == "PERMIT") {
        int role = find(f[1]);
        if (role < 0)
            return "unknown role " + f[1];
        if (permits(role, f[2], f[3]))
            return text("duplicate permission ", f[1], " ", f[2], " ", f[3]);
        grants.push_back({role, f[2], f[3]});
    } else if (keyword == "SSD" || keyword == "DSD") {
        std::vector<Constraint> &constraints = keyword == "SSD" ? ssd : dsd;
        for (const Constraint &c : constraints)
            if (c.name == f[1])
                return "duplicate constraint " + f[1];
        Names names = split(f[3], ",");
        Roles mask = 0;
        for (const std::string &name : names) {
            int role = find(name);
            if (role < 0)
                return "unknown role " + name;
            mask |= bit(role);
        }
        int count = std::stoi(f[2]);
        if (count < 2 || count > int(names.size()))
            return text("bad cardinality ", f[1], " ", count);
        constraints.push_back({f[1], count, mask});
    } else {
        int role = find(f[2]);
        if (role < 0)
            return "unknown role " + f[2];
        int first = std::stoi(f[3]), last = std::stoi(f[4]);
        if (!(1 <= first && first <= last && last <= 365))
            return text("bad range ", first, " ", last);
        for (const Constraint &c : ssd)
            for (int day = first; day <= last; ++day) {
                Roles intersection = c.roles & closure(assigned(f[1], day) | bit(role));
                if (cardinality(intersection) >= c.cardinality)
                    return text("ssd ", c.name, " day ", day, " roles ",
                                join(names(intersection), ","));
            }
        assignments.push_back({f[1], role, first, last});
    }
    return "";
}
void RBAC::read() {
    Lines lines = read_lines("input/rbac.txt");
    for (const std::string &keyword : Names{"ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN"})
        for (int i = 0; i < int(lines.size()); ++i) {
            Names fields = split(lines[i]);
            if (fields[0] != keyword)
                continue;
            std::string error = accept(fields);
            if (!error.empty())
                diagnostics.push_back({i + 1, keyword, error});
        }
    std::sort(diagnostics.begin(), diagnostics.end(),
              [](const Diagnostic &a, const Diagnostic &b) { return a.number < b.number; });
}
