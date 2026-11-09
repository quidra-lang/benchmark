package main

import (
 "fmt"
 "os"
 "sort"
 "strconv"
 "strings"
)

type ColorDef struct { value Color; used bool }
type Pen struct { width,on,off int; color *ColorDef; used bool }
type Brush struct { first,second *ColorDef; axis,rule string; used bool }
type Matrix struct { a,b,c,d,e,f int }
func (m Matrix) Transform(p Point) Point { return Point{m.a*p.x+m.b*p.y+m.e,m.c*p.x+m.d*p.y+m.f} }
func (m *Matrix) Translate(x,y int) { m.e+=m.a*x+m.b*y; m.f+=m.c*x+m.d*y }
func (m Matrix) Rectangle(p,q Point) Rect { p,q=m.Transform(p),m.Transform(q); return Rect{min(p.x,q.x),min(p.y,q.y),max(p.x,q.x),max(p.y,q.y)} }
func (m Matrix) Radii(rx,ry int) Point { return Point{abs(m.a)*rx+abs(m.b)*ry,abs(m.c)*rx+abs(m.d)*ry} }
type Pair struct { matrix Matrix; clip Rect }
type DrawingState struct { matrix Matrix; clip Rect; stack []Pair }
func (s DrawingState) Clone() DrawingState { return DrawingState{s.matrix,s.clip,append([]Pair(nil),s.stack...)} }
type SourceLine struct { number int; keyword string; arguments []string }
type Node struct { source SourceLine; repeating bool; count,dx,dy int; body []Node }
type Symbol struct { body []Node; end,uses int }
type SceneLayer struct { name string; surface *Layer; body []Node; commands,errors int }
type Font struct { width,height int; glyphs map[byte][]string }
type Probe struct { point bool; area Rect }
type KeywordTotal struct { executed,errors,pixels int }
type Scene struct {
 colors map[string]*ColorDef; pens map[string]*Pen; brushes map[string]*Brush; symbols map[string]*Symbol
 font Font; width,height int; background *ColorDef; layers []*SceneLayer; probes []Probe
 sequence,drawing,state,errors,painted,erased int; errorCounts map[string]int; keywords map[string]*KeywordTotal; log []string
}
func integer(text string) int { n,e:=strconv.Atoi(text); if e!=nil { panic(e) }; return n }
func readLines(path string) []string { data,e:=os.ReadFile(path); if e!=nil { panic(e) }; text:=strings.TrimSuffix(string(data),"\n"); if len(data)==0 { return nil }; return strings.Split(text,"\n") }
func parseBody(lines []SourceLine,position *int,ending string) ([]Node,int) {
 nodes:=[]Node{}
 for { line:=lines[*position]; (*position)++; if line.keyword==ending { return nodes,line.number }; node:=Node{source:line}; if line.keyword=="REPEAT" { node.repeating=true; node.count=integer(line.arguments[0]); node.dx=integer(line.arguments[1]); node.dy=integer(line.arguments[2]); node.body,_=parseBody(lines,position,"ENDREPEAT") }; nodes=append(nodes,node) }
}
func readScene() *Scene {
 s:=&Scene{colors:map[string]*ColorDef{},pens:map[string]*Pen{},brushes:map[string]*Brush{},symbols:map[string]*Symbol{},errorCounts:map[string]int{},keywords:map[string]*KeywordTotal{}}
 for _,line:=range readLines("input/styles.txt") { if line=="" || strings.HasPrefix(line,"#") { continue }; p:=strings.Split(line," "); switch p[0] {
 case "color": s.colors[p[1]]=&ColorDef{value:Color{integer(p[2]),integer(p[3]),integer(p[4]),integer(p[5])}}
 case "pen": s.pens[p[1]]=&Pen{width:integer(p[2]),color:s.colors[p[3]],on:integer(p[4]),off:integer(p[5])}
 case "brush": s.brushes[p[1]]=&Brush{first:s.colors[p[2]],rule:p[3]}
 case "gradient": s.brushes[p[1]]=&Brush{first:s.colors[p[2]],second:s.colors[p[3]],axis:p[4],rule:p[5]}
 } }
 lines:=readLines("input/font.txt"); header:=strings.Split(lines[0]," "); s.font=Font{integer(header[1]),integer(header[2]),map[byte][]string{}}; for at:=1;at<len(lines);at+=s.font.height+1 { character:=strings.Split(lines[at]," ")[1][0]; s.font.glyphs[character]=append([]string(nil),lines[at+1:at+1+s.font.height]...) }
 source:=[]SourceLine{}; for i,line:=range readLines("input/scene.txt") { trimmed:=strings.TrimLeft(line," "); if trimmed=="" || strings.HasPrefix(trimmed,"#") { continue }; words:=strings.Fields(trimmed); source=append(source,SourceLine{i+1,words[0],words[1:]}) }; canvas:=source[0].arguments; s.width=integer(canvas[0]); s.height=integer(canvas[1]); s.background=s.colors[canvas[2]]; s.background.used=true
 for position:=1;position<len(source); { line:=source[position]; position++; body,end:=parseBody(source,&position,"END"); if line.keyword=="SYMBOL" { s.symbols[line.arguments[0]]=&Symbol{body:body,end:end} } else { surface:=&Layer{width:s.width,height:s.height,opacity:integer(line.arguments[1]),mode:line.arguments[2],pixels:make([]Pixel,s.width*s.height)}; s.layers=append(s.layers,&SceneLayer{name:line.arguments[0],surface:surface,body:body}) } }
 lines=readLines("input/probes.txt"); count:=integer(lines[0]); for _,line:=range lines[1:count+1] { p:=strings.Split(line," "); probe:=Probe{point:p[0]=="point"}; if probe.point { x,y:=integer(p[1]),integer(p[2]); probe.area=Rect{x,y,x,y} } else { probe.area=Rect{integer(p[1]),integer(p[2]),integer(p[3]),integer(p[4])} }; s.probes=append(s.probes,probe) }; return s
}
func integerWord(word string) bool { if strings.HasPrefix(word,"-") { word=word[1:] }; if word=="" { return false }; for _,c:=range []byte(word) { if c<'0' || c>'9' { return false } }; return true }
type PathCommand struct { kind byte; values []int }
func pathData(words []string) ([]PathCommand,bool) {
 if len(words)==0 { return nil,false }; commands:=[]PathCommand{}; expectMove:=true
 for at:=0;at<len(words); { word:=words[at]; at++; if len(word)!=1 { return nil,false }; kind:=word[0]; upper:=kind; if upper>='a' && upper<='z' { upper-=32 }; count:=-1; switch upper { case 'M','L':count=2; case 'H','V':count=1; case 'Q':count=4; case 'C':count=6; case 'Z':count=0 }; if count<0 || expectMove && upper!='M' || at+count>len(words) { return nil,false }; values:=make([]int,count); for i:=0;i<count;i++ { if !integerWord(words[at+i]) { return nil,false }; values[i]=integer(words[at+i]) }; commands=append(commands,PathCommand{kind,values}); at+=count; expectMove=upper=='Z' }; return commands,true
}
var penCommands=map[string]bool{"LINE":true,"RECT":true,"CIRCLE":true,"ELLIPSE":true,"POLYLINE":true,"POLYGON":true,"PATH":true}
var brushCommands=map[string]bool{"FILLRECT":true,"FILLCIRCLE":true,"FILLELLIPSE":true,"FILLPOLYGON":true,"FILLPATH":true,"FLOOD":true,"TEXT":true}
var stateCommands=map[string]bool{"TRANSLATE":true,"SCALE":true,"ROTATE":true,"SAVE":true,"RESTORE":true,"CLIP":true,"NOCLIP":true,"USE":true}
func (s *Scene) Validate(line SourceLine,state *DrawingState) string {
 name,args:=line.keyword,line.arguments; if !penCommands[name] && !brushCommands[name] && !stateCommands[name] && name!="ERASE" { return "unknown_command" }; expected,start,end:=-1,0,len(args)
 switch name { case "LINE","RECT","FILLRECT","ELLIPSE","FILLELLIPSE":expected,start=5,1; case "CIRCLE","FILLCIRCLE":expected,start=4,1; case "FLOOD":expected,start=3,1; case "TEXT":expected,start,end=5,1,3; case "ERASE","CLIP":expected=4; case "TRANSLATE","SCALE":expected=2; case "ROTATE":expected=1; case "SAVE","RESTORE","NOCLIP":expected=0; case "USE":expected,start=3,1; case "POLYLINE","POLYGON","FILLPOLYGON":start=1; case "PATH","FILLPATH":start,end=1,2 }
 if expected>=0 && len(args)!=expected || expected<0 && len(args)<2 { return "bad_arguments" }; for i:=start;i<end;i++ { if !integerWord(args[i]) { return "bad_arguments" } }; if name=="POLYLINE" || name=="POLYGON" || name=="FILLPOLYGON" { if len(args)!=2+2*integer(args[1]) { return "bad_arguments" } }; if name=="PATH" || name=="FILLPATH" { if _,valid:=pathData(args[2:]); !valid { return "bad_arguments" } }
 if penCommands[name] && s.pens[args[0]]==nil || brushCommands[name] && s.brushes[args[0]]==nil { return "unknown_style" }; if name=="USE" { symbol:=s.symbols[args[0]]; if symbol==nil || symbol.end>line.number { return "unknown_symbol" } }; if name=="TEXT" { for _,character:=range []byte(args[4]) { if character!='_' && s.font.glyphs[character]==nil { return "unknown_glyph" } } }
 bad:=false; switch name { case "CIRCLE","FILLCIRCLE":bad=integer(args[3])<1; case "ELLIPSE","FILLELLIPSE":bad=integer(args[3])<1 || integer(args[4])<1; case "POLYLINE":bad=integer(args[1])<2; case "POLYGON","FILLPOLYGON":bad=integer(args[1])<3; case "PATH","FILLPATH":bad=integer(args[1])<1 || integer(args[1])>32; case "FLOOD":bad=!state.clip.Contains(state.matrix.Transform(Point{integer(args[1]),integer(args[2])})); case "TEXT":bad=args[3]!="left" && args[3]!="center" && args[3]!="right"; case "SCALE":bad=integer(args[0])==0 || integer(args[1])==0; case "CLIP":bad=intersection(state.clip,state.matrix.Rectangle(Point{integer(args[0]),integer(args[1])},Point{integer(args[2]),integer(args[3])})).Empty() }; if bad { return "bad_value" }; if name=="RESTORE" && len(state.stack)==0 { return "stack_empty" }; return ""
}
type Subpath struct { points []Point; closed bool }
func buildSubpaths(commands []PathCommand,segments int,matrix Matrix) []Subpath {
 subpaths:=[]Subpath{}; current,start:=Point{},Point{}
 for _,command:=range commands { kind:=command.kind; relative:=kind>='a' && kind<='z'; if relative { kind-=32 }; values:=command.values; if kind=='Z' { subpaths[len(subpaths)-1].closed=true; current=start; continue }; points:=[]Point{}
  if kind=='H' { x:=values[0]; if relative { x+=current.x }; points=[]Point{{x,current.y}} } else if kind=='V' { y:=values[0]; if relative { y+=current.y }; points=[]Point{{current.x,y}} } else { for i:=0;i<len(values);i+=2 { p:=Point{values[i],values[i+1]}; if relative { p.x+=current.x; p.y+=current.y }; points=append(points,p) } }; current=points[len(points)-1]
  if kind=='M' { start=current; subpaths=append(subpaths,Subpath{points:[]Point{matrix.Transform(current)}}) } else { subpath:=&subpaths[len(subpaths)-1]; if kind=='Q' || kind=='C' { controls:=[]Point{subpath.points[len(subpath.points)-1]}; for _,p:=range points { controls=append(controls,matrix.Transform(p)) }; subpath.points=append(subpath.points,bezierPoints(controls,segments)[1:]...) } else { subpath.points=append(subpath.points,matrix.Transform(current)) } }
 }; return subpaths
}
func addRectangle(pixels Pixels,r Rect) { for y:=r.y0;y<=r.y1;y++ { for x:=r.x0;x<=r.x1;x++ { pixels[Point{x,y}]=true } } }
func penCoverage(segments []Edge,pen *Pen,clip Rect) Pixels { pixels:=Pixels{}; index:=0; for _,segment:=range segments { start,end,valid:=clipSegment(segment.start,segment.end,clip); if !valid { continue }; for _,p:=range bresenham(start,end) { keep:=pen.off==0 || index%(pen.on+pen.off)<pen.on; index++; if keep { for _,pixel:=range expandSquare(p,pen.width) { if clip.Contains(pixel) { pixels[pixel]=true } } } } }; return pixels }
func bounds(pixels Pixels) (Rect,bool) { if len(pixels)==0 { return Rect{},false }; first:=true; var box Rect; for p:=range pixels { if first { box=Rect{p.x,p.y,p.x,p.y}; first=false } else { box=Rect{min(box.x0,p.x),min(box.y0,p.y),max(box.x1,p.x),max(box.y1,p.y)} } }; return box,true }
func boxText(pixels Pixels) string { box,exists:=bounds(pixels); if !exists { return "none" }; return fmt.Sprintf("%d %d %d %d",box.x0,box.y0,box.x1,box.y1) }
func (s *Scene) Coverage(line SourceLine,state *DrawingState,layer *Layer) Pixels {
 name,args:=line.keyword,line.arguments; matrix,clip:=state.matrix,state.clip; points:=[]Point{}; segments:=[]Edge{}; pixels:=Pixels{}
 switch name {
 case "LINE": points=[]Point{matrix.Transform(Point{integer(args[1]),integer(args[2])}),matrix.Transform(Point{integer(args[3]),integer(args[4])})}; segments=[]Edge{{points[0],points[1]}}
 case "RECT","FILLRECT","ERASE": offset:=1; if name=="ERASE" { offset=0 }; r:=matrix.Rectangle(Point{integer(args[offset]),integer(args[offset+1])},Point{integer(args[offset+2]),integer(args[offset+3])}); if name=="RECT" { points=[]Point{{r.x0,r.y0},{r.x1,r.y0},{r.x1,r.y1},{r.x0,r.y1}}; for i,p:=range points { segments=append(segments,Edge{p,points[(i+1)%4]}) } } else { addRectangle(pixels,intersection(r,clip)); if name=="ERASE" { for p:=range pixels { if layer.At(p).line==0 { delete(pixels,p) } } }; return pixels }
 case "POLYLINE","POLYGON","FILLPOLYGON": for i:=2;i<len(args);i+=2 { points=append(points,matrix.Transform(Point{integer(args[i]),integer(args[i+1])})) }; if name=="FILLPOLYGON" { return fillPolygons([][]Point{clipPolygon(points,clip)},s.brushes[args[0]].rule,clip) }; for i:=0;i<len(points)-1;i++ { segments=append(segments,Edge{points[i],points[i+1]}) }; if name=="POLYGON" { segments=append(segments,Edge{points[len(points)-1],points[0]}) }
 case "CIRCLE","FILLCIRCLE","ELLIPSE","FILLELLIPSE": center:=matrix.Transform(Point{integer(args[1]),integer(args[2])}); rx,ry:=integer(args[3]),integer(args[3]); if name=="ELLIPSE" || name=="FILLELLIPSE" { ry=integer(args[4]) }; radii:=matrix.Radii(rx,ry); shape:=Pixels{}; if (name=="CIRCLE" || name=="FILLCIRCLE") && radii.x==radii.y { shape=circlePoints(radii.x) } else { shape=ellipsePoints(radii.x,radii.y) }; if name=="FILLCIRCLE" || name=="FILLELLIPSE" { return fillShape(center,shape,clip) }; pen:=s.pens[args[0]]; for p:=range shape { for _,pixel:=range expandSquare(Point{center.x+p.x,center.y+p.y},pen.width) { if clip.Contains(pixel) { pixels[pixel]=true } } }; return pixels
 case "FLOOD": return floodFill(layer,matrix.Transform(Point{integer(args[1]),integer(args[2])}),clip)
 case "TEXT": text:=args[4]; x,y:=integer(args[1]),integer(args[2]); extent:=len(text)*(s.font.width+1)-1; if args[3]=="center" { x-=extent/2 } else if args[3]=="right" { x-=extent-1 }; for i,character:=range []byte(text) { if character=='_' { continue }; ox:=x+i*(s.font.width+1); for j,row:=range s.font.glyphs[character] { for k,dot:=range []byte(row) { if dot!='#' { continue }; r:=matrix.Rectangle(Point{ox+k,y+j},Point{ox+k+1,y+j+1}); r.x1--; r.y1--; addRectangle(pixels,intersection(r,clip)) } } }; return pixels
 case "PATH","FILLPATH": commands,_:=pathData(args[2:]); subpaths:=buildSubpaths(commands,integer(args[1]),matrix); sequences:=[][]Point{}; for _,subpath:=range subpaths { if name=="FILLPATH" { sequences=append(sequences,clipPolygon(subpath.points,clip)); continue }; for i:=0;i<len(subpath.points)-1;i++ { segments=append(segments,Edge{subpath.points[i],subpath.points[i+1]}) }; if subpath.closed { segments=append(segments,Edge{subpath.points[len(subpath.points)-1],subpath.points[0]}) } }; if name=="FILLPATH" { return fillPolygons(sequences,s.brushes[args[0]].rule,clip) }
 }; return penCoverage(segments,s.pens[args[0]],clip)
}
func (s *Scene) ExecuteBlock(layer *SceneLayer,nodes []Node,state *DrawingState) {
 for _,node:=range nodes { if node.repeating { snapshot:=state.Clone(); for k:=0;k<node.count;k++ { *state=snapshot.Clone(); state.matrix.Translate(k*node.dx,k*node.dy); s.ExecuteBlock(layer,node.body,state) }; *state=snapshot.Clone() } else { s.Execute(layer,node.source,state) } }
}
func (s *Scene) Execute(layer *SceneLayer,line SourceLine,state *DrawingState) {
 s.sequence++; layer.commands++; name,args:=line.keyword,line.arguments; total:=s.keywords[name]; if total==nil { total=&KeywordTotal{}; s.keywords[name]=total }; total.executed++; prefix:=fmt.Sprintf("cmd %d line %d %s",s.sequence,line.number,name)
 if reason:=s.Validate(line,state); reason!="" { s.errors++; layer.errors++; s.errorCounts[reason]++; total.errors++; s.log=append(s.log,prefix+" error "+reason); return }
 if penCommands[name] || brushCommands[name] || name=="ERASE" { pixels:=s.Coverage(line,state,layer.surface); s.drawing++; total.pixels+=len(pixels); if name=="ERASE" { s.erased+=len(pixels); for p:=range pixels { layer.surface.Erase(p) } } else { s.painted+=len(pixels); if penCommands[name] { pen:=s.pens[args[0]]; pen.used=true; pen.color.used=true; for p:=range pixels { layer.surface.Paint(p,pen.color.value,line.number) } } else { brush:=s.brushes[args[0]]; brush.used=true; brush.first.used=true; if brush.second!=nil { brush.second.used=true }; box,_:=bounds(pixels); for p:=range pixels { color:=brush.first.value; if brush.second!=nil { t,length:=p.x-box.x0,box.x1-box.x0; if brush.axis=="y" { t,length=p.y-box.y0,box.y1-box.y0 }; if length>0 { for k:=0;k<4;k++ { color[k]+=roundRatio((brush.second.value[k]-color[k])*t,length) } } }; layer.surface.Paint(p,color,line.number) } } }; s.log=append(s.log,fmt.Sprintf("%s pixels %d box %s",prefix,len(pixels),boxText(pixels))); return }
 s.state++; s.log=append(s.log,prefix+" ok")
 switch name { case "TRANSLATE":state.matrix.Translate(integer(args[0]),integer(args[1])); case "SCALE":x,y:=integer(args[0]),integer(args[1]); state.matrix.a*=x; state.matrix.c*=x; state.matrix.b*=y; state.matrix.d*=y; case "ROTATE":q:=(integer(args[0])%4+4)%4; for i:=0;i<q;i++ { m:=state.matrix; state.matrix.a,state.matrix.b,state.matrix.c,state.matrix.d=m.b,-m.a,m.d,-m.c }; case "SAVE":state.stack=append(state.stack,Pair{state.matrix,state.clip}); case "RESTORE":pair:=state.stack[len(state.stack)-1]; state.stack=state.stack[:len(state.stack)-1]; state.matrix,state.clip=pair.matrix,pair.clip; case "CLIP":state.clip=intersection(state.clip,state.matrix.Rectangle(Point{integer(args[0]),integer(args[1])},Point{integer(args[2]),integer(args[3])})); case "NOCLIP":state.clip=Rect{0,0,s.width-1,s.height-1}; case "USE":symbol:=s.symbols[args[0]]; symbol.uses++; snapshot:=state.Clone(); state.matrix.Translate(integer(args[1]),integer(args[2])); s.ExecuteBlock(layer,symbol.body,state); *state=snapshot.Clone() }
}
func sortedKeys[V any](values map[string]V) []string { keys:=make([]string,0,len(values)); for key:=range values { keys=append(keys,key) }; sort.Strings(keys); return keys }
type ColorCount struct { color Color; count int }
func colorCounts(counts map[Color]int) []ColorCount { colors:=make([]ColorCount,0,len(counts)); for color,count:=range counts { colors=append(colors,ColorCount{color,count}) }; sort.Slice(colors,func(i,j int)bool { if colors[i].count!=colors[j].count { return colors[i].count>colors[j].count }; for k:=0;k<4;k++ { if colors[i].color[k]!=colors[j].color[k] { return colors[i].color[k]<colors[j].color[k] } }; return false }); return colors }
func writeText(name string,lines []string) { text:=""; if len(lines)>0 { text=strings.Join(lines,"\n")+"\n" }; if e:=os.WriteFile("output/"+name,[]byte(text),0644); e!=nil { panic(e) } }
func (s *Scene) Write(image []RGB) {
 writePPM(image,s.width,s.height); writePreview(image,s.width,s.height); writeText("commands.txt",s.log); layers:=[]string{fmt.Sprintf("layers %d",len(s.layers))}
 for i,layer:=range s.layers { pixels:=Pixels{}; counts:=map[Color]int{}; visible:=0; for y:=0;y<s.height;y++ { for x:=0;x<s.width;x++ { p:=Point{x,y}; pixel:=layer.surface.At(p); if pixel.line==0 { continue }; pixels[p]=true; counts[pixel.color]++; if layer.surface.Alpha(p)>0 { covered:=false; for _,later:=range s.layers[i+1:] { if later.surface.Alpha(p)==255 { covered=true; break } }; if !covered { visible++ } } } }; layers=append(layers,fmt.Sprintf("layer %d %s opacity %d mode %s commands %d errors %d pixels %d box %s visible %d colors %d",i+1,layer.name,layer.surface.opacity,layer.surface.mode,layer.commands,layer.errors,len(pixels),boxText(pixels),visible,len(counts))); colors:=colorCounts(counts); for _,entry:=range colors[:min(5,len(colors))] { c:=entry.color; layers=append(layers,fmt.Sprintf("color %d %d %d %d pixels %d",c[0],c[1],c[2],c[3],entry.count)) } }; writeText("layers.txt",layers)
 summary:=[]string{fmt.Sprintf("canvas %d %d",s.width,s.height),fmt.Sprintf("background %d %d %d",s.background.value[0],s.background.value[1],s.background.value[2]),fmt.Sprintf("layers %d",len(s.layers)),fmt.Sprintf("symbols %d",len(s.symbols)),fmt.Sprintf("commands %d",s.sequence),fmt.Sprintf("drawing %d",s.drawing),fmt.Sprintf("state %d",s.state),fmt.Sprintf("errors %d",s.errors)}
 for _,reason:=range []string{"unknown_command","bad_arguments","unknown_style","unknown_symbol","unknown_glyph","bad_value","stack_empty"} { summary=append(summary,fmt.Sprintf("error %s %d",reason,s.errorCounts[reason])) }; counts:=map[Color]int{}; for _,rgb:=range image { counts[Color{rgb[0],rgb[1],rgb[2],0}]++ }; summary=append(summary,fmt.Sprintf("painted %d",s.painted),fmt.Sprintf("erased %d",s.erased),fmt.Sprintf("colors %d",len(counts))); colors:=colorCounts(counts); for i,entry:=range colors[:min(8,len(colors))] { c:=entry.color; summary=append(summary,fmt.Sprintf("top %d %d %d %d pixels %d",i+1,c[0],c[1],c[2],entry.count)) }; for _,name:=range sortedKeys(s.symbols) { summary=append(summary,fmt.Sprintf("symbol %s uses %d",name,s.symbols[name].uses)) }; for _,name:=range sortedKeys(s.keywords) { total:=s.keywords[name]; summary=append(summary,fmt.Sprintf("keyword %s executed %d errors %d pixels %d",name,total.executed,total.errors,total.pixels)) }
 unused:=[]string{}; for _,name:=range sortedKeys(s.colors) { if !s.colors[name].used { unused=append(unused,"unused color "+name) } }; for _,name:=range sortedKeys(s.pens) { if !s.pens[name].used { unused=append(unused,"unused pen "+name) } }; for _,name:=range sortedKeys(s.brushes) { if !s.brushes[name].used { unused=append(unused,"unused brush "+name) } }; for _,name:=range sortedKeys(s.symbols) { if s.symbols[name].uses==0 { unused=append(unused,"unused symbol "+name) } }; summary=append(summary,fmt.Sprintf("unused %d",len(unused))); summary=append(summary,unused...); writeText("summary.txt",summary)
 probes:=[]string{}; for i,probe:=range s.probes { r:=probe.area; if probe.point { p:=Point{r.x0,r.y0}; rgb:=image[p.y*s.width+p.x]; stack:=[]string{}; for j,layer:=range s.layers { if layer.surface.Alpha(p)>0 { stack=append(stack,fmt.Sprintf("%d:%d",j+1,layer.surface.At(p).line)) } }; overlap:="none"; if len(stack)>0 { overlap=strings.Join(stack," ") }; probes=append(probes,fmt.Sprintf("point %d %d %d rgb %d %d %d layers %d stack %s",i+1,p.x,p.y,rgb[0],rgb[1],rgb[2],len(stack),overlap)) } else { count:=(r.x1-r.x0+1)*(r.y1-r.y0+1); sums:=RGB{}; colors:=map[RGB]bool{}; cover:=make([]int,len(s.layers)); for y:=r.y0;y<=r.y1;y++ { for x:=r.x0;x<=r.x1;x++ { p:=Point{x,y}; rgb:=image[y*s.width+x]; colors[rgb]=true; for k:=0;k<3;k++ { sums[k]+=rgb[k] }; for j,layer:=range s.layers { if layer.surface.Alpha(p)>0 { cover[j]++ } } } }; line:=fmt.Sprintf("area %d %d %d %d %d pixels %d mean %d %d %d colors %d cover",i+1,r.x0,r.y0,r.x1,r.y1,count,sums[0]/count,sums[1]/count,sums[2]/count,len(colors)); for _,n:=range cover { line+=fmt.Sprintf(" %d",n) }; probes=append(probes,line) } }; writeText("probes.txt",probes)
}
func main() { scene:=readScene(); surfaces:=make([]*Layer,len(scene.layers)); for i,layer:=range scene.layers { state:=DrawingState{matrix:Matrix{1,0,0,1,0,0},clip:Rect{0,0,scene.width-1,scene.height-1}}; scene.ExecuteBlock(layer,layer.body,&state); surfaces[i]=layer.surface }; image:=composite(surfaces,scene.background.value,scene.width,scene.height); if e:=os.MkdirAll("output",0755); e!=nil { panic(e) }; scene.Write(image) }
