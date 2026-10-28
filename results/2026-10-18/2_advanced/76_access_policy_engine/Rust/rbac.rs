use std::collections::{BTreeMap,BTreeSet};
use std::fs;
pub struct Constraint {
    pub name: String,
    pub cardinality: usize,
    pub roles: BTreeSet<String>
}
pub struct Assignment {
    pub user: String,
    pub role: String,
    pub first: usize,
    pub last: usize
}
pub struct Rbac {
    pub roles: BTreeSet<String>,
    pub inherits: BTreeMap<String,BTreeSet<String>>,
    pub permissions: BTreeSet<(String,String,String)>,
    pub ssd: Vec<Constraint>,
    pub dsd: Vec<Constraint>,
    pub assignments: Vec<Assignment>,
    pub diagnostics: Vec<(usize,String,String)>
}
impl Rbac {
    pub fn closure(&self, roles: &BTreeSet<String>) -> BTreeSet<String> {
        let mut result = roles.clone();
        let mut queue: Vec<_> = roles.iter().cloned().collect();
        while let Some(role) = queue.pop() {
            if let Some(children) = self.inherits.get(&role) {
                for child in children {
                    if result.insert(child.clone()) {
                        queue.push(child.clone());
                    }
                }
            }
        }
        result
    }
    pub fn assigned(&self, user: &str, day: usize) -> BTreeSet<String> {
        self.assignments.iter().filter(|a| a.user == user && a.first <= day && day <= a.last).map(|a| a.role.clone()).collect()
    }
    pub fn authorized(&self, user: &str, day: usize) -> BTreeSet<String> {
        self.closure(&self.assigned(user,day))
    }
    fn path(&self, from: &str, to: &str) -> Option<Vec<String>> {
        if from == to {
            return Some(vec![from.to_owned()]);
        }
        if let Some(children) = self.inherits.get(from) {
            for child in children {
                if let Some(mut path) = self.path(child,to) {
                    path.insert(0,from.to_owned());
                    return Some(path);
                }
            }
        }
        None
    }
    pub fn read() -> Self {
        let rows: Vec<_> = fs::read_to_string("input/rbac.txt").unwrap().lines().enumerate().map(|(i,line)| (i+1,line.split_whitespace().map(str::to_owned).collect::<Vec<_>>())).collect();
        let mut result = Self {
            roles: BTreeSet::new(),
            inherits: BTreeMap::new(),
            permissions: BTreeSet::new(),
            ssd: Vec::new(),
            dsd: Vec::new(),
            assignments: Vec::new(),
            diagnostics: Vec::new()
        };
        for keyword in ["ROLE","INHERITS","PERMIT","SSD","DSD","ASSIGN"].iter().copied() {
            for (line,w) in rows.iter().filter(|(_,w)| w[0] == keyword) {
                let mut error = None;
                match keyword {
                    "ROLE" => {
                        if !result.roles.insert(w[1].clone()) {
                            error = Some(format!("duplicate role {}",w[1]));
                        }
                    }
                    "INHERITS" => {
                        if let Some(role) = w[1..3].iter().find(|r| !result.roles.contains(*r)) {
                            error = Some(format!("unknown role {}",role));
                        } else if result.inherits.get(&w[1]).map_or(false,|children| children.contains(&w[2])) {
                            error = Some(format!("duplicate inheritance {} {}",w[1],w[2]));
                        } else if let Some(mut path) = result.path(&w[2],&w[1]) {
                            path.insert(0,w[1].clone());
                            error = Some(format!("cycle {}",path.join(" > ")));
                        } else {
                            result.inherits.entry(w[1].clone()).or_default().insert(w[2].clone());
                        }
                    }
                    "PERMIT" => {
                        let permission = (w[1].clone(),w[2].clone(),w[3].clone());
                        if !result.roles.contains(&w[1]) {
                            error = Some(format!("unknown role {}",w[1]));
                        } else if !result.permissions.insert(permission) {
                            error = Some(format!("duplicate permission {} {} {}",w[1],w[2],w[3]));
                        }
                    }
                    "SSD" | "DSD" => {
                        let constraints = if keyword == "SSD" {
                            &result.ssd
                        } else {
                            &result.dsd
                        };
                        let roles: Vec<_> = w[3].split(',').map(str::to_owned).collect();
                        let cardinality = w[2].parse().unwrap();
                        if constraints.iter().any(|c| c.name == w[1]) {
                            error = Some(format!("duplicate constraint {}",w[1]));
                        } else if let Some(role) = roles.iter().find(|r| !result.roles.contains(*r)) {
                            error = Some(format!("unknown role {}",role));
                        } else if cardinality < 2 || cardinality > roles.len() {
                            error = Some(format!("bad cardinality {} {}",w[1],cardinality));
                        } else {
                            let constraint = Constraint {
                                name: w[1].clone(),
                                cardinality,
                                roles: roles.into_iter().collect()
                            };
                            if keyword == "SSD" {
                                result.ssd.push(constraint);
                            } else {
                                result.dsd.push(constraint);
                            }
                        }
                    }
                    _ => {
                        let first: usize = w[3].parse().unwrap();
                        let last: usize = w[4].parse().unwrap();
                        if !result.roles.contains(&w[2]) {
                            error = Some(format!("unknown role {}",w[2]));
                        } else if !(1 <= first && first <= last && last <= 365) {
                            error = Some(format!("bad range {} {}",first,last));
                        } else {
                            'constraints: for constraint in &result.ssd {
                                for day in first..=last {
                                    let mut assigned = result.assigned(&w[1],day);
                                    assigned.insert(w[2].clone());
                                    let closure = result.closure(&assigned);
                                    let intersection: Vec<_> = closure.intersection(&constraint.roles).cloned().collect();
                                    if intersection.len() >= constraint.cardinality {
                                        error = Some(format!("ssd {} day {} roles {}",constraint.name,day,intersection.join(",")));
                                        break 'constraints;
                                    }
                                }
                            }
                            if error.is_none() {
                                result.assignments.push(Assignment {
                                    user: w[1].clone(),
                                    role: w[2].clone(),
                                    first,
                                    last
                                });
                            }
                        }
                    }
                }
                if let Some(error) = error {
                    result.diagnostics.push((*line,keyword.to_owned(),error));
                }
            }
        }
        result.diagnostics.sort_by_key(|d| d.0);
        result
    }
}
