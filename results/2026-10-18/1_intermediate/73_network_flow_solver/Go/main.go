package main

import (
    "bufio"
    "fmt"
    "io"
    "os"
    "strconv"
    "strings"
)

type edge struct {
    from, to, capacity, cost, lower, flow int
}

type augmentation struct {
    path []int
    amount, stage, unit int
}

type piece struct {
    path []int
    amount int
    cycle bool
}

type graph struct {
    names []string
    edges []edge
}

func number(text string) int {
    value, _ := strconv.Atoi(text)
    return value
}

func (g *graph) copy() *graph {
    result := &graph{names: append([]string{}, g.names...), edges: append([]edge{}, g.edges...)}
    for i := range result.edges {
        result.edges[i].flow = 0
    }
    return result
}

func (g *graph) arcs(vertex int) []int {
    result := []int{}
    for i, e := range g.edges {
        if e.from == vertex {
            result = append(result, i + 1)
        }
    }
    for i, e := range g.edges {
        if e.to == vertex {
            result = append(result, -i - 1)
        }
    }
    return result
}

func (g *graph) endpoints(arc int) (int, int) {
    if arc > 0 {
        e := g.edges[arc - 1]
        return e.from, e.to
    }
    e := g.edges[-arc - 1]
    return e.to, e.from
}

func (g *graph) residual(arc int) int {
    if arc > 0 {
        e := g.edges[arc - 1]
        return e.capacity - e.flow
    }
    return g.edges[-arc - 1].flow
}

func (g *graph) arcCost(arc int) int {
    if arc > 0 {
        return g.edges[arc - 1].cost
    }
    return -g.edges[-arc - 1].cost
}

func (g *graph) push(path []int, amount int) {
    for _, arc := range path {
        if arc > 0 {
            g.edges[arc - 1].flow += amount
        } else {
            g.edges[-arc - 1].flow -= amount
        }
    }
}

func (g *graph) bottleneck(path []int) int {
    result := g.residual(path[0])
    for _, arc := range path[1:] {
        result = min(result, g.residual(arc))
    }
    return result
}

func (g *graph) bfs(source, threshold int) ([]int, []int) {
    levels, parents := make([]int, len(g.names)), make([]int, len(g.names))
    for i := range levels {
        levels[i] = -1
    }
    levels[source] = 0
    queue := []int{source}
    for at := 0; at < len(queue); at++ {
        vertex := queue[at]
        for _, arc := range g.arcs(vertex) {
            _, target := g.endpoints(arc)
            if g.residual(arc) >= threshold && levels[target] < 0 {
                levels[target], parents[target] = levels[vertex] + 1, arc
                queue = append(queue, target)
            }
        }
    }
    return levels, parents
}

func (g *graph) path(source, target int, parents []int) []int {
    result := []int{}
    for target != source {
        arc := parents[target]
        result = append(result, arc)
        target, _ = g.endpoints(arc)
    }
    for a, b := 0, len(result) - 1; a < b; a, b = a + 1, b - 1 {
        result[a], result[b] = result[b], result[a]
    }
    return result
}

func (g *graph) augment(source, target, threshold int) *augmentation {
    levels, parents := g.bfs(source, threshold)
    if levels[target] < 0 {
        return nil
    }
    path := g.path(source, target, parents)
    amount := g.bottleneck(path)
    g.push(path, amount)
    return &augmentation{path: path, amount: amount, stage: threshold}
}

func (g *graph) maximum(source, target int, mode string) ([]augmentation, int) {
    result, phases := []augmentation{}, 0
    if mode == "DINIC" {
        adjacency := make([][]int, len(g.names))
        for vertex := range adjacency {
            adjacency[vertex] = g.arcs(vertex)
        }
        for {
            levels, _ := g.bfs(source, 1)
            if levels[target] < 0 {
                break
            }
            phases++
            pointers := make([]int, len(g.names))
            path, vertex := []int{}, source
            for {
                if vertex == target {
                    amount := g.bottleneck(path)
                    g.push(path, amount)
                    result = append(result, augmentation{append([]int{}, path...), amount, phases, 0})
                    path, vertex = []int{}, source
                } else if pointers[vertex] == len(adjacency[vertex]) {
                    if vertex == source {
                        break
                    }
                    arc := path[len(path) - 1]
                    path = path[:len(path) - 1]
                    vertex, _ = g.endpoints(arc)
                    pointers[vertex]++
                } else {
                    arc := adjacency[vertex][pointers[vertex]]
                    _, next := g.endpoints(arc)
                    if g.residual(arc) > 0 && levels[next] == levels[vertex] + 1 {
                        path = append(path, arc)
                        vertex = next
                    } else {
                        pointers[vertex]++
                    }
                }
            }
        }
        return result, phases
    }
    threshold := 1
    if mode == "SCALING" {
        largest := 0
        for _, e := range g.edges {
            largest = max(largest, e.capacity)
        }
        for threshold * 2 <= largest {
            threshold *= 2
        }
    }
    for threshold > 0 {
        for {
            pushed := g.augment(source, target, threshold)
            if pushed == nil {
                break
            }
            result = append(result, *pushed)
        }
        threshold /= 2
    }
    return result, phases
}

