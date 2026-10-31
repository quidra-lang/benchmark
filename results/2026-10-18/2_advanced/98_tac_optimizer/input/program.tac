# Three-address code emitted by a naive front end.
# Global arrays are zero-filled at the start of every run.
array data 32
array hist 8
array mat 36
array prod 36

# reads n and n values, then runs every kernel
func main
    read n
    debug = n * 0
    i = 0
L1:
    if i >= n goto L2
    read v
    data[i] = v
    t1 = i + 1
    i = t1
    goto L1
L2:
    if debug != 0 goto L9
    lo = 0
    hi = n
    param lo
    param hi
    s = call sum_range 2
    print s
    param n
    cnt = call histogram 1
    param n
    call bubble 1
    t2 = n - 1
    first = data[0]
    last = data[t2]
    print first
    print last
    param first
    param last
    b = call blend 2
    print b
    param n
    call normalize 1
    t3 = data[t2]
    print t3
    t4 = n % 3
    m = t4 + 3
    param m
    tr = call matmul 1
    print tr
    t5 = n % 4
    param t5
    param 5
    call series 2
    param last
    param first
    g = call gcd 2
    print g
    return
L9:
    param n
    call dump 1
    return
end

# weighted sum of data[lo..hi-1]
func sum_range lo hi
    s = 0
    i = lo + 0
    k = 2
    goto L2
L1:
    t1 = data[i]
    w = k * 3
    t2 = t1 * w
    span = hi - lo
    t3 = t2 + span
    s = s + t3
    i = i + 1
L2:
    if i < hi goto L1
    return s
end

# counts data values by residue mod 8 and prints the non-empty buckets
func histogram n
    j = 0
L1:
    if j >= 8 goto L2
    hist[j] = 0
    j = j + 1
    goto L1
L2:
    i = 0
L3:
    if i >= n goto L4
    t1 = data[i]
    t2 = t1 % 8
    t3 = hist[t2]
    t4 = t1 % 8
    t5 = t3 + 1
    hist[t4] = t5
    i = i + 1
    goto L3
L4:
    j = 0
    used = 0
L5:
    if j >= 8 goto L6
    c = hist[j]
    if c == 0 goto L7
    print j
    print c
    used = used + 1
L7:
    j = j + 1
    goto L5
L6:
    return used
end

# sorts data[0..n-1] in ascending order
func bubble n
    i = 0
    lim = n - 1
L1:
    if i >= lim goto L5
    j = 0
L2:
    t1 = lim - i
    if j >= t1 goto L4
    t2 = data[j]
    t3 = j + 1
    t4 = data[t3]
    if t2 <= t4 goto L3
    t5 = data[j]
    t6 = j + 1
    t7 = data[t6]
    data[j] = t7
    data[t6] = t5
L3:
    j = j + 1
    goto L2
L4:
    i = i + 1
    goto L1
L5:
    return
end

# |a - b| + a * b
func blend a b
    if a < b goto L1
    d = a - b
    p = a * b
    goto L2
L1:
    d = b - a
    q = a * b
L2:
    r = a * b
    t = r + d
    return t
end

# data[i] = (data[i] + hist[0]) / 2
func normalize n
    mode = 1
    i = 0
    if n > 0 goto L1
    return
L1:
    c0 = hist[0]
    base = c0 * 1
    v = data[i]
    if mode == 1 goto L2
    v = v * 2
L2:
    t1 = v + base
    t2 = t1 / 2
    data[i] = t2
    i = i + 1
    if i < n goto L1
    return
end

# trace of M * M for the m x m matrix M[i][j] = i + j
func matmul m
    i = 0
L1:
    if i >= m goto L4
    j = 0
L2:
    if j >= m goto L3
    t1 = i * m
    t2 = t1 + j
    t3 = i + j
    mat[t2] = t3
    j = j + 1
    goto L2
L3:
    i = i + 1
    goto L1
L4:
    i = 0
L5:
    if i >= m goto L10
    j = 0
L6:
    if j >= m goto L9
    sum = 0
    q = 0
L7:
    if q >= m goto L8
    t4 = i * m
    t5 = t4 + q
    a = mat[t5]
    t6 = q * m
    t7 = t6 + j
    b = mat[t7]
    t8 = a * b
    sum = sum + t8
    q = q + 1
    goto L7
L8:
    t9 = i * m
    t10 = t9 + j
    prod[t10] = sum
    j = j + 1
    goto L6
L9:
    i = i + 1
    goto L5
L10:
    tr = 0
    i = 0
L11:
    if i >= m goto L12
    t11 = i * m
    t12 = t11 + i
    x = prod[t12]
    tr = tr + x
    i = i + 1
    goto L11
L12:
    return tr
end

# prints n * 2 * step + 100 / step for n, n-1, ..., 1
func series n step
L1:
    if n <= 0 goto L2
    inc = step * 2
    q = 100 / step
    t = n * inc
    t = t + q
    print t
    n = n - 1
    goto L1
L2:
    return
end

# greatest common divisor (recursive)
func gcd a b
    a = a + 0
    if b == 0 goto L1
    r = a % b
    param b
    param r
    t = call gcd 2
    return t
    print 0
L1:
    return a
end

# debugging aid: prints data[0..n-1]
func dump n
    i = 0
L1:
    if i >= n goto L2
    t = data[i]
    print t
    i = i + 1
    goto L1
L2:
    return
end
