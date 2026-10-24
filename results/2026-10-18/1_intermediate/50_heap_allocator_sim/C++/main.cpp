#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

using namespace std;

constexpr int UNIT = 8;
constexpr int HEADER = 8;
constexpr int MIN_BLOCK = 16;
constexpr int MIN_BUDDY_BLOCK = 32;
constexpr int MAX_HEAP = 65536;
constexpr int UNINITIALIZED = -1;
constexpr int64_t RANDOM_MULTIPLIER = 48271;
constexpr int64_t RANDOM_MODULUS = 2147483647;
const vector<string> MODES = {"FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"};
const vector<string> COUNTERS = {"allocs", "frees", "reallocs", "moves", "failures", "collected"};

struct CommandError : runtime_error { using runtime_error::runtime_error; };

bool power_of_two(int n) { return n > 0 && (n & (n - 1)) == 0; }
int size_class(int n) {
    int power = 0;
    while ((1 << (power + 1)) <= n) ++power;
    return power;
}
int fragmentation_percent(int total, int largest) {
    return total ? (total - largest) * 100 / total : 0;
}
int64_t next_random(int64_t state) {
    return RANDOM_MULTIPLIER * state % RANDOM_MODULUS;
}

struct Block {
    int start, size;
    bool used = false;
    string owner;
    int requested = 0;
    vector<int> contents;
    int stamp = 0;

    Block(int start, int size) : start(start), size(size) {}
    int end() const { return start + size; }
    int payload() const { return start + HEADER; }
    string area() const { return to_string(start) + "+" + to_string(size); }
    string map_units() const {
        string units(1, used ? 'H' : 'F');
        for (int i = 0; i < size / UNIT - 1; ++i) {
            units += !used ? '.' : i * UNIT < requested ? '#' : '-';
        }
        return units;
    }
};

using BlockRef = shared_ptr<Block>;

struct Choice {
    pair<int, int> rank;
    int index, place;
};
struct Moved { BlockRef block; int from; };

struct Heap {
    string mode;
    int size, rover = 0, registrations = 0;
    vector<BlockRef> blocks;

