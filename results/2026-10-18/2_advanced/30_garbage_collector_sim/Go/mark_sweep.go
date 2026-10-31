package main

func mark(record *CollectionRecord, roots, objects []*HeapObject) {
	for _, o := range objects {
		o.Marked = false
	}
	record.Work += len(roots)
	stack := []*HeapObject{}
	push := func(o *HeapObject) {
		o.Marked = true
		stack = append(stack, o)
		record.Stack = max(record.Stack, len(stack))
	}
	for _, root := range roots {
		if root == nil || root.Marked {
			continue
		}
		push(root)
		for len(stack) > 0 {
			o := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			record.Live.Add(o)
			record.Work += 1 + len(o.Fields)
			for _, child := range o.Fields {
				if child != nil && !child.Marked {
					push(child)
				}
			}
		}
	}
}
func sweep(record *CollectionRecord, objects []*HeapObject) []*HeapObject {
	record.Work += len(objects)
	survivors := []*HeapObject{}
	for _, o := range objects {
		if o.Marked {
			survivors = append(survivors, o)
		} else {
			record.Freed.Add(o)
		}
	}
	return survivors
}
func (h *Heap) SweepCollection(roots []*HeapObject, line, request int) {
	kind := "sweep"
	if h.Type == "MARK_COMPACT" {
		kind = "compact"
	}
	r := newRecord(len(h.Records)+1, line, request, kind, h.FreeList())
	mark(r, roots, h.Objects)
	if h.Type == "MARK_COMPACT" {
		r.Work += len(h.Objects) + len(roots)
		dest := 0
		survivors := []*HeapObject{}
		for _, o := range byAddress(h.Objects) {
			if !o.Marked {
				r.Freed.Add(o)
				continue
			}
			r.Work += len(o.Fields)
			if o.Address != dest {
				r.Moved.Add(o)
				r.Work += o.Size
				o.Address = dest
				o.Moves++
			}
			dest += o.Size
			survivors = append(survivors, o)
		}
		h.Top = dest
		h.Objects = survivors
	} else {
		h.Objects = sweep(r, h.Objects)
	}
	r.Finish(h.FreeList())
	h.Records = append(h.Records, r)
}
func (h *Heap) AllocateMark(o *HeapObject, roots []*HeapObject, line int) bool {
	if h.Type == "MARK_COMPACT" {
		if h.Top+o.Size > h.Size {
			h.SweepCollection(roots, line, o.Size)
		}
		if h.Top+o.Size > h.Size {
			return false
		}
		o.Address = h.Top
		h.Top += o.Size
	} else {
		address, ok := firstFit(h.FreeList(), o.Size)
		if !ok {
			if h.Type == "REFCOUNT" {
				h.Backup(roots, line, o.Size)
			} else {
				h.SweepCollection(roots, line, o.Size)
			}
			address, ok = firstFit(h.FreeList(), o.Size)
		}
		if !ok {
			return false
		}
		o.Address = address
	}
	h.Objects = append(h.Objects, o)
	return true
}
