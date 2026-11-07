#include "raster.h"

int64_t floor_div(int64_t n,int64_t d) { int64_t q=n/d; return n<0 && n%d!=0?q-1:q; }
int round_ratio(int64_t n,int64_t d) { if(d<0) { n=-n; d=-d; } return (int)floor_div(2*n+d,2*d); }
bool rect_empty(Rect r) { return r.x0>r.x1 || r.y0>r.y1; }
bool rect_contains(Rect r,Point p) { return r.x0<=p.x && p.x<=r.x1 && r.y0<=p.y && p.y<=r.y1; }
Rect rect_intersection(Rect a,Rect b) { return (Rect){maximum(a.x0,b.x0),maximum(a.y0,b.y0),minimum(a.x1,b.x1),minimum(a.y1,b.y1)}; }
Pixels pixels_new(int width,int height) { Pixels p={.width=width,.height=height}; p.bits=calloc((size_t)width*(size_t)height,sizeof(*p.bits)); if(!p.bits) abort(); return p; }
void pixels_add(Pixels *pixels,Point p) { if(p.x>=0 && p.x<pixels->width && p.y>=0 && p.y<pixels->height) pixels->bits[p.y*pixels->width+p.x]=true; }
int pixels_count(const Pixels *pixels) { int count=0; for(int i=0;i<pixels->width*pixels->height;i++) count+=pixels->bits[i]; return count; }
bool pixels_bounds(const Pixels *pixels,Rect *box) { bool found=false; for(int y=0;y<pixels->height;y++) for(int x=0;x<pixels->width;x++) if(pixels->bits[y*pixels->width+x]) { if(!found) { *box=(Rect){x,y,x,y}; found=true; } else { box->x0=minimum(box->x0,x); box->y0=minimum(box->y0,y); box->x1=maximum(box->x1,x); box->y1=maximum(box->y1,y); } } return found; }
Pixel layer_at(const Layer *layer,Point p) { return layer->pixels[p.y*layer->width+p.x]; }
void layer_paint(Layer *layer,Point p,Color color,int line) { layer->pixels[p.y*layer->width+p.x]=(Pixel){color,line}; }
void layer_erase(Layer *layer,Point p) { layer->pixels[p.y*layer->width+p.x]=(Pixel){0}; }
int layer_alpha(const Layer *layer,Point p) { Pixel pixel=layer_at(layer,p); return pixel.line?round_ratio(pixel.color.v[3]*layer->opacity,255):0; }
bool color_equal(Color a,Color b) { for(int i=0;i<4;i++) if(a.v[i]!=b.v[i]) return false; return true; }
RGB *composite(const Layer *const *layers,size_t count,Color background,int width,int height) {
 RGB *image=resize(NULL,(size_t)width*(size_t)height*sizeof(*image));
 for(int y=0;y<height;y++) for(int x=0;x<width;x++) { Point p={x,y}; RGB value={{background.v[0],background.v[1],background.v[2]}};
  for(size_t i=0;i<count;i++) { const Layer *layer=layers[i]; Pixel pixel=layer_at(layer,p); if(!pixel.line) continue; int alpha=round_ratio(pixel.color.v[3]*layer->opacity,255); for(int k=0;k<3;k++) { int source=pixel.color.v[k]; if(strcmp(layer->mode,"multiply")==0) source=round_ratio(source*value.v[k],255); else if(strcmp(layer->mode,"screen")==0) source=255-round_ratio((255-source)*(255-value.v[k]),255); value.v[k]=round_ratio(alpha*source+(255-alpha)*value.v[k],255); }
  } image[y*width+x]=value;
 } return image;
}
