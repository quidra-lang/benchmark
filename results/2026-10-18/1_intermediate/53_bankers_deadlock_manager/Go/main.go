package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type Vector []int

type Process struct {
    Max, Allocation Vector
    Created int
}

type Waiting struct {
    ID int
    Value Vector
    Since int
}

type Event struct {
    Time int
    Kind string
    ID int
    Value Vector
    Wait int
}

type State struct {
    Total, Available Vector
    Processes map[int]*Process
    Queue []Waiting
    History []Event
}

type Manager struct {
    State
    Mode, Policy string
    Trace, Auto bool
    Time int
    Snapshots map[string]State
}
var out = bufio.NewWriter(os.Stdout)

func emit(s string) {
    fmt.Fprintln(out, s)
}

func number(s string) int {
    n, _ := strconv.Atoi(s)
    return n
}

func vector(a []string) Vector {
    v := make(Vector, len(a))
    for i, s := range a {
        v[i] = number(s)
    }
    return v
}

func copyv(v Vector) Vector {
    return append(Vector{}, v...)
}

func combine(a, b Vector, sign int) Vector {
    c := copyv(a)
    for i := range c {
        c[i] += sign * b[i]
    }
    return c
}

func le(a, b Vector) bool {
    for i := range a {
        if a[i] > b[i] {
            return false
        }
    }
    return true
}

func sum(a Vector) int {
    n := 0
    for _, x := range a {
        n += x
    }
    return n
}

func vf(v Vector) string {
    a := make([]string, len(v))
    for i, x := range v {
        a[i] = strconv.Itoa(x)
    }
    return "(" + strings.Join(a, ",") + ")"
}

func pname(id int) string {
    return fmt.Sprintf("P%d", id)
}

func pf(ids []int) string {
    a := make([]string, len(ids))
    for i, id := range ids {
        a[i] = pname(id)
    }
    return strings.Join(a, " ")
}

func (s State) ids() []int {
    ids := make([]int, 0, len(s.Processes))
    for id := range s.Processes {
        ids = append(ids, id)
    }
    sort.Ints(ids)
    return ids
}

func (s State) clone() State {
    c := State{copyv(s.Total), copyv(s.Available), make(map[int]*Process), append([]Waiting{}, s.Queue...), append([]Event{}, s.History...)}
    for id, p := range s.Processes {
        c.Processes[id] = &Process{copyv(p.Max), copyv(p.Allocation), p.Created}
    }
    for i := range c.Queue {
        c.Queue[i].Value = copyv(c.Queue[i].Value)
    }
    for i := range c.History {
        c.History[i].Value = copyv(c.History[i].Value)
    }
    return c
}

func (s State) request(id int) Vector {
    for _, q := range s.Queue {
        if q.ID == id {
            return q.Value
        }
    }
    return make(Vector, len(s.Total))
}

func (s State) blocked(id int) bool {
    for _, q := range s.Queue {
        if q.ID == id {
            return true
        }
    }
    return false
}

func (s State) check(detect, trace bool) (bool, []int, []int) {
    work := copyv(s.Available)
    remaining, idle, sequence := []int{}, []int{}, []int{}
    for _, id := range s.ids() {
        if detect && sum(s.Processes[id].Allocation) == 0 {
            idle = append(idle, id)
        } else {
            remaining = append(remaining, id)
        }
    }
    tag := "[safety]"
    if detect {
        tag = "[detect]"
    }
    if trace {
        line := tag + " start work=" + vf(work)
        if len(idle) > 0 {
            line += " idle " + pf(idle)
        }
        emit(line)
    }
    for {
        chosen := -1
        for i, id := range remaining {
            p := s.Processes[id]
            need := combine(p.Max, p.Allocation, -1)
            if detect {
                need = s.request(id)
            }
            if le(need, work) {
                chosen = i
                break
            }
        }
        if chosen < 0 {
            break
        }
        id := remaining[chosen]
        work = combine(work, s.Processes[id].Allocation, 1)
        sequence = append(sequence, id)
        remaining = append(remaining[: chosen], remaining[chosen + 1:]...)
        if trace {
            emit(tag + " " + pname(id) + " can finish, work=" + vf(work))
        }
    }
    if trace && len(remaining) > 0 {
        emit(tag + " stuck work=" + vf(work) + " remaining " + pf(remaining))
    }
    return len(remaining) == 0, sequence, remaining
}

