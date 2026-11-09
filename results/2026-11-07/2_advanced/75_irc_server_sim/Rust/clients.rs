use std::collections::VecDeque;
pub struct Client {
    pub id: String,
    pub host: String,
    pub connected: usize,
    pub nickname: Option<String>,
    pub username: Option<String>,
    pub realname: String,
    pub invisible: bool,
    pub registered: bool,
    pub signon: Option<usize>,
    pub last_received: usize,
    pub last_speaking: usize,
    pub ping: Option<usize>,
    pub tokens: usize,
    pub refill: Option<usize>,
    pub queue: VecDeque<String>,
    pub channels: Vec<usize>,
    pub invites: Vec<usize>,
    pub away: String,
    pub received: usize,
    pub sent: usize
}
impl Client {
    pub fn new(id: String, host: String, time: usize, capacity: usize) -> Self {
        Self {
            id,
            host,
            connected: time,
            nickname: None,
            username: None,
            realname: String::new(),
            invisible: false,
            registered: false,
            signon: None,
            last_received: time,
            last_speaking: 0,
            ping: None,
            tokens: capacity,
            refill: None,
            queue: VecDeque::new(),
            channels: Vec::new(),
            invites: Vec::new(),
            away: String::new(),
            received: 0,
            sent: 0
        }
    }
    pub fn addressee(&self) -> &str {
        self.nickname.as_deref().unwrap_or("*")
    }
    pub fn prefix(&self) -> String {
        format!("{}!{}@{}",self.addressee(),self.username.as_deref().unwrap_or("*"),self.host)
    }
    pub fn mode(&self) -> &str {
        if self.invisible {
            "+i"
        } else {
            "+"
        }
    }
    pub fn use_token(&mut self, time: usize, capacity: usize, interval: usize) {
        if self.tokens == capacity {
            self.refill = Some(time+interval);
        }
        self.tokens -= 1;
    }
    pub fn refill(&mut self, time: usize, capacity: usize, interval: usize) {
        if self.refill == Some(time) {
            self.tokens += 1;
            self.refill = if self.tokens < capacity {
                Some(time+interval)
            } else {
                None
            };
        }
    }
}
