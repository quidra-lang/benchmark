fn main() {
    let mut x = 42_i64;
    let mut free_time = [0; 2];
    let (mut arrival, mut total_wait, mut maximum) = (0_i32, 0_i32, 0_i32);
    for k in 1..=20 {
        x = x * 48271 % 2147483647;
        arrival += (x % 5) as i32 + 1;
        x = x * 48271 % 2147483647;
        let service = (x % 7) as i32 + 2;
        let teller = usize::from(free_time[1] < free_time[0]);
        let start = arrival.max(free_time[teller]);
        let end = start + service;
        let wait = start - arrival;
        free_time[teller] = end;
        total_wait += wait;
        maximum = maximum.max(wait);
        println!("customer {}: arrive={} start={} end={} teller={} wait={}", k, arrival, start, end, teller + 1,
            wait);
    }
    println!("average wait: {:.2}\nmax wait: {}\nlast departure: {}", f64::from(total_wait) / 20.0, maximum,
        free_time[0].max(free_time[1]));
}
