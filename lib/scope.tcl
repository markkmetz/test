# scope.tcl — Scope stack and variable tracking
# Tracks variable definitions, global declarations, upvar mappings,
# and dynamic variable prefixes at each level of the scope stack.

namespace eval ::tclcheck::scope {

    # The scope stack is a list of dicts, innermost last.
    # Each frame dict keys:
    #   type        — global | proc | namespace
    #   name        — qualified name (proc or namespace)
    #   filename    — source file
    #   lineNum     — definition line
    #   vars        — dict: varname -> {definedLine usedCount}
    #   globalDecls — list of variable names declared via `global`
    #   upvarMap    — dict: localAlias -> {remoteName level dynamic}
    #   dynPrefixes — list of static prefixes from partial-dynamic sets
    #   fullyDyn    — bool: scope has fully-dynamic set
    #   arrayDynKeys— dict: arrayName -> 1 (array has dynamic key access)

    variable stack {}

    # ------------------------------------------------------------------
    # Stack management
    # ------------------------------------------------------------------

    proc push {type name filename lineNum} {
        variable stack
        lappend stack [dict create \
            type        $type   \
            name        $name   \
            filename    $filename \
            lineNum     $lineNum  \
            vars        {}        \
            globalDecls {}        \
            upvarMap    {}        \
            dynPrefixes {}        \
            fullyDyn    0         \
            arrayDynKeys {}       \
        ]
    }

    proc pop {} {
        variable stack
        if {[llength $stack] == 0} { error "Scope stack underflow" }
        set frame [lindex $stack end]
        set stack [lrange $stack 0 end-1]
        return $frame
    }

    proc depth {} {
        variable stack
        return [llength $stack]
    }

    proc current {} {
        variable stack
        return [lindex $stack end]
    }

    proc currentType {} {
        return [dict get [current] type]
    }

    proc currentName {} {
        return [dict get [current] name]
    }

    # ------------------------------------------------------------------
    # Variable definition
    # ------------------------------------------------------------------

    # Record that varname is defined at lineNum in the current scope.
    proc define {varname lineNum} {
        variable stack
        set frame [lindex $stack end]
        dict set frame vars $varname [list $lineNum 0]
        lset stack end $frame
    }

    # Pre-populate a proc scope with its argument names.
    proc defineArgs {argList lineNum} {
        foreach arg $argList {
            # Handle {argname default} pairs
            if {[llength $arg] >= 1} {
                define [lindex $arg 0] $lineNum
            }
        }
        # `args` is implicitly defined if present as last arg
    }

    # Record a `global` declaration in current scope.
    proc declareGlobal {varname} {
        variable stack
        set frame [lindex $stack end]
        dict lappend frame globalDecls $varname
        # Also mark as defined in current scope
        dict set frame vars $varname [list 0 0]
        lset stack end $frame
    }

    # Record an `upvar` mapping: localAlias -> remote
    proc defineUpvar {localAlias remoteName level isDynamic} {
        variable stack
        set frame [lindex $stack end]
        dict set frame upvarMap $localAlias [list $remoteName $level $isDynamic]
        # treat as defined
        dict set frame vars $localAlias [list 0 0]
        lset stack end $frame
    }

    # Record a `variable` declaration (namespace scope)
    proc declareNamespaceVar {varname lineNum} {
        define $varname $lineNum
    }

    # ------------------------------------------------------------------
    # Dynamic variable tracking
    # ------------------------------------------------------------------

    # Partial-dynamic: set var$x $val → prefix is "var"
    proc addDynPrefix {prefix} {
        variable stack
        set frame [lindex $stack end]
        set prefixes [dict get $frame dynPrefixes]
        if {$prefix ni $prefixes} {
            lappend prefixes $prefix
            dict set frame dynPrefixes $prefixes
        }
        lset stack end $frame
    }

    # Fully-dynamic: set $varname $val
    proc setFullyDynamic {} {
        variable stack
        set frame [lindex $stack end]
        dict set frame fullyDyn 1
        lset stack end $frame
    }

    proc isFullyDynamic {} {
        return [dict get [current] fullyDyn]
    }

    # Record that an array has dynamic key access
    proc setArrayDynKey {arrayName} {
        variable stack
        set frame [lindex $stack end]
        dict set frame arrayDynKeys $arrayName 1
        lset stack end $frame
    }

    # ------------------------------------------------------------------
    # Variable lookup
    # ------------------------------------------------------------------

    # Mark a variable as used (increment use count).
    proc markUsed {varname} {
        variable stack
        # Walk stack from innermost outward
        for {set idx [expr {[llength $stack]-1}]} {$idx >= 0} {incr idx -1} {
            set frame [lindex $stack $idx]
            if {[dict exists [dict get $frame vars] $varname]} {
                set entry [dict get [dict get $frame vars] $varname]
                set cnt [lindex $entry 1]
                incr cnt
                dict set frame vars $varname [list [lindex $entry 0] $cnt]
                lset stack $idx $frame
                return 1
            }
        }
        return 0
    }