func (m *Manager) decision(id int, v Vector, reject, trace bool) (string, string, []int) {
    p := m.Processes[id]
    if reject {
        if m.blocked(id) {
            return "rejected", "process " + pname(id) + " is blocked", nil
        }
        if sum(v) == 0 {
            return "rejected", "zero vector", nil
        }
        if !le(v, combine(p.Max, p.Allocation, -1)) {
            return "rejected", "request exceeds need", nil
        }
        if m.Mode == "ORDER" {
            last := -1
            for j, x := range p.Allocation {
                if x > 0 {
                    last = j
                }
            }
            for j, x := range v {
                if x > 0 && j <= last {
                    return "rejected", "resource order violation", nil
                }
            }
        }
    }
    if !le(v, m.Available) {
        return "blocked", "insufficient resources", nil
    }
    if m.Mode == "AVOID" {
        oldA, oldP := m.Available, p.Allocation
        m.Available = combine(oldA, v, -1)
        p.Allocation = combine(oldP, v, 1)
        ok, seq, _ := m.State.check(false, trace)
        m.Available, p.Allocation = oldA, oldP
        if !ok {
            return "blocked", "unsafe state", nil
        }
        return "granted", "", seq
    }
    return "granted", "", nil
}

func (m *Manager) event(kind string, id int, v Vector, wait int) {
    m.History = append(m.History, Event{m.Time, kind, id, copyv(v), wait})
}

func (m *Manager) grant(id int, v Vector) {
    p := m.Processes[id]
    p.Allocation = combine(p.Allocation, v, 1)
    m.Available = combine(m.Available, v, -1)
}

func (m *Manager) retry() {
    queue := append([]Waiting{}, m.Queue...)
    for _, q := range queue {
        result, _, _ := m.decision(q.ID, q.Value, false, m.Trace)
        if result == "granted" {
            m.grant(q.ID, q.Value)
            m.removeWait(q.ID)
            emit("unblocked " + pname(q.ID) + " " + vf(q.Value))
            m.event("unblocked", q.ID, q.Value, m.Time - q.Since)
        }
    }
}

func (m *Manager) removeWait(id int) {
    for i, q := range m.Queue {
        if q.ID == id {
            m.Queue = append(m.Queue[: i], m.Queue[i + 1:]...)
            return
        }
    }
}

func (m *Manager) terminate(id int, kind string, retry bool) {
    v := copyv(m.Processes[id].Allocation)
    m.Available = combine(m.Available, v, 1)
    delete(m.Processes, id)
    m.removeWait(id)
    emit(kind + " " + pname(id) + " released " + vf(v))
    m.event(kind, id, v, 0)
    if retry {
        m.retry()
    }
}

func (s State) victims() []int {
    _, _, dead := s.check(true, false)
    type Candidate struct {
        IDs []int
        Cost int
    }
    choices := []Candidate{}
    for mask := 1; mask < (1 << len(dead)); mask++ {
        c := Candidate{}
        for i, id := range dead {
            if mask & (1 << i) != 0 {
                c.IDs = append(c.IDs, id)
                c.Cost += sum(s.Processes[id].Allocation)
            }
        }
        choices = append(choices, c)
    }
    sort.Slice(choices, func(i, j int) bool {
        a, b := choices[i], choices[j]
        if len(a.IDs) != len(b.IDs) {
            return len(a.IDs) < len(b.IDs)
        }
        if a.Cost != b.Cost {
            return a.Cost < b.Cost
        }
        for k := range a.IDs {
            if a.IDs[k] != b.IDs[k] {
                return a.IDs[k] < b.IDs[k]
            }
        }
        return false
    })
    for _, c := range choices {
        trial := s.clone()
        for _, id := range c.IDs {
            trial.Available = combine(trial.Available, trial.Processes[id].Allocation, 1)
            delete(trial.Processes, id)
        }
        ok, _, _ := trial.check(true, false)
        if ok {
            return c.IDs
        }
    }
    return nil
}

