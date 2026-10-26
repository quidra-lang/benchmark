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

type tree map[string]string

type commit struct {
	id       string
	sequence int
	parents  []*commit
	files    tree
	message  string
}

type operation struct {
	kind   string
	target *commit
}

type stashEntry struct {
	label string
	base  *commit
	files tree
}

func clone(files tree) tree {
	result := tree{}
	for path, text := range files {
		result[path] = text
	}
	return result
}

func paths(trees ...tree) []string {
	all := map[string]bool{}
	for _, files := range trees {
		for path := range files {
			all[path] = true
		}
	}
	result := []string{}
	for path := range all {
		result = append(result, path)
	}
	sort.Strings(result)
	return result
}

func agree(a, b tree, path string) bool {
	left, hasLeft := a[path]
	right, hasRight := b[path]
	return hasLeft == hasRight && left == right
}

func differences(a, b tree) []string {
	result := []string{}
	for _, path := range paths(a, b) {
		if !agree(a, b, path) {
			result = append(result, path)
		}
	}
	return result
}

func same(a, b tree) bool {
	return len(differences(a, b)) == 0
}

func matchPath(target, source tree, path string) {
	if text, present := source[path]; present {
		target[path] = text
	} else {
		delete(target, path)
	}
}

func conflictText(ours, theirs tree, path string) string {
	a, ok := ours[path]
	if !ok {
		a = "(deleted)"
	}
	b, ok := theirs[path]
	if !ok {
		b = "(deleted)"
	}
	return "<<<<<<< " + a + " ======= " + b + " >>>>>>>"
}

func threeWay(base, ours, theirs tree) (tree, []string) {
	result, conflicts := tree{}, []string{}
	for _, path := range paths(base, ours, theirs) {
		if agree(theirs, base, path) || agree(ours, theirs, path) {
			matchPath(result, ours, path)
		} else if agree(ours, base, path) {
			matchPath(result, theirs, path)
		} else {
			conflicts = append(conflicts, path)
			matchPath(result, ours, path)
		}
	}
	return result, conflicts
}

func distances(start *commit) map[*commit]int {
	result, queue := map[*commit]int{start: 0}, []*commit{start}
	for at := 0; at < len(queue); at++ {
		current := queue[at]
		for _, parent := range current.parents {
			if _, found := result[parent]; !found {
				result[parent] = result[current] + 1
				queue = append(queue, parent)
			}
		}
	}
	return result
}

func ancestor(a, b *commit) bool {
	_, exists := distances(b)[a]
	return exists
}

func mergeBase(a, b *commit) *commit {
	da, db := distances(a), distances(b)
	candidates := map[*commit]bool{}
	for c := range da {
		if _, found := db[c]; found {
			candidates[c] = true
		}
	}
	excluded := map[*commit]bool{}
	for c := range candidates {
		for _, parent := range c.parents {
			excluded[parent] = true
		}
	}
	var best *commit
	bestDistance := 0
	for c := range candidates {
		if excluded[c] {
			continue
		}
		d := da[c]
		if db[c] > d {
			d = db[c]
		}
		if best == nil || d < bestDistance || d == bestDistance && c.sequence > best.sequence {
			best, bestDistance = c, d
		}
	}
	return best
}

func glob(pattern, path string) bool {
	previous := make([]bool, len(path)+1)
	previous[0] = true
	for i := range pattern {
		current := make([]bool, len(path)+1)
		if pattern[i] == '*' {
			current[0] = previous[0]
		}
		for j := 1; j <= len(path); j++ {
			if pattern[i] == '*' {
				current[j] = previous[j] || current[j-1]
			} else {
				current[j] = previous[j-1] && (pattern[i] == '?' || pattern[i] == path[j-1])
			}
		}
		previous = current
	}
	return previous[len(path)]
}

type repository struct {
	commits        map[string]*commit
	branches, tags map[string]*commit
	attached       string
	detached       *commit
	work, index    tree
	conflicts      map[string]bool
	pending        *operation
	stash          []stashEntry
	ignores        []string
	created        int
	out            *bufio.Writer
}

func newRepository(out *bufio.Writer) *repository {
	r := &repository{commits: map[string]*commit{}, branches: map[string]*commit{}, tags: map[string]*commit{}, attached: "main", work: tree{}, index: tree{}, conflicts: map[string]bool{}, out: out}
	root := r.create(nil, tree{}, "init")
	r.branches["main"] = root
	return r
}

