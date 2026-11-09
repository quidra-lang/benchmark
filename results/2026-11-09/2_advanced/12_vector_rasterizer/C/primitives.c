#include "raster.h"

void point_add(Points *points,Point p) { if(points->count==points->capacity) { points->capacity=points->capacity?points->capacity*2:16; points->data=resize(points->data,points->capacity*sizeof(*points->data)); } points->data[points->count++]=p; }
void edge_add(Edges *edges,Point first,Point last) { if(edges->count==edges->capacity) { edges->capacity=edges->capacity?edges->capacity*2:16; edges->data=resize(edges->data,edges->capacity*sizeof(*edges->data)); } edges->data[edges->count++]=(Edge){first,last}; }
static void unique_point(Points *points,Point p) { for(size_t i=0;i<points->count;i++) if(points->data[i].x==p.x && points->data[i].y==p.y) return; point_add(points,p); }
Points bresenham(Point first,Point last) {
 Points points={0}; int x=first.x,y=first.y,dx=absolute(last.x-x),dy=-absolute(last.y-y),sx=x<last.x?1:-1,sy=y<last.y?1:-1,error=dx+dy;
 for(;;) { point_add(&points,(Point){x,y}); if(x==last.x && y==last.y) return points; int doubled=2*error; if(doubled>=dy) { error+=dy; x+=sx; } if(doubled<=dx) { error+=dx; y+=sy; } }
}
Points expand_square(Point p,int width) { Points points={0}; int low=-((width-1)/2); for(int j=low;j<low+width;j++) for(int i=low;i<low+width;i++) point_add(&points,(Point){p.x+i,p.y+j}); return points; }
Points circle_points(int radius) { Points points={0}; int a=radius,b=0,error=1-radius; while(a>=b) { Point next[]={{a,b},{b,a},{-b,a},{-a,b},{-a,-b},{-b,-a},{b,-a},{a,-b}}; for(int i=0;i<8;i++) unique_point(&points,next[i]); b++; if(error<0) error+=2*b+1; else { a--; error+=2*(b-a)+1; } } return points; }
static void quadrants(Points *points,int x,int y) { unique_point(points,(Point){x,y}); unique_point(points,(Point){-x,y}); unique_point(points,(Point){x,-y}); unique_point(points,(Point){-x,-y}); }
Points ellipse_points(int rx,int ry) { Points points={0}; int64_t rx2=rx*rx,ry2=ry*ry; int x=0,y=ry; unique_point(&points,(Point){0,ry}); unique_point(&points,(Point){0,-ry});
 while(ry2*x<rx2*y) { int64_t decision=4*ry2*(x+1)*(x+1)+rx2*(2*y-1)*(2*y-1)-4*rx2*ry2; x++; if(decision>=0) y--; quadrants(&points,x,y); }
 while(y>0) { int64_t decision=ry2*(2*x+1)*(2*x+1)+4*rx2*(y-1)*(y-1)-4*rx2*ry2; y--; if(decision<=0) x++; quadrants(&points,x,y); } return points;
}
Points bezier_points(const Point *controls,int count,int segments) {
 Points points={0}; int degree=count-1; int64_t scale=segments*segments; if(degree==3) scale*=segments;
 for(int i=0;i<=segments;i++) { int64_t rest=segments-i,weights[4]={rest*rest,2*i*rest,(int64_t)i*i,0}; if(degree==3) { weights[0]=rest*rest*rest; weights[1]=3*i*rest*rest; weights[2]=3*(int64_t)i*i*rest; weights[3]=(int64_t)i*i*i; } int64_t x=0,y=0; for(int k=0;k<count;k++) { x+=weights[k]*controls[k].x; y+=weights[k]*controls[k].y; } point_add(&points,(Point){round_ratio(x,scale),round_ratio(y,scale)}); } return points;
}
