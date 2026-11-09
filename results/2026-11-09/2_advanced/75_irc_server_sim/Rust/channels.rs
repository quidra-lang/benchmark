use std::collections::BTreeSet;
use crate::masks;
pub struct Member {
    pub client: usize,
    pub operator: bool,
    pub voice: bool
}
pub struct Ban {
    pub mask: String,
    pub setter: String,
    pub time: usize
}
pub struct Channel {
    pub name: String,
    pub created: usize,
    pub members: Vec<Member>,
    pub topic: String,
    pub setter: String,
    pub topic_time: usize,
    pub bans: Vec<Ban>,
    pub flags: BTreeSet<u8>,
    pub key: String,
    pub limit: usize,
    pub peak: usize,
    pub messages: usize
}
impl Channel {
    pub fn new(name: String, time: usize) -> Self {
        Self {
            name,
            created: time,
            members: Vec::new(),
            topic: String::new(),
            setter: String::new(),
            topic_time: 0,
            bans: Vec::new(),
            flags: [b'n',b't'].iter().copied().collect(),
            key: String::new(),
            limit: 0,
            peak: 0,
            messages: 0
        }
    }
    pub fn member(&self, client: usize) -> Option<&Member> {
        self.members.iter().find(|m| m.client == client)
    }
    pub fn member_mut(&mut self, client: usize) -> Option<&mut Member> {
        self.members.iter_mut().find(|m| m.client == client)
    }
    pub fn add(&mut self, client: usize) {
        let operator = self.members.is_empty();
        self.members.push(Member {
            client,
            operator,
            voice: false
        });
        self.peak = self.peak.max(self.members.len());
    }
    pub fn remove(&mut self, client: usize) {
        self.members.retain(|m| m.client != client);
    }
    pub fn privilege(&self, client: usize) -> &str {
        self.member(client).map_or("",|m| if m.operator {
            "@"
        } else if m.voice {
            "+"
        } else {
            ""
        })
    }
    pub fn display(&self, client: usize, nickname: &str) -> String {
        format!("{}{}",self.privilege(client),nickname)
    }
    pub fn banned(&self, prefix: &str) -> bool {
        self.bans.iter().any(|b| masks::matches(&b.mask,prefix))
    }
    pub fn can_speak(&self, client: usize, prefix: &str) -> bool {
        let member = self.member(client);
        let privileged = member.map_or(false,|m| m.operator || m.voice);
        (member.is_some() || !self.flags.contains(&b'n')) && (!self.flags.contains(&b'm') || privileged) && (privileged || !self.banned(prefix))
    }
    pub fn mode(&self, include_key: bool) -> String {
        let mut result = "+".to_owned();
        for c in b"iklmnt" {
            if match *c {
                b'k' => !self.key.is_empty(),b'l' => self.limit > 0,_ => self.flags.contains(c)
            }
            {
                result.push(*c as char);
            }
        }
        if include_key && !self.key.is_empty() {
            result.push(' ');
            result.push_str(&self.key);
        }
        if self.limit > 0 {
            result.push_str(&format!(" {}",self.limit));
        }
        result
    }
}
