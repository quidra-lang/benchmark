package main

import (
	"bufio"
	"errors"
	"fmt"
	"maps"
	"os"
	"slices"
	"strconv"
	"strings"
)

type valueKind string

const (
	stringKind valueKind = "string"
	listKind   valueKind = "list"
	hashKind   valueKind = "hash"
	setKind    valueKind = "set"
	zsetKind   valueKind = "zset"
)

type value interface {
	kind() valueKind
	empty() bool
	clone() value
}
type textValue string
type listValue []string
type hashValue map[string]string
type setValue map[string]struct{}
type zsetValue map[string]int

func (v textValue) kind() valueKind { return stringKind }
func (v listValue) kind() valueKind { return listKind }
func (v hashValue) kind() valueKind { return hashKind }
func (v setValue) kind() valueKind  { return setKind }
func (v zsetValue) kind() valueKind { return zsetKind }
func (v textValue) empty() bool    { return false }
func (v listValue) empty() bool    { return len(v) == 0 }
func (v hashValue) empty() bool    { return len(v) == 0 }
func (v setValue) empty() bool     { return len(v) == 0 }
func (v zsetValue) empty() bool    { return len(v) == 0 }
func (v textValue) clone() value   { return v }
func (v listValue) clone() value   { return slices.Clone(v) }
func (v hashValue) clone() value   { return maps.Clone(v) }
func (v setValue) clone() value    { return maps.Clone(v) }
func (v zsetValue) clone() value   { return maps.Clone(v) }

type expiration struct {
	at  int
	set bool
}
type entry struct {
	value  value
	expiry expiration
}
type database map[string]entry

func cloneDatabase(source database) database {
	copy := make(database, len(source))
	for key, item := range source {
		copy[key] = entry{item.value.clone(), item.expiry}
	}
	return copy
}
func readValue[T value](db database, key string, empty T) (T, error) {
	item, exists := db[key]
	if !exists {
		return empty, nil
	}
	typed, ok := item.value.(T)
	if !ok {
		return empty, errWrongType
	}
	return typed.clone().(T), nil
}

var (
	errWrongType = errors.New("WRONGTYPE Operation against a key holding the wrong kind of value")
	errNotInt    = errors.New("ERR value is not an integer or out of range")
	errOverflow  = errors.New("ERR increment or decrement would overflow")
	errSyntax    = errors.New("ERR syntax error")
	errPositive  = errors.New("ERR value is out of range, must be positive")
	errNoKey     = errors.New("ERR no such key")
)

func parseInteger(text string) (int, bool) {
	if text == "0" {
		return 0, true
	}
	start := 0
	if strings.HasPrefix(text, "-") {
		start = 1
	}
	if len(text)-start < 1 || len(text)-start > 9 || text[start] < '1' || text[start] > '9' {
		return 0, false
	}
	number := 0
	for i := start; i < len(text); i++ {
		if text[i] < '0' || text[i] > '9' {
			return 0, false
		}
		number = number*10 + int(text[i]-'0')
	}
	if start == 1 {
		number = -number
	}
	return number, true
}
func integer(text string) (int, error) {
	number, ok := parseInteger(text)
	if !ok {
		return 0, errNotInt
	}
	return number, nil
}
func increment(old, delta int) (int, error) {
	result := old + delta
	if result < -999999999 || result > 999999999 {
		return 0, errOverflow
	}
	return result, nil
}
func normalize(length, start, stop int) (int, int) {
	if start < 0 {
		start += length
	}
	if stop < 0 {
		stop += length
	}
	start = max(0, start)
	stop = min(length-1, stop)
	if start > stop {
		return 0, 0
	}
	return start, stop + 1
}
func indices(a, b string) (int, int, error) {
	start, err := integer(a)
	if err != nil {
		return 0, 0, err
	}
	stop, err := integer(b)
	return start, stop, err
}
func splitLine(line string) ([]string, bool) {
	var words []string
	for position := 0; position < len(line); {
		if line[position] == ' ' {
			position++
			continue
		}
		if line[position] != '"' {
			start := position
			for position < len(line) && line[position] != ' ' {
				position++
			}
			words = append(words, line[start:position])
			continue
		}
		position++
		var text strings.Builder
		for position < len(line) && line[position] != '"' {
			if line[position] == '\\' {
				position++
				if position == len(line) || (line[position] != '\\' && line[position] != '"') {
					return nil, false
				}
			}
			text.WriteByte(line[position])
			position++
		}
		if position == len(line) {
			return nil, false
		}
		position++
		if position < len(line) && line[position] != ' ' {
			return nil, false
		}
		words = append(words, text.String())
	}
	return words, true
}

