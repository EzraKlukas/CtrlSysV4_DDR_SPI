# Convert the implemented Vivado bitstream to a Red Pitaya-friendly .bit.bin.
# This script is self-locating and does not depend on Vivado's current directory.

set script_dir [file normalize [file dirname [info script]]]
set source_dir [file normalize [file join $script_dir ".."]]
set repo_root  [file normalize [file join $source_dir ".."]]
set project_dir [file normalize [file join $repo_root "Vivado_CtrlSysV4"]]
set work_dir   [file normalize [file join $repo_root "build"]]

proc newest_file { files } {
    set newest ""
    set newest_mtime -1

    foreach file $files {
        set mtime [file mtime $file]
        if {$mtime > $newest_mtime} {
            set newest $file
            set newest_mtime $mtime
        }
    }

    return $newest
}

proc find_bitstream { project_dir } {
    set bit_files {}
    set repo_root [file dirname $project_dir]
    set build_bit [file normalize [file join $repo_root "build" "design_1_wrapper.bit"]]

    if {[file exists $build_bit]} {
        lappend bit_files $build_bit
    }

    if {[llength [info commands get_runs]] > 0} {
        if {[catch {get_runs -quiet impl_1} runs]} {
            set runs {}
        }
        if {[llength $runs] == 0} {
            if {[catch {get_runs -quiet impl_*} runs]} {
                set runs {}
            }
        }

        foreach run $runs {
            set run_dir [get_property DIRECTORY $run]
            if {$run_dir ne "" && [file isdirectory $run_dir]} {
                set bit_files [concat $bit_files [glob -nocomplain -directory $run_dir *.bit]]
            }
        }
    }

    if {[llength $bit_files] == 0 && [llength [info commands current_project]] > 0} {
        if {[catch {current_project -quiet} project]} {
            set project ""
        }
        if {$project ne ""} {
            set project_dir [get_property DIRECTORY $project]
            set bit_files [glob -nocomplain [file join $project_dir "*.runs" "impl_*" "*.bit"]]
        }
    }

    if {[llength $bit_files] == 0} {
        set bit_files [glob -nocomplain [file join $project_dir "*.runs" "impl_*" "*.bit"]]
    }

    return [newest_file $bit_files]
}

proc find_bootgen {} {
    set bootgen [auto_execok bootgen]
    if {$bootgen ne ""} {
        return $bootgen
    }

    set vivado_bin [file dirname [info nameofexecutable]]
    foreach candidate [list \
        [file join $vivado_bin bootgen] \
        [file join $vivado_bin bootgen.exe] \
        [file join $vivado_bin bootgen.bat]] {
        if {[file executable $candidate]} {
            return [list $candidate]
        }
    }

    error "Could not find bootgen. Run this from the Vivado Tcl console, or add bootgen to PATH."
}

set bit_src [find_bitstream $project_dir]
if {$bit_src eq ""} {
    error "Could not find an implemented .bit file. Run implementation/bitstream generation first."
}

file mkdir $work_dir

set bit_name [file tail $bit_src]
set bit_base [file rootname $bit_name]
set bit_dst  [file normalize [file join $work_dir $bit_name]]
set bif_path [file normalize [file join $work_dir "${bit_base}.bif"]]
set bin_path [file normalize [file join $work_dir "${bit_name}.bin"]]

if {[file normalize $bit_src] ne $bit_dst} {
    file copy -force $bit_src $bit_dst
}
file delete -force $bin_path

set fp [open $bif_path w]
puts $fp "all:"
puts $fp "{"
puts $fp "  $bit_name"
puts $fp "}"
close $fp

set old_dir [pwd]
cd $work_dir
set bootgen [find_bootgen]
set bootgen_status [catch {
    exec {*}$bootgen -image $bif_path -arch zynq -process_bitstream bin -o $bin_path -w
} bootgen_result]
cd $old_dir

if {$bootgen_status != 0} {
    error "bootgen failed: $bootgen_result"
}

if {![file exists $bin_path]} {
    error "bootgen completed but did not create expected output: $bin_path"
}

puts "Bitstream source: $bit_src"
puts "Copied bitstream: $bit_dst"
puts "Generated bin:    $bin_path"
puts "Generated mtime:  [clock format [file mtime $bin_path]]"