    Heap(string mode, int size) : mode(move(mode)), size(size) {
        blocks.push_back(reg(make_shared<Block>(0, size)));
    }
    BlockRef reg(BlockRef block) {
        block->stamp = ++registrations;
        return block;
    }
    bool buddy() const { return mode == "BUDDY"; }
    int required_length(int request) const {
        int length = ((request + UNIT - 1) / UNIT) * UNIT + HEADER;
        if (!buddy()) return length;
        int power = MIN_BUDDY_BLOCK;
        while (power < length) power *= 2;
        return power;
    }
    int locate(int address) const {
        int index = 0;
        while (blocks.at(index)->end() <= address) ++index;
        return index;
    }
    int index_of(const BlockRef &block) const {
        return static_cast<int>(find(blocks.begin(), blocks.end(), block) - blocks.begin());
    }
    vector<BlockRef> used_blocks() const {
        vector<BlockRef> selected;
        for (const auto &block : blocks) if (block->used) selected.push_back(block);
        return selected;
    }
    vector<BlockRef> free_blocks() const {
        vector<BlockRef> selected;
        for (const auto &block : blocks) if (!block->used) selected.push_back(block);
        return selected;
    }
    int used_total() const {
        int total = 0;
        for (const auto &block : blocks) if (block->used) total += block->size;
        return total;
    }
    int fragmentation() const {
        int total = 0, largest = 0;
        for (const auto &block : blocks) if (!block->used) {
            total += block->size;
            largest = max(largest, block->size);
        }
        return fragmentation_percent(total, largest);
    }
    int placement(const Block &block, int alignment) const {
        int place = ((block.start + HEADER + alignment - 1) / alignment) * alignment - HEADER;
        if (place > block.start && place - block.start < MIN_BLOCK) place += alignment;
        return place;
    }
    pair<int,int> rank(int index, int rover_index) const {
        const Block &block = *blocks[index];
        if (mode == "NEXT") return {(index - rover_index + (int)blocks.size()) % (int)blocks.size(), 0};
        if (mode == "BEST" || mode == "BUDDY") return {block.size, block.start};
        if (mode == "WORST") return {-block.size, block.start};
        if (mode == "SEGFIT") return {size_class(block.size), -block.stamp};
        return {block.start, 0};
    }
    optional<Choice> choose(int length, int alignment) const {
        int rover_index = locate(rover);
        optional<Choice> chosen;
        for (int index = 0; index < (int)blocks.size(); ++index) {
            const Block &block = *blocks[index];
            if (block.used) continue;
            int place = placement(block, alignment);
            if (place + length > block.end()) continue;
            pair<int,int> r = rank(index, rover_index);
            if (!chosen || r < chosen->rank) chosen = Choice{r, index, place};
        }
        return chosen;
    }
    BlockRef carve(int index, int place, int length) {
        BlockRef original = blocks[index];
        vector<BlockRef> parts;
        if (place > original->start)
            parts.push_back(reg(make_shared<Block>(original->start, place-original->start)));
        BlockRef used = make_shared<Block>(place, original->end() - place);
        parts.push_back(used);
        if (used->size - length >= MIN_BLOCK) {
            parts.push_back(reg(make_shared<Block>(place + length, used->size-length)));
            used->size = length;
        }
        blocks.erase(blocks.begin() + index);
        blocks.insert(blocks.begin() + index, parts.begin(), parts.end());
        return used;
    }
    BlockRef halve(int index, int length) {
        BlockRef block = blocks[index];
        while (block->size > length) {
            block->size /= 2;
            blocks.insert(blocks.begin() + index + 1,
                          reg(make_shared<Block>(block->end(), block->size)));
        }
        return block;
    }
    BlockRef allocate(int length, int alignment) {
        optional<Choice> chosen = choose(length, alignment);
        if (!chosen) return nullptr;
        BlockRef block = buddy()
            ? halve(chosen->index, length) : carve(chosen->index, chosen->place, length);
        block->used = true;
        if (mode == "NEXT") rover = block->end() == size ? 0 : block->end();
        return block;
    }
    void merge_next(int index) {
        blocks[index]->size += blocks[index+1]->size;
        blocks.erase(blocks.begin() + index + 1);
    }
    pair<BlockRef,int> coalesce(int index) {
        int merges = 0;
        if (buddy()) {
            while (blocks[index]->size < size) {
                const BlockRef block = blocks[index];
                int partner = block->start % (2 * block->size) == 0 ? index + 1 : index - 1;
                if (partner < 0 || partner >= (int)blocks.size()) break;
                const BlockRef other = blocks[partner];
                if (other->used || other->size != block->size) break;
                index = min(index, partner);
                merge_next(index);
                ++merges;
            }
        } else {
            if (index+1 < (int)blocks.size() && !blocks[index+1]->used) {
                merge_next(index);
                ++merges;
            }
            if (index > 0 && !blocks[index-1]->used) {
                --index;
                merge_next(index);
                ++merges;
            }
        }
        return {reg(blocks[index]),merges};
    }
    pair<BlockRef,int> release(BlockRef block) {
        block->used = false;
        block->owner.clear();
        block->requested = 0;
        block->contents.clear();
        return coalesce(index_of(block));
    }
    string shrink(int index, int length) {
        BlockRef block = blocks[index];
        if (buddy()) {
            if (block->size == length) return "kept";
            halve(index, length);
            return "shrunk";
        }
        if (block->size - length < MIN_BLOCK) return "kept";
        blocks.insert(blocks.begin() + index + 1,
                      make_shared<Block>(block->start + length, block->size - length));
        block->size = length;
        coalesce(index+1);
        return "shrunk";
    }
    string grow_into_next(int index, int length) {
        BlockRef block = blocks[index];
        if (index+1 >= (int)blocks.size() || blocks[index+1]->used) return "";
        int total = block->size + blocks[index+1]->size;
        if (total < length) return "";
        blocks.erase(blocks.begin() + index + 1);
        if (total - length >= MIN_BLOCK) {
            block->size = length;
            blocks.insert(blocks.begin() + index + 1,
                          reg(make_shared<Block>(block->end(),total - length)));
        } else block->size = total;
        return "grown";
    }
    string grow_buddy(int index, int length) {
        BlockRef block = blocks[index];
        int size = block->size, last = index;
        while (size < length) {
            ++last;
            if (block->start % (2*size) != 0 || last >= (int)blocks.size()) return "";
            BlockRef partner = blocks[last];
            if (partner->used || partner->size != size) return "";
            size *= 2;
        }
        blocks.erase(blocks.begin()+index+1,blocks.begin()+last+1);
        block->size = length;
        return "grown";
    }
    string resize(BlockRef block, int length) {
        int index = index_of(block);
        if (length <= block->size) return shrink(index, length);
        return buddy() ? grow_buddy(index, length) : grow_into_next(index, length);
    }
    BlockRef extend(int amount) {
        blocks.push_back(make_shared<Block>(size,amount));
        size += amount;
        return coalesce((int)blocks.size()-1).first;
    }
    int trim() {
        int released = 0;
        if (buddy()) {
            while (!blocks.back()->used && 2*blocks.back()->size == size) {
                released += blocks.back()->size;
                blocks.pop_back();
                size /= 2;
            }
        } else if (blocks.size()>=2 && !blocks.back()->used) {
            BlockRef block = blocks.back();
            blocks.pop_back();
            released = block->size;
            size = block->start;
        }
        if (rover >= size) rover = 0;
        return released;
    }
    pair<vector<Moved>,int> compact() {
        vector<BlockRef> packed = used_blocks();
        vector<Moved> moved;
        int address = 0;
        for (auto &block : packed) {
            if (block->start != address) {
                moved.push_back({block,block->payload()});
                block->start = address;
            }
            address += block->size;
        }
        if (address < size) packed.push_back(reg(make_shared<Block>(address,size-address)));
        blocks = move(packed);
        rover = 0;
        return {moved,address};
    }
};

