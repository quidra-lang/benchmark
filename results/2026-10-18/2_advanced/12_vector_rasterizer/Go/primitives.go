package main

type Pixels map[Point]bool
func bresenham(start,end Point) []Point {
 x,y:=start.x,start.y; dx,dy:=abs(end.x-x),-abs(end.y-y); sx,sy:=-1,-1; if x<end.x { sx=1 }; if y<end.y { sy=1 }; error:=dx+dy; points:=[]Point{}
 for { points=append(points,Point{x,y}); if x==end.x && y==end.y { return points }; doubled:=2*error; if doubled>=dy { error+=dy; x+=sx }; if doubled<=dx { error+=dx; y+=sy } }
}
func expandSquare(p Point,width int) []Point { low:=-(width-1)/2; points:=[]Point{}; for j:=low;j<low+width;j++ { for i:=low;i<low+width;i++ { points=append(points,Point{p.x+i,p.y+j}) } }; return points }
func circlePoints(radius int) Pixels { points:=Pixels{}; a,b,error:=radius,0,1-radius; for a>=b { for _,p:=range []Point{{a,b},{b,a},{-b,a},{-a,b},{-a,-b},{-b,-a},{b,-a},{a,-b}} { points[p]=true }; b++; if error<0 { error+=2*b+1 } else { a--; error+=2*(b-a)+1 } }; return points }
func ellipsePoints(rx,ry int) Pixels {
 points:=Pixels{{0,ry}:true,{0,-ry}:true}; rx2,ry2:=rx*rx,ry*ry; x,y:=0,ry; quadrants:=func(){ for _,p:=range []Point{{x,y},{-x,y},{x,-y},{-x,-y}} { points[p]=true } }
 for ry2*x<rx2*y { decision:=4*ry2*(x+1)*(x+1)+rx2*(2*y-1)*(2*y-1)-4*rx2*ry2; x++; if decision>=0 { y-- }; quadrants() }; for y>0 { decision:=ry2*(2*x+1)*(2*x+1)+4*rx2*(y-1)*(y-1)-4*rx2*ry2; y--; if decision<=0 { x++ }; quadrants() }; return points
}
func bezierPoints(controls []Point,segments int) []Point {
 degree:=len(controls)-1; scale:=segments*segments; if degree==3 { scale*=segments }; points:=[]Point{}
 for i:=0;i<=segments;i++ { rest:=segments-i; weights:=[]int{rest*rest,2*i*rest,i*i}; if degree==3 { weights=[]int{rest*rest*rest,3*i*rest*rest,3*i*i*rest,i*i*i} }; x,y:=0,0; for k,p:=range controls { x+=weights[k]*p.x; y+=weights[k]*p.y }; points=append(points,Point{roundRatio(x,scale),roundRatio(y,scale)}) }; return points
}
