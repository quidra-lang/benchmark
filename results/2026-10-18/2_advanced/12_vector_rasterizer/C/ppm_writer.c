#include "raster.h"

void write_ppm(const RGB *image,int width,int height) { FILE *file=fopen("output/image.ppm","w"); if(!file) abort(); fprintf(file,"P3\n%d %d\n255\n",width,height); for(int y=0;y<height;y++) { for(int x=0;x<width;x++) { RGB p=image[y*width+x]; fprintf(file,"%s%d %d %d",x?" ":"",p.v[0],p.v[1],p.v[2]); } fputc('\n',file); } fclose(file); }
void write_preview(const RGB *image,int width,int height) { FILE *file=fopen("output/preview.txt","w"); if(!file) abort(); const char *ramp="@%#*+=-:,."; for(int y=0;y<height;y+=4) { for(int x=0;x<width;x+=2) { int total=0; for(int j=0;j<4;j++) for(int i=0;i<2;i++) { RGB p=image[(y+j)*width+x+i]; total+=299*p.v[0]+587*p.v[1]+114*p.v[2]; } fputc(ramp[(total/8000)*10/256],file); } fputc('\n',file); } fclose(file); }