func (g *graph) negativeCycle(useLower bool) bool {
    distance := make([]int, len(g.names))
    for pass := 0; pass < len(g.names); pass++ {
        changed := false
        for _, e := range g.edges {
            capacity := e.capacity
            if useLower {
                capacity -= e.lower
            }
            if capacity > 0 && distance[e.to] > distance[e.from] + e.cost {
                distance[e.to] = distance[e.from] + e.cost
                changed = true
            }
        }
        if !changed {
            return false
        }
    }
    return len(g.names) > 0
}

func (g *graph) shortest(source int) ([]int, []bool, []int) {
    distance, defined, parents := make([]int, len(g.names)), make([]bool, len(g.names)), make([]int, len(g.names))
    defined[source] = true
    arcs := []int{}
    for i := range g.edges {
        if g.residual(i + 1) > 0 {
            arcs = append(arcs, i + 1)
        }
    }
    for i := range g.edges {
        if g.residual(-i - 1) > 0 {
            arcs = append(arcs, -i - 1)
        }
    }
    for {
        changed := false
        for _, arc := range arcs {
            a, b := g.endpoints(arc)
            candidate := distance[a] + g.arcCost(arc)
            if defined[a] && (!defined[b] || candidate < distance[b]) {
                distance[b], defined[b], parents[b], changed = candidate, true, arc, true
            }
        }
        if !changed {
            return distance, defined, parents
        }
    }
}

func (g *graph) minimumCost(source, target, limit int) ([]augmentation, int, int) {
    paths, total, cost := []augmentation{}, 0, 0
    for limit < 0 || total < limit {
        distance, defined, parents := g.shortest(source)
        if !defined[target] {
            break
        }
        path := g.path(source, target, parents)
        amount := g.bottleneck(path)
        if limit >= 0 {
            amount = min(amount, limit - total)
        }
        g.push(path, amount)
        total, cost = total + amount, cost + amount * distance[target]
        paths = append(paths, augmentation{path: path, amount: amount, unit: distance[target]})
    }
    return paths, total, cost
}

func (g *graph) balances() ([]int, []int) {
    incoming, outgoing := make([]int, len(g.names)), make([]int, len(g.names))
    for _, e := range g.edges {
        outgoing[e.from] += e.flow
        incoming[e.to] += e.flow
    }
    return incoming, outgoing
}

func (g *graph) value(source int) int {
    incoming, outgoing := g.balances()
    return outgoing[source] - incoming[source]
}

func (g *graph) totalCost() int {
    total := 0
    for _, e := range g.edges {
        total += e.flow * e.cost
    }
    return total
}

func (g *graph) notation(path []int, originalEdges int) string {
    source, _ := g.endpoints(path[0])
    parts := []string{g.names[source]}
    for _, arc := range path {
        magnitude, sign := arc, "+"
        if arc < 0 {
            magnitude, sign = -arc, "-"
        }
        if originalEdges > 0 && magnitude > originalEdges {
            continue
        }
        _, target := g.endpoints(arc)
        parts = append(parts, sign + strconv.Itoa(magnitude), g.names[target])
    }
    return strings.Join(parts, " ")
}

