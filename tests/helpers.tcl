# tests/helpers.tcl — Helper procs used by t_imports_ok.tcl
# This file is sourced from t_imports_ok.tcl to test valid sourcing.

package provide testhelpers 1.0

namespace eval ::helpers {
    proc double {x} { return [expr {$x * 2}] }
    proc triple {x} { return [expr {$x * 3}] }
}
