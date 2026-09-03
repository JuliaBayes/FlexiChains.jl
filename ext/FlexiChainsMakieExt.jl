module FlexiChainsMakieExt

using FlexiChains: FlexiChains
using Makie
using Makie: ColorTypes
using StatsBase: StatsBase
using KernelDensity: KernelDensity

const FC = FlexiChains
const MakieGrids = Union{Makie.GridPosition,Makie.GridSubposition}

const MAKIE_KWARGS_DOCSTRING = """
- `figure::NamedTuple`: Additional keyword arguments passed to the `Makie.Figure` constructor.
- `axis::NamedTuple`: Additional keyword arguments passed to the `Makie.Axis` constructor for each subplot.
- `legend::NamedTuple`: Additional keyword arguments passed to the `Makie.Legend` constructor, if the legend is added.
- `legend_position::Symbol`: Position of the legend. This can be either `:right`, `:bottom` or `:none` for no legend.
- `layout`: either `nothing` (the default), or a tuple of `(nrows, ncols)` specifying the grid layout for the subplots.

All other keyword arguments are passed to the original Makie plotting function.
"""

"""
Adds a legend to the given `fig` for the chains in `chn` using the provided `colors`.

`legend_position` specifies where to place the legend: either `:right`, `:bottom` or `:none`.
If `legend_position` is `:none`, no legend is added.

Keyword arguments are forwarded to `Makie.Legend`.

Returns the created `Makie.Legend`, or `nothing` if no legend was added.
"""
function maybe_add_legend(
    fig::Makie.Figure,
    chn::FC.FlexiChain,
    colors::AbstractVector,
    legend_position::Symbol;
    kwargs...,
)
    legend_position == :none && return nothing
    nrows, ncols = size(fig.layout)
    labels = map(string, FC.chain_indices(chn))
    elems = map(color -> Makie.PolyElement(; color=color), colors)
    l = if legend_position == :bottom
        colpos = ncols > 1 ? range(1, ncols) : 1
        Makie.Legend(
            fig[nrows+1, colpos],
            elems,
            labels,
            "Chain";
            orientation=:horizontal,
            kwargs...,
        )
    elseif legend_position == :right
        rowpos = nrows > 1 ? range(1, nrows) : 1
        Makie.Legend(fig[rowpos, ncols+1], elems, labels, "Chain"; kwargs...)
    else
        error(
            "unsupported value for `legend_position`: permitted values are `:right`, `:bottom` or `:none`",
        )
    end
    return l
end

"""
Determines the color for each chain based on the provided `color` and `colormap` arguments.

Returns a `Vector` of colors, one per chain. When neither `color` nor `colormap` is given,
colours are taken from the current Makie theme palette.
"""
function determine_chain_colors(nchains::Int, kwargs::NamedTuple)::Vector
    color = get(kwargs, :color, nothing)
    colormap = get(kwargs, :colormap, nothing)

    if (!isnothing(colormap) && !isnothing(color))
        error("cannot specify both `color` and `colormap` arguments")
    end

    return if isnothing(colormap)
        if isnothing(color)
            # We need to explicitly construct the colors here (instead of just letting Makie
            # cycle through them) because for some plots we need to reuse the same colours
            # on the same plot (for example, ridgeline plots -- the density for each chain
            # needs to use the same colour across all parameters). If we just let Makie
            # cycle through them, then each chain x parameter combination will get a new
            # colour.
            map(j -> Makie.Cycled(j), 1:nchains)
        elseif color isa AbstractVector
            length(color) < nchains && error(
                "not enough colors specified for each chain: got $(length(color)), need $nchains",
            )
            collect(color[1:nchains])
        else
            fill(color, nchains)
        end
    else
        cm = Makie.to_colormap(colormap)
        map(i -> cm[i], 1:nchains)
    end
end

"""
This function sets up the figure and layout for the given number of rows and columns, unless
the user has manually specified a layout, in which case it uses that instead.
"""
function setup_figure_and_layout(
    nrows_default::Int,
    ncols_default::Int,
    layout::Union{Nothing,Tuple{Int,Int}},
    figure,
)
    nrows, ncols = if isnothing(layout)
        nrows_default, ncols_default
    else
        layout
    end
    figure = Makie.Figure(;
        size=(FC.PlotUtils.DEFAULT_WIDTH * ncols, FC.PlotUtils.DEFAULT_HEIGHT * nrows),
        figure...,
    )
    return nrows, ncols, figure
end

_band_alpha(i, n_bands) = 0.2 + 0.7 * i / n_bands

include("FlexiChainsMakieExt/pushforward_continuous.jl")
include("FlexiChainsMakieExt/pushforward_discrete.jl")
include("FlexiChainsMakieExt/pushforward_hist.jl")
include("FlexiChainsMakieExt/density.jl")
include("FlexiChainsMakieExt/hist.jl")
include("FlexiChainsMakieExt/mixeddensity.jl")
include("FlexiChainsMakieExt/traceplot.jl")
include("FlexiChainsMakieExt/plot.jl")
include("FlexiChainsMakieExt/meanplot.jl")
include("FlexiChainsMakieExt/autocorplot.jl")
include("FlexiChainsMakieExt/rankplot.jl")
include("FlexiChainsMakieExt/forestplot.jl")
include("FlexiChainsMakieExt/ridgeline.jl")
include("FlexiChainsMakieExt/violin.jl")

end