type optionalText struct {
	text    string
	present bool
}

const nilReply = "(nil)"

func integerReply(number int) string { return fmt.Sprintf("(integer) %d", number) }
func textReply(text string) string   { return strconv.Quote(text) }
func arrayReply(items []optionalText) string {
	if len(items) == 0 {
		return "(empty array)"
	}
	width := len(strconv.Itoa(len(items)))
	lines := make([]string, len(items))
	for i, item := range items {
		text := nilReply
		if item.present {
			text = textReply(item.text)
		}
		lines[i] = fmt.Sprintf("%*d) %s", width, i+1, text)
	}
	return strings.Join(lines, "\n")
}
func stringArray(items []string) string {
	values := make([]optionalText, len(items))
	for i, text := range items {
		values[i] = optionalText{text, true}
	}
	return arrayReply(values)
}
func sortedKeys[V any](items map[string]V) []string { return slices.Sorted(maps.Keys(items)) }

type partKind int

const (
	literalPart partKind = iota
	anyPart
	starPart
	classPart
)

type patternPart struct {
	kind       partKind
	literal    byte
	characters [128]bool
	negated    bool
}

func parsePattern(text string) ([]patternPart, error) {
	var parts []patternPart
	for i := 0; i < len(text); i++ {
		part := patternPart{}
		switch text[i] {
		case '\\':
			i++
			if i == len(text) {
				return nil, errors.New("ERR invalid pattern")
			}
			part.literal = text[i]
		case '*':
			part.kind = starPart
		case '?':
			part.kind = anyPart
		case '[':
			end := i + 1
			for end < len(text) && text[end] != ']' {
				end++
			}
			if end == len(text) {
				return nil, errors.New("ERR invalid pattern")
			}
			part.kind = classPart
			i++
			if i < end && text[i] == '^' {
				part.negated = true
				i++
			}
			if i == end {
				return nil, errors.New("ERR invalid pattern")
			}
			for i < end {
				first, last := int(text[i]), int(text[i])
				if i+2 < end && text[i+1] == '-' {
					last = int(text[i+2])
					i += 3
				} else {
					i++
				}
				for c := min(first, last); c <= max(first, last); c++ {
					part.characters[c] = true
				}
			}
		default:
			part.literal = text[i]
		}
		parts = append(parts, part)
	}
	return parts, nil
}
func matchesPattern(parts []patternPart, text string) bool {
	previous := make([]bool, len(text)+1)
	previous[0] = true
	for _, part := range parts {
		next := make([]bool, len(previous))
		if part.kind == starPart {
			next[0] = previous[0]
			for i := 1; i < len(next); i++ {
				next[i] = previous[i] || next[i-1]
			}
		} else {
			for i := range len(text) {
				accepts := part.kind == anyPart || (part.kind == literalPart && part.literal == text[i]) ||
					(part.kind == classPart && part.characters[text[i]] != part.negated)
				next[i+1] = previous[i] && accepts
			}
		}
		previous = next
	}
	return previous[len(text)]
}

type bound struct {
	infinity  int
	number    int
	exclusive bool
}