func (m *Manager) graphs(resource bool) {
    ids := m.ids()
    n := len(m.Total)
    type Edge struct {
        To, Type int
    }
    edges := map[int][]Edge{}
    if resource {
        for _, x := range m.Total {
            if x != 1 {
                emit("error: not single-instance")
                return
            }
        }
        for j := 0; j < n; j++ {
            for _, id := range ids {
                if m.Processes[id].Allocation[j] > 0 {
                    emit(fmt.Sprintf("assign %c -> %s", 'A' + j, pname(id)))
                }
            }
        }
        for _, id := range ids {
            r := m.request(id)
            for j, x := range r {
                if x > 0 {
                    emit(fmt.Sprintf("request %s -> %c", pname(id), 'A' + j))
                    for _, to := range ids {
                        if m.Processes[to].Allocation[j] > 0 {
                            edges[id] = append(edges[id], Edge{to, j})
                        }
                    }
                }
            }
        }
        for _, id := range ids {
            p := m.Processes[id]
            r := m.request(id)
            for j, x := range p.Max {
                if x > p.Allocation[j] && r[j] == 0 {
                    emit(fmt.Sprintf("claim %s -> %c", pname(id), 'A' + j))
                }
            }
        }
    } else {
        count := 0
        for _, id := range ids {
            r := m.request(id)
            for _, to := range ids {
                if id == to {
                    continue
                }
                labels := []string{}
                for j, x := range r {
                    if x > m.Available[j] && m.Processes[to].Allocation[j] > 0 {
                        labels = append(labels, string(rune('A' + j)))
                    }
                }
                if len(labels) > 0 {
                    emit(pname(id) + " -> " + pname(to) + " on " + strings.Join(labels, ","))
                    edges[id] = append(edges[id], Edge{to, 0})
                    count++
                }
            }
        }
        if count == 0 {
            emit("no wait edges")
        }
    }
    cycles := [][]int{}
    for _, start := range ids {
        var visit func(int, []int, map[int]bool)
        visit = func(at int, path []int, seen map[int]bool) {
            for _, e := range edges[at] {
                next := append([]int{}, path...)
                if resource {
                    next = append(next, e.Type)
                }
                next = append(next, e.To)
                if e.To == start {
                    if resource || len(seen) >= 2 {
                        cycles = append(cycles, next)
                    }
                    continue
                }
                if e.To < start || seen[e.To] {
                    continue
                }
                seen[e.To] = true
                visit(e.To, next, seen)
                delete(seen, e.To)
            }
        }
        visit(start, []int{start}, map[int]bool{start: true})
    }
    sort.Slice(cycles, func(i, j int) bool {
        a, b := cycles[i], cycles[j]
        for k := 0; k < len(a) && k < len(b); k++ {
            if a[k] != b[k] {
                return a[k] < b[k]
            }
        }
        return len(a) < len(b)
    })
    for _, cycle := range cycles {
        parts := []string{}
        for i, x := range cycle {
            if resource && i % 2 == 1 {
                parts = append(parts, string(rune('A' + x)))
            } else {
                parts = append(parts, pname(x))
            }
        }
        emit("cycle: " + strings.Join(parts, " -> "))
    }
    if len(cycles) == 0 {
        emit("no cycles")
    }
}

func (m *Manager) table() {
    widths := make([]int, len(m.Total))
    names := make([]string, len(widths))
    for i, x := range m.Total {
        widths[i] = len(strconv.Itoa(x))
        names[i] = fmt.Sprintf("%*s", widths[i], string(rune('A' + i)))
    }
    name := strings.Join(names, " ")
    cw := []int{max(10, len(name)), max(3, len(name)), max(4, len(name)), max(7, len(name))}
    row := func(heading string, cols []string) {
        line := fmt.Sprintf("%-9s", heading)
        for i := 0; i < 4; i++ {
            value := ""
            if i < len(cols) {
                value = cols[i]
            }
            line += fmt.Sprintf("  %-*s", cw[i], value)
        }
        emit(strings.TrimRight(line, " "))
    }
    form := func(v Vector) string {
        a := make([]string, len(v))
        for i, x := range v {
            a[i] = fmt.Sprintf("%*d", widths[i], x)
        }
        return strings.Join(a, " ")
    }
    row("Process", []string{"Allocation", "Max", "Need", "Request"})
    row("", []string{name, name, name, name})
    for _, id := range m.ids() {
        p := m.Processes[id]
        row(pname(id), []string{form(p.Allocation), form(p.Max), form(combine(p.Max, p.Allocation, -1)), form(m.request(id))})
    }
    row("Available", []string{form(m.Available)})
    row("Total", []string{form(m.Total)})
    if len(m.Queue) == 0 {
        emit("blocked queue: empty")
    } else {
        a := []string{}
        for _, q := range m.Queue {
            a = append(a, fmt.Sprintf("%s %s since t=%d", pname(q.ID), vf(q.Value), q.Since))
        }
        emit("blocked queue: " + strings.Join(a, ", "))
    }
}

