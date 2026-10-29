function _default_pushforward_discrete_axis(vertical)
    if vertical
        (; xlabel="parameter", ylabel="value")
    else
        (; xlabel="value", ylabel="parameter")
    end
end

function _plot_pushforward_discrete!(
    ax::Makie.Axis,
    sub::FC.FlexiChain;
    levels=FC.PlotUtils.DEFAULT_LEVELS,
    color=Makie.Cycled(1),
    vertical::Bool=true,
    alpha_limits=(0.15, 0.85),
    kwargs...,
)
    sorted_levels, probs = FC.PlotUtils.levels_to_quantile_probs(levels)
    n_bands = length(sorted_levels)
    n = length(keys(sub))
    qs = FC.PlotUtils.chain_quantile_bands(sub, probs)
    positions = collect(1:n)
    alphas = FC.PlotUtils.band_alpha(n_bands; alpha_limits)

    p = nothing
    for i in 1:n_bands
        p = Makie.barplot!(
            ax,
            positions,
            qs[end+1-i, :];
            fillto=qs[i, :],
            alpha=alphas[i],
            color=color,
            strokewidth=0,
            direction=vertical ? :y : :x,
            width=0.6,
            kwargs...,
        )
    end

    return Makie.AxisPlot(ax, p)
end


"""
    FlexiChains.Makie.pushforward_discrete(chn, param_or_params; vertical=true, kwargs...)

Plot each component of an array parameter as an independent quantile bar, with nested
intervals shown as stacked bands. Unlike [`pushforward_continuous`](@ref
FlexiChains.Makie.pushforward_continuous), components are not connected; each bar is separated from
its neighbours, making this appropriate when the components have no natural ordering or
functional relationship (e.g. group-level intercepts in a hierarchical model).

This function is a port of [Michael Betancourt's
`plot_disc_pushforward_quantiles`](https://github.com/betanalpha/mcmc_visualization_tools).

# Keyword arguments
- `vertical`: if `true`, bars are vertical; otherwise horizontal. Defaults to `true`.
- `levels`: vector of interval masses in `(0, 1)`, e.g. `[0.95]` for the central 95% interval.
  One nested band is drawn per level. Defaults to `$(FC.PlotUtils.DEFAULT_LEVELS)`.
- `alpha_limits`: a tuple of two values specifying the lower and upper limit of
  alpha values that the quantile ribbons should span. Values must be sorted and in `[0, 1]`.
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`.
"""
function FC.Makie.pushforward_discrete(
    chn::FC.FlexiChain,
    param;
    figure=(;),
    axis=(;),
    vertical::Bool=true,
    alpha_limits=(0.15, 0.85),
    kwargs...,
)
    fig = isempty(figure) ? Figure() : Figure(; figure...)
    ax = Makie.Axis(fig[1, 1]; _default_pushforward_discrete_axis(vertical)..., axis...)
    _, p = FC.Makie.pushforward_discrete!(ax, chn, param; vertical, kwargs...)
    return Makie.FigureAxisPlot(fig, ax, p)
end

function FC.Makie.pushforward_discrete!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param;
    vertical::Bool=true,
    alpha_limits=(0.15, 0.85),
    kwargs...,
)
    sub, plot_names = FC.PlotUtils.subset_and_split_chain(chn, param)
    ks = collect(keys(sub))
    kstrs = [FC.PlotUtils.get_plot_param_name(k, plot_names) for k in ks]
    isempty(ks) && throw(ArgumentError("no parameters to plot"))
    for k in ks
        FC.PlotUtils.check_eltype_is_real(FC.PlotUtils._get_raw_data(sub, k))
    end
    ticks = (1:length(ks), kstrs)
    if vertical
        ax.xticks = ax.xticks[] === Makie.automatic ? ticks : ax.xticks[]
    else
        ax.yticks = ax.yticks[] === Makie.automatic ? ticks : ax.yticks[]
    end
    return _plot_pushforward_discrete!(ax, sub; vertical, kwargs...)
end

function FC.Makie.pushforward_discrete!(chn::FC.FlexiChain, param; kwargs...)
    return FC.Makie.pushforward_discrete!(Makie.current_axis(), chn, param; kwargs...)
end
