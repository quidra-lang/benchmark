package main

import "sort"

type Container struct {
	ID       string
	Message  *Message
	Parent   *Container
	Children []*Container
	Subject  string
}
type Threader struct {
	Table      map[string]*Container
	Containers []*Container
}

func adopt(parent, child *Container) {
	child.Parent = parent
	parent.Children = append(parent.Children, child)
}
func (c *Container) ancestorOf(other *Container) bool {
	for other != nil {
		if c == other {
			return true
		}
		other = other.Parent
	}
	return false
}
func (t *Threader) containerOf(id string) *Container {
	if container, ok := t.Table[id]; ok {
		return container
	}
	container := &Container{ID: id}
	t.Table[id] = container
	t.Containers = append(t.Containers, container)
	return container
}
func (t *Threader) add(message *Message) {
	var container *Container
	if message.ID != "" {
		container = t.containerOf(message.ID)
	} else {
		container = &Container{}
		t.Containers = append(t.Containers, container)
	}
	container.Message = message
	references := []*Container{}
	for _, id := range message.References {
		references = append(references, t.containerOf(id))
	}
	for i := 0; i+1 < len(references); i++ {
		current, following := references[i], references[i+1]
		if following.Parent == nil && !following.ancestorOf(current) {
			adopt(current, following)
		}
	}
	if container.Parent != nil {
		parent := container.Parent
		for i, child := range parent.Children {
			if child == container {
				parent.Children = append(parent.Children[:i], parent.Children[i+1:]...)
				break
			}
		}
		container.Parent = nil
	}
	if len(references) > 0 && !container.ancestorOf(references[len(references)-1]) {
		adopt(references[len(references)-1], container)
	}
}
func prune(containers []*Container, atRoot bool) []*Container {
	result := []*Container{}
	for _, container := range containers {
		container.Children = prune(container.Children, false)
		if container.Message != nil || atRoot && len(container.Children) >= 2 {
			result = append(result, container)
			continue
		}
		for _, child := range container.Children {
			if atRoot {
				child.Parent = nil
			} else {
				child.Parent = container.Parent
			}
		}
		result = append(result, container.Children...)
	}
	return result
}
func messageLess(a, b *Message) bool {
	if a.DateValid != b.DateValid {
		return a.DateValid
	}
	if a.DateValid && a.Date != b.Date {
		return a.Date < b.Date
	}
	if a.ID != b.ID {
		return a.ID < b.ID
	}
	return a.Number < b.Number
}
func containerKey(container *Container) *Message {
	if container.Message != nil {
		return container.Message
	}
	var best *Message
	for _, child := range container.Children {
		candidate := containerKey(child)
		if best == nil || messageLess(candidate, best) {
			best = candidate
		}
	}
	return best
}
func sortContainers(containers []*Container) {
	for _, container := range containers {
		sortContainers(container.Children)
	}
	sort.Slice(containers, func(i, j int) bool { return messageLess(containerKey(containers[i]), containerKey(containers[j])) })
}
func rootSubject(root *Container) string {
	if root.Message != nil {
		return root.Message.BaseSubject
	}
	return root.Children[0].Message.BaseSubject
}
func mergeBySubject(roots []*Container) []*Container {
	groups := map[string][]*Container{}
	order := []string{}
	for _, root := range roots {
		subject := rootSubject(root)
		if subject != "" {
			if _, exists := groups[subject]; !exists {
				order = append(order, subject)
			}
			groups[subject] = append(groups[subject], root)
		}
	}
	merged := []*Container{}
	for _, root := range roots {
		subject := rootSubject(root)
		if subject == "" || len(groups[subject]) == 1 {
			merged = append(merged, root)
		}
	}
	for _, subject := range order {
		group := groups[subject]
		if len(group) < 2 {
			continue
		}
		var target *Container
		originals := []*Container{}
		for _, root := range group {
			if root.Message == nil && target == nil {
				target = root
			}
			if root.Message != nil && !root.Message.Reply {
				originals = append(originals, root)
			}
		}
		if target == nil {
			if len(originals) == 1 {
				target = originals[0]
			} else {
				target = &Container{Subject: subject}
			}
		}
		for _, root := range group {
			if root == target {
				continue
			}
			if root.Message != nil {
				adopt(target, root)
			} else {
				for _, child := range root.Children {
					adopt(target, child)
				}
			}
		}
		merged = append(merged, target)
	}
	return merged
}
func buildThreads(messages []*Message) []*Container {
	threader := Threader{Table: map[string]*Container{}}
	for _, message := range messages {
		threader.add(message)
	}
	roots := []*Container{}
	for _, container := range threader.Containers {
		if container.Parent == nil {
			roots = append(roots, container)
		}
	}
	roots = prune(roots, true)
	sortContainers(roots)
	roots = mergeBySubject(roots)
	sortContainers(roots)
	return roots
}
