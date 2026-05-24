# checks/variables.tcl — Variable usage checks
# Checks for undefined variable reads, missing global declarations,
# unused variables, and dynamic variable patterns.

namespace eval ::tclcheck::checks::variables {

    # Commands that assign to their first argument (besides set)
    variable assignCmds {incr append lappend set unset}

    # Commands that bind loop variables
    variable loopBindCmds {foreach for}

    # ------------------------------------------------------------------
    # Main entry: process a single parsed command in current scope context
    # ------------------------------------------------------------------

    # Process one command record {lineNum wordList} and update scope.
    # Returns list of issues.
    proc processCmd {lineNum words filename} {
        if {[llength $words] == 0} { return {} }
        set cmd [lindex $words 0]
        set issues {}

        switch -- $cmd {
            proc     { }
            namespace { }
            set      { lappend issues {*}[_processSet $lineNum $words $filename] }
            global   { _processGlobal $lineNum $words }
            variable { _processVariable $lineNum $words $filename }
            upvar    { _processUpvar $lineNum $words $filename }
            unset    { lappend issues {*}[_processUnset $lineNum $words $filename] }
            incr     { lappend issues {*}[_processIncr $lineNum $words $filename] }
            lassign  { lappend issues {*}[_processLassign $lineNum $words $filename] }
            foreach  { lappend issues {*}[_processForeach $lineNum $words $filename] }
            for      { lappend issues {*}[_processFor $lineNum $words $filename] }
            catch    { lappend issues {*}[_processCatch $lineNum $words $filename] }
            if       { lappend issues {*}[_processIf $lineNum $words $filename] }
            default  {
                # Check all $ references in the word list
                lappend issues {*}[_checkWordRefs $lineNum $words $filename]
            }
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # Per-command handlers
    # ------------------------------------------------------------------

    proc _processSet {lineNum words filename} {
        set issues {}
        if {[llength $words] < 2} { return {} }

        set nameWord [lindex $words 1]
        set hasValue [expr {[llength $words] >= 3}]

        # Classify the target name
        set kind [::tclcheck::dynvar::classify $nameWord]

        switch -- $kind {
            full {
                # Fully dynamic: set $varname ... or set [cmd] ...
                ::tclcheck::scope::setFullyDynamic
                lappend issues [list $filename $lineNum INFO dynamic-var \
                    "Fully dynamic variable assignment 'set $nameWord': variable checks suppressed in this scope"]
            }
            partial {
                # Partially dynamic: set var$x ...
                set prefix [::tclcheck::dynvar::staticPrefix $nameWord]
                ::tclcheck::scope::addDynPrefix $prefix
                lappend issues [list $filename $lineNum INFO dynamic-var \
                    "Dynamic variable name 'set $nameWord': references matching prefix '$prefix' will not be flagged"]
            }
            static {
                lassign [::tclcheck::parser::parseSetTarget $nameWord] \
                    varname isDyn isArray arrayKey

                if {$isArray} {
                    # Array element assignment
                    if {[string first "\$" $arrayKey] >= 0 ||
                        [string first "\[" $arrayKey] >= 0} {
                        # Dynamic key
                        ::tclcheck::scope::setArrayDynKey $varname
                    }
                    ::tclcheck::scope::define "${varname}($arrayKey)" $lineNum
                    ::tclcheck::scope::define $varname $lineNum
                } else {
                    if {$hasValue} {
                        ::tclcheck::scope::define $varname $lineNum
                    }
                }
            }
        }

        # Check RHS ($-references in value word and name if dynamic)
        if {$hasValue} {
            set valueWord [lindex $words 2]
            lappend issues {*}[_checkSingleWord $lineNum $valueWord $filename]
        }
        # Also check name word for embedded references
        lappend issues {*}[_checkSingleWord $lineNum $nameWord $filename]

        return $issues
    }

    proc _processGlobal {lineNum words} {
        foreach varname [lrange $words 1 end] {
            ::tclcheck::scope::declareGlobal $varname
        }
    }

    proc _processVariable {lineNum words filename} {
        set issues {}
        set i 1
        while {$i < [llength $words]} {
            set varname [lindex $words $i]
            incr i
            # optional initializer
            if {$i < [llength $words]} {
                set val [lindex $words $i]
                # Check if initializer contains references
                lappend issues {*}[_checkSingleWord $lineNum $val $filename]
                incr i
            }
            ::tclcheck::scope::declareNamespaceVar $varname $lineNum
        }
        return $issues
    }

    proc _processUpvar {lineNum words filename} {
        set issues {}
        # upvar ?level? varName localAlias ?varName localAlias ...?
        set i 1
        set level 1
        # Optional level argument
        if {$i < [llength $words]} {
            set first [lindex $words $i]
            if {[regexp {^[0-9]+$} $first] || [regexp {^#[0-9]+$} $first]} {
                set level $first
                incr i
            }
        }
        # Process pairs
        while {$i+1 < [llength $words]} {
            set remoteWord [lindex $words $i]
            set localAlias [lindex $words [expr {$i+1}]]
            set isDyn [expr {[::tclcheck::parser::isDynamic $remoteWord] ||
                             [string first "\$" $remoteWord] >= 0}]
            ::tclcheck::scope::defineUpvar $localAlias $remoteWord $level $isDyn
            incr i 2
        }
        if {$i < [llength $words]} {
            lappend issues [list $filename $lineNum ERROR variables \
                "upvar: odd number of varName/localAlias pairs"]
        }
        return $issues
    }

    proc _processUnset {lineNum words filename} {
        set issues {}
        foreach varname [lrange $words 1 end] {
            # Skip flags like -nocomplain
            if {[string match "-*" $varname]} continue
            set state [::tclcheck::scope::lookup $varname]
            if {$state eq "undefined"} {
                lappend issues [list $filename $lineNum WARN variables \
                    "unset '$varname': variable not defined in current scope"]
            }
        }
        return $issues
    }

    proc _processIncr {lineNum words filename} {
        set issues {}
        if {[llength $words] < 2} { return {} }
        set varname [lindex $words 1]
        set state [::tclcheck::scope::lookup $varname]
        if {$state eq "undefined"} {
            # incr creates the variable if not defined (treats as 0)
            ::tclcheck::scope::define $varname $lineNum
        } elseif {$state eq "global_needed"} {
            lappend issues [list $filename $lineNum WARN variables \
                "incr '$varname': variable is global but 'global $varname' not declared in this proc"]
        }
        return $issues
    }

    proc _processLassign {lineNum words filename} {
        set issues {}
        if {[llength $words] < 3} { return {} }
        # lassign listValue var1 ?var2 ...?
        set listWord [lindex $words 1]
        lappend issues {*}[_checkSingleWord $lineNum $listWord $filename]
        foreach varname [lrange $words 2 end] {
            ::tclcheck::scope::define $varname $lineNum
        }
        return $issues
    }

    proc _processForeach {lineNum words filename} {
        set issues {}
        # foreach varList valueList body
        # foreach var1 list1 ?var2 list2 ...? body
        if {[llength $words] < 4} { return {} }
        set i 1
        while {$i+2 < [llength $words]} {
            set varSpec [lindex $words $i]
            set listWord [lindex $words [expr {$i+1}]]
            lappend issues {*}[_checkSingleWord $lineNum $listWord $filename]
            # varSpec may be a single var or a brace-list of vars
            if {[::tclcheck::parser::isBraceWord $varSpec]} {
                foreach v [::tclcheck::parser::stripBraces $varSpec] {
                    ::tclcheck::scope::define $v $lineNum
                }
            } else {
                ::tclcheck::scope::define $varSpec $lineNum
            }
            incr i 2
        }
        return $issues
    }

    proc _processFor {lineNum words filename} {
        set issues {}
        # for {init} {cond} {incr} {body}
        if {[llength $words] < 5} { return {} }

        set initWord [lindex $words 1]
        set condWord [lindex $words 2]
        set incrWord [lindex $words 3]

        # Evaluate init script with the same command handlers so loop vars are
        # recorded before condition/incr references are checked.
        if {[::tclcheck::parser::isBraceWord $initWord]} {
            set initSrc [::tclcheck::parser::stripBraces $initWord]
            set parseIssues {}
            set initCmds [::tclcheck::parser::parseScript $initSrc $filename $lineNum parseIssues]
            lappend issues {*}$parseIssues
            foreach cmdRec $initCmds {
                lassign $cmdRec initLine initWords
                lappend issues {*}[processCmd $initLine $initWords $filename]
            }
        } else {
            lappend issues {*}[_checkSingleWord $lineNum $initWord $filename]
        }

        lappend issues {*}[_checkSingleWord $lineNum $condWord $filename]
        lappend issues {*}[_checkSingleWord $lineNum $incrWord $filename]
        return $issues
    }

    proc _processCatch {lineNum words filename} {
        set issues {}
        # catch script ?resultVar ?optionsVar?
        if {[llength $words] >= 3} {
            set resultVar [lindex $words 2]
            if {![::tclcheck::parser::isDynamic $resultVar]} {
                ::tclcheck::scope::define $resultVar $lineNum
            }
        }
        if {[llength $words] >= 4} {
            set optionsVar [lindex $words 3]
            if {![::tclcheck::parser::isDynamic $optionsVar]} {
                ::tclcheck::scope::define $optionsVar $lineNum
            }
        }
        return $issues
    }

    proc _processIf {lineNum words filename} {
        set issues {}
        if {[llength $words] < 2} { return {} }

        set condWord [lindex $words 1]
        lappend issues {*}[_checkSingleWord $lineNum $condWord $filename]

        # Handle bracketed catch in condition: if {[catch {...} result]} {...}
        set bracketExpr ""
        if {[::tclcheck::parser::isBracketWord $condWord]} {
            set bracketExpr [string range $condWord 1 end-1]
        } elseif {[::tclcheck::parser::isBraceWord $condWord]} {
            set innerCond [::tclcheck::parser::stripBraces $condWord]
            if {$innerCond ne "" && [string index $innerCond 0] eq "\[" &&
                [string index $innerCond end] eq "\]"} {
                set bracketExpr [string range $innerCond 1 end-1]
            }
        }

        if {$bracketExpr ne ""} {
            set parseIssues {}
            set condCmds [::tclcheck::parser::parseScript $bracketExpr $filename $lineNum parseIssues]
            lappend issues {*}$parseIssues
            foreach condRec $condCmds {
                lassign $condRec _ condWords
                if {[llength $condWords] >= 3 && [lindex $condWords 0] eq "catch"} {
                    set resultVar [lindex $condWords 2]
                    if {![::tclcheck::parser::isDynamic $resultVar]} {
                        ::tclcheck::scope::define $resultVar $lineNum
                    }
                    if {[llength $condWords] >= 4} {
                        set optionsVar [lindex $condWords 3]
                        if {![::tclcheck::parser::isDynamic $optionsVar]} {
                            ::tclcheck::scope::define $optionsVar $lineNum
                        }
                    }
                }
            }
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # Reference checking helpers
    # ------------------------------------------------------------------

    # Check all words in a command for $-references
    proc _checkWordRefs {lineNum words filename} {
        set issues {}
        foreach word [lrange $words 1 end] {
            lappend issues {*}[_checkSingleWord $lineNum $word $filename]
        }
        return $issues
    }

    # Check a single word for $-references that may be undefined
    proc _checkSingleWord {lineNum word filename} {
        set issues {}
        set pairs [::tclcheck::parser::extractVarRefs $word]
        foreach pair $pairs {
            lassign $pair varname isDyn
            if {$isDyn || $varname eq "DYNAMIC" || $varname eq ""} continue

            # Strip array indexing for lookup
            regexp {^([^(]+)} $varname baseVar

            set state [::tclcheck::scope::lookup $baseVar]
            switch -- $state {
                defined     { ::tclcheck::scope::markUsed $baseVar }
                global_needed {
                    lappend issues [list $filename $lineNum WARN variables \
                        "Variable '\$$baseVar' is global but 'global $baseVar' not declared in this proc"]
                }
                undefined {
                    # Check dynamic prefix suppression at any scope level
                    if {![::tclcheck::scope::matchesDynPrefix $baseVar] &&
                        ![::tclcheck::scope::isFullyDynamic]} {
                        lappend issues [list $filename $lineNum WARN variables \
                            "Variable '\$$baseVar' used but never defined in this scope"]
                    }
                }
            }
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # Post-scope harvest: collect unused variables
    # ------------------------------------------------------------------

    proc harvestUnused {frame filename} {
        set issues {}
        foreach pair [::tclcheck::scope::getUnusedVars $frame] {
            lassign $pair varname defLine
            lappend issues [list $filename $defLine INFO variables \
                "Variable '$varname' is set but never read"]
        }
        return $issues
    }
}
