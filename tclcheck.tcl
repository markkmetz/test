# tclcheck.tcl — Main entry point for the TCL syntax checker
#
# Usage:
#   tclsh tclcheck.tcl [options] file1.tcl ?file2.tcl ...?
#   tclsh tclcheck.tcl --dir <path> [options]
#
# Options:
#   --dir <path>         Check all .tcl files in directory recursively
#   --severity <level>   Minimum severity to report: error|warn|info (default: warn)
#   --no-style           Suppress INFO-level style checks
#   --suppress <ids>     Comma-separated check IDs to suppress
#   --json               Output results as JSON array
#   --help               Show this help

set selfDir [file dirname [file normalize [info script]]]

# Load library modules
foreach lib {
    lib/builtins.tcl
    lib/parser.tcl
    lib/scope.tcl
    lib/dynvar.tcl
    lib/imports.tcl
    lib/checks/syntax.tcl
    lib/checks/variables.tcl
    lib/checks/procs.tcl
    lib/checks/expressions.tcl
    lib/checks/style.tcl
} {
    source [file join $selfDir $lib]
}

# ------------------------------------------------------------------
# CLI parsing
# ------------------------------------------------------------------

proc parseArgs {argv} {
    set opts {
        severity warn
        noStyle  0
        suppress {}
        json     0
        dirs     {}
        files    {}
    }

    set i 0
    while {$i < [llength $argv]} {
        set arg [lindex $argv $i]
        switch -- $arg {
            --help {
                puts [helpText]
                exit 0
            }
            --dir {
                incr i
                dict lappend opts dirs [lindex $argv $i]
            }
            --severity {
                incr i
                dict set opts severity [lindex $argv $i]
            }
            --no-style {
                dict set opts noStyle 1
            }
            --suppress {
                incr i
                dict set opts suppress [split [lindex $argv $i] ","]
            }
            --json {
                dict set opts json 1
            }
            default {
                if {[string match "--*" $arg]} {
                    puts stderr "Unknown option: $arg"
                    exit 1
                }
                dict lappend opts files $arg
            }
        }
        incr i
    }
    return $opts
}

proc helpText {} {
    return {TCL Syntax Checker
Usage: tclsh tclcheck.tcl [options] file1.tcl ?file2.tcl ...?

Options:
  --dir <path>         Check all .tcl files in directory recursively
  --severity <level>   Minimum severity: error|warn|info (default: warn)
  --no-style           Suppress INFO-level style checks
  --suppress <ids>     Comma-separated check IDs to suppress
  --json               Output results as JSON array
  --help               Show this help}
}

# ------------------------------------------------------------------
# File collection
# ------------------------------------------------------------------

proc collectFiles {opts} {
    set files [dict get $opts files]
    foreach dir [dict get $opts dirs] {
        lappend files {*}[glob -nocomplain -directory $dir -type f *.tcl]
        # Recurse into subdirs
        foreach sub [glob -nocomplain -directory $dir -type d *] {
            lappend files {*}[collectFilesInDir $sub]
        }
    }
    return $files
}

proc collectFilesInDir {dir} {
    set result {}
    foreach f [glob -nocomplain -directory $dir -type f *.tcl] {
        lappend result $f
    }
    foreach sub [glob -nocomplain -directory $dir -type d *] {
        lappend result {*}[collectFilesInDir $sub]
    }
    return $result
}

# ------------------------------------------------------------------
# First pass: definition collection
# ------------------------------------------------------------------

proc firstPass {files issuesVar} {
    upvar 1 $issuesVar issues
    foreach filename $files {
        if {![file readable $filename]} {
            lappend issues [list $filename 0 ERROR syntax "Cannot read file"]
            continue
        }
        set fh [open $filename r]
        set src [read $fh]
        close $fh
        collectDefinitions $src $filename issues
    }
}

