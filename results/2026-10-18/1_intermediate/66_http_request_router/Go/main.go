package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var namePattern = regexp.MustCompile(`^[a-z][a-z0-9_]{0,19}$`)
var rolePattern = regexp.MustCompile(`^[a-z]{1,16}$`)
var tokenPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,32}$`)
var originPattern = regexp.MustCompile(`^https?://[a-z0-9.:-]+$`)
var mediaPartPattern = regexp.MustCompile(`^[a-z0-9.+-]+$`)
var methodPattern = regexp.MustCompile(`^[A-Z]{1,16}$`)
var headerPattern = regexp.MustCompile(`^[A-Za-z0-9-]+$`)
var intPattern = regexp.MustCompile(`^[0-9]{1,9}$`)
var slugPattern = regexp.MustCompile(`^[a-z0-9-]+$`)
var decimalPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
var qPattern = regexp.MustCompile(`^[01](\.[0-9]{0,3})?$`)

func trim(s string) string {
	return strings.Trim(s, " ")
}

func unreserved(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || strings.ContainsRune("-._~", rune(c))
}

func segment(s string) bool {
	if s == "" || s == "." || s == ".." {
		return false
	}
	for i := range s {
		if !unreserved(s[i]) {
			return false
		}
	}
	return true
}

func canonical(s string) bool {
	if s == "/" {
		return true
	}
	if !strings.HasPrefix(s, "/") {
		return false
	}
	for _, p := range strings.Split(s[1:], "/") {
		if !segment(p) {
			return false
		}
	}
	return true
}

func media(s string) bool {
	parts := strings.Split(s, "/")
	return len(parts) == 2 && mediaPartPattern.MatchString(parts[0]) && mediaPartPattern.MatchString(parts[1])
}

func rulePath(s string) (string, bool, bool) {
	if strings.HasSuffix(s, "/*") {
		base := s[:len(s)-2]
		return base, true, base != "/" && canonical(base)
	}
	return s, false, canonical(s)
}

func encode(s string) string {
	var b strings.Builder
	const hex = "0123456789ABCDEF"
	for i := range s {
		c := s[i]
		if unreserved(c) {
			b.WriteByte(c)
		} else {
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&15])
		}
	}
	return b.String()
}

func hex(c byte) int {
	switch {
	case c >= '0' && c <= '9':
		return int(c - '0')
	case c >= 'a' && c <= 'f':
		return int(c-'a') + 10
	case c >= 'A' && c <= 'F':
		return int(c-'A') + 10
	}
	return -1
}

func decode(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			b.WriteByte(byte(hex(s[i+1])*16 + hex(s[i+2])))
			i += 2
		} else {
			b.WriteByte(s[i])
		}
	}
	return b.String()
}

func escapeCheck(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] == '%' {
			if i+2 >= len(s) || hex(s[i+1]) < 0 || hex(s[i+2]) < 0 {
				return false
			}
			n := hex(s[i+1])*16 + hex(s[i+2])
			if n < 32 || n > 126 {
				return false
			}
			i += 2
		}
	}
	return true
}

func normalize(path string) string {
	var b strings.Builder
	for i := 0; i < len(path); i++ {
		if path[i] == '%' {
			c := byte(hex(path[i+1])*16 + hex(path[i+2]))
			if unreserved(c) {
				b.WriteByte(c)
			} else {
				b.WriteString(strings.ToUpper(path[i : i+3]))
			}
			i += 2
		} else {
			b.WriteByte(path[i])
		}
	}
	parts := []string{}
	for _, p := range strings.Split(b.String()[1:], "/") {
		if p == "" || p == "." {
			continue
		}
		if p == ".." {
			if len(parts) > 0 {
				parts = parts[:len(parts)-1]
			}
		} else {
			parts = append(parts, p)
		}
	}
	return "/" + strings.Join(parts, "/")
}

type piece struct {
	kind, name string
}

