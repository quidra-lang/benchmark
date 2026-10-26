package main

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Event struct {
	Tick         int64
	Status, Meta int
	Data         []byte
}

type Song struct {
	Format   int
	Division int64
	Tracks   [][]*Event
}

type Placed struct {
	Event        *Event
	Track, Order int
}

type Note struct {
	On, Off Placed
	Length  int64
}

type Failure struct {
	Position int
	Reason   string
}

func (e Failure) Error() string {
	return e.Reason
}

var channelNames = []string{"NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND"}
var metaNames = map[int]string{
	0: "SEQUENCE_NUMBER", 1: "TEXT_EVENT", 2: "COPYRIGHT",
	3: "TRACK_NAME", 4: "INSTRUMENT_NAME", 5: "LYRIC",
	6: "MARKER", 7: "CUE_POINT", 32: "CHANNEL_PREFIX",
	47: "END_OF_TRACK", 81: "TEMPO", 84: "SMPTE_OFFSET",
	88: "TIME_SIGNATURE", 89: "KEY_SIGNATURE", 127: "SEQUENCER_SPECIFIC",
}
var keyNames = [][]string{
	{"Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"},
	{"Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"},
}
var writer = bufio.NewWriter(os.Stdout)

func output(s string) {
	fmt.Fprintln(writer, s)
}

func integer(s string) int64 {
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}

func decimal(n int64) string {
	return strconv.FormatInt(n, 10)
}

func noteName(n int) string {
	return []string{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}[n%12] + strconv.Itoa(n/12-1)
}

func be(data []byte) int64 {
	value := int64(0)
	for _, b := range data {
		value = value*256 + int64(b)
	}
	return value
}

func bytesBE(value int64, size int) []byte {
	data := make([]byte, size)
	for i := size - 1; i >= 0; i-- {
		data[i] = byte(value % 256)
		value /= 256
	}
	return data
}

func (e *Event) channel() int {
	return e.Status%16 + 1
}

func (e *Event) kind() string {
	if e.Status < 240 {
		return channelNames[e.Status/16-8]
	}
	if e.Status == 240 {
		return "SYSEX"
	}
	if e.Status == 247 {
		return "SYSEX_ESCAPE"
	}
	if name, ok := metaNames[e.Meta]; ok {
		return name
	}
	return "META"
}

func (e *Event) isMeta(meta int) bool {
	return e.Status == 255 && e.Meta == meta
}

func (e *Event) on() bool {
	return e.Status/16 == 9 && e.Data[1] > 0
}

func (e *Event) off() bool {
	return e.Status/16 == 8 || e.Status/16 == 9 && e.Data[1] == 0
}

func end(tick int64) *Event {
	return &Event{tick, 255, 47, nil}
}

func (s *Song) clone() *Song {
	c := &Song{Format: s.Format, Division: s.Division}
	for _, track := range s.Tracks {
		row := []*Event{}
		for _, e := range track {
			copy := *e
			copy.Data = append([]byte{}, e.Data...)
			row = append(row, &copy)
		}
		c.Tracks = append(c.Tracks, row)
	}
	return c
}

func (s *Song) summary() string {
	count := 0
	for _, track := range s.Tracks {
		count += len(track)
	}
	return fmt.Sprintf("format %d tracks %d division %d events %d", s.Format, len(s.Tracks), s.Division, count)
}

func (s *Song) length() int64 {
	length := int64(0)
	for _, track := range s.Tracks {
		length = max(length, track[len(track)-1].Tick)
	}
	return length
}

func (s *Song) ordered() []Placed {
	all := []Placed{}
	for t, track := range s.Tracks {
		for _, e := range track {
			all = append(all, Placed{e, t, 0})
		}
	}
	sort.SliceStable(all, func(i, j int) bool {
		return all[i].Event.Tick < all[j].Event.Tick
	})
	for i := range all {
		all[i].Order = i
	}
	return all
}

