package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type MailLine struct {
	Number int
	Text   string
}
type Entity struct {
	Number, MainType, Subtype string
	Parameters                map[string]string
	Disposition, Filename     string
	Split                     bool
	Children                  []*Entity
	Content                   string
}
type Message struct {
	Number               int
	Problems             []string
	Sender               *Mailbox
	To, Cc               []string
	Subject, BaseSubject string
	Reply                bool
	Date                 int64
	DateValid            bool
	ID                   string
	References           []string
	Body                 *Entity
	Thread, Depth        int
	Parent               *Message
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	lines := strings.Split(string(data), "\n")
	if len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}
func readMailbox(path string) [][]MailLine {
	messages := [][]MailLine{}
	for i, line := range readLines(path) {
		if strings.HasPrefix(line, "From ") {
			messages = append(messages, []MailLine{})
			continue
		}
		unquoted := strings.TrimLeft(line, ">")
		if unquoted != line && strings.HasPrefix(unquoted, "From ") {
			line = line[1:]
		}
		if len(messages) > 0 {
			last := len(messages) - 1
			messages[last] = append(messages[last], MailLine{i + 1, line})
		}
	}
	for i, lines := range messages {
		if len(lines) > 0 && lines[len(lines)-1].Text == "" {
			messages[i] = lines[:len(lines)-1]
		}
	}
	return messages
}
func splitSections(lines []MailLine) ([]MailLine, []MailLine) {
	for i, line := range lines {
		if line.Text == "" {
			return lines[:i], lines[i+1:]
		}
	}
	return lines, nil
}
func isMessageID(text string) bool {
	if len(text) < 3 || text[0] != '<' || text[len(text)-1] != '>' {
		return false
	}
	inside := text[1 : len(text)-1]
	if strings.Count(inside, "@") != 1 || inside[0] == '@' || inside[len(inside)-1] == '@' {
		return false
	}
	for i := 0; i < len(inside); i++ {
		if inside[i] < 33 || inside[i] > 126 || strings.ContainsRune("<>()\"\\", rune(inside[i])) {
			return false
		}
	}
	return true
}
func extractIDs(value string) []string {
	ids := []string{}
	for position := 0; position < len(value); {
		start := strings.IndexByte(value[position:], '<')
		if start < 0 {
			break
		}
		start += position
		end := strings.IndexByte(value[start+1:], '>')
		if end < 0 {
			break
		}
		end += start + 1
		if isMessageID(value[start : end+1]) {
			ids = append(ids, value[start:end+1])
		}
		position = end + 1
	}
	return ids
}
func dateNotation(message *Message) string {
	if !message.DateValid {
		return "invalid"
	}
	return formatUTC(message.Date)
}
func subjectNotation(subject string) string {
	if subject == "" {
		return "(no subject)"
	}
	return subject
}
func (m *Message) problem(text string) { m.Problems = append(m.Problems, text) }
func (m *Message) process(lines []MailLine, knownIDs map[string]int) {
	headerLines, bodyLines := splitSections(lines)
	header := parseFields(headerLines)
	for _, number := range header.Invalid {
		m.problem(fmt.Sprintf("bad header line %d", number))
	}
	for _, name := range []string{"From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"} {
		if header.Count(name) > 1 {
			m.problem("duplicate " + name)
		}
	}
	value, present := header.Value("From")
	if !present {
		m.problem("missing From")
	} else {
		addresses, failed, ok := parseAddressList(value)
		if !ok || len(addresses) != 1 || addresses[0].Mailbox == nil {
			m.problem("bad From")
		} else {
			m.Sender = addresses[0].Mailbox
			if failed {
				m.problem("bad encoded word in From")
			}
		}
	}
	m.To = m.recipients(header, "To")
	m.Cc = m.recipients(header, "Cc")
	value, _ = header.Value("Subject")
	var failed bool
	m.Subject, failed = decodeUnstructured(value)
	if failed {
		m.problem("bad encoded word in Subject")
	}
	m.BaseSubject = m.Subject
	for len(m.BaseSubject) >= 3 && strings.ToLower(m.BaseSubject[:3]) == "re:" {
		m.BaseSubject = strings.TrimLeft(m.BaseSubject[3:], " ")
		m.Reply = true
	}
	value, present = header.Value("Date")
	if !present {
		m.problem("missing Date")
	} else {
		seconds, problem := parseDate(value)
		if problem != "" {
			m.problem(problem)
		} else {
			m.Date = seconds
			m.DateValid = true
		}
	}
	value, present = header.Value("Message-ID")
	if !present {
		m.problem("missing Message-ID")
	} else if !isMessageID(value) {
		m.problem("bad Message-ID")
	} else if earlier, exists := knownIDs[value]; exists {
		m.problem(fmt.Sprintf("Message-ID already used by message %d", earlier))
	} else {
		m.ID = value
		knownIDs[value] = m.Number
	}
	value, _ = header.Value("References")
	m.References = extractIDs(value)
	value, _ = header.Value("In-Reply-To")
	replies := extractIDs(value)
	if len(replies) > 0 && (len(m.References) == 0 || m.References[len(m.References)-1] != replies[0]) {
		m.References = append(m.References, replies[0])
	}
	mime := false
	value, present = header.Value("MIME-Version")
	if present {
		text, ok := removeComments(value)
		mime = ok && strings.NewReplacer(" ", "", "\t", "").Replace(text) == "1.0"
		if !mime {
			m.problem("bad MIME-Version")
		}
	}
	m.Body = m.parseEntity("1", header, bodyLines, mime)
}
func (m *Message) recipients(header Header, name string) []string {
	value, present := header.Value(name)
	result := []string{}
	if !present {
		return result
	}
	addresses, failed, ok := parseAddressList(value)
	if !ok {
		m.problem("bad " + name)
		return result
	}
	for _, address := range addresses {
		if address.Mailbox != nil {
			result = append(result, address.Mailbox.Address)
		} else {
			for _, mailbox := range address.Group {
				result = append(result, mailbox.Address)
			}
		}
	}
	if failed {
		m.problem("bad encoded word in " + name)
	}
	return result
}
func (m *Message) parseEntity(number string, header Header, lines []MailLine, mime bool) *Entity {
	entity := &Entity{Number: number, MainType: "text", Subtype: "plain", Parameters: map[string]string{}}
	if value, present := header.Value("Content-Type"); mime && present {
		parsed, ok := parseParameters(value, true)
		if !ok {
			m.problem("bad Content-Type in part " + number)
		} else {
			entity.MainType = parsed.MainType
			entity.Subtype = parsed.Subtype
			entity.Parameters = parsed.Values
		}
	}
	if value, present := header.Value("Content-Disposition"); mime && present {
		parsed, ok := parseParameters(value, false)
		if !ok {
			m.problem("bad Content-Disposition in part " + number)
		} else {
			entity.Disposition = parsed.MainType
			entity.Filename = parsed.Values["filename"]
		}
	}
	if entity.Filename == "" {
		entity.Filename = entity.Parameters["name"]
	}
	if charset, present := entity.Parameters["charset"]; entity.MainType == "text" && present && strings.ToLower(charset) != "us-ascii" {
		m.problem("unsupported charset \"" + strings.ToLower(charset) + "\" in part " + number)
	}
	if mime && entity.MainType == "multipart" {
		boundary := entity.Parameters["boundary"]
		if boundary != "" {
			m.splitMultipart(entity, lines, boundary)
			return entity
		}
		m.problem("missing boundary in part " + number)
	}
	body := make([]string, len(lines))
	for i, line := range lines {
		body[i] = line.Text
	}
	original := strings.Join(body, "\n")
	encoding := "7bit"
	if value, present := header.Value("Content-Transfer-Encoding"); mime && present {
		encoding = strings.ToLower(value)
	}
	switch encoding {
	case "base64":
		content, ok := decodeBase64Body(original)
		if !ok {
			m.problem("bad base64 in part " + number)
		}
		entity.Content = content
	case "quoted-printable":
		content, failed := decodeQuotedPrintable(original)
		if failed {
			m.problem("bad quoted-printable in part " + number)
		}
		entity.Content = content
	default:
		entity.Content = original
		if encoding != "7bit" && encoding != "8bit" && encoding != "binary" {
			m.problem("unknown encoding \"" + encoding + "\" in part " + number)
		}
	}
	return entity
}
func (m *Message) splitMultipart(entity *Entity, lines []MailLine, boundary string) {
	parts := [][]MailLine{}
	closed := false
	for _, line := range lines {
		text := strings.TrimRight(line.Text, whitespace)
		if text == "--"+boundary+"--" {
			closed = true
			break
		}
		if text == "--"+boundary {
			parts = append(parts, []MailLine{})
		} else if len(parts) > 0 {
			i := len(parts) - 1
			parts[i] = append(parts[i], line)
		}
	}
	if len(parts) == 0 {
		m.problem("no parts in part " + entity.Number)
	} else if !closed {
		m.problem("unterminated multipart in part " + entity.Number)
	}
	entity.Split = true
	for i, part := range parts {
		headerLines, bodyLines := splitSections(part)
		header := parseFields(headerLines)
		for _, number := range header.Invalid {
			m.problem(fmt.Sprintf("bad header line %d", number))
		}
		entity.Children = append(entity.Children, m.parseEntity(fmt.Sprintf("%s.%d", entity.Number, i+1), header, bodyLines, true))
	}
}
func collectTextParts(entity *Entity, allowHTML bool) []*Entity {
	if !entity.Split {
		if entity.Disposition == "attachment" || entity.MainType != "text" {
			return nil
		}
		if entity.Subtype == "plain" || entity.Subtype == "html" && allowHTML {
			return []*Entity{entity}
		}
		return nil
	}
	if entity.Subtype == "alternative" {
		for _, html := range []bool{false, true} {
			for _, child := range entity.Children {
				if parts := collectTextParts(child, html); len(parts) > 0 {
					return parts
				}
			}
		}
		return nil
	}
	parts := []*Entity{}
	for _, child := range entity.Children {
		parts = append(parts, collectTextParts(child, allowHTML)...)
	}
	return parts
}

