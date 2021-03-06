module Gnuplot

using StructC14N, ColorTypes, Printf, StatsBase, ReusePatterns, DataFrames
using ColorSchemes

import Base.reset
import Base.write
import Base.iterate
import Base.convert
import Base.string

export @gp, @gsp, save, linestyles, palette, contourlines, hist

# ╭───────────────────────────────────────────────────────────────────╮
# │                           TYPE DEFINITIONS                        │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
mutable struct DataSet
    name::String
    lines::Vector{String}
end


# ---------------------------------------------------------------------
mutable struct SinglePlot
    cmds::Vector{String}
    elems::Vector{String}
    flag3d::Bool
    SinglePlot() = new(Vector{String}(), Vector{String}(), false)
end


# ---------------------------------------------------------------------
@quasiabstract mutable struct DrySession
    sid::Symbol                # session ID
    datas::Vector{DataSet}     # data sets
    plots::Vector{SinglePlot}  # commands and plot commands (one entry for each plot of the multiplot)
    curmid::Int                # current multiplot ID
end


# ---------------------------------------------------------------------
@quasiabstract mutable struct GPSession <: DrySession
    pin::Base.Pipe;
    pout::Base.Pipe;
    perr::Base.Pipe;
    proc::Base.Process;
    channel::Channel{String};
end


# ---------------------------------------------------------------------
Base.@kwdef mutable struct Options
    dry::Bool = false                         # Use "dry" sessions (i.e. without an underlying Gnuplot process)
    cmd::String = "gnuplot"                   # Customizable command to start the Gnuplot process
    default::Symbol = :default                # Default session name
    init::Vector{String} = Vector{String}()   # Commands to initialize the gnuplot session (e.g., to set default terminal)
    verbose::Bool = false                     # verbosity flag (true/false)
    datalines::Int = 4;                       # How many lines of a dataset are printed in log
end
const sessions = Dict{Symbol, DrySession}()
const options = Options()

# ╭───────────────────────────────────────────────────────────────────╮
# │                         LOW LEVEL FUNCTIONS                       │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
function string(c::ColorTypes.RGB)
    return string(float(c.r)*255) * " " * string(float(c.g)*255) * " " * string(float(c.b)*255)
end


# ---------------------------------------------------------------------
"""
  # CheckGnuplotVersion

  Check whether gnuplot is runnable with the command given in `cmd`.
  Also check that gnuplot version is >= 4.7 (required to use data
  blocks).
"""
function CheckGnuplotVersion(cmd::AbstractString)
    icmd = `$(cmd) --version`

    proc = open(`$icmd`, read=true)
    s = String(read(proc))
    if !success(proc)
        error("An error occurred while running: " * string(icmd))
    end

    s = split(s, " ")
    ver = ""
    for token in s
        try
            ver = VersionNumber("$token")
            break
        catch
        end
    end

    if ver < v"4.7"
        error("gnuplot ver. >= 4.7 is required, but " * string(ver) * " was found.")
    end
    #@info "  Gnuplot version: " * string(ver)
    return ver
end


# ---------------------------------------------------------------------
function parseKeywords(; kwargs...)
    template = (xrange=NTuple{2, Real},
                yrange=NTuple{2, Real},
                zrange=NTuple{2, Real},
                cbrange=NTuple{2, Real},
                title=AbstractString,
                xlabel=AbstractString,
                ylabel=AbstractString,
                zlabel=AbstractString,
                xlog=Bool,
                ylog=Bool,
                zlog=Bool)

    kw = canonicalize(template; kwargs...)
    out = Vector{String}()
    ismissing(kw.xrange ) || (push!(out, "set xrange  [" * join(kw.xrange , ":") * "]"))
    ismissing(kw.yrange ) || (push!(out, "set yrange  [" * join(kw.yrange , ":") * "]"))
    ismissing(kw.zrange ) || (push!(out, "set zrange  [" * join(kw.zrange , ":") * "]"))
    ismissing(kw.cbrange) || (push!(out, "set cbrange [" * join(kw.cbrange, ":") * "]"))
    ismissing(kw.title  ) || (push!(out, "set title  \"" * kw.title  * "\""))
    ismissing(kw.xlabel ) || (push!(out, "set xlabel \"" * kw.xlabel * "\""))
    ismissing(kw.ylabel ) || (push!(out, "set ylabel \"" * kw.ylabel * "\""))
    ismissing(kw.zlabel ) || (push!(out, "set zlabel \"" * kw.zlabel * "\""))
    ismissing(kw.xlog   ) || (push!(out, (kw.xlog  ?  ""  :  "un") * "set logscale x"))
    ismissing(kw.ylog   ) || (push!(out, (kw.ylog  ?  ""  :  "un") * "set logscale y"))
    ismissing(kw.zlog   ) || (push!(out, (kw.zlog  ?  ""  :  "un") * "set logscale z"))
    return out
end


