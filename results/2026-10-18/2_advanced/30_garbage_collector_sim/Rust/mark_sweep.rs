use crate::heap::{
    Memory, Record
};
pub fn mark(m: &mut Memory, roots: &[Option<usize>], r: &mut Record) {
    for o in &mut m.objects {
        o.marked = false
    }
    r.work += roots.len();
    let mut stack = vec![];
    for &root in roots {
        let Some(root) = root else {
            continue
        };
        if m.objects[root].marked {
            continue
        }
        m.objects[root].marked = true;
        stack.push(root);
        r.stack = r.stack.max(stack.len());
        while let Some(id) = stack.pop() {
            r.live.add(&m.objects[id]);
            r.work += 1+m.objects[id].fields.len();
            for child in m.objects[id].fields.clone().into_iter().flatten() {
                if !m.objects[child].marked {
                    m.objects[child].marked = true;
                    stack.push(child);
                    r.stack = r.stack.max(stack.len())
                }
            }
        }
    }
}
pub fn sweep(m: &mut Memory, r: &mut Record) {
    for id in m.ids() {
        r.work += 1;
        if !m.objects[id].marked {
            r.freed.add(&m.objects[id]);
            m.objects[id].present = false;
        }
    }
}
pub fn collect(m: &mut Memory, roots: &[Option<usize>], line: usize, request: usize, compact: bool) {
    let mut r = Record::new(line, request, if compact {
        "compact"
    }else {
        "sweep"
    }, &m.free_list());
    mark(m, roots, &mut r);
    if compact {
        r.work += m.ids().len()+roots.len();
        let mut dest = 0;
        for id in m.ordered(m.ids()) {
            let o = &mut m.objects[id];
            if !o.marked {
                r.freed.add(o);
                o.present = false;
                continue
            }
            r.work += o.fields.len();
            if o.address != dest {
                r.moved.add(o);
                r.work += o.size;
                o.address = dest;
                o.moves += 1
            }
            dest += o.size;
        }
        m.top = dest;
    }else {
        sweep(m, &mut r)
    }
    r.after = crate::heap::free_amount(&m.free_list());
    m.records.push(r);
}
