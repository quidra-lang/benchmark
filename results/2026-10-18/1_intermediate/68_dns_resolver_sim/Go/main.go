package main

import (
    "bufio"
    "fmt"
    "io"
    "os"
    "sort"
    "strconv"
    "strings"
)

var types = []string{"A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA"}
var responseKinds = []string{"ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT"}
func indexOf(xs []string, s string) int {
    for i, x := range xs {
        if x == s {
            return i
        }
    }
    return -1
}
func integerWord(s string) bool {
    if len(s) < 1 || len(s) > 9 || len(s) > 1 && s[0] == '0' {
        return false
    }
    for i := range s {
        if s[i] < '0' || s[i] > '9' {
            return false
        }
    }
    return true
}
func number(s string) int {
    n, _ := strconv.Atoi(s)
    return n
}
func nameLabels(name string) []string {
    if name == "." {
        return nil
    }
    return strings.Split(name[:len(name) - 1], ".")
}
func nameLength(name string) int {
    return len(nameLabels(name))
}
func below(name, ancestor string) bool {
    return ancestor == "." || name == ancestor || strings.HasSuffix(name, "." + ancestor)
}
func nameCompare(a, b string) int {
    x, y := nameLabels(a), nameLabels(b)
    for i, j := len(x) - 1, len(y) - 1; i >= 0 && j >= 0; i, j = i - 1, j - 1 {
        if x[i] != y[j] {
            return strings.Compare(x[i], y[j])
        }
    }
    if len(x) < len(y) {
        return -1
    }
    if len(x) > len(y) {
        return 1
    }
    return 0
}
func ancestors(name string) []string {
    out := []string{name}
    for name != "." {
        at := strings.IndexByte(name, '.')
        name = name[at + 1:]
        if name == "" {
            name = "."
        }
        out = append(out, name)
    }
    return out
}
func parseName(word, origin string, wildcard bool) (string, error) {
    if origin != "" && word == "@" {
        return origin, nil
    }
    if word == "." {
        return ".", nil
    }
    absolute := strings.HasSuffix(word, ".")
    text := strings.TrimSuffix(word, ".")
    labels := strings.Split(text, ".")
    for i, label := range labels {
        if wildcard && i == 0 && label == "*" {
            continue
        }
        if len(label) < 1 || len(label) > 63 || label[0] == '-' || label[len(label) - 1] == '-' {
            return "", fmt.Errorf("bad name %s", word)
        }
        for j := range label {
            c := label[j]
            if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-') {
                return "", fmt.Errorf("bad name %s", word)
            }
        }
    }
    result := strings.ToLower(text) + "."
    if origin != "" && origin != "." && !absolute {
        result += origin
    }
    return result, nil
}
func parseIPv4(s string) (uint32, error) {
    fields := strings.Split(s, ".")
    if len(fields) != 4 {
        return 0, fmt.Errorf("bad address %s", s)
    }
    var a uint32
    for _, field := range fields {
        if len(field) > 3 || !integerWord(field) || number(field) > 255 {
            return 0, fmt.Errorf("bad address %s", s)
        }
        a = a * 256 + uint32(number(field))
    }
    return a, nil
}
func ipv4(a uint32) string {
    return fmt.Sprintf("%d.%d.%d.%d", a >> 24, a >> 16 & 255, a >> 8 & 255, a & 255)
}
func parseIPv6(s string) ([8]uint16, error) {
    var result [8]uint16
    invalid := fmt.Errorf("bad address %s", s)
    left, right, compressed := strings.Cut(s, "::")
    parse := func(text string) ([]uint16, bool) {
        if text == "" {
            return []uint16{}, true
        }
        values := []uint16{}
        for _, group := range strings.Split(text, ":") {
            if len(group) < 1 || len(group) > 4 {
                return nil, false
            }
            for i := range group {
                if !strings.ContainsRune("0123456789abcdefABCDEF", rune(group[i])) {
                    return nil, false
                }
            }
            n, _ := strconv.ParseUint(group, 16, 16)
            values = append(values, uint16(n))
        }
        return values, true
    }
    a, ok := parse(left)
    if !ok {
        return result, invalid
    }
    if !compressed {
        if len(a) != 8 {
            return result, invalid
        }
        copy(result[:], a)
        return result, nil
    }
    b, ok := parse(right)
    if !ok || len(a) + len(b) > 7 {
        return result, invalid
    }
    copy(result[:], a)
    copy(result[8 - len(b):], b)
    return result, nil
}
func ipv6(a [8]uint16) string {
    best, length := -1, 0
    for i := 0; i < 8; {
        if a[i] != 0 {
            i++
            continue
        }
        j := i
        for j < 8 && a[j] == 0 {
            j++
        }
        if j - i >= 2 && j - i > length {
            best, length = i, j - i
        }
        i = j
    }
    groups := make([]string, 8)
    for i, n := range a {
        groups[i] = strconv.FormatUint(uint64(n), 16)
    }
    if best < 0 {
        return strings.Join(groups, ":")
    }
    return strings.Join(groups[:best], ":") + "::" + strings.Join(groups[best + length:], ":")
}
func parseTTL(s string) (int, error) {
    invalid := fmt.Errorf("bad ttl %s", s)
    if integerWord(s) {
        n := number(s)
        if n >= 1 && n <= 604800 {
            return n, nil
        }
        return 0, invalid
    }
    units := "wdhms"
    multipliers := []int{604800, 86400, 3600, 60, 1}
    total, previous, pos := 0, -1, 0
    for pos < len(s) {
        start := pos
        for pos < len(s) && s[pos] >= '0' && s[pos] <= '9' {
            pos++
        }
        digits := s[start:pos]
        if len(digits) > 3 || !integerWord(digits) || pos == len(s) {
            return 0, invalid
        }
        unit := strings.IndexByte(units, strings.ToLower(s[pos:pos + 1])[0])
        if unit <= previous {
            return 0, invalid
        }
        total += number(digits) * multipliers[unit]
        previous = unit
        pos++
    }
    if total < 1 || total > 604800 {
        return 0, invalid
    }
    return total, nil
}

