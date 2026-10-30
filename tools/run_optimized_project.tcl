# Keep the historical entry point, but use the same stage/artifact/timing gates
# as the closeout build. TD "bitgen Success" alone does not imply timing passed.
source [file join [file dirname [info script]] run_closeout_project.tcl]
