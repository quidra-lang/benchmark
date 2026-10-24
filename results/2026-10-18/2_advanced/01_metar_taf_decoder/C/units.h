#pragma once

static I floor_div(I n, I d) {
    I q = n/d, r = n%d;
    return q-(r<0);
}

static int isin(int x) {
    static const int table[] = {
        0, 174, 342, 500, 643, 766, 866, 940, 985, 1000
    };
    int y = (x%360+360)%360;
    if (y <= 90) return table[y/10];
    if (y <= 180) return table[(180-y)/10];
    if (y <= 270) return -table[(y-180)/10];
    return -table[(360-y)/10];
}

static int icos(int x) {
    return isin(x+90);
}

static int knots(int v) {
    return (v*1944+500)/1000;
}

static int inhg(int q) {
    return (q*2953+500)/1000;
}

static int hpa(int a) {
    return (a*33864+50000)/100000;
}

static int month_days(int y, int m) {
    if (m == 2) return 28+(y%4 == 0 && (y%100 != 0 || y%400 == 0));
    return m == 4 || m == 6 || m == 9 || m == 11?30:31;
}

static void calendar_init(void) {
    cfg.days = month_days(cfg.year, cfg.month);
    cfg.next_year = cfg.year+(cfg.month == 12);
    cfg.next_month = cfg.month%12+1;
    cfg.next_days = month_days(cfg.next_year, cfg.next_month);
}

static int forecast_time(int day, int hour, int minute, int issue_day) {
    if (day<1 || day>(day >= issue_day?cfg.days:cfg.next_days)) return -1;
    return (day<issue_day?cfg.days*1440:0)+((day-1)*24+hour)*60+minute;
}

static char *stamp(int m) {
    int y = cfg.year, mo = cfg.month;
    if (m >= cfg.days*1440) {
        m -= cfg.days*1440;
        y = cfg.next_year;
        mo = cfg.next_month;
    }
    return format("%04d-%02d-%02dT%02d:%02dZ", y, mo, m/1440+1, m%1440/60, m%60);
}

static void mile_fraction(Value *v, I *p, I *q) {
    if (v->visibility_kind != 2) {
        *p = 1000*(I)v->meters;
        *q = 1609344;
    } else {
        *q = v->denominator?v->denominator:1;
        *p = v->whole*(*q)+v->numerator;
    }
}

static I meter_value(Value *v) {
    if (v->visibility_kind != 2) return v->meters;
    I p, q;
    mile_fraction(v, &p, &q);
    return 1609344*p/(1000*q);
}

static char *fraction(I p, I q) {
    if (!q) return "undefined";
    I a = p<0?-p:p, b = q;
    while (b) {
        I r = a%b;
        a = b;
        b = r;
    }
    return format("%lld/%lld", (long long)(p/a), (long long)(q/a));
}
