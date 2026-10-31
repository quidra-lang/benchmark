use crate::object_parser::{
    self,
    Object
};
pub struct Member {
    pub object: Object,
    pub exports: Vec<String>,
    pub loaded: bool
}
pub struct Archive {
    pub members: Vec<Member>
}
impl Archive {
    pub fn read(name: &str) -> Self {
        let lines = object_parser::lines(name);
        let mut members = Vec::new();
        let mut i = 0;
        while i < lines.len() {
            let fields: Vec<&str> = lines[i].split(' ').collect();
            let member_name = format!("{}({})", name, fields[1]);
            let exports = fields[2..].iter().map(|s| s.to_string()).collect();
            i += 1;
            let start = i;
            while lines[i] != "end" {
                i += 1;
            }
            i += 1;
            members.push(Member {
                object: object_parser::parse(member_name, &lines[start..i]),
                exports,
                loaded: false
            });
        }
        Self {
            members
        }
    }
    pub fn scan<F: FnMut(&Member) -> bool>(&mut self, mut extract: F) -> bool {
        let mut any = false;
        loop {
            let mut changed = false;
            for member in &mut self.members {
                if !member.loaded && extract(member) {
                    member.loaded = true;
                    changed = true;
                    any = true;
                }
            }
            if !changed {
                break;
            }
        }
        any
    }
}
