package main

func (h *Heap) IsYoung(o *HeapObject) bool { return o.Address < h.Young }
func (h *Heap) OldBlocks() []FreeBlock     { return freeBlocks(h.Objects, h.Young, h.Size) }
func (h *Heap) WriteBarrier(target, value *HeapObject) {
	if h.IsYoung(target) {
		return
	}
	h.Barriers++
	if value != nil && h.IsYoung(value) && !h.Remembered[target] {
		h.Remembered[target] = true
		h.Remembers++
	}
}
func (h *Heap) GenerationCollection(kind string, roots []*HeapObject, line, request int) bool {
	r := newRecord(len(h.Records)+1, line, request, kind, h.FreeList())
	marking := kind == "major" || kind == "full"
	if marking {
		mark(r, roots, h.Objects)
		survivors := []*HeapObject{}
		for _, o := range h.Objects {
			if h.IsYoung(o) {
				survivors = append(survivors, o)
			} else {
				r.Work++
				if o.Marked {
					survivors = append(survivors, o)
				} else {
					r.Freed.Add(o)
					delete(h.Remembered, o)
				}
			}
		}
		h.Objects = survivors
	}
	pending := map[*HeapObject]bool{}
	for _, o := range h.Objects {
		if h.IsYoung(o) {
			pending[o] = true
		}
	}
	destination := h.Young/2 - h.Base
	target := destination
	queue := []*HeapObject{}
	evacuate := func(o *HeapObject) bool {
		if o == nil || !pending[o] {
			return true
		}
		delete(pending, o)
		o.Age++
		o.Moves++
		if kind == "tenure" || kind == "full" || o.Age >= h.PromotionAge {
			address, ok := firstFit(h.OldBlocks(), o.Size)
			if !ok {
				return false
			}
			o.Address = address
			r.Promoted.Add(o)
		} else {
			o.Address = target
			target += o.Size
		}
		r.Moved.Add(o)
		if !marking {
			r.Live.Add(o)
		}
		queue = append(queue, o)
		return true
	}
	r.Work += len(roots)
	for _, root := range roots {
		if !evacuate(root) {
			return false
		}
	}
	remembered := []*HeapObject{}
	for o := range h.Remembered {
		remembered = append(remembered, o)
	}
	for _, o := range byAddress(remembered) {
		r.Work += 1 + len(o.Fields)
		for _, child := range o.Fields {
			if !evacuate(child) {
				return false
			}
		}
	}
	for i := 0; i < len(queue); i++ {
		o := queue[i]
		r.Work += o.Size + len(o.Fields)
		for _, child := range o.Fields {
			if !evacuate(child) {
				return false
			}
		}
	}
	survivors := []*HeapObject{}
	for _, o := range h.Objects {
		if pending[o] {
			r.Freed.Add(o)
		} else {
			survivors = append(survivors, o)
		}
	}
	h.Objects = survivors
	h.Base, h.Top = destination, target
	h.Remembered = map[*HeapObject]bool{}
	for _, o := range h.Objects {
		if !h.IsYoung(o) {
			for _, child := range o.Fields {
				if child != nil && h.IsYoung(child) {
					h.Remembered[o] = true
					break
				}
			}
		}
	}
	r.Finish(h.FreeList())
	h.Records = append(h.Records, r)
	return true
}
func (h *Heap) AllocateGeneration(o *HeapObject, roots []*HeapObject, line int) bool {
	for step := 0; step <= 2; step++ {
		if h.Top+o.Size <= h.Base+h.Young/2 {
			o.Address = h.Top
			h.Top += o.Size
			h.Objects = append(h.Objects, o)
			return true
		}
		if step == 2 {
			return false
		}
		marking := largestFree(h.OldBlocks()) < h.Top-h.Base
		kind := "minor"
		if step == 0 && marking {
			kind = "major"
		}
		if step == 1 {
			kind = "tenure"
			if marking {
				kind = "full"
			}
		}
		if !h.GenerationCollection(kind, roots, line, o.Size) {
			return false
		}
	}
	return false
}