# ---------------------------------------------------------------------
function data2string(args...)
    @assert length(args) > 0

    # Check types of args
    for iarg in 1:length(args)
        d = args[iarg]

        ok = false
        if typeof(d) <: Number
            ok = true
        elseif typeof(d) <: AbstractArray
            if typeof(d[1]) <: Number
                ok = true
            end
            if typeof(d[1]) <: ColorTypes.RGB
                ok = true
            end
        end
        @assert ok "Invalid argument type at position $iarg"
    end

    # Collect lengths and number of dims
    lengths = Vector{Int}()
    dims = Vector{Int}()
    firstMultiDim = 0
    for i in 1:length(args)
        d = args[i]
        @assert ndims(d) <= 3 "Array dimensions must be <= 3"
        push!(lengths, length(d))
        push!(dims   , ndims(d))
        (firstMultiDim == 0)  &&  (ndims(d) > 1)  &&  (firstMultiDim = i)
    end

    accum = Vector{String}()

    # All scalars
    if minimum(dims) == 0
        #@info "Case 0"
        @assert maximum(dims) == 0 "Input data are ambiguous: either use all scalar or arrays of floats"
        v = ""
        for iarg in 1:length(args)
            d = args[iarg]
            v *= " " * string(d)
        end
        push!(accum, v)
        return accum
    end

    @assert all((dims .== 1)  .|  (dims .== maximum(dims))) "Array size are incompatible"

    # All 1D
    if firstMultiDim == 0
        #@info "Case 1"
        @assert minimum(lengths) == maximum(lengths) "Array size are incompatible"
        for i in 1:lengths[1]
            v = ""
            for iarg in 1:length(args)
                d = args[iarg]
                v *= " " * string(d[i])
            end
            push!(accum, v)
        end
        return accum
    end

    # Multidimensional, no independent indices
    if firstMultiDim == 1
        #@info "Case 2"
        @assert minimum(lengths) == maximum(lengths) "Array size are incompatible"
        i = 1
        for CIndex in CartesianIndices(size(args[1]))
            indices = Tuple(CIndex)
            (i > 1)  &&  (indices[end-1] == 1)  &&  (push!(accum, ""))  # blank line
            v = "" # * join(string.(getindex.(Ref(Tuple(indices)), 1:ndims(args[1]))), " ")
            for iarg in 1:length(args)
                d = args[iarg]
                v *= " " * string(d[i])
            end
            i += 1
            push!(accum, v)
        end
        return accum
    end

    # Multidimensional (independent indices provided in input)
    if firstMultiDim >= 2
        @assert (firstMultiDim-1 == dims[firstMultiDim]) "Not enough independent variables"
        refLength = lengths[firstMultiDim]
        @assert all(lengths[firstMultiDim:end] .== refLength) "Array size are incompatible"

        if lengths[1] < refLength
            #@info "Case 3"
            # Cartesian product of Independent variables
            checkLength = prod(lengths[1:firstMultiDim-1])
            @assert prod(lengths[1:firstMultiDim-1]) == refLength "Array size are incompatible"

            i = 1
            for CIndex in CartesianIndices(size(args[firstMultiDim]))
                indices = Tuple(CIndex)
                (i > 1)  &&  (indices[end-1] == 1)  &&  (push!(accum, ""))  # blank line
                v = ""
                for iarg in 1:firstMultiDim-1
                    d = args[iarg]
                    v *= " " * string(d[indices[iarg]])
                end
                for iarg in firstMultiDim:length(args)
                    d = args[iarg]
                    v *= " " * string(d[i])
                end
                i += 1
                push!(accum, v)
            end
            return accum
        else
            #@info "Case 4"
            # All Independent variables have the same length as the main multidimensional data
            @assert all(lengths[1:firstMultiDim-1] .== refLength) "Array size are incompatible"

            i = 1
            for CIndex in CartesianIndices(size(args[firstMultiDim]))
                indices = Tuple(CIndex)
                (i > 1)  &&  (indices[end-1] == 1)  &&  (push!(accum, ""))  # blank line
                v = ""
                for iarg in 1:length(args)
                    d = args[iarg]
                    v *= " " * string(d[i])
                end
                i += 1
                push!(accum, v)
            end
            return accum
        end
    end

    return nothing
end


# ╭───────────────────────────────────────────────────────────────────╮
# │                SESSION CONSTRUCTORS AND getsession()              │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
function DrySession(sid::Symbol)
    global options
    (sid in keys(sessions))  &&  error("Gnuplot session $sid is already active")
    out = DrySession(sid, Vector{DataSet}(), [SinglePlot()], 1)
    sessions[sid] = out
    return out
end

# ---------------------------------------------------------------------
function GPSession(sid::Symbol)
    function readTask(sid, stream, channel)
        global options
        saveOutput = false

        while isopen(stream)
            line = readline(stream)
            if (length(line) >= 1)  &&  (line[1] == Char(0x1b)) # Escape (xterm -ti vt340)
                buf = Vector{UInt8}()
                append!(buf, convert(Vector{UInt8}, [line...]))
                push!(buf, 0x0a)
                c = 0x00
                while c != 0x1b
                    c = read(stream, 1)[1]
                    push!(buf, c)
                end
                c = read(stream, 1)[1]
                push!(buf, c)
                write(stdout, buf)
                continue
            end
            if line == "GNUPLOT_CAPTURE_BEGIN"
                saveOutput = true
            else
                if (line != "")  &&  (line != "GNUPLOT_CAPTURE_END")  &&  (options.verbose)
                    printstyled(color=:cyan, "GNUPLOT ($sid) -> $line\n")
                end
                (saveOutput)  &&  (put!(channel, line))
                (line == "GNUPLOT_CAPTURE_END")  &&  (saveOutput = false)
            end
        end
        delete!(sessions, sid)
        return nothing
    end

    global options

    CheckGnuplotVersion(options.cmd)
    session = DrySession(sid)

    pin  = Base.Pipe()
    pout = Base.Pipe()
    perr = Base.Pipe()
    proc = run(pipeline(`$(options.cmd)`, stdin=pin, stdout=pout, stderr=perr), wait=false)
    chan = Channel{String}(32)

    # Close unused sides of the pipes
    Base.close(pout.in)
    Base.close(perr.in)
    Base.close(pin.out)
    Base.start_reading(pout.out)
    Base.start_reading(perr.out)

    # Start reading tasks
    @async readTask(sid, pout, chan)
    @async readTask(sid, perr, chan)

    out = GPSession(getfield.(Ref(session), fieldnames(concretetype(DrySession)))...,
                    pin, pout, perr, proc, chan)
    sessions[sid] = out

    # Set window title
    term = writeread(out, "print GPVAL_TERM")[1]
    if term in ("aqua", "x11", "qt", "wxt")
        opts = writeread(out, "print GPVAL_TERMOPTIONS")[1]
        if findfirst("title", opts) == nothing
            writeread(out, "set term $term $opts title 'Gnuplot.jl: $(out.sid)'")
        end
    end
    for l in options.init
        writeread(out, l)
    end

    return out