type LogicalLine struct {
	Depth   int
	Text    string
	Flowing bool
}

func quotePrefix(depth int) string {
	if depth == 0 {
		return ""
	}
	return strings.Repeat(">", depth) + " "
}
func wrap(text, prefix string) []string {
	lines := []string{}
	current := ""
	for _, word := range splitWords(text) {
		if current != "" && len(current)+1+len(word) > 72 {
			lines = append(lines, prefix+current)
			current = word
		} else if current != "" {
			current += " " + word
		} else {
			current = word
		}
	}
	return append(lines, prefix+current)
}
func flowedLines(content string, deleteSpace bool) []string {
	if content == "" {
		return nil
	}
	logical := []LogicalLine{}
	for _, line := range strings.Split(content, "\n") {
		text := strings.TrimLeft(line, ">")
		depth := len(line) - len(text)
		if strings.HasPrefix(text, " ") {
			text = text[1:]
		}
		flowing := strings.HasSuffix(text, " ") && text != "-- "
		if len(logical) > 0 && logical[len(logical)-1].Flowing && logical[len(logical)-1].Depth == depth {
			previous := &logical[len(logical)-1]
			if deleteSpace {
				previous.Text = previous.Text[:len(previous.Text)-1]
			}
			previous.Text += text
			previous.Flowing = flowing
		} else {
			logical = append(logical, LogicalLine{depth, text, flowing})
		}
	}
	lines := []string{}
	for _, line := range logical {
		lines = append(lines, wrap(line.Text, quotePrefix(line.Depth))...)
	}
	return lines
}
func tagName(text string) string {
	end := 0
	for end < len(text) && (text[end] >= 'A' && text[end] <= 'Z' || text[end] >= 'a' && text[end] <= 'z' || text[end] >= '0' && text[end] <= '9') {
		end++
	}
	return strings.ToLower(text[:end])
}
func replaceReferences(text string) string {
	names := map[string]string{"amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "}
	var result strings.Builder
	for position := 0; position < len(text); {
		replacement, found, end := "", false, -1
		if text[position] == '&' {
			end = strings.IndexByte(text[position+1:], ';')
			if end >= 0 {
				end += position + 1
				name := text[position+1 : end]
				replacement, found = names[name]
				if !found && strings.HasPrefix(name, "#") && digits(name[1:], 1, 2, 3) {
					value := decimal(name[1:])
					if value >= 32 && value <= 126 {
						replacement = string(byte(value))
						found = true
					}
				}
			}
		}
		if found {
			result.WriteString(replacement)
			position = end + 1
		} else {
			result.WriteByte(text[position])
			position++
		}
	}
	return result.String()
}
func htmlLines(content string) []string {
	blocks := []LogicalLine{}
	depth, position := 0, 0
	text, hide := "", ""
	for position < len(content) {
		close := -1
		if content[position] == '<' {
			close = strings.IndexByte(content[position+1:], '>')
			if close >= 0 {
				close += position + 1
			}
		}
		if close < 0 {
			if hide == "" {
				text += content[position : position+1]
			}
			position++
			continue
		}
		inside := content[position+1 : close]
		position = close + 1
		endTag := strings.HasPrefix(inside, "/")
		if endTag {
			inside = inside[1:]
		}
		name := tagName(inside)
		if hide != "" {
			if endTag && name == hide {
				hide = ""
			}
		} else if !endTag && (name == "head" || name == "style" || name == "script") {
			hide = name
		} else if name == "br" || name == "li" && !endTag {
			blocks = append(blocks, LogicalLine{Depth: depth, Text: text})
			text = ""
			if name == "li" {
				text = "* "
			}
		} else if stringIndex([]string{"p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"}, name) >= 0 {
			blocks = append(blocks, LogicalLine{Depth: depth, Text: text}, LogicalLine{Depth: depth})
			text = ""
			if name == "blockquote" {
				if !endTag {
					depth++
				} else if depth > 0 {
					depth--
				}
			}
		}
	}
	blocks = append(blocks, LogicalLine{Depth: depth, Text: text})
	lines := []string{}
	for _, block := range blocks {
		text = collapseWhitespace(strings.ReplaceAll(block.Text, "\n", " "))
		text = strings.Trim(replaceReferences(text), " ")
		if text != "" {
			lines = append(lines, wrap(text, quotePrefix(block.Depth))...)
		} else if len(lines) > 0 && lines[len(lines)-1] != "" {
			lines = append(lines, "")
		}
	}
	for len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}
