import Foundation
typealias Interval = (Int, Int, Character)
func chartScale(_ makespan: Int, _ width: Int) -> (Int, Int) {
    var magnitude = 1;
    while true {
        for step in [1, 2, 5] {
            let q = step*magnitude, n = (makespan+q-1)/q;
            if n <= width {
                return(q, n)
            }
        };
        magnitude *= 10
    }
}
func timeRow(_ q: Int, _ n: Int) -> String {
    var s = "time";
    for c in stride(from: 0, to: n, by: 10) {
        if s.count<6+c {
            s += String(repeating: " ", count: 6+c-s.count)
        };
        s += String(c*q)
    };
    return s
}
func ruleRow(_ n: Int) -> String {
    "      "+String((0..<n).map {
        $0%10 == 0 ? Character("+") : Character("-")
    })
}
func frame(_ label: String, _ marks: String) -> String {
    label+String(repeating: " ", count: max(0, 4-label.count))+" |"+marks+"|"
}
func chartRow(_ label: String, _ intervals: [Interval], _ q: Int, _ n: Int) -> String {
    let sorted = intervals.sorted {
        $0.0<$1.0
    };
    return frame(label, String((0..<n).map {
        c in var best = 0, mark: Character = "."; for(s, e, m)in sorted {
            let overlap = min(e, (c+1)*q)-max(s, c*q); if overlap>best {
                best = overlap; mark = m
            }
        }; return mark
    }))
}
func busyRow(_ rows: [[Interval]], _ q: Int, _ n: Int) -> String {
    frame("busy", String((0..<n).map {
        c in let busy = rows.filter {
            $0.contains {
                $0.0 <= c*q && c*q<$0.1
            }
        }.count; return busy == 10 ? Character("X") : Character(String(busy))
    }))
}
