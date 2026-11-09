fn main() {
    let mut a = [52, 17, 38, 9, 61, 38, 24, 45];
    let mut total = 0;
    for i in 1..8 {
        let v = a[i];
        let (mut j, mut shifts) = (i, 0);
        while j > 0 && a[j - 1] > v {
            a[j] = a[j - 1];
            j -= 1;
            shifts += 1;
        }
        a[j] = v;
        total += shifts;
        print!("i={} shifts={}:", i, shifts);
        for n in a {
            print!(" {}", n);
        }
        println!();
    }
    println!("total shifts: {}", total);
}