# Walk a script collecting proc/namespace/package definitions.
proc collectDefinitions {src filename issuesVar {baseLine 1}} {
    upvar 1 $issuesVar issues
    set cmds [::tclcheck::parser::parseScript $src $filename $baseLine issues]

    foreach cmdRecord $cmds {
        lassign $cmdRecord lineNum words
        if {[llength $words] == 0} continue
        set cmd [lindex $words 0]

        switch -- $cmd {
            proc {
                if {[llength $words] == 4} {
                    set name [lindex $words 1]
                    set argList [lindex $words 2]
                    set qualName [::tclcheck::scope::qualifyName $name]
                    ::tclcheck::checks::procs::registerProc \
                        $qualName $filename $lineNum $argList
                }
            }
            namespace {
                if {[llength $words] >= 3 &&
                    [lindex $words 1] eq "eval"} {
                    set ns [lindex $words 2]
                    ::tclcheck::scope::enterNamespace $ns
                    if {[llength $words] >= 4} {
                        set body [lindex $words 3]
                        if {[::tclcheck::parser::isBraceWord $body]} {
                            set inner [::tclcheck::parser::stripBraces $body]
                            collectDefinitions $inner $filename issues $lineNum
                        }
                    }
                    ::tclcheck::scope::leaveNamespace
                }
            }
            package {
                if {[llength $words] >= 3 &&
                    [lindex $words 1] eq "provide"} {
                    set pkg [lindex $words 2]
                    set ver [expr {[llength $words] >= 4 ? [lindex $words 3] : "0"}]
                    ::tclcheck::imports::registerPackage $pkg $ver $filename
                }
            }
            source {
                if {[llength $words] >= 2} {
                    set path [lindex $words 1]
                    # Strip quotes if present
                    if {[::tclcheck::parser::isQuotedWord $path]} {
                        set path [::tclcheck::parser::stripQuotes $path]
                    }
                    if {[::tclcheck::parser::isDynamic $path] ||
                        [string first "\[" $path] >= 0 ||
                        [string first "\$" $path] >= 0} {
                        continue
                    }
                    set baseDir [file dirname $filename]
                    lassign [::tclcheck::imports::resolveSource \
                        $path $baseDir $filename $lineNum] resolved err
                    if {$err ne ""} {
                        lappend issues $err
                    } elseif {$resolved ne "" &&
                              $resolved ni $::_processedFirstPass} {
                        lappend ::_processedFirstPass $resolved
                        set fh2 [open $resolved r]
                        set src2 [read $fh2]
                        close $fh2
                        collectDefinitions $src2 $resolved issues 1
                    }
                }
            }
        }
    }
}

# ------------------------------------------------------------------
# Second pass: analysis
# ------------------------------------------------------------------

proc secondPass {files opts issuesVar} {
    upvar 1 $issuesVar issues
    set suppressed [dict get $opts suppress]
    set noStyle    [dict get $opts noStyle]

    foreach filename $files {
        if {![file readable $filename]} continue
        set fh [open $filename r]
        set src [read $fh]
        close $fh

        # Syntax checks (raw text)
        set syntaxIssues [::tclcheck::checks::syntax::check $src $filename]
        lappend issues {*}$syntaxIssues

        # Stop further analysis if structural errors found
        set hasErrors 0
        foreach iss $syntaxIssues {
            if {[lindex $iss 2] eq "ERROR"} { set hasErrors 1; break }
        }
        if {$hasErrors} continue

        # Parse and analyze
        ::tclcheck::scope::reset
        ::tclcheck::scope::push global "::" $filename 1

        set cmds [::tclcheck::parser::parseScript $src $filename 1 issues]
        analyzeCommands $cmds $filename $src issues
        set frame [::tclcheck::scope::pop]

        # Harvest unused globals
        lappend issues {*}[::tclcheck::checks::variables::harvestUnused \
            $frame $filename]
    }

    # Resolve deferred proc calls
    lappend issues {*}[::tclcheck::checks::procs::resolvePendingCalls]
}

