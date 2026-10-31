use crate::config_io::address;
pub const TYPES: [&str;5] = ["BusRd","BusRdX","BusUpgr","BusWr","WB"];
pub struct Transaction {
    pub start: usize,
    pub core: usize,
    pub kind: usize,
    pub block: usize,
    pub text: String
}
pub struct Bus {
    pub free: usize,
    pub wait: usize,
    pub latency: usize,
    pub transactions: Vec<Transaction>
}
impl Bus {
    pub fn new(latency: usize) -> Self {
        Self {
            free: 0,
            wait: 0,
            latency,
            transactions: Vec::new()
        }
    }
    pub fn assign(&mut self, request: usize, core: usize, kind: usize, block: usize) -> usize {
        let start = request.max(self.free);
        self.wait += start-request;
        self.free = start+self.latency;
        let index = self.transactions.len();
        self.transactions.push(Transaction {
            start,
            core,
            kind,
            block,
            text: String::new()
        });
        index
    }
    pub fn describe(&mut self, index: usize, line_size: usize, details: &str) {
        let t = &self.transactions[index];
        self.transactions[index].text = format!("{} {} c{} {} {}{}",index+1,t.start,t.core,TYPES[t.kind],address(t.block*line_size),details);
    }
}
