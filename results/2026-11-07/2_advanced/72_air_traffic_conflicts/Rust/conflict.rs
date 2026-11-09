use crate::trajectory::Trajectory;
#[derive(Clone)] pub struct Loss {
    pub lo: f64,
    pub hi: f64,
    pub time: f64,
    pub distance: f64,
    pub vertical: f64
}
#[derive(Clone)] pub struct Piece {
    pub a: usize,
    pub b: usize,
    pub loss: Loss
}
#[derive(Clone)] pub struct Conflict {
    pub a: usize,
    pub b: usize,
    pub start: f64,
    pub end: f64,
    pub pieces: Vec<Piece>,
    pub closest: usize
}
impl Conflict {
    pub fn pair(&self) -> (usize,usize) {
        (self.a,self.b)
    }
    pub fn closest(&self) -> &Piece {
        &self.pieces[self.closest]
    }
    pub fn active(&self, time: f64) -> bool {
        self.start <= time && time < self.end
    }
}
pub fn difference(a: [f64;3], b: [f64;3]) -> [f64;3] {
    [a[0]-b[0],a[1]-b[1],a[2]-b[2]]
}
pub fn loss(p: [f64;3], w: [f64;3], t1: f64, t2: f64, horizontal: f64, vertical: f64) -> Option<Loss> {
    let qa = w[0]*w[0]+w[1]*w[1];
    let qb = 2.0*(p[0]*w[0]+p[1]*w[1]);
    let qc = (p[0]*p[0]+p[1]*p[1])-horizontal*horizontal;
    let (mut lo,mut hi) = (t1,t2);
    if qa < 0.000000000001 {
        if qc >= 0.0 {
            return None;
        }
    } else {
        let discriminant = qb*qb-4.0*qa*qc;
        if discriminant <= 0.0 {
            return None;
        }
        let root = discriminant.sqrt();
        lo = lo.max(t1+(-qb-root)/(2.0*qa));
        hi = hi.min(t1+(-qb+root)/(2.0*qa));
    }
    if w[2] == 0.0 {
        if p[2].abs() >= vertical {
            return None;
        }
    } else {
        let r1 = (-vertical-p[2])/w[2];
        let r2 = (vertical-p[2])/w[2];
        lo = lo.max(t1+r1.min(r2));
        hi = hi.min(t1+r1.max(r2));
    }
    if hi-lo <= 0.000001 {
        return None;
    }
    let time = (if qa >= 0.000000000001 {
        t1+(-qb/(2.0*qa))
    } else {
        t1
    }).max(lo).min(hi);
    let tau = time-t1;
    let ex = p[0]+w[0]*tau;
    let ey = p[1]+w[1]*tau;
    Some(Loss {
        lo,
        hi,
        time,
        distance: (ex*ex+ey*ey).sqrt(),
        vertical: (p[2]+w[2]*tau).abs()
    })
}
pub fn pair(a: usize, b: usize, first: &Trajectory, second: &Trajectory, horizontal: f64, vertical: f64) -> Vec<Conflict> {
    let mut pieces = Vec::new();
    for (i,x) in first.segments.iter().enumerate() {
        for (j,y) in second.segments.iter().enumerate() {
            let t1 = x.start.max(y.start);
            let t2 = x.end.min(y.end);
            if t1 < t2 {
                if let Some(loss) = loss(difference(x.at(t1),y.at(t1)),difference(x.velocity,y.velocity),t1,t2,horizontal,vertical) {
                    pieces.push(Piece {
                        a: i,
                        b: j,
                        loss
                    });
                }
            }
        }
    }
    pieces.sort_by(|x,y| x.loss.lo.total_cmp(&y.loss.lo));
    let mut conflicts = Vec::<Conflict>::new();
    for piece in pieces {
        if conflicts.last().map_or(true,|c| piece.loss.lo-c.end > 0.000001) {
            conflicts.push(Conflict {
                a,
                b,
                start: piece.loss.lo,
                end: piece.loss.hi,
                pieces: vec![piece],
                closest: 0
            });
        } else {
            let c = conflicts.last_mut().unwrap();
            c.end = piece.loss.hi;
            if piece.loss.distance < c.closest().loss.distance-0.000000001 {
                c.closest = c.pieces.len();
            }
            c.pieces.push(piece);
        }
    }
    conflicts
}
pub fn sort(conflicts: &mut [Conflict]) {
    conflicts.sort_by(|x,y| x.start.total_cmp(&y.start).then(x.a.cmp(&y.a)).then(x.b.cmp(&y.b)));
}
pub fn list(trajectories: &[Trajectory], horizontal: f64, vertical: f64) -> Vec<Conflict> {
    let mut conflicts = Vec::new();
    for a in 0..trajectories.len() {
        for b in a+1..trajectories.len() {
            conflicts.extend(pair(a,b,&trajectories[a],&trajectories[b],horizontal,vertical));
        }
    }
    sort(&mut conflicts);
    conflicts
}
