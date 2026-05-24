# t_syntax_errors.tcl — Deliberately broken syntax: expect specific ERRORs
# Each ##EXPECT annotation identifies what the checker should report on that line.

# Unbalanced opening brace
proc broken1 {x} {       ;##EXPECT: ERROR:syntax
    set result {unclosed

# Missing closing bracket
proc broken2 {} {
    set x [expr {1 + 2}
    return $x
}                          ;##EXPECT: ERROR:syntax

# Unclosed double-quote
proc broken3 {} {
    set msg "hello world
    return $msg
}                          ;##EXPECT: ERROR:syntax

# Extra closing brace
proc broken4 {} {
    set x 1
}}
