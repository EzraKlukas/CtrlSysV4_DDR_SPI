# Rebuild the ctrlsys_core Vivado IP package from the current RTL.
#
# Batch usage:
#   vivado -mode batch -source source/scripts/repackage_ctrlsys_core_ip.tcl
#
# Vivado Tcl console:
#   source C:/Users/gordo/Documents/CtrlSysV4/source/scripts/repackage_ctrlsys_core_ip.tcl
#
# When sourced with a project open, packaging runs in a clean child Vivado
# process and the caller's IP catalog is refreshed afterward.

proc ctrlsys_usage {} {
    puts "Usage:"
    puts "  vivado -mode batch -source repackage_ctrlsys_core_ip.tcl -tclargs ?options?"
    puts ""
    puts "Options:"
    puts "  -ip_root <path>   Output directory. Default: <repo>/IP/ctrlsys_core"
    puts "  -part <part>      Packaging part. Default: xc7z020clg400-1"
    puts "  -vendor <vendor>  VLNV vendor. Default: user.org"
    puts "  -library <lib>    VLNV library. Default: user"
    puts "  -name <name>      VLNV name. Default: ctrlsys_core"
    puts "  -version <ver>    VLNV version. Default: 1.2"
    puts "  -taxonomy <path>  IP catalog taxonomy. Default: /UserIP"
}

proc ctrlsys_require_file {path label} {
    if {![file exists $path]} {
        error "$label does not exist: $path"
    }
}

