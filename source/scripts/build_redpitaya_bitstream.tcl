# Rebuild the complete Red Pitaya FPGA image from canonical repository sources.
#
# This script performs the normal release path:
#   1. require a clean, committed Git state;
#   2. repackage user.org:user:ctrlsys_core:1.2 from source/hdl;
#   3. refresh/upgrade the project IP and regenerate block-design products;
#   4. run out-of-context IP synthesis, top synthesis, implementation, and
#      bitstream generation;
#   5. require non-negative routed setup and hold slack;
#   6. copy the .bit to build/deploy and convert it to .bit.bin with bootgen;
#   7. write a manifest tying the artifacts to the full Git commit.
#
# Typical invocation from the repository root:
#
#   source "$HOME/tools/amd/2026.1/Vivado/settings64.sh"
#   vivado -mode batch \
#       -source source/scripts/build_redpitaya_bitstream.tcl \
#       -tclargs -jobs 4
#
# The output filename is similar to:
#   build/deploy/ctrlsys-9cc49ebf7d29-z7020-125mhz.bit.bin

proc deployment_usage {} {
    puts "Usage:"
    puts "  vivado -mode batch -source build_redpitaya_bitstream.tcl -tclargs ?options?"
    puts ""
    puts "Options:"
    puts "  -project <path>       Vivado .xpr file."
    puts "                        Default: <repo>/Vivado_CtrlSysV5_2026_1/Vivado_CtrlSysV5_2026_1.xpr"
    puts "  -output_dir <path>    Deployment artifact directory."
    puts "                        Default: <repo>/build/deploy"
    puts "  -jobs <count>         Parallel Vivado jobs. Default: 4"
    puts "  -ip_version <ver>     ctrlsys_core VLNV version. Default: 1.2"
    puts "  -allow_dirty          Permit a dirty Git worktree and add '-dirty' to names."
    puts "  -skip_repackage       Reuse the existing packaged IP (for debugging only)."
    puts "  -help                  Show this message."
}

proc deployment_require_file {path label} {
    if {![file exists $path]} {
        error "$label does not exist: $path"
    }
}

proc deployment_parse_args {repo_root} {
    array set opts [list \
        project [file normalize [file join \
            $repo_root Vivado_CtrlSysV5_2026_1 Vivado_CtrlSysV5_2026_1.xpr]] \
        output_dir [file normalize [file join $repo_root build deploy]] \
        jobs 4 \
        ip_version 1.2 \
        allow_dirty 0 \
        skip_repackage 0]

    set args $::argv
    while {[llength $args] > 0} {
        set key [lindex $args 0]
        set args [lrange $args 1 end]

        switch -- $key {
            -help -
            --help {
                deployment_usage
                exit 0
            }
            -allow_dirty {
                set opts(allow_dirty) 1
            }
            -skip_repackage {
                set opts(skip_repackage) 1
            }
            -project -
            -output_dir -
            -jobs -
            -ip_version {
                if {[llength $args] == 0} {
                    error "$key requires a value"
                }
                set opts([string range $key 1 end]) [lindex $args 0]
                set args [lrange $args 1 end]
            }
            default {
                error "Unknown option '$key'. Use -help for usage."
            }
        }
    }

    if {![string is integer -strict $opts(jobs)] || $opts(jobs) < 1} {
        error "-jobs must be a positive integer"
    }

    set opts(project) [file normalize $opts(project)]
    set opts(output_dir) [file normalize $opts(output_dir)]
    return [array get opts]
}

proc deployment_git {repo_root args} {
    return [string trim [exec git -C $repo_root {*}$args]]
}

proc deployment_run_complete {run_name} {
    set run [get_runs -quiet $run_name]
    if {[llength $run] != 1} {
        error "Expected exactly one Vivado run named '$run_name'"
    }

    set status [get_property STATUS $run]
    set progress [get_property PROGRESS $run]
    puts "$run_name status: $status ($progress)"

    if {![string match "*Complete*" $status] || $progress ne "100%"} {
        error "$run_name did not complete successfully: $status ($progress)"
    }
}

proc deployment_find_bootgen {} {
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

    error "Could not find bootgen. Source the Vivado settings64.sh before running."
}

proc deployment_sha256 {path} {
    set sha_tool [auto_execok sha256sum]
    if {$sha_tool eq ""} {
        return "unavailable"
    }
    return [lindex [exec {*}$sha_tool $path] 0]
}

