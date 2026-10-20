package main

import (
	"bufio"
	"cmp"
	"fmt"
	"io"
	"maps"
	"os"
	"slices"
	"strconv"
	"strings"
)

type nodeKind int

const (
	directory nodeKind = iota
	regularFile
	symbolicLink
)

type node struct {
	kind            nodeKind
	inode, modified int
	parent          *node
	name            string
	entries         map[string]*node
	lines           []string
	target          string
}

func (n *node) size() int64 {
	switch n.kind {
	case directory:
		return int64(len(n.entries))
	case symbolicLink:
		return int64(len(n.target))
	default:
		var size int64
		for _, line := range n.lines {
			size += int64(len(line)) + 1
		}
		return size
	}
}

func (n *node) links() int {
	if n.kind != directory {
		return 1
	}
	count := 2
	for _, child := range n.entries {
		if child.kind == directory {
			count++
		}
	}
	return count
}

func (n *node) tag() byte { return "dfl"[n.kind] }
func (n *node) names() []string { return slices.Sorted(maps.Keys(n.entries)) }

type failure int

const (
	resolved failure = iota
	missing
	notDirectory
	tooManyLinks
)

type resolution struct {
	node, creationParent *node
	creationName         string
	failure              failure
}

func (r resolution) reason() string {
	switch r.failure {
	case missing:
		return "No such file or directory"
	case notDirectory:
		return "Not a directory"
	case tooManyLinks:
		return "Too many levels of symbolic links"
	default:
		return ""
	}
}

type output struct {
	terminal io.Writer
	direct   bool
	lines    []string
}

func (o *output) emit(line string) {
	if o.direct {
		fmt.Fprintln(o.terminal, line)
	} else {
		o.lines = append(o.lines, line)
	}
}

func (o *output) print(format string, args ...any) { o.emit(fmt.Sprintf(format, args...)) }
func (o *output) error(format string, args ...any) { fmt.Fprintf(o.terminal, format+"\n", args...) }

type options struct {
	flags [128]bool
	paths []string
}

func parseOptions(args []string) options {
	var result options
	position := 0
	for position < len(args) && strings.HasPrefix(args[position], "-") {
		for i := 1; i < len(args[position]); i++ {
			result.flags[args[position][i]] = true
		}
		position++
	}
	result.paths = args[position:]
	return result
}

func lastComponent(path string) string { return path[strings.LastIndexByte(path, '/')+1:] }
func invalidSource(path string) bool {
	name := lastComponent(path)
	return name == "" || name == "." || name == ".."
}

func joinPath(path, name string) string {
	if path == "/" {
		return "/" + name
	}
	return path + "/" + name
}

type shell struct {
	root, current    *node
	previous         *string
	clock, nextInode  int
}

func newShell() *shell {
	root := &node{kind: directory, inode: 1, entries: make(map[string]*node)}
	root.parent = root
	return &shell{root: root, current: root, nextInode: 2}
}

func (s *shell) absolute(n *node) string {
	var names []string
	for n != s.root {
		names = append(names, n.name)
		n = n.parent
	}
	slices.Reverse(names)
	return "/" + strings.Join(names, "/")
}

func (s *shell) descendant(n, ancestor *node) bool {
	for {
		if n == ancestor {
			return true
		}
		if n == s.root {
			return false
		}
		n = n.parent
	}
}

func (s *shell) add(parent *node, name string, n *node) {
	parent.entries[name] = n
	parent.modified = s.clock
	n.parent, n.name = parent, name
}

func (s *shell) create(parent *node, name string, kind nodeKind, target string) *node {
	n := &node{kind: kind, inode: s.nextInode, modified: s.clock, target: target}
	s.nextInode++
	if kind == directory {
		n.entries = make(map[string]*node)
	}
	s.add(parent, name, n)
	return n
}

func (s *shell) detach(n *node) {
	delete(n.parent.entries, n.name)
	n.parent.modified = s.clock
}