func (r *repository) head() *commit {
	if r.attached != "" {
		return r.branches[r.attached]
	}
	return r.detached
}

func (r *repository) moveHead(c *commit) {
	if r.attached != "" {
		r.branches[r.attached] = c
	} else {
		r.detached = c
	}
}

func (r *repository) create(parents []*commit, files tree, message string) *commit {
	var text strings.Builder
	fmt.Fprintf(&text, "commit %d\n", r.created)
	for _, parent := range parents {
		fmt.Fprintf(&text, "parent %s\n", parent.id)
	}
	for _, path := range paths(files) {
		fmt.Fprintf(&text, "file %s %s\n", path, files[path])
	}
	fmt.Fprintf(&text, "message %s\n", message)
	hash := int64(0)
	for _, c := range []byte(text.String()) {
		hash = (hash*131 + int64(c)) % 2147483647
	}
	c := &commit{id: fmt.Sprintf("%08x", hash), sequence: r.created, parents: append([]*commit{}, parents...), files: clone(files), message: message}
	r.created++
	r.commits[c.id] = c
	return c
}

func (r *repository) record(parents []*commit, files tree, message string) {
	c := r.create(parents, files, message)
	r.moveHead(c)
	location := r.attached
	if location == "" {
		location = "detached HEAD"
	}
	added, modified, deleted := 0, 0, 0
	old := parents[0].files
	for _, path := range differences(old, files) {
		if _, found := old[path]; !found {
			added++
		} else if _, found := files[path]; !found {
			deleted++
		} else {
			modified++
		}
	}
	fmt.Fprintf(r.out, "[%s %s] %s (%d added, %d modified, %d deleted)\n", location, c.id, message, added, modified, deleted)
}

func (r *repository) revision(rev string) (*commit, error) {
	anchor, suffix, hasSuffix := strings.Cut(rev, "~")
	var c *commit
	if anchor == "HEAD" {
		c = r.head()
	} else if r.branches[anchor] != nil {
		c = r.branches[anchor]
	} else if r.tags[anchor] != nil {
		c = r.tags[anchor]
	} else {
		c = r.commits[anchor]
	}
	if hasSuffix {
		n, _ := strconv.Atoi(suffix)
		for i := 0; i < n && c != nil; i++ {
			if len(c.parents) == 0 {
				c = nil
			} else {
				c = c.parents[0]
			}
		}
	}
	if c == nil {
		return nil, fmt.Errorf("unknown revision '%s'", rev)
	}
	return c, nil
}