type record struct {
    owner string
    ttl int
    kind, data, target string
    address uint32
    address6 [8]uint16
    preference, minimum int
}
func (r record) String() string {
    return fmt.Sprintf("%s %d %s %s", r.owner, r.ttl, r.kind, r.data)
}
func dataCompare(a, b record) int {
    switch a.kind {
    case "A":
        if a.address < b.address {
            return -1
        }
        if a.address > b.address {
            return 1
        }
    case "AAAA":
        for i := 0; i < 8; i++ {
            if a.address6[i] < b.address6[i] {
                return -1
            }
            if a.address6[i] > b.address6[i] {
                return 1
            }
        }
    case "NS", "CNAME", "PTR":
        return nameCompare(a.target, b.target)
    case "MX":
        if a.preference < b.preference {
            return -1
        }
        if a.preference > b.preference {
            return 1
        }
        return nameCompare(a.target, b.target)
    default:
        return strings.Compare(a.data, b.data)
    }
    return 0
}
func sortedRecords(records []record) []record {
    result := append([]record{}, records...)
    sort.Slice(result, func(i, j int) bool {
        a, b := result[i], result[j]
        if c := nameCompare(a.owner, b.owner); c != 0 {
            return c < 0
        }
        if a.kind != b.kind {
            return indexOf(types, a.kind) < indexOf(types, b.kind)
        }
        return dataCompare(a, b) < 0
    })
    return result
}
type zone struct {
    origin string
    server uint32
    line int
    records []record
}
func (z *zone) recordsAt(owner, kind string) []record {
    out := []record{}
    for _, r := range z.records {
        if r.owner == owner && (kind == "" || r.kind == kind) {
            out = append(out, r)
        }
    }
    return sortedRecords(out)
}
func (z *zone) exists(name string) bool {
    for _, r := range z.records {
        if below(r.owner, name) {
            return true
        }
    }
    return false
}
func (z *zone) soa() record {
    for _, r := range z.records {
        if r.kind == "SOA" {
            return r
        }
    }
    return record{}
}
type response struct {
    kind, referral string
    answer, authority, additional []record
}
func (r response) description() string {
    if r.kind == "REFERRAL" {
        return "REFERRAL " + r.referral
    }
    if r.kind == "CNAME" {
        return "CNAME " + r.answer[0].target
    }
    return r.kind
}
type cacheKey struct {
    name, kind string
}
type entry struct {
    kind string
    records []record
    expiry int
}
type result struct {
    status string
    answer []record
}
type resolver struct {
    roots []uint32
    zones []*zone
    current *zone
    down map[uint32]bool
    cache map[cacheKey]entry
    settings map[string]int
    stats map[uint32]*[7]int
    resolutions [4]int
    hits, clock int
    out *bufio.Writer
}
func newResolver(out *bufio.Writer) *resolver {
    return &resolver{down:map[uint32]bool{}, cache:map[cacheKey]entry{}, settings:map[string]int{"MINTTL":1, "MAXTTL":86400, "NEGTTL":3600}, stats:map[uint32]*[7]int{}, out:out}
}
func (r *resolver) zoneLine(words []string, line int) error {
    if words[0] == "ROOT" {
        pending := []uint32{}
        for _, s := range words[1:] {
            a, err := parseIPv4(s)
            if err != nil {
                return err
            }
            for _, old := range append(append([]uint32{}, r.roots...), pending...) {
                if old == a {
                    return fmt.Errorf("duplicate root %s", s)
                }
            }
            pending = append(pending, a)
        }
        r.roots = append(r.roots, pending...)
        return nil
    }
    if words[0] == "ZONE" {
        r.current = nil
        origin, err := parseName(words[1], "", false)
        if err != nil {
            return err
        }
        server, err := parseIPv4(words[2])
        if err != nil {
            return err
        }
        for _, z := range r.zones {
            if z.origin == origin && z.server == server {
                return fmt.Errorf("duplicate zone %s at %s", origin, words[2])
            }
        }
        z := &zone{origin:origin, server:server, line:line}
        r.zones = append(r.zones, z)
        r.current = z
        return nil
    }
    z := r.current
    if z == nil {
        return fmt.Errorf("no current zone")
    }
    owner, err := parseName(words[0], z.origin, true)
    if err != nil {
        return err
    }
    if !below(owner, z.origin) {
        return fmt.Errorf("out of zone %s", owner)
    }
    ttl, err := parseTTL(words[1])
    if err != nil {
        return err
    }
    kind, fields := words[2], words[3:]
    if indexOf(types, kind) < 0 {
        return fmt.Errorf("bad type %s", kind)
    }
    required := 1
    if kind == "MX" {
        required = 2
    }
    if kind == "SOA" {
        required = 7
    }
    if kind != "TXT" && len(fields) != required {
        return fmt.Errorf("wrong field count")
    }
    rec := record{owner:owner, ttl:ttl, kind:kind}
    switch kind {
    case "A":
        rec.address, err = parseIPv4(fields[0])
        rec.data = ipv4(rec.address)
    case "AAAA":
        rec.address6, err = parseIPv6(fields[0])
        rec.data = ipv6(rec.address6)
    case "NS", "CNAME", "PTR":
        rec.target, err = parseName(fields[0], z.origin, false)
        rec.data = rec.target
    case "MX":
        if !integerWord(fields[0]) || number(fields[0]) > 65535 {
            return fmt.Errorf("bad preference %s", fields[0])
        }
        rec.preference = number(fields[0])
        rec.target, err = parseName(fields[1], z.origin, false)
        rec.data = fmt.Sprintf("%d %s", rec.preference, rec.target)
    case "TXT":
        rec.data = strings.Join(fields, " ")
        if len(rec.data) < 2 || rec.data[0] != '"' || rec.data[len(rec.data) - 1] != '"' || strings.Contains(rec.data[1:len(rec.data) - 1], "\"") {
            return fmt.Errorf("bad text %s", rec.data)
        }
    case "SOA":
        data := append([]string{}, fields...)
        data[0], err = parseName(fields[0], z.origin, false)
        if err != nil {
            return err
        }
        data[1], err = parseName(fields[1], z.origin, false)
        if err != nil {
            return err
        }
        for i := 2; i < 6; i++ {
            if !integerWord(fields[i]) {
                return fmt.Errorf("bad number %s", fields[i])
            }
        }
        if !integerWord(fields[6]) || number(fields[6]) < 1 || number(fields[6]) > 86400 {
            return fmt.Errorf("bad minimum %s", fields[6])
        }
        rec.minimum = number(fields[6])
        rec.data = strings.Join(data, " ")
    }
    if err != nil {
        return err
    }
    if kind == "NS" && strings.HasPrefix(owner, "*.") {
        return fmt.Errorf("ns at wildcard")
    }
    if kind == "SOA" && owner != z.origin {
        return fmt.Errorf("soa not at origin")
    }
    if kind == "SOA" {
        for _, old := range z.records {
            if old.kind == "SOA" {
                return fmt.Errorf("duplicate soa")
            }
        }
    }
    for _, old := range z.records {
        if old.owner == owner && old.kind == kind && old.data == rec.data {
            return fmt.Errorf("duplicate record")
        }
    }
    for _, old := range z.records {
        if old.owner == owner && (kind == "CNAME" || old.kind == "CNAME") {
            return fmt.Errorf("cname conflict %s", owner)
        }
    }
    z.records = append(z.records, rec)
    return nil
}
func (r *resolver) finishZones() {
    kept := []*zone{}
    count := 0
    for _, z := range r.zones {
        if z.soa().kind == "" {
            fmt.Fprintf(r.out, "error line %d: zone %s at %s has no soa\n", z.line, z.origin, ipv4(z.server))
        } else {
            kept = append(kept, z)
            count += len(z.records)
            fmt.Fprintf(r.out, "zone %s at %s records=%d\n", z.origin, ipv4(z.server), len(z.records))
        }
    }
    r.zones = kept
    r.current = nil
    fmt.Fprintf(r.out, "loaded roots=%d zones=%d records=%d\n", len(r.roots), len(r.zones), count)
}
func (r *resolver) known(server uint32) bool {
    for _, z := range r.zones {
        if z.server == server {
            return true
        }
    }
    return false
}
func (r *resolver) authoritative(server uint32, name, kind, cut string) response {
    if r.down[server] || !r.known(server) {
        return response{kind:"TIMEOUT"}
    }
    var z *zone
    for _, candidate := range r.zones {
        if candidate.server == server && below(name, candidate.origin) && (z == nil || nameLength(candidate.origin) > nameLength(z.origin)) {
            z = candidate
        }
    }
    if z == nil || nameLength(z.origin) < nameLength(cut) {
        return response{kind:"LAME"}
    }
    chain := ancestors(name)
    for i := len(chain) - 1; i >= 0; i-- {
        d := chain[i]
        if d == z.origin || !below(d, z.origin) {
            continue
        }
        ns := z.recordsAt(d, "NS")
        if len(ns) > 0 {
            additional := []record{}
            for _, n := range ns {
                additional = append(additional, z.recordsAt(n.target, "A")...)
            }
            return response{kind:"REFERRAL", referral:d, authority:ns, additional:additional}
        }
    }
    records := z.recordsAt(name, "")
    if len(records) == 0 {
        if z.exists(name) {
            return response{kind:"NODATA", authority:[]record{z.soa()}}
        }
        wildcard := ""
        for _, ancestor := range chain[1:] {
            if z.exists(ancestor) {
                wildcard = "*."
                if ancestor != "." {
                    wildcard += ancestor
                }
                break
            }
        }
        records = z.recordsAt(wildcard, "")
        if len(records) == 0 {
            return response{kind:"NXDOMAIN", authority:[]record{z.soa()}}
        }
    }
    answers := []record{}
    for _, rec := range records {
        if rec.kind == kind {
            rec.owner = name
            answers = append(answers, rec)
        }
    }
    if len(answers) > 0 {
        return response{kind:"ANSWER", answer:sortedRecords(answers)}
    }
    if kind != "CNAME" {
        for _, rec := range records {
            if rec.kind == "CNAME" {
                rec.owner = name
                return response{kind:"CNAME", answer:[]record{rec}}
            }
        }
    }
    return response{kind:"NODATA", authority:[]record{z.soa()}}
}
func (r *resolver) ask(server uint32, name, kind, cut string) response {
    answer := r.authoritative(server, name, kind, cut)
    if r.stats[server] == nil {
        r.stats[server] = &[7]int{}
    }
    r.stats[server][indexOf(responseKinds, answer.kind)]++
    return answer
}
func (r *resolver) trace(depth int, format string, args ...any) {
    fmt.Fprint(r.out, strings.Repeat(" ", 2 * (depth + 1)))
    fmt.Fprintf(r.out, format + "\n", args...)
}
func (r *resolver) store(records []record) int {
    ttl := records[0].ttl
    for _, rec := range records {
        if rec.ttl < ttl {
            ttl = rec.ttl
        }
    }
    if ttl < r.settings["MINTTL"] {
        ttl = r.settings["MINTTL"]
    }
    if ttl > r.settings["MAXTTL"] {
        ttl = r.settings["MAXTTL"]
    }
    first := records[0]
    r.cache[cacheKey{first.owner, first.kind}] = entry{kind:"POS", records:sortedRecords(records), expiry:r.clock + ttl}
    return ttl
}
func withTTL(records []record, ttl int) []record {
    out := append([]record{}, records...)
    for i := range out {
        out[i].ttl = ttl
    }
    return out
}
func (r *resolver) queryServers(name, kind, cut string, names []string, roots bool, depth int, resolving []cacheKey) *response {
    query := func(a uint32) *response {
        response := r.ask(a, name, kind, cut)
        r.trace(depth, "ASK %s %s %s -> %s", ipv4(a), name, kind, response.description())
        if response.kind == "LAME" || response.kind == "TIMEOUT" {
            return nil
        }
        return &response
    }
    if roots {
        for _, a := range r.roots {
            if answer := query(a); answer != nil {
                return answer
            }
        }
        return nil
    }
    names = append([]string{}, names...)
    sort.Slice(names, func(i, j int) bool {
        return nameCompare(names[i], names[j]) < 0
    })
    for _, host := range names {
        addresses := map[uint32]bool{}
        key := cacheKey{host, "A"}
        if cached, ok := r.cache[key]; ok && cached.kind == "POS" {
            for _, rec := range cached.records {
                addresses[rec.address] = true
            }
        } else {
            loop := false
            for _, pair := range resolving {
                if pair == key {
                    loop = true
                    break
                }
            }
            if loop {
                r.trace(depth, "GLUELESS %s -> LOOP", host)
            } else {
                r.trace(depth, "GLUELESS %s", host)
                answer := r.resolve(host, "A", depth + 1, resolving)
                if answer.status == "NOERROR" {
                    for _, rec := range answer.answer {
                        if rec.kind == "A" {
                            addresses[rec.address] = true
                        }
                    }
                }
            }
        }
        ordered := []uint32{}
        for a := range addresses {
            ordered = append(ordered, a)
        }
        sort.Slice(ordered, func(i, j int) bool {
            return ordered[i] < ordered[j]
        })
        for _, a := range ordered {
            if answer := query(a); answer != nil {
                return answer
            }
        }
    }
    return nil
}
func (r *resolver) lookup(name, kind string, depth int, resolving []cacheKey) response {
    key := cacheKey{name, kind}
    if cached, ok := r.cache[key]; ok {
        r.hits++
        result := response{kind:cached.kind}
        if cached.kind == "POS" {
            result.kind = "ANSWER"
            result.answer = withTTL(cached.records, cached.expiry - r.clock)
        }
        r.trace(depth, "CACHE HIT %s %s -> %s", name, kind, result.kind)
        return result
    }
    for k, cached := range r.cache {
        if cached.kind == "NXDOMAIN" && below(name, k.name) {
            r.hits++
            r.trace(depth, "CACHE HIT %s %s -> NXDOMAIN", name, kind)
            return response{kind:"NXDOMAIN"}
        }
    }
    if kind != "CNAME" {
        if cached, ok := r.cache[cacheKey{name, "CNAME"}]; ok && cached.kind == "POS" {
            r.hits++
            records := withTTL(cached.records, cached.expiry - r.clock)
            r.trace(depth, "CACHE HIT %s %s -> CNAME %s", name, kind, records[0].target)
            return response{kind:"CNAME", answer:records}
        }
    }
    cut, names, roots := ".", []string{}, true
    for _, ancestor := range ancestors(name) {
        if cached, ok := r.cache[cacheKey{ancestor, "NS"}]; ok && cached.kind == "POS" {
            cut = ancestor
            roots = false
            for _, rec := range cached.records {
                names = append(names, rec.target)
            }
            r.hits++
            r.trace(depth, "CACHE HIT %s %s -> REFERRAL %s", name, kind, cut)
            break
        }
    }
    for {
        obtained := r.queryServers(name, kind, cut, names, roots, depth, resolving)
        if obtained == nil {
            return response{kind:"SERVFAIL no server for " + cut}
        }
        answer := *obtained
        if answer.kind == "REFERRAL" {
            r.store(answer.authority)
            grouped := map[string][]record{}
            for _, rec := range answer.additional {
                grouped[rec.owner] = append(grouped[rec.owner], rec)
            }
            for _, records := range grouped {
                r.store(records)
            }
            cut, names, roots = answer.referral, nil, false
            for _, rec := range answer.authority {
                names = append(names, rec.target)
            }
        } else if answer.kind == "ANSWER" || answer.kind == "CNAME" {
            answer.answer = withTTL(answer.answer, r.store(answer.answer))
            return answer
        } else {
            soa := answer.authority[0]
            ttl := soa.ttl
            if soa.minimum < ttl {
                ttl = soa.minimum
            }
            if r.settings["NEGTTL"] < ttl {
                ttl = r.settings["NEGTTL"]
            }
            r.cache[key] = entry{kind:answer.kind, expiry:r.clock + ttl}
            return answer
        }
    }
}
func (r *resolver) resolve(name, kind string, depth int, resolving []cacheKey) result {
    resolving = append(append([]cacheKey{}, resolving...), cacheKey{name, kind})
    chain := []record{}
    seen := map[string]bool{name:true}
    current := name
    var result result
    for {
        lookup := r.lookup(current, kind, depth, resolving)
        if lookup.kind == "CNAME" {
            rec := lookup.answer[0]
            chain = append(chain, rec)
            if seen[rec.target] {
                result.status = "SERVFAIL cname loop"
                break
            }
            if len(chain) == 9 {
                result.status = "SERVFAIL cname chain too long"
                break
            }
            seen[rec.target] = true
            current = rec.target
        } else if lookup.kind == "ANSWER" {
            result = resultWith("NOERROR", append(chain, lookup.answer...))
            break
        } else if lookup.kind == "NODATA" || lookup.kind == "NXDOMAIN" {
            result = resultWith(lookup.kind, chain)
            break
        } else {
            result.status = lookup.kind
            break
        }
    }
    statusIndex := indexOf([]string{"NOERROR", "NODATA", "NXDOMAIN"}, result.status)
    if statusIndex < 0 {
        statusIndex = 3
        result.answer = nil
    }
    r.resolutions[statusIndex]++
    return result
}
func resultWith(status string, records []record) result {
    return result{status, records}
}
func (r *resolver) emitResult(answer result) {
    for _, rec := range answer.answer {
        fmt.Fprintln(r.out, "answer " + rec.String())
    }
    fmt.Fprintln(r.out, "status " + answer.status)
}
func (r *resolver) command(words []string) error {
    command := words[0]
    switch command {
    case "RESOLVE", "MX":
        name, err := parseName(words[1], "", true)
        if err != nil {
            return err
        }
        kind := "MX"
        if command == "RESOLVE" {
            kind = words[2]
            if indexOf(types, kind) < 0 {
                return fmt.Errorf("bad type %s", kind)
            }
            fmt.Fprintf(r.out, "resolve %s %s\n", name, kind)
        } else {
            fmt.Fprintln(r.out, "mx " + name)
        }
        answer := r.resolve(name, kind, 0, nil)
        r.emitResult(answer)
        if command == "MX" {
            addressResolution := func(host, prefix string) {
                a := r.resolve(host, "A", 0, nil)
                aaaa := r.resolve(host, "AAAA", 0, nil)
                addresses := []string{}
                for _, result := range []result{a, aaaa} {
                    if result.status == "NOERROR" {
                        for _, rec := range result.answer {
                            if rec.kind == "A" || rec.kind == "AAAA" {
                                addresses = append(addresses, rec.data)
                            }
                        }
                    }
                }
                text := "no address"
                if len(addresses) > 0 {
                    text = strings.Join(addresses, " ")
                }
                fmt.Fprintln(r.out, prefix + " -> " + text)
            }
            if answer.status == "NOERROR" {
                for _, rec := range answer.answer {
                    if rec.kind == "MX" {
                        prefix := fmt.Sprintf("exchange %d %s", rec.preference, rec.target)
                        if rec.target == "." {
                            fmt.Fprintln(r.out, prefix + " -> null")
                        } else {
                            addressResolution(rec.target, prefix)
                        }
                    }
                }
            } else if answer.status == "NODATA" {
                host := name
                for _, rec := range answer.answer {
                    if rec.kind == "CNAME" {
                        host = rec.target
                    }
                }
                addressResolution(host, "implicit " + host)
            }
        }
    case "REVERSE":
        text, name := "", ""
        if strings.Contains(words[1], ":") {
            a, err := parseIPv6(words[1])
            if err != nil {
                return err
            }
            text = ipv6(a)
            digits := ""
            for _, n := range a {
                digits += fmt.Sprintf("%04x", n)
            }
            labels := []string{}
            for i := len(digits) - 1; i >= 0; i-- {
                labels = append(labels, digits[i:i + 1])
            }
            name = strings.Join(labels, ".") + ".ip6.arpa."
        } else {
            a, err := parseIPv4(words[1])
            if err != nil {
                return err
            }
            text = ipv4(a)
            fields := strings.Split(text, ".")
            name = fields[3] + "." + fields[2] + "." + fields[1] + "." + fields[0] + ".in-addr.arpa."
        }
        fmt.Fprintf(r.out, "reverse %s %s\n", text, name)
        r.emitResult(r.resolve(name, "PTR", 0, nil))
    case "QUERY", "DUMP":
        server, err := parseIPv4(words[1])
        if err != nil {
            return err
        }
        name, err := parseName(words[2], "", command == "QUERY")
        if err != nil {
            return err
        }
        if command == "QUERY" {
            kind := words[3]
            if indexOf(types, kind) < 0 {
                return fmt.Errorf("bad type %s", kind)
            }
            answer := r.ask(server, name, kind, ".")
            fmt.Fprintf(r.out, "query %s %s %s -> %s\n", ipv4(server), name, kind, answer.description())
            for _, group := range []struct{
                label string
                records []record
            }{{"answer", answer.answer}, {"authority", answer.authority}, {"additional", answer.additional}} {
                for _, rec := range group.records {
                    fmt.Fprintln(r.out, group.label + " " + rec.String())
                }
            }
        } else {
            if r.down[server] || !r.known(server) {
                fmt.Fprintf(r.out, "dump %s %s -> TIMEOUT\n", ipv4(server), name)
                return nil
            }
            for _, z := range r.zones {
                if z.server == server && z.origin == name {
                    fmt.Fprintf(r.out, "dump %s %s records=%d\n", ipv4(server), name, len(z.records))
                    for _, rec := range sortedRecords(z.records) {
                        fmt.Fprintln(r.out, "  " + rec.String())
                    }
                    return nil
                }
            }
            fmt.Fprintf(r.out, "dump %s %s -> REFUSED\n", ipv4(server), name)
        }
    case "DOWN", "UP":
        server, err := parseIPv4(words[1])
        if err != nil {
            return err
        }
        if command == "DOWN" {
            if r.down[server] {
                return fmt.Errorf("server %s already down", words[1])
            }
            r.down[server] = true
            fmt.Fprintln(r.out, "down " + ipv4(server))
        } else {
            if !r.down[server] {
                return fmt.Errorf("server %s not down", words[1])
            }
            delete(r.down, server)
            fmt.Fprintln(r.out, "up " + ipv4(server))
        }
    case "SET":
        key := words[1]
        if _, ok := r.settings[key]; !ok {
            return fmt.Errorf("bad setting %s", key)
        }
        if !integerWord(words[2]) || number(words[2]) < 1 || number(words[2]) > 604800 {
            return fmt.Errorf("bad value %s", words[2])
        }
        n := number(words[2])
        minimum, maximum := r.settings["MINTTL"], r.settings["MAXTTL"]
        if key == "MINTTL" {
            minimum = n
        }
        if key == "MAXTTL" {
            maximum = n
        }
        if minimum > maximum {
            return fmt.Errorf("minttl above maxttl")
        }
        r.settings[key] = n
        fmt.Fprintf(r.out, "set %s=%d\n", key, n)
    case "TIME":
        if !integerWord(words[1]) || number(words[1]) < 1 || number(words[1]) > 1000000 {
            return fmt.Errorf("bad time %s", words[1])
        }
        r.clock += number(words[1])
        expired := 0
        for key, cached := range r.cache {
            if cached.expiry <= r.clock {
                delete(r.cache, key)
                expired++
            }
        }
        fmt.Fprintf(r.out, "time now=%d expired=%d\n", r.clock, expired)
    case "CACHE", "FLUSH":
        ancestor := "."
        if len(words) == 2 {
            var err error
            ancestor, err = parseName(words[1], "", false)
            if err != nil {
                return err
            }
        }
        keys := []cacheKey{}
        for key := range r.cache {
            if below(key.name, ancestor) {
                keys = append(keys, key)
            }
        }
        sort.Slice(keys, func(i, j int) bool {
            a, b := keys[i], keys[j]
            if c := nameCompare(a.name, b.name); c != 0 {
                return c < 0
            }
            return indexOf(types, a.kind) < indexOf(types, b.kind)
        })
        if command == "FLUSH" {
            for _, key := range keys {
                delete(r.cache, key)
            }
            fmt.Fprintf(r.out, "flush removed=%d\n", len(keys))
        } else {
            fmt.Fprintf(r.out, "cache entries=%d\n", len(keys))
            for _, key := range keys {
                cached := r.cache[key]
                if cached.kind == "POS" {
                    for _, rec := range withTTL(cached.records, cached.expiry - r.clock) {
                        fmt.Fprintln(r.out, "  " + rec.String())
                    }
                } else {
                    fmt.Fprintf(r.out, "  %s %d %s %s\n", key.name, cached.expiry - r.clock, key.kind, cached.kind)
                }
            }
        }
    case "STATS":
        servers, total := []uint32{}, 0
        for server, stats := range r.stats {
            servers = append(servers, server)
            for _, n := range stats {
                total += n
            }
        }
        sort.Slice(servers, func(i, j int) bool {
            return servers[i] < servers[j]
        })
        fmt.Fprintf(r.out, "stats queries=%d hits=%d\n", total, r.hits)
        for _, server := range servers {
            stats := r.stats[server]
            sent := 0
            for _, n := range stats {
                sent += n
            }
            fmt.Fprintf(r.out, "  %s sent=%d", ipv4(server), sent)
            for i, kind := range responseKinds {
                fmt.Fprintf(r.out, " %s=%d", strings.ToLower(kind), stats[i])
            }
            fmt.Fprintln(r.out)
        }
        fmt.Fprintf(r.out, "resolutions noerror=%d nodata=%d nxdomain=%d servfail=%d\n", r.resolutions[0], r.resolutions[1], r.resolutions[2], r.resolutions[3])
    }
    return nil
}
func main() {
    data, _ := io.ReadAll(os.Stdin)
    lines := strings.Split(string(data), "\n")
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    r := newResolver(out)
    position := 0
    for lines[position] != "END ZONES" {
        if err := r.zoneLine(strings.Split(lines[position], " "), position + 1); err != nil {
            fmt.Fprintf(out, "error line %d: %s\n", position + 1, err)
        }
        position++
    }
    r.finishZones()
    position++
    for lines[position] != "END" {
        if err := r.command(strings.Split(lines[position], " ")); err != nil {
            fmt.Fprintf(out, "error line %d: %s\n", position + 1, err)
        }
        position++
    }
}
