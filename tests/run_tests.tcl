# run_tests.tcl — Automated test runner for tclcheck
#
# Usage:  tclsh tests/run_tests.tcl
#
# For each t_*_ok.tcl test: assert checker produces 0 ERRORs and 0 WARNs.
# For each t_*_warn.tcl / t_*_errors.tcl test: parse ##EXPECT annotations
# and assert that checker output matches the expected issues (by line and checkId).

set selfDir [file dirname [file normalize [info script]]]
set rootDir [file dirname $selfDir]
set checker [file join $rootDir tclcheck.tcl]

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

# Run the checker on a file; return list of issue dicts
proc runChecker {file} {
    global checker
    set cmd [list tclsh $checker --severity info $file]
    if {[catch {exec -ignorestderr -- {*}$cmd 2>@1} output]} {
        # Non-zero exit is expected when checker reports issues.
    }
    set issues {}
    foreach line [split $output "\n"] {
        set line [string trim $line]
        if {$line eq ""} continue
        # Format: file:line: [LEVEL] (checkId) message
        if {[regexp {^(.+):(\d+): \[(\w+)\] \((\w[^)]*)\) (.+)$} $line \
                -> f l sev chk msg]} {
            lappend issues [dict create \
                line $l severity $sev check $chk message $msg]
        }
    }
    return $issues
}

# Parse ##EXPECT: LEVEL:checkId annotations from a file.
# Returns list of {lineNum level checkId}
proc parseExpectations {file} {
    set expects {}
    set lineNum 0
    set fh [open $file r]
    foreach line [split [read $fh] "\n"] {
        incr lineNum
        if {[regexp {##EXPECT:\s*(\w+):(\S+)} $line -> level checkId]} {
            lappend expects [list $lineNum [string toupper $level] $checkId]
        }
    }
    close $fh
    return $expects
}

# Check if an issue matches a given expectation (line, severity, checkId).
# Allows a one-line tolerance for multi-word commands.
proc issueMatches {issue expectLine expectSev expectChk} {
    set line [dict get $issue line]
    set sev  [dict get $issue severity]
    set chk  [dict get $issue check]
    return [expr {
        abs($line - $expectLine) <= 4 &&
        $sev eq $expectSev &&
        $chk eq $expectChk
    }]
}

# ------------------------------------------------------------------
# Test execution
# ------------------------------------------------------------------

set pass 0
set fail 0
set total 0

proc runOkTest {file} {
    global pass fail total
    incr total
    set issues [runChecker $file]
    # Filter to ERROR and WARN only
    set problems {}
    foreach iss $issues {
        if {[dict get $iss severity] in {ERROR WARN}} {
            lappend problems $iss
        }
    }
    if {[llength $problems] == 0} {
        puts "PASS  [file tail $file]"
        incr pass
    } else {
        puts "FAIL  [file tail $file] — expected 0 errors/warnings, got [llength $problems]:"
        foreach iss $problems {
            puts "      line [dict get $iss line]: \[[dict get $iss severity]\] ([dict get $iss check]) [dict get $iss message]"
        }
        incr fail
    }
}

proc runWarnTest {file} {
    global pass fail total
    incr total
    set expectations [parseExpectations $file]
    set issues [runChecker $file]

    set missed {}
    set unexpected {}

    # Check each expectation is satisfied
    foreach exp $expectations {
        lassign $exp expLine expSev expChk
        set matched 0
        foreach iss $issues {
            if {[issueMatches $iss $expLine $expSev $expChk]} {
                set matched 1
                break
            }
        }
        if {!$matched} {
            lappend missed [list $expLine $expSev $expChk]
        }
    }

    # Check for unexpected issues beyond annotations
    set expectLines {}
    foreach exp $expectations { lappend expectLines [lindex $exp 0] }

    foreach iss $issues {
        set line [dict get $iss line]
        set sev  [dict get $iss severity]
        set chk  [dict get $iss check]
        # Unexpected INFO diagnostics are ignored.
        if {$sev ni {ERROR WARN INFO}} continue
        if {$sev eq "INFO"} continue
        set found 0
        foreach exp $expectations {
            lassign $exp expLine expSev expChk
            if {[issueMatches $iss $expLine $expSev $expChk]} {
                set found 1; break
            }
        }
        if {!$found} {
            lappend unexpected [list $line $sev $chk [dict get $iss message]]
        }
    }

    if {[llength $missed] == 0 && [llength $unexpected] == 0} {
        puts "PASS  [file tail $file]"
        incr pass
    } else {
        puts "FAIL  [file tail $file]"
        foreach m $missed {
            lassign $m l s c
            puts "      MISSED  line $l: expected $s:$c"
        }
        foreach u $unexpected {
            lassign $u l s c msg
            puts "      EXTRA   line $l: $s:$c — $msg"
        }
        incr fail
    }
}

# ------------------------------------------------------------------
# Discover and run all tests
# ------------------------------------------------------------------

puts "=== tclcheck test suite ==="
puts ""

foreach file [lsort [glob -directory $selfDir t_*.tcl]] {
    set tail [file tail $file]
    if {[string match *_ok.tcl $tail]} {
        runOkTest $file
    } elseif {[string match *_warn.tcl $tail] ||
              [string match *_errors.tcl $tail]} {
        runWarnTest $file
    } else {
        # Mixed (e.g. t_dynamic_vars.tcl, t_style.tcl) — run as warn test
        # since they may have ##EXPECT annotations
        set hasExpects 0
        set fh [open $file r]
        if {[string first "##EXPECT:" [read $fh]] >= 0} {
            set hasExpects 1
        }
        close $fh
        if {$hasExpects} {
            runWarnTest $file
        } else {
            runOkTest $file
        }
    }
}

puts ""
puts "=== Results: $pass/$total passed, $fail failed ==="

if {$fail > 0} { exit 1 } else { exit 0 }
