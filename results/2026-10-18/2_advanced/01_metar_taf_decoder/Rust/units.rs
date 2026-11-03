use crate::groups::Visibility;

#[derive(Clone)]
pub struct Calendar {
    pub year: i64,
    pub month: i64,
    pub days: i64,
    pub next_year: i64,
    pub next_month: i64,
    pub next_days: i64
}

pub fn days_in_month(year: i64, month: i64) -> i64 {
    if month == 2 {
        28+i64::from(year%4 == 0 && (year%100 != 0 || year%400 == 0))
    } else if matches!(month, 4|6|9|11) {
        30
    } else {
        31
    }
}

impl Calendar {
    pub fn new(year: i64, month: i64) -> Self {
        let next_year = year+i64::from(month == 12);
        let next_month = month%12+1;
        Self {
            year,
            month,
            days: days_in_month(year, month),
            next_year,
            next_month,
            next_days: days_in_month(next_year, next_month)
        }
    }
    pub fn forecast_time(&self, day: i64, hour: i64, minute: i64, issue_day: i64) -> Option<i64> {
        let next = day<issue_day;
        let days = if next {
            self.next_days
        } else {
            self.days
        };
        if !(1..=days).contains(&day) {
            None
        } else {
            Some((if next {
                self.days*1440
            } else {
                0
            })+((day-1)*24+hour)*60+minute)
        }
    }
    pub fn stamp(&self, mut time: i64) -> String {
        let (year, month) = if time >= self.days*1440 {
            time -= self.days*1440;
            (self.next_year, self.next_month)
        } else {
            (self.year, self.month)
        };
        format!("{year:04}-{month:02}-{:02}T{:02}:{:02}Z", time/1440+1, time%1440/60, time%60)
    }
}

pub fn sin(angle: i64) -> i64 {
    const TABLE: [i64; 10] = [0, 174, 342, 500, 643, 766, 866, 940, 985, 1000];
    let y = angle.rem_euclid(360);
    if y <= 90 {
        TABLE[(y/10)as usize]
    } else if y <= 180 {
        TABLE[((180-y)/10)as usize]
    } else if y <= 270 {
        -TABLE[((y-180)/10)as usize]
    } else {
        -TABLE[((360-y)/10)as usize]
    }
}

pub fn cos(angle: i64) -> i64 {
    sin(angle+90)
}

pub fn knots(v: i64) -> i64 {
    (v*1944+500)/1000
}

pub fn inhg(q: i64) -> i64 {
    (q*2953+500)/1000
}

pub fn hpa(a: i64) -> i64 {
    (a*33864+50000)/100000
}

pub fn mile_fraction(v: &Visibility) -> (i64, i64) {
    match v {
        Visibility::Meters {
            value,
            ..
        } => (1000*value, 1609344),
        Visibility::Miles {
            whole,
            numerator,
            denominator,
            ..
        } => {
            let q = denominator.unwrap_or(1);
            (whole*q+numerator, q)
        }
    }
}

pub fn meter_value(v: &Visibility) -> i64 {
    match v {
        Visibility::Meters {
            value,
            ..
        } => *value,
        _ => {
            let (p, q) = mile_fraction(v);
            1609344*p/(1000*q)
        }
    }
}

pub fn fraction(p: i64, q: i64) -> String {
    if q == 0 {
        return "undefined".into();
    }
    let (mut a, mut b) = (p.abs(), q);
    while b != 0 {
        (a, b) = (b, a%b);
    }
    format!("{}/{}", p/a, q/a)
}