func (g *graph) decompose() []piece {
    residual := make([]int, len(g.edges))
    balance := make([]int, len(g.names))
    for i, e := range g.edges {
        residual[i] = e.flow
        balance[e.from] += e.flow
        balance[e.to] -= e.flow
    }
    result := []piece{}
    for {
        first := -1
        for i, flow := range residual {
            if flow > 0 {
                first = i
                break
            }
        }
        if first < 0 {
            return result
        }
        source := g.edges[first].from
        for vertex, amount := range balance {
            if amount > 0 {
                source = vertex
                break
            }
        }
        vertices, path := []int{source}, []int{}
        for {
            vertex, chosen := vertices[len(vertices) - 1], -1
            for i, e := range g.edges {
                if e.from == vertex && residual[i] > 0 {
                    chosen = i
                    break
                }
            }
            path = append(path, chosen + 1)
            target := g.edges[chosen].to
            repeated := -1
            for i, held := range vertices {
                if held == target {
                    repeated = i
                    break
                }
            }
            if repeated >= 0 {
                cycle := append([]int{}, path[repeated:]...)
                amount := residual[cycle[0] - 1]
                for _, id := range cycle {
                    amount = min(amount, residual[id - 1])
                }
                for _, id := range cycle {
                    residual[id - 1] -= amount
                }
                result = append(result, piece{cycle, amount, true})
                break
            }
            vertices = append(vertices, target)
            if balance[target] < 0 {
                amount := min(balance[source], -balance[target])
                for _, id := range path {
                    amount = min(amount, residual[id - 1])
                }
                for _, id := range path {
                    residual[id - 1] -= amount
                }
                balance[source] -= amount
                balance[target] += amount
                result = append(result, piece{path, amount, false})
                break
            }
        }
    }
}

type network struct {
    graph
    demands []int
    owner string
    source, target int
    out *bufio.Writer
}

func (n *network) vertex(name string) (int, error) {
    for i, candidate := range n.names {
        if candidate == name {
            return i, nil
        }
    }
    return 0, fmt.Errorf("UNKNOWN NODE %s", name)
}

func (n *network) endpointsCheck(a, b string) (int, int, error) {
    source, err := n.vertex(a)
    if err != nil {
        return 0, 0, err
    }
    target, err := n.vertex(b)
    if err != nil {
        return 0, 0, err
    }
    if source == target {
        return 0, 0, fmt.Errorf("SAME NODE")
    }
    return source, target, nil
}

func (n *network) start(source, target int) int {
    if n.owner != "flow" || n.source != source || n.target != target {
        for i := range n.edges {
            n.edges[i].flow = 0
        }
    }
    n.owner, n.source, n.target = "flow", source, target
    return n.value(source)
}

func (n *network) flowList() {
    for i, e := range n.edges {
        fmt.Fprintf(n.out, "FLOW %d %s %s %d/%d\n", i + 1, n.names[e.from], n.names[e.to], e.flow, e.capacity)
    }
}