string experiment(const string &mode, int size, int64_t seed, int operations, int max_request) {
    Heap heap(mode,size);
    int64_t state = seed;
    vector<BlockRef> live;
    int used = 0, peak = 0, success = 0, failures = 0;
    for (int operation = 0; operation < operations; ++operation) {
        state = next_random(state);
        bool allocating = live.empty() || state % 3 != 0;
        state = next_random(state);
        if (allocating) {
            int requested = 1 + (int)(state % max_request);
            BlockRef block = heap.allocate(heap.required_length(requested),UNIT);
            if (!block) ++failures;
            else {++success;live.push_back(block);used+=block->size;}
        } else {
            size_t index = (size_t)(state % live.size());
            BlockRef block = live[index];
            live.erase(live.begin() + index);
            used -= block->size;
            heap.release(block);
        }
        peak = max(peak,used);
    }
    ostringstream out;
    out << "BENCH " << mode << " ok=" << success << " fail=" << failures
        << " peak=" << peak << " used=" << used << " frag=" << heap.fragmentation()
        << " blocks=" << heap.blocks.size();
    return out.str();
}

struct Allocator {
    unique_ptr<Heap> heap;
    unordered_map<string,BlockRef> allocations;
    unordered_set<string> freed, roots;
    unordered_map<string,unordered_set<string>> references;
    unordered_map<string,vector<string>> histories;
    unordered_map<string,int> counters;
    int peak = 0;
    vector<string> output;

