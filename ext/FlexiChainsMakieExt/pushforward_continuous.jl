# No title: pushforward_continuous plots an array variable as a whole, not a single leaf.
_default_pushforward_continuous_axis() = (xlabel="index", ylabel="value")

"""
    FlexiChains.Makie.pushforward_continuous(chn, param_or_params; x_grid=nothing; kwargs...)

Plot the marginal posterior of each component of an array parameter as a quantile ribbon,
forming a "function envelope" over `x_grid`. Useful for visualising how a functional
quantity (e.g. a fitted curve or spectrum) varies with posterior uncertainty.

This is a port of [Michael Betancourt's
`plot_conn_pushforward_quantiles`](https://github.com/betanalpha/mcmc_visualization_tools).

# Keyword arguments
- `x_grid`: the x-values to plot against. Defaults to `1:N`, where `N` is the number of
  components being plotted.
- `levels`: vector of interval masses in `(0, 1)`, e.g. `0.95` for the central 95% interval.
  One nested band is drawn per level. Defaults to `$(FC.PlotUtils.DEFAULT_LEVELS)`.
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`.
"""
function FC.Makie.pushforward_continuous(
    chn::FC.FlexiChain,
    param;
    figure=(;),
    axis=(;),
    kwargs...,
)
    fig = isempty(figure) ? Figure() : Figure(; figure...)
    ax = Makie.Axis(fig[1, 1]; _default_pushforward_continuous_axis()..., axis...)
    _, p = FC.Makie.pushforward_continuous!(ax, chn, param; kwargs...)
    return Makie.FigureAxisPlot(fig, ax, p)
end

function FC.Makie.pushforward_continuous!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param;
    x_grid,
    levels=FC.PlotUtils.DEFAULT_LEVELS,
    color=Makie.Cycled(1),
    kwargs...,
)
    sorted_levels, probs = FC.PlotUtils.levels_to_quantile_probs(levels)
    n_bands = length(sorted_levels)
    sub, _ = FC.PlotUtils.subset_and_split_chain(chn, param)
    ks = collect(keys(sub))
    isempty(ks) && throw(ArgumentError("no parameters to plot"))
    for k in ks
        FC.PlotUtils.check_eltype_is_real(FC.PlotUtils._get_raw_data(sub, k))
    end

    n = length(ks)
    if length(x_grid) != n
        throw(
            ArgumentError(
                "connquantile: length of `x_grid` ($(length(x_grid))) must match number of components ($n)",
            ),
        )
    end

    qs = FC.PlotUtils.chain_quantile_bands(sub, probs)

    for i in 1:n_bands
        Makie.band!(
            ax,
            x_grid,
            qs[i, :],
            qs[end+1-i, :];
            alpha=FC.PlotUtils.band_alpha(i, n_bands),
            color=color,
            kwargs...,
        )
    end
    p = Makie.lines!(ax, x_grid, qs[n_bands+1, :]; color=color, linewidth=2)

    return Makie.AxisPlot(ax, p)
end

function FC.Makie.pushforward_continuous!(chn::FC.FlexiChain, param; kwargs...)
    return FC.Makie.pushforward_continuous!(Makie.current_axis(), chn, param; kwargs...)
end
