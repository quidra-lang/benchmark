#include "tac.hpp"
namespace tac {
    CFG::CFG(const Function& function) {
        blocks.resize(1);
        instructions.resize(1);
        positions.resize(1);
        block_of.resize(1);
        std::vector<std::string> pending;
        int first_label = 0, current = 0;
        std::string previous;
        for (int index = 0;index < static_cast<int>(function.code.size());++index) {
            const Line& line = function.code[index];
            if (line.is_label()) {
                if (pending.empty()) first_label = index;
                pending.push_back(line.label);
                continue;
            }
            if (current == 0 || !pending.empty() || previous == "goto" || previous == "if" || previous == "return") {
                int start = pending.empty() ? index : first_label;
                if (current) blocks[current].end = start;
                Block block;
                block.start = start;
                block.labels = pending;
                blocks.push_back(block);
                pending.clear();
                current = static_cast<int>(blocks.size()) - 1;
            }
            int n = static_cast<int>(instructions.size());
            instructions.push_back(line.instruction);
            positions.push_back(index);
            block_of.push_back(current);
            blocks[current].instructions.push_back(n);
            previous = line.instruction.kind;
        }
        blocks[current].end = static_cast<int>(function.code.size());
        std::map<std::string, int> labels;
        for (int b = 1;b < static_cast<int>(blocks.size());++b) for (const std::string& label : blocks[b].labels) labels[label] = b;
        for (int b = 1;b < static_cast<int>(blocks.size());++b) {
            const Instruction& last = instructions[blocks[b].instructions.back()];
            if (last.kind == "goto") blocks[b].successors = {labels.at(last.name)};
            else if (last.kind == "if") {
                blocks[b].successors = {b + 1};
                int target = labels.at(last.name);
                if (target != b + 1) blocks[b].successors.push_back(target);
            } else if (last.kind != "return") blocks[b].successors = {b + 1};
            for (int s : blocks[b].successors) blocks[s].predecessors.push_back(b);
        }
        std::function<void(int)> visit =[&](int b) {
            reachable.insert(b);
            for (int s : blocks[b].successors) if (!reachable.count(s)) visit(s);
            postorder.push_back(b);
        };
        visit(1);
        reverse_postorder.assign(postorder.rbegin(), postorder.rend());
        for (int b : reachable) for (int p : blocks[b].predecessors) if (reachable.count(p)) blocks[b].reachable_predecessors.push_back(p);
        dominators.resize(blocks.size());
        immediate.assign(blocks.size(), 0);
        for (int b : reachable) dominators[b] = reachable;
        dominators[1] = {1};
        bool changed = true;
        while (changed) {
            changed = false;
            for (std::size_t i = 1;i < reverse_postorder.size();++i) {
                int b = reverse_postorder[i];
                const std::vector<int>& preds = blocks[b].reachable_predecessors;
                std::set<int> value = dominators[preds[0]];
                for (std::size_t j = 1;j < preds.size();++j) value = intersection(value, dominators[preds[j]]);
                value.insert(b);
                if (value != dominators[b]) {
                    dominators[b] = value;
                    changed = true;
                }
            }
        }
        for (int b : reachable) if (b != 1) {
            int best = 0;
            for (int d : dominators[b]) if (d != b &&(best == 0 || dominators[d].size() > dominators[best].size())) best = d;
            immediate[b] = best;
        }
        for (int header : reachable) {
            Loop loop;
            loop.header = header;
            for (int p : blocks[header].reachable_predecessors) if (dominators[p].count(header)) loop.latches.push_back(p);
            if (loop.latches.empty()) continue;
            loop.blocks.insert(header);
            std::vector<int> work;
            for (int latch : loop.latches) {
                loop.blocks.insert(latch);
                if (latch != header) work.push_back(latch);
            } while (!work.empty()) {
                int b = work.back();
                work.pop_back();
                for (int p : blocks[b].reachable_predecessors) if (loop.blocks.insert(p).second) work.push_back(p);
            }
            loops.push_back(loop);
        }
        for (Loop& loop : loops) {
            for (const Loop& other : loops) if (other.blocks.count(loop.header))++loop.depth;
            for (int b : loop.blocks) {
                ++blocks[b].depth;
                bool exit = instructions[blocks[b].instructions.back()].kind == "return";
                for (int s : blocks[b].successors) if (!loop.blocks.count(s)) {
                    loop.outside.insert(s);
                    exit = true;
                }
                if (exit) loop.exits.insert(b);
            }
        }
    }
}
