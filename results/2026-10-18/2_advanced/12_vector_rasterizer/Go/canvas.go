package main

type Color [4]int
type RGB [3]int
type Point struct { x,y int }
type Rect struct { x0,y0,x1,y1 int }
func (r Rect) Empty() bool { return r.x0>r.x1 || r.y0>r.y1 }
func (r Rect) Contains(p Point) bool { return r.x0<=p.x && p.x<=r.x1 && r.y0<=p.y && p.y<=r.y1 }
func intersection(a,b Rect) Rect { return Rect{max(a.x0,b.x0),max(a.y0,b.y0),min(a.x1,b.x1),min(a.y1,b.y1)} }
func floorDiv(n,d int) int { q:=n/d; if n<0 && n%d!=0 { q-- }; return q }
func roundRatio(n,d int) int { if d<0 { n,d=-n,-d }; return floorDiv(2*n+d,2*d) }
func abs(n int) int { if n<0 { return -n }; return n }
type Pixel struct { color Color; line int }
type Layer struct { width,height,opacity int; mode string; pixels []Pixel }
func (l *Layer) At(p Point) Pixel { return l.pixels[p.y*l.width+p.x] }
func (l *Layer) Paint(p Point,color Color,line int) { l.pixels[p.y*l.width+p.x]=Pixel{color,line} }
func (l *Layer) Erase(p Point) { l.pixels[p.y*l.width+p.x]=Pixel{} }
func (l *Layer) Alpha(p Point) int { pixel:=l.At(p); if pixel.line==0 { return 0 }; return roundRatio(pixel.color[3]*l.opacity,255) }
func composite(layers []*Layer,background Color,width,height int) []RGB {
 image:=make([]RGB,width*height)
 for y:=0;y<height;y++ { for x:=0;x<width;x++ { p:=Point{x,y}; value:=RGB{background[0],background[1],background[2]}; for _,layer:=range layers { pixel:=layer.At(p); if pixel.line==0 { continue }; alpha:=roundRatio(pixel.color[3]*layer.opacity,255); for k:=0;k<3;k++ { source:=pixel.color[k]; if layer.mode=="multiply" { source=roundRatio(source*value[k],255) } else if layer.mode=="screen" { source=255-roundRatio((255-source)*(255-value[k]),255) }; value[k]=roundRatio(alpha*source+(255-alpha)*value[k],255) } }; image[y*width+x]=value } }; return image
}