end


# ---------------------------------------------------------------------
function getsession(sid::Symbol=options.default)
    global options
    if !(sid in keys(sessions))
        if options.dry
            DrySession(sid)
        else
            GPSession(sid)
        end
    end
    return sessions[sid]
end


# ╭───────────────────────────────────────────────────────────────────╮
# │                       write() and writeread()                     │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
"""
  # write

  Send a string to gnuplot's STDIN.

  The commands sent through `write` are not stored in the current
  session (use `newcmd` to save commands in the current session).

  ## Arguments:
  - `gp`: a `DrySession` object;
  - `str::String`: command to be sent;
"""
write(gp::DrySession, str::AbstractString) = nothing
function write(gp::GPSession, str::AbstractString)
    global options
    if options.verbose
        printstyled(color=:light_yellow, "GNUPLOT ($(gp.sid)) $str\n")
    end
    w = write(gp.pin, strip(str) * "\n")
    w <= 0  &&  error("Writing on gnuplot STDIN pipe returned $w")
    flush(gp.pin)
    return w
end


write(gp::DrySession, d::DataSet) = nothing
function write(gp::GPSession, d::DataSet)
    if options.verbose
        v = ""
        printstyled(color=:light_black, "GNUPLOT ($(gp.sid)) $(d.name) << EOD\n")
        n = min(options.datalines, length(d.lines))
        for i in 1:n
            printstyled(color=:light_black, "GNUPLOT ($(gp.sid)) $(d.lines[i])\n")
        end
        if n < length(d.lines)
            printstyled(color=:light_black, "GNUPLOT ($(gp.sid)) ...\n")
        end
        printstyled(color=:light_black, "GNUPLOT ($(gp.sid)) EOD\n")
    end
    write(gp.pin, "$(d.name) << EOD\n")
    write(gp.pin, join(d.lines, "\n") * "\n")
    write(gp.pin, "EOD\n")
    flush(gp.pin)
    return nothing
end


# ---------------------------------------------------------------------
writeread(gp::DrySession, str::AbstractString) = [""]
function writeread(gp::GPSession, str::AbstractString)
    global options
    verbose = options.verbose

    options.verbose = false
    write(gp, "print 'GNUPLOT_CAPTURE_BEGIN'")

    options.verbose = verbose
    write(gp, str)

    options.verbose = false
    write(gp, "print 'GNUPLOT_CAPTURE_END'")
    options.verbose = verbose

    out = Vector{String}()
    while true
        l = take!(gp.channel)
        l == "GNUPLOT_CAPTURE_END"  &&  break
        push!(out, l)
    end
    return out
end


# ╭───────────────────────────────────────────────────────────────────╮
# │              PRIVATE FUNCTIONS TO MANIPULATE SESSIONS             │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
function reset(gp::DrySession)
    gp.datas = Vector{DataSet}()
    gp.plots = [SinglePlot()]
    gp.curmid = 1
    exec(gp, "reset session")
    return nothing
end


# ---------------------------------------------------------------------
function setmulti(gp::DrySession, mid::Int)
    @assert mid >= 0 "Multiplot ID must be a >= 0"
    for i in length(gp.plots)+1:mid
        push!(gp.plots, SinglePlot())
    end
    (mid > 0)  &&  (gp.curmid = mid)
end


# ---------------------------------------------------------------------
function newdataset(gp::DrySession, accum::Vector{String}; name="")
    (name == "")  &&  (name = string("data", length(gp.datas)))
    name = "\$$name"
    d = DataSet(name, accum)
    push!(gp.datas, d)
    write(gp, d) # Send now to gnuplot process
    return name
end
newdataset(gp::DrySession, args...; name="") = newdataset(gp, data2string(args...), name=name)


# ---------------------------------------------------------------------
function newcmd(gp::DrySession, v::String; mid::Int=0)
    setmulti(gp, mid)
    (v != "")  &&  (push!(gp.plots[gp.curmid].cmds, v))
    (length(gp.plots) == 1)  &&  (exec(gp, v))  # execute now to check against errors
    return nothing
end

function newcmd(gp::DrySession; mid::Int=0, args...)
    for v in parseKeywords(;args...)
        newcmd(gp, v, mid=mid)
    end
    return nothing
end


# ---------------------------------------------------------------------
function newplot(gp::DrySession, name, opt=""; mid=0)
    setmulti(gp, mid)
    push!(gp.plots[gp.curmid].elems, "$name $opt")
