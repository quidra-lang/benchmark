package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Zone struct {
	lo, hi      Value
	has         bool
	nulls, rows int
}
type Page struct {
	kind, method, count, nulls, offset, header, body int
	checksum                                         uint32
	zone                                             Zone
}
type Chunk struct {
	offset, size, nulls int
	methods             []int
	dictionary          bool
	zone                Zone
	pages, dataPages    []*Page
}
type RowGroup struct {
	rows, first int
	chunks      []*Chunk
}
type Store struct {
	data                                     []byte
	version, rows, footerOffset, footerBytes int
	schema                                   []Column
	groups                                   []*RowGroup
}
type Candidate struct {
	data        []byte
	fallback, k int
	dictionary  []Value
	methods     []int
}

func compare(a, b Value, kind string) int {
	if a.null {
		if b.null {
			return 0
		}
		return -1
	}
	if b.null {
		return 1
	}
	if kind == "STRING" {
		return strings.Compare(a.text,
			b.text)
	}
	if a.number < b.number {
		return -1
	}
	if a.number > b.number {
		return 1
	}
	return 0
}
func equal(a, b Value, kind string) bool {
	return a.null == b.null && (a.null || compare(a, b, kind) == 0)
}
func statistics(a []Value, kind string) Zone {
	z := Zone{rows: len(a)}
	for _, v := range a {
		if v.null {
			z.nulls++
			continue
		}
		if !z.has {
			z.lo = v
			z.hi = v
			z.has = true
		} else {
			if compare(v,
				z.lo, kind) < 0 {
				z.lo = v
			}
			if compare(v, z.hi, kind) > 0 {
				z.hi = v
			}
		}
	}
	return z
}
func writeZone(out []byte, z Zone, kind string) []byte {
	if !z.has {
		return append(out, 0)
	}
	out = append(out,
		1)
	out = writeStatValue(out, z.lo, kind)
	return writeStatValue(out, z.hi, kind)
}
func readZone(r *Reader, kind string) Zone {
	z := Zone{}
	if r.byte() != 0 {
		z.has = true
		z.lo = readStatValue(r, kind)
		z.hi = readStatValue(r, kind)
	}
	return z
}
func zoneText(z Zone, kind string) string {
	if !z.has {
		return "stats none"
	}
	return "min " + valueText(z.lo, kind, false) + " max " + valueText(z.hi, kind, false)
}
func makePage(kind, method, count, nulls int, body []byte, zone Zone, column Column) []byte {
	out := []byte{byte(kind),
		byte(method)}
	out = appendULEB(out, int64(count))
	out = appendULEB(out, int64(nulls))
	out = appendULEB(out,
		int64(len(body)))
	out = appendU32(out, adler(body))
	out = writeZone(out, zone, column.kind)
	return append(out,
		body...)
}
func makeCandidate(values []Value, column Column, method int, options Options) Candidate {
	var pages [][]Value
	for start := 0; start < len(values); start += options.page {
		pages = append(pages,
			values[start:min(start+options.page, len(values))])
	}
	candidate := Candidate{}
	if method == 1 {
		seen := map[string]bool{}
		for _, page := range pages {
			proposed := append([]Value(nil), candidate.dictionary...)
			added := map[string]bool{}
			for _, v := range page {
				if v.null {
					continue
				}
				key := dictionaryKey(v, column.kind)
				if !seen[key] && !added[key] {
					added[key] = true
					proposed = append(proposed,
						v)
				}
			}
			if len(encodeValues(proposed, column.kind, 0, nil)) > options.limit {
				break
			}
			candidate.dictionary = proposed
			for key := range added {
				seen[key] = true
			}
			candidate.k++
		}
		if len(candidate.dictionary) == 0 {
			candidate.k = 0
		}
		candidate.fallback = len(pages) - candidate.k
		if candidate.k > 0 {
			body := encodeValues(candidate.dictionary,
				column.kind, 0, nil)
			candidate.data = append(candidate.data, makePage(1, 0, len(candidate.dictionary),
				0, body, Zone{}, column)...)
		}
	}
	methods := map[int]bool{}
	for p, page := range pages {
		encoding := method
		if method == 1 && p >= candidate.k {
			encoding = 0
		}
		methods[encoding] = true
		var body []byte
		if column.nullable {
			levels := make([]int64,
				len(page))
			for i, v := range page {
				if !v.null {
					levels[i] = 1
				}
			}
			encoded := encodeHybrid(levels, 1)
			body = appendU32(body,
				uint32(len(encoded)))
			body = append(body, encoded...)
		}
		var nonnull []Value
		for _, v := range page {
			if !v.null {
				nonnull = append(nonnull,
					v)
			}
		}
		body = append(body, encodeValues(nonnull, column.kind, encoding, candidate.dictionary)...)
		z := statistics(page,
			column.kind)
		candidate.data = append(candidate.data, makePage(0, encoding, len(page), z.nulls, body,
			z, column)...)
	}
	for method := range methods {
		candidate.methods = append(candidate.methods, method)
	}
	sort.Ints(candidate.methods)
	return candidate
}
func buildStore(schema []Column, rows [][]Value, options Options) ([]byte, []string) {
	data := []byte("MPTC")
	var groups []*RowGroup
	report := []string{"row_group,column,encoding,bytes,fallback_pages,chosen"}
	for first := 0; first < len(rows); first += options.rows {
		g := len(groups)
		end := min(first+options.rows,
			len(rows))
		group := &RowGroup{rows: end - first, first: first}
		for c, column := range schema {
			values := make([]Value,
				end-first)
			for i := first; i < end; i++ {
				values[i-first] = rows[i][c]
			}
			all := map[int]Candidate{}
			for _, method := range candidates(column.kind) {
				all[method] = makeCandidate(values, column, method, options)
			}
			chosen := options.methods[c]
			if chosen < 0 {
				chosen = candidates(column.kind)[0]
				for _, method := range candidates(column.kind) {
					if len(all[method].data) < len(all[chosen].data) {
						chosen = method
					}
				}
			}
			if chosen == 1 && all[1].k == 0 {
				chosen = 0
			}
			for _, method := range candidates(column.kind) {
				candidate := all[method]
				selected := "no"
				if method == chosen {
					selected = "yes"
				}
				report = append(report,
					fmt.Sprintf("%d,%s,%s,%d,%d,%s", g, column.name, methodNames[method], len(candidate.data), candidate.fallback,
						selected))
			}
			candidate := all[chosen]
			z := statistics(values, column.kind)
			chunk := &Chunk{offset: len(data),
				size: len(candidate.data), nulls: z.nulls, methods: candidate.methods, dictionary: chosen == 1 && candidate.k > 0,
				zone: z}
			group.chunks = append(group.chunks, chunk)
			data = append(data, candidate.data...)
		}
		groups = append(groups,
			group)
	}
	var footer []byte
	footer = appendULEB(footer, 1)
	footer = appendULEB(footer, int64(len(schema)))
	for _, column := range schema {
		footer = appendULEB(footer, int64(len(column.name)))
		footer = append(footer, []byte(column.name)...)
		kind := 0
		for i, name := range typeNames {
			if name == column.kind {
				kind = i
			}
		}
		nullable := byte(0)
		if column.nullable {
			nullable = 1
		}
		footer = append(footer,
			byte(kind), nullable)
	}
	footer = appendULEB(footer, int64(len(rows)))
	footer = appendULEB(footer, int64(len(groups)))
	for _, group := range groups {
		footer = appendULEB(footer, int64(group.rows))
		for c, chunk := range group.chunks {
			footer = appendULEB(footer,
				int64(chunk.offset))
			footer = appendULEB(footer, int64(chunk.size))
			footer = appendULEB(footer, int64(len(chunk.methods)))
			for _, method := range chunk.methods {
				footer = append(footer, byte(method))
			}
			dictionary := byte(0)
			if chunk.dictionary {
				dictionary = 1
			}
			footer = append(footer,
				dictionary)
			footer = appendULEB(footer, int64((group.rows+options.page-1)/options.page))
			footer = appendULEB(footer,
				int64(chunk.nulls))
			footer = writeZone(footer, chunk.zone, schema[c].kind)
		}
	}
	data = append(data, footer...)
	data = appendU32(data,
		uint32(len(footer)))
	data = append(data, []byte("MPTC")...)
	return data, report
}
func parseStore(data []byte) *Store {
	tail := Reader{data: data, position: len(data) - 8}
	size := int(tail.u32())
	position := len(data) - 8 - size
	r := Reader{data: data,
		position: position}
	store := &Store{data: data, footerOffset: position, footerBytes: size, version: int(r.uleb())}
	columns := int(r.uleb())
	for c := 0; c < columns; c++ {
		name := string(r.take(int(r.uleb())))
		kind := typeNames[int(r.byte())]
		nullable := r.byte() != 0
		store.schema = append(store.schema,
			Column{name, kind, nullable})
	}
	store.rows = int(r.uleb())
	count := int(r.uleb())
	first := 0
	for g := 0; g < count; g++ {
		group := &RowGroup{rows: int(r.uleb()),
			first: first}
		first += group.rows
		for c := 0; c < columns; c++ {
			chunk := &Chunk{offset: int(r.uleb()), size: int(r.uleb())}
			methods := int(r.uleb())
			for i := 0; i < methods; i++ {
				chunk.methods = append(chunk.methods,
					int(r.byte()))
			}
			chunk.dictionary = r.byte() != 0
			r.uleb()
			chunk.nulls = int(r.uleb())
			chunk.zone = readZone(&r,
				store.schema[c].kind)
			chunk.zone.nulls = chunk.nulls
			chunk.zone.rows = group.rows
			group.chunks = append(group.chunks,
				chunk)
		}
		store.groups = append(store.groups, group)
	}
	for _, group := range store.groups {
		for c, chunk := range group.chunks {
			p := Reader{data: data,
				position: chunk.offset}
			for p.position < chunk.offset+chunk.size {
				pageOffset := p.position
				page := &Page{offset: pageOffset, kind: int(p.byte()),
					method: int(p.byte()), count: int(p.uleb()), nulls: int(p.uleb()), body: int(p.uleb()), checksum: p.u32()}
				page.zone = readZone(&p,
					store.schema[c].kind)
				page.zone.nulls = page.nulls
				page.zone.rows = page.count
				page.header = p.position - page.offset
				chunk.pages = append(chunk.pages,
					page)
				if page.kind == 0 {
					chunk.dataPages = append(chunk.dataPages, page)
				}
				p.position += page.body
			}
		}
	}
	return store
}
func (s *Store) body(page *Page) []byte {
	return s.data[page.offset+page.header : page.offset+page.header+page.body]
}
func (s *Store) dictionary(chunk *Chunk, column Column) []Value {
	if !chunk.dictionary {
		return nil
	}
	page := chunk.pages[0]
	r := Reader{data: s.body(page)}
	return decodeValues(&r,
		page.count, column.kind, 0, nil)
}
func (s *Store) decode(page *Page, column Column, dictionary []Value) []Value {
	r := Reader{data: s.body(page)}
	levels := make([]int64,
		page.count)
	for i := range levels {
		levels[i] = 1
	}
	if column.nullable {
		size := int(r.u32())
		reader := Reader{data: r.take(size)}
		levels = decodeHybrid(&reader,
			page.count, 1)
	}
	count := 0
	for _, level := range levels {
		if level == 1 {
			count++
		}
	}
	values := decodeValues(&r,
		count, column.kind, page.method, dictionary)
	out := make([]Value, page.count)
	at := 0
	for i, level := range levels {
		if level == 0 {
			out[i].null = true
		} else {
			out[i] = values[at]
			at++
		}
	}
	return out
}
func methodsText(methods []int) string {
	a := make([]string, len(methods))
	for i, m := range methods {
		a[i] = methodNames[m]
	}
	return strings.Join(a, ",")
}
func columnLines(schema []Column) []string {
	var out []string
	for c, column := range schema {
		nullable := "REQUIRED"
		if column.nullable {
			nullable = "NULLABLE"
		}
		out = append(out,
			fmt.Sprintf("column %d %s %s %s", c, column.name, column.kind, nullable))
	}
	return out
}
func (s *Store) metadata(original [][]Value) []string {
	out := []string{fmt.Sprintf("file bytes %d footer_offset %d footer_bytes %d",
		len(s.data), s.footerOffset, s.footerBytes), fmt.Sprintf("table version %d rows %d columns %d row_groups %d",
		s.version, s.rows, len(s.schema), len(s.groups))}
	out = append(out, columnLines(s.schema)...)
	bytesByColumn,
		pagesByColumn, dictionaries := make([]int, len(s.schema)), make([]int, len(s.schema)), make([]int, len(s.schema))
	methods := make([]map[int]bool,
		len(s.schema))
	for c := range methods {
		methods[c] = map[int]bool{}
	}
	cells, nulls, mismatches, checksums := 0,
		0, 0, 0
	for g, group := range s.groups {
		size := 0
		for _, chunk := range group.chunks {
			size += chunk.size
		}
		out = append(out,
			fmt.Sprintf("row_group %d rows %d first_row %d bytes %d", g, group.rows, group.first, size))
		for c, chunk := range group.chunks {
			column := s.schema[c]
			hasDictionary := "no"
			if chunk.dictionary {
				hasDictionary = "yes"
				dictionaries[c]++
			}
			bytesByColumn[c] += chunk.size
			pagesByColumn[c] += len(chunk.dataPages)
			for _, method := range chunk.methods {
				methods[c][method] = true
			}
			out = append(out, fmt.Sprintf("chunk %d %s offset %d size %d encodings %s dictionary %s pages %d nulls %d %s",
				g, column.name, chunk.offset, chunk.size, methodsText(chunk.methods), hasDictionary, len(chunk.dataPages),
				chunk.nulls, zoneText(chunk.zone, column.kind)))
			dictionary := s.dictionary(chunk, column)
			pageNumber,
				row := 0, group.first
			for _, page := range chunk.pages {
				if adler(s.body(page)) != page.checksum {
					checksums++
				}
				prefix := fmt.Sprintf("page %d %s ",
					g, column.name)
				if page.kind == 1 {
					out = append(out, fmt.Sprintf("%sdict offset %d header %d body %d checksum %s entries %d",
						prefix, page.offset, page.header, page.body, formatChecksum(page.checksum), page.count))
					continue
				}
				out = append(out,
					fmt.Sprintf("%s%d offset %d header %d body %d checksum %s encoding %s values %d nulls %d %s",
						prefix, pageNumber, page.offset, page.header, page.body, formatChecksum(page.checksum), methodNames[page.method],
						page.count, page.nulls, zoneText(page.zone, column.kind)))
				pageNumber++
				values := s.decode(page, column,
					dictionary)
				for _, value := range values {
					cells++
					if value.null {
						nulls++
					}
					if !equal(value, original[row][c],
						column.kind) {
						mismatches++
					}
					row++
				}
			}
		}
	}
	for c, column := range s.schema {
		var encodings []int
		for m := 0; m < 5; m++ {
			if methods[c][m] {
				encodings = append(encodings,
					m)
			}
		}
		out = append(out, fmt.Sprintf("summary %s bytes %d data_pages %d dictionary_pages %d encodings %s",
			column.name, bytesByColumn[c], pagesByColumn[c], dictionaries[c], methodsText(encodings)))
	}
	status := "ok"
	if mismatches != 0 || checksums != 0 {
		status = "failed"
	}
	out = append(out,
		fmt.Sprintf("roundtrip %s cells %d nulls %d mismatches %d checksum_errors %d", status, cells, nulls,
			mismatches, checksums))
	return out
}
func checkQuery(q *Query, schema []Column) string {
	byName := map[string]int{}
	for c, column := range schema {
		byName[column.name] = c
	}
	if q.star {
		for c, column := range schema {
			q.items = append(q.items, Item{column: column.name, index: c})
		}
	}
	leaves := conditionLeaves(q.condition)
	unknown := false
	for i := range q.items {
		item := &q.items[i]
		if item.column == "*" {
			continue
		}
		index,
			ok := byName[item.column]
		if !ok {
			unknown = true
		} else {
			item.index = index
		}
	}
	for _, condition := range leaves {
		index,
			ok := byName[condition.column]
		if !ok {
			unknown = true
		} else {
			condition.index = index
		}
	}
	if q.group != "" {
		index,
			ok := byName[q.group]
		if !ok {
			unknown = true
		} else {
			q.groupIndex = index
		}
	}
	if q.order != "" {
		index, ok := byName[q.order]
		if !ok {
			unknown = true
		} else {
			q.orderIndex = index
		}
	}
	if unknown {
		return "unknown_column"
	}
	for _, condition := range leaves {
		kind := schema[condition.index].kind
		for _, literal := range condition.literals {
			expected := kind
			if kind == "DATE" {
				expected = "STRING"
			}
			if literal.kind != expected {
				return "type_mismatch"
			}
		}
	}
	for _, item := range q.items {
		if (item.op == "SUM" || item.op == "AVG") && schema[item.index].kind != "INT" {
			return "bad_aggregate"
		}
	}
	if q.aggregate {
		for _, item := range q.items {
			if item.op == "" && (q.group == "" || item.column != q.group) {
				return "not_grouped"
			}
		}
		if q.order != "" {
			return "bad_order"
		}
	}
	for _, condition := range leaves {
		if schema[condition.index].kind == "DATE" {
			for i := range condition.literals {
				condition.literals[i].value = Value{number: dateNumber(condition.literals[i].value.text)}
			}
		}
	}
	needed,
		conditions := map[int]bool{}, map[int]bool{}
	for _, item := range q.items {
		if item.column != "*" {
			needed[item.index] = true
		}
	}
	for _, condition := range leaves {
		needed[condition.index] = true
		conditions[condition.index] = true
	}
	if q.groupIndex >= 0 {
		needed[q.groupIndex] = true
	}
	if q.orderIndex >= 0 {
		needed[q.orderIndex] = true
	}
	for c := range schema {
		if needed[c] {
			q.needed = append(q.needed,
				c)
			if conditions[c] {
				q.conditionColumns = append(q.conditionColumns, c)
			} else {
				q.remaining = append(q.remaining,
					c)
			}
		}
	}
	return ""
}
func logical(op string, a, b int) int {
	if op == "NOT" {
		if a == 2 {
			return 2
		}
		return 1 - a
	}
	if op == "AND" {
		if a == 0 || b == 0 {
			return 0
		}
		if a == 2 || b == 2 {
			return 2
		}
		return 1
	}
	if a == 1 || b == 1 {
		return 1
	}
	if a == 2 || b == 2 {
		return 2
	}
	return 0
}
func conditionValue(c *Condition, row []Value, schema []Column) int {
	if c == nil {
		return 1
	}
	if len(c.children) > 0 {
		a := conditionValue(c.children[0],
			row, schema)
		b := 0
		if len(c.children) > 1 {
			b = conditionValue(c.children[1], row, schema)
		}
		return logical(c.op,
			a, b)
	}
	v := row[c.index]
	if c.op == "IS NULL" {
		if v.null {
			return 1
		}
		return 0
	}
	if c.op == "IS NOT NULL" {
		if v.null {
			return 0
		}
		return 1
	}
	if v.null {
		return 2
	}
	kind := schema[c.index].kind
	test := false
	compareLiteral := func(i int) int {
		return compare(v,
			c.literals[i].value, kind)
	}
	switch c.op {
	case "=":
		test = compareLiteral(0) == 0
	case "<>":
		test = compareLiteral(0) != 0
	case "<":
		test = compareLiteral(0) < 0
	case "<=":
		test = compareLiteral(0) <= 0
	case ">":
		test = compareLiteral(0) > 0
	case ">=":
		test = compareLiteral(0) >= 0
	case "BETWEEN":
		test = compareLiteral(0) >= 0 && compareLiteral(1) <= 0
	case "IN":
		for i := range c.literals {
			if compareLiteral(i) == 0 {
				test = true
				break
			}
		}
	}
	if test {
		return 1
	}
	return 0
}
func zoneValues(c *Condition, zones []Zone, schema []Column) int {
	if c == nil {
		return 2
	}
	if len(c.children) > 0 {
		a := zoneValues(c.children[0],
			zones, schema)
		result := 0
		if c.op == "NOT" {
			for v := 0; v < 3; v++ {
				if a>>v&1 != 0 {
					result |= 1 << logical("NOT",
						v, 0)
				}
			}
			return result
		}
		b := zoneValues(c.children[1], zones, schema)
		for x := 0; x < 3; x++ {
			for y := 0; y < 3; y++ {
				if a>>x&1 != 0 && b>>y&1 != 0 {
					result |= 1 << logical(c.op,
						x, y)
				}
			}
		}
		return result
	}
	z := zones[c.index]
	result := 0
	if c.op == "IS NULL" || c.op == "IS NOT NULL" {
		t,
			f := z.nulls > 0, z.nulls < z.rows
		if c.op == "IS NOT NULL" {
			t, f = f, t
		}
		if t {
			result |= 2
		}
		if f {
			result |= 1
		}
		return result
	}
	if z.nulls > 0 {
		result |= 4
	}
	if !z.has {
		return result
	}
	kind := schema[c.index].kind
	lo := func(i int) int {
		return compare(z.lo,
			c.literals[i].value, kind)
	}
	hi := func(i int) int { return compare(z.hi, c.literals[i].value, kind) }
	t,
		f := false, false
	switch c.op {
	case "=":
		t = lo(0) <= 0 && hi(0) >= 0
		f = !(lo(0) == 0 && hi(0) == 0)
	case "<>":
		t = !(lo(0) == 0 && hi(0) == 0)
		f = lo(0) <= 0 && hi(0) >= 0
	case "<":
		t = lo(0) < 0
		f = hi(0) >= 0
	case "<=":
		t = lo(0) <= 0
		f = hi(0) > 0
	case ">":
		t = hi(0) > 0
		f = lo(0) <= 0
	case ">=":
		t = hi(0) >= 0
		f = lo(0) < 0
	case "BETWEEN":
		t = lo(1) <= 0 && hi(0) >= 0 && compare(c.literals[0].value,
			c.literals[1].value, kind) <= 0
		f = lo(0) < 0 || hi(1) > 0
	case "IN":
		matchesSingleton := false
		for i := range c.literals {
			if lo(i) <= 0 && hi(i) >= 0 {
				t = true
			}
			if lo(i) == 0 {
				matchesSingleton = true
			}
		}
		f = !(compare(z.lo,
			z.hi, kind) == 0 && matchesSingleton)
	}
	if t {
		result |= 2
	}
	if f {
		result |= 1
	}
	return result
}

