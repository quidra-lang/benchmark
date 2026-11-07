#include "mrp.h"

char *money(int64_t cents) { return format("%" PRId64 ".%02" PRId64,cents/100,cents%100); }
int64_t percentage(int64_t part,int64_t whole) { return (200*part+whole)/(2*whole); }
char *table_row(const char *label,const int64_t *values,int count,int width) { Text row={0}; append_text(&row,format("%-10s",label)); for (int i=0;i<count;i++) append_text(&row,format("%*" PRId64,width,values[i])); return row.data; }
void write_report(const char *name,Strings lines) { FILE *file=fopen(format("output/%s",name),"w"); if (!file) exit(EXIT_FAILURE); for (int i=0;i<lines.count;i++) if (fprintf(file,"%s\n",lines.data[i])<0) exit(EXIT_FAILURE); if (fclose(file)) exit(EXIT_FAILURE); }