end


# ---------------------------------------------------------------------
function quit(gp::DrySession)
    global options
    delete!(sessions, gp.sid)
    return 0
end

function quit(gp::GPSession)
    close(gp.pin)
    close(gp.pout)
    close(gp.perr)
    wait( gp.proc)
    exitCode = gp.proc.exitcode
    invoke(quit, Tuple{DrySession}, gp)
    return exitCode
end


# ╭───────────────────────────────────────────────────────────────────╮
# │                 execall(), dump() and driver()                    │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
execall(gp::DrySession; term::AbstractString="", output::AbstractString="") = nothing
function execall(gp::GPSession; term::AbstractString="", output::AbstractString="")
    if term != ""
        former_term = writeread(gp, "print GPVAL_TERM")[1]
        former_opts = writeread(gp, "print GPVAL_TERMOPTIONS")[1]
        exec(gp, "set term $term")
    end
    (output != "")  &&  exec(gp, "set output '$output'")

    for i in 1:length(gp.plots)
        d = gp.plots[i]
        for j in 1:length(d.cmds)
            exec(gp, d.cmds[j])
        end
        if length(d.elems) > 0
            s = (d.flag3d  ?  "splot "  :  "plot ") * " \\\n  " *
                join(d.elems, ", \\\n  ")
            exec(gp, s)
        end
    end
    (length(gp.plots) > 1)  &&  exec(gp, "unset multiplot")
    (output != "")  &&  exec(gp, "set output")
    if term != ""
        exec(gp, "set term $former_term $former_opts")
    end
    return nothing
end


function savescript(gp::DrySession, filename; term::AbstractString="", output::AbstractString="")
    stream = open(filename, "w")

    println(stream, "reset session")
    if term != ""
        println(stream, "set term $term")
    end
    (output != "")  &&  println(stream, "set output '$output'")

    for i in 1:length(gp.datas)
        d = gp.datas[i]
        println(stream, d.name * " << EOD")
        for j in 1:length(d.lines)
            println(stream, d.lines[j])
        end
        println(stream, "EOD")
    end

    for i in 1:length(gp.plots)
        d = gp.plots[i]
        for j in 1:length(d.cmds)
            println(stream, d.cmds[j])
        end
        if length(d.elems) > 0
            s = (d.flag3d  ?  "splot "  :  "plot ") * " \\\n  " *
                join(d.elems, ", \\\n  ")
            println(stream, s)
        end
    end
    (length(gp.plots) > 1)  &&  println(stream, "unset multiplot")
    println(stream, "set output")
    close(stream)
    return nothing
end


# ---------------------------------------------------------------------
function driver(args...; flag3d=false)
    if length(args) == 0
        gp = getsession()
        execall(gp)
        return nothing
    end

    data = Vector{Any}()
    dataname = ""
    dataplot = nothing

    function dataCompleted()
        if length(data) > 0
            AllArraysAreNotEmpty = true
            for i in 1:length(data)
                if (typeof(data[i]) <: AbstractArray)  &&  (length(data[i]) == 0)
                    @warn "Input array is empty"
                    AllArraysAreNotEmpty = false
                    break
                end
            end
            if AllArraysAreNotEmpty
                last = newdataset(gp, data...; name=dataname)
                (dataplot != nothing)  &&  (newplot(gp, last, dataplot))
            end
        end
        data = Vector{Any}()
        dataname = ""
        dataplot = nothing
    end
    function isPlotCmd(s::String)
        (length(s) >= 2)  &&  (s[1:2] ==  "p "    )  &&  (return (true, false, strip(s[2:end])))
        (length(s) >= 3)  &&  (s[1:3] ==  "pl "   )  &&  (return (true, false, strip(s[3:end])))
        (length(s) >= 4)  &&  (s[1:4] ==  "plo "  )  &&  (return (true, false, strip(s[4:end])))
        (length(s) >= 5)  &&  (s[1:5] ==  "plot " )  &&  (return (true, false, strip(s[5:end])))
        (length(s) >= 2)  &&  (s[1:2] ==  "s "    )  &&  (return (true, true , strip(s[2:end])))
        (length(s) >= 3)  &&  (s[1:3] ==  "sp "   )  &&  (return (true, true , strip(s[3:end])))
        (length(s) >= 4)  &&  (s[1:4] ==  "spl "  )  &&  (return (true, true , strip(s[4:end])))
        (length(s) >= 5)  &&  (s[1:5] ==  "splo " )  &&  (return (true, true , strip(s[5:end])))
        (length(s) >= 6)  &&  (s[1:6] ==  "splot ")  &&  (return (true, true , strip(s[6:end])))
        return (false, false, "")
    end

    gp = nothing
    doDump  = true
    doReset = true

    for loop in 1:2
        if loop == 2
            (gp == nothing)  &&  (gp = getsession())
            doReset  &&  reset(gp)
            gp.plots[gp.curmid].flag3d = flag3d
        end

        for iarg in 1:length(args)
            arg = args[iarg]

            if typeof(arg) == Symbol
                if arg == :-
                    (loop == 1)  &&  (iarg < length(args)) &&  (doReset = false)
                    (loop == 1)  &&  (iarg > 1 )           &&  (doDump  = false)
                else
                    (loop == 1)  &&  (gp = getsession(arg))
                end
            elseif isa(arg, Tuple)  &&  length(arg) == 2  &&  isa(arg[1], Symbol)
                if arg[1] == :term
                    if loop == 1
                        if typeof(arg[2]) == String
                            term = (deepcopy(arg[2]), "")
                        elseif length(arg[2]) == 2
                            term = deepcopy(arg[2])
                        else
                            error("The term tuple must contain at most two strings")
                        end
                    end
                else
                    (loop == 2)  &&  newcmd(gp; [arg]...) # A cmd keyword
                end
            elseif isa(arg, Int)
                (loop == 2)  &&  (@assert arg > 0)
                (loop == 2)  &&  (dataplot = ""; dataCompleted())
                (loop == 2)  &&  setmulti(gp, arg)
                (loop == 2)  &&  (gp.plots[gp.curmid].flag3d = flag3d)
            elseif isa(arg, String)
                # Either a dataname, a plot or a command
                if loop == 2
                    if isa(arg, String)  &&  (length(arg) > 1)  &&  (arg[1] == '$')
                        dataname = arg[2:end]
                        dataCompleted()
                    elseif length(data) > 0
                        dataplot = arg
                        dataCompleted()
                    else
                        (isPlot, is3d, cmd) = isPlotCmd(arg)
                        if isPlot
                            gp.plots[gp.curmid].flag3d = is3d
                            newplot(gp, cmd)
                        else
                            newcmd(gp, arg)
                        end
                    end
                end
            else
                (loop == 2)  &&  push!(data, arg) # a data set
            end
        end
    end

    dataplot = ""
    dataCompleted()
    (doDump)  &&  (execall(gp))

    return nothing
