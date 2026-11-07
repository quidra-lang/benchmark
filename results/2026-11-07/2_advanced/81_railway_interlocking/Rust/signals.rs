use crate::layout::Layout;
use crate::interlocking::{Finish,Interlocking};
pub const ASPECTS: [&str;3] = ["RED","YELLOW","GREEN"];
pub fn decide(layout: &Layout, interlocking: &Interlocking, occupied: &[bool]) -> Vec<usize> {
    let mut cleared = vec![None;layout.signals.len()];
    for (index,route) in interlocking.routes.iter().enumerate() {
        if route.state == 1 && route.points.iter().chain(&route.flank).all(|&(p,position)| layout.points[p].detected() && layout.points[p].position == position) && route.sections.iter().chain(&route.overlap).all(|&s| !occupied[s]) {
            cleared[route.start] = Some(index);
        }
    }
    cleared.iter().map(|route| if let Some(r) = route {
        match interlocking.routes[*r].finish {
            Finish::Signal(s) => if cleared[s].is_some() {
                2
            } else {
                1
            },Finish::Buffer(_) => 1,Finish::Boundary(_) => 2
        }
    } else {
        0
    }).collect()
}
