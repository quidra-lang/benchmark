#include "raster.h"
#include <sys/stat.h>

#define APPEND(values,count,capacity,value) do { if((count)==(capacity)) { (capacity)=(capacity)?(capacity)*2:8; (values)=resize((values),(capacity)*sizeof(*(values))); } (values)[(count)++]=(value); } while(0)

typedef struct { char name[25]; Color value; bool used; } ColorDef;
typedef struct { char name[25]; int width,on,off; ColorDef *color; bool used; } Pen;
typedef struct { char name[25],rule[8],axis; ColorDef *first,*second; bool used; } Brush;
typedef struct { int a,b,c,d,e,f; } Matrix;
typedef struct { Matrix matrix; Rect clip; } Pair;
typedef struct { Matrix matrix; Rect clip; Pair *stack; size_t count,capacity; } State;
typedef struct { char *text,**words,**arguments,*keyword; size_t count; int number; } SourceLine;
typedef struct Node Node;
typedef struct { Node *data; size_t count,capacity; } Nodes;
struct Node { SourceLine *source; bool repeating; int count,dx,dy; Nodes body; };
typedef struct { char name[25]; Nodes body; int end_line,uses; } Symbol;
typedef struct { char name[25]; Layer surface; Nodes body; int commands,errors; } SceneLayer;
typedef struct { int width,height; bool defined[128]; char glyphs[128][8][9]; } Font;
typedef struct { bool point; Rect area; } Probe;
typedef struct { const char *name; int executed,errors,pixels; } Keyword;
typedef struct { char **data; size_t count,capacity; } Lines;
typedef struct {
 ColorDef colors[100]; Pen pens[100]; Brush brushes[100]; Symbol symbols[20]; SceneLayer layers[20];
 int color_count,pen_count,brush_count,symbol_count,layer_count; Font font;
 SourceLine source[1000]; size_t source_count; Probe probes[50]; int probe_count,width,height; ColorDef *background;
 int sequence,drawing,state,errors,painted,erased,error_counts[8]; Keyword keywords[1000]; int keyword_count; Lines log;
} Scene;
typedef enum { CMD_UNKNOWN=-1,CMD_LINE,CMD_RECT,CMD_FILLRECT,CMD_CIRCLE,CMD_FILLCIRCLE,CMD_ELLIPSE,CMD_FILLELLIPSE,CMD_POLYLINE,CMD_POLYGON,CMD_FILLPOLYGON,CMD_PATH,CMD_FILLPATH,CMD_FLOOD,CMD_TEXT,CMD_ERASE,CMD_TRANSLATE,CMD_SCALE,CMD_ROTATE,CMD_SAVE,CMD_RESTORE,CMD_CLIP,CMD_NOCLIP,CMD_USE } Command;
typedef enum { ERROR_NONE,ERROR_UNKNOWN,ERROR_ARGUMENTS,ERROR_STYLE,ERROR_SYMBOL,ERROR_GLYPH,ERROR_VALUE,ERROR_STACK } Error;
static const char *const command_names[]={"LINE","RECT","FILLRECT","CIRCLE","FILLCIRCLE","ELLIPSE","FILLELLIPSE","POLYLINE","POLYGON","FILLPOLYGON","PATH","FILLPATH","FLOOD","TEXT","ERASE","TRANSLATE","SCALE","ROTATE","SAVE","RESTORE","CLIP","NOCLIP","USE"};
static const char *const error_names[]={"","unknown_command","bad_arguments","unknown_style","unknown_symbol","unknown_glyph","bad_value","stack_empty"};
typedef struct { char kind; int values[6]; } PathCommand;
typedef struct { PathCommand *data; size_t count,capacity; } PathCommands;
typedef struct { Points points; bool closed; } Subpath;
typedef struct { Subpath *data; size_t count,capacity; } Subpaths;

