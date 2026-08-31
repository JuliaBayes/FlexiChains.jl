rep2(vals) = repeat(vals, inner=2)

function _plot_pushforward_hist!(
    ax::Makie.Axis,
    stacked_data;  # niters x nchains x nparams
    observed=nothing,
    nbins::Integer=25,
    levels=FC.PlotUtils.DEFAULT_LEVELS,
    color=Makie.Cycled(1),
    alpha_limits=(0.15, 0.85),
    kwargs...,
)
    sorted_levels, probs = FC.PlotUtils.levels_to_quantile_probs(levels)
    n_bands = length(sorted_levels)
    edges = FC.PlotUtils.get_bin_edges(stacked_data, nbins)
    # counts is iter × chain × nbins
    counts = FC.PlotUtils.bin_count_matrices(stacked_data, edges)

    qs = Matrix{Float64}(undef, length(probs), nbins)
    alphas = FC.PlotUtils.band_alpha(n_bands; alpha_limits)

    for b in 1:nbins
        qs[:, b] = FC.PlotUtils.compute_quantile_bands(view(counts, :, :, b), probs)
    end

    xs = Float64[]
    for b in 1:(length(edges)-1)
        push!(xs, edges[b], edges[b+1])
    end

    for i in 1:n_bands
        Makie.band!(
            ax,
            xs,
            rep2(qs[i, :]),
            rep2(qs[end+1-i, :]);
            alpha=alphas[i],
            color=color,
            label="predicted",
            kwargs...,
        )
    end

    p = Makie.lines!(
        ax,
        xs,
        rep2(qs[n_bands+1, :]);
        color=color,
        label="predicted",
        linewidth=2,
    )

    if observed !== nothing
        obs = FC.PlotUtils.histogram_counts(observed, edges)
        p = Makie.lines!(
            ax,
            xs,
            rep2(Float64.(obs));
            color=:black,
            label="observed",
            linewidth=2,
        )
    end

    axislegend(ax, merge=true, unique=true)

    return Makie.AxisPlot(ax, p)
end

"""
    FlexiChains.Makie.pushforward_hist(chn, param_or_params; observed=nothing, nbins=25, kwargs...)

Plot a histogram of binned predictions with nested quantiles for posterior predictive checking.
Optionally overlay `observed` data to show to what degree the predictive distribution agrees
with the observations.

This function is a port of [Michael Betancourt's
`plot_hist_quantiles`](https://github.com/betanalpha/mcmc_visualization_tools).

# Keyword arguments
- `observed`: vector of observed values; its histogram (same bins) is overlaid as a line.
- `nbins`: number of equal-width bins. Defaults to `25`.
- `levels`: vector of interval masses in `(0, 1)`, e.g. `[0.95]` for the central 95% interval.
  One nested band is drawn per level. Defaults to `$(FC.PlotUtils.DEFAULT_LEVELS)`.
- `alpha_limits`: a tuple or vector two values specifying the lower and upper limit of
  alpha values that the quantile ribbons should span. Values must be sorted and in `[0, 1]`.
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`.
"""
function FC.Makie.pushforward_hist(
    chn::FC.FlexiChain,
    param;
    figure=(;),
    axis=(;),
    kwargs...,
)
    fig = isempty(figure) ? Figure() : Figure(; figure...)
    ax = Makie.Axis(fig[1, 1]; xlabel="value", ylabel="counts", axis...)
    _, p = FC.Makie.pushforward_hist!(ax, chn, param; kwargs...)
    return Makie.FigureAxisPlot(fig, ax, p)
end

function FC.Makie.pushforward_hist!(ax::Makie.Axis, chn::FC.FlexiChain, param; kwargs...)
    sub, _ = FC.PlotUtils.subset_and_split_chain(chn, param)
    ks = collect(keys(sub))
    isempty(ks) && throw(ArgumentError("no parameters to plot"))
    data = map(ks) do k
        d = FC.PlotUtils._get_raw_data(sub, k)
        FC.PlotUtils.check_eltype_is_real(d)
        d
    end
    stacked_data = stack(data) # niters × nchains × nparams
    return _plot_pushforward_hist!(ax, stacked_data; kwargs...)
end

function FC.Makie.pushforward_hist!(chn::FC.FlexiChain, param; kwargs...)
    return FC.Makie.pushforward_hist!(Makie.current_axis(), chn, param; kwargs...)
end
