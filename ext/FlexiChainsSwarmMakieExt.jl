module FlexiChainsSwarmMakieExt

using FlexiChains: FlexiChains
using Makie
using StatsBase: StatsBase
using SwarmMakie: SwarmMakie

const FC = FlexiChains
const MakieExt = Base.get_extension(FlexiChains, :FlexiChainsMakieExt)
const MakieGrids = Union{Makie.GridPosition,Makie.GridSubposition}

_default_dotplot_axis() = (xlabel="value",)

"""
The quantile dots of a `FlexiChainDotplot`, and the chain each dot came from.

Each chain contributes its own set of dots, but all of them are laid out together, so a
single stack can hold dots from several chains.
"""
function _dotplot_dots(d::FC.PlotUtils.FlexiChainDotplot)
    data = FC._get_raw_data(d.chn, d.param)
    FC.PlotUtils.check_eltype_is_real(data)
    dots_per_chain = if d.pool_chains
        [FC.PlotUtils.quantile_dots(data, d.nquantiles)]
    else
        [FC.PlotUtils.quantile_dots(datacol, d.nquantiles) for datacol in eachcol(data)]
    end
    values = reduce(vcat, dots_per_chain)
    # The size of a dot is one bin of the value range, so that range has to be positive.
    allequal(values) && throw(
        ArgumentError(
            "cannot draw a dot plot of $(d.param): all of its values are $(first(values))",
        ),
    )
    chains = StatsBase.inverse_rle(eachindex(dots_per_chain), length.(dots_per_chain))
    return values, chains
end

"""
One concrete colour per chain, resolving any `Makie.Cycled` against `ax`'s palette.

The colours are needed as values rather than as placeholders: every dot is drawn by a
single `beeswarm!` call carrying one colour per point, and the legend is built from the
same vector.
"""
function _chain_colors(ax::Makie.Axis, nchains::Int, kwargs::NamedTuple)
    palette = Makie.to_value(Makie.theme(ax.scene, :palette)[:color])
    return map(MakieExt.determine_chain_colors(nchains, kwargs)) do c
        c isa Makie.Cycled ? palette[mod1(c.i, length(palette))] : c
    end
end

"""
Number of dots in the tallest stack that `WilkinsonBeeswarm` produces over `values` when the
value axis is divided into `nbins` stacking pitches.

This mirrors the binning `WilkinsonBeeswarm` performs, but in data units rather than pixels.
The two agree because the bins depend on the pitch only as a fraction of the value span,
which `nbins` fixes in either space.
"""
function _tallest_stack(values::AbstractVector{<:Real}, nbins::Int)
    lo, hi = extrema(values)
    pitch = (hi - lo) / nbins
    pitch > 0 || return length(values)
    counts = zeros(Int, nbins)
    for v in values
        counts[clamp(round(Int, (v - lo) / pitch), 1, nbins)] += 1
    end
    return maximum(counts)
end

"""
The coarsest binning at which every panel's tallest stack still fits its axis.

A dot is one stacking pitch across and a stack of `k` dots is `k` pitches tall, so with the
value axis divided into `nbins` pitches the tallest stack covers `tallest / nbins` of the
axis width. `aspect` is the height-to-width ratio of the shortest axis; bins are added,
which shrinks the dots, until the tallest stack fits within it.

The starting point is `sqrt(2π * ndots)` bins, the binning a dot plot is conventionally
drawn with, so a plot with room to spare is left at that shape.
"""
function _fitting_nbins(values_per_panel, aspect::Real)
    ndots = maximum(length, values_per_panel)
    nbins = round(Int, sqrt(2 * pi * ndots))
    # An axis with no height has room for nothing, and no binning would change that.
    aspect > 0 || return nbins
    # A stack is at most `ndots` tall, so this many bins always fit and bounds the search.
    limit = ceil(Int, ndots / aspect)
    while nbins < limit &&
          maximum(v -> _tallest_stack(v, nbins), values_per_panel) / nbins > aspect
        nbins += 1
    end
    return nbins