func eventLine(e *Event, track int) string {
	fields := []string{decimal(e.Tick), strconv.Itoa(track), e.kind()}
	data := e.Data
	if e.Status < 240 {
		fields = append(fields, strconv.Itoa(e.channel()))
		switch e.Status / 16 {
		case 8, 9, 10:
			fields = append(fields, noteName(int(data[0])), strconv.Itoa(int(data[1])))
		case 14:
			fields = append(fields, strconv.Itoa(int(data[0])+128*int(data[1])-8192))
		default:
			for _, b := range data {
				fields = append(fields, strconv.Itoa(int(b)))
			}
		}
	} else if e.Status == 255 && e.Meta >= 1 && e.Meta <= 7 {
		fields = append(fields, "\""+string(data)+"\"")
	} else if e.isMeta(0) || e.isMeta(81) {
		fields = append(fields, decimal(be(data)))
	} else if e.isMeta(32) {
		fields = append(fields, strconv.Itoa(int(data[0])+1))
	} else if e.isMeta(47) {
	} else if e.isMeta(84) {
		for _, b := range data {
			fields = append(fields, strconv.Itoa(int(b)))
		}
	} else if e.isMeta(88) {
		fields = append(fields, fmt.Sprintf("%d/%d", data[0], 1<<data[1]), strconv.Itoa(int(data[2])), strconv.Itoa(int(data[3])))
	} else if e.isMeta(89) {
		sf := int(int8(data[0]))
		mode := "major"
		if data[1] == 1 {
			mode = "minor"
		}
		fields = append(fields, keyNames[data[1]][sf+7], mode)
	} else {
		if e.Status == 255 && e.Meta != 127 {
			fields = append(fields, fmt.Sprintf("%02X", e.Meta))
		}
		fields = append(fields, strconv.Itoa(len(data)))
		if len(data) > 0 {
			fields = append(fields, strings.ToUpper(hex.EncodeToString(data)))
		}
	}
	return strings.Join(fields, " ")
}

func parseHex(data []byte) (song *Song, failure *Failure) {
	defer func() {
		if caught := recover(); caught != nil {
			value := caught.(Failure)
			song = nil
			failure = &value
		}
	}()
	fail := func(pos int, reason string) {
		panic(Failure{pos, reason})
	}
	chunk := func(pos int, id string) (int, int) {
		if len(data)-pos < 8 {
			fail(pos, "truncated chunk")
		}
		if string(data[pos:pos+4]) != id {
			fail(pos, "bad chunk id")
		}
		length := be(data[pos+4 : pos+8])
		if int64(pos)+8+length > int64(len(data)) {
			fail(pos, "truncated chunk")
		}
		return pos + 8, pos + 8 + int(length)
	}
	start, finish := chunk(0, "MThd")
	if finish-start != 6 {
		fail(4, "bad header length")
	}
	format, tracks, division := int(be(data[8:10])), int(be(data[10:12])), be(data[12:14])
	if format > 2 {
		fail(8, "bad format")
	}
	if tracks == 0 || format == 0 && tracks != 1 {
		fail(10, "bad track count")
	}
	if division >= 32768 {
		fail(12, "smpte timing not supported")
	}
	if division == 0 {
		fail(12, "bad division")
	}
	song = &Song{Format: format, Division: division}
	position := finish
	for t := 0; t < tracks; t++ {
		if position == len(data) {
			fail(len(data), "missing track")
		}
		start, finish = chunk(position, "MTrk")
		position = start
		tick := int64(0)
		running := 0
		track := []*Event{}
		for position < finish {
			if len(track) > 0 && track[len(track)-1].isMeta(47) {
				fail(position, "event after end of track")
			}
			eventStart := position
			read := func() byte {
				if position >= finish {
					fail(eventStart, "truncated event")
				}
				b := data[position]
				position++
				return b
			}
			vlq := func() int64 {
				at := position
				value := int64(0)
				for i := 0; i < 4; i++ {
					b := read()
					value = value*128 + int64(b&127)
					if b < 128 {
						return value
					}
				}
				fail(at, "variable-length value too long")
				return 0
			}
			tick += vlq()
			statusPos := position
			if position >= finish {
				fail(eventStart, "truncated event")
			}
			status := int(data[position])
			if status < 128 {
				if running == 0 {
					fail(position, "data byte without running status")
				}
				status = running
			} else {
				position++
			}
			e := &Event{Tick: tick, Status: status}
			if status < 240 {
				running = status
				count := 2
				if status/16 == 12 || status/16 == 13 {
					count = 1
				}
				for j := 0; j < count; j++ {
					at := position
					b := read()
					if b >= 128 {
						fail(at, "bad data byte")
					}
					e.Data = append(e.Data, b)
				}
			} else if status == 240 || status == 247 || status == 255 {
				running = 0
				if status == 255 {
					e.Meta = int(read())
				}
				length := vlq()
				if int64(position)+length > int64(finish) {
					fail(eventStart, "truncated event")
				}
				e.Data = append([]byte{}, data[position:position+int(length)]...)
				position += int(length)
				if status == 255 {
					sizes := map[int]int{0: 2, 32: 1, 47: 0, 81: 3, 84: 5, 88: 4, 89: 2}
					if size, ok := sizes[e.Meta]; ok && size != len(e.Data) {
						fail(statusPos, "bad meta length")
					}
					d := e.Data
					bad := e.Meta == 81 && be(d) == 0 || e.Meta == 32 && d[0] > 15 || e.Meta == 88 && (d[0] == 0 || d[1] > 6) || e.Meta == 89 && (int8(d[0]) < -7 || int8(d[0]) > 7 || d[1] > 1)
					if bad {
						fail(statusPos, "bad meta data")
					}
				}
			} else {
				fail(statusPos, "unknown status byte")
			}
			track = append(track, e)
		}
		if len(track) == 0 || !track[len(track)-1].isMeta(47) {
			fail(finish, "missing end of track")
		}
		song.Tracks = append(song.Tracks, track)
		position = finish
	}
	if position < len(data) {
		fail(position, "extra data")
	}
	return song, nil
}

