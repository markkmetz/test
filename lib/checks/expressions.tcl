# checks/expressions.tcl — Expression and control-flow checks
# Detects unbraced conditions, division by zero, unknown math functions,
# and mismatched parentheses inside braced expressions.

namespace eval ::tclcheck::checks::expressions {

    # Commands whose first argument should be a braced expression
    variable exprCmds {expr if elseif while}

    # Commands with specific structure
    variable forCmd for

    # ------------------------------------------------------------------
    # Main entry
    # ------------------------------------------------------------------

    proc processCmd {lineNum words filename} {
        if {[llength $words] == 0} { return {} }
        set cmd [lindex $words 0]
        set issues {}

        switch -- $cmd {
            expr     { lappend issues {*}[_checkExpr $lineNum $words $filename] }
            if       { lappend issues {*}[_checkIf $lineNum $words $filename] }
            elseif   { lappend issues {*}[_checkIf $lineNum $words $filename] }
            while    { lappend issues {*}[_checkWhile $lineNum $words $filename] }
            for      { lappend issues {*}[_checkFor $lineNum $words $filename] }
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # Per-command handlers
    # ------------------------------------------------------------------

    proc _checkExpr {lineNum words filename} {
        set issues {}
        if {[llength $words] < 2} { return {} }

        set condWord [lindex $words 1]

        # Single word that is NOT braced
        if {[llength $words] == 2} {
            if {![::tclcheck::parser::isBraceWord $condWord]} {
                lappend issues [list $filename $lineNum WARN expressions \
                    "Unbraced 'expr' argument: use {expr {...}} to avoid double-substitution"]
            } else {
                # Braced — validate expression syntax
                set inner [::tclcheck::parser::stripBraces $condWord]
                lappend issues {*}[_validateExprString $inner $filename $lineNum]
            }
        } else {
            # Multiple words: expr $a + $b style
            lappend issues [list $filename $lineNum WARN expressions \
                "Unbraced 'expr': combine into a single braced argument {expr {$condWord ...}}"]
        }
        return $issues
    }

    proc _checkIf {lineNum words filename} {
        set issues {}
        if {[llength $words] < 2} { return {} }
        set condWord [lindex $words 1]

        if {![::tclcheck::parser::isBraceWord $condWord] &&
            ![::tclcheck::parser::isQuotedWord $condWord]} {
            lappend issues [list $filename $lineNum WARN expressions \
                "Unbraced '[lindex $words 0]' condition: use {condition} to prevent double-substitution"]
        } elseif {[::tclcheck::parser::isBraceWord $condWord]} {
            set inner [::tclcheck::parser::stripBraces $condWord]
            lappend issues {*}[_validateExprString $inner $filename $lineNum]
        }
        return $issues
    }

    proc _checkWhile {lineNum words filename} {
        set issues {}
        if {[llength $words] < 2} { return {} }
        set condWord [lindex $words 1]

        if {![::tclcheck::parser::isBraceWord $condWord] &&
            ![::tclcheck::parser::isQuotedWord $condWord]} {
            lappend issues [list $filename $lineNum WARN expressions \
                "Unbraced 'while' condition: use {condition}"]
        } elseif {[::tclcheck::parser::isBraceWord $condWord]} {
            set inner [::tclcheck::parser::stripBraces $condWord]
            lappend issues {*}[_validateExprString $inner $filename $lineNum]
        }
        return $issues
    }

    proc _checkFor {lineNum words filename} {
        set issues {}
        # for {init} {cond} {incr} {body}
        if {[llength $words] < 5} { return {} }
        foreach idx {1 2 3 4} label {init cond incr body} {
            set w [lindex $words $idx]
            if {![::tclcheck::parser::isBraceWord $w]} {
                lappend issues [list $filename $lineNum WARN expressions \
                    "'for' $label argument should be braced: use {$label}"]
            }
        }
        # Validate condition expression if braced
        set condWord [lindex $words 2]
        if {[::tclcheck::parser::isBraceWord $condWord]} {
            set inner [::tclcheck::parser::stripBraces $condWord]
            lappend issues {*}[_validateExprString $inner $filename $lineNum]
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # Expression string validator
    # ------------------------------------------------------------------

    proc _validateExprString {expr filename lineNum} {
        set issues {}

        # Heuristic: expressions containing command substitutions often carry
        # regex/list syntax that looks like unmatched parens to this lightweight
        # validator. Skip deep validation to avoid noisy false positives.
        if {[string first "\[" $expr] >= 0 || [string first "\]" $expr] >= 0} {
            return $issues
        }

        # Check parenthesis balance
        set depth 0
        set openLine $lineNum
        set i 0
        set len [string length $expr]
        while {$i < $len} {
            set ch [string index $expr $i]
            if {$ch eq "\\"} { incr i 2; continue }
            if {$ch eq "("} { incr depth }
            if {$ch eq ")"} {
                incr depth -1
                if {$depth < 0} {
                    lappend issues [list $filename $lineNum ERROR expressions \
                        "Unmatched ')' in expression"]
                    set depth 0
                }
            }
            incr i
        }
        if {$depth > 0} {
            lappend issues [list $filename $lineNum ERROR expressions \
                "Unclosed '(' in expression: $depth unmatched"]
        }

        # Check for literal division by zero: / 0 or /0
        if {[regexp {/\s*0\b} $expr]} {
            lappend issues [list $filename $lineNum WARN expressions \
                "Possible division by zero in expression"]
        }

        # Check for unknown math functions: word followed by (
        # Exclude known operators and keywords
        set knownWords {if else eq ne in ni}
        set i 0
        while {[regexp -indices -start $i {([a-zA-Z_][a-zA-Z0-9_]*)\s*\(} \
                $expr match funcMatch]} {
            set start [lindex $funcMatch 0]
            set end   [lindex $funcMatch 1]
            set fname [string range $expr $start $end]
            set i [expr {$end + 1}]
            if {$start > 0 && [string index $expr [expr {$start - 1}]] eq "\$"} {
                continue
            }
            if {$fname ni $knownWords &&
                ![::tclcheck::builtins::isMathFunc $fname]} {
                lappend issues [list $filename $lineNum WARN expressions \
                    "Unknown math function '${fname}()' in expression"]
            }
        }

        return $issues
    }
}