# Recursive command analyzer
proc analyzeCommands {cmds filename src issuesVar} {
    upvar 1 $issuesVar issues

    foreach cmdRecord $cmds {
        lassign $cmdRecord lineNum words
        if {[llength $words] == 0} continue
        set cmd [lindex $words 0]

        # Check for ##tclcheck:ignore annotation in last word
        if {[string match "*##tclcheck:ignore*" [lindex $words end]]} continue

        # Dispatch to check modules
        lappend issues {*}[::tclcheck::checks::procs::processCmd \
            $lineNum $words $filename]
        lappend issues {*}[::tclcheck::checks::variables::processCmd \
            $lineNum $words $filename]
        lappend issues {*}[::tclcheck::checks::expressions::processCmd \
            $lineNum $words $filename]
        lappend issues {*}[::tclcheck::checks::style::processCmd \
            $lineNum $words $filename]

        # Analyze nested bracket command substitutions so checks also cover
        # commands like: set x [expr ...] or if {[catch ...]} { ... }
        lappend issues {*}[_analyzeNestedSubcommands $lineNum $words $filename issues]

        # Handle scope-creating commands
        switch -- $cmd {
            proc {
                if {[llength $words] == 4} {
                    _analyzeProcBody $lineNum $words $filename issues
                }
            }
            namespace {
                if {[llength $words] >= 3 && [lindex $words 1] eq "eval"} {
                    _analyzeNamespaceBody $lineNum $words $filename issues
                } elseif {[llength $words] >= 3 && [lindex $words 1] eq "import"} {
                    set pattern [lindex $words end]
                    if {![::tclcheck::parser::isDynamic $pattern]} {
                        set iss [::tclcheck::imports::checkNamespaceImport \
                            $pattern $filename $lineNum]
                        if {$iss ne ""} { lappend issues $iss }
                    }
                }
            }
            source {
                _analyzeSource $lineNum $words $filename issues
            }
            package {
                _analyzePackage $lineNum $words $filename issues
            }
            if - elseif {
                _analyzeIfChain $lineNum $words $filename issues
            }
            for - while - foreach {
                _analyzeLoop $lineNum $words $filename issues
            }
            catch {
                _analyzeCatch $lineNum $words $filename issues
            }
            try {
                _analyzeTry $lineNum $words $filename issues
            }
        }
    }
}

proc _analyzeNestedSubcommands {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    set nestedIssues {}

    foreach word [lrange $words 1 end] {
        set inner ""
        if {[::tclcheck::parser::isBracketWord $word]} {
            set inner [string range $word 1 end-1]
        } elseif {[::tclcheck::parser::isBraceWord $word]} {
            set maybe [::tclcheck::parser::stripBraces $word]
            if {$maybe ne "" && [string index $maybe 0] eq "\[" &&
                [string index $maybe end] eq "\]"} {
                set inner [string range $maybe 1 end-1]
            }
        }

        if {$inner eq ""} { continue }

        set subCmds [::tclcheck::parser::parseScript $inner $filename $lineNum issues]
        analyzeCommands $subCmds $filename $inner nestedIssues
    }

    return $nestedIssues
}

proc _analyzeProcBody {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    set procName [lindex $words 1]
    set argList  [lindex $words 2]
    set body     [lindex $words 3]

    if {![::tclcheck::parser::isBraceWord $body]} { return }

    set qualName [::tclcheck::scope::qualifyName $procName]
    ::tclcheck::scope::push proc $qualName $filename $lineNum

    # Pre-populate args
    set parsedArgs {}
    if {[::tclcheck::parser::isBraceWord $argList]} {
        if {![catch {
            set parsedArgs [lrange [::tclcheck::parser::stripBraces $argList] 0 end]
        }]} {
            # Parsed normally.
        } else {
            set parsedArgs {}
        }
    } else {
        set parsedArgs [list $argList]
    }
    ::tclcheck::scope::defineArgs $parsedArgs $lineNum

    set innerSrc [::tclcheck::parser::stripBraces $body]
    set innerCmds [::tclcheck::parser::parseScript $innerSrc $filename $lineNum issues]
    analyzeCommands $innerCmds $filename $innerSrc issues

    set frame [::tclcheck::scope::pop]
    lappend issues {*}[::tclcheck::checks::variables::harvestUnused $frame $filename]
}

