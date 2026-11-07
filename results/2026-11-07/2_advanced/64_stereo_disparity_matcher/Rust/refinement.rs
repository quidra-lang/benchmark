pub fn decimal(a: i64, b: i64) -> String {
    let n = (200*a+b)/(2*b);
    format!("{}.{:02}", n/100, n%100)
}

pub fn subpixel(disparity: i64, costs: &[i64], minimum: i64, maximum: i64, focal: i64, baseline: i64) -> (String, String) {
    let index = (disparity-minimum) as usize;
    let (a, b) = if disparity > minimum && disparity < maximum && costs[index-1] > costs[index] && costs[index+1] >= costs[index] {
        (costs[index-1]-costs[index+1], 2*(costs[index-1]-2*costs[index]+costs[index+1]))
    } else { (0, 1) };
    let q = (200*(disparity*b+a)+b)/(2*b);
    (format!("{}.{:02}", q/100, q%100), decimal(100*focal*baseline, q))
}

pub fn depth(disparity: i64, focal: i64, baseline: i64) -> i64 { (200*focal*baseline+disparity)/(2*disparity) }