func parsePattern(pattern string) ([]piece, bool) {
	if pattern == "/" {
		return []piece{}, true
	}
	if !strings.HasPrefix(pattern, "/") {
		return nil, false
	}
	parts := strings.Split(pattern[1:], "/")
	pieces := []piece{}
	names := map[string]bool{}
	for i, p := range parts {
		x := piece{kind: "literal", name: p}
		if segment(p) {
			pieces = append(pieces, x)
			continue
		}
		if len(p) < 3 || p[0] != '{' || p[len(p)-1] != '}' {
			return nil, false
		}
		inside := p[1 : len(p)-1]
		x.kind = "param"
		x.name = inside
		if strings.HasPrefix(inside, "*") {
			x.kind = "wild"
			x.name = inside[1:]
			if i != len(parts)-1 {
				return nil, false
			}
		} else if name, t, ok := strings.Cut(inside, ":"); ok {
			x.name = name
			x.kind = t
			if t != "int" && t != "slug" {
				return nil, false
			}
		}
		if !namePattern.MatchString(x.name) || names[x.name] {
			return nil, false
		}
		names[x.name] = true
		pieces = append(pieces, x)
	}
	return pieces, true
}

type route struct {
	name, pattern, role                 string
	methods                             map[string]bool
	pieces                              []piece
	types                               []string
	number, literals, typed, selections int
	wild                                bool
}

func higher(a, b *route) bool {
	if a.literals != b.literals {
		return a.literals > b.literals
	}
	if a.typed != b.typed {
		return a.typed > b.typed
	}
	if a.wild != b.wild {
		return !a.wild
	}
	return a.number < b.number
}

type redirect struct {
	from, to string
	prefix   bool
	code     int
}

type client struct {
	level, last, allowed, limited int
}

type router struct {
	routes, priority                                    []*route
	byName                                              map[string]*route
	tokens                                              map[string]string
	redirects                                           []redirect
	origins                                             map[string]bool
	capacity, period, errors, requests, urlOK, urlError int
	clients                                             map[string]*client
	statuses                                            map[int]int
}

func newRouter() *router {
	return &router{byName: map[string]*route{}, tokens: map[string]string{}, origins: map[string]bool{}, clients: map[string]*client{}, statuses: map[int]int{}}
}

