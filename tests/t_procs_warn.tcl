# t_procs_warn.tcl — Proc errors: expect specific ERROR/WARN

# Call to undefined proc
set x [nonExistentProc 1 2]    ;##EXPECT: WARN:procs

# Proc defined with wrong structure (2 args instead of 3)
proc badDef {a}                 ;##EXPECT: ERROR:procs

# Too few required args
proc requireTwo {a b} { return "$a $b" }
requireTwo "only_one"           ;##EXPECT: ERROR:procs

# Too many args to fixed-arity proc
proc fixedArity {x} { return $x }
fixedArity 1 2 3                ;##EXPECT: ERROR:procs

# return at global scope
return                          ;##EXPECT: WARN:procs

# Proc redefinition
proc dupProc {} { return 1 }
proc dupProc {} { return 2 }    ;##EXPECT: WARN:procs

# upvar with odd argument pairs
proc badUpvar {} {
    upvar 1 a b c               ;##EXPECT: ERROR:procs
}

# Built-in arg count: string length with 0 extra args (needs exactly 1)
string length                   ;##EXPECT: ERROR:builtins

# Built-in arg count: too many args to llength
llength {1 2 3} extra           ;##EXPECT: ERROR:builtins