func parseText(lines []string) (song *Song, failure *Failure) {
	lineNo := 1
	defer func() {
		if caught := recover(); caught != nil {
			value := Failure{lineNo, caught.(string)}
			song = nil
			failure = &value
		}
	}()
	require := func(ok bool) {
		if !ok {
			panic("bad value")
		}
	}
	header := strings.Fields(lines[0])
	if len(header) != 4 || header[0] != "HEADER" {
		panic("bad header")
	}
	f, t, d := integer(header[1]), integer(header[2]), integer(header[3])
	if f < 0 || f > 2 || t < 1 || t > 65535 || d < 1 || d > 32767 || f == 0 && t != 1 {
		panic("bad header")
	}
	song = &Song{Format: int(f), Division: d, Tracks: make([][]*Event, int(t))}
	current := 0
	code := map[string]int{}
	for n, name := range metaNames {
		code[name] = n
	}
	for i, line := range lines[1:] {
		lineNo = i + 2
		words := strings.SplitN(line, " ", 4)
		tick, track, kind := integer(words[0]), int(integer(words[1])), words[2]
		fields := []string{}
		if len(words) == 4 {
			fields = strings.Split(words[3], " ")
		}
		e := &Event{Tick: tick, Status: 255}
		channel := -1
		for j, name := range channelNames {
			if name == kind {
				channel = j
			}
		}
		meta, knownMeta := code[kind]
		if channel < 0 && !knownMeta && kind != "META" && kind != "SYSEX" && kind != "SYSEX_ESCAPE" {
			panic("unknown event type")
		}
		value := func(index int, low, high int64) int64 {
			require(index < len(fields))
			n := integer(fields[index])
			require(n >= low && n <= high)
			return n
		}
		if channel >= 0 {
			count := 3
			if channel == 4 || channel == 5 || channel == 6 {
				count = 2
			}
			require(len(fields) == count)
			ch := value(0, 1, 16)
			e.Status = (channel+8)*16 + int(ch) - 1
			if channel <= 2 {
				pitch := -1
				for p := 0; p < 128; p++ {
					if fields[1] == noteName(p) {
						pitch = p
						break
					}
				}
				require(pitch >= 0)
				e.Data = []byte{byte(pitch), byte(value(2, 0, 127))}
			} else if channel == 6 {
				bend := value(1, -8192, 8191) + 8192
				e.Data = []byte{byte(bend % 128), byte(bend / 128)}
			} else {
				for j := 1; j < count; j++ {
					e.Data = append(e.Data, byte(value(j, 0, 127)))
				}
			}
		} else if knownMeta && meta >= 1 && meta <= 7 {
			require(len(words) == 4)
			text := words[3]
			require(len(text) >= 2 && text[0] == '"' && text[len(text)-1] == '"')
			require(!strings.Contains(text[1:len(text)-1], "\""))
			e.Meta = meta
			e.Data = []byte(text[1 : len(text)-1])
		} else if kind == "SYSEX" || kind == "SYSEX_ESCAPE" || kind == "META" || kind == "SEQUENCER_SPECIFIC" {
			if kind == "SYSEX" {
				e.Status = 240
			} else if kind == "SYSEX_ESCAPE" {
				e.Status = 247
			} else if kind == "META" {
				require(len(fields) >= 2 && len(fields[0]) == 2)
				require(strings.Trim(fields[0], "0123456789ABCDEF") == "")
				n, _ := strconv.ParseInt(fields[0], 16, 64)
				e.Meta = int(n)
				_, reserved := metaNames[e.Meta]
				require(!reserved)
				fields = fields[1:]
			} else {
				e.Meta = 127
			}
			length := value(0, 0, 1000000)
			if length == 0 {
				require(len(fields) == 1)
			} else {
				require(len(fields) == 2 && int64(len(fields[1])) == length*2)
				require(strings.Trim(fields[1], "0123456789ABCDEF") == "")
				e.Data, _ = hex.DecodeString(fields[1])
			}
		} else {
			e.Meta = meta
			switch meta {
			case 0:
				require(len(fields) == 1)
				e.Data = bytesBE(value(0, 0, 65535), 2)
			case 32:
				require(len(fields) == 1)
				e.Data = []byte{byte(value(0, 1, 16) - 1)}
			case 47:
				require(len(fields) == 0)
			case 81:
				require(len(fields) == 1)
				e.Data = bytesBE(value(0, 1, 16777215), 3)
			case 84:
				require(len(fields) == 5)
				for j := 0; j < 5; j++ {
					e.Data = append(e.Data, byte(value(j, 0, 255)))
				}
			case 88:
				require(len(fields) == 3)
				fraction := strings.Split(fields[0], "/")
				require(len(fraction) == 2)
				nn, dd := integer(fraction[0]), integer(fraction[1])
				exponent := -1
				for j := 0; j <= 6; j++ {
					if dd == 1<<j {
						exponent = j
					}
				}
				require(nn >= 1 && nn <= 255 && exponent >= 0)
				e.Data = []byte{byte(nn), byte(exponent), byte(value(1, 0, 255)), byte(value(2, 0, 255))}
			case 89:
				require(len(fields) == 2)
				found := false
				for mi, mode := range []string{"major", "minor"} {
					for j, key := range keyNames[mi] {
						if fields[0] == key && fields[1] == mode {
							e.Data = []byte{byte(j - 7), byte(mi)}
							found = true
						}
					}
				}
				require(found)
			}
		}
		if track >= len(song.Tracks) {
			panic("bad track")
		}
		row := song.Tracks[current]
		ended := len(row) > 0 && row[len(row)-1].isMeta(47)
		if track < current {
			panic("out of order")
		}
		if track > current && (!ended || track > current+1) {
			panic("missing end of track")
		}
		if track == current && ended {
			panic("event after end of track")
		}
		if track == current+1 {
			current++
			row = song.Tracks[current]
		}
		if len(row) > 0 && tick < row[len(row)-1].Tick {
			panic("out of order")
		}
		song.Tracks[current] = append(row, e)
	}
	lineNo = len(lines) + 1
	row := song.Tracks[current]
	if current+1 < len(song.Tracks) || len(row) == 0 || !row[len(row)-1].isMeta(47) {
		panic("missing end of track")
	}
	return song, nil
}

