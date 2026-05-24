# imports.tcl — Package and source dependency resolution
# Builds a dependency graph, detects circular sources, and validates
# package require / namespace import statements.

namespace eval ::tclcheck::imports {

    # Registry of provided packages: name -> {version filename}
    variable packageRegistry {}

    # Set of files already processed (cycle detection)
    variable processedFiles {}

    # Import graph: file -> list of sourced files
    variable importGraph {}

    # Known namespace exports: qualifiedProcName -> 1
    # Populated during first-pass collection
    variable knownProcs {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    proc reset {} {
        variable packageRegistry {}
        variable processedFiles {}
        variable importGraph {}
        variable knownProcs {}
    }

    # Register a `package provide` statement found during first pass
    proc registerPackage {name version filename} {
        variable packageRegistry
        dict set packageRegistry $name [list $version $filename]
    }

    # Register a known proc (fully qualified) found during first pass
    proc registerProc {qualName} {
        variable knownProcs
        dict set knownProcs $qualName 1
    }

    # Check `package require name ?version?`
    # Returns "" if OK, or an issue tuple
    proc checkPackageRequire {name filename lineNum} {
        variable packageRegistry
        # Known stdlib packages never need sourcing
        if {[::tclcheck::builtins::isKnownPackage $name]} {
            return ""
        }
        if {[dict exists $packageRegistry $name]} {
            return ""
        }
        return [list $filename $lineNum WARN import \
            "package require '$name': not found in provided packages or stdlib"]
    }

    # Resolve and validate a `source path` call.
    # baseDir is the directory containing the calling file.
    # Returns {resolvedPath ""} on success, {"" errorTuple} on failure.
    proc resolveSource {path baseDir filename lineNum} {
        variable processedFiles
        # Resolve relative path
        set resolved [file normalize [file join $baseDir $path]]
        if {![file exists $resolved]} {
            return [list "" [list $filename $lineNum ERROR import \
                "source '$path': file not found (resolved: $resolved)"]]
        }
        return [list $resolved ""]
    }

    # Check for circular source imports.
    # chain is the current ancestry chain (list of filenames).
    # Returns "" if no cycle, or an issue tuple.
    proc checkCircular {filename chain callerFile callerLine} {
        if {$filename in $chain} {
            set cycle [concat $chain [list $filename]]
            set cycleStr [join $cycle " -> "]
            return [list $callerFile $callerLine ERROR import \
                "Circular source dependency: $cycleStr"]
        }
        return ""
    }

    # Record a source edge in the import graph
    proc addSourceEdge {fromFile toFile} {
        variable importGraph
        if {![dict exists $importGraph $fromFile]} {
            dict set importGraph $fromFile {}
        }
        dict lappend importGraph $fromFile $toFile
    }

    # Check `namespace import ?-force? pattern`
    # pattern examples: ::myns::*  or  ::myns::cmdName
    proc checkNamespaceImport {pattern filename lineNum} {
        variable knownProcs
        # Strip leading -force flag
        if {[string match "-*" $pattern]} { return "" }
        # Wildcard — just verify the namespace prefix exists
        if {[string match "*::*" $pattern]} {
            set ns [regsub {::[^:]*$} $pattern ""]
            if {$ns ne "::" && $ns ne ""} {
                # Check if any known proc starts with this namespace
                set found 0
                dict for {proc _} $knownProcs {
                    if {[string match "${ns}::*" $proc]} {
                        set found 1
                        break
                    }
                }
                if {!$found} {
                    return [list $filename $lineNum WARN import \
                        "namespace import '$pattern': no procs found in namespace '$ns'"]
                }
            }
        } else {
            # Exact name
            set qualName "::$pattern"
            if {![dict exists $knownProcs $qualName] &&
                ![dict exists $knownProcs $pattern]} {
                return [list $filename $lineNum WARN import \
                    "namespace import '$pattern': proc not found in symbol table"]
            }
        }
        return ""
    }

    # Check that a `source`-referenced file is not already in the
    # processed set (duplicate source detection, warn only)
    proc checkDuplicateSource {resolved filename lineNum} {
        variable processedFiles
        if {$resolved in $processedFiles} {
            return [list $filename $lineNum WARN import \
                "source '$resolved': file sourced multiple times"]
        }
        lappend processedFiles $resolved
        return ""
    }

    # Mark a file as processed (add to set without duplicate check)
    proc markProcessed {filename} {
        variable processedFiles
        if {$filename ni $processedFiles} {
            lappend processedFiles $filename
        }
    }
}