void *resize(void *pointer,size_t bytes) { void *result=realloc(pointer,bytes); if(!result && bytes) abort(); return result; }
static void add_line(Lines *lines,const char *format,...) { va_list args,copy; va_start(args,format); va_copy(copy,args); int length=vsnprintf(NULL,0,format,copy); va_end(copy); if(length<0) abort(); char *text=resize(NULL,(size_t)length+1); vsnprintf(text,(size_t)length+1,format,args); va_end(args); APPEND(lines->data,lines->count,lines->capacity,text); }
static char *read_line(FILE *file) { char *line=NULL; size_t n=0,capacity=0; int c; while((c=fgetc(file))!=EOF && c!='\n') { if(n+1>=capacity) { capacity=capacity?capacity*2:128; line=resize(line,capacity); } line[n++]=(char)c; } if(c==EOF && n==0) { free(line); return NULL; } if(n+1>=capacity) line=resize(line,n+1); line[n]=0; return line; }
static char **split_words(char *text,size_t *count) { char **parts=NULL; size_t capacity=0; *count=0; char *p=text; while(*p) { while(*p==' ') p++; if(!*p) break; char *start=p; while(*p && *p!=' ') p++; if(*p) *p++=0; APPEND(parts,*count,capacity,start); } return parts; }
static int integer(const char *text) { return (int)strtol(text,NULL,10); }
static FILE *input_file(const char *path) { FILE *file=fopen(path,"r"); if(!file) abort(); return file; }
static ColorDef *find_color(Scene *s,const char *name) { for(int i=0;i<s->color_count;i++) if(strcmp(s->colors[i].name,name)==0) return &s->colors[i]; return NULL; }
static Pen *find_pen(Scene *s,const char *name) { for(int i=0;i<s->pen_count;i++) if(strcmp(s->pens[i].name,name)==0) return &s->pens[i]; return NULL; }
static Brush *find_brush(Scene *s,const char *name) { for(int i=0;i<s->brush_count;i++) if(strcmp(s->brushes[i].name,name)==0) return &s->brushes[i]; return NULL; }
static Symbol *find_symbol(Scene *s,const char *name) { for(int i=0;i<s->symbol_count;i++) if(strcmp(s->symbols[i].name,name)==0) return &s->symbols[i]; return NULL; }
static Point transform(Matrix m,Point p) { return (Point){m.a*p.x+m.b*p.y+m.e,m.c*p.x+m.d*p.y+m.f}; }
static void translate(Matrix *m,int x,int y) { m->e+=m->a*x+m->b*y; m->f+=m->c*x+m->d*y; }
static Rect device_rectangle(Matrix m,Point p,Point q) { p=transform(m,p); q=transform(m,q); return (Rect){minimum(p.x,q.x),minimum(p.y,q.y),maximum(p.x,q.x),maximum(p.y,q.y)}; }
static State clone_state(const State *state) { State copy={.matrix=state->matrix,.clip=state->clip,.count=state->count,.capacity=state->count}; if(copy.count) { copy.stack=resize(NULL,copy.count*sizeof(*copy.stack)); memcpy(copy.stack,state->stack,copy.count*sizeof(*copy.stack)); } return copy; }
static void restore_state(State *state,const State *snapshot) { free(state->stack); *state=clone_state(snapshot); }
static Nodes parse_body(Scene *scene,size_t *position,const char *ending,int *end_line) {
 Nodes nodes={0}; for(;;) { SourceLine *line=&scene->source[(*position)++]; if(strcmp(line->keyword,ending)==0) { *end_line=line->number; return nodes; } Node node={.source=line}; if(strcmp(line->keyword,"REPEAT")==0) { node.repeating=true; node.count=integer(line->arguments[0]); node.dx=integer(line->arguments[1]); node.dy=integer(line->arguments[2]); int end; node.body=parse_body(scene,position,"ENDREPEAT",&end); } APPEND(nodes.data,nodes.count,nodes.capacity,node); }
}
static Scene *read_scene(void) {
 Scene *s=calloc(1,sizeof(*s)); if(!s) abort(); FILE *file=input_file("input/styles.txt"); char *line;
 while((line=read_line(file))) { if(!*line || line[0]=='#') { free(line); continue; } size_t count; char **p=split_words(line,&count);
  if(strcmp(p[0],"color")==0) { ColorDef *c=&s->colors[s->color_count++]; strcpy(c->name,p[1]); for(int k=0;k<4;k++) c->value.v[k]=integer(p[k+2]); }
  else if(strcmp(p[0],"pen")==0) { Pen *pen=&s->pens[s->pen_count++]; strcpy(pen->name,p[1]); pen->width=integer(p[2]); pen->color=find_color(s,p[3]); pen->on=integer(p[4]); pen->off=integer(p[5]); }
  else { Brush *b=&s->brushes[s->brush_count++]; strcpy(b->name,p[1]); b->first=find_color(s,p[2]); if(strcmp(p[0],"gradient")==0) { b->second=find_color(s,p[3]); b->axis=p[4][0]; strcpy(b->rule,p[5]); } else strcpy(b->rule,p[3]); }
  free(p); free(line);
 } fclose(file); file=input_file("input/font.txt"); line=read_line(file); sscanf(line,"font %d %d",&s->font.width,&s->font.height); free(line);
 while((line=read_line(file))) { unsigned char character=(unsigned char)line[6]; s->font.defined[character]=true; free(line); for(int j=0;j<s->font.height;j++) { line=read_line(file); strcpy(s->font.glyphs[character][j],line); free(line); } } fclose(file);
 file=input_file("input/scene.txt"); int number=0;
 while((line=read_line(file))) { number++; size_t count; char **p=split_words(line,&count); if(count==0 || p[0][0]=='#') { free(p); free(line); continue; } SourceLine source={.text=line,.words=p,.arguments=p+1,.keyword=p[0],.count=count-1,.number=number}; s->source[s->source_count++]=source; } fclose(file);
 char **canvas=s->source[0].arguments; s->width=integer(canvas[0]); s->height=integer(canvas[1]); s->background=find_color(s,canvas[2]); s->background->used=true;
 for(size_t position=1;position<s->source_count;) { SourceLine *start=&s->source[position++]; int end; Nodes body=parse_body(s,&position,"END",&end); char **args=start->arguments; if(strcmp(start->keyword,"SYMBOL")==0) { Symbol *symbol=&s->symbols[s->symbol_count++]; strcpy(symbol->name,args[0]); symbol->body=body; symbol->end_line=end; } else { SceneLayer *layer=&s->layers[s->layer_count++]; strcpy(layer->name,args[0]); layer->body=body; layer->surface.width=s->width; layer->surface.height=s->height; layer->surface.opacity=integer(args[1]); strcpy(layer->surface.mode,args[2]); layer->surface.pixels=calloc((size_t)s->width*(size_t)s->height,sizeof(Pixel)); if(!layer->surface.pixels) abort(); } }
 file=input_file("input/probes.txt"); line=read_line(file); s->probe_count=integer(line); free(line);
 for(int i=0;i<s->probe_count;i++) { line=read_line(file); size_t count; char **p=split_words(line,&count); Probe *probe=&s->probes[i]; probe->point=strcmp(p[0],"point")==0; if(probe->point) { int x=integer(p[1]),y=integer(p[2]); probe->area=(Rect){x,y,x,y}; } else probe->area=(Rect){integer(p[1]),integer(p[2]),integer(p[3]),integer(p[4])}; free(p); free(line); } fclose(file); return s;
}
static Command command_id(const char *name) { for(int i=0;i<23;i++) if(strcmp(name,command_names[i])==0) return (Command)i; return CMD_UNKNOWN; }
static bool pen_command(Command command) { return command==CMD_LINE || command==CMD_RECT || command==CMD_CIRCLE || command==CMD_ELLIPSE || command==CMD_POLYLINE || command==CMD_POLYGON || command==CMD_PATH; }
static bool brush_command(Command command) { return command==CMD_FILLRECT || command==CMD_FILLCIRCLE || command==CMD_FILLELLIPSE || command==CMD_FILLPOLYGON || command==CMD_FILLPATH || command==CMD_FLOOD || command==CMD_TEXT; }
static bool integer_word(const char *word) { if(*word=='-') word++; if(!*word) return false; for(;*word;word++) if(*word<'0' || *word>'9') return false; return true; }
static bool parse_path(char *const *words,size_t count,PathCommands *output) {
 if(count==0) return false; size_t at=0; bool expect_move=true;
 while(at<count) { const char *word=words[at++]; if(strlen(word)!=1) return false; char kind=word[0],upper=kind>='a' && kind<='z'?(char)(kind-32):kind; int n=-1; switch(upper) { case 'M':case 'L':n=2;break;case 'H':case 'V':n=1;break;case 'Q':n=4;break;case 'C':n=6;break;case 'Z':n=0;break;default:break; } if(n<0 || (expect_move && upper!='M') || at+(size_t)n>count) return false; PathCommand command={.kind=kind}; for(int i=0;i<n;i++) { if(!integer_word(words[at+(size_t)i])) return false; command.values[i]=integer(words[at+(size_t)i]); } if(output) APPEND(output->data,output->count,output->capacity,command); at+=(size_t)n; expect_move=upper=='Z'; }
 return true;
}
static Error validate(Scene *s,const SourceLine *line,const State *state,Command command) {
 if(command==CMD_UNKNOWN) return ERROR_UNKNOWN; char **args=line->arguments; size_t count=line->count,start=0,end=count; int expected=-1;
 switch(command) { case CMD_LINE:case CMD_RECT:case CMD_FILLRECT:case CMD_ELLIPSE:case CMD_FILLELLIPSE:expected=5;start=1;break;case CMD_CIRCLE:case CMD_FILLCIRCLE:expected=4;start=1;break;case CMD_FLOOD:expected=3;start=1;break;case CMD_TEXT:expected=5;start=1;end=3;break;case CMD_ERASE:case CMD_CLIP:expected=4;break;case CMD_TRANSLATE:case CMD_SCALE:expected=2;break;case CMD_ROTATE:expected=1;break;case CMD_SAVE:case CMD_RESTORE:case CMD_NOCLIP:expected=0;break;case CMD_USE:expected=3;start=1;break;case CMD_POLYLINE:case CMD_POLYGON:case CMD_FILLPOLYGON:start=1;break;case CMD_PATH:case CMD_FILLPATH:start=1;end=2;break;default:break; }
 if((expected>=0 && count!=(size_t)expected) || (expected<0 && count<2)) return ERROR_ARGUMENTS; for(size_t i=start;i<end;i++) if(!integer_word(args[i])) return ERROR_ARGUMENTS;
 if((command==CMD_POLYLINE || command==CMD_POLYGON || command==CMD_FILLPOLYGON) && (int64_t)count!=2+2*(int64_t)integer(args[1])) return ERROR_ARGUMENTS;
 if((command==CMD_PATH || command==CMD_FILLPATH) && !parse_path(args+2,count-2,NULL)) return ERROR_ARGUMENTS;
 if((pen_command(command) && !find_pen(s,args[0])) || (brush_command(command) && !find_brush(s,args[0]))) return ERROR_STYLE;
 if(command==CMD_USE) { Symbol *symbol=find_symbol(s,args[0]); if(!symbol || symbol->end_line>line->number) return ERROR_SYMBOL; }
 if(command==CMD_TEXT) for(const unsigned char *p=(const unsigned char *)args[4];*p;p++) if(*p!='_' && !s->font.defined[*p]) return ERROR_GLYPH;
 bool bad=false; switch(command) { case CMD_CIRCLE:case CMD_FILLCIRCLE:bad=integer(args[3])<1;break;case CMD_ELLIPSE:case CMD_FILLELLIPSE:bad=integer(args[3])<1 || integer(args[4])<1;break;case CMD_POLYLINE:bad=integer(args[1])<2;break;case CMD_POLYGON:case CMD_FILLPOLYGON:bad=integer(args[1])<3;break;case CMD_PATH:case CMD_FILLPATH:bad=integer(args[1])<1 || integer(args[1])>32;break;case CMD_FLOOD:bad=!rect_contains(state->clip,transform(state->matrix,(Point){integer(args[1]),integer(args[2])}));break;case CMD_TEXT:bad=strcmp(args[3],"left") && strcmp(args[3],"center") && strcmp(args[3],"right");break;case CMD_SCALE:bad=integer(args[0])==0 || integer(args[1])==0;break;case CMD_CLIP:bad=rect_empty(rect_intersection(state->clip,device_rectangle(state->matrix,(Point){integer(args[0]),integer(args[1])},(Point){integer(args[2]),integer(args[3])})));break;default:break; }
 if(bad) return ERROR_VALUE; if(command==CMD_RESTORE && state->count==0) return ERROR_STACK; return ERROR_NONE;
}
static Subpaths build_subpaths(const PathCommands *commands,int segments,Matrix matrix) {
 Subpaths paths={0}; Point current={0},start={0};
 for(size_t i=0;i<commands->count;i++) { PathCommand command=commands->data[i]; char kind=command.kind; bool relative=kind>='a' && kind<='z'; if(relative) kind=(char)(kind-32); if(kind=='Z') { paths.data[paths.count-1].closed=true; current=start; continue; } Point points[3]; int count=0;
  if(kind=='H') points[count++]=(Point){command.values[0]+(relative?current.x:0),current.y}; else if(kind=='V') points[count++]=(Point){current.x,command.values[0]+(relative?current.y:0)};
  else { int n=kind=='C'?6:kind=='Q'?4:2; for(int k=0;k<n;k+=2) points[count++]=(Point){command.values[k]+(relative?current.x:0),command.values[k+1]+(relative?current.y:0)}; } current=points[count-1];
  if(kind=='M') { start=current; Subpath path={0}; point_add(&path.points,transform(matrix,current)); APPEND(paths.data,paths.count,paths.capacity,path); }
  else { Subpath *path=&paths.data[paths.count-1]; if(kind=='Q' || kind=='C') { Point controls[4]; controls[0]=path->points.data[path->points.count-1]; for(int k=0;k<count;k++) controls[k+1]=transform(matrix,points[k]); Points curve=bezier_points(controls,count+1,segments); for(size_t k=1;k<curve.count;k++) point_add(&path->points,curve.data[k]); free(curve.data); } else point_add(&path->points,transform(matrix,current)); }
 } return paths;
}
static void free_subpaths(Subpaths *paths) { for(size_t i=0;i<paths->count;i++) free(paths->data[i].points.data); free(paths->data); }
static void add_rectangle(Pixels *pixels,Rect rectangle) { for(int y=rectangle.y0;y<=rectangle.y1;y++) for(int x=rectangle.x0;x<=rectangle.x1;x++) pixels_add(pixels,(Point){x,y}); }
static Pixels pen_coverage(const Edges *segments,const Pen *pen,Rect clip,int width,int height) {
 Pixels pixels=pixels_new(width,height); size_t index=0;
 for(size_t i=0;i<segments->count;i++) { Point first=segments->data[i].first,last=segments->data[i].last; if(!clip_segment(&first,&last,clip)) continue; Points points=bresenham(first,last);
  for(size_t j=0;j<points.count;j++) { bool keep=pen->off==0 || index%(size_t)(pen->on+pen->off)<(size_t)pen->on; index++; if(keep) { Points square=expand_square(points.data[j],pen->width); for(size_t k=0;k<square.count;k++) if(rect_contains(clip,square.data[k])) pixels_add(&pixels,square.data[k]); free(square.data); } } free(points.data);
 } return pixels;
}
static void write_box(FILE *file,const Pixels *pixels) { Rect box; if(pixels_bounds(pixels,&box)) fprintf(file,"%d %d %d %d",box.x0,box.y0,box.x1,box.y1); else fputs("none",file); }
static Pixels coverage(Scene *s,const SourceLine *line,const State *state,const Layer *layer,Command command) {
 char **args=line->arguments; Matrix matrix=state->matrix; Rect clip=state->clip; Points points={0}; Edges edges={0};
 switch(command) {
 case CMD_LINE: edge_add(&edges,transform(matrix,(Point){integer(args[1]),integer(args[2])}),transform(matrix,(Point){integer(args[3]),integer(args[4])})); break;
 case CMD_RECT:case CMD_FILLRECT:case CMD_ERASE: { int offset=command==CMD_ERASE?0:1; Rect r=device_rectangle(matrix,(Point){integer(args[offset]),integer(args[offset+1])},(Point){integer(args[offset+2]),integer(args[offset+3])});
  if(command==CMD_RECT) { Point vertices[]={{r.x0,r.y0},{r.x1,r.y0},{r.x1,r.y1},{r.x0,r.y1}}; for(int i=0;i<4;i++) edge_add(&edges,vertices[i],vertices[(i+1)%4]); }
  else { Pixels pixels=pixels_new(s->width,s->height); add_rectangle(&pixels,rect_intersection(r,clip)); if(command==CMD_ERASE) for(int y=0;y<s->height;y++) for(int x=0;x<s->width;x++) if(pixels.bits[y*s->width+x] && layer_at(layer,(Point){x,y}).line==0) pixels.bits[y*s->width+x]=false; return pixels; } break;
 }
 case CMD_POLYLINE:case CMD_POLYGON:case CMD_FILLPOLYGON:
  for(size_t i=2;i<line->count;i+=2) point_add(&points,transform(matrix,(Point){integer(args[i]),integer(args[i+1])}));
  if(command==CMD_FILLPOLYGON) { Points clipped=clip_polygon(&points,clip); Pixels pixels=fill_polygons(&clipped,1,find_brush(s,args[0])->rule,clip,s->width,s->height); free(points.data); free(clipped.data); return pixels; }
  for(size_t i=0;i+1<points.count;i++) edge_add(&edges,points.data[i],points.data[i+1]); if(command==CMD_POLYGON) edge_add(&edges,points.data[points.count-1],points.data[0]); break;
 case CMD_CIRCLE:case CMD_FILLCIRCLE:case CMD_ELLIPSE:case CMD_FILLELLIPSE: { Point center=transform(matrix,(Point){integer(args[1]),integer(args[2])}); int rx=integer(args[3]),ry=(command==CMD_ELLIPSE || command==CMD_FILLELLIPSE)?integer(args[4]):rx; int device_rx=absolute(matrix.a)*rx+absolute(matrix.b)*ry,device_ry=absolute(matrix.c)*rx+absolute(matrix.d)*ry; Points shape=((command==CMD_CIRCLE || command==CMD_FILLCIRCLE) && device_rx==device_ry)?circle_points(device_rx):ellipse_points(device_rx,device_ry); Pixels pixels;
  if(command==CMD_FILLCIRCLE || command==CMD_FILLELLIPSE) pixels=fill_shape(center,&shape,clip,s->width,s->height);
  else { pixels=pixels_new(s->width,s->height); Pen *pen=find_pen(s,args[0]); for(size_t i=0;i<shape.count;i++) { Points square=expand_square((Point){center.x+shape.data[i].x,center.y+shape.data[i].y},pen->width); for(size_t j=0;j<square.count;j++) if(rect_contains(clip,square.data[j])) pixels_add(&pixels,square.data[j]); free(square.data); } } free(shape.data); return pixels;
 }
 case CMD_FLOOD: return flood_fill(layer,transform(matrix,(Point){integer(args[1]),integer(args[2])}),clip);
 case CMD_TEXT: { const char *text=args[4]; int x=integer(args[1]),y=integer(args[2]),extent=(int)strlen(text)*(s->font.width+1)-1; if(strcmp(args[3],"center")==0) x-=extent/2; else if(strcmp(args[3],"right")==0) x-=extent-1; Pixels pixels=pixels_new(s->width,s->height);
  for(size_t i=0;text[i];i++) { unsigned char character=(unsigned char)text[i]; if(character=='_') continue; int ox=x+(int)i*(s->font.width+1); for(int j=0;j<s->font.height;j++) for(int k=0;k<s->font.width;k++) if(s->font.glyphs[character][j][k]=='#') { Rect r=device_rectangle(matrix,(Point){ox+k,y+j},(Point){ox+k+1,y+j+1}); r.x1--; r.y1--; add_rectangle(&pixels,rect_intersection(r,clip)); } } return pixels;
 }
 case CMD_PATH:case CMD_FILLPATH: { PathCommands commands={0}; parse_path(args+2,line->count-2,&commands); Subpaths paths=build_subpaths(&commands,integer(args[1]),matrix); free(commands.data);
  if(command==CMD_FILLPATH) { Points *sequences=resize(NULL,paths.count*sizeof(*sequences)); for(size_t i=0;i<paths.count;i++) sequences[i]=clip_polygon(&paths.data[i].points,clip); Pixels pixels=fill_polygons(sequences,paths.count,find_brush(s,args[0])->rule,clip,s->width,s->height); for(size_t i=0;i<paths.count;i++) free(sequences[i].data); free(sequences); free_subpaths(&paths); return pixels; }
  for(size_t i=0;i<paths.count;i++) { const Subpath *path=&paths.data[i]; for(size_t j=0;j+1<path->points.count;j++) edge_add(&edges,path->points.data[j],path->points.data[j+1]); if(path->closed) edge_add(&edges,path->points.data[path->points.count-1],path->points.data[0]); } free_subpaths(&paths); break;
 }
 default:abort();
 }
 Pixels pixels=pen_coverage(&edges,find_pen(s,args[0]),clip,s->width,s->height); free(points.data); free(edges.data); return pixels;
}
static Keyword *keyword_total(Scene *s,const char *name) { for(int i=0;i<s->keyword_count;i++) if(strcmp(s->keywords[i].name,name)==0) return &s->keywords[i]; Keyword *total=&s->keywords[s->keyword_count++]; total->name=name; return total; }
static void execute(Scene *s,SceneLayer *layer,const SourceLine *line,State *state);
static void execute_block(Scene *s,SceneLayer *layer,const Nodes *nodes,State *state) {
 for(size_t i=0;i<nodes->count;i++) { const Node *node=&nodes->data[i]; if(node->repeating) { State snapshot=clone_state(state); for(int k=0;k<node->count;k++) { restore_state(state,&snapshot); translate(&state->matrix,k*node->dx,k*node->dy); execute_block(s,layer,&node->body,state); } restore_state(state,&snapshot); free(snapshot.stack); } else execute(s,layer,node->source,state); }
}
static void execute(Scene *s,SceneLayer *layer,const SourceLine *line,State *state) {
 int sequence=++s->sequence; layer->commands++; Keyword *total=keyword_total(s,line->keyword); total->executed++; Command command=command_id(line->keyword); Error error=validate(s,line,state,command); char **args=line->arguments;
 if(error!=ERROR_NONE) { s->errors++; layer->errors++; s->error_counts[error]++; total->errors++; add_line(&s->log,"cmd %d line %d %s error %s",sequence,line->number,line->keyword,error_names[error]); return; }
 if(pen_command(command) || brush_command(command) || command==CMD_ERASE) {
  Pixels pixels=coverage(s,line,state,&layer->surface,command); int count=pixels_count(&pixels); s->drawing++; total->pixels+=count;
  if(command==CMD_ERASE) { s->erased+=count; for(int y=0;y<s->height;y++) for(int x=0;x<s->width;x++) if(pixels.bits[y*s->width+x]) layer_erase(&layer->surface,(Point){x,y}); }
  else { s->painted+=count; Pen *pen=pen_command(command)?find_pen(s,args[0]):NULL; Brush *brush=pen?NULL:find_brush(s,args[0]); Rect box={0}; pixels_bounds(&pixels,&box);
   if(pen) { pen->used=true; pen->color->used=true; } else { brush->used=true; brush->first->used=true; if(brush->second) brush->second->used=true; }
   for(int y=0;y<s->height;y++) for(int x=0;x<s->width;x++) if(pixels.bits[y*s->width+x]) { Color color=pen?pen->color->value:brush->first->value; if(brush && brush->second) { int t=brush->axis=='x'?x-box.x0:y-box.y0,length=brush->axis=='x'?box.x1-box.x0:box.y1-box.y0; if(length>0) for(int k=0;k<4;k++) color.v[k]+=round_ratio((brush->second->value.v[k]-color.v[k])*t,length); } layer_paint(&layer->surface,(Point){x,y},color,line->number); }
  }
  Rect box; if(pixels_bounds(&pixels,&box)) add_line(&s->log,"cmd %d line %d %s pixels %d box %d %d %d %d",sequence,line->number,line->keyword,count,box.x0,box.y0,box.x1,box.y1); else add_line(&s->log,"cmd %d line %d %s pixels %d box none",sequence,line->number,line->keyword,count); free(pixels.bits); return;
 }
 s->state++; add_line(&s->log,"cmd %d line %d %s ok",sequence,line->number,line->keyword); Matrix *m=&state->matrix;
 switch(command) {
 case CMD_TRANSLATE:translate(m,integer(args[0]),integer(args[1]));break;
 case CMD_SCALE: { int x=integer(args[0]),y=integer(args[1]); m->a*=x; m->c*=x; m->b*=y; m->d*=y; break; }
 case CMD_ROTATE: { int q=(integer(args[0])%4+4)%4; for(int i=0;i<q;i++) { Matrix before=*m; m->a=before.b; m->b=-before.a; m->c=before.d; m->d=-before.c; } break; }
 case CMD_SAVE: { Pair pair={state->matrix,state->clip}; APPEND(state->stack,state->count,state->capacity,pair); break; }
 case CMD_RESTORE: { Pair pair=state->stack[--state->count]; state->matrix=pair.matrix; state->clip=pair.clip; break; }
 case CMD_CLIP:state->clip=rect_intersection(state->clip,device_rectangle(*m,(Point){integer(args[0]),integer(args[1])},(Point){integer(args[2]),integer(args[3])}));break;
 case CMD_NOCLIP:state->clip=(Rect){0,0,s->width-1,s->height-1};break;
 case CMD_USE: { Symbol *symbol=find_symbol(s,args[0]); symbol->uses++; State snapshot=clone_state(state); translate(m,integer(args[1]),integer(args[2])); execute_block(s,layer,&symbol->body,state); restore_state(state,&snapshot); free(snapshot.stack); break; }
 default:abort();
 }
}
typedef struct { Color color; int count; } ColorCount;
typedef struct { ColorCount *data; size_t count; } ColorTable;
static int compare_colors(const void *left,const void *right) { const Color *a=left,*b=right; for(int k=0;k<4;k++) if(a->v[k]!=b->v[k]) return (a->v[k]>b->v[k])-(a->v[k]<b->v[k]); return 0; }
static int compare_color_counts(const void *left,const void *right) { const ColorCount *a=left,*b=right; if(a->count!=b->count) return (a->count<b->count)-(a->count>b->count); return compare_colors(&a->color,&b->color); }
static ColorTable color_table(Color *values,size_t count) { if(count>1) qsort(values,count,sizeof(*values),compare_colors); ColorTable table={.data=resize(NULL,count*sizeof(*table.data))}; for(size_t i=0;i<count;i++) { if(table.count && color_equal(values[i],table.data[table.count-1].color)) table.data[table.count-1].count++; else table.data[table.count++]=(ColorCount){values[i],1}; } if(table.count>1) qsort(table.data,table.count,sizeof(*table.data),compare_color_counts); return table; }
static int compare_names(const void *left,const void *right) { const char *const *a=left,*const *b=right; return strcmp(*a,*b); }
static int compare_symbols(const void *left,const void *right) { const Symbol *const *a=left,*const *b=right; return strcmp((*a)->name,(*b)->name); }
static int compare_keywords(const void *left,const void *right) { const Keyword *const *a=left,*const *b=right; return strcmp((*a)->name,(*b)->name); }
static FILE *output_file(const char *path) { FILE *file=fopen(path,"w"); if(!file) abort(); return file; }
static void output(Scene *s,const RGB *image) {
 write_ppm(image,s->width,s->height); write_preview(image,s->width,s->height); FILE *file=output_file("output/commands.txt"); for(size_t i=0;i<s->log.count;i++) fprintf(file,"%s\n",s->log.data[i]); fclose(file);
 file=output_file("output/layers.txt"); fprintf(file,"layers %d\n",s->layer_count);
 for(int i=0;i<s->layer_count;i++) { const SceneLayer *layer=&s->layers[i]; Pixels pixels=pixels_new(s->width,s->height); Color *values=resize(NULL,(size_t)s->width*(size_t)s->height*sizeof(*values)); size_t count=0; int visible=0;
  for(int y=0;y<s->height;y++) for(int x=0;x<s->width;x++) { Point p={x,y}; Pixel pixel=layer_at(&layer->surface,p); if(!pixel.line) continue; pixels_add(&pixels,p); values[count++]=pixel.color; if(layer_alpha(&layer->surface,p)>0) { bool covered=false; for(int j=i+1;j<s->layer_count;j++) if(layer_alpha(&s->layers[j].surface,p)==255) { covered=true; break; } if(!covered) visible++; } }
  ColorTable colors=color_table(values,count); fprintf(file,"layer %d %s opacity %d mode %s commands %d errors %d pixels %zu box ",i+1,layer->name,layer->surface.opacity,layer->surface.mode,layer->commands,layer->errors,count); write_box(file,&pixels); fprintf(file," visible %d colors %zu\n",visible,colors.count);
  for(size_t k=0;k<colors.count && k<5;k++) { ColorCount entry=colors.data[k]; fprintf(file,"color %d %d %d %d pixels %d\n",entry.color.v[0],entry.color.v[1],entry.color.v[2],entry.color.v[3],entry.count); } free(colors.data); free(values); free(pixels.bits);
 } fclose(file);
 file=output_file("output/summary.txt"); fprintf(file,"canvas %d %d\nbackground %d %d %d\nlayers %d\nsymbols %d\ncommands %d\ndrawing %d\nstate %d\nerrors %d\n",s->width,s->height,s->background->value.v[0],s->background->value.v[1],s->background->value.v[2],s->layer_count,s->symbol_count,s->sequence,s->drawing,s->state,s->errors);
 for(int i=1;i<8;i++) fprintf(file,"error %s %d\n",error_names[i],s->error_counts[i]); size_t area=(size_t)s->width*(size_t)s->height; Color *values=resize(NULL,area*sizeof(*values)); for(size_t i=0;i<area;i++) values[i]=(Color){{image[i].v[0],image[i].v[1],image[i].v[2],0}}; ColorTable colors=color_table(values,area);
 fprintf(file,"painted %d\nerased %d\ncolors %zu\n",s->painted,s->erased,colors.count); for(size_t i=0;i<colors.count && i<8;i++) { ColorCount entry=colors.data[i]; fprintf(file,"top %zu %d %d %d pixels %d\n",i+1,entry.color.v[0],entry.color.v[1],entry.color.v[2],entry.count); } free(colors.data); free(values);
 const Symbol *symbols[20]; for(int i=0;i<s->symbol_count;i++) symbols[i]=&s->symbols[i]; if(s->symbol_count>1) qsort(symbols,(size_t)s->symbol_count,sizeof(*symbols),compare_symbols); for(int i=0;i<s->symbol_count;i++) fprintf(file,"symbol %s uses %d\n",symbols[i]->name,symbols[i]->uses);
 const Keyword *keywords[1000]; for(int i=0;i<s->keyword_count;i++) keywords[i]=&s->keywords[i]; if(s->keyword_count>1) qsort(keywords,(size_t)s->keyword_count,sizeof(*keywords),compare_keywords); for(int i=0;i<s->keyword_count;i++) { const Keyword *total=keywords[i]; fprintf(file,"keyword %s executed %d errors %d pixels %d\n",total->name,total->executed,total->errors,total->pixels); }
 int unused=0; for(int i=0;i<s->color_count;i++) unused+=!s->colors[i].used; for(int i=0;i<s->pen_count;i++) unused+=!s->pens[i].used; for(int i=0;i<s->brush_count;i++) unused+=!s->brushes[i].used; for(int i=0;i<s->symbol_count;i++) unused+=s->symbols[i].uses==0; fprintf(file,"unused %d\n",unused);
 const char *kinds[]={"color","pen","brush","symbol"}; for(int kind=0;kind<4;kind++) { const char *names[100]; size_t count=0; if(kind==0) for(int i=0;i<s->color_count;i++) { if(!s->colors[i].used) names[count++]=s->colors[i].name; } if(kind==1) for(int i=0;i<s->pen_count;i++) { if(!s->pens[i].used) names[count++]=s->pens[i].name; } if(kind==2) for(int i=0;i<s->brush_count;i++) { if(!s->brushes[i].used) names[count++]=s->brushes[i].name; } if(kind==3) for(int i=0;i<s->symbol_count;i++) { if(s->symbols[i].uses==0) names[count++]=s->symbols[i].name; } if(count>1) qsort(names,count,sizeof(*names),compare_names); for(size_t i=0;i<count;i++) fprintf(file,"unused %s %s\n",kinds[kind],names[i]); } fclose(file);
 file=output_file("output/probes.txt");
 for(int i=0;i<s->probe_count;i++) { Probe probe=s->probes[i]; Rect r=probe.area;
  if(probe.point) { Point p={r.x0,r.y0}; RGB rgb=image[p.y*s->width+p.x]; int count=0; for(int j=0;j<s->layer_count;j++) count+=layer_alpha(&s->layers[j].surface,p)>0; fprintf(file,"point %d %d %d rgb %d %d %d layers %d stack",i+1,p.x,p.y,rgb.v[0],rgb.v[1],rgb.v[2],count); if(count==0) fputs(" none",file); else for(int j=0;j<s->layer_count;j++) if(layer_alpha(&s->layers[j].surface,p)>0) fprintf(file," %d:%d",j+1,layer_at(&s->layers[j].surface,p).line); fputc('\n',file); }
  else { int count=(r.x1-r.x0+1)*(r.y1-r.y0+1),sums[3]={0},cover[20]={0}; Color *samples=resize(NULL,(size_t)count*sizeof(*samples)); size_t n=0;
   for(int y=r.y0;y<=r.y1;y++) for(int x=r.x0;x<=r.x1;x++) { Point p={x,y}; RGB rgb=image[y*s->width+x]; samples[n++]=(Color){{rgb.v[0],rgb.v[1],rgb.v[2],0}}; for(int k=0;k<3;k++) sums[k]+=rgb.v[k]; for(int j=0;j<s->layer_count;j++) cover[j]+=layer_alpha(&s->layers[j].surface,p)>0; }
   ColorTable counts=color_table(samples,n); fprintf(file,"area %d %d %d %d %d pixels %d mean %d %d %d colors %zu cover",i+1,r.x0,r.y0,r.x1,r.y1,count,sums[0]/count,sums[1]/count,sums[2]/count,counts.count); for(int j=0;j<s->layer_count;j++) fprintf(file," %d",cover[j]); fputc('\n',file); free(counts.data); free(samples);
  }
 } fclose(file);
}
static void free_nodes(Nodes *nodes) { for(size_t i=0;i<nodes->count;i++) free_nodes(&nodes->data[i].body); free(nodes->data); }
static void destroy(Scene *s) { for(int i=0;i<s->layer_count;i++) { free_nodes(&s->layers[i].body); free(s->layers[i].surface.pixels); } for(int i=0;i<s->symbol_count;i++) free_nodes(&s->symbols[i].body); for(size_t i=0;i<s->source_count;i++) { free(s->source[i].words); free(s->source[i].text); } for(size_t i=0;i<s->log.count;i++) free(s->log.data[i]); free(s->log.data); free(s); }
int main(void) { Scene *scene=read_scene(); const Layer *surfaces[20]; for(int i=0;i<scene->layer_count;i++) { State state={.matrix={1,0,0,1,0,0},.clip={0,0,scene->width-1,scene->height-1}}; execute_block(scene,&scene->layers[i],&scene->layers[i].body,&state); free(state.stack); surfaces[i]=&scene->layers[i].surface; } RGB *image=composite(surfaces,(size_t)scene->layer_count,scene->background->value,scene->width,scene->height); mkdir("output",0777); output(scene,image); free(image); destroy(scene); return 0; }
