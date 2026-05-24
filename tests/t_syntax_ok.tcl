# t_syntax_ok.tcl — Well-formed TCL: expect ZERO errors/warnings

# Properly braced proc with defaults and args
proc greet {name {greeting "Hello"} args} {
    set msg "$greeting, $name!"
    foreach extra $args {
        append msg " $extra"
    }
    return $msg
}

# Nested namespace and proc
namespace eval ::utils {
    proc add {a b} {
        return [expr {$a + $b}]
    }
    proc multiply {a b} {
        return [expr {$a * $b}]
    }
}

# Multi-line string in braces (no substitution)
set template {
    line one
    line two
    line three
}

# Braced if/elseif/else chain
proc classify {n} {
    if {$n < 0} {
        return negative
    } elseif {$n == 0} {
        return zero
    } else {
        return positive
    }
}

# Properly braced while loop
proc countdown {n} {
    while {$n > 0} {
        incr n -1
    }
    return $n
}

# Properly braced for loop
proc sumRange {start end_} {
    set total 0
    for {set i $start} {$i <= $end_} {incr i} {
        incr total $i
    }
    return $total
}

# lassign unpacking
proc splitName {fullname} {
    lassign [split $fullname " "] first last
    return "$last, $first"
}

# foreach with multi-var binding
proc pairSums {pairs} {
    set result {}
    foreach {a b} $pairs {
        lappend result [expr {$a + $b}]
    }
    return $result
}

# catch with result variable
proc safeDiv {a b} {
    if {[catch {expr {$a / $b}} result]} {
        return 0
    }
    return $result
}

# Package provide at top of a module-like file is valid
# (not tested here to avoid side effects in checker output)

# Array usage
proc arrayDemo {} {
    set colors(red)   "#FF0000"
    set colors(green) "#00FF00"
    set colors(blue)  "#0000FF"
    return $colors(red)
}

# switch with default
proc dayType {day} {
    switch -- $day {
        Monday - Tuesday - Wednesday - Thursday - Friday {
            return weekday
        }
        Saturday - Sunday {
            return weekend
        }
        default {
            return unknown
        }
    }
}

# try/finally (Tcl 8.6)
proc withFile {path body} {
    set fh [open $path r]
    try {
        uplevel 1 $body
    } finally {
        close $fh
    }
}

# Backslash line continuation in a string
set longString "This is a very long string that \
continues on the next line"

# Math expressions with known functions
proc circleArea {r} {
    return [expr {3.14159265 * $r * $r}]
}

proc hypotenuse {a b} {
    return [expr {sqrt($a*$a + $b*$b)}]
}