proc deployment_core_ips {expected_vlnv} {
    set matches {}
    foreach ip [get_ips -all -quiet] {
        if {[get_property VLNV $ip] eq $expected_vlnv} {
            lappend matches $ip
        }
    }
    return $matches
}

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set repo_root [file normalize [file join $script_dir ../..]]
array set opts [deployment_parse_args $repo_root]

set repackage_script [file normalize [file join $script_dir repackage_ctrlsys_core_ip.tcl]]
set ip_root [file normalize [file join $repo_root IP ctrlsys_core]]
set expected_vlnv "user.org:user:ctrlsys_core:$opts(ip_version)"

deployment_require_file $opts(project) "Vivado project"
deployment_require_file $repackage_script "IP-repackaging script"
deployment_require_file [file join $repo_root source hdl ctrlsys_core.sv] \
    "Canonical ctrlsys_core RTL"

set commit [deployment_git $repo_root rev-parse HEAD]
set short_commit [deployment_git $repo_root rev-parse --short=12 HEAD]
set branch [deployment_git $repo_root branch --show-current]
if {$branch eq ""} {
    set branch "DETACHED"
}

set git_status [deployment_git $repo_root status --porcelain]
set dirty_suffix ""
if {$git_status ne ""} {
    if {!$opts(allow_dirty)} {
        error [join [list \
            "Git worktree is not clean." \
            "Commit or stash the changes so the generated image identifies one exact source state," \
            "or explicitly use -allow_dirty for a diagnostic build."] " "]
    }
    set dirty_suffix "-dirty"
}

set artifact_base "ctrlsys-${short_commit}${dirty_suffix}-z7020-125mhz"
file mkdir $opts(output_dir)

puts ""
puts "CtrlSys Red Pitaya release build"
puts "  repository: $repo_root"
puts "  branch:     $branch"
puts "  commit:     $commit"
puts "  project:    $opts(project)"
puts "  IP:         $expected_vlnv"
puts "  output:     $opts(output_dir)"
puts ""

if {!$opts(skip_repackage)} {
    puts "STEP 1: Repackage ctrlsys_core from source/hdl"
    set vivado [info nameofexecutable]
    set package_command [list \
        $vivado -mode batch -nojournal -nolog \
        -source $repackage_script -tclargs \
        -ip_root $ip_root \
        -part xc7z020clg400-1 \
        -version $opts(ip_version)]

    set package_status [catch {
        exec {*}$package_command 2>@1
    } package_output]
    puts $package_output
    if {$package_status} {
        error "ctrlsys_core repackaging failed"
    }
} else {
    puts "STEP 1: Reuse existing packaged IP (-skip_repackage)"
}

deployment_require_file [file join $ip_root component.xml] "Packaged component.xml"

puts "STEP 2: Refresh IP catalog and regenerate block-design products"
open_project $opts(project)

set project [current_project]
set repo_paths [get_property ip_repo_paths $project]
if {[lsearch -exact $repo_paths $ip_root] < 0} {
    set_property ip_repo_paths [linsert $repo_paths 0 $ip_root] $project
}
update_ip_catalog -rebuild

# upgrade_ip also refreshes an instance when the VLNV is unchanged but the
# packaged core's revision/checksum has changed.
set candidate_core_ips {}
foreach ip [get_ips -all -quiet] {
    if {[string match "user.org:user:ctrlsys_core:*" [get_property VLNV $ip]]} {
        lappend candidate_core_ips $ip
    }
}
if {[llength $candidate_core_ips] == 0} {
    error "The project contains no ctrlsys_core IP instance"
}
if {[catch {upgrade_ip $candidate_core_ips} upgrade_message]} {
    puts "IP refresh note: $upgrade_message"
}

set core_ips [deployment_core_ips $expected_vlnv]
if {[llength $core_ips] == 0} {
    set actual_vlnvs {}
    foreach ip $candidate_core_ips {
        lappend actual_vlnvs [get_property VLNV $ip]
    }
    error "Expected $expected_vlnv after refresh; found $actual_vlnvs"
}

foreach core_ip $core_ips {
    if {[get_property IS_LOCKED $core_ip]} {
        error "IP remains locked after refresh: $core_ip"
    }
    catch {reset_target all $core_ip}
    generate_target all $core_ip
}

set bd_files [get_files -all -quiet *.bd]
if {[llength $bd_files] == 0} {
    error "The project contains no block design"
}
foreach bd_file $bd_files {
    open_bd_design $bd_file
    validate_bd_design
    save_bd_design
    generate_target all $bd_file
}

update_compile_order -fileset sources_1

set ip_status_report [file join $opts(output_dir) "${artifact_base}-ip-status.txt"]
report_ip_status -file $ip_status_report -force