func (m *Manager) execute(a []string) {
    cmd := a[0]
    args := a[1:]
    err := ""
    id := 0
    var v Vector
    hasID := strings.Contains(" PROCESS CLAIM REQUEST WHATIF RELEASE FINISH ABORT CANCEL MAXGRANT ", " " + cmd + " ")
    hasVector := strings.Contains(" PROCESS CLAIM REQUEST WHATIF RELEASE ADD REMOVE ", " " + cmd + " ")
    if hasID {
        id = number(args[0])
    }
    if hasVector {
        start := 0
        if hasID {
            start = 1
        }
        v = vector(args[start:])
        if len(v) != len(m.Total) {
            err = "wrong vector length"
        }
    }
    if err == "" && hasID {
        _, exists := m.Processes[id]
        if cmd == "PROCESS" {
            if exists {
                err = "duplicate process " + pname(id)
            }
        } else if !exists {
            err = "unknown process " + pname(id)
        }
    }
    if err != "" {
        emit("error: " + err)
        return
    }
    switch cmd {
    case "RESOURCES":
        m.State = State{vector(args), vector(args), make(map[int]*Process), nil, nil}
        emit("resources " + vf(m.Total))
    case "MODE", "POLICY", "TRACE", "AUTODETECT":
        x := args[0]
        switch cmd {
        case "MODE":
            m.Mode = x
        case "POLICY":
            m.Policy = x
        case "TRACE":
            m.Trace = x == "ON"
        case "AUTODETECT":
            m.Auto = x == "ON"
        }
        emit(strings.ToLower(cmd) + " " + x)
    case "PROCESS":
        if !le(v, m.Total) {
            err = "max exceeds total"
        } else {
            m.Processes[id] = &Process{v, make(Vector, len(v)), m.Time}
            emit("process " + pname(id) + " max " + vf(v))
        }
    case "CLAIM":
        p := m.Processes[id]
        if m.blocked(id) {
            err = "process " + pname(id) + " is blocked"
        } else if !le(p.Allocation, v) {
            err = "claim below allocation"
        } else if !le(v, m.Total) {
            err = "max exceeds total"
        } else {
            old := p.Max
            p.Max = v
            if m.Mode == "AVOID" {
                ok, _, _ := m.State.check(false, m.Trace)
                if !ok {
                    p.Max = old
                    err = "claim makes state unsafe"
                }
            }
            if err == "" {
                emit("claim " + pname(id) + " max " + vf(v))
                m.retry()
            }
        }
    case "ADD", "REMOVE":
        if sum(v) == 0 {
            err = "zero vector"
        } else if cmd == "ADD" {
            m.Total = combine(m.Total, v, 1)
            m.Available = combine(m.Available, v, 1)
            emit("added " + vf(v) + " total " + vf(m.Total))
            m.retry()
        } else {
            total := combine(m.Total, v, -1)
            if !le(v, m.Available) {
                err = "remove exceeds available"
            } else {
                for _, x := range total {
                    if x == 0 {
                        err = "total must stay positive"
                        break
                    }
                }
                if err == "" {
                    for _, p := range m.Processes {
                        if !le(p.Max, total) {
                            err = "max exceeds total"
                            break
                        }
                    }
                }
                if err == "" {
                    old := m.Available
                    m.Available = combine(old, v, -1)
                    if m.Mode == "AVOID" {
                        ok, _, _ := m.State.check(false, m.Trace)
                        if !ok {
                            err = "removal makes state unsafe"
                        }
                    }
                    if err != "" {
                        m.Available = old
                    } else {
                        m.Total = total
                        emit("removed " + vf(v) + " total " + vf(total))
                    }
                }
            }
        }
    case "REQUEST", "WHATIF":
        result, reason, seq := m.decision(id, v, true, m.Trace)
        if cmd == "WHATIF" {
            line := "whatif " + pname(id) + " " + vf(v) + ": " + result
            if result != "granted" {
                line += " (" + reason + ")"
            } else if m.Mode == "AVOID" {
                line += ", safe sequence " + pf(seq)
            }
            emit(line)
        } else if result == "rejected" {
            err = reason
        } else {
            if result == "granted" {
                m.grant(id, v)
                emit("granted " + pname(id) + " " + vf(v))
            } else {
                m.Queue = append(m.Queue, Waiting{id, v, m.Time})
                emit("blocked " + pname(id) + " " + vf(v) + ": " + reason)
            }
            m.event(result, id, v, 0)
            if result == "blocked" && m.Auto {
                _, _, dead := m.State.check(true, m.Trace)
                if len(dead) > 0 {
                    emit("deadlock detected: " + pf(dead))
                }
            }
        }
    case "RELEASE":
        p := m.Processes[id]
        if m.blocked(id) {
            err = "process " + pname(id) + " is blocked"
        } else if sum(v) == 0 {
            err = "zero vector"
        } else if !le(v, p.Allocation) {
            err = "release exceeds allocation"
        } else {
            p.Allocation = combine(p.Allocation, v, -1)
            m.Available = combine(m.Available, v, 1)
            emit("released " + pname(id) + " " + vf(v))
            m.event("released", id, v, 0)
            m.retry()
        }
    case "FINISH", "ABORT":
        if cmd == "FINISH" && m.blocked(id) {
            err = "process " + pname(id) + " is blocked"
        } else {
            kind := "finished"
            if cmd == "ABORT" {
                kind = "aborted"
            }
            m.terminate(id, kind, true)
        }
    case "CANCEL":
        if !m.blocked(id) {
            err = "process " + pname(id) + " is not blocked"
        } else {
            value := m.request(id)
            m.removeWait(id)
            emit("cancelled " + pname(id) + " " + vf(value))
            m.event("cancelled", id, value, 0)
        }
    case "MAXGRANT":
        if m.blocked(id) {
            err = "process " + pname(id) + " is blocked"
        } else {
            need := combine(m.Processes[id].Max, m.Processes[id].Allocation, -1)
            values := make(Vector, len(need))
            for j, limit := range need {
                for x := limit; x > 0; x-- {
                    r := make(Vector, len(need))
                    r[j] = x
                    result, _, _ := m.decision(id, r, true, false)
                    if result == "granted" {
                        values[j] = x
                        break
                    }
                }
            }
            emit("maxgrant " + pname(id) + ": " + vf(values))
        }
    case "SAFE":
        if len(m.Processes) == 0 {
            emit("safe: no processes")
        } else {
            ok, seq, left := m.State.check(false, m.Trace)
            if ok {
                emit("safe: " + pf(seq))
            } else {
                emit("unsafe: " + pf(left) + " cannot finish")
            }
        }
    case "SEQUENCES":
        if len(m.Processes) == 0 {
            emit("safe sequences: no processes")
            break
        }
        count, k := 0, number(args[0])
        samples := []string{}
        ids := m.ids()
        var search func(Vector, []int, map[int]bool)
        search = func(work Vector, path []int, seen map[int]bool) {
            if len(path) == len(ids) {
                count++
                if len(samples) < k {
                    samples = append(samples, pf(path))
                }
                return
            }
            for _, id := range ids {
                p := m.Processes[id]
                if !seen[id] && le(combine(p.Max, p.Allocation, -1), work) {
                    seen[id] = true
                    search(combine(work, p.Allocation, 1), append(path, id), seen)
                    delete(seen, id)
                }
            }
        }
        search(m.Available, nil, map[int]bool{})
        emit(fmt.Sprintf("safe sequences: %d", count))
        for _, line := range samples {
            emit(line)
        }
    case "DEFICIT":
        values := make([]string, len(m.Total))
        for j := range values {
            limit := 0
            for _, p := range m.Processes {
                limit += p.Max[j] - p.Allocation[j]
            }
            values[j] = "-"
            for x := 0; x <= limit; x++ {
                s := m.State
                s.Available = copyv(m.Available)
                s.Available[j] += x
                ok, _, _ := s.check(false, false)
                if ok {
                    values[j] = strconv.Itoa(x)
                    break
                }
            }
        }
        emit("deficit: (" + strings.Join(values, ",") + ")")
    case "STATE":
        m.table()
    case "STATS":
        for j, total := range m.Total {
            used := total - m.Available[j]
            requested := 0
            for _, q := range m.Queue {
                requested += q.Value[j]
            }
            pct := used * 1000 / total
            emit(fmt.Sprintf("%c: allocated %d/%d (%d.%d%%), requested %d", 'A' + j, used, total, pct / 10, pct % 10, requested))
        }
        kinds := []string{"granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"}
        counts := map[string]int {}
        waits := 0
        for _, e := range m.History {
            counts[e.Kind]++
            if e.Kind == "unblocked" {
                waits += e.Wait
            }
        }
        parts := []string{}
        for _, kind := range kinds {
            parts = append(parts, fmt.Sprintf("%s %d", kind, counts[kind]))
        }
        emit("events: " + strings.Join(parts, ", "))
        if counts["unblocked"] == 0 {
            emit("waits: none")
        } else {
            avg := waits * 100 / counts["unblocked"]
            emit(fmt.Sprintf("waits: %d unblocked, total %d, average %d.%02d", counts["unblocked"], waits, avg / 100, avg % 100))
        }
    case "DETECT":
        _, _, dead := m.State.check(true, m.Trace)
        if len(dead) == 0 {
            emit("no deadlock")
        } else {
            emit("deadlocked: " + pf(dead))
        }
    case "VICTIMS":
        victims := m.State.victims()
        if len(victims) == 0 {
            emit("no deadlock")
        } else {
            emit("victims: " + pf(victims))
        }
    case "RECOVER":
        count := 0
        for {
            _, _, dead := m.State.check(true, m.Trace)
            if len(dead) == 0 {
                break
            }
            if len(args) > 0 {
                for _, id := range dead {
                    m.terminate(id, "aborted", false)
                    count++
                }
                m.retry()
                break
            }
            chosen := dead[0]
            for _, id := range dead[1:] {
                p, q := m.Processes[id], m.Processes[chosen]
                better := false
                switch m.Policy {
                case "ALLOC":
                    a, b := sum(p.Allocation), sum(q.Allocation)
                    better = a < b || a == b && id > chosen
                case "NEED":
                    a, b := sum(combine(p.Max, p.Allocation, -1)), sum(combine(q.Max, q.Allocation, -1))
                    better = a > b || a == b && id > chosen
                case "YOUNGEST":
                    better = p.Created > q.Created
                }
                if better {
                    chosen = id
                }
            }
            m.terminate(chosen, "aborted", true)
            count++
        }
        if count == 0 {
            emit("no deadlock")
        } else {
            emit(fmt.Sprintf("recovered: %d aborted", count))
        }
    case "WAITGRAPH":
        m.graphs(false)
    case "GRAPH":
        m.graphs(true)
    case "HISTORY":
        count := 0
        for _, e := range m.History {
            if len(args) > 0 && args[0] != e.Kind && args[0] != strconv.Itoa(e.ID) {
                continue
            }
            line := fmt.Sprintf("t=%d %s %s %s", e.Time, e.Kind, pname(e.ID), vf(e.Value))
            if e.Kind == "unblocked" {
                line += fmt.Sprintf(" waited %d", e.Wait)
            }
            emit(line)
            count++
        }
        if count == 0 {
            emit("no events")
        }
    case "SNAPSHOT":
        m.Snapshots[args[0]] = m.State.clone()
        emit("saved " + args[0])
    case "RESTORE":
        s, ok := m.Snapshots[args[0]]
        if !ok {
            err = "unknown snapshot " + args[0]
        } else {
            m.State = s.clone()
            emit("restored " + args[0])
        }
    }
    if err != "" {
        emit("error: " + err)
    }
}

func main() {
    defer out.Flush()
    reader := bufio.NewReader(os.Stdin)
    line, _ := reader.ReadString('\n')
    n := number(strings.TrimSpace(line))
    m := Manager{Mode: "AVOID", Policy: "ALLOC", Snapshots: map[string]State{}}
    for i := 1; i <= n; i++ {
        line, _ = reader.ReadString('\n')
        m.Time = i
        m.execute(strings.Fields(line))
    }
}
