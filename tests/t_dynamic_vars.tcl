# t_dynamic_vars.tcl — Dynamic variable edge cases
# Tests all three dynamic tiers and related patterns.

# ---------------------------------------------------------------
# Tier 1: Static name — full tracking, no suppression
# ---------------------------------------------------------------
proc staticVars {} {
    set x 10
    set y [expr {$x + 5}]
    return $y
}

# ---------------------------------------------------------------
# Tier 2: Partial dynamic — prefix suppresses warnings for $var*
# ---------------------------------------------------------------
proc partialDynamic1 {} {
    set i 0
    foreach v {a b c} {
        set var$i $v       ;# INFO: dynamic-var, prefix "var"
        incr i
    }
    # $var0 should NOT generate a WARN (covered by prefix "var")
    return $var0
}

proc partialDynamic2 {suffix} {
    set prefix_$suffix "data"  ;# INFO: dynamic-var, prefix "prefix_"
    # $prefix_foo should not warn
    return $prefix_foo
}

# ---------------------------------------------------------------
# Tier 3: Fully dynamic — all var checks suppressed in scope
# ---------------------------------------------------------------
proc fullyDynamic1 {varname value} {
    set $varname $value     ;# INFO: dynamic-var, fully dynamic
    # $varname itself is a known arg — no warning
    # any other $var read should be suppressed too
    return $varname
}

# ---------------------------------------------------------------
# upvar with static remote name
# ---------------------------------------------------------------
proc staticUpvar {} {
    set localData 42
    upvar 1 localData alias
    # $alias should be defined (upvar link)
    return $alias
}

# ---------------------------------------------------------------
# upvar with dynamic remote name
# ---------------------------------------------------------------
proc dynUpvar {remoteName} {
    upvar 1 $remoteName localAlias
    # $localAlias should be treated as defined (upvar-linked)
    return $localAlias
}

# ---------------------------------------------------------------
# Array with static key
# ---------------------------------------------------------------
proc staticArrayKey {} {
    set data(foo) 100
    set data(bar) 200
    # Both keys defined — reads should not warn
    return [expr {$data(foo) + $data(bar)}]
}

# ---------------------------------------------------------------
# Array with dynamic key — suppress all data(*) warnings
# ---------------------------------------------------------------
proc dynArrayKey {key} {
    set table(x) 1
    set table($key) 99     ;# dynamic key → suppress all table(*) warnings
    # table(y) was never statically set but should not warn
    return $table(y)
}

# ---------------------------------------------------------------
# set $varname (fully dynamic) followed by normal reads — no false positives
# ---------------------------------------------------------------
proc dynThenNormal {varname} {
    set $varname 1          ;# fully dynamic → suppress in scope
    set known 42
    return $known
}
