#include "nonogram.h"

void guess_cell(const Grid *grid,int *row,int *column) {
 int rows[30]={0},columns[30]={0}; for(int r=0;r<grid->height;r++) for(int c=0;c<grid->width;c++) if(grid->cells[r][c]==UNKNOWN) { rows[r]++; columns[c]++; }
 *row=-1; *column=-1; int best=0;
 for(int r=0;r<grid->height;r++) for(int c=0;c<grid->width;c++) if(grid->cells[r][c]==UNKNOWN && (*row<0 || rows[r]+columns[c]<best)) { *row=r; *column=c; best=rows[r]+columns[c]; }
}
bool search_run(const Model *model,Search *search,const Grid *grid,int depth) {
 int row,column; guess_cell(grid,&row,&column);
 for(Cell value=FILLED;value<=EMPTY;value++) { Grid child=*grid; child.cells[row][column]=value; bool rows[30]={false},columns[30]={false}; rows[row]=true; columns[column]=true; Propagation p=propagate(model,&child,true,rows,columns); Guess guess={.number=search->guess_count+1,.depth=depth,.row=row,.column=column,.value=value,.solves=(int)p.count,.known=determined(&child),.result=GUESS_OPEN};
  if(p.conflict>=0) { Step step=p.steps[p.conflict]; guess.result=GUESS_CONTRADICTION; guess.conflict_row=step.row; guess.conflict_index=step.index; search->backtracks++; }
  else if(guess.known==model->width*model->height) { search->solutions[search->solution_count++]=child; guess.result=search->solution_count==1?GUESS_SOLUTION1:GUESS_SOLUTION2; }
  search->guesses[search->guess_count++]=guess; search->max_depth=maximum(search->max_depth,depth); search->line_solves+=(int)p.count; free(p.steps);
  if(guess.result==GUESS_OPEN) { if(search_run(model,search,&child,depth+1)) return true; } else if(search->solution_count==2) return true;
 }
 return false;
}
