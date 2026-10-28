package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

func integer(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		panic(err)
	}
	return n
}
func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func line(parts ...any) string {
	fields := make([]string, len(parts))
	for i, p := range parts {
		fields[i] = fmt.Sprint(p)
	}
	return strings.Join(fields, " ")
}

type Settings struct {
	InitialDifficulty, Retarget, Target, InitialReward, Halving, Maturity, MaxBlock, MinFee, MaxMempool,
	MaxOrphans, Drift, Expiry, MaxReorg, Ban, BlockPenalty, TxPenalty int
	Genesis []Output
}

func readSettings() Settings {
	fields := map[string][]string{}
	for _, l := range readLines("input/params.txt") {
		f := strings.Fields(l)
		fields[f[0]] = f[1:]
	}
	n := func(key string, i int) int { return integer(fields[key][i]) }
	s := Settings{InitialDifficulty: n("DIFFICULTY", 0), Retarget: n("RETARGET", 0), Target: n("RETARGET",
		1), InitialReward: n("REWARD", 0), Halving: n("REWARD", 1), Maturity: n("MATURITY", 0), MaxBlock: n("MAXBLOCK",
		0), MinFee: n("MINFEERATE", 0), MaxMempool: n("MEMPOOL", 0), MaxOrphans: n("ORPHANS", 0),
		Drift: n("DRIFT", 0), Expiry: n("EXPIRY", 0), MaxReorg: n("MAXREORG", 0), Ban: n("BAN", 0),
		BlockPenalty: n("BAN", 1), TxPenalty: n("BAN", 2)}
	for i := 0; i < len(fields["GENESIS"]); i += 2 {
		s.Genesis = append(s.Genesis, Output{fields["GENESIS"][i], integer(fields["GENESIS"][i+1])})
	}
	return s
}

type Peer struct {
	Name                                                                              string
	AcceptedBlocks, RejectedBlocks, Orphans, AcceptedTxs, RejectedTxs, Ignored, Score int
}
type Entry struct {
	Transaction  *Transaction
	Fee, Arrival int
}
type Orphan struct {
	Block *Block
	Peer  *Peer
}
type Reorganization struct {
	Time, Fork, Disconnected, Connected int
	Old, New                            string
}
type Acceptance struct {
	Reason    string
	Fee       int
	Conflicts []*Entry
}
type Node struct {
	Settings        Settings
	Wallets         []*Wallet
	Owners, Named   map[string]*Wallet
	Now             int
	Records         map[string]*BlockRecord
	Tip             *BlockRecord
	MainChain       []*BlockRecord
	Confirmed       map[string]int
	Mempool         []*Entry
	Orphans         []*Orphan
	Rejected        map[string]bool
	Dropped         map[string]string
	Peers           map[string]*Peer
	Rejections      map[string]int
	Reorganizations []Reorganization
	Logs            []string
}

