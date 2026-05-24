#!/usr/bin/env tclsh
# Minimal test to ensure adjacent bracket command substitutions are parsed
# as a single logical word.

set package_name "foo"
set package_name_cap [string toupper [string index $package_name 0]][string range $package_name 1 end]

# No EXPECT annotations — test runner treats this as an OK test (no WARN/ERROR expected)
