func writeBarrier(_ m: Memory, _ target: Int, _ value: Int?) {
    if m.objects[target].address<m.young {
        return
    };
    m.barriers += 1;
    if let value = value, m.objects[value].address<m.young, m.remembered.insert(target).inserted {
        m.remembers += 1
    }
}
func evacuate(_ m: Memory, _ id: Int?, _ r: inout Record, _ pending: inout Set<Int>, _ queue: inout [Int], _ target: inout Int) -> Bool {
    guard let id = id, pending.remove(id) != nil else {
        return true
    };
    m.objects[id].age += 1;
    m.objects[id].moves += 1
    if ["tenure", "full"].contains(r.kind) || m.objects[id].age >= m.promotionAge {
        guard let a = firstFit(m.oldBlocks, m.objects[id].size)else {
            return false
        };
        m.objects[id].address = a;
        r.promoted.add(m.objects[id])
    }else {
        m.objects[id].address = target;
        target += m.objects[id].size
    };
    r.moved.add(m.objects[id]);
    if !["major", "full"].contains(r.kind) {
        r.live.add(m.objects[id])
    };
    queue.append(id);
    return true
}
func collectGeneration(_ m: Memory, _ roots: [Int?], _ line: Int, _ request: Int, _ kind: String) -> Bool {
    var r = Record(line, request, kind, m.freeList)
    if ["major", "full"].contains(kind) {
        mark(m, roots, &r);
        for id in m.ids {
            if m.objects[id].address >= m.young {
                r.work += 1;
                if !m.objects[id].marked {
                    r.freed.add(m.objects[id]);
                    m.objects[id].present = false;
                    m.remembered.remove(id)
                }
            }
        }
    }
    var pending = Set(m.ids.filter {
        m.objects[$0].address<m.young
    });
    let destination = m.young/2-m.base;
    var target = destination, queue = [Int]();
    r.work += roots.count
    for root in roots {
        if !evacuate(m, root, &r, &pending, &queue, &target) {
            return false
        }
    }
    for id in m.ordered(Array(m.remembered)) {
        r.work += 1+m.objects[id].fields.count;
        for child in m.objects[id].fields {
            if !evacuate(m, child, &r, &pending, &queue, &target) {
                return false
            }
        }
    }
    var i = 0;
    while i<queue.count {
        let id = queue[i];
        i += 1;
        r.work += m.objects[id].size+m.objects[id].fields.count;
        for child in m.objects[id].fields {
            if !evacuate(m, child, &r, &pending, &queue, &target) {
                return false
            }
        }
    }
    for id in pending {
        r.freed.add(m.objects[id]);
        m.objects[id].present = false
    };
    m.base = destination;
    m.top = target;
    m.remembered = Set(m.ids.filter {
        id in m.objects[id].address >= m.young && m.objects[id].fields.compactMap {
            $0
        }.contains {
            m.objects[$0].address<m.young
        }
    });
    r.after = freeAmount(m.freeList);
    m.records.append(r);
    return true
}