func (s *shell) write(file *node, lines []string, appendMode bool) {
	if appendMode {
		file.lines = append(file.lines, lines...)
	} else {
		file.lines = slices.Clone(lines)
	}
	file.modified = s.clock
}

func (s *shell) resolve(path string, follow, parents bool) resolution {
	expansions := 0
	var walk func(string, *node, bool, bool) resolution
	walk = func(path string, base *node, follow, original bool) resolution {
		n := base
		if strings.HasPrefix(path, "/") {
			n = s.root
		}
		parts := strings.Split(path, "/")
		for i, name := range parts {
			if name == "" {
				continue
			}
			if n.kind != directory {
				return resolution{failure: notDirectory}
			}
			if name == "." {
				continue
			}
			if name == ".." {
				n = n.parent
				continue
			}
			last := i+1 == len(parts)
			child := n.entries[name]
			if child == nil {
				if original && parents && !last {
					child = s.create(n, name, directory, "")
				} else {
					result := resolution{failure: missing}
					if original && last {
						result.creationParent, result.creationName = n, name
					}
					return result
				}
			}
			if child.kind == symbolicLink && (!last || follow) {
				expansions++
				if expansions > 8 {
					return resolution{failure: tooManyLinks}
				}
				result := walk(child.target, n, true, false)
				if result.node == nil {
					return result
				}
				child = result.node
			}
			n = child
		}
		return resolution{node: n}
	}
	return walk(path, s.current, follow, true)
}

func (s *shell) clone(source, parent *node, name string) {
	copy := s.create(parent, name, source.kind, source.target)
	if source.kind == regularFile {
		copy.lines = slices.Clone(source.lines)
	} else if source.kind == directory {
		for _, name := range source.names() {
			s.clone(source.entries[name], copy, name)
		}
	}
}

func (s *shell) move(sourcePath, destination string, out *output) {
	problem := func(path, reason string) { out.error("mv: cannot move '%s' to '%s': %s", sourcePath, path, reason) }
	if invalidSource(sourcePath) {
		problem(destination, "Invalid argument")
		return
	}
	result := s.resolve(sourcePath, false, false)
	source := result.node
	if source == nil {
		out.error("mv: cannot stat '%s': %s", sourcePath, result.reason())
		return
	}
	var parent *node
	var name, target string
	destinationNode := s.resolve(destination, true, false).node
	if destinationNode != nil && destinationNode.kind == directory {
		parent, name = destinationNode, lastComponent(sourcePath)
		target = joinPath(destination, name)
	} else {
		result := s.resolve(destination, false, false)
		if result.node != nil {
			parent, name = result.node.parent, result.node.name
		} else if result.creationParent != nil {
			parent, name = result.creationParent, result.creationName
		} else {
			problem(destination, result.reason())
			return
		}
		target = destination
	}
	existing := parent.entries[name]
	switch {
	case source.kind == directory && s.descendant(parent, source):
		out.error("mv: cannot move '%s' to a subdirectory of itself, '%s'", sourcePath, target)
	case existing == source:
		out.error("mv: '%s' and '%s' are the same file", sourcePath, target)
	case existing != nil && source.kind == directory && existing.kind != directory:
		out.error("mv: cannot overwrite non-directory '%s' with directory '%s'", target, sourcePath)
	case existing != nil && source.kind != directory && existing.kind == directory:
		out.error("mv: cannot overwrite directory '%s' with non-directory '%s'", target, sourcePath)
	case existing != nil && existing.kind == directory && len(existing.entries) > 0:
		problem(target, "Directory not empty")
	case existing == s.current:
		problem(target, "Device or resource busy")
	default:
		if existing != nil {
			s.detach(existing)
		}
		s.detach(source)
		s.add(parent, name, source)
	}
}