end

"""
The binning to draw `values_per_panel` with, shared by every panel so that all of them get
the same dot size. Follows the axes' shape as they are resized, unless `nbins` is given.
"""
function _dotplot_nbins(axes, values_per_panel, nbins::Union{Nothing,Int})
    isnothing(nbins) || return Makie.Observable(nbins)
    viewports = map(ax -> ax.scene.viewport, axes)
    return Makie.lift(viewports...) do vps...
        _fitting_nbins(values_per_panel, minimum(vp -> vp.widths[2] / vp.widths[1], vps))
    end
end

"""
One stacking pitch of `values` in pixels, which `WilkinsonBeeswarm` takes as its bin width
and Makie as the diameter of a dot. Follows `ax` as it is resized or its limits change.
"""
function _dotplot_markersize(
    ax::Makie.Axis,
    values::AbstractVector{<:Real},
    nbins::Makie.Observable{Int},
)
    lo, hi = extrema(values)
    return Makie.lift(ax.finallimits, ax.scene.viewport, nbins) do limits, viewport, n
        (hi - lo) * viewport.widths[1] / limits.widths[1] / n
    end
end

"""
Draw `values` into `ax`, coloured by the chain each dot came from, and return the plot
together with the colour of each chain.

The layout runs in pixel space, so the category axis carries no data: it is fixed to `0..1`
with the category line on `0`, which puts the foot of every stack on the bottom of the
axis, and its decorations are hidden.
"""
function _draw_dotplot!(
    ax::Makie.Axis,
    values::AbstractVector{<:Real},
    chains::AbstractVector{Int},
    nchains::Int,
    nbins::Makie.Observable{Int};
    kwargs...,
)
    colors = _chain_colors(ax, nchains, NamedTuple(kwargs))
    Makie.ylims!(ax, 0, 1)
    Makie.hideydecorations!(ax)
    # The outermost dots reach exactly to the extreme values, so half a pitch of margin —
    # `0.5/nbins` of the value span — leaves half a dot of air on either side.
    Makie.on(nbins; update=true) do n
        ax.xautolimitmargin = (0.5 / n, 0.5 / n)
    end
    p = SwarmMakie.beeswarm!(
        ax,
        zeros(length(values)),
        values;
        algorithm=SwarmMakie.WilkinsonBeeswarm(),
        direction=:x,
        side=:right,
        markersize=_dotplot_markersize(ax, values, nbins),
        kwargs...,
        color=colors[chains],
    )
    return p, colors
end

