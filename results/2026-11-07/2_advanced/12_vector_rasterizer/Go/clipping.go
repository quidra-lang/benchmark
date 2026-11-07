package main

func regionCode(p Point,c Rect) int { code:=0; if p.x<c.x0 { code|=1 }; if p.x>c.x1 { code|=2 }; if p.y<c.y0 { code|=4 }; if p.y>c.y1 { code|=8 }; return code }
func clipSegment(start,end Point,c Rect) (Point,Point,bool) {
 for { a,b:=regionCode(start,c),regionCode(end,c); if a==0 && b==0 { return start,end,true }; if a&b!=0 { return start,end,false }; outside,other,code:=start,end,a; if a==0 { outside,other,code=end,start,b }; var next Point
  if code&4!=0 { next=Point{outside.x+roundRatio((other.x-outside.x)*(c.y0-outside.y),other.y-outside.y),c.y0} } else if code&8!=0 { next=Point{outside.x+roundRatio((other.x-outside.x)*(c.y1-outside.y),other.y-outside.y),c.y1} } else if code&2!=0 { next=Point{c.x1,outside.y+roundRatio((other.y-outside.y)*(c.x1-outside.x),other.x-outside.x)} } else { next=Point{c.x0,outside.y+roundRatio((other.y-outside.y)*(c.x0-outside.x),other.x-outside.x)} }; if a!=0 { start=next } else { end=next }
 }
}
func clipPolygon(vertices []Point,c Rect) []Point {
 for boundary,limit:=range []int{c.x0,c.x1+1,c.y0,c.y1+1} { axis:=boundary/2; lower:=boundary%2==0; coordinate:=func(p Point)int { if axis==0 { return p.x }; return p.y }; inside:=func(p Point)bool { if lower { return coordinate(p)>=limit }; return coordinate(p)<=limit }; cross:=func(s,e Point)Point { if axis==0 { return Point{limit,s.y+roundRatio((limit-s.x)*(e.y-s.y),e.x-s.x)} }; return Point{s.x+roundRatio((limit-s.y)*(e.x-s.x),e.y-s.y),limit} }; output:=[]Point{}
  for i,end:=range vertices { start:=vertices[(i+len(vertices)-1)%len(vertices)]; if inside(end) { if !inside(start) { output=append(output,cross(start,end)) }; output=append(output,end) } else if inside(start) { output=append(output,cross(start,end)) } }; vertices=output
 }; return vertices
}
