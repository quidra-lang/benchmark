#include "finance.h"

bool leap_year(int year) { return year%4==0 && (year%100!=0 || year%400==0); }
int year_length(int year) { return leap_year(year) ? 366 : 365; }
int month_length(int year,int month) { static const int lengths[]={31,28,31,30,31,30,31,31,30,31,30,31}; return month==2 && leap_year(year) ? 29 : lengths[month-1]; }
Date date_parts(const char *text) { Date result; sscanf(text,"%d-%d-%d",&result.year,&result.month,&result.day); return result; }
bool valid_date(const char *text) { Date d=date_parts(text); return d.year>=2001 && d.year<=2099 && d.month>=1 && d.month<=12 && d.day>=1 && d.day<=month_length(d.year,d.month); }
int day_number(int year,int month,int day) { int number=day-1; for (int y=2000;y<year;y++) number+=year_length(y); for (int m=1;m<month;m++) number+=month_length(year,m); return number; }
int parse_date(const char *text) { Date d=date_parts(text); return day_number(d.year,d.month,d.day); }
Date civil_date(int number) { Date d={2000,1,0}; while (number>=year_length(d.year)) number-=year_length(d.year++); while (number>=month_length(d.year,d.month)) number-=month_length(d.year,d.month++); d.day=number+1; return d; }
char *date_text(int number) { Date d=civil_date(number); return format("%04d-%02d-%02d",d.year,d.month,d.day); }
bool business_day(const Calendar *calendar,int day) { if ((day+5)%7>=5) return false; for (int i=0;i<calendar->count;i++) if (calendar->days[i]==day) return false; return true; }
int move_business(const Calendar *calendar,int day,int count,int direction) { while (count) { day+=direction; if (business_day(calendar,day)) count--; } return day; }
int adjust_date(const Calendar *calendar,int day,const char *rule) { if (!strcmp(rule,"UNADJUSTED")) return day; int direction=!strcmp(rule,"PRECEDING") ? -1 : 1; int adjusted=day; while (!business_day(calendar,adjusted)) adjusted+=direction; if (!strcmp(rule,"MODIFIED_FOLLOWING") && civil_date(adjusted).month!=civil_date(day).month) return adjust_date(calendar,day,"PRECEDING"); return adjusted; }