func (r *router) config(words []string) string {
	cmd, args := words[0], words[1:]
	n := len(args)
	validCount := false
	switch cmd {
	case "ROUTE":
		validCount = n == 3 || n == 5
	case "TOKEN", "LIMIT":
		validCount = n == 2
	case "REDIRECT":
		validCount = n == 3
	case "ORIGIN":
		validCount = n == 1
	case "TYPES":
		validCount = n >= 2
	default:
		return "unknown command " + cmd
	}
	if !validCount {
		return "wrong number of arguments"
	}
	switch cmd {
	case "ROUTE":
		name := args[0]
		if !namePattern.MatchString(name) {
			return "bad route name " + name
		}
		if r.byName[name] != nil {
			return "duplicate route " + name
		}
		methods := map[string]bool{}
		for _, m := range strings.Split(args[1], ",") {
			if !strings.Contains(" GET POST PUT PATCH DELETE ", " "+m+" ") || methods[m] {
				return "bad methods " + args[1]
			}
			methods[m] = true
		}
		pieces, ok := parsePattern(args[2])
		if !ok {
			return "bad pattern " + args[2]
		}
		role := ""
		if n == 5 {
			if args[3] != "ROLE" {
				return "unknown option " + args[3]
			}
			if !rolePattern.MatchString(args[4]) {
				return "bad role " + args[4]
			}
			role = args[4]
			if role == "none" {
				role = ""
			}
		}
		v := &route{name: name, pattern: args[2], role: role, methods: methods, pieces: pieces, number: len(r.routes)}
		for _, p := range pieces {
			switch p.kind {
			case "literal":
				v.literals++
			case "int", "slug":
				v.typed++
			case "wild":
				v.wild = true
			}
		}
		r.routes = append(r.routes, v)
		r.byName[name] = v
	case "TOKEN":
		if !tokenPattern.MatchString(args[0]) {
			return "bad token " + args[0]
		}
		if _, ok := r.tokens[args[0]]; ok {
			return "duplicate token " + args[0]
		}
		if !rolePattern.MatchString(args[1]) {
			return "bad role " + args[1]
		}
		r.tokens[args[0]] = args[1]
	case "REDIRECT":
		from, prefix, ok := rulePath(args[0])
		if !ok {
			return "bad path " + args[0]
		}
		to, toPrefix, ok := rulePath(args[1])
		if !ok {
			return "bad path " + args[1]
		}
		if prefix != toPrefix {
			return "wildcard mismatch"
		}
		if args[2] != "301" && args[2] != "302" && args[2] != "307" && args[2] != "308" {
			return "bad redirect code " + args[2]
		}
		for _, d := range r.redirects {
			if d.from == from && d.prefix == prefix {
				return "duplicate redirect " + args[0]
			}
		}
		code, _ := strconv.Atoi(args[2])
		r.redirects = append(r.redirects, redirect{from, to, prefix, code})
	case "ORIGIN":
		if !originPattern.MatchString(args[0]) {
			return "bad origin " + args[0]
		}
		if r.origins[args[0]] {
			return "duplicate origin " + args[0]
		}
		r.origins[args[0]] = true
	case "LIMIT":
		n, errN := strconv.Atoi(args[0])
		s, errS := strconv.Atoi(args[1])
		if !decimalPattern.MatchString(args[0]) || !decimalPattern.MatchString(args[1]) || errN != nil || errS != nil || n < 1 || n > 100 || s < 1 || s > 3600 {
			return "bad limit"
		}
		if r.capacity > 0 {
			return "duplicate limit"
		}
		r.capacity, r.period = n, s
	case "TYPES":
		v := r.byName[args[0]]
		if v == nil {
			return "unknown route " + args[0]
		}
		if v.types != nil {
			return "duplicate types " + args[0]
		}
		seen := map[string]bool{}
		for _, t := range args[1:] {
			if !media(t) {
				return "bad media type " + t
			}
			if seen[t] {
				return "duplicate media type " + t
			}
			seen[t] = true
		}
		v.types = append([]string{}, args[1:]...)
	}
	return ""
}

func methodList(methods map[string]bool, options bool) []string {
	set := map[string]bool{}
	for m := range methods {
		set[m] = true
	}
	if set["GET"] {
		set["HEAD"] = true
	}
	if options {
		set["OPTIONS"] = true
	}
	out := []string{}
	for m := range set {
		out = append(out, m)
	}
	sort.Strings(out)
	return out
}

func (r *router) table(out *bufio.Writer) {
	limit := "none"
	if r.capacity > 0 {
		limit = fmt.Sprintf("%d/%d", r.capacity, r.period)
	}
	fmt.Fprintf(out, "CONFIG routes=%d tokens=%d redirects=%d origins=%d limit=%s errors=%d\n", len(r.routes), len(r.tokens), len(r.redirects), len(r.origins), limit, r.errors)
	r.priority = append([]*route{}, r.routes...)
	sort.Slice(r.priority, func(i, j int) bool {
		return higher(r.priority[i], r.priority[j])
	})
	for i, v := range r.priority {
		if v.types == nil {
			v.types = []string{"application/json"}
		}
		role := v.role
		if role == "" {
			role = "-"
		}
		fmt.Fprintf(out, "TABLE %d %s %s %s role=%s types=%s\n", i+1, v.name, strings.Join(methodList(v.methods, false), ","), v.pattern, role, strings.Join(v.types, ","))
	}
}

type pair struct {
	name, value string
}

func match(v *route, segments []string) ([]pair, bool) {
	m := len(v.pieces)
	if v.wild {
		m--
	}
	if !v.wild && len(segments) != m || v.wild && len(segments) < m {
		return nil, false
	}
	params := []pair{}
	for j, p := range v.pieces {
		if p.kind == "wild" {
			values := []string{}
			for _, s := range segments[j:] {
				values = append(values, decode(s))
			}
			params = append(params, pair{p.name, strings.Join(values, "/")})
			break
		}
		x := segments[j]
		switch p.kind {
		case "literal":
			if p.name != x {
				return nil, false
			}
		case "int":
			if !intPattern.MatchString(x) {
				return nil, false
			}
			n, _ := strconv.Atoi(x)
			params = append(params, pair{p.name, strconv.Itoa(n)})
		case "slug":
			if !slugPattern.MatchString(x) {
				return nil, false
			}
			params = append(params, pair{p.name, x})
		case "param":
			params = append(params, pair{p.name, decode(x)})
		}
	}
	sort.Slice(params, func(i, j int) bool {
		return params[i].name < params[j].name
	})
	return params, true
}

