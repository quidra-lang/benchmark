#include "spc.h"
#include <math.h>

Center attribute_center(int chart,const Numbers *chosen,const Dataset *d) {
 int64_t defects=0,defectives=0,inspected=0;
 for(int j=0;j<chosen->count;j++){Lot l=d->lots[chosen->values[j]-1];defectives+=l.defectives;defects+=l.defects;inspected+=l.inspected;}
 double fraction=(double)defectives/inspected,value=fraction;
 if(chart==1)value=(double)defectives/chosen->count;else if(chart==2)value=(double)defects/chosen->count;else if(chart==3)value=(double)defects/inspected;
 return (Center){value,fraction};
}
LotPoint attribute_point(int chart,Lot l,Center c) {
 double v,sigma;
 if(chart==0){v=(double)l.defectives/l.inspected;sigma=sqrt(c.value*(1-c.value)/l.inspected);}
 else if(chart==1){v=l.defectives;sigma=sqrt(c.value*(1-c.fraction));}
 else if(chart==2){v=l.defects;sigma=sqrt(c.value);}
 else {v=(double)l.defects/l.inspected;sigma=sqrt(c.value/l.inspected);}
 LotPoint p={v,fmax(0,c.value-3*sigma),c.value+3*sigma,(v-c.value)/sigma,0};if(v>p.ucl)p.status=1;else if(v<p.lcl)p.status=-1;return p;
}
