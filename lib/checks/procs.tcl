# checks/procs.tcl — Procedure definition and call validation
# Checks arg counts, forward references, undefined procs, redefinition.

namespace eval ::tclcheck::checks::procs {

    # Symbol table: qualName -> {filename lineNum minArgs maxArgs argNames}
    variable symTable {}

    # Pending calls to validate after first pass: list of {qualName argc filename lineNum}
    variable pendingCalls {}

    proc reset {} {
        variable symTable {}
        variable pendingCalls {}
    }

    # ------------------------------------------------------------------
    # First-pass registration
    # ------------------------------------------------------------------

    # Register a proc discovered during first pass.
    proc registerProc {qualName filename lineNum argList} {
        variable symTable
        if {[dict exists $symTable $qualName]} {
            # Redefinition — will warn during second pass
        }
        lassign [_parseArgList $argList] minA maxA argNames
        dict set symTable $qualName [list $filename $lineNum $minA $maxA $argNames]
        # Also register with imports module
        ::tclcheck::imports::registerProc $qualName
    }

    # Parse a proc argument list into {minArgs maxArgs argNames}
    proc _parseArgList {argList} {
        # Strip outer braces if present
        if {[::tclcheck::parser::isBraceWord $argList]} {
            set argList [::tclcheck::parser::stripBraces $argList]
        }
        if {[catch {set args [lrange $argList 0 end]}]} {
            # Fall back to variadic to avoid hard-failing on exotic argument
            # lists from third-party code; analysis can continue safely.
            return [list 0 -1 {}]
        }
        set required 0
        set optional 0
        set hasArgs 0
        set names {}

        foreach arg $args {
            if {[catch {set argLen [llength $arg]}]} {
                return [list 0 -1 {}]
            }
            if {$argLen == 1} {
                if {$arg eq "args"} {
                    set hasArgs 1
                } else {
                    incr required
                    lappend names $arg
                }
            } else {
                # {name default}
                incr optional
                if {[catch {lappend names [lindex $arg 0]}]} {
                    return [list 0 -1 {}]
                }
            }
        }

        set minA $required
        set maxA [expr {$hasArgs ? -1 : $required + $optional}]
        return [list $minA $maxA $names]
    }

    # ------------------------------------------------------------------
    # Second-pass checks
    # ------------------------------------------------------------------

    # Process a command during second pass
    proc processCmd {lineNum words filename} {
        if {[llength $words] == 0} { return {} }
        set cmd [lindex $words 0]
        set issues {}

        switch -- $cmd {
            proc {
                lappend issues {*}[_checkProcDef $lineNum $words $filename]
            }
            return {
                # return at global scope is an error
                if {[::tclcheck::scope::currentType] eq "global" &&
                    [file tail $filename] ne "pkgIndex.tcl"} {
                    # This is often valid in module guard/loader patterns;
                    # report as WARN to reduce hard false positives.
                    lappend issues [list $filename $lineNum WARN procs \
                        "'return' used at global scope (outside a proc)"]
                }
            }
            upvar {
                lappend issues {*}[_checkUpvarArgs $lineNum $words $filename]
            }
            default {
                lappend issues {*}[_checkCall $lineNum $words $filename]
            }
        }
        return $issues
    }

    proc _checkProcDef {lineNum words filename} {
        variable symTable
        set issues {}
        if {[llength $words] != 4} {
            lappend issues [list $filename $lineNum ERROR procs \
                "proc definition must have exactly 3 arguments: name arglist body"]
            return $issues
        }
        set name [lindex $words 1]
        set qualName [::tclcheck::scope::qualifyName $name]

        if {[dict exists $symTable $qualName]} {
            set prev [dict get $symTable $qualName]
            set prevFile [lindex $prev 0]
            set prevLine [lindex $prev 1]
            if {!(($prevFile eq $filename) && ($prevLine == $lineNum))} {
                lappend issues [list $filename $lineNum WARN procs \
                    "proc '$name' redefined (previously defined at $prevFile:$prevLine)"]
            }
        }
        return $issues
    }