proc _analyzeNamespaceBody {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    set ns   [lindex $words 2]
    set body [lindex $words end]
    if {![::tclcheck::parser::isBraceWord $body]} { return }

    ::tclcheck::scope::enterNamespace $ns
    ::tclcheck::scope::push namespace $ns $filename $lineNum

    set innerSrc [::tclcheck::parser::stripBraces $body]
    set innerCmds [::tclcheck::parser::parseScript $innerSrc $filename $lineNum issues]
    analyzeCommands $innerCmds $filename $innerSrc issues

    set frame [::tclcheck::scope::pop]
    ::tclcheck::scope::leaveNamespace
}

proc _analyzeSource {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    if {[llength $words] < 2} { return }
    set path [lindex $words 1]
    if {[::tclcheck::parser::isQuotedWord $path]} {
        set path [::tclcheck::parser::stripQuotes $path]
    }
    if {[::tclcheck::parser::isDynamic $path] ||
        [string first "\[" $path] >= 0 ||
        [string first "\$" $path] >= 0} { return }

    set baseDir [file dirname $filename]
    lassign [::tclcheck::imports::resolveSource \
        $path $baseDir $filename $lineNum] resolved err
    if {$err ne ""} {
        lappend issues $err
        return
    }

    # Duplicate source warning
    set dupIssue [::tclcheck::imports::checkDuplicateSource \
        $resolved $filename $lineNum]
    if {$dupIssue ne ""} { lappend issues $dupIssue; return }

    # Recurse into sourced file
    set fh [open $resolved r]
    set src [read $fh]
    close $fh
    ::tclcheck::imports::addSourceEdge $filename $resolved
    set srcCmds [::tclcheck::parser::parseScript $src $resolved 1 issues]
    analyzeCommands $srcCmds $resolved $src issues
}

proc _analyzePackage {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    if {[llength $words] < 3} { return }
    if {[lindex $words 1] eq "require"} {
        set pkgName [lindex $words 2]
        set iss [::tclcheck::imports::checkPackageRequire \
            $pkgName $filename $lineNum]
        if {$iss ne ""} { lappend issues $iss }
    }
    if {[lindex $words 1] eq "import" || [lindex $words 1] eq "namespace"} {
        # handled separately via namespace import
    }
}

proc _analyzeIfChain {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    # if {cond} {body} ?elseif {cond} {body}? ?else {body}?
    set i 1
    while {$i < [llength $words]} {
        set kw [lindex $words $i]
        if {$kw eq "else"} {
            incr i
            set body [lindex $words $i]
            if {[::tclcheck::parser::isBraceWord $body]} {
                _analyzeBody $body $filename $lineNum issues
            }
            incr i
        } elseif {$kw eq "elseif"} {
            incr i 2 ;# skip condition
            set body [lindex $words $i]
            if {[::tclcheck::parser::isBraceWord $body]} {
                _analyzeBody $body $filename $lineNum issues
            }
            incr i
        } else {
            # condition is at $i, body at $i+1
            set body [lindex $words [expr {$i+1}]]
            if {[::tclcheck::parser::isBraceWord $body]} {
                _analyzeBody $body $filename $lineNum issues
            }
            incr i 2
        }
    }
}

proc _analyzeLoop {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    set cmd [lindex $words 0]
    set body [lindex $words end]
    if {[::tclcheck::parser::isBraceWord $body]} {
        _analyzeBody $body $filename $lineNum issues
    }
}

