#ifndef RASTER_H
#define RASTER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef struct { int x,y; } Point;
typedef struct { int x0,y0,x1,y1; } Rect;
typedef struct { int v[4]; } Color;
typedef struct { int v[3]; } RGB;
typedef struct { Point *data; size_t count,capacity; } Points;
typedef struct { Point first,last; } Edge;
typedef struct { Edge *data; size_t count,capacity; } Edges;
typedef struct { int width,height; bool *bits; } Pixels;
typedef struct { Color color; int line; } Pixel;
typedef struct { int width,height,opacity; char mode[9]; Pixel *pixels; } Layer;
void *resize(void *pointer,size_t bytes);
int64_t floor_div(int64_t numerator,int64_t denominator);
int round_ratio(int64_t numerator,int64_t denominator);
bool rect_empty(Rect rectangle);
bool rect_contains(Rect rectangle,Point point);
Rect rect_intersection(Rect a,Rect b);
Pixels pixels_new(int width,int height);
void pixels_add(Pixels *pixels,Point point);
int pixels_count(const Pixels *pixels);
bool pixels_bounds(const Pixels *pixels,Rect *box);
Pixel layer_at(const Layer *layer,Point point);
void layer_paint(Layer *layer,Point point,Color color,int line);
void layer_erase(Layer *layer,Point point);
int layer_alpha(const Layer *layer,Point point);
bool color_equal(Color a,Color b);
RGB *composite(const Layer *const *layers,size_t count,Color background,int width,int height);
void point_add(Points *points,Point point);
void edge_add(Edges *edges,Point first,Point last);
Points bresenham(Point first,Point last);
Points expand_square(Point point,int width);
Points circle_points(int radius);
Points ellipse_points(int rx,int ry);
Points bezier_points(const Point *controls,int count,int segments);
bool clip_segment(Point *first,Point *last,Rect clip);
Points clip_polygon(const Points *vertices,Rect clip);
Pixels fill_polygons(const Points *sequences,size_t count,const char *rule,Rect clip,int width,int height);
Pixels fill_shape(Point center,const Points *shape,Rect clip,int width,int height);
Pixels flood_fill(const Layer *layer,Point seed,Rect clip);
void write_ppm(const RGB *image,int width,int height);
void write_preview(const RGB *image,int width,int height);
static inline int minimum(int a,int b) { return a<b?a:b; }
static inline int maximum(int a,int b) { return a>b?a:b; }
static inline int absolute(int n) { return n<0?-n:n; }
#endif
