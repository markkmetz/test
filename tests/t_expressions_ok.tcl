# t_expressions_ok.tcl — Valid expressions: expect ZERO warnings

# Braced expr
proc add {a b} { return [expr {$a + $b}] }

# Braced if condition
proc classify {n} {
    if {$n > 0} {
        return positive
    } elseif {$n < 0} {
        return negative
    } else {
        return zero
    }
}

# Braced while condition
proc countDown {n} {
    while {$n > 0} { incr n -1 }
    return $n
}

# Properly braced for loop — all 4 parts braced
proc sumN {n} {
    set total 0
    for {set i 1} {$i <= $n} {incr i} {
        incr total $i
    }
    return $total
}

# Known math functions
proc geometry {r} {
    set area  [expr {3.14159 * $r * $r}]
    set circ  [expr {2 * 3.14159 * $r}]
    set diag  [expr {sqrt($r * $r + $r * $r)}]
    set hyp   [expr {hypot($r, $r)}]
    set ceiled [expr {ceil($area)}]
    return [list $area $circ $diag $hyp $ceiled]
}

# String equality in expr
proc strEq {a b} {
    return [expr {$a eq $b}]
}

# Ternary expression
proc max2 {a b} {
    return [expr {$a > $b ? $a : $b}]
}

# Logical operators
proc inRange {x lo hi} {
    return [expr {$x >= $lo && $x <= $hi}]
}
