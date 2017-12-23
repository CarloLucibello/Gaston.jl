## Copyright (c) 2013 Miguel Bazdresch
##
## This file is distributed under the 2-clause BSD License.

function gnuplot_init()
    global gnuplot_state

    pr = (0,0,0,0) # stdin, stdout, stderr, pid
    try
		pr = popen3(`gnuplot`)
    catch
        error("There was a problem starting up gnuplot.")
    end
    # It's possible that `popen3` runs successfully, but gnuplot exits
    # immediately. Double-check that gnuplot is running at this point.
    if Base.process_running(pr[4])
	    gnuplot_state.running = true
	    gnuplot_state.fid = pr
		# Start tasks to read and write gnuplot's pipes
		yield()  # get async tasks started (code blocks without this line)
		notify(StartPipes)
	else
        error("There was a problem starting up gnuplot.")
	end
end

# Async tasks to read/write to gnuplot's pipes.
const StartPipes = Condition()  # signal to start reading pipes

# This task reads all characters available from gnuplot's stdout.
@async while true
	wait(StartPipes)
	pout = gnuplot_state.fid[2]
	while true
		if !isopen(pout)
			break
		end
		gnuplot_state.gp_stdout = string(readavailable(pout))
	end
end

# This task reads all characters available from gnuplot's stderr.
@async while true
	wait(StartPipes)
	perr = gnuplot_state.fid[3]
	while true
		if !isopen(perr)
			break
		end
		gnuplot_state.gp_stderr = ascii(String(readavailable(perr)))
	end
end

# close gnuplot pipe
function gnuplot_exit(x...)
    global gnuplot_state

    if gnuplot_state.running
        # close pipe
        close(gnuplot_state.fid[1])
        close(gnuplot_state.fid[2])
        close(gnuplot_state.fid[3])
    end
    # reset gnuplot_state
    gnuplot_state.running = false
    gnuplot_state.current = nothing
    gnuplot_state.figs = Any[]
    return 0
end

# Return index to figure with handle 'c'. If no such figure exists, returns 0.
function findfigure(c)
    global gnuplot_state
    i = 0
    for j = 1:length(gnuplot_state.figs)
        if gnuplot_state.figs[j].handle == c
            i = j
            break
        end
    end
    return i
end

# Return the next available handle (smallest non-used positive integer)
function nexthandle()
	handles = [f.handle for f in gnuplot_state.figs]
	mh = maximum(handles)
	for i = 1:mh+1
		!in(i,handles) && return i
	end
end

# Push a figure to gnuplot_state
function push_figure!(f::Figure)
	# if pushing to an existing but empty handle, overwrite it
	handle = f.handle
	handle < 1 && error("Invalid handle")
	index = findfigure(handle)
	if gnuplot_state.figs[index].isempty
		gnuplot_state.figs[index] = f
	else
		push!(gnuplot_state.figs,f)
	end
	return nothing
end

# Push a curve to a figure
function push_curve!(handle,curves...)
	index = findfigure(handle)
	index == 0 && error("No such figure.")
	for c in curves
		if gnuplot_state.figs[index].isempty
			gnuplot_state.figs[index].curves = [c]
		else
			push!(gnuplot_state.figs[index].curves,c)
		end
	end
	return nothing
end

# convert marker string description to gnuplot's expected number
function pointtype(x::AbstractString)
    if x == "+"
        return 1
    elseif x == "x"
        return 2
    elseif x == "*"
        return 3
    elseif x == "esquare"
        return 4
    elseif x == "fsquare"
        return 5
    elseif x == "ecircle"
        return 6
    elseif x == "fcircle"
        return 7
    elseif x == "etrianup"
        return 8
    elseif x == "ftrianup"
        return 9
    elseif x == "etriandn"
        return 10
    elseif x == "ftriandn"
        return 11
    elseif x == "edmd"
        return 12
    elseif x == "fdmd"
        return 13
    end
    return 1
end

# return configuration string for a single plot
function linestr_single(conf::CurveConf)
    s = ""
    if conf.legend != ""
        s = string(s, " title '", conf.legend, "' ")
    else
        s = string(s, "notitle ")
    end
    s = string(s, " with ", conf.plotstyle, " ")
    if conf.color != ""
        s = string(s, "linecolor rgb '", conf.color, "' ")
    end
    s = string(s, "lw ", string(conf.linewidth), " ")
    # some plotstyles don't allow point specifiers
    cp = conf.plotstyle
    if cp != "lines" && cp != "impulses" && cp != "pm3d" && cp != "image" &&
        cp != "rgbimage" && cp != "boxes" && cp != "dots" && cp != "steps" &&
        cp != "fsteps" && cp != "fillsteps" && cp != "financebars"
        if conf.marker != ""
            s = string(s, "pt ", string(pointtype(conf.marker)), " ")
        end
        s = string(s, "ps ", string(conf.pointsize), " ")
    end
    return s
end

# build a string with plot commands according to configuration
function linestr(curves::Vector{Curve}, cmd::AbstractString, file::AbstractString)
    # We have to insert "," between plot commands. One easy way to do this
    # is create the first plot command, then the rest
    # We also need to keep track of the current index (starts at zero)
    index = 0
    s = string(cmd, " '", file, "' ", " i 0 ", linestr_single(curves[1].conf))
    if length(curves) > 1
        for i in curves[2:end]
            index += 1
            s = string(s, ", '", file, "' ", " i ", string(index)," ",
                linestr_single(i.conf))
        end
    end
    return s
end

# create a Z-coordinate matrix from x, y coordinates and a function
function meshgrid(x,y,f)
    Z = zeros(length(x),length(y))
    for k = 1:length(x)
        Z[k,:] = [ f(i,j) for i=x[k], j=y ]
    end
    return Z
