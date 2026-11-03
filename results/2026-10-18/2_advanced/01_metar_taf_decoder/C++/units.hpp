#pragma once

static I floor_div(I n, I d) {
    I q = n/d;
    return q-(n%d<0);
}

static int isin(int angle) {
    static constexpr std::array<int, 10> table = {
        0, 174, 342, 500, 643, 766, 866, 940, 985, 1000
    };
    int y = (angle%360+360)%360;
    if (y <= 90) return table[y/10];
    if (y <= 180) return table[(180-y)/10];
    if (y <= 270) return -table[(y-180)/10];
    return -table[(360-y)/10];
}

static int icos(int angle) {
    return isin(angle+90);
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

static int month_days(int year, int month) {
    if (month == 2) return 28+(year%4 == 0 && (year%100 != 0 || year%400 == 0));
    return month == 4 || month == 6 || month == 9 || month == 11?30:31;
}

static void calendar_init() {
    cfg.days = month_days(cfg.year, cfg.month);
    cfg.next_year = cfg.year+(cfg.month == 12);
    cfg.next_month = cfg.month%12+1;
    cfg.next_days = month_days(cfg.next_year, cfg.next_month);
}

static std::optional<int> forecast_time(int day, int hour, int minute, int issue_day) {
    if (day<1 || day>(day >= issue_day?cfg.days:cfg.next_days)) return std::nullopt;
    return (day<issue_day?cfg.days*1440:0)+((day-1)*24+hour)*60+minute;
}

static string stamp(int time) {
    int year = cfg.year, month = cfg.month;
    if (time >= cfg.days*1440) {
        time -= cfg.days*1440;
        year = cfg.next_year;
        month = cfg.next_month;
    }
    return pad(year, 4)+"-"+pad(month, 2)+"-"+pad(time/1440+1, 2)+"T"+pad(time%1440/60, 2)+":"+pad(time%60, 2)+"Z";
}

static std::pair<I, I> mile_fraction(const Value& v) {
    if (v.visibility_kind != 2) return {
        1000*(I)v.meters, 1609344
    };
    I q = v.denominator?v.denominator:1;
    return {
        v.whole*q+v.numerator, q
    };
}

static I meter_value(const Value& v) {
    if (v.visibility_kind != 2) return v.meters;
    auto f = mile_fraction(v);
    return 1609344*f.first/(1000*f.second);
}

static string fraction(I p, I q) {
    if (!q) return "undefined";
    I g = std::gcd(p, q);
    return std::to_string(p/g)+"/"+std::to_string(q/g);
}