func negotiate(types []string, accept string, present bool) string {
	if !present {
		return types[0]
	}
	type element struct {
		rangeText           string
		specificity, weight int
	}
	elements := []element{}
	for _, text := range strings.Split(accept, ",") {
		parts := strings.Split(text, ";")
		rangeText := strings.ToLower(trim(parts[0]))
		spec := 3
		if rangeText == "*/*" {
			spec = 1
		} else if strings.HasSuffix(rangeText, "/*") && mediaPartPattern.MatchString(strings.TrimSuffix(rangeText, "/*")) {
			spec = 2
		} else if !media(rangeText) {
			continue
		}
		weight := 1000
		valid := true
		for _, p := range parts[1:] {
			name, v, ok := strings.Cut(trim(p), "=")
			if ok && strings.ToLower(trim(name)) == "q" {
				v = trim(v)
				if !qPattern.MatchString(v) {
					valid = false
				} else {
					whole, fraction, _ := strings.Cut(v, ".")
					if whole == "1" && strings.Trim(fraction, "0") != "" {
						valid = false
					} else {
						fraction += ("000")
						weight, _ = strconv.Atoi(whole + fraction[:3])
					}
				}
				break
			}
		}
		if valid {
			elements = append(elements, element{rangeText, spec, weight})
		}
	}
	selected := ""
	best := 0
	for _, t := range types {
		specificity, weight := 0, 0
		main, _, _ := strings.Cut(t, "/")
		for _, e := range elements {
			fits := e.rangeText == "*/*" || e.rangeText == main+"/*" || e.rangeText == t
			if fits && e.specificity > specificity {
				specificity = e.specificity
				weight = e.weight
			}
		}
		if weight > best {
			best = weight
			selected = t
		}
	}
	return selected
}

func quoted(s string) string {
	return "\"" + strings.NewReplacer("\\", "\\\\", "\"", "\\\"").Replace(s) + "\""
}

var htmlEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;")

func bodyFor(v *route, params []pair, query string, headers map[string]string, selected string) string {
	queries, cookies := []pair{}, []pair{}
	for _, p := range strings.Split(query, "&") {
		if p == "" {
			continue
		}
		name, value, _ := strings.Cut(p, "=")
		queries = append(queries, pair{decode(strings.ReplaceAll(name, "+", " ")), decode(strings.ReplaceAll(value, "+", " "))})
	}
	seen := map[string]bool{}
	if cookie, ok := headers["cookie"]; ok {
		for _, p := range strings.Split(cookie, ";") {
			name, value, ok := strings.Cut(trim(p), "=")
			if ok && name != "" && !seen[name] {
				seen[name] = true
				cookies = append(cookies, pair{name, value})
			}
		}
	}
	sort.Slice(cookies, func(i, j int) bool {
		return cookies[i].name < cookies[j].name
	})
	if selected == "application/json" {
		object := func(ps []pair) string {
			parts := []string{}
			for _, p := range ps {
				parts = append(parts, quoted(p.name)+":"+quoted(p.value))
			}
			return "{" + strings.Join(parts, ",") + "}"
		}
		qp := []string{}
		for _, p := range queries {
			qp = append(qp, "["+quoted(p.name)+","+quoted(p.value)+"]")
		}
		return "{\"route\":" + quoted(v.name) + ",\"params\":" + object(params) + ",\"query\":[" + strings.Join(qp, ",") + "],\"cookies\":" + object(cookies) + "}"
	}
	if selected == "text/html" {
		s := "<dl><dt>route</dt><dd>" + htmlEscaper.Replace(v.name) + "</dd>"
		for i, ps := range [][]pair{params, queries, cookies} {
			label := []string{"param", "query", "cookie"}[i]
			for _, p := range ps {
				s += "<dt>" + label + " " + htmlEscaper.Replace(p.name) + "</dt><dd>" + htmlEscaper.Replace(p.value) + "</dd>"
			}
		}
		return s + "</dl>"
	}
	encoded := func(ps []pair) string {
		if len(ps) == 0 {
			return "-"
		}
		parts := []string{}
		for _, p := range ps {
			parts = append(parts, encode(p.name)+"="+encode(p.value))
		}
		return strings.Join(parts, "&")
	}
	return "route=" + v.name + " params=" + encoded(params) + " query=" + encoded(queries) + " cookies=" + encoded(cookies)
}

