# t_imports_ok.tcl — Valid import patterns: expect ZERO errors/warnings

# Source a file that exists in the same directory
source ./helpers.tcl

# Use a proc from sourced file
set d [::helpers::double 5]
set t [::helpers::triple 5]

# Known stdlib package
package require Tcl 8.6

# namespace import from a namespace we defined via source
namespace import ::helpers::double
namespace import ::helpers::triple
