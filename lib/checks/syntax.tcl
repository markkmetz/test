# checks/syntax.tcl — Brace/bracket/quote balance and structural checks
# These checks are run directly on the raw source text before parsing.

namespace eval ::tclcheck::checks::syntax {

    # Run all syntax checks on source text.
    # Returns list of issue tuples.
    proc check {src filename} {
        set issues {}
        lappend issues {*}[checkBalance $src $filename]
        lappend issues {*}[checkLongLines $src $filename]
        return $issues
    }

    # Verify brace, bracket, and quote balance across the entire source.
    proc checkBalance {src filename} {
        set issues {}
        set braceDepth 0
        set bracketDepth 0
        set inDouble 0
        set braceOpenLine 0
        set bracketOpenLine 0
        set doubleOpenLine 0
        set atCmdStart 1
        set lineNum 1
        set len [string length $src]

        for {set i 0} {$i < $len} {incr i} {
            set ch [string index $src $i]

            # Backslash escape — skip next char
            if {$ch eq "\\"} {
                if {$i+1 < $len && [string index $src [expr {$i+1}]] eq "\n"} {
                    incr lineNum
                }
                incr i
                continue
            }

            if {$ch eq "\n"} {
                incr lineNum
                set atCmdStart 1
                continue
            }

            # Skip comments that begin at command start.
            if {$braceDepth == 0 && !$inDouble && $atCmdStart && $ch eq "#"} {
                while {$i < $len && [string index $src $i] ne "\n"} {
                    incr i
                }
                if {$i < $len} {
                    incr lineNum
                    set atCmdStart 1
                }
                continue
            }

            if {$ch eq " " || $ch eq "\t" || $ch eq "\r"} {
                continue
            }
            if {$ch eq ";"} {
                set atCmdStart 1
                continue
            }
            set atCmdStart 0

            # Inside double-quoted string
            if {$inDouble} {
                if {$ch eq "\""} { set inDouble 0 }
                continue
            }

            # Comment: rest of line is ignored (only at command start, but
            # for balance checking we skip # lines to avoid false positives)
            # We handle this by skipping brace tracking inside string content
            # Note: a full parser handles this; here we do a simpler heuristic

            switch -- $ch {
                "\{" {
                    if {$braceDepth == 0} { set braceOpenLine $lineNum }
                    incr braceDepth
                }
                "\}" {
                    incr braceDepth -1
                    if {$braceDepth < 0} {
                        lappend issues [list $filename $lineNum ERROR syntax \
                               "Unexpected '\}': no matching opening brace"]
                        set braceDepth 0
                    }
                }
                "\[" {
                    if {$bracketDepth == 0} { set bracketOpenLine $lineNum }
                    incr bracketDepth
                }
                "\]" {
                    incr bracketDepth -1
                    if {$bracketDepth < 0} {
                        lappend issues [list $filename $lineNum ERROR syntax \
                            "Unexpected '\]': no matching opening bracket"]
                        set bracketDepth 0
                    }
                }
                "\"" {
                    set inDouble 1
                    set doubleOpenLine $lineNum
                }
            }
        }

        if {$braceDepth > 0} {
            lappend issues [list $filename $braceOpenLine ERROR syntax \
                "Unbalanced '\{': $braceDepth unclosed brace(s) (opened near line $braceOpenLine)"]
        }
        if {$bracketDepth > 0} {
            lappend issues [list $filename $bracketOpenLine ERROR syntax \
                "Unbalanced '\[': $bracketDepth unclosed bracket(s) (opened near line $bracketOpenLine)"]
        }
        if {$inDouble} {
            lappend issues [list $filename $doubleOpenLine ERROR syntax \
                "Unclosed double-quote opened at line $doubleOpenLine"]
        }
        return $issues
    }

    # Check for excessively long lines (> 120 chars)
    proc checkLongLines {src filename} {
        set issues {}
        set lineNum 1
        foreach line [split $src "\n"] {
            if {[string length $line] > 120} {
                lappend issues [list $filename $lineNum INFO style \
                    "Line exceeds 120 characters ([string length $line] chars)"]
            }
            incr lineNum
        }
        return $issues
    }

    # Check for close-brace indentation alignment.
    # For each close brace on its own line, verify it aligns with the opener.
    proc checkBraceAlignment {src filename} {
        set issues {}
        set lines [split $src "\n"]
        # Stack entries are column and line number for each open brace.
        set openStack {}
        set lineNum 0

        foreach line $lines {
            incr lineNum
            set col 0
            set len [string length $line]
            for {set i 0} {$i < $len} {incr i} {
                set ch [string index $line $i]
                if {$ch eq "\\"} { incr i; continue }
                if {$ch eq "\{"} {
                    lappend openStack [list $col $lineNum]
                } elseif {$ch eq "\}"} {
                    if {[llength $openStack] > 0} {
                        set opener [lindex $openStack end]
                        set openStack [lrange $openStack 0 end-1]
                        set openCol [lindex $opener 0]
                        # Only flag when the close brace is first non-space char on line.
                        set trimmed [string trimleft $line]
                        if {[string index $trimmed 0] eq "\}" && $col != $openCol} {
                            lappend issues [list $filename $lineNum INFO style \
                                "Close brace at column $col; opening brace was at column $openCol (line [lindex $opener 1])"]
                        }
                    }
                }
                incr col
            }
        }
        return $issues
    }
}