func displayLines(entity *Entity) (string, []string) {
	if entity.Subtype == "html" {
		return "html", htmlLines(entity.Content)
	}
	if strings.ToLower(entity.Parameters["format"]) == "flowed" {
		return "flowed", flowedLines(entity.Content, strings.ToLower(entity.Parameters["delsp"]) == "yes")
	}
	if entity.Content == "" {
		return "plain", nil
	}
	return "plain", strings.Split(entity.Content, "\n")
}

type ThreadEntry struct {
	Container *Container
	Prefix    string
	Depth     int
}
type Thread struct {
	Number   int
	Root     *Container
	Entries  []ThreadEntry
	Messages []*Message
}

func makeThread(number int, root *Container) *Thread {
	thread := &Thread{Number: number, Root: root}
	var walk func(*Container, string, string, int)
	walk = func(container *Container, prefix, stem string, depth int) {
		thread.Entries = append(thread.Entries, ThreadEntry{container, prefix, depth})
		if container.Message != nil {
			message := container.Message
			thread.Messages = append(thread.Messages, message)
			message.Thread = number
			message.Depth = depth
			if container.Parent != nil {
				message.Parent = container.Parent.Message
			}
		}
		for i, child := range container.Children {
			if i < len(container.Children)-1 {
				walk(child, stem+"+- ", stem+"|  ", depth+1)
			} else {
				walk(child, stem+"`- ", stem+"   ", depth+1)
			}
		}
	}
	walk(root, "", "", 0)
	return thread
}
func containerNotation(container *Container) string {
	if container.Message != nil {
		message := container.Message
		sender := "-"
		if message.Sender != nil {
			sender = message.Sender.Address
		}
		return fmt.Sprintf("[%d] %s %s %s", message.Number, dateNotation(message), sender, subjectNotation(message.Subject))
	}
	if container.Subject != "" {
		return "[subject] " + container.Subject
	}
	return "[missing] " + container.ID
}
func (t *Thread) report() []string {
	depth := 0
	senders := map[string]bool{}
	dates := []int64{}
	for _, entry := range t.Entries {
		if entry.Depth > depth {
			depth = entry.Depth
		}
	}
	for _, message := range t.Messages {
		if message.Sender != nil {
			senders[message.Sender.Address] = true
		}
		if message.DateValid {
			dates = append(dates, message.Date)
		}
	}
	lines := []string{fmt.Sprintf("thread %d messages %d depth %d senders %d", t.Number, len(t.Messages), depth, len(senders))}
	if len(dates) > 0 {
		first, last := dates[0], dates[0]
		for _, date := range dates[1:] {
			if date < first {
				first = date
			}
			if date > last {
				last = date
			}
		}
		lines = append(lines, "span "+formatUTC(first)+" .. "+formatUTC(last))
	} else {
		lines = append(lines, "span -")
	}
	subject := t.Root.Subject
	if subject == "" {
		subject = rootSubject(t.Root)
	}
	lines = append(lines, "subject "+subjectNotation(subject))
	for _, entry := range t.Entries {
		lines = append(lines, entry.Prefix+containerNotation(entry.Container))
	}
	return lines
}
func senderNotation(sender *Mailbox) string {
	if sender == nil {
		return "-"
	}
	if sender.Name != "" {
		return sender.Name + " <" + sender.Address + ">"
	}
	return sender.Address
}
func entityLines(entity *Entity) []string {
	line := "part " + entity.Number + " " + entity.MainType + "/" + entity.Subtype
	if entity.Split {
		lines := []string{line}
		for _, child := range entity.Children {
			lines = append(lines, entityLines(child)...)
		}
		return lines
	}
	line += fmt.Sprintf(" %d", len(entity.Content))
	if entity.Disposition != "" {
		line += " " + entity.Disposition
	}
	if entity.Filename != "" {
		line += " \"" + entity.Filename + "\""
	}
	return []string{line}
}
func dash(text string) string {
	if text == "" {
		return "-"
	}
	return text
}
func messageReport(message *Message) []string {
	parent := "-"
	if message.Parent != nil {
		parent = strconv.Itoa(message.Parent.Number)
	}
	lines := []string{fmt.Sprintf("message %d", message.Number), "id " + dash(message.ID), "date " + dateNotation(message), "from " + senderNotation(message.Sender), "to " + dash(strings.Join(message.To, ", ")), "cc " + dash(strings.Join(message.Cc, ", ")), "subject " + subjectNotation(message.Subject), "refs " + dash(strings.Join(message.References, " ")), fmt.Sprintf("thread %d depth %d parent %s", message.Thread, message.Depth, parent)}
	return append(lines, entityLines(message.Body)...)
}
func bodyReport(request string, messages map[string]*Message) []string {
	lines := []string{"request " + request}
	message := messages[request]
	if message == nil {
		return append(lines, "not found")
	}
	parts := collectTextParts(message.Body, true)
	lines = append(lines, fmt.Sprintf("message %d text parts %d", message.Number, len(parts)))
	for _, part := range parts {
		format, display := displayLines(part)
		quoted, signature := 0, 0
		for i, line := range display {
			line = strings.TrimRight(line, whitespace)
			if strings.HasPrefix(line, ">") {
				quoted++
			}
			if line == "--" {
				signature = len(display) - i - 1
			}
		}
		lines = append(lines, fmt.Sprintf("part %s %s lines %d quoted %d signature %d", part.Number, format, len(display), quoted, signature))
		for _, line := range display {
			line = strings.TrimRight(line, whitespace)
			if line == "" {
				lines = append(lines, "|")
			} else {
				lines = append(lines, "| "+line)
			}
		}
	}
	return lines
}