func newNode(s Settings, wallets []*Wallet) *Node {
	n := &Node{Settings: s, Wallets: wallets, Owners: map[string]*Wallet{}, Named: map[string]*Wallet{},
		Records: map[string]*BlockRecord{}, Rejected: map[string]bool{}, Dropped: map[string]string{},
		Peers: map[string]*Peer{}, Rejections: map[string]int{}}
	for _, w := range wallets {
		n.Owners[w.Address] = w
		n.Named[w.Name] = w
	}
	outputs := []Output{}
	for _, o := range s.Genesis {
		outputs = append(outputs, Output{n.Named[o.Address].Address, o.Amount})
	}
	t := coinbase(0, outputs)
	b := newBlock(0, strings.Repeat("0", 32), t.Txid, 0, 0, 0, []*Transaction{t})
	u := Utxo{}
	applyTransaction(u, t, 0)
	n.Tip = newRecord(b, nil, u, nil, "genesis")
	n.Records[b.Hash] = n.Tip
	n.refresh()
	return n
}
func (n *Node) refresh() {
	n.MainChain = chainTo(n.Tip)
	n.Confirmed = map[string]int{}
	for _, r := range n.MainChain {
		for _, t := range r.Block.Transactions {
			n.Confirmed[t.Txid] = r.Block.Height
		}
	}
}
func (n *Node) log(parts ...any)              { n.Logs = append(n.Logs, fmt.Sprint(n.Now)+" "+line(parts...)) }
func (n *Node) tally(category, reason string) { n.Rejections[category+" "+reason]++ }
func (n *Node) height() int                   { return n.Tip.Block.Height + 1 }
func (n *Node) reward(h int) int              { return reward(h, n.Settings.InitialReward, n.Settings.Halving) }
func (n *Node) difficulty(parent *BlockRecord) int {
	return requiredDifficulty(parent, n.Settings.InitialDifficulty, n.Settings.Retarget, n.Settings.Target)
}
func (n *Node) mature(c Coin) bool { return c.Mature(n.height(), n.Settings.Maturity) }
func (n *Node) balance(address string) int {
	total := 0
	for _, c := range n.Tip.Utxo {
		if c.Address == address {
			total += c.Amount
		}
	}
	return total
}
func (n *Node) locked() map[Reference]bool {
	locked := map[Reference]bool{}
	for _, e := range n.Mempool {
		for _, r := range e.Transaction.Inputs {
			locked[r] = true
		}
	}
	return locked
}
func (n *Node) priority() []*Entry {
	entries := append([]*Entry(nil), n.Mempool...)
	sort.Slice(entries, func(i, j int) bool {
		a, b := entries[i], entries[j]
		x, y := a.Fee*b.Transaction.Size, b.Fee*a.Transaction.Size
		if x != y {
			return x > y
		}
		return a.Transaction.Txid < b.Transaction.Txid
	})
	return entries
}
func (n *Node) find(id string) *Entry {
	for _, e := range n.Mempool {
		if e.Transaction.Txid == id {
			return e
		}
	}
	return nil
}
func (n *Node) acceptance(t *Transaction) Acceptance {
	if t.Coinbase {
		return Acceptance{Reason: "coinbase"}
	}
	if _, ok := n.Confirmed[t.Txid]; ok || n.find(t.Txid) != nil {
		return Acceptance{Reason: "duplicate"}
	}
	reason, fee := checkTransaction(t, n.Tip.Utxo, nil, n.height(), n.Settings.Maturity, n.Owners)
	if reason != "" {
		return Acceptance{Reason: reason}
	}
	if fee*1000 < n.Settings.MinFee*t.Size {
		return Acceptance{Reason: "low-fee"}
	}
	inputs := map[Reference]bool{}
	for _, r := range t.Inputs {
		inputs[r] = true
	}
	result := Acceptance{Fee: fee}
	total := 0
	higher := true
	for _, e := range n.Mempool {
		conflict := false
		for _, r := range e.Transaction.Inputs {
			if inputs[r] {
				conflict = true
				break
			}
		}
		if conflict {
			result.Conflicts = append(result.Conflicts, e)
			total += e.Fee
			if fee*e.Transaction.Size <= e.Fee*t.Size {
				higher = false
			}
		}
	}
	if len(result.Conflicts) > 0 && (fee <= total || !higher) {
		return Acceptance{Reason: "conflict"}
	}
	return result
}
func (n *Node) recordDrop(id, reason string) {
	n.Dropped[id] = reason
	n.log("DROP", short(id), reason)
}
func (n *Node) drop(e *Entry, reason string) {
	for i, x := range n.Mempool {
		if x == e {
			n.Mempool = append(n.Mempool[:i], n.Mempool[i+1:]...)
			break
		}
	}
	n.recordDrop(e.Transaction.Txid, reason)
}
func (n *Node) register(t *Transaction, a Acceptance, arrival int) {
	for _, e := range a.Conflicts {
		n.drop(e, "replaced")
	}
	n.Mempool = append(n.Mempool, &Entry{t, a.Fee, arrival})
	if len(n.Mempool) > n.Settings.MaxMempool {
		order := n.priority()
		n.drop(order[len(order)-1], "mempool-full")
	}
}
func (n *Node) switchTip(target *BlockRecord) {
	old := n.Tip
	fork := forkPoint(old, target)
	d, c := old.Block.Height-fork.Block.Height, target.Block.Height-fork.Block.Height
	if d > n.Settings.MaxReorg {
		n.log("REFUSE", target.Block.Height, short(target.Block.Hash), "work", target.Work, "fork", fork.Block.Height, "depth", d)
		return
	}
	returned := []*Transaction{}
	for _, r := range n.MainChain[fork.Block.Height+1:] {
		returned = append(returned, r.Block.Transactions[1:]...)
	}
	n.Tip = target
	n.refresh()
	if d == 0 {
		n.log("TIP", target.Block.Height, short(target.Block.Hash), "work", target.Work)
	} else {
		n.log("REORG", target.Block.Height, short(target.Block.Hash), "work", target.Work, "fork", fork.Block.Height, "disconnected", d, "connected", c)
		n.Reorganizations = append(n.Reorganizations, Reorganization{n.Now, fork.Block.Height, d, c, old.Block.Hash, target.Block.Hash})
	}
	previous := n.Mempool
	n.Mempool = nil
	for _, t := range returned {
		if _, ok := n.Confirmed[t.Txid]; ok {
			continue
		}
		a := n.acceptance(t)
		if a.Reason != "" {
			n.recordDrop(t.Txid, a.Reason)
		} else {
			n.log("RETURN", short(t.Txid))
			n.register(t, a, n.Now)
		}
	}
	for _, e := range previous {
		t := e.Transaction
		if _, ok := n.Confirmed[t.Txid]; ok {
			continue
		}
		a := n.acceptance(t)
		if a.Reason != "" {
			n.recordDrop(t.Txid, a.Reason)
		} else {
			n.register(t, a, e.Arrival)
		}
	}
}
func (n *Node) penalize(p *Peer, points int) {
	before := p.Score
	p.Score += points
	if before < n.Settings.Ban && p.Score >= n.Settings.Ban {
		n.log("BAN", p.Name, "score", p.Score)
	}
}
func (n *Node) process(f, texts []string) {
	n.Now = integer(f[0])
	for _, e := range append([]*Entry(nil), n.Mempool...) {
		if n.Now-e.Arrival >= n.Settings.Expiry {
			n.drop(e, "expired")
		}
	}
	switch f[1] {
	case "PAY":
		n.pay(f)
	case "BUMP":
		n.bump(f[2], integer(f[3]))
	case "MINE":
		n.mine(n.Named[f[2]])
	case "STATUS":
		n.status(f[2])
	case "PRINT":
		n.printState()
	default:
		p := n.Peers[f[2]]
		if p == nil {
			p = &Peer{Name: f[2]}
			n.Peers[p.Name] = p
		}
		if p.Score >= n.Settings.Ban {
			p.Ignored++
			n.log("IGNORE", p.Name, f[1])
			return
		}
		if f[1] == "TX" {
			n.receiveTransaction(p, parseTransaction(f[3]))
		} else {
			n.receiveBlock(p, parseBlock(f, texts))
		}
	}
}
func (n *Node) pay(f []string) {
	sender := n.Named[f[2]]
	fee := integer(f[3])
	outputs := []Output{}
	total := 0
	for i := 4; i < len(f); i += 2 {
		amount := integer(f[i+1])
		outputs = append(outputs, Output{n.Named[f[i]].Address, amount})
		total += amount
	}
	prefix := []any{"PAY", sender.Name, "fee", fee, "total", total}
	need := total + fee
	locked := n.locked()
	coins := []Reference{}
	for ref, c := range n.Tip.Utxo {
		if c.Address == sender.Address && !locked[ref] && n.mature(c) {
			coins = append(coins, ref)
		}
	}
	sort.Slice(coins, func(i, j int) bool {
		a, b := n.Tip.Utxo[coins[i]], n.Tip.Utxo[coins[j]]
		if a.Amount != b.Amount {
			return a.Amount > b.Amount
		}
		return referenceLess(coins[i], coins[j])
	})
	inputs := []Reference{}
	gathered := 0
	for _, r := range coins {
		if gathered >= need {
			break
		}
		inputs = append(inputs, r)
		gathered += n.Tip.Utxo[r].Amount
	}
	if gathered < need {
		n.log(append(prefix, "rejected", "insufficient-funds")...)
		n.tally("pay", "insufficient-funds")
		return
	}
	if gathered > need {
		outputs = append(outputs, Output{sender.Address, gathered - need})
	}
	t := payment(inputs, outputs, sender.Secret)
	a := n.acceptance(t)
	prefix = append(prefix, "tx", short(t.Txid))
	if a.Reason != "" {
		n.log(append(prefix, "rejected", a.Reason)...)
		n.tally("pay", a.Reason)
		return
	}
	n.log(append(prefix, "accepted", "inputs", len(t.Inputs), "outputs", len(t.Outputs), "size", t.Size)...)
	n.register(t, a, n.Now)
}
func (n *Node) bump(id string, fee int) {
	prefix := []any{"BUMP", short(id), "fee", fee}
	e := n.find(id)
	reject := func(reason string) { n.log(append(prefix, "rejected", reason)...); n.tally("bump", reason) }
	if e == nil {
		reject("unknown")
		return
	}
	original := e.Transaction
	outputs := append([]Output(nil), original.Outputs...)
	last := &outputs[len(outputs)-1]
	last.Amount -= fee - e.Fee
	valid := last.Amount >= 1
	for _, r := range original.Inputs {
		if n.Tip.Utxo[r].Address != last.Address {
			valid = false
		}
	}
	if !valid {
		reject("no-change")
		return
	}
	t := payment(original.Inputs, outputs, n.Owners[last.Address].Secret)
	a := n.acceptance(t)
	prefix = append(prefix, "tx", short(t.Txid))
	if a.Reason != "" {
		reject(a.Reason)
		return
	}
	n.log(append(prefix, "accepted", "size", t.Size)...)
	n.register(t, a, n.Now)
}
func (n *Node) receiveTransaction(p *Peer, t *Transaction) {
	a := n.acceptance(t)
	if a.Reason != "" {
		p.RejectedTxs++
		n.tally("tx", a.Reason)
		n.log("TX", p.Name, short(t.Txid), "rejected", a.Reason)
		switch a.Reason {
		case "coinbase", "bad-output", "bad-sig", "overspend":
			n.penalize(p, n.Settings.TxPenalty)
		}
		return
	}
	p.AcceptedTxs++
	n.log("TX", p.Name, short(t.Txid), "accepted", "fee", a.Fee, "size", t.Size)
	n.register(t, a, n.Now)
}
func (n *Node) mine(w *Wallet) {
	h := n.height()
	selected := []*Transaction{}
	fees := []int{}
	size, total := 0, 0
	for _, e := range n.priority() {
		if size+e.Transaction.Size <= n.Settings.MaxBlock {
			selected = append(selected, e.Transaction)
			fees = append(fees, e.Fee)
			size += e.Transaction.Size
			total += e.Fee
		}
	}
	txs := append([]*Transaction{coinbase(h, []Output{{w.Address, n.reward(h) + total}})}, selected...)
	b := mineBlock(h, n.Tip.Block.Hash, txs, max(n.Now, medianTime(n.Tip)+1), n.difficulty(n.Tip))
	u := copyUtxo(n.Tip.Utxo)
	for _, t := range txs {
		applyTransaction(u, t, h)
	}
	r := newRecord(b, n.Tip, u, fees, "local")
	n.Records[b.Hash] = r
	n.log("MINE", w.Name, h, short(b.Hash), "bits", b.Difficulty, "nonce", b.Nonce, "txs", len(txs), "size", b.Size(), "fees", r.Fees, "work", r.Work)
	n.switchTip(r)
}
func (n *Node) receiveBlock(p *Peer, b *Block) {
	duplicate := n.Records[b.Hash] != nil || n.Rejected[b.Hash]
	for _, o := range n.Orphans {
		if o.Block.Hash == b.Hash {
			duplicate = true
		}
	}
	if duplicate {
		n.log("BLOCK", p.Name, b.Height, short(b.Hash), "rejected", "duplicate")
		p.RejectedBlocks++
		n.tally("block", "duplicate")
		return
	}
	reason := contextFreeError(b, n.Settings.MaxBlock)
	if reason == "" && n.Rejected[b.Previous] {
		reason = "bad-parent"
	}
	if reason != "" {
		n.rejectBlock("BLOCK", b, p, reason)
		n.resolveOrphans(b.Hash)
		return
	}
	if n.Records[b.Previous] == nil {
		n.Orphans = append(n.Orphans, &Orphan{b, p})
		p.Orphans++
		n.log("BLOCK", p.Name, b.Height, short(b.Hash), "orphan", "parent", short(b.Previous))
		if len(n.Orphans) > n.Settings.MaxOrphans {
			evicted := n.Orphans[0]
			n.Orphans = n.Orphans[1:]
			n.log("EVICT", short(evicted.Block.Hash), "orphan-limit")
		}
		return
	}
	n.connectBlock("BLOCK", b, p)
	n.resolveOrphans(b.Hash)
}
func (n *Node) validateBlock(b *Block, p *BlockRecord) (string, Utxo, []int) {
	if b.Height != p.Block.Height+1 {
		return "bad-height", nil, nil
	}
	if b.Difficulty != n.difficulty(p) {
		return "bad-difficulty", nil, nil
	}
	if b.Timestamp <= medianTime(p) {
		return "time-too-old", nil, nil
	}
	if b.Timestamp > n.Now+n.Settings.Drift {
		return "time-too-new", nil, nil
	}
	u := copyUtxo(p.Utxo)
	spent := map[Reference]bool{}
	fees := []int{}
	total := 0
	for i, t := range b.Transactions[1:] {
		reason, fee := checkTransaction(t, u, spent, b.Height, n.Settings.Maturity, n.Owners)
		if reason != "" {
			return fmt.Sprintf("%s tx %d", reason, i+2), nil, nil
		}
		for _, ref := range t.Inputs {
			spent[ref] = true
		}
		applyTransaction(u, t, b.Height)
		fees = append(fees, fee)
		total += fee
	}
	cb := b.Transactions[0]
	for _, out := range cb.Outputs {
		if n.Owners[out.Address] == nil || out.Amount == 0 {
			return "bad-output tx 1", nil, nil
		}
	}
	if cb.OutputTotal() > n.reward(b.Height)+total {
		return "bad-coinbase", nil, nil
	}
	applyTransaction(u, cb, b.Height)
	return "", u, fees
}
func (n *Node) connectBlock(kind string, b *Block, p *Peer) {
	parent := n.Records[b.Previous]
	reason, u, fees := n.validateBlock(b, parent)
	if reason != "" {
		n.rejectBlock(kind, b, p, reason)
		return
	}
	r := newRecord(b, parent, u, fees, p.Name)
	n.Records[b.Hash] = r
	p.AcceptedBlocks++
	n.log(kind, p.Name, b.Height, short(b.Hash), "accepted", "work", r.Work)
	if r.Work > n.Tip.Work {
		n.switchTip(r)
	}
}
func (n *Node) rejectBlock(kind string, b *Block, p *Peer, reason string) {
	n.Rejected[b.Hash] = true
	p.RejectedBlocks++
	n.tally("block", strings.Fields(reason)[0])
	n.log(kind, p.Name, b.Height, short(b.Hash), "rejected", reason)
	if reason != "time-too-new" {
		n.penalize(p, n.Settings.BlockPenalty)
	}
}
func (n *Node) resolveOrphans(start string) {
	queue := []string{start}
	for len(queue) > 0 {
		parent := queue[0]
		queue = queue[1:]
		children := []*Orphan{}
		remaining := []*Orphan{}
		for _, o := range n.Orphans {
			if o.Block.Previous == parent {
				children = append(children, o)
			} else {
				remaining = append(remaining, o)
			}
		}
		n.Orphans = remaining
		for _, o := range children {
			if n.Rejected[parent] {
				n.rejectBlock("UNORPHAN", o.Block, o.Peer, "bad-parent")
			} else {
				n.connectBlock("UNORPHAN", o.Block, o.Peer)
			}
			queue = append(queue, o.Block.Hash)
		}
	}
}
func (n *Node) status(id string) {
	if h, ok := n.Confirmed[id]; ok {
		n.log("STATUS", short(id), "confirmed", h, "confirmations", n.height()-h)
		return
	}
	order := n.priority()
	for i, e := range order {
		if e.Transaction.Txid == id {
			n.log("STATUS", short(id), "mempool", "rank", i+1, "of", len(order))
			return
		}
	}
	if reason, ok := n.Dropped[id]; ok {
		n.log("STATUS", short(id), "dropped", reason)
		return
	}
	for _, r := range n.Records {
		for _, t := range r.Block.Transactions {
			if t.Txid == id {
				n.log("STATUS", short(id), "stale")
				return
			}
		}
	}
	n.log("STATUS", short(id), "unknown")
}
func (n *Node) printState() {
	order := n.priority()
	size := 0
	for _, e := range order {
		size += e.Transaction.Size
	}
	n.log("PRINT", "height", n.Tip.Block.Height, "tip", short(n.Tip.Block.Hash), "work", n.Tip.Work,
		"bits", n.difficulty(n.Tip), "reward", n.reward(n.height()), "mempool", len(order), "size",
		size, "orphans", len(n.Orphans))
	for i, e := range order {
		n.log("MEMPOOL", i+1, short(e.Transaction.Txid), "fee", e.Fee, "size", e.Transaction.Size)
	}
	for _, w := range n.Wallets {
		n.log("BALANCE", w.Name, n.balance(w.Address))
	}
}
func (n *Node) miner(r *BlockRecord) string {
	return n.Owners[r.Block.Transactions[0].Outputs[0].Address].Name
}
func category(coinbase bool, height int) string {
	if height == 0 {
		return "genesis"
	}
	if coinbase {
		return "coinbase"
	}
	return "payment"
}
func (n *Node) chainLines() []string {
	tip := n.Tip
	lines := []string{line("TIP", tip.Block.Height, tip.Block.Hash, "work", tip.Work, "stored", len(n.Records), "orphans", len(n.Orphans))}
	main := map[string]bool{}
	for _, r := range n.MainChain {
		b := r.Block
		main[b.Hash] = true
		miner := "-"
		if b.Height > 0 {
			miner = n.miner(r)
		}
		lines = append(lines, line("BLOCK", b.Height, b.Hash, "prev", short(b.Previous), "time", b.Timestamp,
			"bits", b.Difficulty, "nonce", b.Nonce, "txs", len(b.Transactions), "size", b.Size(),
			"fees", r.Fees, "miner", miner, "source", r.Source, "work", r.Work))
		for i, t := range b.Transactions {
			if t.Coinbase {
				lines = append(lines, line("TX", i+1, t.Txid, category(true, b.Height), "out", len(t.Outputs), "amount", t.OutputTotal()))
			} else {
				lines = append(lines, line("TX", i+1, t.Txid, "payment", "in", len(t.Inputs), "out", len(t.Outputs), "size", t.Size, "fee", r.TransactionFees[i-1]))
			}
		}
	}
	stale := []*BlockRecord{}
	for hash, r := range n.Records {
		if !main[hash] {
			stale = append(stale, r)
		}
	}
	sort.Slice(stale, func(i, j int) bool {
		a, b := stale[i].Block, stale[j].Block
		if a.Height != b.Height {
			return a.Height < b.Height
		}
		return a.Hash < b.Hash
	})
	for _, r := range stale {
		b := r.Block
		lines = append(lines, line("STALE", b.Height, b.Hash, "prev", short(b.Previous), "source", r.Source, "work", r.Work))
	}
	for _, o := range n.Orphans {
		b := o.Block
		lines = append(lines, line("ORPHAN", b.Height, b.Hash, "prev", short(b.Previous), "source", o.Peer.Name))
	}
	for _, r := range n.Reorganizations {
		lines = append(lines, line("REORG", r.Time, "fork", r.Fork, "disconnected", r.Disconnected, "connected",
			r.Connected, "old", short(r.Old), "new", short(r.New)))
	}
	mined := n.MainChain[1:]
	for _, w := range n.Wallets {
		count, minted, fees := 0, 0, 0
		for _, r := range mined {
			if n.miner(r) == w.Name {
				count++
				minted += r.Block.Transactions[0].OutputTotal()
				fees += r.Fees
			}
		}
		if count > 0 {
			lines = append(lines, line("MINER", w.Name, "blocks", count, "coinbase", minted, "fees", fees))
		}
	}
	for i := 0; i < len(mined); {
		j := i
		for j+1 < len(mined) && mined[j+1].Block.Difficulty == mined[i].Block.Difficulty {
			j++
		}
		lines = append(lines, line("BITS", mined[i].Block.Difficulty, "heights", fmt.Sprintf("%d-%d", mined[i].Block.Height, mined[j].Block.Height), "blocks", j-i+1))
		i = j + 1
	}
	names := []string{}
	for name := range n.Peers {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		p := n.Peers[name]
		state := "ok"
		if p.Score >= n.Settings.Ban {
			state = "banned"
		}
		lines = append(lines, line("PEER", name, "blocks", p.AcceptedBlocks, "rejected", p.RejectedBlocks,
			"orphans", p.Orphans, "txs", p.AcceptedTxs, "rejected", p.RejectedTxs, "ignored", p.Ignored,
			"score", p.Score, state))
	}
	for i, e := range n.priority() {
		lines = append(lines, line("MEMPOOL", i+1, e.Transaction.Txid, "fee", e.Fee, "size", e.Transaction.Size, "time", e.Arrival))
	}
	keys := []string{}
	for k := range n.Rejections {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, key := range keys {
		lines = append(lines, line("REJECT", key, n.Rejections[key]))
	}
	rewards, fees, minted, total := 0, 0, 0, 0
	for _, r := range mined {
		rewards += n.reward(r.Block.Height)
		fees += r.Fees
		minted += r.Block.Transactions[0].OutputTotal()
	}
	for _, coin := range tip.Utxo {
		total += coin.Amount
	}
	lines = append(lines, line("SUPPLY", "genesis", n.MainChain[0].Block.Transactions[0].OutputTotal(),
		"rewards", rewards, "fees", fees, "burned", rewards+fees-minted, "utxo", total))
	return lines
}
func (n *Node) balanceLines() []string {
	lines := []string{"wallet,address,balance,immature,locked,incoming,utxos"}
	locked := n.locked()
	for _, w := range n.Wallets {
		balance, immature, amount, incoming, count := 0, 0, 0, 0, 0
		for r, c := range n.Tip.Utxo {
			if c.Address == w.Address {
				balance += c.Amount
				count++
				if !n.mature(c) {
					immature += c.Amount
				}
				if locked[r] {
					amount += c.Amount
				}
			}
		}
		for _, e := range n.Mempool {
			for _, o := range e.Transaction.Outputs {
				if o.Address == w.Address {
					incoming += o.Amount
				}
			}
		}
		lines = append(lines, fmt.Sprintf("%s,%s,%d,%d,%d,%d,%d", w.Name, w.Address, balance, immature, amount, incoming, count))
	}
	return lines
}
func (n *Node) utxoLines() []string {
	refs := []Reference{}
	for r := range n.Tip.Utxo {
		refs = append(refs, r)
	}
	sort.Slice(refs, func(i, j int) bool { return referenceLess(refs[i], refs[j]) })
	locked := n.locked()
	lines, hashes := []string{}, []string{}
	total := 0
	for _, r := range refs {
		c := n.Tip.Utxo[r]
		state := "free"
		if !n.mature(c) {
			state = "immature"
		} else if locked[r] {
			state = "locked"
		}
		text := line(r.String(), n.Owners[c.Address].Name, c.Amount, "height", c.Height, category(c.Coinbase, c.Height), state)
		lines = append(lines, text)
		hashes = append(hashes, digest(text))
		total += c.Amount
	}
	return append(lines, line("TOTAL", len(refs), total), line("ROOT", merkleRoot(hashes)))
}
func (n *Node) historyLines() []string {
	transactions := map[string]*Transaction{}
	for _, r := range n.MainChain {
		for _, t := range r.Block.Transactions {
			transactions[t.Txid] = t
		}
	}
	lines := []string{}
	for _, w := range n.Wallets {
		lines = append(lines, line("WALLET", w.Name, w.Address))
		count, spentTotal, receivedTotal, balance, pending := 0, 0, 0, 0, 0
		for _, r := range n.MainChain {
			for _, t := range r.Block.Transactions {
				spent, received := 0, 0
				involved := false
				for _, ref := range t.Inputs {
					o := transactions[ref.Txid].Outputs[ref.Index]
					if o.Address == w.Address {
						spent += o.Amount
						involved = true
					}
				}
				for _, o := range t.Outputs {
					if o.Address == w.Address {
						received += o.Amount
						involved = true
					}
				}
				if involved {
					count++
					spentTotal += spent
					receivedTotal += received
					balance += received - spent
					lines = append(lines, line(r.Block.Height, short(t.Txid), category(t.Coinbase, r.Block.Height),
						"spent", spent, "received", received, "net", fmt.Sprintf("%+d", received-spent),
						"balance", balance))
				}
			}
		}
		for _, e := range n.priority() {
			t := e.Transaction
			spent, received := 0, 0
			for _, ref := range t.Inputs {
				c := n.Tip.Utxo[ref]
				if c.Address == w.Address {
					spent += c.Amount
				}
			}
			for _, o := range t.Outputs {
				if o.Address == w.Address {
					received += o.Amount
				}
			}
			if spent != 0 || received != 0 {
				pending++
				lines = append(lines, line("pending", short(t.Txid), "spent", spent, "received", received, "net", fmt.Sprintf("%+d", received-spent)))
			}
		}
		lines = append(lines, line("END", w.Name, "txs", count, "spent", spentTotal, "received", receivedTotal, "balance", balance, "pending", pending))
	}
	return lines
}
func main() {
	n := newNode(readSettings(), readWallets())
	events := readLines("input/events.txt")
	for i := 0; i < len(events); i++ {
		f := strings.Fields(events[i])
		count := 0
		if f[1] == "BLOCK" {
			count = integer(f[9])
		}
		n.process(f, events[i+1:i+1+count])
		i += count
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("log.txt", n.Logs)
	writeLines("chain.txt", n.chainLines())
	writeLines("balances.csv", n.balanceLines())
	writeLines("utxo.txt", n.utxoLines())
	writeLines("history.txt", n.historyLines())
}
