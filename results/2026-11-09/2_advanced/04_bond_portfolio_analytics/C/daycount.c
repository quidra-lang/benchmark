#include "finance.h"

Fraction year_fraction(const char *kind,int start,int end) {
    if (!strcmp(kind,"ACT/360")) return (Fraction){end-start,360};
    if (!strcmp(kind,"ACT/365F")) return (Fraction){end-start,365};
    Date a=civil_date(start),b=civil_date(end);
    if (!strcmp(kind,"ACT/ACT")) { int leap=0,other=0; while (start<end) { int boundary=day_number(a.year+1,1,1); if (boundary>end) boundary=end; if (leap_year(a.year)) leap+=boundary-start; else other+=boundary-start; start=boundary; a.year++; } return (Fraction){365*leap+366*other,133590}; }
    if (!strcmp(kind,"30/360")) {
        bool february=a.month==2 && a.day==month_length(a.year,a.month);
        if (february && b.month==2 && b.day==month_length(b.year,b.month)) b.day=30;
        if (february) a.day=30;
        if (b.day==31 && a.day>=30) b.day=30;
        if (a.day==31) a.day=30;
    } else { if (a.day==31) a.day=30; if (b.day==31) b.day=30; }
    return (Fraction){360*(b.year-a.year)+30*(b.month-a.month)+b.day-a.day,360};
}