type Row struct {
	number int
	values []Value
}

var scanNames = []string{"row_groups_read", "row_groups_skipped", "pages_read", "pages_skipped", "pages_unneeded",
	"dictionary_pages_read", "bytes_read", "rows_scanned", "rows_matched"}

type Scan struct {
	counts  [9]int
	records []string
	rows    []Row
}

func nullRow(n int) []Value {
	row := make([]Value, n)
	for i := range row {
		row[i].null = true
	}
	return row
}
func (s *Store) scan(q *Query) Scan {
	out := Scan{}
	dictionaries := map[*Chunk][]Value{}
	read := func(chunk *Chunk,
		page *Page, column Column) []Value {
		if page.method == 1 {
			if _, ok := dictionaries[chunk]; !ok {
				dictionaries[chunk] = s.dictionary(chunk,
					column)
				dictPage := chunk.pages[0]
				out.counts[5]++
				out.counts[6] += dictPage.header + dictPage.body
			}
		}
		out.counts[2]++
		out.counts[6] += page.header + page.body
		return s.decode(page,
			column, dictionaries[chunk])
	}
	for _, group := range s.groups {
		zones := make([]Zone, len(s.schema))
		for c, chunk := range group.chunks {
			zones[c] = chunk.zone
		}
		if q.condition != nil && zoneValues(q.condition, zones,
			s.schema)&2 == 0 {
			out.counts[1]++
			out.records = append(out.records, "skipped")
			continue
		}
		out.counts[0]++
		if len(q.needed) == 0 {
			out.counts[7] += group.rows
			for row := 0; row < group.rows; row++ {
				out.rows = append(out.rows,
					Row{group.first + row, nullRow(len(s.schema))})
			}
			out.records = append(out.records, "-")
			continue
		}
		record := ""
		first := group.first
		for p, page := range group.chunks[0].dataPages {
			count := page.count
			for c, chunk := range group.chunks {
				zones[c] = chunk.dataPages[p].zone
			}
			if q.condition != nil && zoneValues(q.condition,
				zones, s.schema)&2 == 0 {
				record += "s"
				out.counts[3] += len(q.needed)
				first += count
				continue
			}
			out.counts[7] += count
			rows := make([][]Value,
				count)
			for i := range rows {
				rows[i] = nullRow(len(s.schema))
			}
			for _, c := range q.conditionColumns {
				values := read(group.chunks[c],
					group.chunks[c].dataPages[p], s.schema[c])
				for i, v := range values {
					rows[i][c] = v
				}
			}
			var selected []int
			for i, row := range rows {
				if conditionValue(q.condition, row, s.schema) == 1 {
					selected = append(selected, i)
				}
			}
			if len(selected) == 0 && len(q.remaining) > 0 {
				record += "u"
				out.counts[4] += len(q.remaining)
			} else {
				record += "r"
				for _, c := range q.remaining {
					values := read(group.chunks[c], group.chunks[c].dataPages[p], s.schema[c])
					for i, v := range values {
						rows[i][c] = v
					}
				}
				for _, i := range selected {
					out.rows = append(out.rows, Row{first + i, rows[i]})
				}
			}
			first += count
		}
		out.records = append(out.records,
			record)
	}
	out.counts[8] = len(out.rows)
	return out
}
func gcd64(a, b int64) int64 {
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return a
}
func valueKey(v Value, kind string) string {
	if v.null {
		return "N"
	}
	return "V" + dictionaryKey(v, kind)
}
func aggregateItem(item Item, rows []Row, key Value, schema []Column) string {
	if item.op == "" {
		return valueText(key,
			schema[item.index].kind, false)
	}
	if item.column == "*" {
		return strconv.Itoa(len(rows))
	}
	kind := schema[item.index].kind
	var values []Value
	distinct := map[string]bool{}
	for _, row := range rows {
		v := row.values[item.index]
		if !v.null {
			values = append(values, v)
			distinct[valueKey(v,
				kind)] = true
		}
	}
	if item.op == "COUNT" {
		if item.distinct {
			return strconv.Itoa(len(distinct))
		}
		return strconv.Itoa(len(values))
	}
	if len(values) == 0 {
		return "NULL"
	}
	switch item.op {
	case "SUM",
		"AVG":
		sum := int64(0)
		for _, v := range values {
			sum += v.number
		}
		if item.op == "SUM" {
			return strconv.FormatInt(sum,
				10)
		}
		n := int64(len(values))
		g := gcd64(sum, n)
		sum /= g
		n /= g
		if n == 1 {
			return strconv.FormatInt(sum, 10)
		}
		return fmt.Sprintf("%d/%d",
			sum, n)
	default:
		best := values[0]
		for _, v := range values[1:] {
			comparison := compare(v, best, kind)
			if item.op == "MIN" && comparison < 0 || item.op == "MAX" && comparison > 0 {
				best = v
			}
		}
		return valueText(best,
			kind, false)
	}
}

