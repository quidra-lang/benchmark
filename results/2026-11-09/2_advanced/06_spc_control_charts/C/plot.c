#include "spc.h"
#include <math.h>
#include <string.h>

static void new_band(char b[62]){memset(b,'.',61);b[61]='\0';}
static int clamp(int p){return p<0?0:p>60?60:p;}
static int rounded(double v){double r=floor(v+0.5);return r< -61?-61:r>61?61:(int)r;}
static void place(char b[62],int p,char c){b[clamp(p)]=c;}
static void framed(char b[62],int center){new_band(b);place(b,0,':');place(b,60,':');place(b,center,'|');}
void limits_band(char b[62],Limits l,double v,bool signalled){double span=l.ucl-l.lcl;framed(b,rounded(60*((l.cl-l.lcl)/span)));place(b,rounded(60*((v-l.lcl)/span)),signalled?'*':'o');}
void cusum_band(char b[62],double upper,double lower,double h,bool up,bool down){framed(b,30);if(lower>0){int e=rounded(30*(lower/h));if(e>30)e=30;place(b,30-e,down?'*':'-');}if(upper>0){int e=rounded(30*(upper/h));if(e>30)e=30;place(b,30+e,up?'*':'+');}}
void width_band(char b[62],double scale,double width,double value,double center,bool signalled){new_band(b);int e=rounded(30*(width/scale));if(e>30)e=30;place(b,30,'|');place(b,30-e,':');place(b,30+e,':');double d=(value-center)/scale;place(b,30+rounded(30*d),signalled?'*':'o');}
void standard_band(char b[62],double z,bool ok){framed(b,30);place(b,30+rounded(10*z),ok?'o':'*');}
