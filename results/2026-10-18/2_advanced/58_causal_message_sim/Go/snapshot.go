package main

type SnapshotRecord struct {
	Process, Time, Balance, L int
	Reason                    string
	V                         []int
	Pending                   []*Copy
}
type SnapshotChannel struct {
	Dispatched, Accepted int
	State                []*Copy
}
type Snapshot struct {
	Name                      string
	Start, Completed, Markers int
	Records                   []*SnapshotRecord
	Channels                  map[ChannelKey]*SnapshotChannel
	Ignored                   [][2]int
}
type CutResult struct {
	Orphans, Transit []*Copy
	Balances, Money  int
	Vector           bool
}

func analyzeCut(sim *Simulation, cut []int) CutResult {
	out := CutResult{Vector: true}
	for p, state := range sim.Processes {
		out.Balances += balanceAt(state, cut[p])
		if cut[p] > 0 && !lessEqual(state.Events[cut[p]-1].V, cut) {
			out.Vector = false
		}
	}
	out.Money = out.Balances
	for _, c := range sim.Copies {
		sent := c.Message.Event.Local <= cut[c.Source]
		received := c.Received != nil && c.Received.Local <= cut[c.Destination]
		if received && !sent {
			out.Orphans = append(out.Orphans, c)
		}
		if sent && !received {
			out.Transit = append(out.Transit, c)
			out.Money += c.Message.Amount
		}
	}
	return out
}
func snapshotCut(s *Snapshot) []int {
	out := make([]int, len(s.Records))
	for p, r := range s.Records {
		out[p] = r.V[p]
	}
	return out
}