func scoreBound(text string) (bound, error) {
	if text == "-inf" {
		return bound{infinity: -1}, nil
	}
	if text == "+inf" {
		return bound{infinity: 1}, nil
	}
	exclusive := strings.HasPrefix(text, "(")
	if exclusive {
		text = text[1:]
	}
	number, ok := parseInteger(text)
	if !ok {
		return bound{}, errors.New("ERR min or max is not a float")
	}
	return bound{number: number, exclusive: exclusive}, nil
}
func (b bound) accepts(score int, lower bool) bool {
	if b.infinity != 0 {
		return (b.infinity < 0) == lower
	}
	if lower {
		return score > b.number || (!b.exclusive && score == b.number)
	}
	return score < b.number || (!b.exclusive && score == b.number)
}

type group int

const (
	textGroup group = iota
	listGroup
	hashGroup
	setGroup
	zsetGroup
	keyGroup
	controlGroup
)

type commandSpec struct {
	group                    group
	minimum, maximum, parity int
}

var commands = buildCommands()

func buildCommands() map[string]commandSpec {
	result := make(map[string]commandSpec)
	add := func(group group, names string, minimum, maximum, parity int) {
		for _, name := range strings.Fields(names) {
			result[name] = commandSpec{group, minimum, maximum, parity}
		}
	}
	add(textGroup, "SET", 2, -1, -1)
	add(textGroup, "GET INCR DECR STRLEN", 1, 1, -1)
	add(textGroup, "MSET", 2, -1, 0)
	add(textGroup, "MGET", 1, -1, -1)
	add(textGroup, "INCRBY DECRBY APPEND", 2, 2, -1)
	add(textGroup, "GETRANGE", 3, 3, -1)
	add(listGroup, "LPUSH RPUSH", 2, -1, -1)
	add(listGroup, "LPOP RPOP", 1, 2, -1)
	add(listGroup, "LRANGE LSET LREM LTRIM", 3, 3, -1)
	add(listGroup, "LLEN", 1, 1, -1)
	add(listGroup, "LINDEX", 2, 2, -1)
	add(listGroup, "LINSERT", 4, 4, -1)
	add(hashGroup, "HSET", 3, -1, 1)
	add(hashGroup, "HGET HEXISTS", 2, 2, -1)
	add(hashGroup, "HDEL", 2, -1, -1)
	add(hashGroup, "HGETALL HLEN HKEYS HVALS", 1, 1, -1)
	add(hashGroup, "HINCRBY", 3, 3, -1)
	add(setGroup, "SADD SREM", 2, -1, -1)
	add(setGroup, "SISMEMBER", 2, 2, -1)
	add(setGroup, "SMEMBERS SCARD", 1, 1, -1)
	add(setGroup, "SINTER SUNION SDIFF", 1, -1, -1)
	add(setGroup, "SINTERSTORE SUNIONSTORE SDIFFSTORE", 2, -1, -1)
	add(zsetGroup, "ZADD", 3, -1, 1)
	add(zsetGroup, "ZSCORE ZRANK", 2, 2, -1)
	add(zsetGroup, "ZINCRBY", 3, 3, -1)
	add(zsetGroup, "ZREM", 2, -1, -1)
	add(zsetGroup, "ZCARD", 1, 1, -1)
	add(zsetGroup, "ZRANGE ZRANGEBYSCORE", 3, 4, -1)
	add(keyGroup, "DEL EXISTS", 1, -1, -1)
	add(keyGroup, "TYPE KEYS TTL PERSIST TICK", 1, 1, -1)
	add(keyGroup, "RENAME RENAMENX", 2, 2, -1)
	add(keyGroup, "EXPIRE", 2, 3, -1)
	add(keyGroup, "TIME DBSIZE FLUSH INFO", 0, 0, -1)
	add(controlGroup, "BEGIN COMMIT ROLLBACK", 0, 0, -1)
	add(controlGroup, "SNAPSHOT RESTORE", 1, 1, -1)
	return result
}

type store struct {
	database  database
	time      int
	stack     []database
	snapshots map[string]database
}

