"""
    FlexiChains.Makie.ppc_density(
        chn, param;
        observed=nothing, n_draws=50, figure=(;), axis=(;), kwargs...
    )

Plots `n_draws` density distributions of predicted values against the `observed` values.

This check is useful to detect if the model misrepresents (part of) the data-generating process.

Chains are pooled and draws selected deterministically.

# Keyword arguments

- `observed`: values to compare predictive draws against
- `n_draws`: number of predictive draws to plot
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`.

Further keyword arguments will be forwarded to `Makie.lines!`, which is used to draw the predictive densities.
"""
function FC.Makie.ppc_density(chn::FC.FlexiChain, param; figure=(;), axis=(;), kwargs...)
    fig = isempty(figure) ? Figure() : Figure(; figure...)
    ax = Makie.Axis(fig[1, 1]; xlabel="value", ylabel="density", axis...)
    _, p = FC.Makie.ppc_density!(ax, chn, param; kwargs...)
    return Makie.FigureAxisPlot(fig, ax, p)
end

function FC.Makie.ppc_density!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param;
    observed=nothing,
    n_draws=50,
    color=Makie.Cycled(1),
    alpha=0.3,
    linewidth=1,
    kwargs...,
)
    draws = FC.PlotUtils.pooled_predictive_draws(chn, param)
    if eltype(draws) <: Integer
        throw(
            ArgumentError(
                "`ppc_density` does not support integer-valued draws, use `pushforward_hist`",
            ),
        )
    end
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
        kd = KernelDensity.kde(observed)
        p = Makie.lines!(ax, kd.x, kd.density; color=:black, linewidth=3, label="observed")
        axislegend(ax, merge=true, unique=true)
    end

    return Makie.AxisPlot(ax, p)
end

function FC.Makie.ppc_density!(chn::FC.FlexiChain, param; kwargs...)
    return FC.Makie.ppc_density!(Makie.current_axis(), chn, param; kwargs...)
end