func (s *shell) copy(sourcePath, destination string, recursive bool, out *output) {
	problem := func(path, reason string) { out.error("cp: cannot copy '%s' to '%s': %s", sourcePath, path, reason) }
	if invalidSource(sourcePath) {
		problem(destination, "Invalid argument")
		return
	}
	result := s.resolve(sourcePath, true, false)
	source := result.node
	if source == nil {
		out.error("cp: cannot stat '%s': %s", sourcePath, result.reason())
		return
	}
	if source.kind == directory && !recursive {
		out.error("cp: -r not specified; omitting directory '%s'", sourcePath)
		return
	}
	result = s.resolve(destination, true, false)
	if result.node == nil && result.creationParent == nil {
		problem(destination, result.reason())
		return
	}
	target := destination
	if result.node != nil && result.node.kind == directory {
		target = joinPath(destination, lastComponent(sourcePath))
	}
	result = s.resolve(target, source.kind != directory, false)
	switch {
	case source.kind == directory:
		if result.node != nil {
			problem(target, "File exists")
		} else if s.descendant(result.creationParent, source) {
			out.error("cp: cannot copy a directory, '%s', into itself, '%s'", sourcePath, target)
		} else {
			s.clone(source, result.creationParent, result.creationName)
		}
	case result.creationParent != nil:
		s.clone(source, result.creationParent, result.creationName)
	case result.node == nil:
		problem(target, result.reason())
	case result.node == source:
		out.error("cp: '%s' and '%s' are the same file", sourcePath, target)
	case result.node.kind == directory:
		out.error("cp: cannot overwrite directory '%s' with non-directory '%s'", target, sourcePath)
	default:
		s.write(result.node, source.lines, false)
	}
}

type listingEntry struct {
	name string
	node *node
}

func (s *shell) listing(opts options, out *output) {
	paths := opts.paths
	if len(paths) == 0 {
		paths = []string{"."}
	}
	for _, path := range paths {
		result := s.resolve(path, !opts.flags['l'], false)
		n := result.node
		if n == nil {
			out.error("ls: cannot access '%s': %s", path, result.reason())
			continue
		}
		var entries []listingEntry
		if n.kind != directory {
			entries = append(entries, listingEntry{path, n})
		} else {
			if len(paths) > 1 {
				out.print("%s:", path)
			}
			if opts.flags['a'] {
				entries = append(entries, listingEntry{".", n}, listingEntry{"..", n.parent})
			}
			for _, name := range n.names() {
				if opts.flags['a'] || !strings.HasPrefix(name, ".") {
					entries = append(entries, listingEntry{name, n.entries[name]})
				}
			}
			if opts.flags['t'] {
				slices.SortStableFunc(entries, func(a, b listingEntry) int { return cmp.Compare(b.node.modified, a.node.modified) })
			}
			if opts.flags['r'] {
				slices.Reverse(entries)
			}
		}
		var widths [3]int
		for _, entry := range entries {
			for i, value := range [3]int64{int64(entry.node.links()), entry.node.size(), int64(entry.node.modified)} {
				widths[i] = max(widths[i], len(strconv.FormatInt(value, 10)))
			}
		}
		for _, entry := range entries {
			if !opts.flags['l'] {
				out.emit(entry.name)
				continue
			}
			n := entry.node
			kind := n.tag()
			if kind == 'f' {
				kind = '-'
			}
			suffix := ""
			if n.kind == symbolicLink {
				suffix = " -> " + n.target
			}
			out.print("%c %*d %*d %*d %s%s", kind, widths[0], n.links(), widths[1], n.size(), widths[2], n.modified, entry.name, suffix)
		}
	}
}

func walkNodes(n *node, path string, depth, limit int, visit func(*node, string, int)) {
	visit(n, path, depth)
	if n.kind == directory && depth < limit {
		for _, name := range n.names() {
			walkNodes(n.entries[name], joinPath(path, name), depth+1, limit, visit)
		}
	}
}