func (s *store) replace(key string, data value, expiry expiration) {
	if data.empty() {
		delete(s.database, key)
	} else {
		s.database[key] = entry{data, expiry}
	}
}
func (s *store) update(key string, data value) { s.replace(key, data, s.database[key].expiry) }
func (s *store) purge() int {
	removed := 0
	for key, item := range s.database {
		if item.expiry.set && item.expiry.at <= s.time {
			delete(s.database, key)
			removed++
		}
	}
	return removed
}
func (s *store) textCommand(command string, a []string) (string, error) {
	key := a[0]
	if command == "SET" {
		options := make(map[string]bool)
		secondsText := ""
		for i := 2; i < len(a); i++ {
			option := strings.ToUpper(a[i])
			if !slices.Contains([]string{"NX", "XX", "EX", "KEEPTTL", "GET"}, option) || options[option] {
				return "", errSyntax
			}
			options[option] = true
			if option == "EX" {
				i++
				if i == len(a) {
					return "", errSyntax
				}
				secondsText = a[i]
			}
		}
		if (options["NX"] && options["XX"]) || (options["EX"] && options["KEEPTTL"]) {
			return "", errSyntax
		}
		expiry := expiration{}
		if options["EX"] {
			seconds, err := integer(secondsText)
			if err != nil {
				return "", err
			}
			if seconds <= 0 {
				return "", errors.New("ERR invalid expire time in 'set' command")
			}
			expiry = expiration{s.time + seconds, true}
		}
		old, exists := s.database[key]
		previous := nilReply
		if options["GET"] {
			text, err := readValue(s.database, key, textValue(""))
			if err != nil {
				return "", err
			}
			if exists {
				previous = textReply(string(text))
			}
		}
		if options["KEEPTTL"] && exists {
			expiry = old.expiry
		}
		changed := !(options["NX"] && exists) && !(options["XX"] && !exists)
		if changed {
			s.replace(key, textValue(a[1]), expiry)
		}
		if options["GET"] {
			return previous, nil
		}
		if changed {
			return "OK", nil
		}
		return nilReply, nil
	}
	if command == "MSET" {
		for i := 0; i < len(a); i += 2 {
			s.replace(a[i], textValue(a[i+1]), expiration{})
		}
		return "OK", nil
	}
	if command == "MGET" {
		items := make([]optionalText, len(a))
		for i, key := range a {
			if text, ok := s.database[key].value.(textValue); ok {
				items[i] = optionalText{string(text), true}
			}
		}
		return arrayReply(items), nil
	}
	if command == "INCR" || command == "DECR" || command == "INCRBY" || command == "DECRBY" {
		delta := 1
		var err error
		if len(a) == 2 {
			delta, err = integer(a[1])
			if err != nil {
				return "", err
			}
		}
		if command == "DECR" || command == "DECRBY" {
			delta = -delta
		}
		text, err := readValue(s.database, key, textValue(""))
		if err != nil {
			return "", err
		}
		old := 0
		if _, exists := s.database[key]; exists {
			old, err = integer(string(text))
			if err != nil {
				return "", err
			}
		}
		result, err := increment(old, delta)
		if err != nil {
			return "", err
		}
		s.update(key, textValue(strconv.Itoa(result)))
		return integerReply(result), nil
	}
	if command == "GETRANGE" {
		start, stop, err := indices(a[1], a[2])
		if err != nil {
			return "", err
		}
		text, err := readValue(s.database, key, textValue(""))
		if err != nil {
			return "", err
		}
		first, end := normalize(len(text), start, stop)
		return textReply(string(text[first:end])), nil
	}
	text, err := readValue(s.database, key, textValue(""))
	if err != nil {
		return "", err
	}
	if command == "GET" {
		if _, exists := s.database[key]; !exists {
			return nilReply, nil
		}
		return textReply(string(text)), nil
	}
	if command == "STRLEN" {
		return integerReply(len(text)), nil
	}
	text += textValue(a[1])
	s.update(key, text)
	return integerReply(len(text)), nil
}

