# t_imports_warn.tcl — Import issues: expect specific ERROR/WARN

# Source file that does not exist
source ./nonexistent_file.tcl    ;##EXPECT: ERROR:import

# Unknown third-party package
package require SomeUnknownLib 3.0   ;##EXPECT: WARN:import

# namespace import from unknown namespace
namespace import ::ghostNS::myCmd    ;##EXPECT: WARN:import
