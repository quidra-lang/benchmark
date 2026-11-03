package main

import (
    "fmt"
    "strconv"
)

func leapYear(year int) bool { return year%4 == 0 && (year%100 != 0 || year%400 == 0) }
func yearLength(year int) int { if leapYear(year) { return 366 }; return 365 }
func monthLength(year, month int) int {
    lengths := [...]int{31,28,31,30,31,30,31,31,30,31,30,31}
    if month == 2 && leapYear(year) { return 29 }
    return lengths[month-1]
}
func dateParts(text string) (int,int,int) {
    year,_ := strconv.Atoi(text[:4]); month,_ := strconv.Atoi(text[5:7]); day,_ := strconv.Atoi(text[8:10])
    return year,month,day
}
func validDate(text string) bool {
    year,month,day := dateParts(text)
    return year>=2001 && year<=2099 && month>=1 && month<=12 && day>=1 && day<=monthLength(year,month)
}
func dayNumber(year,month,day int) int {
    number := day-1
    for y:=2000; y<year; y++ { number += yearLength(y) }
    for m:=1; m<month; m++ { number += monthLength(year,m) }
    return number
}
func parseDate(text string) int { return dayNumber(dateParts(text)) }
func civilDate(number int) (int,int,int) {
    year,month := 2000,1
    for number>=yearLength(year) { number-=yearLength(year); year++ }
    for number>=monthLength(year,month) { number-=monthLength(year,month); month++ }
    return year,month,number+1
}
func formatDate(number int) string { year,month,day:=civilDate(number); return fmt.Sprintf("%04d-%02d-%02d",year,month,day) }
type Calendar map[int]bool
func (calendar Calendar) business(day int) bool { return (day+5)%7<5 && !calendar[day] }
func (calendar Calendar) move(day,count,direction int) int { for count>0 { day+=direction; if calendar.business(day) { count-- } }; return day }
func (calendar Calendar) adjust(day int,rule string) int {
    if rule=="UNADJUSTED" { return day }
    direction:=1; if rule=="PRECEDING" { direction=-1 }
    adjusted:=day; for !calendar.business(adjusted) { adjusted+=direction }
    if rule=="MODIFIED_FOLLOWING" { _,oldMonth,_:=civilDate(day); _,newMonth,_:=civilDate(adjusted); if oldMonth!=newMonth { return calendar.adjust(day,"PRECEDING") } }
    return adjusted
}
