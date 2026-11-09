#include "spc.h"
#include <stdlib.h>
#include <string.h>

const char *const chart_names[9]={"XBAR_R","R","XBAR_S","S","I","MR","CUSUM","EWMA","MA"};
const char *const family_names[3]={"XBAR_R","XBAR_S","I_MR"};
const char *const attribute_names[4]={"p","np","c","u"};
const Constants control_constants[9]={
 {1.880,2.659,0,3.267,0,3.267,1.128,0.7979},
 {1.023,1.954,0,2.568,0,2.574,1.693,0.8862},
 {0.729,1.628,0,2.266,0,2.282,2.059,0.9213},
 {0.577,1.427,0,2.089,0,2.114,2.326,0.9400},
 {0.483,1.287,0.030,1.970,0,2.004,2.534,0.9515},
 {0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594},
 {0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650},
 {0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693},
 {0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727}
};
static FILE *open_input(const char *name) {char path[128];snprintf(path,sizeof path,"input/%s",name);FILE *file=fopen(path,"r");if(!file)exit(1);return file;}
static char *read_line(FILE *file) {size_t size=128,length=0;char *line=malloc(size);if(!line)exit(1);int c;while((c=fgetc(file))!=EOF&&c!='\n'){if(length+1==size){size*=2;char *grown=realloc(line,size);if(!grown)exit(1);line=grown;}line[length++]=(char)c;}if(!length&&c==EOF){free(line);return NULL;}line[length]='\0';return line;}
Dataset read_dataset(void) {
 Dataset d={0};Settings *s=&d.settings;char *line;FILE *file=open_input("spec.txt");
 while((line=read_line(file))) {
  char *name=strtok(line," "),*value=strtok(NULL," ");
  if(!strcmp(name,"rules")) {int chart=6;for(int j=0;j<6;j++)if(!strcmp(value,chart_names[j]))chart=j;char *token;while((token=strtok(NULL," ")))s->rules[chart].values[s->rules[chart].count++]=atoi(token);free(line);continue;}
  if(!strcmp(name,"characteristic"))strcpy(s->name,value);
  else if(!strcmp(name,"lsl"))s->lsl=atoi(value);
  else if(!strcmp(name,"usl"))s->usl=atoi(value);
  else if(!strcmp(name,"target"))s->target=atoi(value);
  else if(!strcmp(name,"subgroup_size"))s->size=atoi(value);
  else if(!strcmp(name,"phase1_subgroups"))s->phase1=atoi(value);
  else if(!strcmp(name,"max_passes"))s->passes=atoi(value);
  else if(!strcmp(name,"cusum_k"))s->k=strtod(value,NULL);
  else if(!strcmp(name,"cusum_h"))s->h=strtod(value,NULL);
  else if(!strcmp(name,"ewma_lambda"))s->lambda=strtod(value,NULL);
  else if(!strcmp(name,"ewma_l"))s->e=strtod(value,NULL);
  else if(!strcmp(name,"ma_span"))s->span=atoi(value);
  else if(!strcmp(name,"event_gap"))s->gap=atoi(value);
  else if(!strcmp(name,"ci_z"))s->z=strtod(value,NULL);
  else if(!strcmp(name,"histogram_bin"))s->bin=atoi(value);
  else if(!strcmp(name,"rolling_window"))s->window=atoi(value);
  else if(!strcmp(name,"rolling_step"))s->step=atoi(value);
  free(line);
 }
 fclose(file);file=open_input("measurements.csv");free(read_line(file));int sample,group,v;
 while(fscanf(file,"%d,%d,%d",&sample,&group,&v)==3)d.values[d.count++]=v;
 fclose(file);file=open_input("attributes.csv");free(read_line(file));Lot l;
 while(fscanf(file,"%d,%d,%d,%d",&l.number,&l.inspected,&l.defectives,&l.defects)==4)d.lots[d.lot_count++]=l;
 fclose(file);return d;
}
