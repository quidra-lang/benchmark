#include "tac.hpp"
namespace tac {
    void rewrite(Function& f, const Replacements& replacements, const std::map<int, std::vector<Line>>& insertions) {
        std::vector<Line> result;
        int n = 0;
        for (int i = 0;i <= static_cast<int>(f.code.size());++i) {
            std::map<int, std::vector<Line>>::const_iterator ins = insertions.find(i);
            if (ins != insertions.end()) result.insert(result.end(), ins->second.begin(), ins->second.end());
            if (i == static_cast<int>(f.code.size())) break;
            const Line& line = f.code[i];
            if (line.is_label()) result.push_back(line);
            else {
                ++n;
                Replacements::const_iterator edit = replacements.find(n);
                if (edit == replacements.end()) result.push_back(line);
                else result.insert(result.end(), edit->second.begin(), edit->second.end());
            }
        }
        f.code = std::move(result);
    }
    std::optional<Instruction> fold(const Instruction& s) {
        if (s.kind != "bin" && s.kind != "if") return s;
        if (s.a.constant && s.b.constant) {
            if ((s.operation == "/" || s.operation == "%") && s.b.number == 0) return s;
            Integer value = calculate(s.operation, s.a.number, s.b.number);
            if (s.kind == "if") {
                if (!value) return std::nullopt;
                Instruction result;
                result.kind = "goto";
                result.name = s.name;
                return result;
            }
            if (value < -2147483648LL || value > 2147483647LL) return s;
            Instruction result;
            result.kind = "copy";
            result.destination = s.destination;
            result.a = Operand::value(value);
            return result;
        }
        if (s.kind != "bin" || s.a.constant == s.b.constant) return s;
        std::optional<Operand> replacement;
        if (s.operation == "+" &&((s.a.constant && s.a.number == 0) ||(s.b.constant && s.b.number == 0))) replacement = s.a.constant ? s.b : s.a;
        else if (s.operation == "-" && s.b.constant && s.b.number == 0) replacement = s.a;
        else if (s.operation == "*" &&((s.a.constant && s.a.number == 1) ||(s.b.constant && s.b.number == 1))) replacement = s.a.constant ? s.b : s.a;
        else if (s.operation == "/" && s.b.constant && s.b.number == 1) replacement = s.a;
        else if (s.operation == "*" &&((s.a.constant && s.a.number == 0) ||(s.b.constant && s.b.number == 0))) replacement = Operand::value(0);
        if (!replacement) return s;
        Instruction result;
        result.kind = "copy";
        result.destination = s.destination;
        result.a = *replacement;
        return result;
    }
    std::string hoist(Function& f, const CFG& g, const Loop& loop, const std::vector<int>& moves) {
        const Block& header = g.blocks[loop.header];
        std::vector<int> outside;
        for (int p : header.predecessors) if (!loop.blocks.count(p)) outside.push_back(p);
        Replacements replacements;
        std::vector<Line> insertion;
        for (int n : moves) {
            replacements[n] = {};
            insertion.push_back(Line::code(g.instructions[n]));
        }
        int position;
        std::string destination;
        if (loop.header != 1 && outside.size() == 1 && g.blocks[outside[0]].successors == std::vector<int> {loop.header}) {
            const Block& preheader = g.blocks[outside[0]];
            int last = preheader.instructions.back();
            position = g.positions[last];
            if (g.instructions[last].kind != "goto" && g.instructions[last].kind != "if")++position;
            destination = "B" + std::to_string(outside[0]);
        } else {
            std::string label = "_p" + std::to_string(++f.preheader_serial);
            position = header.start;
            insertion.insert(insertion.begin(), Line::named(label));
            destination = "new " + label;
            for (int p : outside) {
                int n = g.blocks[p].instructions.back();
                Instruction s = g.instructions[n];
                if ((s.kind == "goto" || s.kind == "if") && std::find(header.labels.begin(), header.labels.end(), s.name) != header.labels.end()) {
                    s.name = label;
                    replacements[n] = {Line::code(s)};
                }
            }
        }
        rewrite(f, replacements, { {position, insertion} });
        return destination;
    }
    std::vector<std::string> remove_unreachable(Function& f, const CFG& g) {
        std::set<int> removed;
        std::vector<std::string> records;
        for (int b = 1;b < static_cast<int>(g.blocks.size());++b) if (!g.reachable.count(b)) {
            records.push_back("remove block B" + std::to_string(b));
            for (int i = g.blocks[b].start;i < g.blocks[b].end;++i) removed.insert(i);
        }
        std::vector<std::pair<Line, int>> remaining;
        int n = 0;
        for (int i = 0;i < static_cast<int>(f.code.size());++i) {
            if (!f.code[i].is_label())++n;
            if (!removed.count(i)) remaining.emplace_back(f.code[i], f.code[i].is_label() ? 0 : n);
        }
        std::set<int> jumps;
        for (std::size_t i = 0;i < remaining.size();++i) {
            const Line& line = remaining[i].first;
            if (line.is_label() ||(line.instruction.kind != "goto" && line.instruction.kind != "if")) continue;
            for (std::size_t j = i + 1;j < remaining.size() && remaining[j].first.is_label();++j) if (line.instruction.name == remaining[j].first.label) jumps.insert(remaining[i].second);
        }
        for (int number : jumps) records.push_back("remove jump #" + std::to_string(number));
        std::set<std::string> targets;
        for (const std::pair<Line, int>& entry : remaining) if (!entry.first.is_label() && !jumps.count(entry.second) &&(entry.first.instruction.kind == "goto" || entry.first.instruction.kind == "if")) targets.insert(entry.first.instruction.name);
        f.code.clear();
        for (const std::pair<Line, int>& entry : remaining) {
            const Line& line = entry.first;
            if (line.is_label() && !targets.count(line.label)) records.push_back("remove label " + line.label);
            else if (!jumps.count(entry.second)) f.code.push_back(line);
        }
        return records;
    }
}