func (s *store) listCommand(command string, a []string) (string, error) {
	key := a[0]
	switch command {
	case "LPOP", "RPOP":
		count := 1
		if len(a) == 2 {
			var ok bool
			count, ok = parseInteger(a[1])
			if !ok || count < 0 {
				return "", errPositive
			}
		}
		list, err := readValue(s.database, key, listValue{})
		if err != nil {
			return "", err
		}
		if _, exists := s.database[key]; !exists {
			return nilReply, nil
		}
		var removed []string
		count = min(count, len(list))
		for range count {
			index := 0
			if command == "RPOP" {
				index = len(list) - 1
			}
			removed = append(removed, list[index])
			list = slices.Delete(list, index, index+1)
		}
		s.update(key, list)
		if len(a) == 1 {
			return textReply(removed[0]), nil
		}
		return stringArray(removed), nil
	case "LRANGE", "LTRIM":
		start, stop, err := indices(a[1], a[2])
		if err != nil {
			return "", err
		}
		list, err := readValue(s.database, key, listValue{})
		if err != nil {
			return "", err
		}
		first, end := normalize(len(list), start, stop)
		kept := slices.Clone(list[first:end])
		if command == "LRANGE" {
			return stringArray(kept), nil
		}
		s.update(key, kept)
		return "OK", nil
	case "LINDEX", "LSET":
		index, err := integer(a[1])
		if err != nil {
			return "", err
		}
		list, err := readValue(s.database, key, listValue{})
		if err != nil {
			return "", err
		}
		if command == "LSET" {
			if _, exists := s.database[key]; !exists {
				return "", errNoKey
			}
		}
		if index < 0 {
			index += len(list)
		}
		inside := index >= 0 && index < len(list)
		if command == "LINDEX" {
			if !inside {
				return nilReply, nil
			}
			return textReply(list[index]), nil
		}
		if !inside {
			return "", errors.New("ERR index out of range")
		}
		list[index] = a[2]
		s.update(key, list)
		return "OK", nil
	case "LREM":
		count, err := integer(a[1])
		if err != nil {
			return "", err
		}
		list, err := readValue(s.database, key, listValue{})
		if err != nil {
			return "", err
		}
		limit := count
		if count < 0 {
			limit = -count
			slices.Reverse(list)
		}
		if count == 0 {
			limit = len(list)
		}
		kept, removed := list[:0], 0
		for _, element := range list {
			if element == a[2] && removed < limit {
				removed++
			} else {
				kept = append(kept, element)
			}
		}
		if count < 0 {
			slices.Reverse(kept)
		}
		s.update(key, kept)
		return integerReply(removed), nil
	case "LINSERT":
		where := strings.ToUpper(a[1])
		if where != "BEFORE" && where != "AFTER" {
			return "", errSyntax
		}
		list, err := readValue(s.database, key, listValue{})
		if err != nil {
			return "", err
		}
		if _, exists := s.database[key]; !exists {
			return integerReply(0), nil
		}
		index := slices.Index(list, a[2])
		if index < 0 {
			return integerReply(-1), nil
		}
		if where == "AFTER" {
			index++
		}
		list = slices.Insert(list, index, a[3])
		s.update(key, list)
		return integerReply(len(list)), nil
	}
	list, err := readValue(s.database, key, listValue{})
	if err != nil {
		return "", err
	}
	if command == "LLEN" {
		return integerReply(len(list)), nil
	}
	for _, element := range a[1:] {
		if command == "LPUSH" {
			list = slices.Insert(list, 0, element)
		} else {
			list = append(list, element)
		}
	}
	s.update(key, list)
	return integerReply(len(list)), nil
}