func globMatch(pattern, text string) bool {
	previous := make([]bool, len(text)+1)
	previous[0] = true
	for _, character := range []byte(pattern) {
		next := make([]bool, len(previous))
		next[0] = character == '*' && previous[0]
		for i := range len(text) {
			if character == '*' {
				next[i+1] = previous[i+1] || next[i]
			} else {
				next[i+1] = previous[i] && (character == '?' || character == text[i])
			}
		}
		previous = next
	}
	return previous[len(text)]
}

func (s *shell) find(args []string, out *output) {
	path, position := ".", 0
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		path, position = args[0], 1
	}
	pattern := ""
	var kind byte
	limit := 1000
	for ; position < len(args); position += 2 {
		switch args[position] {
		case "-name":
			pattern = args[position+1]
		case "-type":
			kind = args[position+1][0]
		case "-maxdepth":
			limit, _ = strconv.Atoi(args[position+1])
		}
	}
	result := s.resolve(path, true, false)
	if result.node == nil {
		out.error("find: '%s': %s", path, result.reason())
		return
	}
	walkNodes(result.node, path, 0, limit, func(n *node, display string, depth int) {
		name := n.name
		if depth == 0 {
			name = lastComponent(path)
			if path == "/" {
				name = "/"
			}
		}
		if (pattern == "" || globMatch(pattern, name)) && (kind == 0 || kind == n.tag()) {
			out.emit(display)
		}
	})
}

func usage(n *node, path string, show bool, opts options, out *output) int64 {
	var total int64
	if n.kind != directory {
		total = n.size()
	} else {
		for _, name := range n.names() {
			child := n.entries[name]
			total += usage(child, joinPath(path, name), show && !opts.flags['s'] && (child.kind == directory || opts.flags['a']), opts, out)
		}
	}
	if show {
		out.print("%d %s", total, path)
	}
	return total
}

func (s *shell) diskUsage(opts options, out *output) {
	paths := opts.paths
	if len(paths) == 0 {
		paths = []string{"."}
	}
	for _, path := range paths {
		result := s.resolve(path, true, false)
		if result.node == nil {
			out.error("du: cannot access '%s': %s", path, result.reason())
		} else {
			usage(result.node, path, true, opts, out)
		}
	}
}

func drawTree(n *node, prefix string, all bool, counts *[2]int, out *output) {
	names := n.names()
	if !all {
		names = slices.DeleteFunc(names, func(name string) bool { return strings.HasPrefix(name, ".") })
	}
	for i, name := range names {
		child := n.entries[name]
		branch, next := "|-- ", "|   "
		if i+1 == len(names) {
			branch, next = "`-- ", "    "
		}
		suffix := ""
		if child.kind == symbolicLink {
			suffix = " -> " + child.target
		}
		out.emit(prefix + branch + name + suffix)
		if child.kind == directory {
			counts[0]++
			drawTree(child, prefix+next, all, counts, out)
		} else {
			counts[1]++
		}
	}
}

func (s *shell) tree(opts options, out *output) {
	path := "."
	if len(opts.paths) > 0 {
		path = opts.paths[0]
	}
	result := s.resolve(path, true, false)
	if result.node == nil {
		out.error("tree: %s: %s", path, result.reason())
		return
	}
	if result.node.kind != directory {
		out.error("tree: %s: Not a directory", path)
		return
	}
	out.emit(path)
	var counts [2]int
	drawTree(result.node, "", opts.flags['a'], &counts, out)
	directories, files := "directories", "files"
	if counts[0] == 1 {
		directories = "directory"
	}
	if counts[1] == 1 {
		files = "file"
	}
	out.print("%d %s, %d %s", counts[0], directories, counts[1], files)
}

type fileInput struct {
	lines []string
	name  *string
}

func (s *shell) readInputs(command string, paths []string, input []string, out *output, consume func(fileInput)) {
	if len(paths) == 0 {
		consume(fileInput{lines: input})
		return
	}
	for _, path := range paths {
		result := s.resolve(path, true, false)
		if result.node == nil {
			out.error("%s: %s: %s", command, path, result.reason())
		} else if result.node.kind == directory {
			out.error("%s: %s: Is a directory", command, path)
		} else {
			consume(fileInput{result.node.lines, &path})
		}
	}
}

