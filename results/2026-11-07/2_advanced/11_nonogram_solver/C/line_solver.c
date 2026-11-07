#include "nonogram.h"

typedef struct { const Cell *cells; const Clue *clue; int length; bool before[31][51],after[31][51]; } Placements;
static void fit_table(const Cell *cells,int n,const Clue *clue,bool table[31][51]) {
 memset(table,0,31*51*sizeof(bool)); int empties[31]={0}; for(int i=0;i<n;i++) empties[i+1]=empties[i]+(cells[i]==EMPTY); table[0][0]=true;
 for(int end=1;end<=n;end++) for(int count=0;count<=clue->count;count++) { bool fits=cells[end-1]!=FILLED && table[end-1][count]; if(!fits && count>0) { int start=end-clue->values[count-1]; if(start>=0 && empties[end]==empties[start]) fits=start==0?count==1:cells[start-1]!=FILLED && table[start-1][count-1]; } table[end][count]=fits; }
}
static void prepare(Placements *p,const Cell *cells,int n,const Clue *clue) {
 p->cells=cells; p->clue=clue; p->length=n; fit_table(cells,n,clue,p->before); Cell reversed[30]; Clue back={.count=clue->count}; for(int i=0;i<n;i++) reversed[n-1-i]=cells[i]; for(int i=0;i<clue->count;i++) back.values[clue->count-1-i]=clue->values[i]; fit_table(reversed,n,&back,p->after);
}
static bool can_start(const Placements *p,int block,int start) {
 int end=start+p->clue->values[block]; for(int i=start;i<end;i++) if(p->cells[i]==EMPTY) return false;
 bool left=start==0?block==0:p->cells[start-1]!=FILLED && p->before[start-1][block]; int rest=p->clue->count-block-1; bool right=end==p->length?rest==0:p->cells[end]!=FILLED && p->after[p->length-end-1][rest]; return left && right;
}
bool has_placement(const Cell *cells,int length,const Clue *clue) { bool table[31][51]; fit_table(cells,length,clue,table); return table[length][clue->count]; }
bool solve_line(const Cell *cells,int n,const Clue *clue,bool precise,Cell *solved) {
 Placements p; prepare(&p,cells,n,clue); if(!p.before[n][clue->count]) return false; memcpy(solved,cells,(size_t)n*sizeof(*cells)); bool fillable[30]={false},covered[30]={false};
 for(int block=0;block<clue->count;block++) { int length=clue->values[block],low=n,high=-1; for(int start=0;start+length<=n;start++) if(can_start(&p,block,start)) { low=minimum(low,start); high=start; if(precise) for(int i=start;i<start+length;i++) fillable[i]=true; }
  if(!precise) { for(int i=high;i<low+length;i++) if(solved[i]==UNKNOWN) solved[i]=FILLED; for(int i=low;i<high+length;i++) covered[i]=true; }
 }
 for(int i=0;i<n;i++) if(cells[i]==UNKNOWN) { if(precise) { bool emptiable=false; for(int k=0;k<=clue->count;k++) if(p.before[i][k] && p.after[n-i-1][clue->count-k]) { emptiable=true; break; } if(fillable[i] && !emptiable) solved[i]=FILLED; else if(emptiable && !fillable[i]) solved[i]=EMPTY; } else if(solved[i]==UNKNOWN && !covered[i]) solved[i]=EMPTY; }
 return true;
}