end


#_____________________________________________________________________
#                         EXPORTED FUNCTIONS
#_____________________________________________________________________

# --------------------------------------------------------------------
"""
`@gp args...`

The `@gp` macro (and its companion `@gsp`, for `splot` operations) allows to exploit all of the **Gnuplot** package functionalities using an extremely efficient and concise syntax.  Both macros accept the same syntax, as described below.

The macros accepts any number of arguments, with the following meaning:
- a symbol: the name of the session to use;
- a string: a command (e.g. "set key left") or plot specification (e.g. "with lines");
- a string starting with a `\$` sign: a data set name;
- an `Int` > 0: the plot destination in a multiplot session;
- a keyword/value pair: a keyword value (see below);
- any other type: a dataset to be passed to Gnuplot.  Each dataset must be terminated by either:
  - a string starting with a `\$` sign (i.e. the data set name);
  - or a string with the plot specifications (e.g. "with lines");
- the `:-` symbol, used as first argument, avoids resetting the Gnuplot session.  Used as last argument avoids immediate execution  of the plot/splot command.  This symbol can be used to split a  single call into multiple ones.

All entries are optional, and there is no mandatory order.  The plot specification can either be:
 - a complete plot/splot command (e.g., "plot sin(x)", both "plot" and "splot" can be abbreviated to "p" and "s" respectively);
 - or a partial specification starting with the "with" clause (if it follows a data set).

The list of accepted keyword is as follows:
- `title::String`: plot title;
- `xlabel::String`: X axis label;
- `ylabel::String`: Y axis label;
- `zlabel::String`: Z axis label;
- `xlog::Bool`: logarithmic scale for X axis;
- `ylog::Bool`: logarithmic scale for Y axis;
- `zlog::Bool`: logarithmic scale for Z axis;
- `xrange::NTuple{2, Number}`: X axis range;
- `yrange::NTuple{2, Number}`: Y axis range;
- `zrange::NTuple{2, Number}`: Z axis range;
- `cbrange::NTuple{2, Number}`: Color box axis range;

The symbol for the above-mentioned keywords may also be used in a shortened form, as long as there is no ambiguity with other keywords.  E.g. you can use: `xr=(1,10)` in place of `xrange=(1,10)`.

# Examples:

## Simple examples with no data:
```
@gp "plot sin(x)"
@gp "plot sin(x)" "pl cos(x)"
@gp "plo sin(x)" "s cos(x)"

# Split a `@gp` call in two
@gp "plot sin(x)" :-
@gp :- "plot cos(x)"

# Insert a 3 second pause between one plot and the next
@gp "plot sin(x)" 2 xr=(-2pi,2pi) "pause 3" "plot cos(4*x)"
```

### Simple examples with data:
```
@gp "set key left" tit="My title" xr=(1,12) 1:10 "with lines tit 'Data'"

x = collect(1.:10)
@gp x
@gp x x
@gp x -x
@gp x x.^2
@gp x x.^2 "w l"

lw = 3
@gp x x.^2 "w l lw \$lw"
```

### A more complex example
```
@gp("set grid", "set key left", xlog=true, ylog=true,
    title="My title", xlab="X label", ylab="Y label",
    x, x.^0.5, "w l tit 'Pow 0.5' dt 2 lw 2 lc rgb 'red'",
    x, x     , "w l tit 'Pow 1'   dt 1 lw 3 lc rgb 'blue'",
    x, x.^2  , "w l tit 'Pow 2'   dt 3 lw 2 lc rgb 'purple'")
```

### Multiplot example:
```
@gp(xr=(-2pi,2pi), "unset key",
    "set multi layout 2,2 title 'Multiplot title'",
    1, "p sin(x)"  ,
    2, "p sin(2*x)",
    3, "p sin(3*x)",
    4, "p sin(4*x)")
```
or equivalently
```
@gp xr=(-2pi,2pi) "unset key" "set multi layout 2,2 title 'Multiplot title'" :-
for i in 1:4
  @gp :- i "p sin(\$i*x)" :-
end
@gp
```

### Multiple gnuplot sessions
```
@gp :GP1 "plot sin(x)"
@gp :GP2 "plot sin(x)"

Gnuplot.quitall()
```

### Further examples
```
x = range(-2pi, stop=2pi, length=100);
y = 1.5 * sin.(0.3 .+ 0.7x) ;
noise = randn(length(x))./2;
e = 0.5 * fill(1, size(x));

name = "\\\$MyDataSet1"
@gp x y name "plot \$name w l" "pl \$name u 1:(2*\\\$2) w l"

@gsp randn(Float64, 30, 50)
@gp randn(Float64, 30, 50) "w image"
@gsp x y y

@gp("set key horizontal", "set grid",
    xrange=(-7,7), ylabel="Y label",
    x, y, "w l t 'Real model' dt 2 lw 2 lc rgb 'red'",
    x, y+noise, e, "w errorbars t 'Data'")

@gp "f(x) = a * sin(b + c*x); a = 1; b = 1; c = 1;"   :-
@gp :- x y+noise e name                               :-
@gp :- "fit f(x) \$name u 1:2:3 via a, b, c;"         :-
@gp :- "set multiplot layout 2,1"                     :-
@gp :- "plot \$name w points" ylab="Data and model"   :-
@gp :- "plot \$name u 1:(f(\\\$1)) w lines"           :-
@gp :- 2 xlab="X label" ylab="Residuals"              :-
@gp :- "plot \$name u 1:((f(\\\$1)-\\\$2) / \\\$3):(1) w errorbars notit"

# Retrieve values for a, b and c
a = Meta.parse(Gnuplot.exec("print a"))
b = Meta.parse(Gnuplot.exec("print b"))
c = Meta.parse(Gnuplot.exec("print c"))

# Save to a PDF file
save(term="pdf", output="gnuplot.pdf")
```

### Display an image
```
using TestImages
img = testimage("lena");
@gp img "w image"
@gp "set size square" img "w rgbimage" # Color image with correct proportions
@gp "set size square" img "u 2:(-\\\$1):3:4:5 with rgbimage" # Correct orientation
```
"""
macro gp(args...)
    out = Expr(:call)
    push!(out.args, :(Gnuplot.driver))
    for iarg in 1:length(args)
        arg = args[iarg]
        if (isa(arg, Expr)  &&  (arg.head == :(=)))
            sym = string(arg.args[1])
            val = arg.args[2]
            push!(out.args, :((Symbol($sym),$val)))
        else
            push!(out.args, arg)
        end
    end
    return esc(out)
