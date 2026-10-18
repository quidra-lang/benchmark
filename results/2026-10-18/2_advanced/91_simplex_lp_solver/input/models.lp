# Quidra LP benchmark models
# blank lines and lines starting with '#' are ignored

model furniture
# weekly production plan of a small workshop
maximize
profit: 45 table + 30 chair + 60 desk + 25 shelf
subject to
wood: 6 table + 2 chair + 8 desk + 3 shelf <= 180
labor: 3 table + 2 chair + 5 desk + 2 shelf <= 120
finish: 2 table + 1.5 chair + 3 desk + shelf <= 75
chairs: chair - 4 table >= 0
bounds
desk <= 12
shelf >= 2
end

model diet
minimize
cost: 0.6 oats + 1.25 milk + 2.4 eggs + 0.9 bread + 1.8 beans
subject to
energy: 11 oats + 16 milk + 18 eggs + 8 bread + 23 beans >= 200
protein: 4 oats + 8 milk + 13 eggs + 3 bread + 15 beans >= 55
calcium: 2 oats + 28 milk + 5 eggs + 2 bread + 8 beans >= 80
sodium: oats + 2 milk + 3 eggs + 4 bread + 5 beans <= 40

bounds
oats <= 4
milk <= 8
eggs <= 3
bread <= 5
end

model transport
# balanced transportation problem: one equality is redundant
minimize
freight: 7 a_north + 9 a_south + 5 a_west + 4 b_north + 3 b_south + 3 b_west + 2 c_north + 3 c_south + 2 c_west
subject to
supply_a: a_north + a_south + a_west = 30
supply_b: b_north + b_south + b_west = 25
supply_c: c_north + c_south + c_west = 45
demand_north: a_north + b_north + c_north = 40
demand_south: a_south + b_south + c_south = 35
demand_west: a_west + b_west + c_west = 25
end

model pipeline
# minimum cost flow from s to t; the transfer arc bc is free of charge
minimize
cost: 4 sa + 2 sb + 1 ab + 3 at + 5 bt + 1 ct + 6 st
subject to
node_s: sa + sb + st = 12
node_a: sa - ab - at = 0
node_b: sb + ab - bt - bc = 0
node_c: bc - ct = 0
node_t: at + bt + ct + st = 12
bounds
sb <= 6
at <= 7
ct <= 4
end

model beale
# Beale's example: the simplex method cycles without an anti-cycling rule
minimize
z: - 0.75 x4 + 20 x5 - 0.5 x6 + 6 x7
subject to
r1: 1/4 x4 - 8 x5 - x6 + 9 x7 <= 0
r2: 1/2 x4 - 12 x5 - 1/2 x6 + 3 x7 <= 0
r3: x6 <= 1
end

model blend
maximize
value: 3 p + 2 q - r + 4 w - 2 t
subject to
mix: p + q + r + w <= 20
ratio: p - 2 q + r >= -6
cap: 2 p + q - w + p <= 24
net: q - r + w = 4
lim: w - t <= 9
qlow: - q - w >= -12
bounds
-5 <= r <= 5
w free
q <= 6
q >= -inf
t = 1
p >= 1
end

model shortage
maximize
z: x + y
subject to
c1: x + y <= 4
c2: x + 2 y >= 10
c3: x - y <= 1
end

model runaway
maximize
z: x + y - 0.5 u
subject to
c1: x - y <= 2
c2: - 2 x + y <= 3
c3: x + y + u >= 1
end

model knapsack
maximize
value: 10 item1 + 17 item2 + 20 item3 + 18 item4 + 9 item5 + 13 item6 + 10 item7 + 10 item8 + 10 item9 + 18 item10
subject to
weight: 10 item1 + 15 item2 + 15 item3 + 11 item4 + 8 item5 + 8 item6 + 10 item7 + 4 item8 + 9 item9 + 12 item10 <= 51
binary
item1 item2 item3 item4 item5
item6 item7 item8 item9 item10
end

model staffing
# nurses work five consecutive days; d1 = number starting on Monday
minimize
staff: d1 + d2 + d3 + d4 + d5 + d6 + d7
subject to
mon: d1 + d4 + d5 + d6 + d7 >= 17
tue: d1 + d2 + d5 + d6 + d7 >= 13
wed: d1 + d2 + d3 + d6 + d7 >= 15
thu: d1 + d2 + d3 + d4 + d7 >= 19
fri: d1 + d2 + d3 + d4 + d5 >= 14
sat: d2 + d3 + d4 + d5 + d6 >= 16
sun: d3 + d4 + d5 + d6 + d7 >= 11
integer
d1 d2 d3 d4
d5 d6 d7
end

model facility
minimize
total: 30 open1 + 26 open2 + 34 open3 + 4 f11 + 6 f12 + 9 f13 + 7 f21 + 3 f22 + 5 f23 + 6 f31 + 8 f32 + 2 f33
subject to
d1: f11 + f21 + f31 >= 6
d2: f12 + f22 + f32 >= 5
d3: f13 + f23 + f33 >= 7
k1: f11 + f12 + f13 - 10 open1 <= 0
k2: f21 + f22 + f23 - 9 open2 <= 0
k3: f31 + f32 + f33 - 11 open3 <= 0
binary
open1 open2 open3
end

model parity
minimize
z: x + y
subject to
c1: 2 x + 4 y = 7
bounds
x <= 5
y <= 5
integer
x y
end

model typo
maximize
z: 3 x + 2 y
subject to
c1: x + y <= 4
c2: 3x + y <= 5
end

model ghost
minimize
z: x + y
subject to
c1: x + y >= 2
bounds
x <= 3
v >= 1
end

model narrow
maximize
z: n + m
subject to
c1: n + 2 m <= 7
bounds
1.2 <= n <= 1.8
integer
m n
end

model twin
maximize
z: a + b
subject to
c1: a + b <= 4
c2: a - b >= -2
c1: a <= 3
end

model clash
maximize
z: x + y
subject to
c1: x + y <= 10
bounds
x >= 4
0 <= y <= 3
x <= 2.5
end

model stray
minimize
z: a + b
subject to
c1: a + b >= 1
integer
a
binary
b c
end

model loose
maximize
z: x
subject to
c1: x <= 5
bounds
x >= inf
end

model stub
minimize
z: x + y
end