end

# dereference CurveConf, by adding a method to copy()
function copy(conf::CurveConf)
    new = CurveConf()
    new.legend = conf.legend
    new.plotstyle = conf.plotstyle
    new.color = conf.color
    new.marker = conf.marker
    new.linewidth = conf.linewidth
    new.pointsize = conf.pointsize
    return new
end

# dereference AxesConf
function copy(conf::AxesConf)
    new = AxesConf()
    new.title = conf.title
    new.xlabel = conf.xlabel
    new.ylabel = conf.ylabel
    new.zlabel = conf.zlabel
    new.fill = conf.fill
    new.grid = conf.grid
    new.box = conf.box
    new.axis = conf.axis
    new.xrange = conf.xrange
    new.yrange = conf.yrange
    new.zrange = conf.zrange
    return new
end

# Build a "set term" string appropriate for the terminal type
function termstring(term::AbstractString)
    global gnuplot_state
    global gaston_config

    gc = gaston_config

    if term ∈ supported_screenterms
        ts = "set term $term $(gnuplot_state.current)"
    else
        if term == "pdf"
            s = "set term pdfcairo $(gc.print_color) "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "eps"
            s = "set term epscairo $(gc.print_color) "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "png"
            s = "set term pngcairo $(gc.print_color) "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "gif"
            s = "set term gif "
            s = "$s font $(gc.print_fontface) $(gc.print_fontsize) "
            s = "$s fontscale $(gc.print_fontscale) "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        elseif term == "svg"
            s = "set term svg "
            s = "$s font \"$(gc.print_fontface),$(gc.print_fontsize)\" "
            s = "$s linewidth $(gc.print_linewidth) "
            s = "$s size $(gc.print_size)"
        end
        ts = "$s \nset output \"$(gc.outputfile)\""
    end
    return ts
end

# send gnuplot the current figure's configuration
function gnuplot_send_fig_config(config)
	# fill style
	if config.fill != ""
		gnuplot_send(string("set style fill ",config.fill))
	end
	# grid
	if config.grid != ""
		if config.grid == "on"
			gnuplot_send(string("set grid"))
		else
			gnuplot_send(string("unset grid"))
		end
	end
    # legend box
    if config.box != ""
        gnuplot_send(string("set key ",config.box))
    end
    # plot title
    if config.title != ""
        gnuplot_send(string("set title '",config.title,"' "))
    end
    # xlabel
    if config.xlabel != ""
        gnuplot_send(string("set xlabel '",config.xlabel,"' "))
    end
    # ylabel
    if config.ylabel != ""
        gnuplot_send(string("set ylabel '",config.ylabel,"' "))
    end
    # zlabel
    if config.zlabel != ""
        gnuplot_send(string("set zlabel '",config.zlabel,"' "))
    end
    # axis log scale
    if config.axis != "" || config.axis != "normal"
        if config.axis == "semilogx"
            gnuplot_send("set logscale x")
        end
        if config.axis == "semilogy"
            gnuplot_send("set logscale y")
        end
        if config.axis == "loglog"
            gnuplot_send("set logscale xy")
        end
    end
    # ranges
    gnuplot_send("set autoscale")
    if config.xrange != ""
        gnuplot_send(string("set xrange ",config.xrange))
    end
    if config.yrange != ""
        gnuplot_send(string("set yrange ",config.yrange))
    end
    if config.zrange != ""
        gnuplot_send(string("set zrange ",config.zrange))
    end
end

# create x,y coordinates for a histogram, from a sample vector, using a number
# of bins
function hist(s,bins)
    # When adding an element s to a bin, we use an iequality m < s <= M.
    # In order to account for elements s==m, we need to special-case
    # the computation for the first bin
    ms = minimum(s)
    Ms = maximum(s)
    bins = max(bins, 1)
    if Ms == ms
        # compute a "natural" scale
        g = (10.0^floor(log10(abs(ms)+eps()))) / 2
        ms, Ms = ms - g, ms + g
    end
    delta = (Ms-ms)/bins
    x = ms:delta:Ms
    y = zeros(bins)
    # this is special-cased because we want to include the minimum in the
    # first bin
    y[1] = sum(ms .<= s .<= x[2])
    for i in 2:length(x)-2
        y[i] = sum(x[i] .< s .<= x[i+1])
    end
    # this is special-cased because there is no guarantee that x[end] == Ms
    # (because of how ranges work)
    if length(y) > 1 y[end] = sum(x[end-1] .< s .<= Ms) end

    if bins != 1
        # We want the left bin to start at ms and the right bin to end at Ms
        x = (ms+delta/2):delta:Ms
    else
        # add two empty bins on the sides to provide a scale to gnuplot
        x = (ms-delta/2):delta:(ms+delta/2)
        y = [0.0, y[1], 0.0]
    end
    return x,y
end

function Base.show(io::IO, ::MIME"image/png", x::Figure)
	# The plot is written to /tmp/gaston-ijula.png. Read the file and
	# write it to io.
	data = open(read, "$(tempdir())/gaston-ijulia.png","r")
	write(io,data)
end

# Execute command `cmd`, and return a tuple `(in, out, err, r)`, where
# `in`, `out`, `err` are pipes to the process' STDIN, STDOUT, and STDERR, and
# `r` is a process descriptor.
function popen3(cmd::Cmd)
    pin = Base.Pipe()
    out = Base.Pipe()
    err = Base.Pipe()
    r = spawn(cmd, (pin, out, err))
    Base.close_pipe_sync(out.in)
    Base.close_pipe_sync(err.in)
    Base.close_pipe_sync(pin.out)
    Base.start_reading(out.out)
    Base.start_reading(err.out)
    return (pin.in, out.out, err.out, r)
end