func (s *store) hashCommand(command string, a []string) (string, error) {
	key, delta := a[0], 0
	var err error
	if command == "HINCRBY" {
		delta, err = integer(a[2])
		if err != nil {
			return "", err
		}
	}
	fields, err := readValue(s.database, key, hashValue{})
	if err != nil {
		return "", err
	}
	switch command {
	case "HSET":
		added := 0
		for i := 1; i < len(a); i += 2 {
			if _, exists := fields[a[i]]; !exists {
				added++
			}
			fields[a[i]] = a[i+1]
		}
		s.update(key, fields)
		return integerReply(added), nil
	case "HGET":
		if text, exists := fields[a[1]]; exists {
			return textReply(text), nil
		}
		return nilReply, nil
	case "HDEL":
		removed := 0
		for _, field := range a[1:] {
			if _, exists := fields[field]; exists {
				delete(fields, field)
				removed++
			}
		}
		s.update(key, fields)
		return integerReply(removed), nil
	case "HLEN":
		return integerReply(len(fields)), nil
	case "HEXISTS":
		if _, exists := fields[a[1]]; exists {
			return integerReply(1), nil
		}
		return integerReply(0), nil
	case "HINCRBY":
		old := 0
		if text, exists := fields[a[1]]; exists {
			var valid bool
			old, valid = parseInteger(text)
			if !valid {
				return "", errors.New("ERR hash value is not an integer")
			}
		}
		result, err := increment(old, delta)
		if err != nil {
			return "", err
		}
		fields[a[1]] = strconv.Itoa(result)
		s.update(key, fields)
		return integerReply(result), nil
	}
	var output []string
	for _, field := range sortedKeys(fields) {
		if command != "HVALS" {
			output = append(output, field)
		}
		if command != "HKEYS" {
			output = append(output, fields[field])
		}
	}
	return stringArray(output), nil
}

func (s *store) setCommand(command string, a []string) (string, error) {
	storing := strings.HasSuffix(command, "STORE")
	operation := strings.TrimSuffix(command, "STORE")
	if operation == "SINTER" || operation == "SUNION" || operation == "SDIFF" {
		first := 0
		if storing {
			first = 1
		}
		var sources []setValue
		for _, key := range a[first:] {
			members, err := readValue(s.database, key, setValue{})
			if err != nil {
				return "", err
			}
			sources = append(sources, members)
		}
		result := sources[0]
		for _, source := range sources[1:] {
			if operation == "SUNION" {
				maps.Copy(result, source)
			} else {
				for member := range result {
					_, present := source[member]
					if (operation == "SINTER") != present {
						delete(result, member)
					}
				}
			}
		}
		if storing {
			s.replace(a[0], result, expiration{})
			return integerReply(len(result)), nil
		}
		return stringArray(sortedKeys(result)), nil
	}
	members, err := readValue(s.database, a[0], setValue{})
	if err != nil {
		return "", err
	}
	switch command {
	case "SCARD":
		return integerReply(len(members)), nil
	case "SMEMBERS":
		return stringArray(sortedKeys(members)), nil
	case "SISMEMBER":
		if _, present := members[a[1]]; present {
			return integerReply(1), nil
		}
		return integerReply(0), nil
	}
	changed := 0
	for _, member := range a[1:] {
		_, present := members[member]
		if command == "SADD" && !present {
			members[member] = struct{}{}
			changed++
		} else if command == "SREM" && present {
			delete(members, member)
			changed++
		}
	}
	s.update(a[0], members)
	return integerReply(changed), nil
}

type scoredMember struct {
	member string
	score  int
}

