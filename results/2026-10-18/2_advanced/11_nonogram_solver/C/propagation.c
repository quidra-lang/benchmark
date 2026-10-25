#include "nonogram.h"

const char *line_label(bool row,int index) { static char buffers[16][8]; static unsigned slot; char *text=buffers[slot++%16]; snprintf(text,8,"%c%d",row?'R':'C',index+1); return text; }
int line_cells(const Grid *grid,bool row,int index,Cell *cells) { int length=row?grid->width:grid->height; for(int i=0;i<length;i++) cells[i]=row?grid->cells[index][i]:grid->cells[i][index]; return length; }
int determined(const Grid *grid) { int n=0; for(int r=0;r<grid->height;r++) for(int c=0;c<grid->width;c++) n+=grid->cells[r][c]!=UNKNOWN; return n; }
Propagation propagate(const Model *model,Grid *grid,bool precise,bool *row_marks,bool *column_marks) {
 Propagation result={.conflict=-1};
 for(;;) { bool row=true; int index=-1; for(int r=0;r<model->height;r++) if(row_marks[r]) { index=r; break; } if(index<0) { row=false; for(int c=0;c<model->width;c++) if(column_marks[c]) { index=c; break; } } if(index<0) return result;
  const Clue *clue; if(row) { row_marks[index]=false; clue=&model->rows[index]; } else { column_marks[index]=false; clue=&model->columns[index]; } Cell cells[30],solved[30]; int length=line_cells(grid,row,index,cells); Step step={.row=row,.index=index}; bool consistent=solve_line(cells,length,clue,precise,solved);
  if(!consistent) step.contradiction=true; else for(int i=0;i<length;i++) if(cells[i]==UNKNOWN && solved[i]!=UNKNOWN) { step.gain++; if(row) { grid->cells[index][i]=solved[i]; column_marks[i]=true; } else { grid->cells[i][index]=solved[i]; row_marks[i]=true; } }
  if(result.count==result.capacity) { result.capacity=result.capacity?result.capacity*2:16; result.steps=resize(result.steps,result.capacity*sizeof(*result.steps)); } result.steps[result.count++]=step;
  if(!consistent) { result.conflict=(int)result.count-1; return result; }
 }
}