func numericPrefix(text string) int64 {
	position := 0
	negative := strings.HasPrefix(text, "-")
	if negative {
		position++
	}
	var value int64
	for position < len(text) && text[position] >= '0' && text[position] <= '9' {
		value = value*10 + int64(text[position]-'0')
		position++
	}
	if negative {
		return -value
	}
	return value
}

func (s *shell) textCommand(command string, args []string, input []string, out *output) {
	opts := parseOptions(args)
	switch command {
	case "grep":
		pattern, paths := opts.paths[0], opts.paths[1:]
		if opts.flags['i'] {
			pattern = strings.ToLower(pattern)
		}
		named := opts.flags['r'] || len(paths) > 1
		consume := func(part fileInput) {
			prefix := ""
			if named {
				prefix = *part.name + ":"
			}
			var selected int64
			for i, line := range part.lines {
				comparison := line
				if opts.flags['i'] {
					comparison = strings.ToLower(line)
				}
				if strings.Contains(comparison, pattern) == opts.flags['v'] {
					continue
				}
				selected++
				if !opts.flags['c'] {
					if opts.flags['n'] {
						out.print("%s%d:%s", prefix, i+1, line)
					} else {
						out.emit(prefix + line)
					}
				}
			}
			if opts.flags['c'] {
				out.print("%s%d", prefix, selected)
			}
		}
		if !opts.flags['r'] {
			s.readInputs(command, paths, input, out, consume)
		} else {
			if len(paths) == 0 {
				paths = []string{"."}
			}
			for _, path := range paths {
				result := s.resolve(path, true, false)
				if result.node == nil {
					out.error("grep: %s: %s", path, result.reason())
					continue
				}
				walkNodes(result.node, path, 0, 1000, func(n *node, display string, depth int) {
					if n.kind == regularFile {
						consume(fileInput{n.lines, &display})
					}
				})
			}
		}
	case "sort":
		var lines []string
		s.readInputs(command, opts.paths, input, out, func(part fileInput) { lines = append(lines, part.lines...) })
		slices.SortFunc(lines, func(a, b string) int {
			if opts.flags['n'] {
				if comparison := cmp.Compare(numericPrefix(a), numericPrefix(b)); comparison != 0 {
					return comparison
				}
			}
			return strings.Compare(a, b)
		})
		if opts.flags['r'] {
			slices.Reverse(lines)
		}
		for _, line := range lines {
			out.emit(line)
		}
	case "wc":
		all := !opts.flags['l'] && !opts.flags['w'] && !opts.flags['c']
		report := func(counts [3]int64, name *string) {
			var numbers []string
			for i, flag := range []byte("lwc") {
				if all || opts.flags[flag] {
					numbers = append(numbers, strconv.FormatInt(counts[i], 10))
				}
			}
			line := strings.Join(numbers, " ")
			if name != nil {
				line += " " + *name
			}
			out.emit(line)
		}
		var totals [3]int64
		s.readInputs(command, opts.paths, input, out, func(part fileInput) {
			counts := [3]int64{int64(len(part.lines)), 0, 0}
			for _, line := range part.lines {
				counts[2] += int64(len(line)) + 1
				inside := false
				for i := range len(line) {
					if line[i] != ' ' && !inside {
						counts[1]++
					}
					inside = line[i] != ' '
				}
			}
			for i := range counts {
				totals[i] += counts[i]
			}
			report(counts, part.name)
		})
		if len(opts.paths) > 1 {
			name := "total"
			report(totals, &name)
		}
	case "head", "tail":
		countText, offset := "10", 0
		if len(args) > 0 && args[0] == "-n" {
			countText, offset = args[1], 2
		}
		special := countText[0] == '-' || countText[0] == '+'
		digits := countText
		if special {
			digits = digits[1:]
		}
		count, _ := strconv.Atoi(digits)
		s.readInputs(command, args[offset:], input, out, func(part fileInput) {
			first, end := 0, len(part.lines)
			if command == "head" {
				if special {
					end = max(0, end-count)
				} else {
					end = min(end, count)
				}
			} else if special {
				first = min(end, max(0, count-1))
			} else {
				first = max(0, end-count)
			}
			for _, line := range part.lines[first:end] {
				out.emit(line)
			}
		})
	default:
		s.readInputs(command, opts.paths, input, out, func(part fileInput) {
			if command == "cat" {
				for _, line := range part.lines {
					out.emit(line)
				}
				return
			}
			for first := 0; first < len(part.lines); {
				end := first + 1
				for end < len(part.lines) && part.lines[first] == part.lines[end] {
					end++
				}
				if opts.flags['c'] {
					out.print("%d %s", end-first, part.lines[first])
				} else {
					out.emit(part.lines[first])
				}
				first = end
			}
		})
	}
}