func vlq(value int64) []byte {
	data := []byte{byte(value % 128)}
	for value /= 128; value > 0; value /= 128 {
		data = append([]byte{byte(value%128) | 128}, data...)
	}
	return data
}

func (s *Song) encode(running, zero bool) []byte {
	result := []byte("MThd")
	result = append(result, bytesBE(6, 4)...)
	result = append(result, bytesBE(int64(s.Format), 2)...)
	result = append(result, bytesBE(int64(len(s.Tracks)), 2)...)
	result = append(result, bytesBE(s.Division, 2)...)
	for _, track := range s.Tracks {
		data := []byte{}
		last := int64(0)
		status := 0
		for _, e := range track {
			data = append(data, vlq(e.Tick-last)...)
			last = e.Tick
			st := e.Status
			body := e.Data
			if zero && st/16 == 8 {
				st += 16
				body = []byte{e.Data[0], 0}
			}
			if st < 240 {
				if !running || status != st {
					data = append(data, byte(st))
				}
				data = append(data, body...)
				status = st
			} else {
				status = 0
				data = append(data, byte(st))
				if st == 255 {
					data = append(data, byte(e.Meta))
				}
				data = append(data, vlq(int64(len(body)))...)
				data = append(data, body...)
			}
		}
		result = append(result, []byte("MTrk")...)
		result = append(result, bytesBE(int64(len(data)), 4)...)
		result = append(result, data...)
	}
	return result
}

