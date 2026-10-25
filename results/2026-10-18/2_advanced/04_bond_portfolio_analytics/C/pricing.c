#include "finance.h"

double bisection(Function function,void *context,double low,double high,double target) { for (int i=0;i<80;i++) { double middle=(low+high)/2; if (function(middle,context)>target) low=middle; else high=middle; } return (low+high)/2; }
double dirty_price(const YieldPricer *p,double rate) { double first=1+p->fraction*rate/p->frequency,growth=1+rate/p->frequency,factor=1,total=0; for (int i=0;i<p->count;i++) { total+=(double)p->flows[i]/(first*factor); factor*=growth; } return total*100/(double)p->outstanding; }
static double yield_function(double rate,void *context) { return dirty_price(context,rate); }
double solve_yield(const YieldPricer *pricer,double target) { return bisection(yield_function,(void *)pricer,0,1,target); }
Risk yield_risk(const YieldPricer *p,double rate) {
    double first=1+p->fraction*rate/p->frequency,growth=1+rate/p->frequency,factor=1,total=0,weighted=0,curvature=0;
    for (int i=0;i<p->count;i++) { double value=(double)p->flows[i]/(first*factor),years=(i+p->fraction)/p->frequency; total+=value; weighted+=years*value; curvature+=years*(years+1.0/p->frequency)*value; factor*=growth; }
    double macaulay=weighted/total;
    return (Risk){macaulay,macaulay/growth,curvature/(total*growth*growth),(dirty_price(p,rate-0.0001)-dirty_price(p,rate+0.0001))/2};
}
