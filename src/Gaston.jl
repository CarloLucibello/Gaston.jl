## Copyright (c) 2013 Miguel Bazdresch
##
## This file is distributed under the 2-clause BSD License.

module Gaston

export closefigure, closeall, figure,
		plot, plot!, histogram, imagesc, surf,
		printfigure, set

import Base.show

# before doing anything else, verify gnuplot is present on this system
if !success(`gnuplot --version`)
    error("Gaston cannot be loaded: gnuplot is not available on this system.")
end

# load files
include("gaston_types.jl")
include("gaston_aux.jl")
include("gaston_llplot.jl")
include("gaston_hilvl.jl")
include("gaston_config.jl")

# set up global variables
# global variable that stores gnuplot's state
gnuplot_state = GnuplotState(false,nothing,[],"","","",false,Figure[],displayable("image/png"))

# when gnuplot_state goes out of scope, exit gnuplot
finalizer(gnuplot_state,gnuplot_exit)

# global variable that stores Gaston's configuration
gaston_config = GastonConfig()

# get started
gnuplot_init()

end