"""
    FlexiChains.Makie.dotplot(
        chn::FC.FlexiChain[, param_or_params];
        nquantiles::Int=50,
        nbins::Union{Nothing,Int}=nothing,
        pool_chains::Bool=false,
        kwargs...,
    )

Create quantile dot plots for the specified parameters in the chain.

Each parameter is summarised by `nquantiles` dots placed at evenly spaced quantiles of the
posterior, so that every dot stands for the same amount of probability mass (`1 /
nquantiles`).

The dots are laid out by SwarmMakie's `WilkinsonBeeswarm`, so loading SwarmMakie.jl is
required. The bins are fixed and equally wide, so stacks line up with one another. The
count axis is not drawn: the layout happens in pixel space, where a stack level is not a
data coordinate. Read the plot by counting dots instead.

The default for several chains is that the quantile dots are coloured to indicate the chain.

$(FC.PlotUtils._PARAM_DOCSTRING("FlexiChains.Makie.dotplot"))

# Keyword arguments

- `nquantiles::Int`: number of dots drawn for each chain. Defaults to `50`.

- `nbins::Union{Nothing,Int}`: number of bins the value axis is divided into. A bin is one
  dot wide, so this is what sets the size of a dot. The default starts at
  `round(Int, sqrt(2π * ndots))` and adds bins until the tallest stack fits the height of
  the axis, so the dots stay as large as the axis has room for. All panels share one value,
  and it is recomputed when the figure is resized.

- `pool_chains::Bool`: whether to pool data from all chains into a single set of dots, or to
  compute the dots for each chain separately. Defaults to `false`.

$(MakieExt.MAKIE_KWARGS_DOCSTRING)
"""
function FC.Makie.dotplot(
    chn::FC.FlexiChain,
    param_or_params=FC.Parameter.(FC.parameters(chn));
    nquantiles::Int=50,
    nbins::Union{Nothing,Int}=nothing,
    pool_chains::Bool=false,
    layout::Union{Tuple{Int,Int},Nothing}=nothing,
    legend_position::Symbol=:bottom,
    figure=(;),
    axis=(;),
    legend=(;),
    kwargs...,
)
    chn, plot_names = FC.PlotUtils.subset_and_split_chain(chn, param_or_params)
    keys_to_plot = keys(chn)
    isempty(keys_to_plot) && throw(ArgumentError("no parameters to plot"))
    nrows, ncols, fig =
        MakieExt.setup_figure_and_layout(length(keys_to_plot), 1, layout, figure)
    # First horizontal, then vertical
    indices = Iterators.product(1:ncols, 1:nrows)
    panels = map(zip(indices, keys_to_plot)) do ((col, row), k)
        kstr = FC.PlotUtils.get_plot_param_name(k, plot_names)
        ax = Makie.Axis(fig[row, col]; _default_dotplot_axis()..., title=kstr, axis...)
        d = FC.PlotUtils.FlexiChainDotplot(chn, k, pool_chains, nquantiles)
        values, chains = _dotplot_dots(d)
        (; ax, values, chains)
    end
    # One binning for all panels, so that their dots are equally big.
    nchains = pool_chains ? 1 : FC.nchains(chn)
    shared_nbins = _dotplot_nbins(
        map(panel -> panel.ax, panels),
        map(panel -> panel.values, panels),
        nbins,
    )
    p, colors = nothing, nothing
    for panel in panels
        p, colors = _draw_dotplot!(
            panel.ax,
            panel.values,
            panel.chains,
            nchains,
            shared_nbins;
            kwargs...,
        )
    end
    if !pool_chains
        MakieExt.maybe_add_legend(fig, chn, colors, legend_position; legend...)
    end
    return Makie.FigureAxisPlot(fig, panels[end].ax, p)
end

########################
# Single axis plotting #
########################
function FC.Makie.dotplot(grid::MakieGrids, chn::FC.FlexiChain, param; axis=(;), kwargs...)
    chn, plot_names = FC.PlotUtils.subset_and_split_chain(chn, param)
    k = only(keys(chn))
    kstr = FC.PlotUtils.get_plot_param_name(k, plot_names)
    return FC.Makie.dotplot!(
        Makie.Axis(grid; _default_dotplot_axis()..., title=kstr, axis...),
        chn,
        param;
        kwargs...,
    )
end

function FC.Makie.dotplot!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param;
    nquantiles::Int=50,
    pool_chains::Bool=false,
    kwargs...,
)
    chn, _ = FC.PlotUtils.subset_and_split_chain(chn, param)
    k = only(keys(chn))
    return FC.Makie.dotplot!(
        ax,
        FC.PlotUtils.FlexiChainDotplot(chn, k, pool_chains, nquantiles);
        kwargs...,
    )
end

function FC.Makie.dotplot!(chn::FC.FlexiChain, param; kwargs...)
    return FC.Makie.dotplot!(Makie.current_axis(), chn, param; kwargs...)
end

function FC.Makie.dotplot!(
    ax::Makie.Axis,
    d::FC.PlotUtils.FlexiChainDotplot;
    nbins::Union{Nothing,Int}=nothing,
    kwargs...,
)
    values, chains = _dotplot_dots(d)
    nchains = d.pool_chains ? 1 : FC.nchains(d.chn)
    p, _ = _draw_dotplot!(
        ax,
        values,
        chains,
        nchains,
        _dotplot_nbins((ax,), (values,), nbins);
        kwargs...,
    )
    return Makie.AxisPlot(ax, p)
end

end