proc ctrlsys_parse_args {repo_root} {
    array set opts [list \
        ip_root [file normalize [file join $repo_root IP ctrlsys_core]] \
        part xc7z020clg400-1 \
        vendor user.org \
        library user \
        name ctrlsys_core \
        version 1.2 \
        taxonomy /UserIP \
        internal_run 0]

    set args {}
    if {[info exists ::argv]} {
        set args $::argv
    }

    while {[llength $args] > 0} {
        set key [lindex $args 0]
        set args [lrange $args 1 end]

        switch -- $key {
            -help -
            --help {
                ctrlsys_usage
                return -code return
            }
            -internal_run {
                set opts(internal_run) 1
            }
            -ip_root -
            -part -
            -vendor -
            -library -
            -name -
            -version -
            -taxonomy {
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

    set opts(ip_root) [file normalize $opts(ip_root)]
    return [array get opts]
}

proc ctrlsys_copy_sources {hdl_dir destination file_names} {
    file mkdir $destination

    foreach file_name $file_names {
        set source [file normalize [file join $hdl_dir $file_name]]
        set target [file normalize [file join $destination $file_name]]

        ctrlsys_require_file $source "HDL source"
        file copy -force $source $target
    }
}

proc ctrlsys_publish_staged_package {staging_root ip_root} {
    set ip_parent [file dirname $ip_root]
    set ip_name [file tail $ip_root]
    set backup_root [file normalize [file join $ip_parent .${ip_name}.backup.[pid]]]
    set had_existing_package [file exists $ip_root]

    ctrlsys_require_file [file join $staging_root component.xml] \
        "Staged packaged component.xml"

    file mkdir $ip_parent
    file delete -force $backup_root

    if {$had_existing_package} {
        file rename $ip_root $backup_root
    }

    if {[catch {file rename $staging_root $ip_root} message options]} {
        if {$had_existing_package && [file exists $backup_root] && ![file exists $ip_root]} {
            file rename $backup_root $ip_root
        }
        return -options $options $message
    }

    if {$had_existing_package} {
        file delete -force $backup_root
    }
}

proc ctrlsys_read_int_localparam {config_path name} {
    set stream [open $config_path r]
    set text [read $stream]
    close $stream

    set pattern [format {localparam\s+int\s+%s\s*=\s*([0-9]+)\s*;} $name]
    if {![regexp $pattern $text -> value]} {
        error "Could not read integer localparam $name from $config_path"
    }
    return $value
}

proc ctrlsys_set_port_map {bus logical_name physical_name} {
    set map [ipx::get_port_maps -quiet $logical_name -of_objects $bus]
    if {$map eq ""} {
        set map [ipx::add_port_map $logical_name $bus]
    }
    set_property physical_name $physical_name $map
}

proc ctrlsys_add_axi_spi_interface {core} {
    set old_bus [ipx::get_bus_interfaces -quiet AXI_SPI -of_objects $core]
    if {$old_bus ne ""} {
        ipx::remove_bus_interface $old_bus
    }

    set bus [ipx::add_bus_interface AXI_SPI $core]
    set_property display_name {AXI SPI} $bus
    set_property description {Mirrored SPI connection to an AXI Quad SPI master} $bus
    set_property bus_type_vlnv xilinx.com:interface:spi:1.0 $bus
    set_property abstraction_type_vlnv xilinx.com:interface:spi_rtl:1.0 $bus
    set_property interface_mode mirroredMaster $bus

    ctrlsys_set_port_map $bus IO0_I axi_spi_io0_i
    ctrlsys_set_port_map $bus IO0_O axi_spi_io0_o
    ctrlsys_set_port_map $bus IO0_T axi_spi_io0_t
    ctrlsys_set_port_map $bus IO1_I axi_spi_io1_i
    ctrlsys_set_port_map $bus IO1_O axi_spi_io1_o
    ctrlsys_set_port_map $bus IO1_T axi_spi_io1_t
    ctrlsys_set_port_map $bus SCK_I axi_spi_sck_i
    ctrlsys_set_port_map $bus SCK_O axi_spi_sck_o
    ctrlsys_set_port_map $bus SCK_T axi_spi_sck_t
    ctrlsys_set_port_map $bus SS_I axi_spi_ss_i
    ctrlsys_set_port_map $bus SS_O axi_spi_ss_o
    ctrlsys_set_port_map $bus SS_T axi_spi_ss_t
}

proc ctrlsys_set_bus_parameter {core bus_name parameter_name value} {
    set bus [ipx::get_bus_interfaces -quiet $bus_name -of_objects $core]
    if {$bus eq ""} {
        error "Missing inferred bus interface '$bus_name'"
    }

    set parameter [ipx::get_bus_parameters -quiet $parameter_name -of_objects $bus]
    if {$parameter eq ""} {
        set parameter [ipx::add_bus_parameter $parameter_name $bus]
    }
    set_property value $value $parameter
}

proc ctrlsys_configure_clocks {core} {
    catch {ipx::associate_bus_interfaces -busif s00_axi -clock s00_axi_aclk $core}
    catch {ipx::associate_bus_interfaces -busif m_axis -clock clk $core}

    ctrlsys_set_bus_parameter $core clk ASSOCIATED_BUSIF m_axis
    ctrlsys_set_bus_parameter $core clk ASSOCIATED_RESET rst_n
    ctrlsys_set_bus_parameter $core rst_n POLARITY ACTIVE_LOW
    ctrlsys_set_bus_parameter $core s00_axi_aclk ASSOCIATED_BUSIF s00_axi
    ctrlsys_set_bus_parameter $core s00_axi_aclk ASSOCIATED_RESET s00_axi_aresetn
}

proc ctrlsys_configure_address_space {core} {
    foreach memory_map [ipx::get_memory_maps -of_objects $core] {
        foreach block [ipx::get_address_blocks -of_objects $memory_map] {
            set_property range 65536 $block
            set_property width 32 $block
        }
    }
}

proc ctrlsys_verify_parameters {core} {
    set actual {}

    foreach parameter [ipx::get_user_parameters -of_objects $core] {
        set name [get_property name $parameter]
        if {$name ne "Component_Name"} {
            lappend actual $name
        }
    }
    set actual [lsort $actual]

    if {[llength $actual] != 0} {
        error "Expected no customization parameters from ctrlsys_core, found $actual"
    }
}

proc ctrlsys_write_xgui {ip_root name} {
    set xgui_dir [file normalize [file join $ip_root xgui]]
    set xgui_path [file normalize [file join $xgui_dir ${name}_v1_0.tcl]]
    file mkdir $xgui_dir

    set text {# Auto-generated by repackage_ctrlsys_core_ip.tcl.
proc init_gui {IPINST} {
    ipgui::add_param $IPINST -name Component_Name
}
}

    set stream [open $xgui_path w]
    puts -nonewline $stream $text
    close $stream
    puts "Wrote XGUI: $xgui_path"
}

proc ctrlsys_verify_axi_spi_interface {core} {
    set bus [ipx::get_bus_interfaces -quiet AXI_SPI -of_objects $core]
    if {$bus eq ""} {
        error "AXI_SPI bus interface was not created"
    }

    if {[get_property bus_type_vlnv $bus] ne "xilinx.com:interface:spi:1.0"} {
        error "AXI_SPI has the wrong bus type"
    }

    foreach mapping {
        IO0_I:axi_spi_io0_i
        IO0_O:axi_spi_io0_o
        IO0_T:axi_spi_io0_t
        IO1_I:axi_spi_io1_i
        IO1_O:axi_spi_io1_o
        IO1_T:axi_spi_io1_t
        SCK_I:axi_spi_sck_i
        SCK_O:axi_spi_sck_o
        SCK_T:axi_spi_sck_t
        SS_I:axi_spi_ss_i
        SS_O:axi_spi_ss_o
        SS_T:axi_spi_ss_t
    } {
        lassign [split $mapping :] logical physical
        set map [ipx::get_port_maps -quiet $logical -of_objects $bus]
        if {$map eq "" || [get_property physical_name $map] ne $physical} {
            error "AXI_SPI mapping $logical -> $physical is missing"
        }
    }
}

proc ctrlsys_build_package {repo_root opts_list} {
    array set opts $opts_list

    set hdl_dir [file normalize [file join $repo_root source hdl]]
    set temp_root [file normalize [file join $repo_root build ip_packager_tmp]]
    set temp_src [file normalize [file join $temp_root src]]
    set project_dir [file normalize [file join $temp_root project]]
    set ip_parent [file dirname $opts(ip_root)]
    set ip_name [file tail $opts(ip_root)]
    set staging_ip_root [file normalize [file join $ip_parent .${ip_name}.staging.[pid]]]
    set hdl_files {
        config_pkg.sv
        axil_regs_slave_lite_v1_0_S00_AXI.v
        axil_regs.v
        acquisition_controller.sv
        ICM_reader.sv
        intan_program.sv
        intan_spi_word_engine.sv
        intan_cmd_sequencer.sv
        intan_acq_engine.sv
        intan_reader.sv
        packet_writer.sv
        packet_buffer.sv
        packet_to_axis.sv
        SPI_mux.sv
        stopwatch_64.sv
        ctrlsys_core.sv
        ctrlsys_core_ip_wrapper.v
    }

    puts "Repackaging ctrlsys_core"
    puts "  RTL:     $hdl_dir"
    puts "  IP root: $opts(ip_root)"
    puts "  Part:    $opts(part)"

    file delete -force $temp_root
    file delete -force $staging_ip_root

    set build_status [catch {
        ctrlsys_copy_sources $hdl_dir $temp_src $hdl_files
        create_project -force ctrlsys_core_ip_packager $project_dir -part $opts(part)

        set project_files {}
        foreach file_name $hdl_files {
            lappend project_files [file normalize [file join $temp_src $file_name]]
        }
        add_files -norecurse -fileset sources_1 $project_files
        set_property top ctrlsys_core_ip_wrapper [get_filesets sources_1]
        update_compile_order -fileset sources_1

        ipx::package_project \
            -root_dir $staging_ip_root \
            -vendor $opts(vendor) \
            -library $opts(library) \
            -taxonomy $opts(taxonomy) \
            -import_files \
            -force

        set core [ipx::current_core]
        set_property vendor $opts(vendor) $core
        set_property library $opts(library) $core
        set_property name $opts(name) $core
        set_property version $opts(version) $core
        set_property taxonomy [list $opts(taxonomy)] $core
        set_property display_name {CtrlSysV4 Control System Core} $core
        set_property description {Multi-sensor SPI acquisition core with AXI4-Lite control and AXI4-Stream output} $core

        ctrlsys_add_axi_spi_interface $core
        ctrlsys_configure_clocks $core
        ctrlsys_configure_address_space $core
        ctrlsys_verify_parameters $core

        ipx::create_xgui_files $core
        ctrlsys_write_xgui $staging_ip_root $opts(name)
        ctrlsys_verify_axi_spi_interface $core

        ipx::update_checksums $core
        set integrity [ipx::check_integrity -quiet $core]
        if {$integrity ne ""} {
            puts $integrity
        }
        ipx::save_core $core

        set staged_component_xml [file normalize [file join $staging_ip_root component.xml]]
        ctrlsys_require_file $staged_component_xml "Staged packaged component.xml"
    } build_message build_options]

    catch {close_project}

    if {$build_status} {
        file delete -force $staging_ip_root
        file delete -force $temp_root
        return -options $build_options $build_message
    }

    if {[catch {
        ctrlsys_publish_staged_package $staging_ip_root $opts(ip_root)
    } publish_message publish_options]} {
        file delete -force $staging_ip_root
        file delete -force $temp_root
        return -options $publish_options $publish_message
    }

    file delete -force $temp_root

    set component_xml [file normalize [file join $opts(ip_root) component.xml]]
    ctrlsys_require_file $component_xml "Packaged component.xml"
    puts "Packaged IP: $component_xml"
}

proc ctrlsys_refresh_open_project {ip_root name} {
    set project [current_project -quiet]
    if {$project eq ""} {
        return
    }

    set repo_paths [get_property ip_repo_paths $project]
    if {[lsearch -exact $repo_paths $ip_root] < 0} {
        set_property ip_repo_paths [concat $repo_paths [list $ip_root]] $project
    }
    update_ip_catalog -rebuild

    set instances [get_ips -all -quiet *${name}*]
    if {[llength $instances] > 0} {
        if {[catch {upgrade_ip $instances} message]} {
            puts "IP upgrade note: $message"
        }
        foreach instance $instances {
            catch {reset_target all $instance}
            catch {generate_target all $instance}
        }
    }

    puts "Refreshed IP catalog for [get_property NAME $project]"
}

proc ctrlsys_spawn_clean_packager {script_path opts_list} {
    array set opts $opts_list
    set vivado [info nameofexecutable]
    set command [list $vivado -mode batch -nojournal -nolog -source $script_path -tclargs \
        -internal_run \
        -ip_root $opts(ip_root) \
        -part $opts(part) \
        -vendor $opts(vendor) \
        -library $opts(library) \
        -name $opts(name) \
        -version $opts(version) \
        -taxonomy $opts(taxonomy)]

    puts "A project is open; running packaging in a clean Vivado process."
    set status [catch {exec {*}$command} output]
    puts $output
    if {$status} {
        error "Clean IP packaging process failed"
    }
}

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set repo_root [file normalize [file join [file dirname [info script]] ../..]]
set opts_list [ctrlsys_parse_args $repo_root]
array set opts $opts_list

if {[catch {
    set open_project [current_project -quiet]
    if {$open_project ne "" && !$opts(internal_run)} {
        ctrlsys_spawn_clean_packager $script_path $opts_list
        ctrlsys_refresh_open_project $opts(ip_root) $opts(name)
    } else {
        ctrlsys_build_package $repo_root $opts_list
    }
} message]} {
    puts $::errorInfo
    error $message
}