func etag(body string) string {
	a, b := 1, 0
	for i := range body {
		a = (a + int(body[i])) % 65521
		b = (b + a) % 65521
	}
	return fmt.Sprintf("\"%04x%04x\"", b, a)
}

type response struct {
	status            int
	headers           map[string]string
	body, contentType string
	head              bool
}

func reply(status int, body string) response {
	return response{status: status, body: body, headers: map[string]string{}}
}

func (r *router) dispatch(method, target string, h map[string]string) response {
	if !strings.Contains(" GET HEAD POST PUT PATCH DELETE OPTIONS ", " "+method+" ") {
		return reply(501, "not implemented: "+method)
	}
	if h["host"] == "" {
		return reply(400, "bad request: missing host")
	}
	effective := method
	if override, ok := h["x-http-method-override"]; ok {
		if method == "POST" && (override == "PUT" || override == "PATCH" || override == "DELETE") {
			effective = override
		} else {
			return reply(400, "bad request: method override")
		}
	}
	if c := h["x-client"]; c != "" {
		t, _ := strconv.Atoi(h["x-time"])
		record := r.clients[c]
		if record == nil {
			record = &client{level: r.capacity * r.period, last: t}
			r.clients[c] = record
		}
		if r.capacity > 0 {
			record.level += (t - record.last) * r.capacity
			if record.level > r.capacity*r.period {
				record.level = r.capacity * r.period
			}
			record.last = t
			if record.level < r.period {
				record.limited++
				w := (r.period - record.level + r.capacity - 1) / r.capacity
				resp := reply(429, "too many requests: client "+c)
				resp.headers["Retry-After"] = strconv.Itoa(w)
				return resp
			}
			record.level -= r.period
		}
		record.allowed++
	}
	path, query, hasQuery := strings.Cut(target, "?")
	suffix := ""
	if hasQuery {
		suffix = "?" + query
	}
	normalized := normalize(path)
	if normalized != path {
		location := normalized + suffix
		resp := reply(308, "redirect to "+location)
		resp.headers["Location"] = location
		return resp
	}
	for _, d := range r.redirects {
		if path == d.from || d.prefix && strings.HasPrefix(path, d.from+"/") {
			location := d.to + path[len(d.from):] + suffix
			resp := reply(d.code, "redirect to "+location)
			resp.headers["Location"] = location
			return resp
		}
	}
	segments := []string{}
	if path != "/" {
		segments = strings.Split(path[1:], "/")
	}
	matching := []*route{}
	values := map[*route][]pair{}
	allowed := map[string]bool{}
	for _, v := range r.priority {
		ps, ok := match(v, segments)
		if ok {
			matching = append(matching, v)
			values[v] = ps
			for m := range v.methods {
				allowed[m] = true
			}
		}
	}
	if len(matching) == 0 {
		return reply(404, "not found: "+path)
	}
	allow := strings.Join(methodList(allowed, true), ", ")
	if effective == "OPTIONS" {
		resp := reply(204, "")
		resp.headers["Allow"] = allow
		return resp
	}
	lookup := effective
	if lookup == "HEAD" {
		lookup = "GET"
	}
	var selected *route
	for _, v := range matching {
		if v.methods[lookup] {
			selected = v
			break
		}
	}
	if selected == nil {
		resp := reply(405, "method not allowed: "+effective)
		resp.headers["Allow"] = allow
		return resp
	}
	selected.selections++
	if selected.role != "" {
		auth, ok := h["authorization"]
		if !ok {
			resp := reply(401, "unauthorized: missing token")
			resp.headers["WWW-Authenticate"] = "Bearer realm=\"api\""
			return resp
		}
		scheme, token, _ := strings.Cut(auth, " ")
		role, exists := r.tokens[token]
		if strings.ToLower(scheme) != "bearer" || !exists {
			resp := reply(401, "unauthorized: invalid token")
			resp.headers["WWW-Authenticate"] = "Bearer realm=\"api\", error=\"invalid_token\""
			return resp
		}
		if role != selected.role && role != "admin" {
			return reply(403, "forbidden: requires role "+selected.role)
		}
	}
	accept, present := h["accept"]
	selectedType := negotiate(selected.types, accept, present)
	var resp response
	if selectedType == "" {
		resp = reply(406, "not acceptable: "+strings.Join(selected.types, ", "))
	} else {
		body := bodyFor(selected, values[selected], query, h, selectedType)
		tag := etag(body)
		conditional := false
		if condition, ok := h["if-none-match"]; ok {
			for _, p := range strings.Split(condition, ",") {
				p = trim(p)
				p = strings.TrimPrefix(p, "W/")
				if p == "*" || p == tag {
					conditional = true
					break
				}
			}
		}
		if conditional {
			if lookup == "GET" {
				resp = reply(304, "")
				resp.headers["ETag"] = tag
			} else {
				resp = reply(412, "precondition failed: "+tag)
			}
		} else {
			resp = reply(200, body)
			resp.contentType = selectedType
			resp.headers["ETag"] = tag
		}
	}
	if len(selected.types) > 1 {
		resp.headers["Vary"] = "Accept"
	}
	return resp
}

