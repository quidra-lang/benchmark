#include "raster.h"

static int region_code(Point p,Rect c) { int code=0; if(p.x<c.x0) code|=1; if(p.x>c.x1) code|=2; if(p.y<c.y0) code|=4; if(p.y>c.y1) code|=8; return code; }
bool clip_segment(Point *first,Point *last,Rect c) {
 for(;;) { int a=region_code(*first,c),b=region_code(*last,c); if(a==0 && b==0) return true; if(a&b) return false; Point outside=a?*first:*last,other=a?*last:*first,next; int code=a?a:b;
  if(code&4) next=(Point){outside.x+round_ratio((int64_t)(other.x-outside.x)*(c.y0-outside.y),other.y-outside.y),c.y0};
  else if(code&8) next=(Point){outside.x+round_ratio((int64_t)(other.x-outside.x)*(c.y1-outside.y),other.y-outside.y),c.y1};
  else if(code&2) next=(Point){c.x1,outside.y+round_ratio((int64_t)(other.y-outside.y)*(c.x1-outside.x),other.x-outside.x)};
  else next=(Point){c.x0,outside.y+round_ratio((int64_t)(other.y-outside.y)*(c.x0-outside.x),other.x-outside.x)};
  if(a) *first=next; else *last=next;
 }
}
static bool inside(Point p,int axis,int limit,bool lower) { int value=axis?p.y:p.x; return lower?value>=limit:value<=limit; }
static Point crossing(Point s,Point e,int axis,int limit) { if(axis==0) return (Point){limit,s.y+round_ratio((int64_t)(limit-s.x)*(e.y-s.y),e.x-s.x)}; return (Point){s.x+round_ratio((int64_t)(limit-s.y)*(e.x-s.x),e.y-s.y),limit}; }
Points clip_polygon(const Points *input,Rect c) {
 Points vertices={0}; for(size_t i=0;i<input->count;i++) point_add(&vertices,input->data[i]); int limits[]={c.x0,c.x1+1,c.y0,c.y1+1};
 for(int boundary=0;boundary<4;boundary++) { Points output={0}; int axis=boundary/2,limit=limits[boundary]; bool lower=boundary%2==0;
  for(size_t i=0;i<vertices.count;i++) { Point s=vertices.data[(i+vertices.count-1)%vertices.count],e=vertices.data[i]; if(inside(e,axis,limit,lower)) { if(!inside(s,axis,limit,lower)) point_add(&output,crossing(s,e,axis,limit)); point_add(&output,e); } else if(inside(s,axis,limit,lower)) point_add(&output,crossing(s,e,axis,limit)); }
  free(vertices.data); vertices=output;
 } return vertices;
}
