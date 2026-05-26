# parser.tcl — TCL tokenizer and command splitter
# Produces a list of parsed commands from a TCL script string.
# Each command record: {lineNum wordList bodyMap}
#   wordList  — list of word strings (substitutions not expanded)
#   bodyMap   — dict of wordIndex -> list of sub-commands (for brace-bodies)

namespace eval ::tclcheck::parser {

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    # Parse a file; return list of command records or emit parse ERRORs
    # into the issues list (passed by name).
    proc parseFile {filename issuesVar} {
        upvar 1 $issuesVar issues
        if {![file readable $filename]} {
            lappend issues [list $filename 0 ERROR syntax "Cannot read file '$filename'"]
            return {}
        }
        set fh [open $filename r]
        set src [read $fh]
        close $fh
        return [parseScript $src $filename 1 issues]
    }

    # Parse a script string starting at the given base line number.
    # Returns list of command records.
    proc parseScript {src filename baseLine issuesVar} {
        upvar 1 $issuesVar issues
        set cmds {}
        set len [string length $src]
        set i 0
        set lineNum $baseLine

        while {$i < $len} {
            # Skip leading whitespace and blank lines
            set i [_skipWhitespace $src $i len lineNum]
            if {$i >= $len} break

            # Skip comment lines
            if {[string index $src $i] eq "#"} {
                set i [_skipToEndOfLine $src $i len lineNum]
                continue
            }

            # Collect one command
            lassign [_readCommand $src $i $len $lineNum $filename issues] \
                words endIdx newLine

            if {[llength $words] > 0} {
                lappend cmds [list $lineNum $words]
            }
            set i $endIdx
            set lineNum $newLine
        }
        return $cmds
    }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    # Skip whitespace that is NOT a newline.
    proc _skipWhitespace {src i lenVar lineVar} {
        upvar 1 $lenVar len $lineVar line
        while {$i < $len} {
            set ch [string index $src $i]
            if {$ch eq " " || $ch eq "\t" || $ch eq "\r"} {
                incr i
            } elseif {$ch eq "\n"} {
                incr i
                incr line
            } elseif {$ch eq ";"} {
                incr i
            } else {
                break
            }
        }
        return $i
    }

    proc _skipToEndOfLine {src i lenVar lineVar} {
        upvar 1 $lenVar len $lineVar line
        while {$i < $len && [string index $src $i] ne "\n"} {
            incr i
        }
        if {$i < $len} { incr i; incr line }
        return $i
    }

    # Read one command (list of words) from position i.
    # Returns: {wordList nextIndex newLineNum}
    proc _readCommand {src i len lineNum filename issuesVar} {
        upvar 1 $issuesVar issues
        set words {}
        set cmdLine $lineNum

        while {$i < $len} {
            set ch [string index $src $i]

            # Command terminators
            if {$ch eq "\n" || $ch eq ";"} {
                if {$ch eq "\n"} { incr lineNum }
                incr i
                # Check for line continuation via backslash before newline
                # (already consumed by word reader), so just break
                break
            }

            # Inline whitespace between words
            if {$ch eq " " || $ch eq "\t" || $ch eq "\r"} {
                incr i
                continue
            }

            # Comment after semicolon (already handled by outer loop but
            # catch it here after word-level parsing to be safe)
            if {$ch eq "#" && [llength $words] == 0} {
                set i [_skipToEndOfLine $src $i len lineNum]
                break
            }

            # Line continuation: backslash before newline is whitespace,
            # not a word token.  Skip both chars and continue the command.
            if {$ch eq "\\" && $i+1 < $len &&
                    [string index $src [expr {$i+1}]] eq "\n"} {
                incr i 2
                incr lineNum
                continue
            }

            # Read next word part (may be one or more adjacent parts)
            lassign [_readWord $src $i $len $lineNum $filename issues] \
                word endIdx newLine

            # Merge adjacent word parts with no separating whitespace
            set i $endIdx
            set lineNum $newLine
            while {$i < $len} {
                set ch [string index $src $i]
                if {$ch eq " " || $ch eq "\t" || $ch eq "\r" || $ch eq "\n" || $ch eq ";"} {
                    break
                }
                # Backslash-newline inside merge: treat as word boundary
                if {$ch eq "\\" && $i+1 < $len &&
                        [string index $src [expr {$i+1}]] eq "\n"} {
                    break
                }
                # Read the next contiguous piece and append it
                lassign [_readWord $src $i $len $lineNum $filename issues] nextPart nextIdx nextLine
                append word $nextPart
                set i $nextIdx
                set lineNum $nextLine
            }

            lappend words $word
        }
        return [list $words $i $lineNum]
    }

