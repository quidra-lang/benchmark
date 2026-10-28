func mark(_ m: Memory, _ roots: [Int?], _ r: inout Record) {
    for i in m.objects.indices {
        m.objects[i].marked = false
    };
    r.work += roots.count;
    var stack = [Int]();
    for root in roots {
        guard let id = root, !m.objects[id].marked else {
            continue
        };
        m.objects[id].marked = true;
        stack.append(id);
        r.stack = max(r.stack, stack.count);
        while let id = stack.popLast() {
            r.live.add(m.objects[id]);
            r.work += 1+m.objects[id].fields.count;
            for child in m.objects[id].fields.compactMap( {
                $0
            }) {
                if !m.objects[child].marked {
                    m.objects[child].marked = true;
                    stack.append(child);
                    r.stack = max(r.stack, stack.count)
                }
            }
        }
    }
}
func sweep(_ m: Memory, _ r: inout Record) {
    for id in m.ids {
        r.work += 1;
        if !m.objects[id].marked {
            r.freed.add(m.objects[id]);
            m.objects[id].present = false
        }
    }
}
func collectMark(_ m: Memory, _ roots: [Int?], _ line: Int, _ request: Int, _ compact: Bool) {
    var r = Record(line, request, compact ? "compact" : "sweep", m.freeList);
    mark(m, roots, &r);
    if compact {
        r.work += m.ids.count+roots.count;
        var destination = 0;
        for id in m.ordered(m.ids) {
            if !m.objects[id].marked {
                r.freed.add(m.objects[id]);
                m.objects[id].present = false;
                continue
            };
            r.work += m.objects[id].fields.count;
            if m.objects[id].address != destination {
                r.moved.add(m.objects[id]);
                r.work += m.objects[id].size;
                m.objects[id].address = destination;
                m.objects[id].moves += 1
            };
            destination += m.objects[id].size
        };
        m.top = destination
    }else {
        sweep(m, &r)
    };
    r.after = freeAmount(m.freeList);
    m.records.append(r)
}