end


"""
  # @gsp

  See documentation for `@gp`.
"""
macro gsp(args...)
    out = Expr(:macrocall, Symbol("@gp"), LineNumberNode(1, "Gnuplot.jl"))
    push!(out.args, args...)
    push!(out.args, Expr(:kw, :flag3d, true))
    return esc(out)
end


# ╭───────────────────────────────────────────────────────────────────╮
# │              FUNCTIONS MEANT TO BE INVOKED BY USERS               │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
"""
  `quit()`

  Quit the session and the associated gnuplot process (if any).
"""
function quit(sid::Symbol)
    global options
    if !(sid in keys(sessions))
        error("Gnuplot session $sid do not exists")
    end
    return quit(sessions[sid])
end

"""
  `quitall()`

  Quit all the sessions and the associated gnuplot processes.
"""
function quitall()
    global options
    for sid in keys(sessions)
        quit(sid)
    end
    return nothing
end


# --------------------------------------------------------------------
"""
`exec(sid::Symbol, s::Vector{String})`

Directly execute commands on the underlying Gnuplot process, and return the result(s).

## Examples:
```julia
exec("print GPVAL_TERM")
exec("plot sin(x)")
```
"""
exec(gp::DrySession, command::String) = nothing
function exec(gp::GPSession, command::String)
    answer = Vector{String}()
    push!(answer, writeread(gp, command)...)

    verbose = options.verbose
    options.verbose = false
    errno = writeread(gp, "print GPVAL_ERRNO")[1]
    options.verbose = verbose

    if errno != "0"
        printstyled(color=:red, "GNUPLOT ERROR $(gp.sid) -> ERRNO=$errno\n")
        errmsg = writeread(gp, "print GPVAL_ERRMSG")
        write(gp.pin, "reset error\n")
        for line in errmsg
            printstyled(color=:red, "GNUPLOT ERROR $(gp.sid) -> $line\n")
        end
        error("Gnuplot process raised an error")
    end

    return join(answer, "\n")
end
function exec(s::String)
    global options
    exec(getsession(), s)
end
exec(sid::Symbol, s::String) = exec(getsession(sid), s)


# --------------------------------------------------------------------
"""
`setverbose(b::Bool)`

Set verbose flag to `true` or `false` (default: `false`).
"""
function setverbose(b::Bool)
    global options
    options.verbose = b
end


# --------------------------------------------------------------------
"""
`save(...)`

Save the data and commands in the current session to either:
- the gnuplot process (i.e. produce a plot): `save(term="", output="")`;
- an IO stream: `save(stream::IO; term="", output="")`;
- a file: `save(file::AbstractStrings; term="", output="")`.

To save the data and command from a specific session pass the ID as first argument, i.e.:
- `save(sid::Symbol, term="", output="")`;
- `save(sid::Symbol, file::AbstractStrings; term="", output="")`.

In all cases the `term` keyword allows to specify a gnuplot terminal, and the `output` keyword allows to specify an output file.
"""
save(           ; kw...) = execall(getsession()   ; kw...)
save(sid::Symbol; kw...) = execall(getsession(sid); kw...)
save(             file::AbstractString; kw...) = savescript(getsession()   , file, kw...)
save(sid::Symbol, file::AbstractString; kw...) = savescript(getsession(sid), file, kw...)


