package main

import "strings"

type ArchiveMember struct {
	Object  *Object
	Exports []string
	Loaded  bool
}
type Archive struct {
	Name    string
	Members []*ArchiveMember
}
type Extraction struct{ Object, Reason, Referrer string }

func readArchive(name string) *Archive {
	archive := &Archive{Name: name}
	var member *ArchiveMember
	body := []string{}
	for _, line := range readLines("input/" + name) {
		a := strings.Split(line, " ")
		if a[0] == "member" {
			member = &ArchiveMember{Exports: append([]string{}, a[2:]...)}
			member.Object = &Object{Name: name + "(" + a[1] + ")"}
			body = nil
		} else {
			body = append(body, line)
			if line == "end" {
				member.Object = parseObject(body, member.Object.Name)
				archive.Members = append(archive.Members, member)
			}
		}
	}
	return archive
}
func scanArchive(archive *Archive, undefined func(string) bool, referrer func(string) string, load func(*Object), record func(Extraction)) int {
	total := 0
	for {
		extracted := 0
		for _, member := range archive.Members {
			if member.Loaded {
				continue
			}
			reason := ""
			for _, name := range member.Exports {
				if undefined(name) {
					reason = name
					break
				}
			}
			if reason == "" {
				continue
			}
			record(Extraction{member.Object.Name, reason, referrer(reason)})
			member.Loaded = true
			load(member.Object)
			extracted++
			total++
		}
		if extracted == 0 {
			return total
		}
	}
}
