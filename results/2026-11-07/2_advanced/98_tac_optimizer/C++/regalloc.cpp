#include "tac.hpp"
namespace tac {
    Cost Cost::power(int exponent) {
        Cost value;
        value.digits = "1" + std::string(exponent, '0');
        return value;
    }
    Cost& Cost::operator +=(const Cost& other) {
        std::string a = digits, b = other.digits, result;
        std::reverse(a.begin(), a.end());
        std::reverse(b.begin(), b.end());
        int carry = 0;
        for (std::size_t i = 0;i < std::max(a.size(), b.size()) || carry;++i) {
            int sum = carry +(i < a.size() ? a[i] - '0' : 0) +(i < b.size() ? b[i] - '0' : 0);
            result.push_back(static_cast<char>('0' + sum%10));
            carry = sum/10;
        }
        if (result.empty()) result = "0";
        std::reverse(result.begin(), result.end());
        digits = result;
        return *this;
    }
    Cost Cost::times(int factor) const {Cost result;
    std::string reversed;
    int carry = 0;
    for (std::string::const_reverse_iterator it = digits.rbegin();it != digits.rend();++it) {
        int v =(*it - '0') * factor + carry;
        reversed.push_back(static_cast<char>('0' + v%10));
        carry = v/10;
    } while (carry) {
        reversed.push_back(static_cast<char>('0' + carry%10));
        carry /= 10;
    } while (reversed.size() > 1 && reversed.back() == '0') reversed.pop_back();
    std::reverse(reversed.begin(), reversed.end());
    result.digits = reversed;
    return result;
    } bool Cost::operator <(const Cost& other) const {return digits.size() != other.digits.size() ? digits.size() < other.digits.size() : digits < other.digits;
    } Allocation::Allocation(const Function& f, const CFG& g, const DataFlow& flow, int registers) {
        Variables nodes(f.parameters.begin(), f.parameters.end());
        for (std::size_t n = 1;n < g.instructions.size();++n) if (g.reachable.count(g.block_of[n])) {
            const Instruction& s = g.instructions[n];
            for (const std::string& v : s.uses()) nodes.insert(v);
            if (!s.destination.empty()) nodes.insert(s.destination);
        }
        for (const std::string& v : nodes) {
            neighbors[v];
            partners[v];
            costs[v];
        }
        std::function<void(const std::string&, const std::string&)> edge =[&](const std::string& a, const std::string& b) {
            if (a != b) {
                neighbors[a].insert(b);
                neighbors[b].insert(a);
            }
        };
        for (int b : g.reachable) {
            Variables state = flow.live_out[b];
            const std::vector<int>& ns = g.blocks[b].instructions;
            for (std::vector<int>::const_reverse_iterator it = ns.rbegin();it != ns.rend();++it) {
                const Instruction& s = g.instructions[*it];
                if (!s.destination.empty()) for (const std::string& v : state) if (v != s.destination && !(s.kind == "copy" && !s.a.constant && v == s.a.variable)) edge(s.destination, v);
                state = live_transfer(s, state);
            }
            Cost weight = Cost::power(g.blocks[b].depth);
            for (int n : ns) {
                const Instruction& s = g.instructions[n];
                for (const std::string& v : s.uses()) costs[v] += weight;
                if (!s.destination.empty()) costs[s.destination] += weight;
            }
        }
        Variables entry = flow.live_in[1];
        entry.insert(f.parameters.begin(), f.parameters.end());
        for (const std::string& p : f.parameters) {
            costs[p] += Cost::power(0);
            for (const std::string& v : entry) edge(p, v);
        }
        for (const Line& line : f.code) if (!line.is_label()) {
            const Instruction& s = line.instruction;
            if (s.kind == "copy" && !s.a.constant && s.destination != s.a.variable) {
                if (nodes.count(s.destination)) partners[s.destination].insert(s.a.variable);
                if (nodes.count(s.a.variable)) partners[s.a.variable].insert(s.destination);
            }
        }
        Variables remaining = nodes;
        while (!remaining.empty()) {
            std::map<std::string, int> degrees;
            std::string chosen;
            int degree = 0;
            bool simple = false;
            for (const std::string& v : remaining) degrees[v] = static_cast<int>(intersection(neighbors[v], remaining).size());
            for (const std::string& v : remaining) if (degrees[v] < registers &&(!simple || degrees[v] < degree)) {
                simple = true;
                chosen = v;
                degree = degrees[v];
            }
            if (!simple) {
                for (const std::string& v : remaining) if (chosen.empty() || costs[v].times(degrees[chosen]) < costs[chosen].times(degrees[v])) chosen = v;
                degree = degrees[chosen];
                potential.emplace_back(chosen, degree);
            }
            order.push_back(chosen);
            remaining.erase(chosen);
        }
        for (std::vector<std::string>::const_reverse_iterator it = order.rbegin();it != order.rend();++it) {
            const std::string& v = *it;
            std::set<int> free;
            for (int r = 0;r < registers;++r) free.insert(r);
            for (const std::string& n : neighbors[v]) if (colors.count(n) && colors[n] >= 0) free.erase(colors[n]);
            if (free.empty()) {
                colors[v] = -1;
                spills.insert(v);
                continue;
            }
            std::set<int> preferred;
            for (const std::string& p : partners[v]) if (colors.count(p) && free.count(colors[p])) preferred.insert(colors[p]);
            colors[v] = preferred.empty() ? *free.begin() : *preferred.begin();
        }
    }
}