# ╭───────────────────────────────────────────────────────────────────╮
# │                     HIGH LEVEL FACILITIES                         │
# ╰───────────────────────────────────────────────────────────────────╯
# ---------------------------------------------------------------------
linestyles(s::Symbol) = linestyles(colorschemes[s])
function linestyles(cmap::ColorScheme)
    styles = Vector{String}()
    for i in 1:length(cmap.colors)
        push!(styles, "set style line $i lt 1 lc rgb '#" * Base.hex(cmap.colors[i]))
    end
    return join(styles, "\n")
end

# --------------------------------------------------------------------
palette(s::Symbol) = palette(colorschemes[s])
function palette(cmap::ColorScheme)
    levels = Vector{String}()
    for x in LinRange(0, 1, length(cmap.colors))
        color = get(cmap, x)
        push!(levels, "$x '#" * Base.hex(color) * "'")
    end
    return "set palette defined (" * join(levels, ", ") * ")\nset palette maxcol $(length(cmap.colors))\n"
end


# ╭───────────────────────────────────────────────────────────────────╮
# │                     EXPERIMENTAL FUNCTIONS                        │
# ╰───────────────────────────────────────────────────────────────────╯
# # --------------------------------------------------------------------
# """
#   # repl
#
#   Read/evaluate/print/loop
# """
# function repl(sid::Symbol)
#     verb = options.verbose
#     options.verbose = 0
#     gp = getsession(sid)
#     while true
#         line = readline(stdin)
#         (line == "")  &&  break
#         answer = send(gp, line, true)
#         for line in answer
#             println(line)
#         end
#     end
#     options.verbose = verb
#     return nothing
# end
# function repl()
#     global options
#     return repl(options.default)
# end

# --------------------------------------------------------------------
#=
Example:
v = randn(1000)
h = hist(v, bs=0.2)
@gp h.loc h.counts "w histep" h.loc h.counts "w l"
=#
function hist(v::Vector{T}; range=[NaN,NaN], bs=NaN, nbins=0, pad=true) where T <: Number
    i = findall(isfinite.(v))
    isnan(range[1])  &&  (range[1] = minimum(v[i]))
    isnan(range[2])  &&  (range[2] = maximum(v[i]))
    i = findall(isfinite.(v)  .&  (v.>= range[1])  .&  (v.<= range[2]))
    (nbins > 0)  &&  (bs = (range[2] - range[1]) / nbins)
    if isfinite(bs)
        rr = range[1]:bs:range[2]
        if maximum(rr) < range[2]
            rr = range[1]:bs:(range[2]+bs)
        end
        hh = fit(Histogram, v[i], rr, closed=:left)
        if sum(hh.weights) < length(i)
            j = findall(v[i] .== range[2])
            @assert length(j) == (length(i) - sum(hh.weights))
            hh.weights[end] += length(j)
        end
    else
        hh = fit(Histogram, v[i], closed=:left)
    end
    @assert sum(hh.weights) == length(i)
    x = collect(hh.edges[1])
    x = (x[1:end-1] .+ x[2:end]) ./ 2
    h = hh.weights
    binsize = x[2] - x[1]
    if pad
        x = [x[1]-binsize, x..., x[end]+binsize]
        h = [0, h..., 0]
    end
    return (loc=x, counts=h, binsize=binsize)
end


# --------------------------------------------------------------------
function hist(v1::Vector{T1}, v2::Vector{T2};
              range1=[NaN,NaN], bs1=NaN, nbins1=0,
              range2=[NaN,NaN], bs2=NaN, nbins2=0) where {T1 <: Number, T2 <: Number}
    i = findall(isfinite.(v2))
    isnan(range1[1])  &&  (range1[1] = minimum(v1[i]))
    isnan(range1[2])  &&  (range1[2] = maximum(v1[i]))
    i = findall(isfinite.(v2))
    isnan(range2[1])  &&  (range2[1] = minimum(v2[i]))
    isnan(range2[2])  &&  (range2[2] = maximum(v2[i]))

    i1 = findall(isfinite.(v1)  .&  (v1.>= range1[1])  .&  (v1.<= range1[2]))
    i2 = findall(isfinite.(v2)  .&  (v2.>= range2[1])  .&  (v2.<= range2[2]))
    (nbins1 > 0)  &&  (bs1 = (range1[2] - range1[1]) / nbins1)
    (nbins2 > 0)  &&  (bs2 = (range2[2] - range2[1]) / nbins2)
    if isfinite(bs1) &&  isfinite(bs2)
        hh = fit(Histogram, (v1[i1], v2[i2]), (range1[1]:bs1:range1[2], range2[1]:bs2:range2[2]), closed=:left)
    else
        hh = fit(Histogram, (v1[i1], v2[i2]), closed=:left)
    end
    x1 = collect(hh.edges[1])
    x1 = (x1[1:end-1] .+ x1[2:end]) ./ 2
    x2 = collect(hh.edges[2])
    x2 = (x2[1:end-1] .+ x2[2:end]) ./ 2

    binsize1 = x1[2] - x1[1]
    binsize2 = x2[2] - x2[1]
    return (loc1=x1, loc2=x2, counts=hh.weights, binsize1=binsize1)