func (n *network) matching(w []string) error {
    left, right := strings.Split(w[1], ","), strings.Split(w[2], ",")
    ids, leftID, rightID := map[string]bool{}, map[string]int{}, map[string]int{}
    for i, name := range left {
        if ids[name] {
            return fmt.Errorf("DUPLICATE VERTEX %s", name)
        }
        ids[name], leftID[name] = true, i
    }
    for i, name := range right {
        if ids[name] {
            return fmt.Errorf("DUPLICATE VERTEX %s", name)
        }
        ids[name], rightID[name] = true, i
    }
    pairs := [][2]int{}
    seen := map[string]bool{}
    if w[3] != "-" {
        for _, text := range strings.Split(w[3], ",") {
            fields := strings.Split(text, "-")
            a, ok := leftID[fields[0]]
            if !ok {
                return fmt.Errorf("UNKNOWN VERTEX %s", fields[0])
            }
            b, ok := rightID[fields[1]]
            if !ok {
                return fmt.Errorf("UNKNOWN VERTEX %s", fields[1])
            }
            if seen[text] {
                return fmt.Errorf("DUPLICATE PAIR %s", text)
            }
            seen[text] = true
            pairs = append(pairs, [2]int{a, b})
        }
    }
    matesA, matesB := make([]int, len(left)), make([]int, len(right))
    for i := range matesA { matesA[i] = -1 }
    for i := range matesB { matesB[i] = -1 }
    var attempt func(int, []bool) bool
    attempt = func(a int, examined []bool) bool {
        for _, pair := range pairs {
            b := pair[1]
            if pair[0] == a && !examined[b] {
                examined[b] = true
                if matesB[b] < 0 || attempt(matesB[b], examined) {
                    matesA[a], matesB[b] = b, a
                    return true
                }
            }
        }
        return false
    }
    for a := range left { attempt(a, make([]bool, len(right))) }
    markedA, markedB := make([]bool, len(left)), make([]bool, len(right))
    queue := []int{}
    freeA, freeB, cover, hallA, hallB := []string{}, []string{}, []string{}, []string{}, []string{}
    size := 0
    for a := range left {
        if matesA[a] < 0 { markedA[a] = true; queue = append(queue, a); freeA = append(freeA, left[a]) } else { size++ }
    }
    for at := 0; at < len(queue); at++ {
        a := queue[at]
        for _, pair := range pairs {
            b := pair[1]
            if pair[0] == a && b != matesA[a] && !markedB[b] {
                markedB[b] = true
                if matesB[b] >= 0 && !markedA[matesB[b]] { markedA[matesB[b]] = true; queue = append(queue, matesB[b]) }
            }
        }
    }
    for a, name := range left { if markedA[a] { hallA = append(hallA, name) } else { cover = append(cover, name) } }
    for b, name := range right {
        if matesB[b] < 0 { freeB = append(freeB, name) }
        if markedB[b] { cover = append(cover, name); hallB = append(hallB, name) }
    }
    fmt.Fprintf(n.out, "MATCH size=%d left=%d right=%d\n", size, len(left), len(right))
    for a, b := range matesA { if b >= 0 { fmt.Fprintf(n.out, "PAIR %s %s\n", left[a], right[b]) } }
    joined := func(values []string) string { if len(values) == 0 { return "-" }; return strings.Join(values, ",") }
    fmt.Fprintf(n.out, "FREE %s %s\n", joined(freeA), joined(freeB))
    fmt.Fprintf(n.out, "COVER size=%d", len(cover))
    for _, name := range cover { fmt.Fprint(n.out, " " + name) }
    fmt.Fprintln(n.out)
    if len(freeA) > 0 { fmt.Fprintf(n.out, "HALL %s %s\n", joined(hallA), joined(hallB)) }
    return nil
}

func (n *network) assignment(w []string) error {
    size := number(w[2])
    if size < 1 || size > 8 { return fmt.Errorf("BAD SIZE") }
    if len(w) - 3 != size * size { return fmt.Errorf("BAD LENGTH") }
    mapping, best := make([]int, size), []int(nil)
    used, optimum, count := make([]bool, size), 0, 0
    var search func(int, int)
    search = func(row, total int) {
        if row == size {
            better := best == nil || w[1] == "MIN" && total < optimum || w[1] == "MAX" && total > optimum
            if better { optimum, count, best = total, 0, append([]int{}, mapping...) }
            if total == optimum { count++ }
            return
        }
        for column := 0; column < size; column++ {
            text := w[3 + row * size + column]
            if !used[column] && text != "x" { mapping[row], used[column] = column, true; search(row + 1, total + number(text)); used[column] = false }
        }
    }
    search(0, 0)
    if best == nil { fmt.Fprintf(n.out, "ASSIGN %s n=%d infeasible\n", w[1], size); return nil }
    fmt.Fprintf(n.out, "ASSIGN %s n=%d total=%d optimal=%d\n", w[1], size, optimum, count)
    for row, column := range best { fmt.Fprintf(n.out, "MATE %d %d %s\n", row + 1, column + 1, w[3 + row * size + column]) }
    return nil
}

