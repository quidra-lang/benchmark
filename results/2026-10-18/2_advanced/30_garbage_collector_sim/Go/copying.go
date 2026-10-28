package main

func (h *Heap) CopyCollection(roots []*HeapObject, line, request int) {
	r := newRecord(len(h.Records)+1, line, request, "copy", h.FreeList())
	h.Base = h.Size/2 - h.Base
	h.Top = h.Base
	copied := map[*HeapObject]bool{}
	queue := []*HeapObject{}
	copyObject := func(o *HeapObject) {
		if o == nil || copied[o] {
			return
		}
		copied[o] = true
		o.Address = h.Top
		h.Top += o.Size
		o.Moves++
		r.Live.Add(o)
		r.Moved.Add(o)
		queue = append(queue, o)
	}
	r.Work += len(roots)
	for _, root := range roots {
		copyObject(root)
	}
	for i := 0; i < len(queue); i++ {
		o := queue[i]
		r.Work += o.Size + len(o.Fields)
		for _, child := range o.Fields {
			copyObject(child)
		}
	}
	for _, o := range h.Objects {
		if !copied[o] {
			r.Freed.Add(o)
		}
	}
	h.Objects = queue
	r.Finish(h.FreeList())
	h.Records = append(h.Records, r)
}
func (h *Heap) AllocateCopy(o *HeapObject, roots []*HeapObject, line int) bool {
	if h.Top+o.Size > h.Base+h.Size/2 {
		h.CopyCollection(roots, line, o.Size)
	}
	if h.Top+o.Size > h.Base+h.Size/2 {
		return false
	}
	o.Address = h.Top
	h.Top += o.Size
	h.Objects = append(h.Objects, o)
	return true
}