func (s *shell) execute(text string, input []string, out *output) {
	words := strings.Fields(text)
	command, args := words[0], words[1:]
	opts := parseOptions(args)
	switch command {
	case "pwd":
		out.emit(s.absolute(s.current))
	case "echo":
		out.emit(text[5:])
	case "cd":
		path := "/"
		if len(args) > 0 {
			path = args[0]
		}
		back := path == "-"
		if back {
			if s.previous == nil {
				out.error("cd: OLDPWD not set")
				return
			}
			path = *s.previous
		}
		result := s.resolve(path, true, false)
		if result.node == nil {
			out.error("cd: %s: %s", path, result.reason())
		} else if result.node.kind != directory {
			out.error("cd: %s: Not a directory", path)
		} else {
			previous := s.absolute(s.current)
			s.previous, s.current = &previous, result.node
			if back {
				out.emit(s.absolute(s.current))
			}
		}
	case "mkdir":
		for _, path := range opts.paths {
			result := s.resolve(path, false, opts.flags['p'])
			if result.creationParent != nil {
				s.create(result.creationParent, result.creationName, directory, "")
			} else if result.node == nil {
				out.error("mkdir: cannot create directory '%s': %s", path, result.reason())
			} else {
				if opts.flags['p'] {
					followed := s.resolve(path, true, false).node
					if followed != nil && followed.kind == directory {
						continue
					}
				}
				out.error("mkdir: cannot create directory '%s': File exists", path)
			}
		}
	case "touch":
		for _, path := range args {
			result := s.resolve(path, true, false)
			if result.creationParent != nil {
				s.create(result.creationParent, result.creationName, regularFile, "")
			} else if result.node != nil {
				result.node.modified = s.clock
			} else {
				out.error("touch: cannot touch '%s': %s", path, result.reason())
			}
		}
	case "ls":
		s.listing(opts, out)
	case "stat":
		for _, path := range args {
			result := s.resolve(path, false, false)
			n := result.node
			if n == nil {
				out.error("stat: cannot stat '%s': %s", path, result.reason())
				continue
			}
			kind := "regular file"
			switch n.kind {
			case directory:
				kind = "directory"
			case symbolicLink:
				kind = "symbolic link"
			case regularFile:
				if len(n.lines) == 0 {
					kind = "regular empty file"
				}
			}
			out.print("%s: %s, size %d, inode %d, links %d, modified %d", path, kind, n.size(), n.inode, n.links(), n.modified)
		}
	case "rm", "rmdir":
		for _, path := range opts.paths {
			directoryOnly := command == "rmdir"
			last := lastComponent(path)
			dot := last == "." || last == ".."
			if dot && !directoryOnly {
				out.error("rm: refusing to remove '.' or '..' directory: skipping '%s'", path)
				continue
			}
			problem := ""
			if dot {
				problem = "Invalid argument"
			} else {
				result := s.resolve(path, false, false)
				n := result.node
				switch {
				case n == nil:
					if !directoryOnly && opts.flags['f'] && result.failure == missing {
						continue
					}
					problem = result.reason()
				case directoryOnly && n.kind != directory:
					problem = "Not a directory"
				case !directoryOnly && n.kind == directory && !opts.flags['r']:
					problem = "Is a directory"
				case s.descendant(s.current, n):
					problem = "Device or resource busy"
				case directoryOnly && len(n.entries) > 0:
					problem = "Directory not empty"
				default:
					s.detach(n)
				}
			}
			if problem != "" {
				if directoryOnly {
					out.error("rmdir: failed to remove '%s': %s", path, problem)
				} else {
					out.error("rm: cannot remove '%s': %s", path, problem)
				}
			}
		}
	case "mv", "cp":
		destination := opts.paths[len(opts.paths)-1]
		if len(opts.paths) > 2 {
			n := s.resolve(destination, true, false).node
			if n == nil || n.kind != directory {
				out.error("%s: target '%s' is not a directory", command, destination)
				return
			}
		}
		for _, source := range opts.paths[:len(opts.paths)-1] {
			if command == "mv" {
				s.move(source, destination, out)
			} else {
				s.copy(source, destination, opts.flags['r'], out)
			}
		}
	case "ln":
		path := args[2]
		result := s.resolve(path, false, false)
		if result.creationParent != nil {
			s.create(result.creationParent, result.creationName, symbolicLink, args[1])
		} else {
			reason := result.reason()
			if result.node != nil {
				reason = "File exists"
			}
			out.error("ln: failed to create symbolic link '%s': %s", path, reason)
		}
	case "readlink", "realpath":
		path := args[0]
		result := s.resolve(path, command == "realpath", false)
		if result.node == nil {
			out.error("%s: %s: %s", command, path, result.reason())
		} else if command == "realpath" {
			out.emit(s.absolute(result.node))
		} else if result.node.kind == symbolicLink {
			out.emit(result.node.target)
		} else {
			out.error("readlink: %s: Invalid argument", path)
		}
	case "find":
		s.find(args, out)
	case "du":
		s.diskUsage(opts, out)
	case "tree":
		s.tree(opts, out)
	case "cat", "wc", "head", "tail", "grep", "sort", "uniq":
		s.textCommand(command, args, input, out)
	default:
		out.error("%s: command not found", command)
	}
}