end


# --------------------------------------------------------------------
function contourlines(args...; cntrparam="level auto 10")
    tmpfile = Base.Filesystem.tempname()
    sid = Symbol("j", Base.Libc.getpid())
    if !haskey(Gnuplot.sessions, sid)
        gp = getsession(sid)
    end

    Gnuplot.exec(sid, "set term unknown")
    @gsp    sid "set contour base" "unset surface" :-
    @gsp :- sid "set cntrparam $cntrparam" :-
    @gsp :- sid "set table '$tmpfile'" :-
    @gsp :- sid args...
    Gnuplot.exec(sid, "unset table")
    Gnuplot.exec(sid, "reset")

    out = DataFrame()
    curlevel = NaN
    curx = Vector{Float64}()
    cury = Vector{Float64}()
    curid = 1
    elength(x, y) = sqrt.((x[2:end] .- x[1:end-1]).^2 .+
                          (y[2:end] .- y[1:end-1]).^2)
    function dump()
        ((length(curx) < 2)  ||  isnan(curlevel))  &&  return nothing
        tmp = DataFrame([Int, Float64, Vector{Float64}, Vector{Float64}, Vector{Float64}],
                        [:id, :level , :len           , :x             , :y])
        push!(tmp, (curid, curlevel, [0.; elength(curx, cury)], [curx...], [cury...]))
        append!(out, tmp)
        curid += 1
        # d = cumsum(elength(curx, cury))
        # i0 = findall(d .<= width); sort!(i0)
        # i1 = findall(d .>  width)
        # if (length(i0) > 0)  &&  (length(i1) > 0)
        #     rot1 = atan(cury[i0[end]]-cury[i0[1]], curx[i0[end]]-curx[i0[1]]) * 180 / pi
        #     rot = round(mod(rot1, 360))
        #     x = mean(curx[i0])
        #     y = mean(cury[i0])
        #     push!(outl, "set label " * string(length(outl)+1) * " '$curlevel' at $x, $y center front rotate by $rot")
        #     curx = curx[i1]
        #     cury = cury[i1]
        # end
        empty!(curx)
        empty!(cury)
    end

    for l in readlines(tmpfile)
        if length(strip(l)) == 0
            dump()
            continue
        end
        if !isnothing(findfirst("# Contour ", l))
            dump()
            curlevel = Meta.parse(strip(split(l, ':')[2]))
            continue
        end
        (l[1] == '#')  &&  continue

        n = Meta.parse.(split(l))
        @assert length(n) == 3
        push!(curx, n[1])
        push!(cury, n[2])
    end
    rm(tmpfile)

    if nrow(out) > 0
        levels = unique(out.level)
        sort!(levels)
        out[!, :levelcount] .= 0
        for i in 1:length(levels)
            j = findall(out.level .== levels[i])
            out[j, :levelcount] .= i
        end
    end
    return out
end


# --------------------------------------------------------------------
function boxxyerror(x, y; xmin=NaN, ymin=NaN, xmax=NaN, ymax=NaN, cartesian=false)
    @assert length(x) == length(y)
    @assert issorted(x)
    @assert issorted(y)
    xlow  = Vector{Float64}(undef, length(x))
    xhigh = Vector{Float64}(undef, length(x))
    ylow  = Vector{Float64}(undef, length(x))
    yhigh = Vector{Float64}(undef, length(x))
    for i in 2:length(x)-1
        xlow[i]  = (x[i-1] + x[i]) / 2
        ylow[i]  = (y[i-1] + y[i]) / 2
        xhigh[i] = (x[i+1] + x[i]) / 2
        yhigh[i] = (y[i+1] + y[i]) / 2
    end
    xlow[1]    = (isfinite(xmin)  ?  xmin  :  (x[1] - (x[2]-x[1])/2))
    ylow[1]    = (isfinite(ymin)  ?  ymin  :  (y[1] - (y[2]-y[1])/2))
    xlow[end]  = (x[end] - (x[end]-x[end-1])/2)
    ylow[end]  = (y[end] - (y[end]-y[end-1])/2)
    xhigh[1]   = (x[1] + (x[2]-x[1])/2)
    yhigh[1]   = (y[1] + (y[2]-y[1])/2)
    xhigh[end] = (isfinite(xmax)  ?  xmax  :  (x[end] + (x[end]-x[end-1])/2))
    yhigh[end] = (isfinite(ymax)  ?  ymax  :  (y[end] + (y[end]-y[end-1])/2))
    if !cartesian
        return (x, y, xlow, xhigh, ylow, yhigh)
    end
    n = length(x)
    i = repeat(1:n, outer=n)
    j = repeat(1:n, inner=n)
    return (x[i], y[j], xlow[i], xhigh[i], ylow[j], yhigh[j])
end


# --------------------------------------------------------------------
function histo2segments(in_x, counts)
    @assert length(in_x) == length(counts)
    x = Vector{Float64}()
    y = Vector{Float64}()
    push!(x, in_x[1])
    push!(y, counts[1])
    for i in 2:length(in_x)
        xx = (in_x[i-1] + in_x[i]) / 2.
        push!(x, xx)
        push!(y, counts[i-1])
        push!(x, xx)
        push!(y, counts[i])
    end
    push!(x, in_x[end])
    push!(y, counts[end])
    return (x, y)
end

end #module