func (s *store) zsetCommand(command string, a []string) (string, error) {
	key := a[0]
	if command == "ZADD" {
		var scores []int
		for i := 1; i < len(a); i += 2 {
			score, err := integer(a[i])
			if err != nil {
				return "", err
			}
			scores = append(scores, score)
		}
		members, err := readValue(s.database, key, zsetValue{})
		if err != nil {
			return "", err
		}
		added := 0
		for i, score := range scores {
			member := a[2*i+2]
			if _, present := members[member]; !present {
				added++
			}
			members[member] = score
		}
		s.update(key, members)
		return integerReply(added), nil
	}
	if command == "ZINCRBY" {
		delta, err := integer(a[1])
		if err != nil {
			return "", err
		}
		members, err := readValue(s.database, key, zsetValue{})
		if err != nil {
			return "", err
		}
		result, err := increment(members[a[2]], delta)
		if err != nil {
			return "", err
		}
		members[a[2]] = result
		s.update(key, members)
		return textReply(strconv.Itoa(result)), nil
	}
	byIndex, byScore, withScores := command == "ZRANGE", command == "ZRANGEBYSCORE", len(a) == 4
	start, stop := 0, 0
	minimum, maximum := bound{infinity: -1}, bound{infinity: 1}
	if byIndex || byScore {
		if withScores && !strings.EqualFold(a[3], "WITHSCORES") {
			return "", errSyntax
		}
		var err error
		if byIndex {
			start, stop, err = indices(a[1], a[2])
		} else {
			minimum, err = scoreBound(a[1])
			if err == nil {
				maximum, err = scoreBound(a[2])
			}
		}
		if err != nil {
			return "", err
		}
	}
	members, err := readValue(s.database, key, zsetValue{})
	if err != nil {
		return "", err
	}
	switch command {
	case "ZSCORE":
		if score, exists := members[a[1]]; exists {
			return textReply(strconv.Itoa(score)), nil
		}
		return nilReply, nil
	case "ZREM":
		removed := 0
		for _, member := range a[1:] {
			if _, exists := members[member]; exists {
				delete(members, member)
				removed++
			}
		}
		s.update(key, members)
		return integerReply(removed), nil
	case "ZCARD":
		return integerReply(len(members)), nil
	}
	var ordered []scoredMember
	for member, score := range members {
		ordered = append(ordered, scoredMember{member, score})
	}
	slices.SortFunc(ordered, func(a, b scoredMember) int {
		if a.score != b.score {
			return a.score - b.score
		}
		return strings.Compare(a.member, b.member)
	})
	if command == "ZRANK" {
		for i, item := range ordered {
			if item.member == a[1] {
				return integerReply(i), nil
			}
		}
		return nilReply, nil
	}
	if byIndex {
		first, end := normalize(len(ordered), start, stop)
		ordered = ordered[first:end]
	}
	var output []string
	for _, item := range ordered {
		if byScore && (!minimum.accepts(item.score, true) || !maximum.accepts(item.score, false)) {
			continue
		}
		output = append(output, item.member)
		if withScores {
			output = append(output, strconv.Itoa(item.score))
		}
	}
	return stringArray(output), nil
}

func (s *store) keyCommand(command string, a []string) (string, error) {
	switch command {
	case "DEL", "EXISTS":
		count := 0
		for _, key := range a {
			if _, exists := s.database[key]; exists {
				count++
				if command == "DEL" {
					delete(s.database, key)
				}
			}
		}
		return integerReply(count), nil
	case "KEYS":
		pattern, err := parsePattern(a[0])
		if err != nil {
			return "", err
		}
		var result []string
		for _, key := range sortedKeys(s.database) {
			if matchesPattern(pattern, key) {
				result = append(result, key)
			}
		}
		return stringArray(result), nil
	case "EXPIRE":
		condition := ""
		if len(a) == 3 {
			condition = strings.ToUpper(a[2])
			if !slices.Contains([]string{"NX", "XX", "GT", "LT"}, condition) {
				return "", fmt.Errorf("ERR Unsupported option %s", a[2])
			}
		}
		seconds, err := integer(a[1])
		if err != nil {
			return "", err
		}
		item, exists := s.database[a[0]]
		if !exists {
			return integerReply(0), nil
		}
		expiry, old := s.time+seconds, item.expiry
		rejected := false
		switch condition {
		case "NX":
			rejected = old.set
		case "XX":
			rejected = !old.set
		case "GT":
			rejected = !old.set || expiry <= old.at
		case "LT":
			rejected = old.set && expiry >= old.at
		}
		if rejected {
			return integerReply(0), nil
		}
		if seconds <= 0 {
			delete(s.database, a[0])
		} else {
			item.expiry = expiration{expiry, true}
			s.database[a[0]] = item
		}
		return integerReply(1), nil
	case "TICK":
		ticks, err := integer(a[0])
		if err != nil {
			return "", err
		}
		if ticks <= 0 {
			return "", errPositive
		}
		s.time += ticks
		return integerReply(s.purge()), nil
	case "TIME":
		return integerReply(s.time), nil
	case "DBSIZE":
		return integerReply(len(s.database)), nil
	case "FLUSH":
		clear(s.database)
		return "OK", nil
	case "INFO":
		counts, expires := make(map[valueKind]int), 0
		for _, item := range s.database {
			counts[item.value.kind()]++
			if item.expiry.set {
				expires++
			}
		}
		return fmt.Sprintf("keys=%d,expires=%d,string=%d,list=%d,hash=%d,set=%d,zset=%d,time=%d,depth=%d,snapshots=%d",
			len(s.database), expires, counts[stringKind], counts[listKind], counts[hashKind], counts[setKind], counts[zsetKind],
			s.time, len(s.stack), len(s.snapshots)), nil
	}
	key := a[0]
	item, exists := s.database[key]
	switch command {
	case "TYPE":
		if !exists {
			return "none", nil
		}
		return string(item.value.kind()), nil
	case "TTL":
		if !exists {
			return integerReply(-2), nil
		}
		if !item.expiry.set {
			return integerReply(-1), nil
		}
		return integerReply(item.expiry.at - s.time), nil
	case "PERSIST":
		if !exists || !item.expiry.set {
			return integerReply(0), nil
		}
		item.expiry = expiration{}
		s.database[key] = item
		return integerReply(1), nil
	}
	if !exists {
		return "", errNoKey
	}
	if command == "RENAMENX" {
		if _, exists := s.database[a[1]]; exists {
			return integerReply(0), nil
		}
	}
	if key != a[1] {
		s.database[a[1]] = item
		delete(s.database, key)
	}
	if command == "RENAME" {
		return "OK", nil
	}
	return integerReply(1), nil
}

