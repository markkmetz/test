# t_style.tcl — Style advisory checks: expect INFO

# switch with no default clause
proc noDefault {x} {
    switch -- $x {
        a { return 1 }
        b { return 2 }
    }
}                                ;##EXPECT: INFO:style

# catch without result variable
proc bareCtach {} {
    catch {expr {1/0}}            ;##EXPECT: INFO:style
}

# Line longer than 120 characters — the next line is intentionally over 120 chars
set longLine "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;##EXPECT: INFO:style

# switch WITH default — no warning
proc withDefault {x} {
    switch -- $x {
        a { return 1 }
        default { return 0 }
    }
}

# catch WITH result var — no warning
proc catchWithVar {} {
    catch {expr {1/0}} result
    return $result
}
