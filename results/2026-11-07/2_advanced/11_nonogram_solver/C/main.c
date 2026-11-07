#include "nonogram.h"
#include <sys/stat.h>

#define APPEND(values,count,capacity,value) do { if((count)==(capacity)) { (capacity)=(capacity)?(capacity)*2:8; (values)=resize((values),(capacity)*sizeof(*(values))); } (values)[(count)++]=(value); } while(0)

typedef struct { char **data; size_t count,capacity; } Lines;
typedef struct { Lines *data; size_t count,capacity; } Blocks;
typedef enum { LOGIC_CONTRADICTION,LOGIC_STUCK,LOGIC_SOLVED } LogicResult;
typedef enum { CONTRADICTION,NONE,UNIQUE,MULTIPLE } Status;
typedef enum { NO_DIFFICULTY,EASY,MEDIUM,HARD } Difficulty;
typedef struct { Grid grid; Propagation propagation; LogicResult result; } Logical;
typedef struct { Logical simple,logic; bool searched; Search search; Grid solutions[2]; int solution_count,line_solves,guesses,max_depth; Status status; Difficulty difficulty; } Analysis;
typedef struct {
 char name[33]; Model model; char **raw_rows,**raw_columns,**answer_lines; int row_count,column_count,answer_count;
 Given *givens; int given_count; bool has_answer; Grid answer; char error[128]; Analysis *analysis; const char *answer_result;
} Puzzle;
typedef struct { int row,column; } Point;
static const char *const status_names[]={"contradiction","none","unique","multiple"};
static const char *const difficulty_names[]={"-","easy","medium","hard"};