    # Check if varname is defined in current scope or any enclosing scope.
    # Returns: defined | global_needed | undefined
    proc lookup {varname} {
        variable stack
        set innermost 1
        for {set idx [expr {[llength $stack]-1}]} {$idx >= 0} {incr idx -1} {
            set frame [lindex $stack $idx]

            # Check fully-dynamic — suppress all warnings in this scope
            if {[dict get $frame fullyDyn]} { return "defined" }

            # Check partial-dynamic prefixes
            foreach prefix [dict get $frame dynPrefixes] {
                if {$prefix eq "" || [string match "${prefix}*" $varname]} {
                    return "defined"
                }
            }

            # Check upvar mappings
            if {[dict exists [dict get $frame upvarMap] $varname]} {
                return "defined"
            }

            # Check local vars
            if {[dict exists [dict get $frame vars] $varname]} {
                return "defined"
            }

            # Check global declarations in this frame
            if {$varname in [dict get $frame globalDecls]} {
                return "defined"
            }

            # If we're in a proc scope (not global), don't look further
            # unless the variable is declared global
            if {$innermost && [dict get $frame type] eq "proc"} {
                # Not found locally; check if it exists at global scope
                set globalFrame [lindex $stack 0]
                if {[dict exists [dict get $globalFrame vars] $varname]} {
                    return "global_needed"
                }
                return "undefined"
            }
            set innermost 0
        }
        return "undefined"
    }

    # Check whether a varname matches a dynamic prefix in current scope
    proc matchesDynPrefix {varname} {
        set frame [current]
        foreach prefix [dict get $frame dynPrefixes] {
            if {$prefix eq "" || [string match "${prefix}*" $varname]} {
                return 1
            }
        }
        return 0
    }

    # Check array dynamic key suppression
    proc arrayHasDynKey {arrayName} {
        return [dict exists [dict get [current] arrayDynKeys] $arrayName]
    }

    # ------------------------------------------------------------------
    # Global scope helpers
    # ------------------------------------------------------------------

    # Define a variable at global scope (stack frame 0)
    proc defineGlobal {varname lineNum} {
        variable stack
        if {[llength $stack] == 0} { return }
        set frame [lindex $stack 0]
        dict set frame vars $varname [list $lineNum 0]
        lset stack 0 $frame
    }

    # Check if varname is known at global scope
    proc existsGlobal {varname} {
        variable stack
        if {[llength $stack] == 0} { return 0 }
        set frame [lindex $stack 0]
        return [dict exists [dict get $frame vars] $varname]
    }

    # ------------------------------------------------------------------
    # Unused variable harvesting (called on scope pop)
    # ------------------------------------------------------------------

    # Returns list of {varname definedLine} for vars with usedCount == 0.
    # Excludes args (defined at line 0) and vars starting with _
    proc getUnusedVars {frame} {
        set unused {}
        dict for {varname entry} [dict get $frame vars] {
            lassign $entry defLine useCnt
            if {$defLine == 0} continue       ;# arg or global decl
            if {[string index $varname 0] eq "_"} continue
            if {$useCnt == 0} {
                lappend unused [list $varname $defLine]
            }
        }
        return $unused
    }

    # ------------------------------------------------------------------
    # Namespace tracking
    # ------------------------------------------------------------------

    variable currentNamespace "::"
    variable namespaceStack {"::"}

    proc enterNamespace {ns} {
        variable currentNamespace
        variable namespaceStack
        # Resolve relative to current
        if {[string match "::*" $ns]} {
            set currentNamespace $ns
        } else {
            set currentNamespace "${currentNamespace}::${ns}"
        }
        lappend namespaceStack $currentNamespace
    }

    proc leaveNamespace {} {
        variable currentNamespace
        variable namespaceStack
        if {[llength $namespaceStack] > 1} {
            set namespaceStack [lrange $namespaceStack 0 end-1]
            set currentNamespace [lindex $namespaceStack end]
        }
    }

    proc getNamespace {} {
        variable currentNamespace
        return $currentNamespace
    }

    # Qualify a proc name with current namespace
    proc qualifyName {name} {
        variable currentNamespace
        if {[string match "::*" $name]} { return $name }
        if {$currentNamespace eq "::"} {
            return "::$name"
        }
        return "${currentNamespace}::${name}"
    }

    # ------------------------------------------------------------------
    # Reset (call before each file analysis)
    # ------------------------------------------------------------------

    proc reset {} {
        variable stack {}
        variable currentNamespace "::"
        variable namespaceStack {"::"}
    }
}
