# t_variables_warn.tcl — Variable issues: expect specific WARN/INFO

# Undefined variable read before set
proc undefinedRead {} {
    puts $notDefined          ;##EXPECT: WARN:variables
    set notDefined "now set"
}

# Missing global declaration inside proc
set sharedState 0

proc missingGlobal {} {
    incr sharedState          ;##EXPECT: WARN:variables
}

# Unused variable (INFO)
proc unusedVar {} {
    set computed [expr {2 + 2}]   ;##EXPECT: INFO:variables
    return "done"
}

# Fully dynamic set — INFO emitted, all var checks suppressed
proc fullyDynamic {name val} {
    set $name $val            ;##EXPECT: INFO:dynamic-var
    puts $name
}

# Partial dynamic — INFO emitted, prefix-matched accesses suppressed
proc partialDynamic {letter} {
    set var$letter "data"     ;##EXPECT: INFO:dynamic-var
}

# unset on undefined variable
proc unsetUndefined {} {
    unset ghostVar             ;##EXPECT: WARN:variables
}