func (n *network) command(w []string) error {
    cmd := w[0]
    switch cmd {
    case "NODE":
        seen := map[string]bool{}
        for _, name := range n.names { seen[name] = true }
        for _, name := range w[1:] { if seen[name] { return fmt.Errorf("DUPLICATE NODE %s", name) }; seen[name] = true }
        if len(n.names) + len(w) - 1 > 20 { return fmt.Errorf("TOO MANY NODES") }
        n.names = append(n.names, w[1:]...)
        n.demands = append(n.demands, make([]int, len(w) - 1)...)
        fmt.Fprintf(n.out, "NODE added=%d total=%d\n", len(w) - 1, len(n.names))
    case "EDGE":
        a, err := n.vertex(w[1]); if err != nil { return err }
        b, err := n.vertex(w[2]); if err != nil { return err }
        if a == b { return fmt.Errorf("SELF LOOP") }
        if len(n.edges) == 60 { return fmt.Errorf("TOO MANY EDGES") }
        cost := 0
        if len(w) == 5 { cost = number(w[4]) }
        n.edges = append(n.edges, edge{from: a, to: b, capacity: number(w[3]), cost: cost})
        fmt.Fprintf(n.out, "EDGE %d %s %s cap=%s cost=%d\n", len(n.edges), w[1], w[2], w[3], cost)
    case "LOWER", "CAP", "COST":
        id := number(w[1])
        if id < 1 || id > len(n.edges) { return fmt.Errorf("UNKNOWN EDGE %s", w[1]) }
        e, value := &n.edges[id - 1], number(w[2])
        if cmd == "LOWER" {
            if value > e.capacity { return fmt.Errorf("BAD BOUND") }
            e.lower = value
            fmt.Fprintf(n.out, "LOWER %d low=%d cap=%d\n", id, value, e.capacity)
        } else if cmd == "CAP" {
            if value < e.lower { return fmt.Errorf("BAD BOUND") }
            if value < e.flow { return fmt.Errorf("BELOW FLOW") }
            e.capacity = value
            fmt.Fprintf(n.out, "CAP %d low=%d cap=%d\n", id, e.lower, value)
        } else { e.cost = value; fmt.Fprintf(n.out, "COST %d cost=%d\n", id, value) }
    case "DEMAND":
        at, err := n.vertex(w[1]); if err != nil { return err }
        n.demands[at] = number(w[2])
        total := 0
        for _, demand := range n.demands { total += demand }
        fmt.Fprintf(n.out, "DEMAND %s %s total=%d\n", w[1], w[2], total)
    case "RESET":
        changed := 0
        for i := range n.edges { if n.edges[i].flow != 0 { changed++ }; n.edges[i].flow = 0 }
        n.owner = "none"
        fmt.Fprintf(n.out, "RESET edges=%d\n", changed)
    case "CLEAR":
        fmt.Fprintf(n.out, "CLEAR nodes=%d edges=%d\n", len(n.names), len(n.edges))
        n.graph, n.demands, n.owner = graph{}, nil, "none"
    case "SHOW":
        fmt.Fprintf(n.out, "NETWORK nodes=%d edges=%d\n", len(n.names), len(n.edges))
        if n.owner == "none" { fmt.Fprintln(n.out, "STATE none") } else if n.owner == "circulation" { fmt.Fprintf(n.out, "STATE circulation cost=%d\n", n.totalCost()) } else { fmt.Fprintf(n.out, "STATE flow %s %s value=%d cost=%d\n", n.names[n.source], n.names[n.target], n.value(n.source), n.totalCost()) }
        incoming, outgoing := n.balances()
        for i, name := range n.names { fmt.Fprintf(n.out, "NODE %s demand=%d out=%d in=%d\n", name, n.demands[i], outgoing[i], incoming[i]) }
        for i, e := range n.edges { fmt.Fprintf(n.out, "EDGE %d %s %s cap=%d cost=%d low=%d flow=%d\n", i + 1, n.names[e.from], n.names[e.to], e.capacity, e.cost, e.lower, e.flow) }
    case "AUGMENT", "MAXFLOW", "DINIC", "SCALING", "MINCUT", "SENSITIVITY", "MINCOST", "DISJOINT":
        source, target, err := n.endpointsCheck(w[1], w[2]); if err != nil { return err }
        if cmd == "SENSITIVITY" {
            base := n.copy(); base.maximum(source, target, "MAXFLOW"); value := base.value(source)
            up, down := make([]bool, len(n.edges)), make([]bool, len(n.edges))
            ups, downs := 0, 0
            for i, e := range n.edges {
                changed := n.copy(); changed.edges[i].capacity++; changed.maximum(source, target, "MAXFLOW"); up[i] = changed.value(source) > value
                if up[i] { ups++ }
                if e.capacity > 0 { changed = n.copy(); changed.edges[i].capacity--; changed.maximum(source, target, "MAXFLOW"); down[i] = changed.value(source) < value; if down[i] { downs++ } }
            }
            fmt.Fprintf(n.out, "SENSITIVITY %s %s value=%d up=%d down=%d\n", w[1], w[2], value, ups, downs)
            yes := func(value bool) string { if value { return "yes" }; return "no" }
            for i, e := range n.edges { if up[i] || down[i] { fmt.Fprintf(n.out, "CRITICAL %d %s %s up=%s down=%s\n", i + 1, n.names[e.from], n.names[e.to], yes(up[i]), yes(down[i])) } }
        } else if cmd == "MINCOST" {
            if n.negativeCycle(false) { return fmt.Errorf("NEGATIVE CYCLE") }
            limit := -1
            if w[3] != "MAX" { limit = number(w[3]) }
            working := n.copy(); paths, value, cost := working.minimumCost(source, target, limit)
            if limit >= 0 && value < limit { fmt.Fprintf(n.out, "MINCOST %s %s k=%s infeasible max=%d\n", w[1], w[2], w[3], value); return nil }
            for i := range n.edges { n.edges[i].flow = working.edges[i].flow }
            n.owner, n.source, n.target = "flow", source, target
            fmt.Fprintf(n.out, "MINCOST %s %s k=%s flow=%d cost=%d\n", w[1], w[2], w[3], value, cost)
            for i, pushed := range paths { fmt.Fprintf(n.out, "AUG %d amount=%d cost=%d %s\n", i + 1, pushed.amount, pushed.unit, working.notation(pushed.path, 0)) }
            n.flowList()
        } else if cmd == "DISJOINT" {
            working := &graph{}
            entrances, exits := make([]int, len(n.names)), make([]int, len(n.names))
            for i, name := range n.names {
                entrances[i] = len(working.names); working.names = append(working.names, name); exits[i] = entrances[i]
                if w[3] == "VERTEX" && i != source && i != target { exits[i] = len(working.names); working.names = append(working.names, name) }
            }
            for _, e := range n.edges { capacity := 0; if e.capacity > 0 { capacity = 1 }; working.edges = append(working.edges, edge{from: exits[e.from], to: entrances[e.to], capacity: capacity}) }
            if w[3] == "VERTEX" { for i := range n.names { if i != source && i != target { working.edges = append(working.edges, edge{from: entrances[i], to: exits[i], capacity: 1}) } } }
            working.maximum(entrances[source], entrances[target], "MAXFLOW")
            paths := []piece{}
            for _, part := range working.decompose() { if !part.cycle { paths = append(paths, part) } }
            fmt.Fprintf(n.out, "DISJOINT %s %s %s count=%d\n", w[1], w[2], w[3], len(paths))
            for i, part := range paths { fmt.Fprintf(n.out, "PATH %d %s\n", i + 1, working.notation(part.path, len(n.edges))) }
        } else {
            start := n.start(source, target)
            if cmd == "AUGMENT" {
                pushed := n.augment(source, target, 1)
                if pushed == nil { fmt.Fprintf(n.out, "AUGMENT %s %s value=%d none\n", w[1], w[2], n.value(source)) } else { fmt.Fprintf(n.out, "AUGMENT %s %s value=%d amount=%d %s\n", w[1], w[2], n.value(source), pushed.amount, n.notation(pushed.path, 0)) }
            } else {
                paths, phases := n.maximum(source, target, cmd)
                if cmd == "MINCUT" {
                    reachable, _ := n.bfs(source, 1); a, b, cut := []string{}, []string{}, []int{}
                    for i, name := range n.names { if reachable[i] >= 0 { a = append(a, name) } else { b = append(b, name) } }
                    for i, e := range n.edges { if reachable[e.from] >= 0 && reachable[e.to] < 0 { cut = append(cut, i) } }
                    fmt.Fprintf(n.out, "MINCUT %s %s value=%d edges=%d\nSOURCE %s\nSINK %s\n", w[1], w[2], n.value(source), len(cut), strings.Join(a, " "), strings.Join(b, " "))
                    for _, i := range cut { e := n.edges[i]; fmt.Fprintf(n.out, "CUT %d %s %s %d\n", i + 1, n.names[e.from], n.names[e.to], e.capacity) }
                } else {
                    fmt.Fprintf(n.out, "%s %s %s value=%d start=%d", cmd, w[1], w[2], n.value(source), start)
                    if cmd == "DINIC" { fmt.Fprintf(n.out, " phases=%d", phases) }
                    fmt.Fprintf(n.out, " paths=%d\n", len(paths))
                    for i, pushed := range paths { fmt.Fprintf(n.out, "AUG %d", i + 1); if cmd == "DINIC" { fmt.Fprintf(n.out, " phase=%d", pushed.stage) }; if cmd == "SCALING" { fmt.Fprintf(n.out, " delta=%d", pushed.stage) }; fmt.Fprintf(n.out, " amount=%d %s\n", pushed.amount, n.notation(pushed.path, 0)) }
                    n.flowList()
                }
            }
        }
    case "DECOMPOSE":
        parts := n.decompose(); paths, cycles := 0, 0
        for _, part := range parts { if part.cycle { cycles++ } else { paths++ } }
        fmt.Fprintf(n.out, "DECOMPOSE paths=%d cycles=%d\n", paths, cycles)
        paths, cycles = 0, 0
        for _, part := range parts { kind, id := "PATH", paths + 1; if part.cycle { kind, id, cycles = "CYCLE", cycles + 1, cycles + 1 } else { paths++ }; fmt.Fprintf(n.out, "%s %d amount=%d %s\n", kind, id, part.amount, n.notation(part.path, 0)) }
    case "VERIFY":
        violations := []string{}
        for i, e := range n.edges { if e.flow < e.lower { violations = append(violations, fmt.Sprintf("LOW %d flow=%d low=%d", i + 1, e.flow, e.lower)) } }
        incoming, outgoing := n.balances()
        for i, name := range n.names { if n.owner == "flow" && (i == n.source || i == n.target) { continue }; need := n.demands[i]; if n.owner == "flow" { need = 0 }; if incoming[i] - outgoing[i] != need { violations = append(violations, fmt.Sprintf("BALANCE %s net=%d need=%d", name, incoming[i] - outgoing[i], need)) } }
        if len(violations) == 0 { fmt.Fprintln(n.out, "VERIFY ok") } else { fmt.Fprintf(n.out, "VERIFY violations=%d\n", len(violations)); for _, text := range violations { fmt.Fprintln(n.out, text) } }
    case "CIRCULATION":
        if w[1] == "MINCOST" && n.negativeCycle(true) { return fmt.Errorf("NEGATIVE CYCLE") }
        total := 0
        for _, demand := range n.demands { total += demand }
        if total != 0 { fmt.Fprintf(n.out, "CIRCULATION infeasible unbalanced=%d\n", total); return nil }
        working, residual := n.copy(), append([]int{}, n.demands...)
        source, target := len(n.names), len(n.names) + 1
        working.names = append(working.names, "SS", "TT")
        for i, e := range n.edges { working.edges[i].capacity -= e.lower; residual[e.to] -= e.lower; residual[e.from] += e.lower }
        for i, value := range residual { if value < 0 { working.edges = append(working.edges, edge{from: source, to: i, capacity: -value}) } }
        required, sinkEdges := 0, []int{}
        for i, value := range residual { if value > 0 { sinkEdges = append(sinkEdges, len(working.edges)); working.edges = append(working.edges, edge{from: i, to: target, capacity: value}); required += value } }
        if w[1] == "ANY" { working.maximum(source, target, "MAXFLOW") } else { working.minimumCost(source, target, -1) }
        achieved := 0
        for _, i := range sinkEdges { achieved += working.edges[i].flow }
        if achieved < required {
            fmt.Fprintf(n.out, "CIRCULATION infeasible required=%d achieved=%d\nCUT", required, achieved)
            reached, _ := working.bfs(source, 1)
            for i, name := range n.names { if reached[i] >= 0 { fmt.Fprint(n.out, " " + name) } }
            fmt.Fprintln(n.out)
        } else {
            for i := range n.edges { n.edges[i].flow = n.edges[i].lower + working.edges[i].flow }
            n.owner = "circulation"
            fmt.Fprintf(n.out, "CIRCULATION feasible required=%d cost=%d\n", required, n.totalCost())
            n.flowList()
        }
    case "MATCH":
        return n.matching(w)
    case "ASSIGN":
        return n.assignment(w)
    }
    return nil
}

func main() {
    input, _ := io.ReadAll(os.Stdin)
    lines := strings.Split(string(input), "\n")
    count := number(lines[0])
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    n := &network{owner: "none", out: out}
    for _, text := range lines[1:count + 1] {
        if err := n.command(strings.Split(text, " ")); err != nil {
            fmt.Fprintln(out, "ERROR " + err.Error())
        }
    }
}
