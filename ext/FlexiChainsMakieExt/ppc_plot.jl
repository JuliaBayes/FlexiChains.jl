"""
    FlexiChains.Makie.ppc_plot(
        chn, param;
        observed=nothing, figure=(;), axis=(;), kwargs...
    )

Plots predictive draws of `param` against the `observed` values.

This check is useful to detect if the model misrepresents (part of) the data-generating process.

Chains are pooled before plotting. The type of plot depends on the element type of the draws:

- Real-valued draws: one kernel density curve for each of `n_draws` deterministically selected draws.
  If `observed` is given, its kernel density is overlaid in black.
- Integer-valued draws: a rootogram. For each count value, a dot marks the mean predicted frequency
  across all draws, and a narrow bar spans the central `level` quantile interval of the
  predicted frequency in the same colour. If `observed` is given, its frequencies are drawn as black squares.
  `observed` must then have an integer element type.

# Keyword arguments

- `observed`: values to compare predictive draws against
- `n_draws`: number of predictive draws to plot (real-valued draws only, default `50`); `nothing`
  plots all draws
- `level`: width of the predicted frequency interval (integer-valued draws only, default `0.95`)
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`.

Further keyword arguments are forwarded to `Makie.lines!` (real-valued draws) or `Makie.barplot!`
(integer-valued draws).
"""
function FC.Makie.ppc_plot(
    chn::FC.FlexiChain,
    param;
    observed=nothing,
    figure=(;),
    axis=(;),
    kwargs...,
)
    draws = FC.PlotUtils.pooled_predictive_draws(chn, param)
    fig = isempty(figure) ? Figure() : Figure(; figure...)
    ax = Makie.Axis(fig[1, 1]; xlabel="value", ylabel=ppc_ylabel(draws), axis...)
    p = plot_ppc!(ax, draws, observed; kwargs...)
    return Makie.FigureAxisPlot(fig, ax, p)
end

function FC.Makie.ppc_plot!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param;
    observed=nothing,
    kwargs...,
)
    draws = FC.PlotUtils.pooled_predictive_draws(chn, param)
    return Makie.AxisPlot(ax, plot_ppc!(ax, draws, observed; kwargs...))
end

function FC.Makie.ppc_plot!(chn::FC.FlexiChain, param; kwargs...)
    return FC.Makie.ppc_plot!(Makie.current_axis(), chn, param; kwargs...)
end

ppc_ylabel(::AbstractMatrix{<:Real}) = "density"
ppc_ylabel(::AbstractMatrix{<:Integer}) = "count"

function plot_ppc!(
    ax::Makie.Axis,
    draws::AbstractMatrix{<:Real},
    observed;
    n_draws=50,
    color=Makie.Cycled(1),
    alpha=0.3,
    linewidth=1,
    kwargs...,
)
    n_pooled, n_components = size(draws)
    isnothing(observed) || FC.PlotUtils.check_observed_length(observed, n_components)

    p = nothing
    n_plotted = isnothing(n_draws) ? n_pooled : min(n_draws, n_pooled)
    for i in FC.PlotUtils.evenly_spaced_draw_indices(n_pooled, n_plotted)
        kd = KernelDensity.kde(view(draws, i, :))
        p = Makie.lines!(
            ax,
            kd.x,
            kd.density;
            color=color,
            alpha=alpha,
            linewidth=linewidth,
            label="predicted",
            kwargs...,
        )
    end

    if !isnothing(observed)
        kd = KernelDensity.kde(vec(observed))
        p = Makie.lines!(ax, kd.x, kd.density; color=:black, linewidth=3, label="observed")
        axislegend(ax, merge=true, unique=true)
    end

    return p
end

function plot_ppc!(
    ax::Makie.Axis,
    draws::AbstractMatrix{<:Integer},
    observed;
    level=maximum(FC.PlotUtils.DEFAULT_INTERVALS),
    color=first(Makie.wong_colors()),
    width=0.1,
    markersize=14,
    kwargs...,
)
    if !isnothing(observed)
        eltype(observed) <: Integer || throw(
            ArgumentError(
                "`observed` must contain integers when the draws of `param` are integers; got element type $(eltype(observed))",
            ),
        )
        FC.PlotUtils.check_observed_length(observed, size(draws, 2))
    end
    count_values = rootogram_count_values(draws, observed)
    frequencies_per_value =
        eachrow(stack(StatsBase.counts(draw, count_values) for draw in eachrow(draws)))
    lower_prob = (1 - level) / 2
    mean_frequencies = map(FC.mean, frequencies_per_value)
    lower_frequencies = map(f -> FC.quantile(f, lower_prob), frequencies_per_value)
    upper_frequencies = map(f -> FC.quantile(f, 1 - lower_prob), frequencies_per_value)

    Makie.barplot!(
        ax,
        count_values,
        upper_frequencies;
        fillto=lower_frequencies,
        width=width,
        color=color,
        kwargs...,
    )
    p = Makie.scatter!(
        ax,
        count_values,
        mean_frequencies;
        color=:white,
        strokecolor=color,
        strokewidth=3,
        markersize=markersize,
        label="predicted",
    )
    if !isnothing(observed)
        p = Makie.scatter!(
            ax,
            count_values,
            StatsBase.counts(observed, count_values);
            color=:white,
            strokecolor=:black,
            strokewidth=2.5,
            marker=:rect,
            markersize=markersize - 1,
            label="observed",
        )
        axislegend(ax, merge=true, unique=true)
    end

    return p
end

function rootogram_count_values(draws, observed)
    lo, hi = extrema(draws)
    isnothing(observed) && return lo:hi
    observed_lo, observed_hi = extrema(observed)
    return min(lo, observed_lo):max(hi, observed_hi)
end