type QueryResult struct {
	kind    string
	matched int
	rows    []string
}

func buildResult(q *Query, matched []Row, schema []Column) QueryResult {
	result := QueryResult{kind: "rows",
		matched: len(matched)}
	if !q.aggregate {
		rows := append([]Row(nil), matched...)
		if q.order != "" {
			sort.SliceStable(rows,
				func(i, j int) bool {
					comparison := compare(rows[i].values[q.orderIndex], rows[j].values[q.orderIndex],
						schema[q.orderIndex].kind)
					if q.descending {
						return comparison > 0
					}
					return comparison < 0
				})
		}
		for _, row := range rows {
			var values []string
			for _, item := range q.items {
				values = append(values, valueText(row.values[item.index],
					schema[item.index].kind, false))
			}
			result.rows = append(result.rows, strings.Join(values, ","))
		}
	} else {
		type Group struct {
			key  Value
			rows []Row
		}
		var groups []*Group
		if q.group == "" {
			result.kind = "aggregate"
			groups = []*Group{{rows: matched}}
		} else {
			result.kind = "grouped"
			byKey := map[string]*Group{}
			kind := schema[q.groupIndex].kind
			for _, row := range matched {
				value := row.values[q.groupIndex]
				key := valueKey(value, kind)
				group := byKey[key]
				if group == nil {
					group = &Group{key: value}
					byKey[key] = group
					groups = append(groups,
						group)
				}
				group.rows = append(group.rows, row)
			}
			sort.Slice(groups, func(i, j int) bool {
				return compare(groups[i].key,
					groups[j].key, kind) < 0
			})
		}
		for _, group := range groups {
			var values []string
			for _, item := range q.items {
				values = append(values,
					aggregateItem(item, group.rows, group.key, schema))
			}
			result.rows = append(result.rows, strings.Join(values,
				","))
		}
	}
	if q.limit > 0 && len(result.rows) > q.limit {
		result.rows = result.rows[:q.limit]
	}
	return result
}
func sameResult(a, b QueryResult) bool {
	if a.kind != b.kind || a.matched != b.matched || len(a.rows) != len(b.rows) {
		return false
	}
	for i, row := range a.rows {
		if row != b.rows[i] {
			return false
		}
	}
	return true
}
func scanCounts(counts [9]int) string {
	parts := make([]string, 9)
	for i, name := range scanNames {
		parts[i] = fmt.Sprintf("%s %d",
			name, counts[i])
	}
	return strings.Join(parts, " ")
}
func (s *Store) queries(original [][]Value) ([]string, []string) {
	var results, stats []string
	var total [9]int
	errors,
		checks := 0, 0
	queries := readLines("input/queries.txt")
	for i, text := range queries {
		number := i + 1
		q := parseQuery(text)
		if errorCode := checkQuery(q,
			s.schema); errorCode != "" {
			errors++
			line := fmt.Sprintf("query %d error %s", number, errorCode)
			results = append(results,
				line)
			stats = append(stats, line)
			continue
		}
		scan := s.scan(q)
		result := buildResult(q, scan.rows, s.schema)
		var direct []Row
		for row, values := range original {
			if conditionValue(q.condition, values, s.schema) == 1 {
				direct = append(direct,
					Row{row, values})
			}
		}
		check := "mismatch"
		if sameResult(result, buildResult(q, direct, s.schema)) {
			check = "ok"
			checks++
		}
		results = append(results,
			fmt.Sprintf("query %d %s matched %d output %d", number, result.kind, result.matched, len(result.rows)),
			"columns "+queryHeaders(q))
		results = append(results, result.rows...)
		var names []string
		for _, c := range q.needed {
			names = append(names,
				s.schema[c].name)
		}
		needed := strings.Join(names, ",")
		if needed == "" {
			needed = "-"
		}
		stats = append(stats,
			fmt.Sprintf("query %d columns %s %s check %s", number, needed, scanCounts(scan.counts), check))
		for g, record := range scan.records {
			if record == "skipped" {
				stats = append(stats, fmt.Sprintf("query %d row_group %d skipped",
					number, g))
			} else {
				stats = append(stats, fmt.Sprintf("query %d row_group %d pages %s", number, g, record))
			}
		}
		for j, value := range scan.counts {
			total[j] += value
		}
	}
	stats = append(stats, fmt.Sprintf("total queries %d errors %d %s checks_ok %d",
		len(queries), errors, scanCounts(total), checks))
	return results, stats
}
func (s *Store) recover() ([]string, []string) {
	out := []string{fmt.Sprintf("file bytes %d rows %d columns %d row_groups %d",
		len(s.data), s.rows, len(s.schema), len(s.groups))}
	out = append(out, columnLines(s.schema)...)
	rows := make([][]Value,
		s.rows)
	for i := range rows {
		rows[i] = make([]Value, len(s.schema))
		for c := range rows[i] {
			rows[i][c].unknown = true
		}
	}
	pages,
		damaged, lost, lostCells := 0, 0, 0, 0
	for g, group := range s.groups {
		for c, chunk := range group.chunks {
			column := s.schema[c]
			var dictionary []Value
			dictionaryDamaged := false
			row := group.first
			pageNumber := 0
			for _, page := range chunk.pages {
				pages++
				computed := adler(s.body(page))
				bad := computed != page.checksum
				label := "dict"
				if page.kind == 0 {
					label = strconv.Itoa(pageNumber)
				}
				if bad {
					damaged++
					out = append(out,
						fmt.Sprintf("damaged %d %s %s offset %d stored %s computed %s", g, column.name, label, page.offset,
							formatChecksum(page.checksum), formatChecksum(computed)))
				}
				if page.kind == 1 {
					dictionaryDamaged = bad
					if !bad {
						reader := Reader{data: s.body(page)}
						dictionary = decodeValues(&reader,
							page.count, column.kind, 0, nil)
					}
					continue
				}
				reason := ""
				if bad {
					reason = "checksum"
				} else if page.method == 1 && dictionaryDamaged {
					reason = "dictionary"
				}
				if reason != "" {
					lost++
					lostCells += page.count
					out = append(out,
						fmt.Sprintf("lost %d %s %d rows %d reason %s", g, column.name, pageNumber, page.count, reason))
				} else {
					values := s.decode(page,
						column, dictionary)
					for i, value := range values {
						rows[row+i][c] = value
					}
				}
				row += page.count
				pageNumber++
			}
		}
	}
	out = append(out,
		fmt.Sprintf("summary pages %d damaged %d lost_pages %d lost_cells %d recovered_cells %d", pages,
			damaged, lost, lostCells, s.rows*len(s.schema)-lostCells))
	var names []string
	for _, column := range s.schema {
		names = append(names,
			column.name)
	}
	csv := []string{strings.Join(names, ",")}
	for _, row := range rows {
		values := make([]string,
			len(s.schema))
		for c, column := range s.schema {
			values[c] = valueText(row[c], column.kind, true)
		}
		csv = append(csv,
			strings.Join(values, ","))
	}
	return out, csv
}
func main() {
	schema := readSchema()
	rows := readTable(schema)
	options := readOptions()
	data, encodingReport := buildStore(schema,
		rows, options)
	store := parseStore(data)
	queryResults, queryStats := store.queries(rows)
	recovery, recovered := parseStore(damagedBytes()).recover()
	var hexLines []string
	for at := 0; at < len(data); at += 32 {
		hexLines = append(hexLines,
			hex.EncodeToString(data[at:min(at+32, len(data))]))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("file.hex",
		hexLines)
	writeLines("metadata.txt", store.metadata(rows))
	writeLines("encoding_report.csv", encodingReport)
	writeLines("query_results.txt",
		queryResults)
	writeLines("query_stats.txt", queryStats)
	writeLines("recovery.txt", recovery)
	writeLines("recovered.csv",
		recovered)
}