    Allocator() { reset(nullptr); }
    void reset(unique_ptr<Heap> next_heap) {
        heap = move(next_heap);
        allocations.clear();
        freed.clear();
        roots.clear();
        references.clear();
        histories.clear();
        counters.clear();
        for (const string &name : COUNTERS) counters[name] = 0;
        peak = 0;
    }
    template <typename... Parts>
    void emit(const Parts &...parts) {
        ostringstream text;
        bool first = true;
        ((text << (exchange(first,false) ? "" : " ") << parts),...);
        output.push_back(text.str());
    }
    void record(const string &name, const string &line) {
        emit(line);
        histories[name].push_back(line);
    }
    CommandError out_of_memory(const string &id) {
        ++counters["failures"];
        return CommandError("OUT OF MEMORY " + id);
    }
    BlockRef live(const string &id) const {
        auto it = allocations.find(id);
        if (it != allocations.end()) return it->second;
        if (freed.count(id)) throw CommandError("USE AFTER FREE " + id);
        throw CommandError("UNKNOWN ID " + id);
    }
    BlockRef range(const string &id, int offset, int length) const {
        BlockRef block = live(id);
        if (offset + length > block->requested) throw CommandError("OUT OF BOUNDS " + id);
        return block;
    }
    void require_free_list() const {
        if (heap->buddy()) throw CommandError("UNSUPPORTED IN BUDDY MODE");
    }
    unordered_set<string> reachable() const {
        unordered_set<string> found = roots;
        vector<string> pending(roots.begin(),roots.end());
        while (!pending.empty()) {
            string name = pending.back();
            pending.pop_back();
            auto it = references.find(name);
            if (it == references.end()) continue;
            for (const string &target : it->second) {
                if (found.insert(target).second) pending.push_back(target);
            }
        }
        return found;
    }
    void allocate_id(const string &kind, const string &id, int requested,
                     int alignment, int initial) {
        if (requested == 0) throw CommandError("BAD SIZE");
        if (allocations.count(id)) throw CommandError("DUPLICATE ID " + id);
        BlockRef block = heap->allocate(heap->required_length(requested),alignment);
        if (!block) throw out_of_memory(id);
        block->owner = id;
        block->requested = requested;
        block->contents.assign(requested,initial);
        allocations[id] = block;
        freed.erase(id);
        ++counters["allocs"];
        record(id,kind + " " + id + " addr=" + to_string(block->payload()) +
               " block=" + to_string(block->size));
    }
    string release_id(const string &id) {
        BlockRef block = allocations.at(id);
        int size = block->size;
        allocations.erase(id);
        freed.insert(id);
        roots.erase(id);
        references.erase(id);
        for (auto &[source,targets] : references) targets.erase(id);
        auto [free,merges] = heap->release(block);
        return "block=" + to_string(size) + " merges=" + to_string(merges) +
               " free=" + free->area();
    }
    void free_id(const string &id) {
        if (freed.count(id)) throw CommandError("DOUBLE FREE " + id);
        if (!allocations.count(id)) throw CommandError("UNKNOWN ID " + id);
        string details = release_id(id);
        ++counters["frees"];
        record(id,"FREE " + id + " " + details);
    }
    void realloc_id(const string &id, int request) {
        if (request == 0) {free_id(id);return;}
        if (freed.count(id)) throw CommandError("USE AFTER FREE " + id);
        if (!allocations.count(id)) {
            allocate_id("MALLOC",id,request,UNIT,UNINITIALIZED);
            return;
        }
        BlockRef block = allocations.at(id);
        int length = heap->required_length(request);
        vector<int> contents = block->contents;
        contents.resize(request,UNINITIALIZED);
        int original = block->payload();
        string kind = heap->resize(block,length);
        if (kind.empty()) {
            BlockRef moved = heap->allocate(length,UNIT);
            if (!moved) throw out_of_memory(id);
            moved->owner = id;
            allocations[id] = moved;
            heap->release(block);
            ++counters["moves"];
            block = moved;
            kind = "moved from=" + to_string(original);
        }
        block->requested = request;
        block->contents = move(contents);
        ++counters["reallocs"];
        record(id,"REALLOC " + id + " addr=" + to_string(block->payload()) +
               " block=" + to_string(block->size) + " " + kind);
    }
    void tree_node(const map<int,BlockRef> &leaves, int start, int size, int depth) {
        string label(depth*2,' ');
        label += to_string(start) + "+" + to_string(size);
        auto it = leaves.find(start);
        if (it != leaves.end() && it->second->size == size) {
            BlockRef block = it->second;
            emit(label,block->used ? "USED" : "FREE");
            if (block->used) {
                output.back() += " " + block->owner;
            }
            return;
        }
        emit(label,"split");
        tree_node(leaves,start,size/2,depth+1);
        tree_node(leaves,start+size/2,size/2,depth+1);
    }
    void run(const string &name, const vector<string> &v) {
        if (name == "HEAP") {
            int size = stoi(v[0]);
            const string &mode = v[1];
            if (size%UNIT != 0 || size<32 || size>MAX_HEAP ||
                (mode=="BUDDY" && !power_of_two(size)))
                throw CommandError("BAD HEAP SIZE");
            reset(make_unique<Heap>(mode,size));
            emit("HEAP size=" + to_string(size) + " mode=" + mode);
        } else if (name == "MALLOC") {
            allocate_id("MALLOC",v[0],stoi(v[1]),UNIT,UNINITIALIZED);
        } else if (name == "CALLOC") {
            allocate_id("CALLOC",v[0],stoi(v[1])*stoi(v[2]),UNIT,0);
        } else if (name == "MEMALIGN") {
            require_free_list();
            int align = stoi(v[1]);
            if (!power_of_two(align)||align<UNIT||align>4096)
                throw CommandError("BAD ALIGNMENT");
            allocate_id("MEMALIGN",v[0],stoi(v[2]),align,UNINITIALIZED);
        } else if (name == "REALLOC") {
            realloc_id(v[0],stoi(v[1]));
        } else if (name == "FREE") {
            free_id(v[0]);
        } else if (name == "FILL") {
            const string &id = v[0];
            int offset = stoi(v[1]), length = stoi(v[2]), value = stoi(v[3]);
            BlockRef block = range(id,offset,length);
            fill(block->contents.begin()+offset,block->contents.begin()+offset+length,value);
            emit("FILL",id,to_string(offset)+"+"+to_string(length),"=",value);
        } else if (name == "COPY") {
            const string &dest = v[0], &source = v[2];
            int doff = stoi(v[1]), soff = stoi(v[3]), length = stoi(v[4]);
            BlockRef destination = range(dest,doff,length);
            BlockRef origin = range(source,soff,length);
            vector<int> saved(origin->contents.begin()+soff,
                              origin->contents.begin()+soff+length);
            copy(saved.begin(),saved.end(),destination->contents.begin()+doff);
            emit("COPY",dest,to_string(doff)+"+"+to_string(length),"from",source,soff);
        } else if (name == "READ") {
            const string &id = v[0];
            int offset = stoi(v[1]), length = stoi(v[2]);
            BlockRef block = range(id,offset,length);
            ostringstream values;
            for (int i = 0; i<length; ++i) {
                if (i) values << ' ';
                int value = block->contents[offset+i];
                if (value==UNINITIALIZED) values << '?';
                else values << value;
            }
            emit("READ",id,to_string(offset)+"+"+to_string(length),"=",values.str());
        } else if (name == "ROOT") {
            live(v[0]);
            roots.insert(v[0]);
            emit("ROOT",v[0]);
        } else if (name == "UNROOT") {
            live(v[0]);
            if (!roots.count(v[0])) throw CommandError("NOT ROOT " + v[0]);
            roots.erase(v[0]);
            emit("UNROOT",v[0]);
        } else if (name == "LINK") {
            live(v[0]);
            live(v[1]);
            references[v[0]].insert(v[1]);
            emit("LINK",v[0],v[1]);
        } else if (name == "UNLINK") {
            live(v[0]);
            live(v[1]);
            if (!references[v[0]].count(v[1]))
                throw CommandError("NO LINK " + v[0] + " " + v[1]);
            references[v[0]].erase(v[1]);
            emit("UNLINK",v[0],v[1]);
        } else if (name == "GC") {
            auto found = reachable();
            vector<BlockRef> garbage;
            for (const auto &[id,block] : allocations)
                if (!found.count(id)) garbage.push_back(block);
            sort(garbage.begin(),garbage.end(),[](auto &a,auto &b){return a->start < b->start;});
            int bytes = 0;
            for (const auto &block : garbage) bytes += block->size;
            emit("GC collected="+to_string(garbage.size())+" bytes="+to_string(bytes));
            for (const auto &block : garbage) {
                string id = block->owner;
                record(id,"COLLECT " + id + " " + release_id(id));
            }
            counters["collected"] += (int)garbage.size();
        } else if (name == "SBRK") {
            int amount = stoi(v[0]);
            bool valid = heap->buddy()
                ? amount==heap->size && 2*heap->size<=MAX_HEAP
                : amount%UNIT==0 && amount>=MIN_BLOCK && heap->size+amount<=MAX_HEAP;
            if (!valid) throw CommandError("BAD SBRK SIZE");
            BlockRef free = heap->extend(amount);
            emit("SBRK heap="+to_string(heap->size)+" free="+free->area());
        } else if (name == "TRIM") {
            int released = heap->trim();
            emit("TRIM heap="+to_string(heap->size)+" released="+to_string(released));
        } else if (name == "COMPACT") {
            require_free_list();
            auto [moved,used] = heap->compact();
            counters["moves"] += (int)moved.size();
            string free = used < heap->size
                ? to_string(used)+"+"+to_string(heap->size-used) : "none";
            emit("COMPACT moved="+to_string(moved.size())+" free="+free);
            for (auto &step : moved) {
                BlockRef block = step.block;
                record(block->owner,"MOVE " + block->owner + " " + to_string(step.from)
                                    + " -> " + to_string(block->payload()));
            }
        } else if (name == "WHO") {
            int address = stoi(v[0]);
            if (address>=heap->size) { emit("WHO",address,"outside");return; }
            BlockRef block = heap->blocks[heap->locate(address)];
            if (!block->used) {emit("WHO",address,"free",block->area());return;}
            if (address < block->payload()) {
                emit("WHO",address,"header",block->owner);
                return;
            }
            int offset = address-block->payload();
            emit("WHO",address,offset<block->requested?"data":"slack",
                 block->owner+"+"+to_string(offset));
        } else if (name == "DUMP") {
            string line = "DUMP mode="+heap->mode+" heap="+to_string(heap->size)
                          +" blocks="+to_string(heap->blocks.size());
            if (heap->mode=="NEXT") line += " rover="+to_string(heap->rover);
            emit(line);
            for (auto &block : heap->blocks) {
                if (block->used)
                    emit(block->start,block->size,"USED",block->owner,"req="+to_string(block->requested));
                else emit(block->start,block->size,"FREE");
            }
        } else if (name == "MAP") {
            emit("MAP heap="+to_string(heap->size));
            string all;
            for (const BlockRef &block : heap->blocks) all += block->map_units();
            for (size_t first=0;first<all.size();first+=64) {
                ostringstream label;
                label << setw(5) << setfill('0') << first*UNIT;
                emit(label.str(),all.substr(first,64));
            }
        } else if (name == "FREELIST") {
            vector<BlockRef> free = heap->free_blocks();
            if (heap->mode=="SEGFIT") {
                sort(free.begin(),free.end(),[](auto &a,auto &b){return a->stamp>b->stamp;});
            }
            emit("FREELIST count="+to_string(free.size()));
            map<int,vector<string>> groups;
            for (auto &block : free) groups[size_class(block->size)].push_back(block->area());
            for (auto &[k,areas] : groups) {
                ostringstream line;
                line << (1 << k) << "-" << ((1 << (k+1))-1) << ":";
                for (const string &value : areas) line << " " << value;
                emit(line.str());
            }
        } else if (name == "TREE") {
            if (!heap->buddy()) throw CommandError("REQUIRES BUDDY MODE");
            emit("TREE heap="+to_string(heap->size));
            map<int,BlockRef> leaves;
            for (auto &block : heap->blocks) leaves[block->start] = block;
            tree_node(leaves,0,heap->size,0);
        } else if (name == "STATS") {
            auto used = heap->used_blocks(),free = heap->free_blocks();
            int total_free=0,largest=0,total_used=0,requested=0;
            for (auto &block:used) {total_used+=block->size;requested+=block->requested;}
            for (auto &block:free) {total_free+=block->size;largest=max(largest,block->size);}
            emit("STATS used="+to_string(total_used)+" used_blocks="+to_string(used.size())
                 +" free="+to_string(total_free)+" free_blocks="+to_string(free.size())
                 +" largest="+to_string(largest)
                 +" frag="+to_string(fragmentation_percent(total_free,largest))
                 +" requested="+to_string(requested)+" peak="+to_string(peak));
            ostringstream line;
            line << "OPS";
            for (const string &key : COUNTERS) line << " " << key << "=" << counters[key];
            emit(line.str());
        } else if (name == "LEAKS") {
            auto found = reachable();
            vector<string> names;
            int lost = 0, requested = 0;
            for (const auto &[id,block] : allocations) {
                names.push_back(id);
                requested += block->requested;
                if (!found.count(id)) ++lost;
            }
            sort(names.begin(),names.end());
            emit("LEAKS count="+to_string(names.size())+" requested="+to_string(requested)
                 +" lost="+to_string(lost));
            for (const string &id : names) {
                BlockRef block = allocations[id];
                emit("LEAK "+id+" addr="+to_string(block->payload())
                     +" block="+to_string(block->size)
                     +" req="+to_string(block->requested)
                     +" "+(found.count(id)?"reachable":"lost"));
            }
        } else if (name == "HISTORY") {
            const auto &lines = histories[v[0]];
            emit("HISTORY",v[0],"events="+to_string(lines.size()));
            output.insert(output.end(),lines.begin(),lines.end());
        } else if (name == "BENCH") {
            int size = stoi(v[0]),operations = stoi(v[2]),max_request = stoi(v[3]);
            int64_t seed = stoll(v[1]);
            if (!power_of_two(size)||size<32||size>MAX_HEAP)
                throw CommandError("BAD HEAP SIZE");
            emit("BENCH heap="+to_string(size)+" seed="+to_string(seed)
                 +" ops="+to_string(operations)+" maxreq="+to_string(max_request));
            for (const string &mode : MODES) emit(experiment(mode,size,seed,operations,max_request));
        }
    }
    void execute(const string &line) {
        istringstream words(line);
        vector<string> tokens;
        string word;
        while (words >> word) tokens.push_back(move(word));
        const string command = tokens[0];
        vector<string> args(tokens.begin()+1,tokens.end());
        try {
            if (!heap && command!="HEAP" && command!="BENCH")
                throw CommandError("NO HEAP");
            run(command,args);
        } catch (const CommandError &error) {
            emit("ERROR",error.what());
        }
        if (heap) peak=max(peak,heap->used_total());
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int count = 0;
    cin >> count;
    string line;
    getline(cin,line);
    Allocator allocator;
    for (int i=0;i<count;++i) {
        getline(cin,line);
        allocator.execute(line);
    }
    for (const string &text : allocator.output) cout << text << '\n';
}
