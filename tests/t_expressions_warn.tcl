# t_expressions_warn.tcl — Expression issues: expect specific WARN/ERROR

# Unbraced expr — double-substitution risk
set a 5
set b 3
set r [expr $a + $b]             ;##EXPECT: WARN:expressions

# Unbraced if condition
if $a {                          ;##EXPECT: WARN:expressions
    puts "nonzero"
}

# Unbraced while condition
set n 3
while $n {                       ;##EXPECT: WARN:expressions
    incr n -1
}

# Unbraced for condition
for {set i 0} $i {incr i} {}    ;##EXPECT: WARN:expressions

# Unbraced for init
for {set i 0} {$i < 5} {incr i} {}   ;# this is fine

# Division by zero
set bad [expr {10 / 0}]          ;##EXPECT: WARN:expressions

# Unknown math function
set v [expr {myFakeFunc($a)}]    ;##EXPECT: WARN:expressions

# Unmatched paren in expression
set p [expr {($a + $b}]          ;##EXPECT: ERROR:expressions