    # Read a single word from position i.
    # Returns: {wordString nextIndex newLineNum}
    proc _readWord {src i len lineNum filename issuesVar} {
        upvar 1 $issuesVar issues
        set ch [string index $src $i]

        if {$ch eq "\{"} {
            return [_readBraceWord $src $i $len $lineNum $filename issues]
        } elseif {$ch eq "\""} {
            return [_readQuotedWord $src $i $len $lineNum $filename issues]
        } elseif {$ch eq "\["} {
            return [_readBracketWord $src $i $len $lineNum $filename issues]
        } else {
            return [_readBareWord $src $i $len $lineNum $filename issues]
        }
    }

    # Read a brace-quoted word: {…}
    proc _readBraceWord {src i len lineNum filename issuesVar} {
        upvar 1 $issuesVar issues
        set startLine $lineNum
        set depth 1
        incr i ;# skip opening brace
        set start $i

        while {$i < $len && $depth > 0} {
            set ch [string index $src $i]
            if {$ch eq "\\"} {
                incr i 2
                continue
            }
            if {$ch eq "\{"} { incr depth }
            if {$ch eq "\}"} { incr depth -1 }
            if {$ch eq "\n"} { incr lineNum }
            incr i
        }

        if {$depth != 0} {
            lappend issues [list $filename $startLine ERROR syntax \
                "Unbalanced brace: missing closing '\}'"]
        }

        set word [string range $src $start [expr {$i - 2}]]
        return [list "\{$word\}" $i $lineNum]
    }

    # Read a double-quoted word: "…"
    proc _readQuotedWord {src i len lineNum filename issuesVar} {
        upvar 1 $issuesVar issues
        set startLine $lineNum
        set bracketDepth 0
        incr i ;# skip opening "
        set word "\""

        while {$i < $len} {
            set ch [string index $src $i]
            if {$ch eq "\\"} {
                set next [string index $src [expr {$i+1}]]
                append word $ch $next
                if {$next eq "\n"} { incr lineNum }
                incr i 2
                continue
            }
            if {$ch eq "\["} {
                incr bracketDepth
                append word $ch
                incr i
                continue
            }
            if {$ch eq "\]" && $bracketDepth > 0} {
                incr bracketDepth -1
                append word $ch
                incr i
                continue
            }
            if {$ch eq "\"" && $bracketDepth == 0} {
                append word $ch
                incr i
                break
            }
            if {$ch eq "\n"} { incr lineNum }
            append word $ch
            incr i
        }

        if {[string index $word end] ne "\""} {
            lappend issues [list $filename $startLine ERROR syntax \
                "Unclosed double-quote starting at line $startLine"]
        }
        return [list $word $i $lineNum]
    }

    # Read a bracket-command substitution: […]
    proc _readBracketWord {src i len lineNum filename issuesVar} {
        upvar 1 $issuesVar issues
        set startLine $lineNum
        set depth 1
        set braceDepth 0
        set inDouble 0
        incr i ;# skip [
        set start $i

        while {$i < $len && $depth > 0} {
            set ch [string index $src $i]
            if {$ch eq "\\"} {
                if {$i + 1 < $len && [string index $src [expr {$i+1}]] eq "\n"} {
                    incr lineNum
                }
                incr i 2
                continue
            }

            if {$ch eq "\n"} {
                incr lineNum
                incr i
                continue
            }

            if {$inDouble} {
                if {$ch eq "\""} {
                    set inDouble 0
                }
                incr i
                continue
            }

            if {$ch eq "\""} {
                set inDouble 1
                incr i
                continue
            }

            if {$ch eq "\{"} {
                incr braceDepth
                incr i
                continue
            }
            if {$ch eq "\}" && $braceDepth > 0} {
                incr braceDepth -1
                incr i
                continue
            }

            if {$braceDepth == 0} {
                if {$ch eq "\["} { incr depth }
                if {$ch eq "\]"} { incr depth -1 }
            }
            incr i
        }

        if {$depth != 0} {
            lappend issues [list $filename $startLine ERROR syntax \
                "Unclosed bracket '\[' starting at line $startLine"]
        }

        set inner [string range $src $start [expr {$i - 2}]]
        return [list "\[$inner\]" $i $lineNum]
    }

    # Read an unquoted (bare) word — terminated by whitespace, ; or \n
    proc _readBareWord {src i len lineNum filename issuesVar} {
        upvar 1 $issuesVar issues
        set start $i
        set bracketDepth 0

        while {$i < $len} {
            set ch [string index $src $i]

            if {$ch eq "\["} {
                incr bracketDepth
                incr i
                continue
            }
            if {$ch eq "\]" && $bracketDepth > 0} {
                incr bracketDepth -1
                incr i
                continue
            }

            if {$ch eq " " || $ch eq "\t" || $ch eq "\r" ||
                $ch eq "\n" || $ch eq ";"} {
                if {$bracketDepth > 0} {
                    incr i
                    if {$ch eq "\n"} { incr lineNum }
                    continue
                }
                break
            }
            if {$ch eq "\\"} {
                set next [string index $src [expr {$i+1}]]
                if {$next eq "\n"} {
                    # Line continuation: treat as whitespace
                    incr i 2
                    incr lineNum
                    continue
                }
                incr i 2
                continue
            }
            incr i
        }
        set word [string range $src $start [expr {$i - 1}]]
        return [list $word $i $lineNum]
    }

