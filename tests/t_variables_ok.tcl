# t_variables_ok.tcl — Valid variable patterns: expect ZERO warnings

# set before read
proc varOrder {} {
    set x 10
    set y 20
    return [expr {$x + $y}]
}

# global properly declared
set globalCounter 0

proc incrementGlobal {} {
    global globalCounter
    incr globalCounter
    return $globalCounter
}

# upvar usage
proc doubleInPlace {varName} {
    upvar 1 $varName v
    set v [expr {$v * 2}]
}

# lassign unpacking
proc swapPair {a b} {
    lassign [list $b $a] first second
    return "$first $second"
}

# foreach loop variable is defined
proc sumList {items} {
    set total 0
    foreach item $items {
        incr total $item
    }
    return $total
}

# Dynamic variable: set var$i $val — subsequent $var1 access should not warn
proc buildIndexed {vals} {
    set i 0
    foreach v $vals {
        set var$i $v   ;# partial dynamic — prefix "var"
        incr i
    }
    # Accessing $var0 should be suppressed (covered by prefix)
    return $var0
}

# Array with static key
proc colorMap {} {
    set palette(red)   255
    set palette(green) 128
    set palette(blue)  0
    return $palette(red)
}

# Array with dynamic key — no warning expected on any key
proc dynArrayRead {key} {
    set data(a) 1
    set data(b) 2
    set idx $key
    return $data($idx)
}

# Variable prefixed with _ is excluded from unused-variable INFO
proc withIgnored {} {
    set _unused "internal"
    set result "value"
    return $result
}
