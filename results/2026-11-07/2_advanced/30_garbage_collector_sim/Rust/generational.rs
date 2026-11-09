use std::collections::BTreeSet;
use crate::{
    heap::{
        Memory, Record, first_fit, free_amount
    }, mark_sweep::mark
};
pub fn write_barrier(m: &mut Memory, target: usize, value: Option<usize>) {
    if m.objects[target].address<m.young {
        return
    }
    m.barriers += 1;
    if value.is_some_and(|id|m.objects[id].address<m.young) && m.remembered.insert(target) {
        m.remembers += 1
    }
}
fn evacuate(m: &mut Memory, id: Option<usize>, r: &mut Record, pending: &mut BTreeSet<usize>, queue: &mut Vec<usize>, target: &mut usize) -> bool {
    let Some(id) = id else {
        return true
    };
    if !pending.remove(&id) {
        return true
    }
    m.objects[id].age += 1;
    m.objects[id].moves += 1;
    if ["tenure", "full"].contains(&r.kind.as_str()) || m.objects[id].age >= m.promotion_age {
        let Some(address) = first_fit(&m.old_blocks(), m.objects[id].size)else {
            return false
        };
        m.objects[id].address = address;
        r.promoted.add(&m.objects[id]);
    }else {
        m.objects[id].address = *target;
        *target += m.objects[id].size;
    }
    r.moved.add(&m.objects[id]);
    if !["major", "full"].contains(&r.kind.as_str()) {
        r.live.add(&m.objects[id])
    }
    queue.push(id);
    true
}
pub fn collect(m: &mut Memory, roots: &[Option<usize>], line: usize, request: usize, kind: &str) -> bool {
    let mut r = Record::new(line, request, kind, &m.free_list());
    if ["major", "full"].contains(&kind) {
        mark(m, roots, &mut r);
        for id in m.ids() {
            if m.objects[id].address >= m.young {
                r.work += 1;
                if !m.objects[id].marked {
                    r.freed.add(&m.objects[id]);
                    m.objects[id].present = false;
                    m.remembered.remove(&id);
                }
            }
        }
    }
    let mut pending = m.ids().into_iter().filter(|&id|m.objects[id].address<m.young).collect::<BTreeSet<_>>();
    let dest = m.young/2-m.base;
    let mut target = dest;
    let mut queue = vec![];
    r.work += roots.len();
    for &root in roots {
        if !evacuate(m, root, &mut r, &mut pending, &mut queue, &mut target) {
            return false
        }
    }
    let remembered = m.ordered(m.remembered.iter().copied());
    for id in remembered {
        r.work += 1+m.objects[id].fields.len();
        for child in m.objects[id].fields.clone() {
            if !evacuate(m, child, &mut r, &mut pending, &mut queue, &mut target) {
                return false
            }
        }
    }
    let mut i = 0;
    while i<queue.len() {
        let id = queue[i];
        i += 1;
        r.work += m.objects[id].size+m.objects[id].fields.len();
        for child in m.objects[id].fields.clone() {
            if !evacuate(m, child, &mut r, &mut pending, &mut queue, &mut target) {
                return false
            }
        }
    }
    for id in pending {
        r.freed.add(&m.objects[id]);
        m.objects[id].present = false;
    }
    m.base = dest;
    m.top = target;
    m.remembered = m.ids().into_iter().filter(|&id|m.objects[id].address >= m.young && m.objects[id].fields.iter().flatten().any(|&c|m.objects[c].address<m.young)).collect();
    r.after = free_amount(&m.free_list());
    m.records.push(r);
    true
}
