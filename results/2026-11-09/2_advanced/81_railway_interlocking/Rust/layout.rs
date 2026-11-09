use std::collections::BTreeSet;
use std::fs;
pub struct Section {
    pub name: String,
    pub length: i64,
    pub row: usize,
    pub first: usize,
    pub last: usize,
    pub failed: bool,
    pub occupied_seconds: usize,
    pub locked_seconds: usize,
    pub trains: BTreeSet<usize>
}
pub struct Motion {
    pub target: bool,
    pub completion: Option<usize>
}
pub struct Point {
    pub name: String,
    pub common: usize,
    pub normal: usize,
    pub reverse: usize,
    pub row: usize,
    pub column: usize,
    pub position: bool,
    pub motion: Option<Motion>,
    pub failed: bool,
    pub throws: usize,
    pub locked_seconds: usize,
    pub moving_seconds: usize
}
impl Point {
    pub fn detected(&self) -> bool {
        self.motion.is_none() && !self.failed
    }
    pub fn display(&self) -> char {
        if self.detected() {
            if self.position {
                'R'
            } else {
                'N'
            }
        } else {
            '?'
        }
    }
}
pub struct Signal {
    pub name: String,
    pub section: usize,
    pub up: bool,
    pub row: usize,
    pub column: usize,
    pub aspect: usize,
    pub seconds: [usize;3],
    pub passes: usize
}
pub struct Buffer {
    pub name: String,
    pub section: usize,
    pub end: usize,
    pub row: usize,
    pub column: usize
}
pub struct Boundary {
    pub name: String,
    pub section: usize,
    pub end: usize
}
pub struct Label {
    pub row: usize,
    pub column: usize,
    pub text: String
}
#[derive(Clone,Copy)] enum Connection {
    Boundary(usize),
    Buffer(usize),
    Joint(usize),
    Point(usize)
}
#[derive(Clone,Copy)] pub enum Beyond {
    Boundary(usize),
    Buffer,
    Section(usize),
    Impassable
}
pub struct Layout {
    pub sections: Vec<Section>,
    pub points: Vec<Point>,
    pub signals: Vec<Signal>,
    pub buffers: Vec<Buffer>,
    pub boundaries: Vec<Boundary>,
    pub labels: Vec<Label>,
    connections: Vec<[Option<Connection>;2]>
}
impl Layout {
    pub fn section(&self, name: &str) -> usize {
        self.sections.iter().position(|s| s.name == name).unwrap()
    }
    pub fn point(&self, name: &str) -> usize {
        self.points.iter().position(|s| s.name == name).unwrap()
    }
    pub fn signal(&self, section: usize, up: bool) -> Option<usize> {
        self.signals.iter().position(|s| s.section == section && s.up == up)
    }
    pub fn boundary(&self, name: &str) -> usize {
        self.boundaries.iter().position(|s| s.name == name).unwrap()
    }
    pub fn beyond(&self, section: usize, up: bool) -> Beyond {
        match self.connections[section][usize::from(up)].unwrap() {
            Connection::Boundary(b) => Beyond::Boundary(b),Connection::Buffer(_) => Beyond::Buffer,Connection::Joint(s) => Beyond::Section(s),Connection::Point(index) => {
                let p = &self.points[index];
                if p.motion.is_some() {
                    Beyond::Impassable
                } else {
                    let selected = if p.position {
                        p.reverse
                    } else {
                        p.normal
                    };
                    if section == p.common {
                        Beyond::Section(selected)
                    } else if section == selected {
                        Beyond::Section(p.common)
                    } else {
                        Beyond::Impassable
                    }
                }
            }
        }
    }
    pub fn read() -> Self {
        let mut layout = Self {
            sections: Vec::new(),
            points: Vec::new(),
            signals: Vec::new(),
            buffers: Vec::new(),
            boundaries: Vec::new(),
            labels: Vec::new(),
            connections: Vec::new()
        };
        for line in fs::read_to_string("input/layout.txt").unwrap().lines() {
            let w: Vec<_> = line.split_whitespace().collect();
            let number = |i: usize| w[i].parse::<usize>().unwrap();
            match w[0] {
                "SECTION" => {
                    layout.sections.push(Section {
                        name: w[1].to_owned(),
                        length: w[2].parse().unwrap(),
                        row: number(3),
                        first: number(4),
                        last: number(5),
                        failed: false,
                        occupied_seconds: 0,
                        locked_seconds: 0,
                        trains: BTreeSet::new()
                    });
                    layout.connections.push([None,None]);
                }
                "JOINT" => {
                    let a = layout.section(w[1]);
                    let b = layout.section(w[2]);
                    layout.connections[a][1] = Some(Connection::Joint(b));
                    layout.connections[b][0] = Some(Connection::Joint(a));
                }
                "POINT" => {
                    let index = layout.points.len();
                    let common = layout.section(w[3]);
                    let normal = layout.section(w[4]);
                    let reverse = layout.section(w[5]);
                    let side = usize::from(w[2] == "R");
                    layout.connections[common][side] = Some(Connection::Point(index));
                    layout.connections[normal][1-side] = Some(Connection::Point(index));
                    layout.connections[reverse][1-side] = Some(Connection::Point(index));
                    layout.points.push(Point {
                        name: w[1].to_owned(),
                        common,
                        normal,
                        reverse,
                        row: number(6),
                        column: number(7),
                        position: false,
                        motion: None,
                        failed: false,
                        throws: 0,
                        locked_seconds: 0,
                        moving_seconds: 0
                    });
                }
                "SIGNAL" => {
                    let section = layout.section(w[2]);
                    layout.signals.push(Signal {
                        name: w[1].to_owned(),
                        section,
                        up: w[3] == "UP",
                        row: number(4),
                        column: number(5),
                        aspect: 0,
                        seconds: [0;3],
                        passes: 0
                    });
                }
                "BUFFER" => {
                    let section = layout.section(w[2]);
                    let end = usize::from(w[3] == "R");
                    let index = layout.buffers.len();
                    layout.connections[section][end] = Some(Connection::Buffer(index));
                    layout.buffers.push(Buffer {
                        name: w[1].to_owned(),
                        section,
                        end,
                        row: number(4),
                        column: number(5)
                    });
                }
                "BOUNDARY" => {
                    let section = layout.section(w[2]);
                    let end = usize::from(w[3] == "R");
                    let index = layout.boundaries.len();
                    layout.connections[section][end] = Some(Connection::Boundary(index));
                    layout.boundaries.push(Boundary {
                        name: w[1].to_owned(),
                        section,
                        end
                    });
                }
                _ => layout.labels.push(Label {
                    row: number(1),
                    column: number(2),
                    text: w[3].to_owned()
                })
            }
        }
        layout
    }
}