    proc _checkUpvarArgs {lineNum words filename} {
        set issues {}
        # upvar ?level? varName localAlias ...
        set i 1
        if {$i < [llength $words]} {
            set first [lindex $words $i]
            if {[regexp {^[0-9]+$} $first] || [regexp {^#[0-9]+$} $first]} {
                incr i
            }
        }
        set remaining [expr {[llength $words] - $i}]
        if {$remaining % 2 != 0} {
            lappend issues [list $filename $lineNum ERROR procs \
                "upvar: odd number of varName/localAlias pairs after level"]
        }
        return $issues
    }

    proc _checkCall {lineNum words filename} {
        variable symTable
        set issues {}
        set cmd [lindex $words 0]
        set argc [expr {[llength $words] - 1}]

        # Heuristic: treat multiple adjacent command/quoted/brace pieces
        # after a `set` target as a single RHS argument. This avoids
        # false positives where the RHS is constructed from adjoining
        # bracket/quoted/brace substitutions (e.g. [cmd][cmd2]).
        if {$cmd eq "set" && $argc > 2} {
            set allCompound 1
            for {set k 2} {$k < [llength $words]} {incr k} {
                set w [lindex $words $k]
                if { ! ( [::tclcheck::parser::isBracketWord $w] || [string match "\[*" $w] \
                        || [::tclcheck::parser::isQuotedWord $w] || [string match "\"*" $w] \
                        || [::tclcheck::parser::isBraceWord $w] || [string match "\{*" $w] ) } {
                    set allCompound 0
                    break
                }
            }
            if {$allCompound} {
                set argc 2
            }
        }

        # Skip dynamic commands
        if {[::tclcheck::parser::isDynamic $cmd]} { return {} }
        # Skip namespace-qualified unknown cmds — may be from imported packages
        if {[string match "*::*" $cmd]} { return {} }
        # Skip commands that look like variable expansions
        if {[string first "\$" $cmd] >= 0} { return {} }

        set qualName [::tclcheck::scope::qualifyName $cmd]

        # Check builtins first
        set range [::tclcheck::builtins::getArgRange $cmd]
        if {$range ne ""} {
            lappend issues {*}[_checkArgCount $argc $range $cmd $filename $lineNum builtins]
            # Check subcommand if applicable
            if {[llength $words] >= 2} {
                set subcmd [lindex $words 1]
                if {![::tclcheck::parser::isDynamic $subcmd]} {
                    set subrange [::tclcheck::builtins::getSubcmdRange $cmd $subcmd]
                    if {$subrange ne ""} {
                        # argc relative to subcommand (subtract 2: cmd + subcmd)
                        set subArgc [expr {[llength $words] - 2}]
                        lappend issues {*}[_checkArgCount $subArgc $subrange \
                            "$cmd $subcmd" $filename $lineNum builtins]
                    }
                }
            }
            return $issues
        }

        # Check user-defined procs (try both qualified and unqualified)
        set entry ""
        if {[dict exists $symTable $qualName]} {
            set candidate [dict get $symTable $qualName]
            # For unqualified names, avoid binding to unrelated proc definitions
            # collected from other standalone files in a directory scan.
            if {[string first "::" $cmd] < 0} {
                set candidateFile [lindex $candidate 0]
                if {$candidateFile eq $filename} {
                    set entry $candidate
                }
            } else {
                set entry $candidate
            }
        } elseif {[dict exists $symTable "::$cmd"]} {
            set candidate [dict get $symTable "::$cmd"]
            if {[string first "::" $cmd] < 0} {
                set candidateFile [lindex $candidate 0]
                if {$candidateFile eq $filename} {
                    set entry $candidate
                }
            } else {
                set entry $candidate
            }
        }

        if {$entry ne ""} {
            lassign $entry _ _ minA maxA _
            lappend issues {*}[_checkArgCount $argc [list $minA $maxA] $cmd $filename $lineNum procs]
            return $issues
        }

        # Unknown command — defer to pending check list
        # (may be defined later in same file or in a sourced file)
        # For now: warn only if it doesn't look like a variable or bracket
        if {![string match "\[*" $cmd] && ![string match "\$*" $cmd] &&
            $cmd ne "" && ![string match "*\$*" $cmd]} {
            # Add to deferred; post-analysis will check if still unresolved
            lappend ::tclcheck::checks::procs::pendingCalls \
                [list $qualName $argc $filename $lineNum $cmd]
        }
        return $issues
    }

    proc _checkArgCount {argc range cmdName filename lineNum category} {
        set issues {}
        lassign $range minA maxA
        if {$argc < $minA} {
            lappend issues [list $filename $lineNum ERROR $category \
                "'$cmdName' requires at least $minA argument(s), got $argc"]
        } elseif {$maxA >= 0 && $argc > $maxA} {
            lappend issues [list $filename $lineNum ERROR $category \
                "'$cmdName' accepts at most $maxA argument(s), got $argc"]
        }
        return $issues
    }

    # ------------------------------------------------------------------
    # Post-analysis: resolve deferred calls
    # ------------------------------------------------------------------

    proc resolvePendingCalls {} {
        variable symTable
        variable pendingCalls
        set issues {}

        foreach callInfo $pendingCalls {
            lassign $callInfo qualName argc filename lineNum origCmd

            set entry ""
            if {[dict exists $symTable $qualName]} {
                set candidate [dict get $symTable $qualName]
                if {[string first "::" $origCmd] < 0} {
                    set candidateFile [lindex $candidate 0]
                    if {$candidateFile eq $filename} {
                        set entry $candidate
                    }
                } else {
                    set entry $candidate
                }
            } elseif {[dict exists $symTable "::$origCmd"]} {
                set candidate [dict get $symTable "::$origCmd"]
                if {[string first "::" $origCmd] < 0} {
                    set candidateFile [lindex $candidate 0]
                    if {$candidateFile eq $filename} {
                        set entry $candidate
                    }
                } else {
                    set entry $candidate
                }
            }

            if {$entry ne ""} {
                lassign $entry _ _ minA maxA _
                lappend issues {*}[_checkArgCount $argc [list $minA $maxA] \
                    $origCmd $filename $lineNum procs]
            } else {
                # Still unknown after all files processed
                lappend issues [list $filename $lineNum WARN procs \
                    "Call to unknown command '$origCmd'"]
            }
        }
        # Clear pending
        set pendingCalls {}
        return $issues
    }
}