func (s *store) controlCommand(command string, a []string) (string, error) {
	switch command {
	case "BEGIN":
		s.stack = append(s.stack, cloneDatabase(s.database))
	case "COMMIT", "ROLLBACK":
		if len(s.stack) == 0 {
			return "", errors.New("ERR no transaction")
		}
		last := len(s.stack) - 1
		saved := s.stack[last]
		s.stack[last] = nil
		s.stack = s.stack[:last]
		if command == "ROLLBACK" {
			s.database = saved
			s.purge()
		}
	case "SNAPSHOT":
		s.snapshots[a[0]] = cloneDatabase(s.database)
	case "RESTORE":
		saved, exists := s.snapshots[a[0]]
		if !exists {
			return "", errors.New("ERR no such snapshot")
		}
		s.database = cloneDatabase(saved)
		s.purge()
	}
	return "OK", nil
}

func (s *store) execute(line string) (string, error) {
	words, valid := splitLine(line)
	if !valid {
		return "Invalid argument(s)", nil
	}
	command := strings.ToUpper(words[0])
	spec, known := commands[command]
	if !known {
		return "", fmt.Errorf("ERR unknown command '%s'", words[0])
	}
	a := words[1:]
	if len(a) < spec.minimum || (spec.maximum >= 0 && len(a) > spec.maximum) || (spec.parity >= 0 && len(a)%2 != spec.parity) {
		return "", fmt.Errorf("ERR wrong number of arguments for '%s' command", strings.ToLower(command))
	}
	switch spec.group {
	case textGroup:
		return s.textCommand(command, a)
	case listGroup:
		return s.listCommand(command, a)
	case hashGroup:
		return s.hashCommand(command, a)
	case setGroup:
		return s.setCommand(command, a)
	case zsetGroup:
		return s.zsetCommand(command, a)
	case keyGroup:
		return s.keyCommand(command, a)
	default:
		return s.controlCommand(command, a)
	}
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	if !input.Scan() {
		return
	}
	count, _ := strconv.Atoi(input.Text())
	s := store{database: make(database), snapshots: make(map[string]database)}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for i := 0; i < count && input.Scan(); i++ {
		reply, err := s.execute(input.Text())
		if err != nil {
			fmt.Fprintln(output, "(error) "+err.Error())
		} else {
			fmt.Fprintln(output, reply)
		}
	}
}