    # ------------------------------------------------------------------
    # Word classification helpers (used by check modules)
    # ------------------------------------------------------------------

    # Returns 1 if word is brace-quoted (literal body)
    proc isBraceWord {word} {
        return [expr {[string index $word 0] eq "\{" &&
                      [string index $word end] eq "\}"}]
    }

    # Returns 1 if word is double-quoted
    proc isQuotedWord {word} {
        return [expr {[string index $word 0] eq "\"" &&
                      [string index $word end] eq "\""}]
    }

    # Returns 1 if word is a bracket command substitution
    proc isBracketWord {word} {
        return [expr {[string index $word 0] eq "\[" &&
                      [string index $word end] eq "\]"}]
    }

    # Returns 1 if word contains variable substitution
    proc hasDollarSub {word} {
        return [expr {[string first "\$" $word] >= 0}]
    }

    # Returns 1 if word is purely dynamic (starts with $ or [)
    proc isDynamic {word} {
        set ch [string index $word 0]
        return [expr {$ch eq "\$" || $ch eq "\["}]
    }

    # Strip outer braces from a brace-word to get the inner script
    proc stripBraces {word} {
        if {[isBraceWord $word]} {
            return [string range $word 1 end-1]
        }
        return $word
    }

    # Strip outer quotes from a quoted word
    proc stripQuotes {word} {
        if {[isQuotedWord $word]} {
            return [string range $word 1 end-1]
        }
        return $word
    }

    # Extract variable name(s) referenced by $-substitution patterns in a word.
    # Returns list of {varname isDynamic} pairs.
    proc extractVarRefs {word} {
        set refs {}
        set i 0
        set len [string length $word]
        while {$i < $len} {
            if {[string index $word $i] eq "\$"} {
                incr i
                set varname ""
                set dynamic 0
                if {$i < $len && [string index $word $i] eq "\{"} {
                    # ${varname} form
                    incr i
                    set start $i
                    while {$i < $len && [string index $word $i] ne "\}"} {
                        incr i
                    }
                    set varname [string range $word $start [expr {$i-1}]]
                    incr i
                } elseif {$i < $len && [string index $word $i] eq "\["} {
                    set dynamic 1
                    set varname "DYNAMIC"
                    # skip bracket content
                    set depth 1
                    incr i
                    while {$i < $len && $depth > 0} {
                        set c [string index $word $i]
                        if {$c eq "\["} { incr depth }
                        if {$c eq "\]"} { incr depth -1 }
                        incr i
                    }
                } else {
                    set start $i
                    while {$i < $len} {
                        set c [string index $word $i]
                        # array element: stop at ( and grab rest up to )
                        if {$c eq "("} {
                            set base [string range $word $start [expr {$i-1}]]
                            incr i
                            set keystart $i
                            while {$i < $len && [string index $word $i] ne ")"} {
                                incr i
                            }
                            set key [string range $word $keystart [expr {$i-1}]]
                            incr i
                            # Check if key contains dynamic part
                            if {[string first "\$" $key] >= 0 ||
                                [string first "\[" $key] >= 0} {
                                set dynamic 1
                            }
                            set varname "${base}($key)"
                            break
                        }
                        if {[string match {[a-zA-Z0-9_]} $c]} {
                            incr i
                            continue
                        }
                        if {$c eq ":"} {
                            if {$i+1 < $len && [string index $word [expr {$i+1}]] eq ":"} {
                                incr i 2
                                continue
                            }
                            break
                        }
                        break
                    }
                    if {$varname eq ""} {
                        set varname [string range $word $start [expr {$i-1}]]
                    }
                    # Check if variable name itself contains substitution
                    if {[string first "\$" $varname] >= 0} {
                        set dynamic 1
                    }
                }
                if {$varname ne ""} {
                    lappend refs [list $varname $dynamic]
                }
            } else {
                incr i
            }
        }
        return $refs
    }

    # Determine the variable name being assigned by a `set` command.
    # Returns {name isDynamic isArray arrayKey}
    proc parseSetTarget {word} {
        # Dynamic: starts with $ or [
        if {[isDynamic $word]} {
            return [list "" 1 0 ""]
        }
        # Check for embedded $ (partially dynamic: var$x)
        if {[string first "\$" $word] >= 0} {
            set prefix [string range $word 0 [expr {[string first "\$" $word]-1}]]
            return [list $prefix 1 0 ""]
        }
        # Array element: name(key)
        if {[regexp {^([^(]+)\(([^)]*)\)$} $word -> arrname key]} {
            set keyDyn [expr {[string first "\$" $key] >= 0 ||
                              [string first "\[" $key] >= 0}]
            return [list $arrname 0 1 $key]
        }
        return [list $word 0 0 ""]
    }
}