func (r *router) request(line string, headerLines []string) response {
	parts := strings.Split(line, " ")
	if len(parts) != 3 || !methodPattern.MatchString(parts[0]) || !strings.HasPrefix(parts[1], "/") || strings.Contains(parts[1], "#") || parts[2] != "HTTP/1.1" {
		return reply(400, "bad request: request line")
	}
	head := parts[0] == "HEAD"
	early := func(body string) response {
		resp := reply(400, body)
		resp.head = head
		return resp
	}
	if !escapeCheck(parts[1]) {
		return early("bad request: percent escape")
	}
	h := map[string]string{}
	for i, l := range headerLines {
		name, v, ok := strings.Cut(l, ":")
		if !ok || !headerPattern.MatchString(name) {
			return early(fmt.Sprintf("bad request: header line %d", i+1))
		}
		name = strings.ToLower(name)
		if _, exists := h[name]; exists {
			return early("bad request: duplicate header " + name)
		}
		h[name] = trim(v)
	}
	resp := r.dispatch(parts[0], parts[1], h)
	resp.head = head
	if origin, ok := h["origin"]; ok && r.origins[origin] {
		resp.headers["Access-Control-Allow-Origin"] = origin
		if resp.status == 204 {
			if _, ok := h["access-control-request-method"]; ok {
				resp.headers["Access-Control-Allow-Methods"] = resp.headers["Allow"]
			}
		}
	}
	return resp
}

