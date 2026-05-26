# t_third_party_regex_ok.tcl
# Regression test from third_party-style regex parsing in command substitutions.
# This should not produce syntax or expression errors.

set sample "x.tcl:42: [ERROR] (syntax) sample message"
set file ""
set line ""
set sev ""
set check ""
set msg ""

if {[regexp {^(.+):(\d+): \[(\w+)\] \((\w[^)]*)\) (.+)$} $sample \
        -> file line sev check msg]} {
    puts "$file:$line $sev $check $msg"
}

set haystack "##EXPECT:"
if {[string first "##EXPECT:" [string cat $haystack]] >= 0} {
    set ok 1
}