func (s *Song) pairing() ([]Note, []Placed) {
	queues := map[[2]int][]Placed{}
	notes := []Note{}
	unmatched := []Placed{}
	for _, p := range s.ordered() {
		e := p.Event
		if !e.on() && !e.off() {
			continue
		}
		key := [2]int{e.channel(), int(e.Data[0])}
		if e.on() {
			queues[key] = append(queues[key], p)
		} else if len(queues[key]) == 0 {
			unmatched = append(unmatched, p)
		} else {
			on := queues[key][0]
			queues[key] = queues[key][1:]
			notes = append(notes, Note{on, p, e.Tick - on.Event.Tick})
		}
	}
	for _, queue := range queues {
		unmatched = append(unmatched, queue...)
	}
	sort.Slice(notes, func(i, j int) bool {
		a, b := notes[i].On, notes[j].On
		if a.Event.Tick != b.Event.Tick {
			return a.Event.Tick < b.Event.Tick
		}
		if a.Event.channel() != b.Event.channel() {
			return a.Event.channel() < b.Event.channel()
		}
		if a.Event.Data[0] != b.Event.Data[0] {
			return a.Event.Data[0] < b.Event.Data[0]
		}
		return a.Order < b.Order
	})
	sort.Slice(unmatched, func(i, j int) bool {
		return unmatched[i].Order < unmatched[j].Order
	})
	return notes, unmatched
}

func (s *Song) timeAt(tick int64) string {
	total, last, tempo := int64(0), int64(0), int64(500000)
	for _, p := range s.ordered() {
		e := p.Event
		if e.Tick > tick {
			break
		}
		if e.isMeta(81) {
			total += (e.Tick - last) * tempo
			last = e.Tick
			tempo = be(e.Data)
		}
	}
	usec := (total + (tick-last)*tempo) / s.Division
	return fmt.Sprintf("%d.%03d", usec/1000, usec%1000)
}

func (s *Song) barAt(tick int64) string {
	start, bar, nn, beat := int64(0), int64(1), int64(4), s.Division
	for _, p := range s.ordered() {
		e := p.Event
		if e.Tick > tick {
			break
		}
		if e.isMeta(88) {
			size := nn * beat
			bar += (e.Tick - start + size - 1) / size
			start = e.Tick
			nn = int64(e.Data[0])
			beat = s.Division * 4 / (1 << e.Data[1])
		}
	}
	x := tick - start
	return fmt.Sprintf("%d:%d:%d", bar+x/(nn*beat), x%(nn*beat)/beat+1, x%beat)
}

func floorDiv(x, y int64) int64 {
	q := x / y
	if x%y < 0 {
		q--
	}
	return q
}