func (s *shell) process(line string, terminal io.Writer) {
	s.clock++
	fmt.Fprintf(terminal, "%s$ %s\n", s.absolute(s.current), line)
	pipeline := line
	var redirect *node
	if marker := strings.Index(line, " >"); marker >= 0 {
		pipeline = line[:marker]
		appendMode := strings.HasPrefix(line[marker:], " >> ")
		offset := 3
		if appendMode {
			offset = 4
		}
		path := line[marker+offset:]
		result := s.resolve(path, true, false)
		if result.creationParent != nil {
			redirect = s.create(result.creationParent, result.creationName, regularFile, "")
		} else if result.node != nil && result.node.kind == regularFile {
			redirect = result.node
			if !appendMode {
				s.write(redirect, nil, false)
			}
		} else {
			reason := result.reason()
			if result.node != nil {
				reason = "Is a directory"
			}
			fmt.Fprintf(terminal, "sh: %s: %s\n", path, reason)
			return
		}
	}
	commands := strings.Split(pipeline, " | ")
	var input []string
	for i, command := range commands {
		out := output{terminal: terminal, direct: i+1 == len(commands) && redirect == nil}
		s.execute(command, input, &out)
		input = out.lines
	}
	if redirect != nil && len(input) > 0 {
		s.write(redirect, input, true)
	}
}

func main() {
	shell := newShell()
	input := bufio.NewScanner(os.Stdin)
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for input.Scan() {
		line := input.Text()
		if line == "exit" {
			break
		}
		shell.process(line, output)
	}
}