void *resize(void *pointer,size_t bytes) { void *result=realloc(pointer,bytes); if(!result && bytes) abort(); return result; }
static void add_text(Lines *lines,const char *text) { char *copy=resize(NULL,strlen(text)+1); strcpy(copy,text); APPEND(lines->data,lines->count,lines->capacity,copy); }
static Blocks read_blocks(const char *path) {
 FILE *file=fopen(path,"r"); if(!file) abort(); Blocks blocks={0}; Lines block={0}; char text[102];
 while(fgets(text,sizeof(text),file)) { size_t length=strlen(text); if(length && text[length-1]=='\n') text[--length]=0;
  if(block.count==0) { if(length && text[0]!='#') add_text(&block,text); } else if(strcmp(text,"END")==0) { APPEND(blocks.data,blocks.count,blocks.capacity,block); block=(Lines){0}; } else add_text(&block,text);
 }
 fclose(file); return blocks;
}
static void free_blocks(Blocks *blocks) { for(size_t k=0;k<blocks->count;k++) { Lines *lines=&blocks->data[k]; for(size_t i=0;i<lines->count;i++) free(lines->data[i]); free(lines->data); } free(blocks->data); }
static bool valid_name(const char *name) { size_t n=strlen(name); if(n<1 || n>20) return false; for(size_t i=0;i<n;i++) if(!((name[i]>='a' && name[i]<='z') || (name[i]>='0' && name[i]<='9') || name[i]=='_')) return false; return true; }
static Puzzle *parse_puzzle(const Lines *block) {
 Puzzle *p=calloc(1,sizeof(*p)); if(!p) abort(); strcpy(p->name,block->data[0]+7); sscanf(block->data[1],"SIZE %d %d",&p->model.width,&p->model.height); size_t at=3; p->raw_rows=&block->data[at]; while(strcmp(block->data[at],"COLUMNS")!=0) { p->row_count++; at++; } at++; p->raw_columns=&block->data[at];
 while(at<block->count && is_clue_line(block->data[at])) { p->column_count++; at++; }
 p->givens=resize(NULL,block->count*sizeof(*p->givens));
 while(at<block->count && strncmp(block->data[at],"GIVEN ",6)==0) { int r,c; char value; sscanf(block->data[at],"GIVEN %d %d %c",&r,&c,&value); p->givens[p->given_count++]=(Given){r-1,c-1,char_state(value)}; at++; }
 if(at<block->count) { p->has_answer=true; p->answer_lines=&block->data[at+1]; p->answer_count=(int)(block->count-at-1); } p->answer_result="-"; return p;
}
static void error_text(Puzzle *p,const char *format,...) { va_list args; va_start(args,format); vsnprintf(p->error,sizeof(p->error),format,args); va_end(args); }
static void validate(Puzzle *p,Puzzle *const *earlier,size_t earlier_count) {
 Model *m=&p->model; if(!valid_name(p->name)) { error_text(p,"bad name"); return; } for(size_t i=0;i<earlier_count;i++) if(strcmp(p->name,earlier[i]->name)==0) { error_text(p,"duplicate name"); return; }
 if(m->width<1 || m->width>30 || m->height<1 || m->height>30) { error_text(p,"bad size"); return; }
 if(p->row_count!=m->height) { error_text(p,"row count %d expected %d",p->row_count,m->height); return; } if(p->column_count!=m->width) { error_text(p,"column count %d expected %d",p->column_count,m->width); return; }
 int totals[2]={0};
 for(int kind=0;kind<2;kind++) { int count=kind?m->width:m->height,length=kind?m->height:m->width; const char *label=kind?"column":"row"; char **texts=kind?p->raw_columns:p->raw_rows; Clue *clues=kind?m->columns:m->rows;
  for(int i=0;i<count;i++) { if(!parse_clue(texts[i],&clues[i])) { error_text(p,"bad clue %s %d",label,i+1); return; } if(clue_span(&clues[i])>length) { error_text(p,"%s %d too long",label,i+1); return; } for(int k=0;k<clues[i].count;k++) totals[kind]+=clues[i].values[k]; }
 }
 if(totals[0]!=totals[1]) { error_text(p,"total mismatch rows=%d columns=%d",totals[0],totals[1]); return; }
 bool occupied[30][30]={{false}};
 for(int k=0;k<p->given_count;k++) { Given g=p->givens[k]; if(g.row<0 || g.row>=m->height || g.column<0 || g.column>=m->width || g.state==UNKNOWN) { error_text(p,"bad given %d",k+1); return; } if(occupied[g.row][g.column]) { error_text(p,"duplicate given %d",k+1); return; } occupied[g.row][g.column]=true; }
 if(p->has_answer) { if(p->answer_count!=m->height) { error_text(p,"bad answer"); return; } p->answer.width=m->width; p->answer.height=m->height; for(int r=0;r<m->height;r++) { const char *line=p->answer_lines[r]; if(strlen(line)!=(size_t)m->width) { error_text(p,"bad answer"); return; } for(int c=0;c<m->width;c++) { if(line[c]!='#' && line[c]!='.' && line[c]!='?') { error_text(p,"bad answer"); return; } p->answer.cells[r][c]=char_state(line[c]); } } }
}
static Logical logical(const Model *model,const Given *givens,int count,bool precise) {
 Logical l={.grid={.width=model->width,.height=model->height}}; for(int k=0;k<count;k++) l.grid.cells[givens[k].row][givens[k].column]=givens[k].state; bool rows[30]={false},columns[30]={false}; for(int r=0;r<model->height;r++) rows[r]=true; for(int c=0;c<model->width;c++) columns[c]=true;
 l.propagation=propagate(model,&l.grid,precise,rows,columns); l.result=l.propagation.conflict>=0?LOGIC_CONTRADICTION:determined(&l.grid)==model->width*model->height?LOGIC_SOLVED:LOGIC_STUCK; return l;
}
static Analysis *analyze(const Model *model,const Given *givens,int count) {
 Analysis *a=calloc(1,sizeof(*a)); if(!a) abort(); a->simple=logical(model,givens,count,false); a->logic=logical(model,givens,count,true); a->line_solves=(int)a->logic.propagation.count;
 if(a->logic.result==LOGIC_CONTRADICTION) a->status=CONTRADICTION;
 else if(a->logic.result==LOGIC_SOLVED) { a->status=UNIQUE; a->difficulty=a->simple.result==LOGIC_SOLVED?EASY:MEDIUM; a->solution_count=1; a->solutions[0]=a->logic.grid; }
 else { a->searched=true; search_run(model,&a->search,&a->logic.grid,1); a->solution_count=a->search.solution_count; for(int i=0;i<a->solution_count;i++) a->solutions[i]=a->search.solutions[i]; a->status=a->solution_count==0?NONE:a->solution_count==1?UNIQUE:MULTIPLE; if(a->status==UNIQUE) a->difficulty=HARD; a->line_solves+=a->search.line_solves; a->guesses=a->search.guess_count; a->max_depth=a->search.max_depth; }
 return a;
}
static void free_analysis(Analysis *a) { free(a->simple.propagation.steps); free(a->logic.propagation.steps); free(a); }
static void write_logic_result(FILE *file,const Logical *l) { if(l->result==LOGIC_CONTRADICTION) { Step s=l->propagation.steps[l->propagation.conflict]; fprintf(file,"contradiction at=%s",line_label(s.row,s.index)); } else fputs(l->result==LOGIC_SOLVED?"solved":"stuck",file); }
static void clue_stats(FILE *file,const Model *m) {
 int row_blocks=0,column_blocks=0,filled=0,largest=0,fixed=0;
 for(int kind=0;kind<2;kind++) { int count=kind?m->width:m->height,length=kind?m->height:m->width; const Clue *clues=kind?m->columns:m->rows; for(int i=0;i<count;i++) { const Clue *clue=&clues[i]; if(kind) column_blocks+=clue->count; else row_blocks+=clue->count; for(int j=0;j<clue->count;j++) { largest=maximum(largest,clue->values[j]); if(!kind) filled+=clue->values[j]; } if(clue->count==0 || clue_span(clue)==length) fixed++; } }
 fprintf(file,"row_blocks=%d column_blocks=%d filled=%d max_block=%d fixed_lines=%d",row_blocks,column_blocks,filled,largest,fixed);
}
static void features(FILE *file,const Grid *grid) {
 int h=grid->height,w=grid->width,filled=0,components=0,largest=0,min_r=h,min_c=w,max_r=-1,max_c=-1; bool visited[30][30]={{false}},symmetry[3]={true,true,true};
 for(int r=0;r<h;r++) for(int c=0;c<w;c++) { Cell state=grid->cells[r][c]; symmetry[0]=symmetry[0] && state==grid->cells[r][w-1-c]; symmetry[1]=symmetry[1] && state==grid->cells[h-1-r][c]; symmetry[2]=symmetry[2] && state==grid->cells[h-1-r][w-1-c]; if(state!=FILLED) continue; filled++; min_r=minimum(min_r,r); min_c=minimum(min_c,c); max_r=maximum(max_r,r); max_c=maximum(max_c,c); if(visited[r][c]) continue;
  Point queue[900]; int head=0,count=1; queue[0]=(Point){r,c}; visited[r][c]=true; components++;
  while(head<count) { Point cell=queue[head++]; const int dr[]={-1,1,0,0},dc[]={0,0,-1,1}; for(int i=0;i<4;i++) { int rr=cell.row+dr[i],cc=cell.column+dc[i]; if(rr>=0 && rr<h && cc>=0 && cc<w && !visited[rr][cc] && grid->cells[rr][cc]==FILLED) { visited[rr][cc]=true; queue[count++]=(Point){rr,cc}; } } } largest=maximum(largest,count);
 }
 fprintf(file,"filled=%d components=%d largest=%d bbox=",filled,components,largest); if(filled) fprintf(file,"%d,%d,%d,%d",min_r+1,min_c+1,max_r+1,max_c+1); else fputc('-',file); fputs(" symmetry=",file); bool any=false; const char *names[]={"lr","ud","rot180"}; for(int i=0;i<3;i++) if(symmetry[i]) { fprintf(file,"%s%s",any?",":"",names[i]); any=true; } if(!any) fputs("none",file);
}
static void number_list(FILE *file,const int *numbers,int count) { if(count==0) fputc('-',file); else for(int i=0;i<count;i++) fprintf(file,"%s%d",i?",":"",numbers[i]); }
static int differing(const Grid *a,const Grid *b,Point *cells) { int count=0; for(int r=0;r<a->height;r++) for(int c=0;c<a->width;c++) if(a->cells[r][c]!=b->cells[r][c]) cells[count++]=(Point){r,c}; return count; }
static int without(const Given *givens,int count,int index,Given *result) { int n=0; for(int i=0;i<count;i++) if(i!=index) result[n++]=givens[i]; return n; }
static const char *grade(FILE *file,Puzzle *p) {
 const Model *m=&p->model; const Grid *answer=&p->answer; int row_mismatch[30],column_mismatch[30],given_mismatch[900],counts[3]={0}; bool occupied[30][30]={{false}};
 for(int r=0;r<m->height;r++) if(!has_placement(answer->cells[r],m->width,&m->rows[r])) row_mismatch[counts[0]++]=r+1;
 for(int c=0;c<m->width;c++) { Cell cells[30]; int n=line_cells(answer,false,c,cells); if(!has_placement(cells,n,&m->columns[c])) column_mismatch[counts[1]++]=c+1; }
 for(int k=0;k<p->given_count;k++) { Given g=p->givens[k]; occupied[g.row][g.column]=true; Cell state=answer->cells[g.row][g.column]; if(state!=UNKNOWN && state!=g.state) given_mismatch[counts[2]++]=k+1; }
 int known=determined(answer); bool partial=known<m->width*m->height,bad=counts[0]+counts[1]+counts[2]>0; const char *result=partial?"partial":bad?"wrong":"correct";
 fprintf(file,"answer result=%s known=%d rows=",result,known); number_list(file,row_mismatch,counts[0]); fputs(" columns=",file); number_list(file,column_mismatch,counts[1]); fputs(" givens=",file); number_list(file,given_mismatch,counts[2]);
 if(partial) { bool extendable=false; if(!bad) { Given givens[900]; int count=p->given_count; memcpy(givens,p->givens,(size_t)count*sizeof(*givens)); for(int r=0;r<m->height;r++) for(int c=0;c<m->width;c++) if(answer->cells[r][c]!=UNKNOWN && !occupied[r][c]) givens[count++]=(Given){r,c,answer->cells[r][c]}; Analysis *other=analyze(m,givens,count); extendable=other->status==UNIQUE || other->status==MULTIPLE; free_analysis(other); } fprintf(file," extendable=%s",extendable?"yes":"no"); }
 if(p->analysis->status==UNIQUE) { int count=0; for(int r=0;r<m->height;r++) for(int c=0;c<m->width;c++) count+=answer->cells[r][c]!=UNKNOWN && answer->cells[r][c]!=p->analysis->solutions[0].cells[r][c]; fprintf(file," differs=%d",count); } fputc('\n',file);
 for(int kind=0;kind<2;kind++) { const int *numbers=kind?column_mismatch:row_mismatch; for(int k=0;k<counts[kind];k++) { int index=numbers[k]-1; const Clue *clue=kind?&m->columns[index]:&m->rows[index]; Cell cells[30]; int n=line_cells(answer,!kind,index,cells); fprintf(file,"mismatch %s expected=%s ",line_label(!kind,index),clue_text(clue,",")); if(partial) { char text[31]; state_string(cells,n,text); fprintf(file,"cells=%s\n",text); } else { Clue got=run_clue(cells,n); fprintf(file,"got=%s\n",clue_text(&got,",")); } } }
 return result;
}
static void puzzle_paragraph(FILE *file,Puzzle *p) {
 fprintf(file,"PUZZLE %s\n",p->name); if(*p->error) { fprintf(file,"error %s\n",p->error); return; } const Model *m=&p->model; const Analysis *a=p->analysis;
 fprintf(file,"size=%dx%d givens=%d status=%s difficulty=%s\n",m->width,m->height,p->given_count,status_names[a->status],difficulty_names[a->difficulty]); fputs("clues ",file); clue_stats(file,m); fputc('\n',file);
 fprintf(file,"simple known=%d line_solves=%zu result=",determined(&a->simple.grid),a->simple.propagation.count); write_logic_result(file,&a->simple); fputc('\n',file); fprintf(file,"logic known=%d line_solves=%zu result=",determined(&a->logic.grid),a->logic.propagation.count); write_logic_result(file,&a->logic); fputc('\n',file);
 int productive=0,idle=0,best=0; const char *at="-"; Step best_step={0};
 for(size_t k=0;k<a->logic.propagation.count;k++) { Step step=a->logic.propagation.steps[k]; if(step.contradiction) continue; if(step.gain) productive++; else idle++; if(step.gain>best) { best=step.gain; best_step=step; } } if(best) at=line_label(best_step.row,best_step.index); fprintf(file,"steps productive=%d idle=%d best=%d at=%s\n",productive,idle,best,at);
 if(m->width*m->height<=49) { fputs("trace",file); for(size_t k=0;k<a->logic.propagation.count;k++) { Step step=a->logic.propagation.steps[k]; fprintf(file," %s",line_label(step.row,step.index)); if(step.contradiction) fputc('!',file); else fprintf(file,"+%d",step.gain); } fputc('\n',file); }
 if(a->logic.result==LOGIC_STUCK) { fputs("stuck rows=",file); for(int kind=0;kind<2;kind++) { bool first=true; int count=kind?m->width:m->height; if(kind) fputs(" columns=",file); for(int i=0;i<count;i++) { Cell cells[30]; int n=line_cells(&a->logic.grid,!kind,i,cells),unknown=0; for(int j=0;j<n;j++) unknown+=cells[j]==UNKNOWN; if(unknown) { fprintf(file,"%s%d:%d",first?"":" ",i+1,unknown); first=false; } } } fputc('\n',file); }
 if(a->status==CONTRADICTION) { Step step=a->logic.propagation.steps[a->logic.propagation.conflict]; const Clue *clue=step.row?&m->rows[step.index]:&m->columns[step.index]; Cell cells[30]; char text[31]; int n=line_cells(&a->logic.grid,step.row,step.index,cells); state_string(cells,n,text); fprintf(file,"conflict line=%s clue=%s cells=%s\n",line_label(step.row,step.index),clue_text(clue,","),text); }
 if(a->searched) { const Search *s=&a->search; fprintf(file,"search guesses=%d max_depth=%d backtracks=%d solutions=%d line_solves=%d\n",s->guess_count,s->max_depth,s->backtracks,s->solution_count,s->line_solves); for(int k=0;k<s->guess_count;k++) { Guess g=s->guesses[k]; fprintf(file,"guess %d depth=%d cell=%d,%d value=%c solves=%d known=%d result=",g.number,g.depth,g.row+1,g.column+1,state_char(g.value),g.solves,g.known); if(g.result==GUESS_OPEN) fputs("open\n",file); else if(g.result==GUESS_CONTRADICTION) fprintf(file,"contradiction at=%s\n",line_label(g.conflict_row,g.conflict_index)); else fprintf(file,"solution%d\n",g.result==GUESS_SOLUTION1?1:2); } }
 if(a->status==MULTIPLE) { Point cells[900]; int count=differing(&a->solutions[0],&a->solutions[1],cells); fprintf(file,"differ count=%d cells=",count); for(int k=0;k<count;k++) fprintf(file,"%s%d,%d",k?" ":"",cells[k].row+1,cells[k].column+1); fputc('\n',file); }
 const char *names[4]; const Grid *grids[4]; int count=0;
 if(a->status==CONTRADICTION) { names[count]="partial"; grids[count++]=&a->logic.grid; } else { if(a->simple.result==LOGIC_STUCK) { names[count]="simple"; grids[count++]=&a->simple.grid; } if(a->logic.result==LOGIC_STUCK) { names[count]="logic"; grids[count++]=&a->logic.grid; } if(a->status==MULTIPLE) { names[count]="first"; grids[count++]=&a->solutions[0]; names[count]="second"; grids[count++]=&a->solutions[1]; } } if(count) grid_display(file,names,grids,count);
 if(a->status==UNIQUE) { fputs("sheet\n",file); answer_sheet(file,m,&a->solutions[0]); fputs("picture ",file); features(file,&a->solutions[0]); fputc('\n',file); }
 if(p->given_count>0 && a->status!=MULTIPLE) { int numbers[900],n=0; Given givens[900]; for(int k=0;k<p->given_count;k++) { int left=without(p->givens,p->given_count,k,givens); Analysis *other=analyze(m,givens,left); if(a->status==UNIQUE?other->status==UNIQUE:other->status==UNIQUE || other->status==MULTIPLE) numbers[n++]=k+1; free_analysis(other); } fprintf(file,"givens %s=",a->status==UNIQUE?"redundant":"blame"); number_list(file,numbers,n); fputc('\n',file); }
 if(p->has_answer) p->answer_result=grade(file,p);
}
static int compare_puzzles(const void *left,const void *right) {
 const Puzzle *a=*(const Puzzle *const *)left,*b=*(const Puzzle *const *)right;
 if(a->analysis->difficulty!=b->analysis->difficulty) return (a->analysis->difficulty>b->analysis->difficulty)-(a->analysis->difficulty<b->analysis->difficulty);
 int x=a->analysis->line_solves+25*a->analysis->guesses,y=b->analysis->line_solves+25*b->analysis->guesses; if(x!=y) return (x>y)-(x<y); return strcmp(a->name,b->name);
}
static void process_puzzles(const Blocks *blocks,Puzzle **puzzles,FILE *solutions,FILE *stats) {
 fputs("puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer\n",stats); int invalid=0,statuses[4]={0},difficulties[4]={0},line_solves=0,guesses=0; Puzzle *ranking[40]; size_t rank_count=0;
 for(size_t k=0;k<blocks->count;k++) { Puzzle *p=parse_puzzle(&blocks->data[k]); validate(p,puzzles,k); puzzles[k]=p;
  if(*p->error) invalid++; else { p->analysis=analyze(&p->model,p->givens,p->given_count); Analysis *a=p->analysis; statuses[a->status]++; difficulties[a->difficulty]++; line_solves+=a->line_solves; guesses+=a->guesses; if(a->status==UNIQUE) ranking[rank_count++]=p; }
  if(k) fputc('\n',solutions); puzzle_paragraph(solutions,p);
  if(*p->error) { fprintf(stats,"%s,invalid",p->name); for(int i=0;i<11;i++) fputs(",-",stats); fputc('\n',stats); }
  else { Analysis *a=p->analysis; fprintf(stats,"%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s\n",p->name,status_names[a->status],difficulty_names[a->difficulty],p->model.width,p->model.height,p->given_count,determined(&a->simple.grid),determined(&a->logic.grid),a->line_solves,a->guesses,a->max_depth,a->solution_count,p->answer_result); }
 }
 qsort(ranking,rank_count,sizeof(*ranking),compare_puzzles); if(blocks->count) fputc('\n',solutions); fputs("RANKING\n",solutions);
 for(size_t i=0;i<rank_count;i++) { const Puzzle *p=ranking[i]; const Analysis *a=p->analysis; fprintf(solutions,"rank %zu %s %s score=%d size=%dx%d\n",i+1,p->name,difficulty_names[a->difficulty],a->line_solves+25*a->guesses,p->model.width,p->model.height); }
 fprintf(solutions,"\nSUMMARY puzzles=%zu invalid=%d contradiction=%d none=%d unique=%d multiple=%d easy=%d medium=%d hard=%d line_solves=%d guesses=%d\n",blocks->count,invalid,statuses[CONTRADICTION],statuses[NONE],statuses[UNIQUE],statuses[MULTIPLE],difficulties[EASY],difficulties[MEDIUM],difficulties[HARD],line_solves,guesses);
}
static bool same_clues(const Puzzle *p,const Model *m) {
 if(*p->error || p->model.width!=m->width || p->model.height!=m->height) return false;
 for(int r=0;r<m->height;r++) if(!equal_clue(&p->model.rows[r],&m->rows[r])) return false;
 for(int c=0;c<m->width;c++) if(!equal_clue(&p->model.columns[c],&m->columns[c])) return false;
 return true;
}
static int compare_givens(const void *left,const void *right) { const Given *a=left,*b=right; if(a->row!=b->row) return (a->row>b->row)-(a->row<b->row); return (a->column>b->column)-(a->column<b->column); }
static void process_pictures(Puzzle *const *puzzles,size_t puzzle_count,FILE *file) {
 Blocks blocks=read_blocks("input/pictures.txt"); int invalid=0,unique=0,line_logic=0,hinted=0,hints=0;
 for(size_t k=0;k<blocks.count;k++) { const Lines *block=&blocks.data[k]; const char *name=block->data[0]+8; size_t height=block->count-1; char reason[128]="";
  if(!valid_name(name)) strcpy(reason,"bad name"); else { for(size_t i=0;i<k;i++) if(strcmp(name,blocks.data[i].data[0]+8)==0) { strcpy(reason,"duplicate name"); break; } }
  if(!*reason && (height<1 || height>30)) strcpy(reason,"bad height");
  if(!*reason) for(size_t r=0;r<height;r++) { const char *line=block->data[r+1]; size_t length=strlen(line); bool bad=length<1 || length>30 || length!=strlen(block->data[1]); for(size_t c=0;c<length;c++) if(line[c]!='#' && line[c]!='.') bad=true; if(bad) { snprintf(reason,sizeof(reason),"bad row %zu",r+1); break; } }
  if(k) fputc('\n',file);
  if(*reason) { invalid++; fprintf(file,"# picture %s error %s\n",name,reason); continue; }
  Model model={.width=(int)strlen(block->data[1]),.height=(int)height}; Grid picture={.width=model.width,.height=model.height};
  for(int r=0;r<model.height;r++) { for(int c=0;c<model.width;c++) picture.cells[r][c]=char_state(block->data[r+1][c]); model.rows[r]=run_clue(picture.cells[r],model.width); }
  for(int c=0;c<model.width;c++) { Cell cells[30]; int n=line_cells(&picture,false,c,cells); model.columns[c]=run_clue(cells,n); }
  const char *duplicate="-"; for(size_t i=0;i<puzzle_count;i++) if(same_clues(puzzles[i],&model)) { duplicate=puzzles[i]->name; break; }
  Given givens[900]; int given_count=0; Analysis *a=analyze(&model,givens,0); if(a->status==UNIQUE) unique++; if(a->difficulty==EASY || a->difficulty==MEDIUM) line_logic++;
  fprintf(file,"# picture %s size=%dx%d ",name,model.width,model.height); features(file,&picture); fputs("\n# clues ",file); clue_stats(file,&model); fprintf(file," duplicate_of=%s\n# plain status=%s difficulty=%s line_solves=%d guesses=%d\n",duplicate,status_names[a->status],difficulty_names[a->difficulty],a->line_solves,a->guesses);
  while(a->status==MULTIPLE) { Point cells[900]; differing(&a->solutions[0],&a->solutions[1],cells); Point cell=cells[0]; Given g={cell.row,cell.column,picture.cells[cell.row][cell.column]}; givens[given_count++]=g; Analysis *next=analyze(&model,givens,given_count); free_analysis(a); a=next; fprintf(file,"# hint %d cell=%d,%d value=%c status=%s\n",given_count,g.row+1,g.column+1,state_char(g.state),status_names[a->status]); }
  free_analysis(a); Given original[900]; int original_count=given_count; memcpy(original,givens,(size_t)given_count*sizeof(*givens));
  for(int i=0;i<original_count;i++) { Given g=original[i],trial[900]; int index=-1; for(int j=0;j<given_count;j++) if(givens[j].row==g.row && givens[j].column==g.column) { index=j; break; } int count=without(givens,given_count,index,trial); Analysis *other=analyze(&model,trial,count); if(other->status==UNIQUE) { memcpy(givens,trial,(size_t)count*sizeof(*givens)); given_count=count; fprintf(file,"# drop cell=%d,%d\n",g.row+1,g.column+1); } free_analysis(other); }
  a=analyze(&model,givens,given_count); int added=0;
  while(a->difficulty==HARD) { int r,c; guess_cell(&a->logic.grid,&r,&c); Given g={r,c,picture.cells[r][c]}; givens[given_count++]=g; Analysis *next=analyze(&model,givens,given_count); free_analysis(a); a=next; fprintf(file,"# logic hint %d cell=%d,%d value=%c difficulty=%s\n",++added,r+1,c+1,state_char(g.state),difficulty_names[a->difficulty]); }
  if(given_count) hinted++; hints+=given_count; fprintf(file,"# final status=%s difficulty=%s hints=%d line_solves=%d guesses=%d\nPUZZLE %s\nSIZE %d %d\nROWS\n",status_names[a->status],difficulty_names[a->difficulty],given_count,a->line_solves,a->guesses,name,model.width,model.height);
  for(int r=0;r<model.height;r++) fprintf(file,"%s\n",clue_text(&model.rows[r]," ")); fputs("COLUMNS\n",file); for(int c=0;c<model.width;c++) fprintf(file,"%s\n",clue_text(&model.columns[c]," "));
  qsort(givens,(size_t)given_count,sizeof(*givens),compare_givens); for(int i=0;i<given_count;i++) fprintf(file,"GIVEN %d %d %c\n",givens[i].row+1,givens[i].column+1,state_char(givens[i].state)); fputs("END\n",file); free_analysis(a);
 }
 if(blocks.count) fputc('\n',file); fprintf(file,"# SUMMARY pictures=%zu invalid=%d unique=%d line_logic=%d hinted=%d hints=%d\n",blocks.count,invalid,unique,line_logic,hinted,hints); free_blocks(&blocks);
}
static FILE *output_file(const char *path) { FILE *file=fopen(path,"w"); if(!file) abort(); return file; }
int main(void) {
 mkdir("output",0777); Blocks blocks=read_blocks("input/puzzles.txt"); Puzzle *puzzles[40]; FILE *solutions=output_file("output/solutions.txt"),*stats=output_file("output/stats.csv"); process_puzzles(&blocks,puzzles,solutions,stats); fclose(solutions); fclose(stats);
 FILE *generated=output_file("output/generated.txt"); process_pictures(puzzles,blocks.count,generated); fclose(generated);
 for(size_t i=0;i<blocks.count;i++) { Puzzle *p=puzzles[i]; if(p->analysis) free_analysis(p->analysis); free(p->givens); free(p); } free_blocks(&blocks); return 0;
}
