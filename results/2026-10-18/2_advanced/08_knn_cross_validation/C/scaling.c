#include "knn.h"
#include <math.h>

Scaling compute_scaling(const Rows *rows,ScalingMethod method,int dimension){Scaling s={0};for(int j=0;j<dimension;j++){if(method==STANDARD){double total=0;for(int k=0;k<rows->count;k++)total+=rows->values[k]->values[j];double center=total/rows->count;s.centers[j]=center;if(rows->count>1){double squares=0;for(int k=0;k<rows->count;k++){double d=rows->values[k]->values[j]-center;squares+=d*d;}s.scales[j]=sqrt(squares/(rows->count-1));}}else{double low=rows->values[0]->values[j],high=low;for(int k=0;k<rows->count;k++){double v=rows->values[k]->values[j];low=fmin(low,v);high=fmax(high,v);}s.centers[j]=low;s.scales[j]=high-low;}}return s;}
void transform(Scaling s,const Row *row,Features features,double *vector){for(int j=0;j<features.count;j++){int i=features.values[j];vector[j]=s.scales[i]>0?(row->values[i]-s.centers[i])/s.scales[i]:0;}}
