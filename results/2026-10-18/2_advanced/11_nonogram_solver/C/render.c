#include "nonogram.h"

char state_char(Cell state) { return "?#."[state]; }
Cell char_state(char character) { return character=='#'?FILLED:character=='.'?EMPTY:UNKNOWN; }
void state_string(const Cell *cells,int length,char *text) { for(int i=0;i<length;i++) text[i]=state_char(cells[i]); text[length]=0; }
void grid_display(FILE *file,const char *const *names,const Grid *const *grids,int count) {
 fputs("grid",file); for(int i=0;i<count;i++) fprintf(file," %s",names[i]); fputc('\n',file);
 for(int r=0;r<grids[0]->height;r++) { for(int i=0;i<count;i++) { if(i) fputs(" | ",file); for(int c=0;c<grids[i]->width;c++) fputc(state_char(grids[i]->cells[r][c]),file); } fputc('\n',file); }
}
void answer_sheet(FILE *file,const Model *model,const Grid *grid) {
 char tokens[30][50][4],row_texts[30][151]; int counts[30],width=0,depth=0,margin=0;
 for(int c=0;c<model->width;c++) { const Clue *clue=&model->columns[c]; counts[c]=maximum(1,clue->count); depth=maximum(depth,counts[c]); for(int i=0;i<counts[c];i++) { snprintf(tokens[c][i],4,"%d",clue->count?clue->values[i]:0); width=maximum(width,(int)strlen(tokens[c][i])+1); } }
 for(int r=0;r<model->height;r++) { strcpy(row_texts[r],clue_text(&model->rows[r]," ")); margin=maximum(margin,(int)strlen(row_texts[r])); }
 for(int t=0;t<depth;t++) { char line[256]; int at=0; for(int i=0;i<margin;i++) line[at++]=' '; for(int c=0;c<model->width;c++) { int skipped=depth-counts[c]; const char *token=t>=skipped?tokens[c][t-skipped]:""; for(int i=0;i<width-(int)strlen(token);i++) line[at++]=' '; for(const char *p=token;*p;p++) line[at++]=*p; } while(at>0 && line[at-1]==' ') at--; line[at]=0; fprintf(file,"%s\n",line); }
 for(int r=0;r<model->height;r++) { fprintf(file,"%*s",margin,row_texts[r]); for(int c=0;c<model->width;c++) fprintf(file,"%*c",width,state_char(grid->cells[r][c])); fputc('\n',file); }
}
