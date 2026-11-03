func copyObject(_ m: Memory, _ id: Int?, _ r: inout Record, _ copied: inout Set<Int>, _ queue: inout [Int]) {
    guard let id = id, copied.insert(id).inserted else {
        return
    };
    m.objects[id].address = m.top;
    m.top += m.objects[id].size;
    m.objects[id].moves += 1;
    r.live.add(m.objects[id]);
    r.moved.add(m.objects[id]);
    queue.append(id)
}
func collectCopy(_ m: Memory, _ roots: [Int?], _ line: Int, _ request: Int) {
    var r = Record(line, request, "copy", m.freeList);
    m.base = m.size/2-m.base;
    m.top = m.base;
    var copied = Set<Int>(), queue = [Int]();
    r.work += roots.count;
    for root in roots {
        copyObject(m, root, &r, &copied, &queue)
    };
    var i = 0;
    while i<queue.count {
        let id = queue[i];
        i += 1;
        r.work += m.objects[id].size+m.objects[id].fields.count;
        for child in m.objects[id].fields {
            copyObject(m, child, &r, &copied, &queue)
        }
    };
    for id in m.ids {
        if !copied.contains(id) {
            r.freed.add(m.objects[id]);
            m.objects[id].present = false
        }
    };
    r.after = freeAmount(m.freeList);
    m.records.append(r)
}