proc _analyzeCatch {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    set body [lindex $words 1]
    if {[::tclcheck::parser::isBraceWord $body]} {
        _analyzeBody $body $filename $lineNum issues
    }
}

proc _analyzeTry {lineNum words filename issuesVar} {
    upvar 1 $issuesVar issues
    foreach word $words {
        if {[::tclcheck::parser::isBraceWord $word]} {
            _analyzeBody $word $filename $lineNum issues
        }
    }
}

proc _analyzeBody {bodyWord filename lineNum issuesVar} {
    upvar 1 $issuesVar issues
    set innerSrc [::tclcheck::parser::stripBraces $bodyWord]
    set innerCmds [::tclcheck::parser::parseScript $innerSrc $filename $lineNum issues]
    analyzeCommands $innerCmds $filename $innerSrc issues
}

# ------------------------------------------------------------------
# Output
# ------------------------------------------------------------------

proc severityRank {s} {
    switch -- [string toupper $s] {
        ERROR { return 3 }
        WARN  { return 2 }
        INFO  { return 1 }
        default { return 0 }
    }
}

proc filterIssues {issues opts} {
    set minRank [severityRank [dict get $opts severity]]
    set suppressed [dict get $opts suppress]
    set noStyle [dict get $opts noStyle]

    # Suppress cascade diagnostics on lines already known to have syntax errors.
    set syntaxErrLines {}
    foreach iss $issues {
        lassign $iss file line sev checkId msg
        if {$checkId eq "syntax" && $sev eq "ERROR"} {
            dict set syntaxErrLines "$file:$line" 1
        }
    }

    set result {}
    foreach iss $issues {
        lassign $iss file line sev checkId msg
        if {[severityRank $sev] < $minRank} continue
        if {$noStyle && $checkId eq "style"} continue
        if {$checkId in $suppressed} continue

        if {$checkId ne "syntax" && [dict exists $syntaxErrLines "$file:$line"]} {
            continue
        }

        lappend result $iss
    }
    return $result
}

proc sortIssues {issues} {
    return [lsort -index 0 -ascii [lsort -index 1 -integer $issues]]
}

proc printText {issues} {
    foreach iss $issues {
        lassign $iss file line sev checkId msg
        puts "$file:$line: \[$sev\] ($checkId) $msg"
    }
}

proc printJson {issues} {
    set arr {}
    foreach iss $issues {
        lassign $iss file line sev checkId msg
        # Escape JSON string values
        set msg [string map {\\ \\\\ \" \\\"} $msg]
        set file [string map {\\ \\\\ \" \\\"} $file]
        lappend arr "  {\"file\":\"$file\",\"line\":$line,\"severity\":\"$sev\",\"check\":\"$checkId\",\"message\":\"$msg\"}"
    }
    puts "\[[join $arr ",\n"]\]"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

proc main {argv} {
    set opts [parseArgs $argv]
    set files [collectFiles $opts]

    if {[llength $files] == 0} {
        puts stderr "No TCL files specified."
        puts stderr [helpText]
        exit 1
    }

    set issues {}
    set ::_processedFirstPass {}

    # Initialise modules
    ::tclcheck::imports::reset
    ::tclcheck::checks::procs::reset

    # First pass: collect all definitions
    ::tclcheck::scope::reset
    ::tclcheck::scope::push global "::" "" 0
    firstPass $files issues
    ::tclcheck::scope::pop

    # Reset scope for second pass
    ::tclcheck::scope::reset

    # Second pass: analysis
    secondPass $files $opts issues

    # Filter, sort, and output
    set filtered [filterIssues $issues $opts]
    set sorted   [sortIssues $filtered]

    if {[dict get $opts json]} {
        printJson $sorted
    } else {
        printText $sorted
    }

    # Exit code: 1 if any ERRORs or WARNs
    foreach iss $sorted {
        if {[lindex $iss 2] in {ERROR WARN}} { exit 1 }
    }
    exit 0
}

main $argv
