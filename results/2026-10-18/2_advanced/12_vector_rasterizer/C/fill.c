#include "raster.h"

typedef struct { int x,direction; } Crossing;
static int compare_crossings(const void *left,const void *right) { const Crossing *a=left,*b=right; if(a->x!=b->x) return (a->x>b->x)-(a->x<b->x); return (a->direction>b->direction)-(a->direction<b->direction); }
Pixels fill_polygons(const Points *sequences,size_t count,const char *rule,Rect clip,int width,int height) {
 Edges edges={0}; for(size_t j=0;j<count;j++) { const Points *points=&sequences[j]; for(size_t i=0;i<points->count;i++) { Point a=points->data[i],b=points->data[(i+1)%points->count]; if(a.y!=b.y) edge_add(&edges,a,b); } }
 Pixels pixels=pixels_new(width,height); Crossing *crossings=resize(NULL,edges.count*sizeof(*crossings));
 for(int y=clip.y0;y<=clip.y1;y++) { size_t n=0; for(size_t i=0;i<edges.count;i++) { Point a=edges.data[i].first,b=edges.data[i].last; if(y<minimum(a.y,b.y) || y>=maximum(a.y,b.y)) continue; int64_t d=b.y-a.y,numerator=2*(int64_t)a.x*d+(2*y+1-2*a.y)*(int64_t)(b.x-a.x); int direction=1; if(d<0) { numerator=-numerator; d=-d; direction=-1; } crossings[n++]=(Crossing){(int)floor_div(numerator-d,2*d)+1,direction}; } if(n>1) qsort(crossings,n,sizeof(*crossings),compare_crossings); size_t index=0; int crossed=0,winding=0;
  for(int x=clip.x0;x<=clip.x1;x++) { while(index<n && crossings[index].x<=x) { crossed++; winding+=crossings[index++].direction; } if(strcmp(rule,"evenodd")==0?crossed%2==1:winding!=0) pixels_add(&pixels,(Point){x,y}); }
 }
 free(crossings); free(edges.data); return pixels;
}
Pixels fill_shape(Point center,const Points *shape,Rect clip,int width,int height) { Pixels pixels=pixels_new(width,height); for(size_t i=0;i<shape->count;i++) { Point p=shape->data[i]; int y=center.y+p.y,extent=absolute(p.x); if(y<clip.y0 || y>clip.y1) continue; for(int x=maximum(clip.x0,center.x-extent);x<=minimum(clip.x1,center.x+extent);x++) pixels_add(&pixels,(Point){x,y}); } return pixels; }
Pixels flood_fill(const Layer *layer,Point seed,Rect clip) {
 Pixels pixels=pixels_new(layer->width,layer->height); Point *queue=resize(NULL,(size_t)layer->width*(size_t)layer->height*sizeof(*queue)); size_t head=0,count=1; queue[0]=seed; pixels_add(&pixels,seed); Pixel target=layer_at(layer,seed);
 while(head<count) { Point p=queue[head++],neighbors[]={{p.x+1,p.y},{p.x-1,p.y},{p.x,p.y+1},{p.x,p.y-1}}; for(int i=0;i<4;i++) { Point next=neighbors[i]; if(!rect_contains(clip,next) || pixels.bits[next.y*layer->width+next.x]) continue; Pixel value=layer_at(layer,next); bool same=target.line?value.line && color_equal(value.color,target.color):value.line==0; if(same) { pixels_add(&pixels,next); queue[count++]=next; } } }
 free(queue); return pixels;
}
