#ifndef FINANCE_H
#define FINANCE_H
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char **data; int count,capacity; } Strings;
typedef struct { char *data; size_t length,capacity; } Text;
typedef struct { int year,month,day; } Date;
typedef struct { int days[1000]; int count; } Calendar;
typedef struct { int64_t numerator,denominator; } Fraction;
typedef struct { int *data; int count; } Schedule;
typedef struct { int day; double amount; } Flow;
typedef struct { Flow *data; int count,capacity; } Flows;
typedef struct { int64_t *flows; int count; double fraction; int frequency; int64_t outstanding; } YieldPricer;
typedef struct { double macaulay,modified,convexity,dv01; } Risk;
typedef struct { int maturity,frequency; int64_t coupon; } Pillar;
typedef struct { int days[30]; double rates[30]; int count; } Curve;
typedef double (*Function)(double,void *);

void *allocate(size_t size);
void *resize(void *pointer,size_t size);
char *copy_text(const char *text);
char *format(const char *pattern,...);
void append_text(Text *text,const char *part);
void add_string(Strings *strings,const char *text);
Strings split(const char *text,char separator);
char *join(Strings strings,const char *separator);
Strings read_lines(const char *name);
void add_flow(Flows *flows,int day,double amount);
bool leap_year(int year);
int year_length(int year);
int month_length(int year,int month);
Date date_parts(const char *text);
bool valid_date(const char *text);
int day_number(int year,int month,int day);
int parse_date(const char *text);
Date civil_date(int number);
char *date_text(int number);
bool business_day(const Calendar *calendar,int day);
int move_business(const Calendar *calendar,int day,int count,int direction);
int adjust_date(const Calendar *calendar,int day,const char *rule);
Fraction year_fraction(const char *kind,int start,int end);
Schedule coupon_schedule(int issue,int maturity,int frequency,bool eom,bool long_stub);
double bisection(Function function,void *context,double low,double high,double target);
double dirty_price(const YieldPricer *pricer,double rate);
double solve_yield(const YieldPricer *pricer,double target);
Risk yield_risk(const YieldPricer *pricer,double rate);
double zero_rate(const Curve *curve,int day);
double discount_factor(const Curve *curve,int day,double spread);
double present_value(const Curve *curve,Flows flows,double spread);
double forward_rate(const Curve *curve,int start,int end);
Curve shifted_curve(const Curve *curve,const double *deltas);
Curve bootstrap(int settlement,const Pillar *pillars,int count);
double z_spread(const Curve *curve,Flows flows,double target);
#endif
