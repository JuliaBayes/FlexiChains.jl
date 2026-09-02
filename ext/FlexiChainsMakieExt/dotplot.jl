_default_dotplot_axis() = (xlabel="value", ylabel="count")

"""
Dot coordinates for a `FlexiChainDotplot`, plus the chain each dot came from and the bin
width they are stacked with.

Each chain contributes its own set of quantile dots, but the dots of all chains are stacked
together, so a single stack can hold dots from several chains.
"""
function _dotplot_coordinates(d::FC.PlotUtils.FlexiChainDotplot, binwidth)
    data = FC._get_raw_data(d.chn, d.param)
    FC.PlotUtils.check_eltype_is_real(data)
    dots_per_chain = if d.pool_chains
        [FC.PlotUtils.quantile_dots(data, d.nquantiles)]
    else
        [FC.PlotUtils.quantile_dots(datacol, d.nquantiles) for datacol in eachcol(data)]
    end
    values = reduce(vcat, dots_per_chain)
    chains = StatsBase.inverse_rle(eachindex(dots_per_chain), length.(dots_per_chain))
    perm = sortperm(values)
    values, chains = values[perm], chains[perm]
    bw = isnothing(binwidth) ? FC.PlotUtils.default_binwidth(values) : binwidth
    locations, levels = FC.PlotUtils.dot_coordinates(values, bw)
    return locations, levels, chains, bw
end

# At most six ticks, all whole numbers of dots.
_dotplot_stack_ticks(maxlevel::Int) = 0:max(1, cld(maxlevel, 6)):maxlevel

"""
Number of bins the value axis spans, including one bin of margin on each side so that the
outermost dots are not clipped by the frame.
"""
function _dotplot_nbins(values, binwidth)
    lo, hi = extrema(values)
    return (hi - lo) / binwidth + 2
end

"""
Set the limits, ticks and aspect ratio that a dot plot needs.

A dot is one bin wide along the value axis and one stack step tall along the count axis, so
the axis box has to be shaped such that those two lengths cover the same number of pixels;
otherwise the dots come out as ellipses. The shape therefore follows from `nbins` and
`nlevels` alone: giving every axis of a figure the same pair makes the axes equally large
and their dots equally big, whatever value range each of them covers.
"""
function _frame_dotplot_axis!(ax::Makie.Axis, values, binwidth, nbins, nlevels::Int)
    centre = Statistics.middle(values)
    halfwidth = nbins * binwidth / 2
    Makie.xlims!(ax, centre - halfwidth, centre + halfwidth)
    Makie.ylims!(ax, 0, nlevels)
    ax.yticks = _dotplot_stack_ticks(nlevels - 1)
    ax.aspect = Makie.AxisAspect(nbins / nlevels)
    return ax
end

"""
    FlexiChains.Makie.dotplot(
        chn::FC.FlexiChain[, param_or_params];
        nquantiles::Int=50,
        binwidth::Union{Nothing,Real}=nothing,
        pool_chains::Bool=false,
        kwargs...,
    )

Create quantile dot plots for the specified parameters in the chain.

Each parameter is summarised by `nquantiles` dots placed at evenly spaced quantiles of the
posterior, so that every dot stands for the same amount of probability mass (`1 /
nquantiles`).

The default for several chains is that the quantile dots are coloured to indicate the chain.

$(FC.PlotUtils._PARAM_DOCSTRING("FlexiChains.Makie.dotplot"))

# Keyword arguments

- `nquantiles::Int`: number of dots drawn for each chain. Defaults to `50`.

- `binwidth::Union{Nothing,Real}`: width of the bins that dots are stacked into, in the
  units of the data. The default creates roughly `sqrt(2π * ndots)` bins in the data range.

- `pool_chains::Bool`: whether to pool data from all chains into a single set of dots, or to
  compute the dots for each chain separately. Defaults to `false`.

$(MAKIE_KWARGS_DOCSTRING)
"""
function FC.Makie.dotplot(
    chn::FC.FlexiChain,
    param_or_params=FC.Parameter.(FC.parameters(chn));
    nquantiles::Int=50,
    binwidth::Union{Nothing,Real}=nothing,
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
    nrows, ncols, fig = setup_figure_and_layout(length(keys_to_plot), 1, layout, figure)
    # First horizontal, then vertical
    indices = Iterators.product(1:ncols, 1:nrows)
    panels = map(zip(indices, keys_to_plot)) do ((col, row), k)
        kstr = FC.PlotUtils.get_plot_param_name(k, plot_names)
        ax = Makie.Axis(fig[row, col]; _default_dotplot_axis()..., title=kstr, axis...)
        d = FC.PlotUtils.FlexiChainDotplot(chn, k, pool_chains, nquantiles)
        (; ax, _draw_dotplot!(ax, d, binwidth; kwargs...)...)
    end
    # One shape for all panels, so that they are equally large and their dots equally big.
    nbins = maximum(panel -> panel.nbins, panels)
    nlevels = maximum(panel -> panel.nlevels, panels)
    for panel in panels
        _frame_dotplot_axis!(panel.ax, panel.locations, panel.binwidth, nbins, nlevels)
    end
    a, p = panels[end].ax, panels[end].plot
    if !pool_chains
        colors = map(p -> p.color[], a.scene.plots[1:FC.nchains(chn)])
        maybe_add_legend(fig, chn, colors, legend_position; legend...)
    end
    return Makie.FigureAxisPlot(fig, a, p)
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
    binwidth::Union{Nothing,Real}=nothing,
    kwargs...,
)
    panel = _draw_dotplot!(ax, d, binwidth; kwargs...)
    _frame_dotplot_axis!(ax, panel.locations, panel.binwidth, panel.nbins, panel.nlevels)
    return Makie.AxisPlot(ax, panel.plot)
end

"""
Draw the dots of `d` into `ax` and return them together with the geometry that
`_frame_dotplot_axis!` needs.
"""
function _draw_dotplot!(
    ax::Makie.Axis,
    d::FC.PlotUtils.FlexiChainDotplot,
    binwidth;
    kwargs...,
)
    locations, levels, chains, bw = _dotplot_coordinates(d, binwidth)
    nchains = d.pool_chains ? 1 : FC.nchains(d.chn)
    colors = determine_chain_colors(nchains, NamedTuple(kwargs))
    labels = if d.pool_chains
        ["pooled"]
    else
        map(cidx -> "chain $cidx", FC.chain_indices(d.chn))
    end
    p = nothing
    for j in 1:nchains
        dots = findall(==(j), chains)
        p = Makie.scatter!(
            ax,
            locations[dots],
            levels[dots];
            markerspace=:data,
            markersize=Makie.Vec2f(bw, 1),
            label=labels[j],
            kwargs...,
            color=colors[j],
        )
    end
    return (;
        plot=p,
        locations,
        binwidth=bw,
        nbins=_dotplot_nbins(locations, bw),
        nlevels=maximum(levels) + 1,
    )
end
