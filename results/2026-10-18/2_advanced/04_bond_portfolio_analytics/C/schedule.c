#include "finance.h"

Schedule coupon_schedule(int issue,int maturity,int frequency,bool eom,bool long_stub) {
    int descending[1200],count=0,boundary=maturity; Date end=civil_date(maturity); bool end_rule=eom && end.day==month_length(end.year,end.month);
    while (boundary>issue) { descending[count++]=boundary; int index=end.year*12+end.month-1-(12/frequency)*count; int year=index/12,month=index%12+1,length=month_length(year,month); int day=end_rule || end.day>length ? length : end.day; boundary=day_number(year,month,day); }
    if (long_stub && boundary!=issue && count>=2) count--;
    Schedule result={allocate((size_t)(count+1)*sizeof(int)),count+1}; result.data[0]=issue; for (int i=0;i<count;i++) result.data[i+1]=descending[count-1-i]; return result;
}