func execute(words []string, songs map[string]*Song, running, zero *bool) {
	cmd := words[0]
	a := words[1:]
	commands := " DECODE ENCODE TIMING NOTES STATS ROLL TRANSPOSE QUANTIZE VELOCITY TEMPO FILTER MERGE SPLIT COPY LIST RUNNING NOTEOFF "
	if !strings.Contains(commands, " "+cmd+" ") {
		output("error: unknown command")
		return
	}
	if cmd == "LIST" {
		names := []string{}
		for name := range songs {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			output(name + " " + songs[name].summary())
		}
		if len(names) == 0 {
			output("no songs")
		}
		return
	}
	if cmd == "RUNNING" || cmd == "NOTEOFF" {
		valid := a[0] == "ON" || a[0] == "OFF"
		if cmd == "NOTEOFF" {
			valid = a[0] == "ZERO" || a[0] == "KEEP"
		}
		if !valid {
			output("error: bad argument")
			return
		}
		if cmd == "RUNNING" {
			*running = a[0] == "ON"
		} else {
			*zero = a[0] == "ZERO"
		}
		output(strings.ToLower(cmd) + " " + strings.ToLower(a[0]))
		return
	}
	song, exists := songs[a[0]]
	if !exists {
		output("error: no song " + a[0])
		return
	}
	args := []int64{}
	if cmd != "COPY" {
		for _, word := range a[1:] {
			args = append(args, integer(word))
		}
	}
	valid := true
	between := func(x, lo, hi int64) bool {
		return x >= lo && x <= hi
	}
	switch cmd {
	case "TRANSPOSE":
		valid = between(args[0], -127, 127)
		if len(args) > 1 {
			valid = valid && between(args[1], 1, 16)
		}
	case "QUANTIZE":
		valid = between(args[0], 1, 1000000) && between(args[1], 0, 100)
	case "VELOCITY":
		valid = between(args[0], 0, 1000) && between(args[1], -127, 127)
	case "TEMPO":
		valid = between(args[0], 1, 1000) && between(args[1], 1, 1000)
	case "FILTER":
		for _, x := range args {
			valid = valid && between(x, 1, 16)
		}
	case "ROLL":
		valid = between(args[0], 0, 10000000) && between(args[1], 1, 10000000) && between(args[2], 1, 10000000) && args[1] > args[0]
		if valid {
			valid = (args[1]-args[0]+args[2]-1)/args[2] <= 64
		}
	}
	if !valid {
		output("error: bad argument")
		return
	}
	if (cmd == "TIMING" || cmd == "STATS") && song.Format == 2 {
		output("error: format 2 not supported")
		return
	}
	if cmd == "MERGE" && song.Format != 1 {
		output("error: not format 1")
		return
	}
	if cmd == "SPLIT" && song.Format != 0 {
		output("error: not format 0")
		return
	}
	switch cmd {
	case "COPY":
		songs[a[1]] = song.clone()
		output("copied " + a[0] + " to " + a[1])
	case "DECODE":
		output(fmt.Sprintf("HEADER %d %d %d", song.Format, len(song.Tracks), song.Division))
		for t, track := range song.Tracks {
			for _, e := range track {
				output(eventLine(e, t))
			}
		}
	case "ENCODE":
		data := song.encode(*running, *zero)
		for i := 0; i < len(data); i += 16 {
			values := []string{}
			for _, b := range data[i:min(i+16, len(data))] {
				values = append(values, fmt.Sprintf("%02X", b))
			}
			output(fmt.Sprintf("%04X: %s", i, strings.Join(values, " ")))
		}
		output(fmt.Sprintf("%d bytes", len(data)))
	case "TIMING":
		for _, p := range song.ordered() {
			e := p.Event
			output(fmt.Sprintf("%d %d %s %s %s", e.Tick, p.Track, e.kind(), song.timeAt(e.Tick), song.barAt(e.Tick)))
		}
		t := song.length()
		output(fmt.Sprintf("end %d %s %s", t, song.timeAt(t), song.barAt(t)))
	case "NOTES", "STATS", "ROLL":
		notes, unmatched := song.pairing()
		if cmd == "ROLL" {
			columns := int((args[1] - args[0] + args[2] - 1) / args[2])
			any := false
			for pitch := 127; pitch >= 0; pitch-- {
				row := make([]byte, columns)
				for i := range row {
					tick := args[0] + int64(i)*args[2]
					row[i] = '.'
					for _, n := range notes {
						if int(n.On.Event.Data[0]) != pitch {
							continue
						}
						start := n.On.Event.Tick
						if tick <= start && start < tick+args[2] {
							row[i] = '#'
							break
						}
						if start <= tick && tick < start+n.Length {
							row[i] = '='
						}
					}
				}
				if strings.Trim(string(row), ".") != "" {
					output(fmt.Sprintf("%-4s %s", noteName(pitch), row))
					any = true
				}
			}
			if !any {
				output("empty")
			}
			break
		}
		if cmd == "STATS" {
			output(song.summary())
		}
		output(fmt.Sprintf("notes %d unmatched %d", len(notes), len(unmatched)))
		if cmd == "NOTES" {
			for _, n := range notes {
				e := n.On.Event
				output(fmt.Sprintf("%d %d %d %s %d", e.Tick, n.Length, e.channel(), noteName(int(e.Data[0])), e.Data[1]))
			}
			for _, p := range unmatched {
				e := p.Event
				kind := "off"
				if e.on() {
					kind = "on"
				}
				output(fmt.Sprintf("unmatched %s %d %d %d %s", kind, e.Tick, p.Track, e.channel(), noteName(int(e.Data[0]))))
			}
		} else {
			low, high := 128, -1
			changes := map[int64]int{}
			for channel := 1; channel <= 16; channel++ {
				count, lo, hi := 0, 128, -1
				for _, n := range notes {
					e := n.On.Event
					if e.channel() == channel {
						count++
						lo = min(lo, int(e.Data[0]))
						hi = max(hi, int(e.Data[0]))
					}
				}
				if count > 0 {
					output(fmt.Sprintf("channel %d notes %d range %s %s", channel, count, noteName(lo), noteName(hi)))
					low = min(low, lo)
					high = max(high, hi)
				}
			}
			if high < 0 {
				output("range none")
			} else {
				output("range " + noteName(low) + " " + noteName(high))
			}
			output(fmt.Sprintf("length %d ticks %s ms", song.length(), song.timeAt(song.length())))
			for _, n := range notes {
				if n.Length > 0 {
					changes[n.On.Event.Tick]++
					changes[n.On.Event.Tick+n.Length]--
				}
			}
			ticks := []int64{}
			for tick := range changes {
				ticks = append(ticks, tick)
			}
			sort.Slice(ticks, func(i, j int) bool {
				return ticks[i] < ticks[j]
			})
			current, peak := 0, 0
			at := int64(0)
			for _, tick := range ticks {
				current += changes[tick]
				if current > peak {
					peak = current
					at = tick
				}
			}
			if peak == 0 {
				output("polyphony 0")
			} else {
				output(fmt.Sprintf("polyphony %d at %d", peak, at))
			}
		}
	case "TRANSPOSE":
		kept, dropped := 0, []string{}
		for t, track := range song.Tracks {
			row := []*Event{}
			for _, e := range track {
				target := e.Status < 176 && (len(args) == 1 || int64(e.channel()) == args[1])
				if target {
					pitch := int64(e.Data[0]) + args[0]
					if pitch < 0 || pitch > 127 {
						dropped = append(dropped, fmt.Sprintf("dropped %d %d %s %d %s", e.Tick, t, e.kind(), e.channel(), noteName(int(e.Data[0]))))
						continue
					}
					e.Data[0] = byte(pitch)
					kept++
				}
				row = append(row, e)
			}
			song.Tracks[t] = row
		}
		output(fmt.Sprintf("transposed %d dropped %d", kept, len(dropped)))
		for _, line := range dropped {
			output(line)
		}
	case "QUANTIZE":
		notes, unmatched := song.pairing()
		moved, targets := 0, 0
		shift := func(on, off *Event) {
			targets++
			grid, strength := args[0], args[1]
			lower := on.Tick / grid * grid
			target := lower
			if on.Tick-lower > lower+grid-on.Tick {
				target += grid
			}
			delta := floorDiv(2*(target-on.Tick)*strength+100, 200)
			if delta != 0 {
				moved++
			}
			on.Tick += delta
			if off != nil {
				off.Tick += delta
			}
		}
		for _, n := range notes {
			shift(n.On.Event, n.Off.Event)
		}
		for _, p := range unmatched {
			if p.Event.on() {
				shift(p.Event, nil)
			}
		}
		for t, track := range song.Tracks {
			ending := track[len(track)-1]
			row := track[:len(track)-1]
			sort.SliceStable(row, func(i, j int) bool {
				return row[i].Tick < row[j].Tick
			})
			if len(row) > 0 {
				ending.Tick = max(ending.Tick, row[len(row)-1].Tick)
			}
			song.Tracks[t] = append(row, ending)
		}
		output(fmt.Sprintf("quantized %d moved %d", targets, moved))
	case "VELOCITY":
		count, clamped := 0, 0
		for _, track := range song.Tracks {
			for _, e := range track {
				if e.on() {
					count++
					v := (int64(e.Data[1])*args[0]+50)/100 + args[1]
					if v < 1 || v > 127 {
						clamped++
					}
					e.Data[1] = byte(max(1, min(127, v)))
				}
			}
		}
		output(fmt.Sprintf("velocity %d clamped %d", count, clamped))
	case "TEMPO":
		trial := song.clone()
		count := 0
		exists := false
		good := true
		scale := func(v int64) int64 {
			return (2*v*args[1] + args[0]) / (2 * args[0])
		}
		for _, track := range trial.Tracks {
			for _, e := range track {
				if e.isMeta(81) {
					count++
					exists = exists || e.Tick == 0
					v := scale(be(e.Data))
					if v < 1 || v > 16777215 {
						good = false
					}
					e.Data = bytesBE(v, 3)
				}
			}
		}
		inserted := scale(500000)
		if !exists {
			if inserted < 1 || inserted > 16777215 {
				good = false
			}
			trial.Tracks[0] = append([]*Event{{0, 255, 81, bytesBE(inserted, 3)}}, trial.Tracks[0]...)
		}
		if !good {
			output("error: tempo out of range")
			return
		}
		songs[a[0]] = trial
		output(fmt.Sprintf("scaled %d", count))
		if !exists {
			output(fmt.Sprintf("inserted 0 0 TEMPO %d", inserted))
		}
	case "FILTER":
		allowed := map[int]bool{}
		for _, ch := range args {
			allowed[int(ch)] = true
		}
		count := 0
		for t, track := range song.Tracks {
			row := []*Event{}
			for _, e := range track {
				if e.Status < 240 && !allowed[e.channel()] {
					count++
				} else {
					row = append(row, e)
				}
			}
			song.Tracks[t] = row
		}
		output(fmt.Sprintf("removed %d", count))
	case "MERGE":
		original := len(song.Tracks)
		length := song.length()
		row := []*Event{}
		for _, p := range song.ordered() {
			if !p.Event.isMeta(47) {
				row = append(row, p.Event)
			}
		}
		row = append(row, end(length))
		song.Format = 0
		song.Tracks = [][]*Event{row}
		output(fmt.Sprintf("merged %d tracks events %d", original, len(row)))
	case "SPLIT":
		length := song.length()
		rows := map[int][]*Event{0: {}}
		for _, e := range song.Tracks[0] {
			if e.isMeta(47) {
				continue
			}
			channel := 0
			if e.Status < 240 {
				channel = e.channel()
			}
			rows[channel] = append(rows[channel], e)
		}
		channels := []int{}
		for ch := range rows {
			channels = append(channels, ch)
		}
		sort.Ints(channels)
		song.Tracks = nil
		for _, ch := range channels {
			song.Tracks = append(song.Tracks, append(rows[ch], end(length)))
		}
		song.Format = 1
		output(fmt.Sprintf("split tracks %d events %d", len(song.Tracks), func() int {
			n := 0
			for _, row := range song.Tracks {
				n += len(row)
			}
			return n
		}()))
	}
}

func main() {
	defer writer.Flush()
	input := bufio.NewReader(os.Stdin)
	read := func() string {
		line, _ := input.ReadString('\n')
		return strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
	}
	n := int(integer(read()))
	songs := map[string]*Song{}
	running, zero := true, false
	for i := 0; i < n; i++ {
		words := strings.Split(read(), " ")
		if words[0] == "HEX" || words[0] == "TEXT" {
			lines := []string{}
			for k := 0; k < int(integer(words[2])); k++ {
				lines = append(lines, read())
			}
			var song *Song
			var failure *Failure
			label := "line"
			if words[0] == "HEX" {
				data, _ := hex.DecodeString(strings.ReplaceAll(strings.Join(lines, ""), " ", ""))
				song, failure = parseHex(data)
				label = "byte"
			} else {
				song, failure = parseText(lines)
			}
			if failure != nil {
				output(fmt.Sprintf("error: %s %d: %s", label, failure.Position, failure.Reason))
			} else {
				songs[words[1]] = song
				output("loaded " + words[1] + " " + song.summary())
			}
		} else {
			execute(words, songs, &running, &zero)
		}
	}
}
