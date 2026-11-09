package main

import "sort"

type Edge struct { start,end Point }
func fillPolygons(sequences [][]Point,rule string,c Rect) Pixels {
 edges:=[]Edge{}; for _,vertices:=range sequences { for i,start:=range vertices { end:=vertices[(i+1)%len(vertices)]; if start.y!=end.y { edges=append(edges,Edge{start,end}) } } }; pixels:=Pixels{}
 type Crossing struct { x,direction int }
 for y:=c.y0;y<=c.y1;y++ { crossings:=[]Crossing{}; for _,edge:=range edges { a,b:=edge.start,edge.end; if y<min(a.y,b.y) || y>=max(a.y,b.y) { continue }; d:=b.y-a.y; n:=2*a.x*d+(2*y+1-2*a.y)*(b.x-a.x); direction:=1; if d<0 { n,d=-n,-d; direction=-1 }; crossings=append(crossings,Crossing{floorDiv(n-d,2*d)+1,direction}) }; sort.Slice(crossings,func(i,j int)bool{if crossings[i].x!=crossings[j].x{return crossings[i].x<crossings[j].x};return crossings[i].direction<crossings[j].direction}); count,winding,index:=0,0,0
  for x:=c.x0;x<=c.x1;x++ { for index<len(crossings) && crossings[index].x<=x { count++; winding+=crossings[index].direction; index++ }; if rule=="evenodd" && count%2==1 || rule=="nonzero" && winding!=0 { pixels[Point{x,y}]=true } }
 }; return pixels
}
func fillShape(center Point,points Pixels,c Rect) Pixels { extents:=map[int]int{}; for p:=range points { extents[p.y]=max(extents[p.y],abs(p.x)) }; pixels:=Pixels{}; for dy,extent:=range extents { y:=center.y+dy; if y<c.y0 || y>c.y1 { continue }; for x:=max(c.x0,center.x-extent);x<=min(c.x1,center.x+extent);x++ { pixels[Point{x,y}]=true } }; return pixels }
func floodFill(layer *Layer,seed Point,c Rect) Pixels { target:=layer.At(seed); same:=func(p Point)bool { pixel:=layer.At(p); if target.line==0 { return pixel.line==0 }; return pixel.line!=0 && pixel.color==target.color }; pixels:=Pixels{seed:true}; pending:=[]Point{seed}; for head:=0;head<len(pending);head++ { p:=pending[head]; for _,next:=range []Point{{p.x+1,p.y},{p.x-1,p.y},{p.x,p.y+1},{p.x,p.y-1}} { if c.Contains(next) && !pixels[next] && same(next) { pixels[next]=true; pending=append(pending,next) } } }; return pixels }
