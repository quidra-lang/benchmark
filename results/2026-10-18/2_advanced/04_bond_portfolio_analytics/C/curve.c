#include "finance.h"

double zero_rate(const Curve *curve,int day) { if (day<=curve->days[0]) return curve->rates[0]; int last=curve->count-1; if (day>=curve->days[last]) return curve->rates[last]; int i=1; while (curve->days[i]<day) i++; if (curve->days[i]==day) return curve->rates[i]; return curve->rates[i-1]+(curve->rates[i]-curve->rates[i-1])*((double)(day-curve->days[i-1])/(curve->days[i]-curve->days[i-1])); }
double discount_factor(const Curve *curve,int day,double spread) { double rate=zero_rate(curve,day)+spread,growth=1; for (int i=0;i<day/365;i++) growth*=1+rate; return 1/(growth*(1+rate*(day%365)/365)); }
double present_value(const Curve *curve,Flows flows,double spread) { double total=0; for (int i=0;i<flows.count;i++) total+=flows.data[i].amount*discount_factor(curve,flows.data[i].day,spread); return total; }
double forward_rate(const Curve *curve,int start,int end) { return (discount_factor(curve,start,0)/discount_factor(curve,end,0)-1)*365/(end-start); }
Curve shifted_curve(const Curve *curve,const double *deltas) { Curve result=*curve; for (int i=0;i<curve->count;i++) result.rates[i]+=deltas[i]; return result; }
typedef struct { Curve *curve; Flows flows; int index; } BootstrapContext;
static double bootstrap_value(double rate,void *context) { BootstrapContext *data=context; data->curve->rates[data->index]=rate; return present_value(data->curve,data->flows,0); }
Curve bootstrap(int settlement,const Pillar *pillars,int count) {
    Curve curve={0};
    for (int i=0;i<count;i++) {
        Schedule schedule=coupon_schedule(settlement,pillars[i].maturity,pillars[i].frequency,false,false); Flows flows={0};
        for (int j=1;j<schedule.count;j++) { Fraction fraction=year_fraction("30/360",schedule.data[j-1],schedule.data[j]); double amount=(double)pillars[i].coupon*(double)fraction.numerator/(10000*(double)fraction.denominator); if (j==schedule.count-1) amount+=1; add_flow(&flows,schedule.data[j]-settlement,amount); }
        curve.days[i]=pillars[i].maturity-settlement; curve.count=i+1; BootstrapContext context={&curve,flows,i}; curve.rates[i]=bisection(bootstrap_value,&context,0,1,1);
    }
    return curve;
}
typedef struct { const Curve *curve; Flows flows; } SpreadContext;
static double spread_value(double spread,void *context) { SpreadContext *data=context; return present_value(data->curve,data->flows,spread); }
double z_spread(const Curve *curve,Flows flows,double target) { SpreadContext context={curve,flows}; return bisection(spread_value,&context,-0.5,0.5,target); }
