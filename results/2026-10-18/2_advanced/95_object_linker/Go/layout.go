package main

type Segment struct {
	Name                                                     string
	Base, Length, Fill, Physical, FileSize, MemorySize, Used int64
	Sections                                                 []*OutputSection
	Image                                                    []byte
}
type OutputSection struct {
	Name                     string
	Segment                  *Segment
	Components               []*Component
	Address, Size, Alignment int64
}
type Component struct {
	Kind                            string
	Size, Alignment, Address        int64
	Section                         *Section
	Common                          *Resolution
	Target                          string
	Data                            []byte
	StringSections, Strings, Unique int
	OriginalSize                    int64
}
type VeneerPair struct {
	Output *OutputSection
	Target string
}

func aligned(x, n int64) int64 { return (x + n - 1) / n * n }
func outputFor(s *Section, outputs []*OutputSection) *OutputSection {
	for _, o := range outputs {
		if belongs(s.Name, o.Name) {
			return o
		}
	}
	return nil
}
func placeSegment(segment *Segment) {
	cursor := segment.Base
	segment.FileSize = 0
	for _, o := range segment.Sections {
		alignment := int64(1)
		for _, c := range o.Components {
			alignment = max(alignment, c.Alignment)
		}
		cursor = aligned(cursor, alignment)
		o.Address = cursor
		o.Alignment = alignment
		for _, c := range o.Components {
			cursor = aligned(cursor, c.Alignment)
			c.Address = cursor
			switch c.Kind {
			case "section":
				c.Section.Address = cursor
			case "common":
				c.Common.Address = cursor
			}
			cursor += c.Size
		}
		o.Size = cursor - o.Address
		if !belongs(o.Name, ".bss") {
			segment.FileSize = cursor - segment.Base
		}
	}
	segment.MemorySize = cursor - segment.Base
}
