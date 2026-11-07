#include "collector.hpp"
std::vector<int> address_order(const Heap &heap) {
    std::vector<int> ids;
    for (const Object &object : heap.objects)
        if (object.present)
            ids.push_back(object.id);
    std::sort(ids.begin(), ids.end(),
              [&](int a, int b) { return heap.object(a).address < heap.object(b).address; });
    return ids;
}
std::vector<std::pair<int, int>> free_blocks(const Heap &heap, int first, int end) {
    std::vector<std::pair<int, int>> blocks;
    int cursor = first;
    for (int id : address_order(heap)) {
        const Object &object = heap.object(id);
        if (object.address < first || object.address >= end)
            continue;
        if (object.address > cursor)
            blocks.emplace_back(cursor, object.address - cursor);
        cursor = object.address + object.size();
    }
    if (cursor < end)
        blocks.emplace_back(cursor, end - cursor);
    return blocks;
}
std::vector<std::pair<int, int>> free_blocks(const Heap &heap) {
    const std::string &type = heap.collector.type;
    if (type == "MARK_COMPACT" || type == "COPYING") {
        const int end = type == "COPYING" ? heap.base + heap.size / 2 : heap.size;
        if (heap.top < end)
            return {{heap.top, end - heap.top}};
        return {};
    }
    if (type == "GENERATIONAL") {
        std::vector<std::pair<int, int>> blocks;
        if (heap.top < heap.base + heap.collector.young / 2)
            blocks.emplace_back(heap.top, heap.base + heap.collector.young / 2 - heap.top);
        const auto old = free_blocks(heap, heap.collector.young, heap.size);
        blocks.insert(blocks.end(), old.begin(), old.end());
        return blocks;
    }
    return free_blocks(heap, 0, heap.size);
}
std::pair<int, int> free_amount(const Heap &heap) {
    int total = 0, largest = 0;
    for (const auto &block : free_blocks(heap)) {
        total += block.second;
        largest = std::max(largest, block.second);
    }
    return {total, largest};
}
int first_fit(const Heap &heap, int size, int first, int end) {
    for (const auto &block : free_blocks(heap, first, end))
        if (block.second >= size)
            return block.first;
    return -1;
}
int used(const Heap &heap) {
    int words = 0;
    for (const Object &object : heap.objects)
        if (object.present)
            words += object.size();
    return words;
}
std::string dec2(Integer a, Integer b) {
    const Integer value = (200 * a + b) / (2 * b);
    std::ostringstream text;
    text << value / 100 << '.' << std::setw(2) << std::setfill('0') << value % 100;
    return text.str();
}
std::string pct(Integer a, Integer b) {
    return b ? dec2(100 * a, b) : "-";
}
std::string class_table(const std::vector<int> &sizes) {
    int counts[5] = {};
    for (int size : sizes)
        ++counts[size == 1 ? 0 : size < 4 ? 1 : size < 8 ? 2 : size < 16 ? 3 : 4];
    std::ostringstream text;
    text << "1:" << counts[0] << " 2-3:" << counts[1] << " 4-7:" << counts[2] << " 8-15:" << counts[3]
         << " 16+:" << counts[4];
    return text.str();
}
std::string heap_map(const Heap &heap, const std::set<int> &reachable) {
    std::string map(heap.size, '.');
    const int half = heap.collector.type == "COPYING"        ? heap.size / 2
                     : heap.collector.type == "GENERATIONAL" ? heap.collector.young / 2
                                                             : 0;
    if (half) {
        const int inactive = half - heap.base;
        std::fill(map.begin() + inactive, map.begin() + inactive + half, '-');
    }
    for (const Object &object : heap.objects)
        if (object.present) {
            const bool live = reachable.count(object.id);
            map[object.address] = live ? char('A' + (object.id - 1) % 26) : '#';
            std::fill(map.begin() + object.address + 1, map.begin() + object.address + object.size(),
                      live ? char('a' + (object.id - 1) % 26) : '=');
        }
    return map;
}
