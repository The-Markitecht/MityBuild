# This script configures Tcl interp to find and load libMityBuild.

# For this to work, user should have set his environment TCLLIBPATH
# to the directory where pkgIndex.tcl is stored.
# That way requires no modifications to the operating system directories by the root user.

package ifneeded MityBuild 3.0 {
    interp alias {} ::MityBuild::pkgconfig {} ::tcl::pkgconfig
    tcl_findLibrary MityBuild 3.0 0 libMityBuild {} MityBuildDir
}

