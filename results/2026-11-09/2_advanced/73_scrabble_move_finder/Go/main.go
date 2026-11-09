package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Tiles struct{ Value, Count, Weight [27]int }
type DictionaryStats struct {
	Lines, Skipped, Duplicates int
	Lengths                    [16]int
}
type PlayerSpec struct {
	Name, Strategy string
	Threshold      int
}
type Job struct {
	Header      []string
	Lines       []string
	Board       Board
	Rack        string
	Count, Seed int
	Order       string
	Records     [][]string
	Players     []PlayerSpec
}
type TopTotals struct{ Jobs, Errors, Moves, Bingos int }
type ValidationTotals struct{ Jobs, Errors, Moves, Valid, Invalid, Loss int }
type GameTotals struct{ Games, Duplicates, Errors, Turns, Rounds, Plays, Exchanges, Passes, Bingos int }
type PlayerRecord struct {
	Name                      string
	Moves, Valid, Score, Loss int
}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func text(path string) string { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int    { v, e := strconv.Atoi(s); must(e); return v }
func upper(c byte) byte {
	if c >= 'a' && c <= 'z' {
		return c - 'a' + 'A'
	}
	return c
}
func tileIndex(c byte) int {
	if c == '?' || c >= 'a' && c <= 'z' {
		return 26
	}
	return int(c - 'A')
}
func collectionCounts(s string) [27]int {
	var a [27]int
	for i := range s {
		a[tileIndex(s[i])]++
	}
	return a
}
func countsString(a [27]int) string {
	var s strings.Builder
	for k := 0; k < a[26]; k++ {
		s.WriteByte('?')
	}
	for i := 0; i < 26; i++ {
		for k := 0; k < a[i]; k++ {
			s.WriteByte(byte('A' + i))
		}
	}
	return s.String()
}
func sortedCollection(s string) string { return countsString(collectionCounts(s)) }
func notation(s string) string {
	if s == "" {
		return "-"
	}
	return sortedCollection(s)
}
func validName(s string) bool {
	if len(s) < 1 || len(s) > 20 {
		return false
	}
	for i := range s {
		c := s[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_') {
			return false
		}
	}
	return true
}
func validNumber(s string, lo, hi int) (int, bool) {
	if len(s) == 0 || len(s) > 1 && s[0] == '0' {
		return 0, false
	}
	n := 0
	for i := range s {
		c := s[i]
		if c < '0' || c > '9' {
			return 0,
				false
		}
		digit := int(c - '0')
		if n > (hi-digit)/10 {
			return 0, false
		}
		n = 10*n + digit
		if n > hi {
			return 0, false
		}
	}
	return n,
		n >= lo && n <= hi
}
func validRack(s string) bool {
	if len(s) < 1 || len(s) > 7 {
		return false
	}
	for i := range s {
		if !(s[i] >= 'A' && s[i] <= 'Z' || s[i] == '?') {
			return false
		}
	}
	return true
}
func validWord(s string, uppercaseOnly bool) bool {
	if len(s) < 2 || len(s) > 15 {
		return false
	}
	for i := range s {
		c := s[i]
		if !(c >= 'A' && c <= 'Z' || !uppercaseOnly && c >= 'a' && c <= 'z') {
			return false
		}
	}
	return true
}
func strategy(s string) bool { return s == "score" || s == "tiles" || s == "equity" }
func readData() (Tiles, Trie, DictionaryStats, []Job) {
	var tiles Tiles
	for _, line := range strings.Split(strings.TrimSuffix(text("input/tiles.txt"),
		"\n"), "\n") {
		if line == "" || line[0] == '#' {
			continue
		}
		a := strings.Fields(line)
		i := tileIndex(a[0][0])
		tiles.Value[i],
			tiles.Count[i], tiles.Weight[i] = integer(a[1]), integer(a[2]), integer(a[3])
	}
	trie := newTrie()
	var stats DictionaryStats
	for _, word := range strings.Split(strings.TrimSuffix(text("input/dictionary.txt"), "\n"), "\n") {
		if word == "" || word[0] == '#' {
			continue
		}
		stats.Lines++
		if !validWord(word,
			true) {
			stats.Skipped++
			continue
		}
		if !trie.add(word) {
			stats.Duplicates++
			continue
		}
		stats.Lengths[len(word)]++
	}
	lines := strings.Split(strings.TrimSuffix(text("input/jobs.txt"),
		"\n"), "\n")
	var jobs []Job
	for pos := 0; pos < len(lines); pos++ {
		line := lines[pos]
		if line == "" || line[0] == '#' {
			continue
		}
		job := Job{Header: strings.Fields(line),
			Board: newBoard()}
		for pos++; pos < len(lines) && lines[pos] != "END"; pos++ {
			job.Lines = append(job.Lines,
				lines[pos])
		}
		jobs = append(jobs, job)
	}
	return tiles, trie, stats, jobs
}
func boardCounts(board Board) [27]int {
	var count [27]int
	for _, row := range board {
		for _, letter := range row {
			if letter != '.' {
				count[tileIndex(letter)]++
			}
		}
	}
	return count
}
func countError(board Board, rack string, tiles Tiles) string {
	count := boardCounts(board)
	r := collectionCounts(rack)
	for i := 0; i < 27; i++ {
		if count[i]+r[i] > tiles.Count[i] {
			letter := byte('A' + i)
			if i == 26 {
				letter = '?'
			}
			return "too many " + string(letter)
		}
	}
	return ""
}
func unseen(board Board, rack string, tiles Tiles) string {
	used, r := boardCounts(board), collectionCounts(rack)
	var a [27]int
	for i := range a {
		a[i] = tiles.Count[i] - used[i] - r[i]
	}
	return countsString(a)
}
func checkBoard(lines []string, rack string, tiles Tiles, trie Trie) (Board, string) {
	board := newBoard()
	if len(lines) != 15 {
		return board,
			fmt.Sprintf("board rows %d", len(lines))
	}
	for i, row := range lines {
		valid := len(row) == 15
		for j := range row {
			c := row[j]
			if !(c == '.' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z') {
				valid = false
			}
		}
		if !valid {
			return board,
				fmt.Sprintf("bad board row %d", i+1)
		}
		copy(board[i][:], row)
	}
	if reason := countError(board, rack,
		tiles); reason != "" {
		return board, reason
	}
	if tileCount(board) > 0 {
		if board[center][center] == '.' {
			return board,
				"center empty"
		}
		if !connected(board) {
			return board, "disconnected"
		}
	}
	for _, word := range boardWords(board) {
		if !trie.contains(word.Word) {
			return board,
				fmt.Sprintf("unknown word %s at %s", word.Word, positionName(word.Row, word.Col, word.Direction))
		}
	}
	return board,
		""
}
func checkJob(job *Job, seen map[string]bool, tiles Tiles, trie Trie) string {
	h := job.Header
	name := h[1]
	reason := ""
	if !validName(name) {
		reason = "bad name"
	} else if seen[name] {
		reason = "duplicate name"
	}
	seen[name] = true
	if reason != "" {
		return reason
	}
	switch h[0] {
	case "TOPN":
		count,
			valid := validNumber(h[2], 1, 99)
		if !valid {
			return "bad count"
		}
		if !strategy(h[3]) {
			return "bad order"
		}
		rack := strings.Fields(job.Lines[0])[1]
		if !validRack(rack) {
			return "bad rack"
		}
		job.Count,
			job.Order, job.Rack = count, h[3], rack
		board, error := checkBoard(job.Lines[2:], rack, tiles, trie)
		job.Board = board
		return error
	case "VALIDATE":
		var boardLines []string
		records := false
		for _, line := range job.Lines[1:] {
			if strings.HasPrefix(line, "MOVE") {
				records = true
			}
			if records {
				job.Records = append(job.Records,
					strings.Fields(line))
			} else {
				boardLines = append(boardLines, line)
			}
		}
		board, error := checkBoard(boardLines,
			"", tiles, trie)
		job.Board = board
		return error
	default:
		seed, valid := validNumber(h[2], 1, 2147483646)
		if !valid {
			return "bad seed"
		}
		job.Seed = seed
		if len(job.Lines) < 2 || len(job.Lines) > 4 {
			return fmt.Sprintf("bad player count %d",
				len(job.Lines))
		}
		names := map[string]bool{}
		for i, line := range job.Lines {
			a := strings.Fields(line)
			threshold := 0
			validThreshold := true
			if h[0] == "GAME" {
				threshold,
					validThreshold = validNumber(a[3], 0, 99)
			}
			if !validName(a[1]) || !strategy(a[2]) || !validThreshold {
				return fmt.Sprintf("bad player %d",
					i+1)
			}
			if names[a[1]] {
				return fmt.Sprintf("duplicate player %d", i+1)
			}
			names[a[1]] = true
			job.Players = append(job.Players,
				PlayerSpec{a[1], a[2], threshold})
		}
		return ""
	}
}
func rackBreakdown(rack string) (int, int, int) {
	v, c, b := 0, 0, 0
	for i := range rack {
		letter := rack[i]
		if letter == '?' {
			b++
		} else if strings.ContainsRune("AEIOU",
			rune(letter)) {
			v++
		} else {
			c++
		}
	}
	return v, c, b
}
func leaveValue(rack string, tiles Tiles) int {
	counts := collectionCounts(rack)
	value, duplicates := 0,
		0
	for i, n := range counts {
		value += n * tiles.Weight[i]
		if i < 26 && n > 0 {
			duplicates += n - 1
		}
	}
	v, c, _ := rackBreakdown(rack)
	difference := v - c
	if difference < 0 {
		difference = -difference
	}
	return value - 4*duplicates - 3*max(0,
		difference-1)
}
func bestLeave(rack string, tiles Tiles) (string, int) {
	best := ""
	value := leaveValue(best, tiles)
	seen := map[string]bool{}
	for mask := 0; mask < (1<<len(rack))-1; mask++ {
		var a []byte
		for i := range rack {
			if mask>>i&1 != 0 {
				a = append(a,
					rack[i])
			}
		}
		candidate := sortedCollection(string(a))
		if seen[candidate] {
			continue
		}
		seen[candidate] = true
		score := leaveValue(candidate,
			tiles)
		if score > value || score == value && (len(candidate) > len(best) || len(candidate) == len(best) && candidate < best) {
			best,
				value = candidate, score
		}
	}
	return best, value
}
func standardLess(a, b Move) bool {
	if a.Score != b.Score {
		return a.Score > b.Score
	}
	if a.Raw.Row != b.Raw.Row {
		return a.Raw.Row < b.Raw.Row
	}
	if a.Raw.Col != b.Raw.Col {
		return a.Raw.Col < b.Raw.Col
	}
	if a.Raw.Direction != b.Raw.Direction {
		return a.Raw.Direction < b.Raw.Direction
	}
	return a.Raw.Word < b.Raw.Word
}
func legalMoves(board Board, rack string, tiles Tiles, trie Trie) []Move {
	raw := generateMoves(board, rack,
		trie)
	moves := make([]Move, len(raw))
	for i, r := range raw {
		moves[i] = evaluateMove(board, rack, r, tiles)
		moves[i].LeaveValue = leaveValue(moves[i].Leave,
			tiles)
	}
	sort.Slice(moves, func(i, j int) bool { return standardLess(moves[i], moves[j]) })
	for i := range moves {
		moves[i].Rank = i + 1
	}
	return moves
}
func orderedMoves(moves []Move, strategy string) []Move {
	a := append([]Move(nil), moves...)
	sort.SliceStable(a,
		func(i, j int) bool {
			if strategy == "tiles" {
				return a[i].Tiles > a[j].Tiles
			}
			if strategy == "equity" {
				return a[i].Score+a[i].LeaveValue > a[j].Score+a[j].LeaveValue
			}
			return false
		})
	return a
}
func moveName(m Move) string {
	return positionName(m.Raw.Row, m.Raw.Col, m.Raw.Direction) + " " + m.Raw.Word
}
func positionSummary(board Board) string {
	words := boardWords(board)
	longest := "-"
	length := 0
	for _, word := range words {
		if len(word.Word) > length {
			longest,
				length = word.Word, len(word.Word)
		}
	}
	blanks := 0
	premiumsUsed := map[byte]int{}
	for r, row := range board {
		for c, tile := range row {
			if tile != '.' {
				if tile >= 'a' && tile <= 'z' {
					blanks++
				}
				premiumsUsed[premiums[r][c]]++
			}
		}
	}
	return fmt.Sprintf("position tiles=%d words=%d longest=%s blanks=%d premiums=TW:%d,DW:%d,TL:%d,DL:%d",
		tileCount(board), len(words), longest, blanks, premiumsUsed['#'], premiumsUsed['*'], premiumsUsed['^'],
		premiumsUsed['+'])
}
func line(s *strings.Builder, template string, a ...any) { fmt.Fprintf(s, template+"\n", a...) }
func boardReport(s *strings.Builder, board Board) {
	line(s, "%s", positionSummary(board))
	for _, row := range display(board) {
		line(s, "%s", row)
	}
}
func reportTop(job Job, tiles Tiles, trie Trie, total *TopTotals) string {
	var out strings.Builder
	moves := legalMoves(job.Board,
		job.Rack, tiles, trie)
	a := anchors(job.Board)
	anchorCount := 0
	for _, row := range a {
		for _, value := range row {
			if value {
				anchorCount++
			}
		}
	}
	unseenTiles := unseen(job.Board,
		job.Rack, tiles)
	vowels, consonants, blanks := rackBreakdown(job.Rack)
	_, acrossChecks := crossChecks(job.Board,
		0, trie)
	_, downChecks := crossChecks(job.Board, 1, trie)
	across, down, bingos, blankMoves := 0, 0, 0, 0
	byTiles := [8]int{-1,
		-1, -1, -1, -1, -1, -1, -1}
	for _, move := range moves {
		if move.Raw.Direction == 0 {
			across++
		} else {
			down++
		}
		if move.Tiles == 7 {
			bingos++
		}
		hasBlank := false
		for _, tile := range move.Placed {
			if tile.Letter >= 'a' && tile.Letter <= 'z' {
				hasBlank = true
			}
		}
		if hasBlank {
			blankMoves++
		}
		byTiles[move.Tiles] = max(byTiles[move.Tiles],
			move.Score)
	}
	total.Moves += len(moves)
	total.Bingos += bingos
	keep, keepValue := bestLeave(job.Rack,
		tiles)
	anagrams := trie.anagrams(job.Rack)
	sort.Slice(anagrams, func(i, j int) bool {
		a, b := anagrams[i],
			anagrams[j]
		return len(a) > len(b) || len(a) == len(b) && a < b
	})
	topAnagrams := "-"
	if len(anagrams) > 0 {
		topAnagrams = strings.Join(anagrams[:min(10,
			len(anagrams))], ",")
	}
	line(&out, "TOPN %s n=%d order=%s rack=%s", job.Header[1], job.Count, job.Order,
		notation(job.Rack))
	line(&out, "board tiles=%d anchors=%d", tileCount(job.Board), anchorCount)
	line(&out,
		"unseen count=%d tiles=%s", len(unseenTiles), notation(unseenTiles))
	line(&out, "rack vowels=%d consonants=%d blanks=%d value=%d",
		vowels, consonants, blanks, collectionValue(job.Rack, tiles))
	line(&out, "checks across=%d,%d,%d down=%d,%d,%d",
		acrossChecks.Squares, acrossChecks.Empty, acrossChecks.Letters, downChecks.Squares, downChecks.Empty,
		downChecks.Letters)
	line(&out, "moves total=%d across=%d down=%d bingos=%d blanks=%d", len(moves),
		across, down, bingos, blankMoves)
	parts := []string{"best_by_tiles"}
	for t := 1; t <= 7; t++ {
		value := "-"
		if byTiles[t] >= 0 {
			value = fmt.Sprint(byTiles[t])
		}
		parts = append(parts,
			fmt.Sprintf("%d=%s", t, value))
	}
	line(&out, strings.Join(parts, " "))
	line(&out, "exchange keep=%s value=%d",
		notation(keep), keepValue)
	line(&out, "anagrams total=%d top=%s", len(anagrams), topAnagrams)
	for _, word := range boardWords(job.Board) {
		if len(word.Word) < 3 {
			continue
		}
		upperWord := strings.ToUpper(word.Word)
		front,
			back := "", ""
		for letter := 'A'; letter <= 'Z'; letter++ {
			if trie.contains(string(letter) + upperWord) {
				front += string(letter)
			}
			if trie.contains(upperWord + string(letter)) {
				back += string(letter)
			}
		}
		if front == "" && back == "" {
			continue
		}
		if front == "" {
			front = "-"
		}
		if back == "" {
			back = "-"
		}
		line(&out,
			"hook %s %s front=%s back=%s", positionName(word.Row, word.Col, word.Direction), word.Word, front,
			back)
	}
	shown := orderedMoves(moves, job.Order)
	shown = shown[:min(job.Count, len(shown))]
	endgame := len(unseenTiles) >= 1 && len(unseenTiles) <= 7 && len(shown) > 0
	nets := make([]int,
		len(shown))
	if endgame {
		best := 0
		for i, move := range shown {
			after := job.Board
			play(&after, move)
			reply := legalMoves(after,
				unseenTiles, tiles, trie)
			score := 0
			if len(reply) > 0 {
				score = reply[0].Score
			}
			nets[i] = move.Score - score
			if nets[i] > nets[best] {
				best = i
			}
		}
		line(&out,
			"endgame opponent=%s best=%d net=%d", notation(unseenTiles), best+1, nets[best])
	}
	for i, move := range shown {
		fmt.Fprintf(&out,
			"%d %s score=%d tiles=%d leave=%s value=%d", i+1, moveName(move), move.Score, move.Tiles, notation(move.Leave),
			move.LeaveValue)
		if endgame {
			fmt.Fprintf(&out, " net=%d", nets[i])
		}
		fmt.Fprintf(&out, " words=%s\n",
			wordList(move))
	}
	return out.String()
}
func validatePlacement(board Board, rack, position, word string, tiles Tiles, trie Trie) (Move, string) {
	row,
		col, direction, valid := parsePosition(position)
	if !valid {
		return Move{}, "bad position"
	}
	if !validWord(word,
		false) {
		return Move{}, "bad word"
	}
	raw := RawMove{row, col, direction, word}
	squares := moveSquares(raw)
	for _, p := range squares {
		if !inside(p.Row, p.Col) {
			return Move{}, "off board"
		}
	}
	var newTiles []PlacedTile
	for i, p := range squares {
		existing := board[p.Row][p.Col]
		if existing != '.' && existing != word[i] {
			return Move{},
				"mismatch at " + squareName(p.Row, p.Col)
		}
		if existing == '.' {
			newTiles = append(newTiles, PlacedTile{p.Row,
				p.Col, word[i]})
		}
	}
	dr, dc := directions(direction)
	before := Square{row - dr, col - dc}
	last := squares[len(squares)-1]
	after := Square{last.Row + dr,
		last.Col + dc}
	if inside(before.Row, before.Col) && board[before.Row][before.Col] != '.' || inside(after.Row,
		after.Col) && board[after.Row][after.Col] != '.' {
		return Move{}, "not whole word"
	}
	if len(newTiles) == 0 {
		return Move{},
			"no new tiles"
	}
	counts := collectionCounts(rack)
	touches, centerCovered := false, false
	for _, tile := range newTiles {
		i := tileIndex(tile.Letter)
		if counts[i] == 0 {
			letter := byte('A' + i)
			if i == 26 {
				letter = '?'
			}
			return Move{},
				"rack lacks " + string(letter)
		}
		counts[i]--
		if adjacent(board, tile.Row, tile.Col) {
			touches = true
		}
		if tile.Row == center && tile.Col == center {
			centerCovered = true
		}
	}
	if tileCount(board) == 0 {
		if !centerCovered {
			return Move{},
				"center not covered"
		}
	} else if !touches {
		return Move{}, "not connected"
	}
	move := evaluateMove(board,
		rack, raw, tiles)
	for _, w := range move.Words {
		word := w.BoardWord
		if !trie.contains(word.Word) {
			return Move{},
				fmt.Sprintf("unknown word %s at %s", word.Word, positionName(word.Row, word.Col, word.Direction))
		}
	}
	move.LeaveValue = leaveValue(move.Leave,
		tiles)
	return move, ""
}
func validateRecord(board Board, record []string, tiles Tiles, trie Trie) (Move, string) {
	if !validName(record[1]) {
		return Move{},
			"bad player"
	}
	rack := record[2]
	if !validRack(rack) {
		return Move{}, "bad rack"
	}
	if reason := countError(board,
		rack, tiles); reason != "" {
		return Move{}, reason
	}
	if len(record) == 4 {
		return Move{}, ""
	}
	if record[3] == "EXCHANGE" {
		putBack := record[4]
		if !validRack(putBack) {
			return Move{},
				"bad exchange"
		}
		count, r := collectionCounts(putBack), collectionCounts(rack)
		for i := range putBack {
			letter := putBack[i]
			index := tileIndex(letter)
			if count[index] > r[index] {
				return Move{},
					"rack lacks " + string(letter)
			}
		}
		return Move{}, ""
	}
	return validatePlacement(board, rack, record[3],
		record[4], tiles, trie)
}
func reportValidation(job Job, tiles Tiles, trie Trie, total *ValidationTotals) string {
	var out strings.Builder
	line(&out,
		"VALIDATE %s", job.Header[1])
	board := job.Board
	var players []*PlayerRecord
	byName := map[string]*PlayerRecord{}
	valid,
		invalid, scoreTotal, bestTotal, lossTotal := 0, 0, 0, 0, 0
	for i, record := range job.Records {
		move, reason := validateRecord(board,
			record, tiles, trie)
		var player *PlayerRecord
		if reason != "bad player" {
			player = byName[record[1]]
			if player == nil {
				player = &PlayerRecord{Name: record[1]}
				byName[record[1]] = player
				players = append(players,
					player)
			}
			player.Moves++
		}
		fmt.Fprintf(&out, "move %d %s %s", i+1, record[1], strings.Join(record[3:],
			" "))
		if reason != "" {
			invalid++
			fmt.Fprintf(&out, " invalid %s\n", reason)
			continue
		}
		valid++
		moves := legalMoves(board,
			record[2], tiles, trie)
		best := 0
		if len(moves) > 0 {
			best = moves[0].Score
		}
		isPlacement := len(record) == 5 && record[3] != "EXCHANGE"
		score := 0
		if isPlacement {
			score = move.Score
		}
		loss := best - score
		player.Valid++
		player.Score += score
		player.Loss += loss
		scoreTotal += score
		bestTotal += best
		lossTotal += loss
		if isPlacement {
			placement := placementKey(board,
				move.Raw)
			rank := 0
			for _, candidate := range moves {
				if placementKey(board, candidate.Raw) == placement {
					rank = candidate.Rank
					break
				}
			}
			fmt.Fprintf(&out,
				" score=%d total=%d tiles=%d rank=%d/%d best=%d words=%s\n", score, player.Score, move.Tiles, rank,
				len(moves), best, wordList(move))
			play(&board, move)
		} else {
			fmt.Fprintf(&out, " score=0 total=%d moves=%d best=%d\n",
				player.Score, len(moves), best)
		}
	}
	for _, player := range players {
		line(&out, "player %s moves=%d valid=%d score=%d loss=%d",
			player.Name, player.Moves, player.Valid, player.Score, player.Loss)
	}
	line(&out, "total valid=%d invalid=%d score=%d best=%d loss=%d",
		valid, invalid, scoreTotal, bestTotal, lossTotal)
	boardReport(&out, board)
	total.Moves += len(job.Records)
	total.Valid += valid
	total.Invalid += invalid
	total.Loss += lossTotal
	return out.String()
}

type GamePlayer struct {
	Spec                                                              PlayerSpec
	Rack                                                              string
	Score, Adjust, Total, Plays, Bingos, Exchanges, Passes, Top, Loss int
}

func subtractCollection(a, b string) string {
	counts, remove := collectionCounts(a), collectionCounts(b)
	for i := range counts {
		counts[i] -= remove[i]
	}
	return countsString(counts)
}
func signed(value int) string {
	if value > 0 {
		return fmt.Sprintf("+%d", value)
	}
	return fmt.Sprint(value)
}
func reportGame(job Job, tiles Tiles, trie Trie, total *GameTotals) string {
	var out strings.Builder
	line(&out,
		"GAME %s seed=%d players=%d", job.Header[1], job.Seed, len(job.Players))
	players := make([]GamePlayer,
		len(job.Players))
	generator := Generator{int64(job.Seed)}
	bag := newBag(tiles, &generator)
	for i, spec := range job.Players {
		players[i] = GamePlayer{Spec: spec,
			Rack: draw(&bag, rackSize)}
		line(&out, "player %d %s strategy=%s threshold=%d", i+1, spec.Name, spec.Strategy,
			spec.Threshold)
	}
	board := newBoard()
	scoreless, turn, goingOut := 0, 0, -1
	reason := ""
	highlightTurn, highlightPlayer := -1,
		-1
	var highlight Move
	for {
		turn++
		index := (turn - 1) % len(players)
		player := &players[index]
		rack := player.Rack
		moves := legalMoves(board,
			rack, tiles, trie)
		fmt.Fprintf(&out, "turn %d %s rack=%s moves=%d", turn, player.Spec.Name, notation(rack),
			len(moves))
		var candidate Move
		hasCandidate := len(moves) > 0
		if hasCandidate {
			candidate = orderedMoves(moves,
				player.Spec.Strategy)[0]
		}
		if hasCandidate && !(candidate.Score < player.Spec.Threshold && len(bag) >= 7) {
			best := moves[0].Score
			play(&board,
				candidate)
			player.Score += candidate.Score
			player.Plays++
			player.Top = max(player.Top, candidate.Score)
			player.Loss += best - candidate.Score
			if candidate.Tiles == 7 {
				player.Bingos++
			}
			drawn := draw(&bag,
				rackSize-len(candidate.Leave))
			player.Rack = candidate.Leave + drawn
			scoreless = 0
			fmt.Fprintf(&out,
				" best=%d play %s score=%d total=%d draw=%s bag=%d\n", best, moveName(candidate), candidate.Score,
				player.Score, notation(drawn), len(bag))
			if highlightTurn < 0 || candidate.Score > highlight.Score {
				highlightTurn,
					highlightPlayer, highlight = turn, index, candidate
			}
			if player.Rack == "" && len(bag) == 0 {
				reason = "out"
				goingOut = index
				break
			}
		} else if len(bag) >= 7 {
			keep,
				_ := bestLeave(rack, tiles)
			putBack := subtractCollection(rack, keep)
			drawn := exchange(&bag, putBack,
				&generator)
			player.Rack = keep + drawn
			player.Exchanges++
			scoreless++
			fmt.Fprintf(&out, " exchange keep=%s draw=%s bag=%d\n",
				notation(keep), notation(drawn), len(bag))
		} else {
			player.Passes++
			scoreless++
			fmt.Fprintf(&out, " pass bag=%d\n",
				len(bag))
		}
		if scoreless == 6 {
			reason = "scoreless"
			break
		}
	}
	if reason == "out" {
		line(&out, "end reason=out player=%s turns=%d",
			players[goingOut].Spec.Name, turn)
	} else {
		line(&out, "end reason=scoreless turns=%d", turn)
	}
	for i := range players {
		if i != goingOut {
			value := collectionValue(players[i].Rack,
				tiles)
			players[i].Adjust = -value
			if goingOut >= 0 {
				players[goingOut].Adjust += value
			}
		}
	}
	for i := range players {
		p := &players[i]
		p.Total = p.Score + p.Adjust
		line(&out,
			"final %s score=%d rack=%s adjust=%s total=%d", p.Spec.Name, p.Score, notation(p.Rack), signed(p.Adjust),
			p.Total)
		total.Plays += p.Plays
		total.Exchanges += p.Exchanges
		total.Passes += p.Passes
		total.Bingos += p.Bingos
	}
	standing := make([]int,
		len(players))
	for i := range standing {
		standing[i] = i
	}
	sort.SliceStable(standing, func(i, j int) bool { return players[standing[i]].Total > players[standing[j]].Total })
	for rank, index := range standing {
		p := players[index]
		line(&out, "standing %d %s total=%d plays=%d bingos=%d exchanges=%d passes=%d top=%d loss=%d",
			rank+1, p.Spec.Name, p.Total, p.Plays, p.Bingos, p.Exchanges, p.Passes, p.Top, p.Loss)
	}
	bestTotal := players[standing[0]].Total
	var winners []string
	for _, p := range players {
		if p.Total == bestTotal {
			winners = append(winners, p.Spec.Name)
		}
	}
	line(&out, "winner %s",
		strings.Join(winners, ","))
	if highlightTurn >= 0 {
		line(&out, "highlight turn=%d player=%s play %s score=%d",
			highlightTurn, players[highlightPlayer].Spec.Name, moveName(highlight), highlight.Score)
	}
	boardReport(&out,
		board)
	total.Turns += turn
	return out.String()
}
func reportDuplicate(job Job, tiles Tiles, trie Trie, total *GameTotals) string {
	var out strings.Builder
	line(&out,
		"DUPLICATE %s seed=%d players=%d", job.Header[1], job.Seed, len(job.Players))
	for i, p := range job.Players {
		line(&out,
			"player %d %s strategy=%s", i+1, p.Name, p.Strategy)
	}
	generator := Generator{int64(job.Seed)}
	bag := newBag(tiles,
		&generator)
	rack := draw(&bag, rackSize)
	board := newBoard()
	totals := make([]int, len(job.Players))
	masterTotal,
		round := 0, 0
	reason := "stuck"
	for {
		moves := legalMoves(board, rack, tiles, trie)
		if len(moves) == 0 {
			reason = "stuck"
			break
		}
		round++
		master := moves[0]
		picks := make([]string,
			len(job.Players))
		for i, p := range job.Players {
			choice := orderedMoves(moves, p.Strategy)[0]
			totals[i] += choice.Score
			picks[i] = fmt.Sprint(choice.Score)
		}
		masterTotal += master.Score
		line(&out,
			"round %d rack=%s moves=%d master %s score=%d picks=%s", round, notation(rack), len(moves), moveName(master),
			master.Score, strings.Join(picks, ","))
		play(&board, master)
		rack = master.Leave + draw(&bag, rackSize-len(master.Leave))
		if rack == "" {
			reason = "out"
			break
		}
	}
	if reason == "out" {
		line(&out,
			"end reason=out rounds=%d", round)
	} else {
		line(&out, "end reason=stuck rounds=%d rack=%s", round, notation(rack))
	}
	line(&out,
		"master total=%d", masterTotal)
	best := totals[0]
	for _, value := range totals {
		best = max(best, value)
	}
	var winners []string
	for i, p := range job.Players {
		percentage := 0
		if masterTotal >= 1 {
			percentage = 100 * totals[i] / masterTotal
		}
		line(&out,
			"final %s total=%d percent=%d", p.Name, totals[i], percentage)
		if totals[i] == best {
			winners = append(winners,
				p.Name)
		}
	}
	line(&out, "winner %s", strings.Join(winners, ","))
	boardReport(&out, board)
	total.Rounds += round
	return out.String()
}
func paragraph(s string) string { return strings.TrimSuffix(s, "\n") }
func writeParagraphs(path string, paragraphs []string) {
	must(os.WriteFile(path, []byte(strings.Join(paragraphs, "\n\n")+"\n"), 0644))
}
func main() {
	tiles, trie, stats, jobs := readData()
	var dictionary strings.Builder
	line(&dictionary, "DICTIONARY lines=%d words=%d skipped=%d duplicates=%d nodes=%d",
		stats.Lines, trie.Words, stats.Skipped, stats.Duplicates, len(trie.Nodes))
	parts := []string{"lengths"}
	for length, count := range stats.Lengths {
		if count > 0 {
			parts = append(parts, fmt.Sprintf("%d=%d", length, count))
		}
	}
	line(&dictionary,
		strings.Join(parts, " "))
	movesParagraphs := []string{paragraph(dictionary.String())}
	var validationParagraphs,
		gameParagraphs []string
	var topTotals TopTotals
	var validationTotals ValidationTotals
	var gameTotals GameTotals
	seen := map[string]bool{}
	for _, inputJob := range jobs {
		job := inputJob
		kind, name := job.Header[0], job.Header[1]
		switch kind {
		case "TOPN":
			topTotals.Jobs++
		case "VALIDATE":
			validationTotals.Jobs++
		case "GAME":
			gameTotals.Games++
		case "DUPLICATE":
			gameTotals.Duplicates++
		}
		reason := checkJob(&job,
			seen, tiles, trie)
		if reason != "" {
			error := kind + " " + name + "\nerror " + reason
			switch kind {
			case "TOPN":
				topTotals.Errors++
				movesParagraphs = append(movesParagraphs,
					error)
			case "VALIDATE":
				validationTotals.Errors++
				validationParagraphs = append(validationParagraphs,
					error)
			default:
				gameTotals.Errors++
				gameParagraphs = append(gameParagraphs, error)
			}
			continue
		}
		switch kind {
		case "TOPN":
			movesParagraphs = append(movesParagraphs,
				paragraph(reportTop(job, tiles, trie, &topTotals)))
		case "VALIDATE":
			validationParagraphs = append(validationParagraphs,
				paragraph(reportValidation(job, tiles, trie, &validationTotals)))
		case "GAME":
			gameParagraphs = append(gameParagraphs,
				paragraph(reportGame(job, tiles, trie, &gameTotals)))
		case "DUPLICATE":
			gameParagraphs = append(gameParagraphs,
				paragraph(reportDuplicate(job, tiles, trie, &gameTotals)))
		}
	}
	movesParagraphs = append(movesParagraphs,
		fmt.Sprintf("SUMMARY jobs=%d errors=%d moves=%d bingos=%d", topTotals.Jobs, topTotals.Errors, topTotals.Moves,
			topTotals.Bingos))
	validationParagraphs = append(validationParagraphs, fmt.Sprintf("SUMMARY jobs=%d errors=%d moves=%d valid=%d invalid=%d loss=%d",
		validationTotals.Jobs, validationTotals.Errors, validationTotals.Moves, validationTotals.Valid, validationTotals.Invalid,
		validationTotals.Loss))
	gameParagraphs = append(gameParagraphs, fmt.Sprintf("SUMMARY games=%d duplicates=%d errors=%d turns=%d rounds=%d plays=%d exchanges=%d passes=%d bingos=%d",
		gameTotals.Games, gameTotals.Duplicates, gameTotals.Errors, gameTotals.Turns, gameTotals.Rounds, gameTotals.Plays,
		gameTotals.Exchanges, gameTotals.Passes, gameTotals.Bingos))
	must(os.MkdirAll("output", 0755))
	writeParagraphs("output/moves.txt",
		movesParagraphs)
	writeParagraphs("output/validation.txt", validationParagraphs)
	writeParagraphs("output/game.txt",
		gameParagraphs)
}