func referenceNames(refs map[string]*commit) []string {
	names := []string{}
	for name := range refs {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func (r *repository) summary(c *commit) string {
	references := []string{}
	if r.head() == c {
		if r.attached == "" {
			references = append(references, "HEAD")
		} else {
			references = append(references, "HEAD -> "+r.attached)
		}
	}
	for _, name := range referenceNames(r.branches) {
		if name != r.attached && r.branches[name] == c {
			references = append(references, name)
		}
	}
	for _, name := range referenceNames(r.tags) {
		if r.tags[name] == c {
			references = append(references, "tag: "+name)
		}
	}
	text := c.id
	if len(references) > 0 {
		text += " (" + strings.Join(references, ", ") + ")"
	}
	return text + " " + c.message
}

func (r *repository) changes(a, b tree) {
	changed := differences(a, b)
	if len(changed) == 0 {
		fmt.Fprintln(r.out, "(no changes)")
		return
	}
	for _, path := range changed {
		old, inOld := a[path]
		text, inNew := b[path]
		if !inOld {
			fmt.Fprintf(r.out, "A %s: %s\n", path, text)
		} else if !inNew {
			fmt.Fprintf(r.out, "D %s: %s\n", path, old)
		} else {
			fmt.Fprintf(r.out, "M %s: %s -> %s\n", path, old, text)
		}
	}
}

func (r *repository) inProgress() error {
	if r.pending != nil {
		return fmt.Errorf("%s in progress", r.pending.kind)
	}
	return nil
}

func (r *repository) uncommitted() bool {
	if !same(r.index, r.head().files) {
		return true
	}
	for path := range r.index {
		if !agree(r.index, r.work, path) {
			return true
		}
	}
	return false
}

func (r *repository) requireClean() error {
	if r.uncommitted() {
		return fmt.Errorf("uncommitted changes")
	}
	return nil
}

func (r *repository) overwrite(selected []string) error {
	sort.Strings(selected)
	for _, path := range selected {
		if !agree(r.index, r.head().files, path) || !agree(r.work, r.head().files, path) {
			return fmt.Errorf("local changes to '%s' would be overwritten", path)
		}
	}
	return nil
}

func (r *repository) switchTree(files tree) error {
	changed := differences(r.head().files, files)
	if err := r.overwrite(changed); err != nil {
		return err
	}
	for _, path := range changed {
		matchPath(r.index, files, path)
		matchPath(r.work, files, path)
	}
	return nil
}

func (r *repository) ignored(path string) bool {
	if _, tracked := r.index[path]; tracked || r.conflicts[path] {
		return false
	}
	for _, pattern := range r.ignores {
		if glob(pattern, path) {
			return true
		}
	}
	return false
}

func (r *repository) apply(base, theirs tree, kind string, target *commit, message string, parents []*commit, baseCommit *commit) error {
	merged, conflicts := threeWay(base, r.head().files, theirs)
	changed := differences(r.head().files, merged)
	if err := r.overwrite(append(append([]string{}, changed...), conflicts...)); err != nil {
		return err
	}
	if kind == "merge" {
		fmt.Fprintln(r.out, "Merge base "+baseCommit.id)
	}
	if kind != "merge" && len(conflicts) == 0 && same(merged, r.head().files) {
		fmt.Fprintln(r.out, "nothing to commit")
		return nil
	}
	for _, path := range changed {
		matchPath(r.index, merged, path)
		matchPath(r.work, merged, path)
	}
	if len(conflicts) == 0 {
		r.record(parents, merged, message)
		return nil
	}
	r.conflicts = map[string]bool{}
	for _, path := range conflicts {
		r.work[path] = conflictText(r.head().files, theirs, path)
		r.conflicts[path] = true
		fmt.Fprintln(r.out, "CONFLICT "+path)
	}
	r.pending = &operation{kind, target}
	if kind == "merge" {
		fmt.Fprintln(r.out, "Automatic merge failed; fix conflicts and then commit the result.")
	} else if kind == "revert" {
		fmt.Fprintln(r.out, "error: could not revert "+target.id)
	} else {
		fmt.Fprintln(r.out, "error: could not apply "+target.id)
	}
	return nil
}

func parentTree(c *commit) tree {
	if len(c.parents) == 0 {
		return tree{}
	}
	return c.parents[0].files
}

func (r *repository) roots(extra bool) []*commit {
	roots := []*commit{r.head()}
	for _, c := range r.branches {
		roots = append(roots, c)
	}
	for _, c := range r.tags {
		roots = append(roots, c)
	}
	if extra {
		for _, entry := range r.stash {
			roots = append(roots, entry.base)
		}
		if r.pending != nil {
			roots = append(roots, r.pending.target)
		}
	}
	return roots
}

func reachable(roots []*commit) map[*commit]bool {
	all := map[*commit]bool{}
	for _, root := range roots {
		for c := range distances(root) {
			all[c] = true
		}
	}
	return all
}

func (r *repository) command(line string) error {
	words := strings.Split(line, " ")
	command := words[0]
	h := r.head()
	switch command {
	case "WRITE":
		args := strings.SplitN(line, " ", 3)
		r.work[args[1]] = args[2]
	case "REMOVE":
		if _, exists := r.work[words[1]]; !exists {
			return fmt.Errorf("no such file '%s'", words[1])
		}
		delete(r.work, words[1])
	case "IGNORE":
		r.ignores = append(r.ignores, words[1])
	case "ADD":
		path := words[1]
		if path == "ALL" {
			selected := paths(r.work, r.index)
			for _, path := range selected {
				if !r.ignored(path) {
					matchPath(r.index, r.work, path)
				}
			}
			r.conflicts = map[string]bool{}
		} else {
			_, inWork := r.work[path]
			_, inIndex := r.index[path]
			if inWork && r.ignored(path) {
				return fmt.Errorf("path '%s' is ignored", path)
			}
			if !inWork && !inIndex && !r.conflicts[path] {
				return fmt.Errorf("pathspec '%s' did not match any files", path)
			}
			matchPath(r.index, r.work, path)
			delete(r.conflicts, path)
		}
	case "RM":
		path := words[1]
		if _, exists := r.index[path]; !exists {
			return fmt.Errorf("pathspec '%s' did not match any files", path)
		}
		delete(r.index, path)
		delete(r.work, path)
		delete(r.conflicts, path)
	case "UNSTAGE":
		path := words[1]
		_, inIndex := r.index[path]
		_, inHead := h.files[path]
		if !inIndex && !inHead {
			return fmt.Errorf("pathspec '%s' did not match any files", path)
		}
		matchPath(r.index, h.files, path)
	case "RESTORE", "CAT":
		path, files := words[1], r.work
		if command == "RESTORE" {
			files = r.index
		}
		if len(words) == 3 {
			c, err := r.revision(words[2])
			if err != nil {
				return err
			}
			files = c.files
			if _, exists := files[path]; !exists {
				return fmt.Errorf("path '%s' does not exist in '%s'", path, words[2])
			}
		} else if _, exists := files[path]; !exists {
			if command == "CAT" {
				return fmt.Errorf("no such file '%s'", path)
			}
			return fmt.Errorf("pathspec '%s' did not match any files", path)
		}
		if command == "CAT" {
			fmt.Fprintln(r.out, files[path])
		} else {
			r.work[path] = files[path]
			if len(words) == 3 {
				r.index[path] = files[path]
				delete(r.conflicts, path)
			}
		}
	case "COMMIT":
		if len(r.conflicts) > 0 {
			return fmt.Errorf("unresolved conflicts")
		}
		message := strings.SplitN(line, " ", 2)[1]
		parents := []*commit{h}
		if r.pending != nil && r.pending.kind == "merge" {
			parents = append(parents, r.pending.target)
		} else if same(r.index, h.files) {
			fmt.Fprintln(r.out, "nothing to commit")
			return nil
		}
		r.record(parents, r.index, message)
		r.pending = nil
	case "AMEND":
		if err := r.inProgress(); err != nil {
			return err
		}
		if len(h.parents) == 0 {
			return fmt.Errorf("cannot amend the root commit")
		}
		r.record(h.parents, r.index, strings.SplitN(line, " ", 2)[1])
	case "STATUS":
		if r.attached == "" {
			fmt.Fprintln(r.out, "HEAD detached at "+h.id)
		} else {
			fmt.Fprintln(r.out, "On branch "+r.attached)
		}
		if r.pending != nil {
			title := map[string]string{"merge": "Merging", "revert": "Reverting", "cherry-pick": "Cherry-picking"}[r.pending.kind]
			fmt.Fprintln(r.out, title+" "+r.pending.target.id)
		}
		all := clone(r.work)
		for path := range r.conflicts {
			all[path] = ""
		}
		printed := false
		for _, path := range paths(h.files, r.index, all) {
			if r.conflicts[path] {
				fmt.Fprintln(r.out, "UU "+path)
				printed = true
				continue
			}
			content, inIndex := r.index[path]
			old, inHead := h.files[path]
			work, inWork := r.work[path]
			if inIndex {
				x, y := byte('.'), byte('.')
				if !inHead {
					x = 'A'
				} else if old != content {
					x = 'M'
				}
				if !inWork {
					y = 'D'
				} else if work != content {
					y = 'M'
				}
				if x != '.' || y != '.' {
					fmt.Fprintf(r.out, "%c%c %s\n", x, y, path)
					printed = true
				}
			} else {
				if inHead {
					fmt.Fprintln(r.out, "D. "+path)
					printed = true
				}
				if inWork && !r.ignored(path) {
					fmt.Fprintln(r.out, "?? "+path)
					printed = true
				}
			}
		}
		if !printed {
			fmt.Fprintln(r.out, "nothing to commit, working tree clean")
		}
	case "LS":
		files := r.work
		if len(words) == 2 {
			c, err := r.revision(words[1])
			if err != nil {
				return err
			}
			files = c.files
		}
		if len(files) == 0 {
			fmt.Fprintln(r.out, "(empty)")
		}
		for _, path := range paths(files) {
			fmt.Fprintln(r.out, path+" "+files[path])
		}
	case "DIFF":
		if len(words) == 1 {
			work := tree{}
			for path := range r.index {
				matchPath(work, r.work, path)
			}
			r.changes(r.index, work)
		} else if len(words) == 2 {
			r.changes(h.files, r.index)
		} else {
			a, err := r.revision(words[1])
			if err != nil {
				return err
			}
			b, err := r.revision(words[2])
			if err != nil {
				return err
			}
			r.changes(a.files, b.files)
		}
	case "LOG":
		limit := r.created
		if len(words) == 2 {
			limit, _ = strconv.Atoi(words[1])
		}
		for c, n := h, 0; c != nil && n < limit; n++ {
			fmt.Fprintln(r.out, r.summary(c))
			if len(c.parents) == 0 {
				break
			}
			c = c.parents[0]
		}
	case "SHOW":
		rev := "HEAD"
		if len(words) == 2 {
			rev = words[1]
		}
		c, err := r.revision(rev)
		if err != nil {
			return err
		}
		fmt.Fprintln(r.out, "commit "+r.summary(c))
		parents := []string{}
		for _, parent := range c.parents {
			parents = append(parents, parent.id)
		}
		if len(parents) == 0 {
			parents = append(parents, "none")
		}
		fmt.Fprintln(r.out, "parents: "+strings.Join(parents, " "))
		r.changes(parentTree(c), c.files)
	case "BLAME":
		path := words[1]
		content, exists := h.files[path]
		if !exists {
			return fmt.Errorf("path '%s' does not exist in 'HEAD'", path)
		}
		c := h
		for len(c.parents) > 0 {
			parent := c.parents[0]
			if text, exists := parent.files[path]; !exists || text != content {
				break
			}
			c = parent
		}
		fmt.Fprintf(r.out, "%s (%s) %s\n", c.id, c.message, content)
	case "BRANCH", "TAG":
		refs, label := r.branches, "branch"
		if command == "TAG" {
			refs, label = r.tags, "tag"
		}
		if words[1] == "-d" {
			name := words[2]
			c := refs[name]
			if c == nil {
				return fmt.Errorf("no such %s '%s'", label, name)
			}
			if command == "BRANCH" {
				if r.attached == name {
					return fmt.Errorf("cannot delete current branch '%s'", name)
				}
				if !ancestor(c, h) {
					return fmt.Errorf("branch '%s' is not fully merged", name)
				}
			}
			delete(refs, name)
			fmt.Fprintf(r.out, "Deleted %s %s (was %s)\n", label, name, c.id)
		} else {
			name := words[1]
			if refs[name] != nil {
				return fmt.Errorf("%s '%s' already exists", label, name)
			}
			rev := "HEAD"
			if len(words) == 3 {
				rev = words[2]
			}
			c, err := r.revision(rev)
			if err != nil {
				return err
			}
			refs[name] = c
			fmt.Fprintf(r.out, "Created %s %s at %s\n", label, name, c.id)
		}
	case "BRANCHES":
		if r.attached == "" {
			fmt.Fprintln(r.out, "* (HEAD detached at "+h.id+")")
		}
		for _, name := range referenceNames(r.branches) {
			mark := " "
			if r.attached == name {
				mark = "*"
			}
			c := r.branches[name]
			fmt.Fprintf(r.out, "%s %s %s %s\n", mark, name, c.id, c.message)
		}
	case "TAGS":
		if len(r.tags) == 0 {
			fmt.Fprintln(r.out, "(no tags)")
		}
		for _, name := range referenceNames(r.tags) {
			c := r.tags[name]
			fmt.Fprintf(r.out, "%s %s %s\n", name, c.id, c.message)
		}
	case "SWITCH":
		name := words[1]
		c := r.branches[name]
		if c == nil {
			return fmt.Errorf("no such branch '%s'", name)
		}
		if name == r.attached {
			fmt.Fprintf(r.out, "Already on '%s'\n", name)
			return nil
		}
		if err := r.inProgress(); err != nil {
			return err
		}
		if err := r.switchTree(c.files); err != nil {
			return err
		}
		r.attached, r.detached = name, nil
		fmt.Fprintf(r.out, "Switched to branch '%s'\n", name)
	case "DETACH":
		c, err := r.revision(words[1])
		if err != nil {
			return err
		}
		if err := r.inProgress(); err != nil {
			return err
		}
		if err := r.switchTree(c.files); err != nil {
			return err
		}
		r.attached, r.detached = "", c
		fmt.Fprintf(r.out, "HEAD is now at %s %s\n", c.id, c.message)
	case "MERGEBASE":
		a, err := r.revision(words[1])
		if err != nil {
			return err
		}
		b, err := r.revision(words[2])
		if err != nil {
			return err
		}
		fmt.Fprintln(r.out, mergeBase(a, b).id)
	case "MERGE", "REVERT", "CHERRYPICK":
		c, err := r.revision(words[1])
		if err != nil {
			return err
		}
		if err := r.inProgress(); err != nil {
			return err
		}
		if command == "MERGE" {
			if ancestor(c, h) {
				fmt.Fprintln(r.out, "Already up to date")
				return nil
			}
			if ancestor(h, c) {
				if err := r.switchTree(c.files); err != nil {
					return err
				}
				r.moveHead(c)
				fmt.Fprintf(r.out, "Fast-forward %s..%s\n", h.id, c.id)
				return nil
			}
		}
		if err := r.requireClean(); err != nil {
			return err
		}
		if command == "MERGE" {
			base := mergeBase(h, c)
			return r.apply(base.files, c.files, "merge", c, "Merge "+words[1], []*commit{h, c}, base)
		}
		if command == "REVERT" {
			return r.apply(c.files, parentTree(c), "revert", c, "Revert \""+c.message+"\"", []*commit{h}, nil)
		}
		return r.apply(parentTree(c), c.files, "cherry-pick", c, c.message, []*commit{h}, nil)
	case "REBASE":
		upstream, err := r.revision(words[1])
		if err != nil {
			return err
		}
		if err := r.inProgress(); err != nil {
			return err
		}
		if ancestor(upstream, h) {
			fmt.Fprintln(r.out, "Already up to date")
			return nil
		}
		if err := r.requireClean(); err != nil {
			return err
		}
		list := []*commit{}
		for c := h; !ancestor(c, upstream); c = c.parents[0] {
			list = append(list, c)
		}
		for i, j := 0, len(list)-1; i < j; i, j = i+1, j-1 {
			list[i], list[j] = list[j], list[i]
		}
		current := upstream.files
		picks := make([]tree, len(list))
		for i, c := range list {
			merged, conflicts := threeWay(parentTree(c), current, c.files)
			if len(conflicts) > 0 {
				return fmt.Errorf("could not rebase %s: conflict in '%s'", c.id, conflicts[0])
			}
			if !same(merged, current) {
				picks[i] = merged
				current = merged
			}
		}
		if err := r.switchTree(current); err != nil {
			return err
		}
		tip := upstream
		for i, c := range list {
			if picks[i] == nil {
				fmt.Fprintf(r.out, "skip %s %s\n", c.id, c.message)
			} else {
				next := r.create([]*commit{tip}, picks[i], c.message)
				fmt.Fprintf(r.out, "pick %s -> %s %s\n", c.id, next.id, c.message)
				tip = next
			}
		}
		r.moveHead(tip)
		fmt.Fprintf(r.out, "HEAD is now at %s %s\n", tip.id, tip.message)
	case "RESET":
		c, err := r.revision(words[2])
		if err != nil {
			return err
		}
		if words[1] == "HARD" {
			all := tree{}
			for path := range r.conflicts {
				all[path] = ""
			}
			for _, path := range paths(r.index, c.files, all) {
				matchPath(r.work, c.files, path)
			}
		}
		if words[1] != "SOFT" {
			r.index = clone(c.files)
		}
		r.moveHead(c)
		r.conflicts = map[string]bool{}
		r.pending = nil
		fmt.Fprintf(r.out, "HEAD is now at %s %s\n", c.id, c.message)
	case "STASH":
		action := ""
		if len(words) > 1 {
			action = words[1]
		}
		if action == "LIST" {
			if len(r.stash) == 0 {
				fmt.Fprintln(r.out, "(no stash entries)")
			}
			for i, entry := range r.stash {
				fmt.Fprintf(r.out, "stash@{%d}: %s\n", i, entry.label)
			}
			return nil
		}
		if action != "" && len(r.stash) == 0 {
			return fmt.Errorf("no stash entries")
		}
		if action == "DROP" {
			label := r.stash[0].label
			r.stash = r.stash[1:]
			fmt.Fprintln(r.out, "Dropped stash@{0}: "+label)
			return nil
		}
		if err := r.inProgress(); err != nil {
			return err
		}
		if action == "POP" {
			if err := r.requireClean(); err != nil {
				return err
			}
			entry := r.stash[0]
			merged, conflicts := threeWay(entry.base.files, h.files, entry.files)
			if len(conflicts) > 0 {
				return fmt.Errorf("stash conflict in '%s'", conflicts[0])
			}
			changed := differences(h.files, merged)
			if err := r.overwrite(changed); err != nil {
				return err
			}
			for _, path := range changed {
				matchPath(r.work, merged, path)
			}
			r.stash = r.stash[1:]
			fmt.Fprintln(r.out, "Restored stash@{0}: "+entry.label)
			r.changes(h.files, merged)
		} else {
			if !r.uncommitted() {
				fmt.Fprintln(r.out, "No local changes to save")
				return nil
			}
			saved := tree{}
			for _, path := range paths(r.index, h.files) {
				matchPath(saved, r.work, path)
				matchPath(r.work, h.files, path)
			}
			r.index = clone(h.files)
			location := r.attached
			if location == "" {
				location = "(no branch)"
			}
			label := "WIP on " + location + ": " + h.id + " " + h.message
			r.stash = append([]stashEntry{{label, h, saved}}, r.stash...)
			fmt.Fprintln(r.out, "Saved stash@{0}: "+label)
		}
	case "GRAPH":
		all := reachable(r.roots(false))
		ordered := []*commit{}
		for c := range all {
			ordered = append(ordered, c)
		}
		sort.Slice(ordered, func(i, j int) bool {
			return ordered[i].sequence > ordered[j].sequence
		})
		lanes := []*commit{}
		for _, c := range ordered {
			at := -1
			for i, held := range lanes {
				if held == c {
					at = i
					break
				}
			}
			if at < 0 {
				at = len(lanes)
				lanes = append(lanes, c)
			}
			symbols := []string{}
			kept := []*commit{}
			for i, held := range lanes {
				symbol := "|"
				if held == c {
					symbol = "/"
					if i == at {
						symbol = "*"
					}
				}
				symbols = append(symbols, symbol)
				if held != c || i == at {
					kept = append(kept, held)
				}
			}
			fmt.Fprintln(r.out, strings.Join(symbols, " ")+" "+r.summary(c))
			lanes = kept
			if len(c.parents) == 0 {
				lanes = append(lanes[:at], lanes[at+1:]...)
			} else {
				lanes[at] = c.parents[0]
				if len(c.parents) == 2 {
					exists := false
					for _, held := range lanes {
						if held == c.parents[1] {
							exists = true
						}
					}
					if !exists {
						lanes = append(lanes, nil)
						copy(lanes[at+2:], lanes[at+1:])
						lanes[at+1] = c.parents[1]
					}
				}
			}
		}
	case "DESCRIBE":
		rev := "HEAD"
		if len(words) == 2 {
			rev = words[1]
		}
		c, err := r.revision(rev)
		if err != nil {
			return err
		}
		d, best, distance := distances(c), "", 0
		for _, name := range referenceNames(r.tags) {
			if n, exists := d[r.tags[name]]; exists && (best == "" || n < distance) {
				best, distance = name, n
			}
		}
		if best == "" {
			return fmt.Errorf("no tag can describe '%s'", c.id)
		}
		if distance == 0 {
			fmt.Fprintln(r.out, best)
		} else {
			fmt.Fprintf(r.out, "%s-%d-g%s\n", best, distance, c.id)
		}
	case "GC":
		keep, removed := reachable(r.roots(true)), 0
		for id, c := range r.commits {
			if !keep[c] {
				delete(r.commits, id)
				removed++
			}
		}
		fmt.Fprintf(r.out, "Removed unreachable commits: %d\n", removed)
	}
	return nil
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	r := newRepository(out)
	for _, line := range strings.Split(string(data), "\n") {
		if line == "EXIT" {
			break
		}
		if err := r.command(line); err != nil {
			fmt.Fprintln(out, "error: "+err.Error())
		}
	}
}
