"""
    FlexiChains.Makie.ppc_density(
        chn, param;
        observed=nothing, ndraws=50, figure=(;), axis=(;), kwargs...
    )

Predictive check via a density overlay. `param` names one array-valued variable holding
predictive draws; one kernel density curve is drawn per predictive draw, each estimated
from that draw's components. Overlaying `observed` shows whether the model reproduces the
shape of the observations.

Chains are pooled. The draws shown are selected at evenly spaced positions from the first
to the last pooled draw, so the same call always produces the same figure.

Integer-valued predictive draws throw an `ArgumentError`; use
[`pushforward_hist`](@ref FlexiChains.Makie.pushforward_hist) for discrete outcomes.

# Keyword arguments
- `observed`: vector of observations, one per component of `param`. Its kernel density is
  drawn on top as a thick black line, and a legend is added.
- `ndraws`: number of predictive draws to show. Defaults to `50`. `nothing` shows every
  pooled draw. A number larger than the number of pooled draws throws an `ArgumentError`.
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`.

All other keyword arguments are forwarded to the `Makie.lines!` calls that draw the
predictive curves.
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
    ndraws=50,
    color=Makie.Cycled(1),
    alpha=0.3,
    linewidth=1,
    kwargs...,
)
    draws = FC.PlotUtils.pooled_predictive_draws(chn, param)
    if eltype(draws) <: Integer
        throw(
            ArgumentError(
                "`ppc_density` does not support integer-valued predictive draws (got element type $(eltype(draws))); use `pushforward_hist` for discrete outcomes",
            ),
        )
    end
    npooled, ncomponents = size(draws)
    isnothing(observed) || FC.PlotUtils.check_observed_length(observed, ncomponents)

    p = nothing
    for i in FC.PlotUtils.evenly_spaced_draw_indices(npooled, ndraws)
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
