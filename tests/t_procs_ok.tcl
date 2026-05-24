# t_procs_ok.tcl — Valid proc patterns: expect ZERO errors/warnings

# Basic proc with correct calls
proc add {a b} { return [expr {$a + $b}] }
proc sub {a b} { return [expr {$a - $b}] }

set r1 [add 3 4]
set r2 [sub 10 2]

# Proc with optional arg — called with and without it
proc greet {name {prefix "Hi"}} {
    return "$prefix, $name"
}
set g1 [greet "Alice"]
set g2 [greet "Bob" "Hello"]

# Variadic proc — called with 0 or more extras
proc logMsg {level args} {
    return "$level: [join $args { }]"
}
set m1 [logMsg INFO]
set m2 [logMsg WARN "something" "happened"]

# Forward reference: call before definition
proc caller {} {
    return [callee 5]
}
proc callee {x} {
    return [expr {$x * 2}]
}

# Namespace proc called correctly
namespace eval ::math {
    proc square {x} { return [expr {$x * $x}] }
}
set s [::math::square 9]

# string subcommand with correct arg count
set upper [string toupper "hello"]
set len   [string length "world"]

# list operations
set lst [list 1 2 3 4]
set elm [lindex $lst 0]
set rng [lrange $lst 1 2]