puts "STEP 3: Rebuild ctrlsys_core out-of-context synthesis products"
set core_runs [get_runs -quiet *ctrlsys_core*_synth_1]
foreach core_run $core_runs {
    reset_run $core_run
}
foreach core_run $core_runs {
    launch_runs $core_run -jobs $opts(jobs)
}
foreach core_run $core_runs {
    wait_on_run $core_run
    deployment_run_complete $core_run
}

puts "STEP 4: Run top-level synthesis"
reset_run synth_1
launch_runs synth_1 -jobs $opts(jobs)
wait_on_run synth_1
deployment_run_complete synth_1

puts "STEP 5: Run implementation and write the bitstream"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $opts(jobs)
wait_on_run impl_1
deployment_run_complete impl_1

set impl_run [get_runs impl_1]
set impl_dir [get_property DIRECTORY $impl_run]
set top_name [get_property top [get_filesets sources_1]]
set bit_src [file normalize [file join $impl_dir "${top_name}.bit"]]
deployment_require_file $bit_src "Implemented bitstream"

puts "STEP 6: Check routed timing and write release reports"
open_run impl_1
set timing_report [file join $opts(output_dir) "${artifact_base}-timing.txt"]
set drc_report [file join $opts(output_dir) "${artifact_base}-drc.txt"]
report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -file $timing_report \
    -force
report_drc -file $drc_report -force

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 1 -nworst 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    error "Could not obtain routed setup and hold timing paths"
}
set setup_wns [get_property SLACK [lindex $setup_paths 0]]
set hold_whs [get_property SLACK [lindex $hold_paths 0]]
puts "  routed setup WNS: $setup_wns ns"
puts "  routed hold WHS:  $hold_whs ns"
if {[expr {double($setup_wns) < 0.0 || double($hold_whs) < 0.0}]} {
    error "Routed timing is not clean; deployment artifacts were not published"
}

puts "STEP 7: Create commit-labelled Red Pitaya artifacts"
set bit_dst [file normalize [file join $opts(output_dir) "${artifact_base}.bit"]]
set bin_dst [file normalize [file join $opts(output_dir) "${artifact_base}.bit.bin"]]
set bif_path [file normalize [file join $opts(output_dir) "${artifact_base}.bif"]]
set manifest_path [file normalize [file join $opts(output_dir) "${artifact_base}.manifest.txt"]]

file copy -force $bit_src $bit_dst
file delete -force $bin_dst

set bif_stream [open $bif_path w]
puts $bif_stream "all:"
puts $bif_stream "{"
puts $bif_stream "  [file tail $bit_dst]"
puts $bif_stream "}"
close $bif_stream

set bootgen [deployment_find_bootgen]
set previous_dir [pwd]
cd $opts(output_dir)
set bootgen_status [catch {
    exec {*}$bootgen \
        -image $bif_path \
        -arch zynq \
        -process_bitstream bin \
        -o $bin_dst \
        -w 2>@1
} bootgen_output]
cd $previous_dir
puts $bootgen_output
if {$bootgen_status} {
    error "bootgen conversion failed"
}
deployment_require_file $bin_dst "Converted Red Pitaya bitstream"

set bit_sha256 [deployment_sha256 $bit_dst]
set bin_sha256 [deployment_sha256 $bin_dst]
set manifest [open $manifest_path w]
puts $manifest "artifact_base=$artifact_base"
puts $manifest "git_commit=$commit"
puts $manifest "git_branch=$branch"
puts $manifest "source_git_dirty=[expr {$dirty_suffix ne ""}]"
puts $manifest "vivado_version=[version -short]"
puts $manifest "part=xc7z020clg400-1"
puts $manifest "ip_vlnv=$expected_vlnv"
puts $manifest "project=$opts(project)"
puts $manifest "source_bitstream=$bit_src"
puts $manifest "routed_setup_wns_ns=$setup_wns"
puts $manifest "routed_hold_whs_ns=$hold_whs"
puts $manifest "bit_sha256=$bit_sha256"
puts $manifest "bit_bin_sha256=$bin_sha256"
puts $manifest "generated_utc=[clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]"
close $manifest

puts ""
puts "PASS: Red Pitaya FPGA image generated"
puts "  BIT:      $bit_dst"
puts "  BIT.BIN:  $bin_dst"
puts "  manifest: $manifest_path"
puts "  timing:   $timing_report"
puts "  DRC:      $drc_report"
puts "  SHA-256:  $bin_sha256"
puts ""

close_project