type SenderStats struct {
	Address, Name string
	Count         int
	Threads       map[int]bool
	First, Last   int64
	HasDate       bool
}

func csvField(text string) string {
	if strings.ContainsAny(text, ",\"") {
		return "\"" + strings.ReplaceAll(text, "\"", "\"\"") + "\""
	}
	return text
}
func sendersReport(messages []*Message) []string {
	stats := map[string]*SenderStats{}
	for _, message := range messages {
		if message.Sender == nil {
			continue
		}
		address := message.Sender.Address
		entry := stats[address]
		if entry == nil {
			entry = &SenderStats{Address: address, Threads: map[int]bool{}}
			stats[address] = entry
		}
		entry.Count++
		entry.Threads[message.Thread] = true
		if message.DateValid {
			if !entry.HasDate || message.Date < entry.First {
				entry.First = message.Date
			}
			if !entry.HasDate || message.Date > entry.Last {
				entry.Last = message.Date
			}
			entry.HasDate = true
		}
		if message.Sender.Name != "" {
			entry.Name = message.Sender.Name
		}
	}
	entries := []*SenderStats{}
	for _, entry := range stats {
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Count != entries[j].Count {
			return entries[i].Count > entries[j].Count
		}
		return entries[i].Address < entries[j].Address
	})
	lines := []string{"address,name,messages,threads,first,last"}
	for _, entry := range entries {
		first, last := "-", "-"
		if entry.HasDate {
			first = formatUTC(entry.First)
			last = formatUTC(entry.Last)
		}
		lines = append(lines, fmt.Sprintf("%s,%s,%d,%d,%s,%s", entry.Address, csvField(entry.Name), entry.Count, len(entry.Threads), first, last))
	}
	return lines
}
func malformedReport(messages []*Message) []string {
	flagged, total := 0, 0
	for _, message := range messages {
		if len(message.Problems) > 0 {
			flagged++
		}
		total += len(message.Problems)
	}
	lines := []string{fmt.Sprintf("messages %d malformed %d problems %d", len(messages), flagged, total)}
	for _, message := range messages {
		for _, problem := range message.Problems {
			lines = append(lines, fmt.Sprintf("message %d: %s", message.Number, problem))
		}
	}
	return lines
}
func joinBlocks(blocks [][]string) []string {
	lines := []string{}
	for _, block := range blocks {
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, block...)
	}
	return lines
}
func writeOutput(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func main() {
	messages := []*Message{}
	knownIDs := map[string]int{}
	for i, lines := range readMailbox("input/mailbox.mbox") {
		message := &Message{Number: i + 1}
		message.process(lines, knownIDs)
		messages = append(messages, message)
	}
	threads := []*Thread{}
	for i, root := range buildThreads(messages) {
		threads = append(threads, makeThread(i+1, root))
	}
	for _, message := range messages {
		parent := message.Parent
		if parent != nil && message.DateValid && parent.DateValid && message.Date < parent.Date {
			message.problem(fmt.Sprintf("dated before parent message %d", parent.Number))
		}
	}
	byID := map[string]*Message{}
	for _, message := range messages {
		if message.ID != "" {
			byID[message.ID] = message
		}
	}
	threadBlocks, messageBlocks, bodyBlocks := [][]string{}, [][]string{}, [][]string{}
	for _, thread := range threads {
		threadBlocks = append(threadBlocks, thread.report())
	}
	for _, message := range messages {
		messageBlocks = append(messageBlocks, messageReport(message))
	}
	for _, request := range readLines("input/requests.txt") {
		bodyBlocks = append(bodyBlocks, bodyReport(request, byID))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeOutput("threads.txt", joinBlocks(threadBlocks))
	writeOutput("messages.txt", joinBlocks(messageBlocks))
	writeOutput("bodies.txt", joinBlocks(bodyBlocks))
	writeOutput("senders.csv", sendersReport(messages))
	writeOutput("malformed.txt", malformedReport(messages))
}
