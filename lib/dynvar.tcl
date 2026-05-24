# dynvar.tcl — Dynamic variable detection and classification
# Classifies `set` target words into static / partial-dynamic / fully-dynamic
# and provides helpers used by the variable checker.

namespace eval ::tclcheck::dynvar {

    # ------------------------------------------------------------------
    # Classification
    # ------------------------------------------------------------------

    # Classify the name-word of a `set` command.
    # Returns one of: static | partial | full
    #   static  — plain identifier, e.g.  myVar  arr(key)
    #   partial — has embedded $ but a static prefix, e.g.  var$letter  arr($i)
    #   full    — starts with $ or [, name entirely dynamic
    proc classify {nameWord} {
        # Fully dynamic: starts with $ or [
        set first [string index $nameWord 0]
        if {$first eq "\$" || $first eq "\["} {
            return full
        }
        # Strip array suffix for prefix check: name(...)
        set base $nameWord
        regexp {^([^(]+)} $nameWord -> base

        # Partial: embedded $ in the base
        if {[string first "\$" $base] >= 0} {
            return partial
        }
        return static
    }

    # Extract the static prefix from a partial-dynamic name word.
    # e.g. "var$letter"  -> "var"
    #      "prefix_$i"   -> "prefix_"
    #      "arr($key)"   -> ""  (array, key is dynamic — prefix is array name)
    proc staticPrefix {nameWord} {
        # Array element with dynamic key: arr($key) -> prefix is the array name
        if {[regexp {^([^(]+)\(\$} $nameWord -> arrname]} {
            return $arrname
        }
        # Plain partial: var$x -> var
        set dollarPos [string first "\$" $nameWord]
        if {$dollarPos > 0} {
            return [string range $nameWord 0 [expr {$dollarPos - 1}]]
        }
        return ""
    }

    # Check if a variable reference ($varname) might be satisfied by
    # any of the dynamic prefixes registered in the scope.
    proc coveredByPrefix {varname prefixes} {
        foreach prefix $prefixes {
            if {$prefix eq ""} { return 1 }
            if {[string match "${prefix}*" $varname]} { return 1 }
        }
        return 0
    }

    # ------------------------------------------------------------------
    # Variable reference parsing helpers
    # ------------------------------------------------------------------

    # Return list of all bare variable names referenced via $ in a word.
    # Skips DYNAMIC entries where the name itself is substituted.
    proc listStaticRefs {word} {
        set refs {}
        set pairs [::tclcheck::parser::extractVarRefs $word]
        foreach pair $pairs {
            lassign $pair varname isDyn
            if {!$isDyn && $varname ne "DYNAMIC" && $varname ne ""} {
                lappend refs $varname
            }
        }
        return $refs
    }

    # Return list of all dynamic (fully or partially) variable refs in a word.
    proc listDynamicRefs {word} {
        set refs {}
        set pairs [::tclcheck::parser::extractVarRefs $word]
        foreach pair $pairs {
            lassign $pair varname isDyn
            if {$isDyn} { lappend refs $varname }
        }
        return $refs
    }

    # ------------------------------------------------------------------
    # Annotation detection
    # ------------------------------------------------------------------

    # Look for suppression annotations in a comment word or a full line.
    # Supported tags:
    #   ##dynvar:suppress     — suppress dynamic-var INFO in this scope
    #   ##tclcheck:ignore     — suppress all checks on this line
    proc parseSuppressTag {commentText} {
        set tags {}
        if {[regexp {##dynvar:suppress} $commentText]} {
            lappend tags dynvar-suppress
        }
        if {[regexp {##tclcheck:ignore} $commentText]} {
            lappend tags tclcheck-ignore
        }
        return $tags
    }
}
