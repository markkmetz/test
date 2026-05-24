# checks/style.tcl — Style and best-practice checks
# Checks switch default, catch result, and other advisory items.

namespace eval ::tclcheck::checks::style {

    proc processCmd {lineNum words filename} {
        if {[llength $words] == 0} { return {} }
        set cmd [lindex $words 0]
        set issues {}

        switch -- $cmd {
            switch { lappend issues {*}[_checkSwitch $lineNum $words $filename] }
            catch  { lappend issues {*}[_checkCatch $lineNum $words $filename] }
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # switch: warn if no default clause
    # ------------------------------------------------------------------

    proc _checkSwitch {lineNum words filename} {
        set issues {}
        # switch ?options? string {pattern body ...}
        # or switch ?options? string pattern body pattern body ...
        if {[llength $words] < 3} { return {} }

        # Find the pattern/body list
        # Skip option flags (-exact, -glob, -regexp, -nocase, --)
        set i 1
        while {$i < [llength $words]} {
            set w [lindex $words $i]
            if {[string match "-*" $w]} {
                incr i
                if {$w eq "--"} break
                continue
            }
            break
        }
        # $i is now the string arg
        incr i

        if {$i >= [llength $words]} { return {} }

        # Collect the pattern/body pairs
        set patternWords {}
        set bodyWord [lindex $words $i]
        if {[::tclcheck::parser::isBraceWord $bodyWord]} {
            # Single braced argument: parse inner pairs
            set inner [::tclcheck::parser::stripBraces $bodyWord]
            # Simple tokenisation: split on whitespace respecting braces
            set patternWords [_splitSwitchBody $inner]
        } else {
            # Alternating pattern body on command line
            set patternWords [lrange $words $i end]
        }

        # Check for "default" pattern
        set hasDefault 0
        set j 0
        while {$j < [llength $patternWords]} {
            set pat [lindex $patternWords $j]
            if {$pat eq "default"} { set hasDefault 1; break }
            incr j 2
        }

        if {!$hasDefault} {
            lappend issues [list $filename $lineNum INFO style \
                "'switch' statement has no 'default' clause"]
        }
        return $issues
    }

    # Very lightweight split of a switch body string into tokens.
    # Handles brace-quoted bodies but not deeply nested structures.
    proc _splitSwitchBody {body} {
        set tokens {}
        set i 0
        set len [string length $body]
        while {$i < $len} {
            # Skip whitespace
            while {$i < $len && [string is space [string index $body $i]]} {
                incr i
            }
            if {$i >= $len} break
            set ch [string index $body $i]
            if {$ch eq "\{"} {
                set depth 1
                incr i
                set start $i
                while {$i < $len && $depth > 0} {
                    set c [string index $body $i]
                    if {$c eq "\{"} { incr depth }
                    if {$c eq "\}"} { incr depth -1 }
                    incr i
                }
                lappend tokens [string range $body $start [expr {$i-2}]]
            } else {
                set start $i
                while {$i < $len && ![string is space [string index $body $i]]} {
                    incr i
                }
                lappend tokens [string range $body $start [expr {$i-1}]]
            }
        }
        return $tokens
    }

    # ------------------------------------------------------------------
    # catch: info if result not captured
    # ------------------------------------------------------------------

    proc _checkCatch {lineNum words filename} {
        set issues {}
        # catch script ?resultVar ?optionsVar??
        if {[llength $words] == 2} {
            lappend issues [list $filename $lineNum INFO style \
                "'catch' used without capturing result variable; consider 'catch {script} result'"]
        }
        return $issues
    }
}
