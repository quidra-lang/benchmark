mod hashing;
mod wallets;
mod transactions;
mod blocks;
mod chain;
use std::{
    collections::{
        BTreeMap, BTreeSet, VecDeque
    }, rc::Rc, fs, io
};
use hashing::{
    digest, merkle_root, short
};
use wallets::{
    Wallet, read_wallets
};
use transactions::{
    Transaction, Reference, Utxo, create_coinbase, create_transaction, check, apply
};
use blocks::{
    Block, mine_block
};
use chain::{
    BlockRecord, chain_to, fork_point, median_time, required_difficulty, reward
};
struct Params {
    values: BTreeMap<String, Vec<String>>
}
impl Params {
    fn get(&self, k: &str, i: usize) -> i64 {
        self.values[k][i].parse().unwrap()
    }
    fn n(&self, k: &str) -> usize {
        self.get(k, 0) as usize
    }
    fn read() -> io::Result<Self> {
        Ok(Self {
            values: fs::read_to_string("input/params.txt")?.lines().map(|l| {
                let mut f = l.split(' '); (f.next().unwrap().to_owned(), f.map(str::to_owned).collect())
            }).collect()
        })
    }
}
#[derive(Default)]
struct Peer {
    accepted_blocks: usize,
    rejected_blocks: usize,
    orphans: usize,
    accepted_txs: usize,
    rejected_txs: usize,
    ignored: usize,
    score: i64
}
#[derive(Clone)]
struct Entry {
    tx: Transaction,
    fee: i64,
    arrival: i64
}
struct Reorganization {
    time: i64,
    fork: usize,
    disconnected: usize,
    connected: usize,
    old: String,
    new: String
}
struct Acceptance {
    fee: i64,
    conflicts: Vec<String>
}
struct Node {
    p: Params,
    wallets: Vec<Wallet>,
    owners: BTreeMap<String, Wallet>,
    named: BTreeMap<String, Wallet>,
    now: i64,
    records: BTreeMap<String, Rc<BlockRecord>>,
    tip: Rc<BlockRecord>,
    main: Vec<Rc<BlockRecord>>,
    confirmed: BTreeMap<String, usize>,
    mempool: Vec<Entry>,
    orphans: Vec<(Block, String)>,
    rejected: BTreeSet<String>,
    drops: BTreeMap<String, String>,
    peers: BTreeMap<String, Peer>,
    rejections: BTreeMap<(String, String), usize>,
    reorganizations: Vec<Reorganization>,
    log: Vec<String>
}
impl Node {
    fn new(p: Params, wallets: Vec<Wallet>) -> Self {
        let owners: BTreeMap<String, Wallet >= wallets.iter().map(|w|(w.address.clone(), w.clone())).collect();
        let named: BTreeMap<String, Wallet >= wallets.iter().map(|w|(w.name.clone(), w.clone())).collect();
        let outputs = p.values["GENESIS"].chunks(2).map(|f|(named[&f[0]].address.clone(), f[1].parse().unwrap())).collect::<Vec<_>>();
        let cb = create_coinbase(0, &outputs);
        let block = Block::new(0, "0".repeat(32), cb.txid.clone(), 0, 0, 0, vec![cb.clone()]);
        let mut utxo = Utxo::new();
        apply(&mut utxo, &cb, 0);
        let tip = BlockRecord::new(block, None, utxo, vec![], "genesis".into());
        let mut records = BTreeMap::new();
        records.insert(tip.block.hash.clone(), tip.clone());
        let mut n = Self {
            p,
            wallets,
            owners,
            named,
            now: 0,
            records,
            tip,
            main: vec![],
            confirmed: BTreeMap::new(),
            mempool: vec![],
            orphans: vec![],
            rejected: BTreeSet::new(),
            drops: BTreeMap::new(),
            peers: BTreeMap::new(),
            rejections: BTreeMap::new(),
            reorganizations: vec![],
            log: vec![]
        };
        n.refresh();
        n
    }
    fn refresh(&mut self) {
        self.main = chain_to(self.tip.clone());
        self.confirmed.clear();
        for r in &self.main {
            for tx in &r.block.transactions {
                self.confirmed.insert(tx.txid.clone(), r.block.height);
            }
        }
    }
    fn log(&mut self, line: String) {
        self.log.push(format!("{} {line}", self.now));
    }
    fn tally(&mut self, c: &str, r: &str) {
        *self.rejections.entry((c.into(), r.into())).or_default() += 1;
    }
    fn height(&self) -> usize {
        self.tip.block.height+1
    }
    fn reward(&self, h: usize) -> i64 {
        reward(h, self.p.get("REWARD", 0), self.p.get("REWARD", 1) as usize)
    }
    fn difficulty(&self, r: Rc<BlockRecord>) -> usize {
        required_difficulty(r, self.p.n("DIFFICULTY"), self.p.n("RETARGET"), self.p.get("RETARGET", 1))
    }
    fn locked(&self) -> BTreeSet<Reference> {
        self.mempool.iter().flat_map(|e|e.tx.inputs.clone()).collect()
    }
    fn ranked(&self) -> Vec<Entry> {
        let mut out = self.mempool.clone();
        out.sort_by(|a, b|(b.fee*a.tx.size()).cmp(&(a.fee*b.tx.size())).then(a.tx.txid.cmp(&b.tx.txid)));
        out
    }
    fn balance(&self, a: &str) -> i64 {
        self.tip.utxo.values().filter(|c|c.address == a).map(|c|c.amount).sum()
    }
    fn acceptance(&self, tx: &Transaction) -> Result<Acceptance, String> {
        if tx.coinbase() {
            return Err("coinbase".into())
        }
        if self.confirmed.contains_key(&tx.txid) || self.mempool.iter().any(|e|e.tx.txid == tx.txid) {
            return Err("duplicate".into())
        }
        let fee = check(tx, &self.tip.utxo, &BTreeSet::new(), self.height(), &self.owners, self.p.n("MATURITY"))?;
        if fee*1000<self.p.get("MINFEERATE", 0)*tx.size() {
            return Err("low-fee".into())
        }
        let conflicts: Vec<&Entry >= self.mempool.iter().filter(|e|e.tx.inputs.iter().any(|r|tx.inputs.contains(r))).collect();
        if !conflicts.is_empty() && (fee <= conflicts.iter().map(|e|e.fee).sum() || conflicts.iter().any(|e|fee*e.tx.size() <= e.fee*tx.size())) {
            return Err("conflict".into())
        }
        Ok(Acceptance {
            fee,
            conflicts: conflicts.iter().map(|e|e.tx.txid.clone()).collect()
        })
    }
    fn drop(&mut self, id: &str, reason: &str) {
        self.mempool.retain(|e|e.tx.txid != id);
        self.drops.insert(id.into(), reason.into());
        self.log(format!("DROP {} {reason}", short(id)));
    }
    fn register(&mut self, tx: Transaction, a: Acceptance, arrival: i64) {
        for id in a.conflicts {
            self.drop(&id, "replaced");
        }
        self.mempool.push(Entry {
            tx,
            fee: a.fee,
            arrival
        });
        if self.mempool.len()>self.p.n("MEMPOOL") {
            let id = self.ranked().last().unwrap().tx.txid.clone();
            self.drop(&id, "mempool-full");
        }
    }
    fn switch(&mut self, target: Rc<BlockRecord>) {
        let old = self.tip.clone();
        let fork = fork_point(old.clone(), target.clone());
        let f = fork.block.height;
        let d = old.block.height-f;
        let c = target.block.height-f;
        if d>self.p.n("MAXREORG") {
            self.log(format!("REFUSE {} {} work {} fork {f} depth {d}", target.block.height, short(&target.block.hash), target.cumulative_work));
            return
        }
        let returned: Vec<Transaction >= self.main.iter().skip(f+1).flat_map(|r|r.block.transactions.iter().skip(1).cloned()).collect();
        self.tip = target.clone();
        self.refresh();
        if d == 0 {
            self.log(format!("TIP {} {} work {}", target.block.height, short(&target.block.hash), target.cumulative_work));
        }else {
            self.log(format!("REORG {} {} work {} fork {f} disconnected {d} connected {c}", target.block.height, short(&target.block.hash), target.cumulative_work));
            self.reorganizations.push(Reorganization {
                time: self.now,
                fork: f,
                disconnected: d,
                connected: c,
                old: old.block.hash.clone(),
                new: target.block.hash.clone()
            });
        }
        let previous = std::mem::take(&mut self.mempool);
        let candidates = returned.into_iter().map(|t|(t, self.now, true)).chain(previous.into_iter().map(|e|(e.tx, e.arrival, false))).collect::<Vec<_>>();
        for (tx, arrival, is_returned) in candidates {
            if self.confirmed.contains_key(&tx.txid) {
                continue
            }
            match self.acceptance(&tx) {
                Err(reason) => self.drop(&tx.txid, &reason), Ok(a) => {
                    if is_returned {
                        self.log(format!("RETURN {}", short(&tx.txid)));
                    }
                    self.register(tx, a, arrival);
                }
            }
        }
    }
    fn penalize(&mut self, name: &str, points: i64) {
        let p = self.peers.get_mut(name).unwrap();
        let before = p.score;
        p.score += points;
        let score = p.score;
        if before<self.p.get("BAN", 0) && score >= self.p.get("BAN", 0) {
            self.log(format!("BAN {name} score {score}"));
        }
    }
    fn pay(&mut self, f: &[&str]) {
        let w = self.named[f[2]].clone();
        let fee: i64 = f[3].parse().unwrap();
        let mut outputs = f[4..].chunks(2).map(|p|(self.named[p[0]].address.clone(), p[1].parse().unwrap())).collect::<Vec<(String, i64)>>();
        let total: i64 = outputs.iter().map(|p|p.1).sum();
        let need = total+fee;
        let prefix = format!("PAY {} fee {fee} total {total}", w.name);
        let locked = self.locked();
        let mut coins = self.tip.utxo.iter().filter(|(r, c)|c.address == w.address && !locked.contains(*r) && c.mature(self.height(), self.p.n("MATURITY"))).collect::<Vec<_>>();
        coins.sort_by(|(ra, a), (rb, b)|b.amount.cmp(&a.amount).then(ra.cmp(rb)));
        let mut inputs = vec![];
        let mut gathered = 0;
        for (r, c) in coins {
            if gathered >= need {
                break
            }
            inputs.push(r.clone());
            gathered += c.amount;
        }
        if gathered<need {
            self.log(format!("{prefix} rejected insufficient-funds"));
            self.tally("pay", "insufficient-funds");
            return
        }
        if gathered>need {
            outputs.push((w.address, gathered-need));
        }
        let tx = create_transaction(&inputs, &outputs, &w.secret);
        match self.acceptance(&tx) {
            Err(r) => {
                self.log(format!("{prefix} tx {} rejected {r}", short(&tx.txid)));
                self.tally("pay", &r)
            }, Ok(a) => {
                self.log(format!("{prefix} tx {} accepted inputs {} outputs {} size {}", short(&tx.txid), tx.inputs.len(), tx.outputs.len(), tx.size()));
                self.register(tx, a, self.now)
            }
        }
    }
    fn bump(&mut self, id: &str, fee: i64) {
        let prefix = format!("BUMP {} fee {fee}", short(id));
        let Some(e) = self.mempool.iter().find(|e|e.tx.txid == id).cloned()else {
            self.log(format!("{prefix} rejected unknown"));
            self.tally("bump", "unknown");
            return
        };
        let (address, amount) = e.tx.outputs.last().unwrap();
        let change = amount-(fee-e.fee);
        if change<1 || e.tx.inputs.iter().any(|r|self.tip.utxo[r].address != *address) {
            self.log(format!("{prefix} rejected no-change"));
            self.tally("bump", "no-change");
            return
        }
        let mut outputs = e.tx.outputs.clone();
        outputs.last_mut().unwrap().1 = change;
        let tx = create_transaction(&e.tx.inputs, &outputs, &self.owners[address].secret);
        match self.acceptance(&tx) {
            Err(r) => {
                self.log(format!("{prefix} tx {} rejected {r}", short(&tx.txid)));
                self.tally("bump", &r)
            }, Ok(a) => {
                self.log(format!("{prefix} tx {} accepted size {}", short(&tx.txid), tx.size()));
                self.register(tx, a, self.now)
            }
        }
    }
    fn receive_tx(&mut self, peer: &str, tx: Transaction) {
        match self.acceptance(&tx) {
            Err(r) => {
                self.peers.get_mut(peer).unwrap().rejected_txs += 1;
                self.tally("tx", &r);
                self.log(format!("TX {peer} {} rejected {r}", short(&tx.txid)));
                if ["coinbase", "bad-output", "bad-sig", "overspend"].contains(&r.as_str()) {
                    self.penalize(peer, self.p.get("BAN", 2));
                }
            }, Ok(a) => {
                self.peers.get_mut(peer).unwrap().accepted_txs += 1;
                self.log(format!("TX {peer} {} accepted fee {} size {}", short(&tx.txid), a.fee, tx.size()));
                self.register(tx, a, self.now)
            }
        }
    }
    fn mine(&mut self, name: &str) {
        let h = self.height();
        let mut selected = vec![];
        let mut size = 0;
        for e in self.ranked() {
            if size+e.tx.size() <= self.p.get("MAXBLOCK", 0) {
                size += e.tx.size();
                selected.push(e);
            }
        }
        let fees: Vec<i64 >= selected.iter().map(|e|e.fee).collect();
        let cb = create_coinbase(h, &[(self.named[name].address.clone(), self.reward(h)+fees.iter().sum::<i64>())]);
        let mut txs = vec![cb];
        txs.extend(selected.into_iter().map(|e|e.tx));
        let b = mine_block(h, self.tip.block.hash.clone(), txs, self.now.max(median_time(self.tip.clone())+1), self.difficulty(self.tip.clone()));
        let mut utxo = self.tip.utxo.clone();
        for tx in &b.transactions {
            apply(&mut utxo, tx, h)
        }
        let r = BlockRecord::new(b, Some(self.tip.clone()), utxo, fees, "local".into());
        self.records.insert(r.block.hash.clone(), r.clone());
        self.log(format!("MINE {name} {h} {} bits {} nonce {} txs {} size {} fees {} work {}", short(&r.block.hash), r.block.difficulty, r.block.nonce, r.block.transactions.len(), r.block.size(), r.fees, r.cumulative_work));
        self.switch(r);
    }
    fn validate(&self, b: &Block, p: Rc<BlockRecord>) -> Result<(Utxo, Vec<i64>), String> {
        if b.height != p.block.height+1 {
            return Err("bad-height".into())
        }
        if b.difficulty != self.difficulty(p.clone()) {
            return Err("bad-difficulty".into())
        }
        if b.timestamp <= median_time(p.clone()) {
            return Err("time-too-old".into())
        }
        if b.timestamp>self.now+self.p.get("DRIFT", 0) {
            return Err("time-too-new".into())
        }
        let mut utxo = p.utxo.clone();
        let mut spent = BTreeSet::new();
        let mut fees = vec![];
        for (i, tx) in b.transactions.iter().enumerate().skip(1) {
            let fee = check(tx, &utxo, &spent, b.height, &self.owners, self.p.n("MATURITY")).map_err(|r|format!("{r} tx {}", i+1))?;
            spent.extend(tx.inputs.clone());
            apply(&mut utxo, tx, b.height);
            fees.push(fee);
        }
        let cb = &b.transactions[0];
        if cb.outputs.iter().any(|(a, v)|!self.owners.contains_key(a) || *v == 0) {
            return Err("bad-output tx 1".into())
        }
        if cb.total()>self.reward(b.height)+fees.iter().sum::<i64>() {
            return Err("bad-coinbase".into())
        }
        apply(&mut utxo, cb, b.height);
        Ok((utxo, fees))
    }
    fn reject(&mut self, kind: &str, b: &Block, peer: &str, reason: &str) {
        self.rejected.insert(b.hash.clone());
        self.peers.get_mut(peer).unwrap().rejected_blocks += 1;
        self.tally("block", reason.split(' ').next().unwrap());
        self.log(format!("{kind} {peer} {} {} rejected {reason}", b.height, short(&b.hash)));
        if reason != "time-too-new" {
            self.penalize(peer, self.p.get("BAN", 1));
        }
    }
    fn connect(&mut self, kind: &str, b: Block, peer: &str) {
        let parent = self.records[&b.previous].clone();
        match self.validate(&b, parent.clone()) {
            Err(reason) => self.reject(kind, &b, peer, &reason), Ok((utxo, fees)) => {
                let r = BlockRecord::new(b, Some(parent), utxo, fees, peer.into());
                self.records.insert(r.block.hash.clone(), r.clone());
                self.peers.get_mut(peer).unwrap().accepted_blocks += 1;
                self.log(format!("{kind} {peer} {} {} accepted work {}", r.block.height, short(&r.block.hash), r.cumulative_work));
                if r.cumulative_work>self.tip.cumulative_work {
                    self.switch(r)
                }
            }
        }
    }
    fn resolve(&mut self, start: String) {
        let mut queue = VecDeque::from([start]);
        while let Some(parent) = queue.pop_front() {
            let children = self.orphans.iter().filter(|(b, _)|b.previous == parent).cloned().collect::<Vec<_>>();
            for (b, peer) in children {
                self.orphans.retain(|(o, _)|o.hash != b.hash);
                let hash = b.hash.clone();
                if self.rejected.contains(&parent) {
                    self.reject("UNORPHAN", &b, &peer, "bad-parent");
                }else {
                    self.connect("UNORPHAN", b, &peer);
                }
                queue.push_back(hash);
            }
        }
    }
    fn receive_block(&mut self, peer: &str, b: Block) {
        if self.records.contains_key(&b.hash) || self.orphans.iter().any(|(o, _)|o.hash == b.hash) || self.rejected.contains(&b.hash) {
            self.log(format!("BLOCK {peer} {} {} rejected duplicate", b.height, short(&b.hash)));
            self.peers.get_mut(peer).unwrap().rejected_blocks += 1;
            self.tally("block", "duplicate");
            return
        }
        let reason = b.context_error(self.p.get("MAXBLOCK", 0)).or_else( || if self.rejected.contains(&b.previous) {
            Some("bad-parent".into())
        }else {
            None
        });
        let hash = b.hash.clone();
        if let Some(r) = reason {
            self.reject("BLOCK", &b, peer, &r);
            self.resolve(hash);
            return
        }
        if !self.records.contains_key(&b.previous) {
            self.log(format!("BLOCK {peer} {} {} orphan parent {}", b.height, short(&b.hash), short(&b.previous)));
            self.orphans.push((b, peer.into()));
            self.peers.get_mut(peer).unwrap().orphans += 1;
            if self.orphans.len()>self.p.n("ORPHANS") {
                let(o, _) = self.orphans.remove(0);
                self.log(format!("EVICT {} orphan-limit", short(&o.hash)));
            }
            return
        }
        self.connect("BLOCK", b, peer);
        self.resolve(hash);
    }
    fn status(&mut self, id: &str) {
        let prefix = format!("STATUS {}", short(id));
        if let Some(h) = self.confirmed.get(id) {
            self.log(format!("{prefix} confirmed {h} confirmations {}", self.height()-h));
            return
        }
        let ranked = self.ranked();
        if let Some(i) = ranked.iter().position(|e|e.tx.txid == id) {
            self.log(format!("{prefix} mempool rank {} of {}", i+1, ranked.len()));
        }else if let Some(r) = self.drops.get(id) {
            self.log(format!("{prefix} dropped {r}"));
        }else if self.records.values().any(|r|r.block.transactions.iter().any(|tx|tx.txid == id)) {
            self.log(format!("{prefix} stale"));
        }else {
            self.log(format!("{prefix} unknown"));
        }
    }
    fn print(&mut self) {
        let ranked = self.ranked();
        self.log(format!("PRINT height {} tip {} work {} bits {} reward {} mempool {} size {} orphans {}", self.tip.block.height, short(&self.tip.block.hash), self.tip.cumulative_work, self.difficulty(self.tip.clone()), self.reward(self.height()), ranked.len(), ranked.iter().map(|e|e.tx.size()).sum::<i64>(), self.orphans.len()));
        for(i, e)in ranked.iter().enumerate() {
            self.log(format!("MEMPOOL {} {} fee {} size {}", i+1, short(&e.tx.txid), e.fee, e.tx.size()));
        }
        for w in self.wallets.clone() {
            self.log(format!("BALANCE {} {}", w.name, self.balance(&w.address)));
        }
    }
    fn process(&mut self, f: &[&str], texts: &[&str]) {
        self.now = f[0].parse().unwrap();
        let expired = self.mempool.iter().filter(|e|self.now-e.arrival >= self.p.get("EXPIRY", 0)).map(|e|e.tx.txid.clone()).collect::<Vec<_>>();
        for id in expired {
            self.drop(&id, "expired");
        }
        match f[1] {
            "PAY" => self.pay(f), "BUMP" => self.bump(f[2], f[3].parse().unwrap()), "MINE" => self.mine(f[2]), "STATUS" => self.status(f[2]), "PRINT" => self.print(), kind => {
                let peer = f[2];
                let p = self.peers.entry(peer.into()).or_default();
                if p.score >= self.p.get("BAN", 0) {
                    p.ignored += 1;
                    self.log(format!("IGNORE {peer} {kind}"));
                }else if kind == "TX" {
                    self.receive_tx(peer, Transaction::parse(f[3]));
                }else {
                    self.receive_block(peer, Block::parse(f, texts));
                }
            }
        }
    }
    fn miner<'a>(&'a self, r: &BlockRecord) -> &'a str {
        &self.owners[&r.block.transactions[0].outputs[0].0].name
    }
    fn chain_lines(&self) -> Vec<String> {
        let tip = &self.tip;
        let mut lines = vec![format!("TIP {} {} work {} stored {} orphans {}", tip.block.height, tip.block.hash, tip.cumulative_work, self.records.len(), self.orphans.len())];
        for r in &self.main {
            let b = &r.block;
            let miner = if b.height == 0 {
                "-"
            }else {
                self.miner(r)
            };
            lines.push(format!("BLOCK {} {} prev {} time {} bits {} nonce {} txs {} size {} fees {} miner {miner} source {} work {}", b.height, b.hash, short(&b.previous), b.timestamp, b.difficulty, b.nonce, b.transactions.len(), b.size(), r.fees, r.source, r.cumulative_work));
            for (i, tx) in b.transactions.iter().enumerate() {
                if tx.coinbase() {
                    lines.push(format!("TX {} {} {} out {} amount {}", i+1, tx.txid, if b.height == 0 {
                        "genesis"
                    }else {
                        "coinbase"
                    }, tx.outputs.len(), tx.total()));
                }else {
                    lines.push(format!("TX {} {} payment in {} out {} size {} fee {}", i+1, tx.txid, tx.inputs.len(), tx.outputs.len(), tx.size(), r.transaction_fees[i-1]));
                }
            }
        }
        let main: BTreeSet<String >= self.main.iter().map(|r|r.block.hash.clone()).collect();
        let mut stale = self.records.values().filter(|r|!main.contains(&r.block.hash)).collect::<Vec<_>>();
        stale.sort_by_key(|r|(r.block.height, r.block.hash.clone()));
        for r in stale {
            lines.push(format!("STALE {} {} prev {} source {} work {}", r.block.height, r.block.hash, short(&r.block.previous), r.source, r.cumulative_work));
        }
        for (b, p) in &self.orphans {
            lines.push(format!("ORPHAN {} {} prev {} source {p}", b.height, b.hash, short(&b.previous)));
        }
        for r in &self.reorganizations {
            lines.push(format!("REORG {} fork {} disconnected {} connected {} old {} new {}", r.time, r.fork, r.disconnected, r.connected, short(&r.old), short(&r.new)));
        }
        for w in &self.wallets {
            let own = self.main.iter().skip(1).filter(|r|self.miner(r) == w.name).collect::<Vec<_>>();
            if !own.is_empty() {
                lines.push(format!("MINER {} blocks {} coinbase {} fees {}", w.name, own.len(), own.iter().map(|r|r.block.transactions[0].total()).sum::<i64>(), own.iter().map(|r|r.fees).sum::<i64>()));
            }
        }
        let mut i = 1;
        while i<self.main.len() {
            let d = self.main[i].block.difficulty;
            let start = i;
            while i+1<self.main.len() && self.main[i+1].block.difficulty == d {
                i += 1
            }
            lines.push(format!("BITS {d} heights {start}-{i} blocks {}", i-start+1));
            i += 1;
        }
        for(name, p)in &self.peers {
            lines.push(format!("PEER {name} blocks {} rejected {} orphans {} txs {} rejected {} ignored {} score {} {}", p.accepted_blocks, p.rejected_blocks, p.orphans, p.accepted_txs, p.rejected_txs, p.ignored, p.score, if p.score >= self.p.get("BAN", 0) {
                "banned"
            }else {
                "ok"
            }));
        }
        for (i, e) in self.ranked().iter().enumerate() {
            lines.push(format!("MEMPOOL {} {} fee {} size {} time {}", i+1, e.tx.txid, e.fee, e.tx.size(), e.arrival));
        }
        for((c, r), n)in &self.rejections {
            lines.push(format!("REJECT {c} {r} {n}"));
        }
        let genesis = self.main[0].block.transactions[0].total();
        let rewards: i64 = self.main.iter().skip(1).map(|r|self.reward(r.block.height)).sum();
        let fees: i64 = self.main.iter().skip(1).map(|r|r.fees).sum();
        let minted: i64 = self.main.iter().skip(1).map(|r|r.block.transactions[0].total()).sum();
        lines.push(format!("SUPPLY genesis {genesis} rewards {rewards} fees {fees} burned {} utxo {}", rewards+fees-minted, self.tip.utxo.values().map(|c|c.amount).sum::<i64>()));
        lines
    }
    fn balance_lines(&self) -> Vec<String> {
        let locked = self.locked();
        let mut lines = vec!["wallet,address,balance,immature,locked,incoming,utxos".into()];
        for w in &self.wallets {
            let coins = self.tip.utxo.iter().filter(|(_, c)|c.address == w.address).collect::<Vec<_>>();
            let immature: i64 = coins.iter().filter(|(_, c)|!c.mature(self.height(), self.p.n("MATURITY"))).map(|(_, c)|c.amount).sum();
            let amount: i64 = coins.iter().filter(|(r, _)|locked.contains(*r)).map(|(_, c)|c.amount).sum();
            let incoming: i64 = self.mempool.iter().flat_map(|e|&e.tx.outputs).filter(|o|o.0 == w.address).map(|o|o.1).sum();
            lines.push(format!("{},{},{},{immature},{amount},{incoming},{}", w.name, w.address, self.balance(&w.address), coins.len()));
        }
        lines
    }
    fn utxo_lines(&self) -> Vec<String> {
        let locked = self.locked();
        let mut lines = vec![];
        for((id, i), c)in &self.tip.utxo {
            let category = if c.height == 0 {
                "genesis"
            }else if c.coinbase {
                "coinbase"
            }else {
                "payment"
            };
            let state = if !c.mature(self.height(), self.p.n("MATURITY")) {
                "immature"
            }else if locked.contains(&(id.clone(), *i)) {
                "locked"
            }else {
                "free"
            };
            lines.push(format!("{id}:{i} {} {} height {} {category} {state}", self.owners[&c.address].name, c.amount, c.height));
        }
        let root = merkle_root(lines.iter().map(|s|digest(s)).collect());
        lines.push(format!("TOTAL {} {}", self.tip.utxo.len(), self.tip.utxo.values().map(|c|c.amount).sum::<i64>()));
        lines.push(format!("ROOT {root}"));
        lines
    }
    fn history_lines(&self) -> Vec<String> {
        let mut confirmed = BTreeMap::new();
        for r in &self.main {
            for t in &r.block.transactions {
                confirmed.insert(t.txid.clone(), t);
            }
        }
        let mut lines = vec![];
        for w in &self.wallets {
            lines.push(format!("WALLET {} {}", w.name, w.address));
            let(mut count, mut spent_total, mut received_total, mut balance) = (0, 0, 0, 0);
            for r in &self.main {
                for t in &r.block.transactions {
                    let mut spent = 0;
                    let mut involved = false;
                    for(id, i)in &t.inputs {
                        let(a, v) = &confirmed[id].outputs[*i];
                        if *a == w.address {
                            spent += v;
                            involved = true;
                        }
                    }
                    let mut received = 0;
                    for(a, v)in &t.outputs {
                        if *a == w.address {
                            received += v;
                            involved = true;
                        }
                    }
                    if !involved {
                        continue
                    }
                    count += 1;
                    spent_total += spent;
                    received_total += received;
                    balance += received-spent;
                    let category = if !t.coinbase() {
                        "payment"
                    }else if r.block.height == 0 {
                        "genesis"
                    }else {
                        "coinbase"
                    };
                    lines.push(format!("{} {} {category} spent {spent} received {received} net {:+} balance {balance}", r.block.height, short(&t.txid), received-spent));
                }
            }
            let mut pending = 0;
            for e in self.ranked() {
                let spent: i64 = e.tx.inputs.iter().map(|r|&self.tip.utxo[r]).filter(|c|c.address == w.address).map(|c|c.amount).sum();
                let received: i64 = e.tx.outputs.iter().filter(|o|o.0 == w.address).map(|o|o.1).sum();
                if spent != 0 || received != 0 {
                    pending += 1;
                    lines.push(format!("pending {} spent {spent} received {received} net {:+}", short(&e.tx.txid), received-spent));
                }
            }
            lines.push(format!("END {} txs {count} spent {spent_total} received {received_total} balance {balance} pending {pending}", w.name));
        }
        lines
    }
}
fn write_lines(name: &str, lines: Vec<String>) -> io::Result<()> {
    fs::write(format!("output/{name}"), if lines.is_empty() {
        String::new()
    }else {
        lines.join("\n")+"\n"
    })
}
fn main() -> io::Result<()> {
    let mut n = Node::new(Params::read()?, read_wallets()?);
    let text = fs::read_to_string("input/events.txt")?;
    let lines = text.lines().collect::<Vec<_>>();
    let mut i = 0;
    while i<lines.len() {
        let f = lines[i].split(' ').collect::<Vec<_>>();
        let count = if f[1] == "BLOCK" {
            f[9].parse().unwrap()
        }else {
            0
        };
        n.process(&f, &lines[i+1..i+1+count]);
        i += count+1;
    }
    fs::create_dir_all("output")?;
    write_lines("chain.txt", n.chain_lines())?;
    write_lines("balances.csv", n.balance_lines())?;
    write_lines("utxo.txt", n.utxo_lines())?;
    write_lines("history.txt", n.history_lines())?;
    write_lines("log.txt", n.log)
}