var phrases = map[int]string{200: "OK", 204: "No Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 412: "Precondition Failed", 429: "Too Many Requests", 501: "Not Implemented"}
var headerOrder = []string{"Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length"}

func (r *router) printResponse(out *bufio.Writer, resp response) {
	r.requests++
	r.statuses[resp.status]++
	if resp.status != 204 && resp.status != 304 {
		contentType := "text/plain"
		if resp.status == 200 {
			contentType = resp.contentType
		}
		resp.headers["Content-Type"] = contentType
		resp.headers["Content-Length"] = strconv.Itoa(len(resp.body))
	}
	fmt.Fprintf(out, "REQUEST %d\nHTTP/1.1 %d %s\n", r.requests, resp.status, phrases[resp.status])
	for _, name := range headerOrder {
		if v, ok := resp.headers[name]; ok {
			fmt.Fprintf(out, "%s: %s\n", name, v)
		}
	}
	if resp.status != 204 && resp.status != 304 && !resp.head {
		fmt.Fprintln(out, resp.body)
	}
}

func (r *router) urlfor(words []string) (string, string) {
	name := words[1]
	v := r.byName[name]
	if v == nil {
		return "", "unknown route " + name
	}
	parameters := map[string]bool{}
	for _, p := range v.pieces {
		if p.kind != "literal" {
			parameters[p.name] = true
		}
	}
	values := map[string]string{}
	query := []pair{}
	for _, a := range words[2:] {
		key, value, ok := strings.Cut(a, "=")
		if !ok || key == "" {
			return "", "bad argument " + a
		}
		if parameters[key] {
			if _, exists := values[key]; exists {
				return "", "duplicate parameter " + key
			}
			values[key] = value
		} else {
			query = append(query, pair{key, value})
		}
	}
	path := []string{}
	for _, p := range v.pieces {
		if p.kind == "literal" {
			path = append(path, p.name)
			continue
		}
		value, exists := values[p.name]
		if p.kind != "wild" && !exists {
			return "", "missing parameter " + p.name
		}
		valid := true
		switch p.kind {
		case "param":
			valid = value != "" && value != "." && value != ".."
		case "int":
			valid = intPattern.MatchString(value)
		case "slug":
			valid = slugPattern.MatchString(value)
		case "wild":
			if value != "" {
				for _, s := range strings.Split(value, "/") {
					if s == "" || s == "." || s == ".." {
						valid = false
						break
					}
				}
			}
		}
		if !valid {
			return "", "bad value for " + p.name
		}
		if p.kind == "wild" {
			if value != "" {
				for _, s := range strings.Split(value, "/") {
					path = append(path, encode(s))
				}
			}
		} else {
			path = append(path, encode(value))
		}
	}
	url := "/" + strings.Join(path, "/")
	if len(query) > 0 {
		qs := []string{}
		for _, p := range query {
			qs = append(qs, encode(p.name)+"="+encode(p.value))
		}
		url += "?" + strings.Join(qs, "&")
	}
	return "URLFOR " + name + " " + url, ""
}

func (r *router) summary(out *bufio.Writer) {
	fmt.Fprintf(out, "SUMMARY requests=%d urlfor_ok=%d urlfor_error=%d\n", r.requests, r.urlOK, r.urlError)
	codes := []int{}
	for c := range r.statuses {
		codes = append(codes, c)
	}
	sort.Ints(codes)
	for _, c := range codes {
		fmt.Fprintf(out, "STATUS %d %d\n", c, r.statuses[c])
	}
	for _, v := range r.routes {
		fmt.Fprintf(out, "ROUTE %s %d\n", v.name, v.selections)
	}
	names := []string{}
	for c := range r.clients {
		names = append(names, c)
	}
	sort.Strings(names)
	for _, c := range names {
		v := r.clients[c]
		fmt.Fprintf(out, "CLIENT %s allowed=%d limited=%d\n", c, v.allowed, v.limited)
	}
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	lines := strings.Split(string(data), "\n")
	r := newRouter()
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	pos := 0
	for lines[pos] != "REQUESTS" {
		reason := r.config(strings.Split(lines[pos], " "))
		if reason != "" {
			r.errors++
			fmt.Fprintf(out, "CONFIG ERROR %d: %s\n", pos+1, reason)
		}
		pos++
	}
	pos++
	r.table(out)
	for lines[pos] != "END" {
		line := lines[pos]
		pos++
		if strings.HasPrefix(line, "URLFOR ") {
			text, err := r.urlfor(strings.Split(line, " "))
			if err != "" {
				r.urlError++
				fmt.Fprintln(out, "URLFOR ERROR "+err)
			} else {
				r.urlOK++
				fmt.Fprintln(out, text)
			}
		} else {
			headers := []string{}
			for lines[pos] != "" {
				headers = append(headers, lines[pos])
				pos++
			}
			pos++
			r.printResponse(out, r.request(line, headers))
		}
	}
	r.summary(out)
}
