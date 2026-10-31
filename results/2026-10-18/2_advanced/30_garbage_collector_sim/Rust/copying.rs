use std::collections::BTreeSet;
use crate::heap::{
    Memory, Record, free_amount
};
fn copy(m: &mut Memory, id: Option<usize>, r: &mut Record, copied: &mut BTreeSet<usize>, queue: &mut Vec<usize>) {
    let Some(id) = id else {
        return
    };
    if !copied.insert(id) {
        return
    }
    let o = &mut m.objects[id];
    o.address = m.top;
    m.top += o.size;
    o.moves += 1;
    r.live.add(o);
    r.moved.add(o);
    queue.push(id);
}
pub fn collect(m: &mut Memory, roots: &[Option<usize>], line: usize, request: usize) {
    let mut r = Record::new(line, request, "copy", &m.free_list());
    m.base = m.size/2-m.base;
    m.top = m.base;
    let mut copied = BTreeSet::new();
    let mut queue = vec![];
    r.work += roots.len();
    for &root in roots {
        copy(m, root, &mut r, &mut copied, &mut queue)
    }
    let mut i = 0;
    while i<queue.len() {
        let id = queue[i];
        i += 1;
        r.work += m.objects[id].size+m.objects[id].fields.len();
        for child in m.objects[id].fields.clone() {
            copy(m, child, &mut r, &mut copied, &mut queue)
        }
    }
    for id in m.ids() {
        if !copied.contains(&id) {
            r.freed.add(&m.objects[id]);
            m.objects[id].present = false
        }
    }
    r.after = free_amount(&m.free_list());
    m.records.push(r);
}
