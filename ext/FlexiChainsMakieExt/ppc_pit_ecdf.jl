function _pit_ecdf_annotation(pvalue, alpha)
    return "p = $(round(pvalue; sigdigits=2)) (α = $(round(alpha; sigdigits=2)))"
end

function _plot_ppc_pit_ecdf!(ax::Makie.Axis, check; kwargs...)
    Makie.hlines!(ax, 0; color=:gray, linestyle=:dash)
    p = Makie.stairs!(
        ax,
        [0; check.sorted_pit; 1],
        [0; check.ecdf_difference; 0];
        step=:post,
        kwargs...,
    )
    if !isempty(check.flagged)
        Makie.scatter!(
            ax,
            check.sorted_pit[check.flagged],
            check.ecdf_difference[check.flagged];
            color=:red,
        )
    end
    Makie.text!(
        ax,
        0,
        1;
        text=_pit_ecdf_annotation(check.pvalue, check.alpha),
        space=:relative,
        align=(:left, :top),
        offset=(8, -8),
    )
    return Makie.AxisPlot(ax, p)
end

function _ppc_pit_ecdf_figure(check; figure=(;), axis=(;), kwargs...)
    fig = isempty(figure) ? Figure() : Figure(; figure...)
    ax = Makie.Axis(
        fig[1, 1];
        xlabel="PIT",
        ylabel="ECDF difference",
        limits=(nothing, (-check.ylimit, check.ylimit)),
        axis...,
    )
    _, p = _plot_ppc_pit_ecdf!(ax, check; kwargs...)
    return Makie.FigureAxisPlot(fig, ax, p)
end

"""
    FlexiChains.Makie.ppc_pit_ecdf(
        chn, param, observed;
        prob=0.99, rng=Random.default_rng(), figure=(;), axis=(;), kwargs...
    )
    FlexiChains.Makie.ppc_pit_ecdf(pit_values; prob=0.99, figure=(;), axis=(;), kwargs...)

Calibration check via the PIT ECDF difference. `param` names one array-valued variable
holding predictive draws, and `observed` holds one observation per component of `param`.
The PIT value of an observation is the fraction of pooled predictive draws that fall below
it. The plot shows the empirical CDF of the PIT values minus the uniform CDF, which is flat
at zero for a calibrated model.

A uniformity test that remains valid when the PIT values depend on each other (Tesso and
Vehtari, 2026, [arXiv:2603.02928](https://arxiv.org/abs/2603.02928)) is run on the PIT
values. Its p-value is annotated together with the threshold `1 - prob`. When the p-value
is below the threshold, every PIT value that contributes to the rejection is marked with a
red dot.

The uniformity test is chosen from the element types of the data: the test for continuous
outcomes when neither the predictive draws nor `observed` are integer-valued, and the
rank-based test for discrete outcomes when both are. An `ArgumentError` is thrown when only
one of them is integer-valued.

PIT values computed elsewhere, such as LOO-PIT values, can be passed directly as
`pit_values`. They are treated as coming from continuous outcomes.

The uniformity test is undefined for PIT values of exactly 0 or 1, which arise when an
observation lies outside the range of all its predictive draws. Such values throw an
`ArgumentError` listing the observations concerned.

# Keyword arguments
- `prob`: probability level of the uniformity test, strictly between 0 and 1. Defaults to
  `0.99`.
- `rng`: random number generator that breaks ties between predictive draws and
  observations. The result does not depend on it when there are no ties.
- `figure`, `axis`: `NamedTuple`s forwarded to `Makie.Figure` / `Makie.Axis`. The default
  y-limits are symmetric and wide enough that chance-level deviations look small; pass
  `limits` in `axis` to override them.

All other keyword arguments are forwarded to the `Makie.stairs!` call that draws the ECDF
difference.
"""
function FC.Makie.ppc_pit_ecdf(
    chn::FC.FlexiChain,
    param,
    observed;
    prob=0.99,
    rng=Random.default_rng(),
    kwargs...,
)
    check = FC.PlotUtils.pit_ecdf_check(rng, chn, param, observed, prob)
    return _ppc_pit_ecdf_figure(check; kwargs...)
end
function FC.Makie.ppc_pit_ecdf(pit_values::AbstractVector{<:Real}; prob=0.99, kwargs...)
    return _ppc_pit_ecdf_figure(FC.PlotUtils.pit_ecdf_check(pit_values, prob); kwargs...)
end

function FC.Makie.ppc_pit_ecdf!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param,
    observed;
    prob=0.99,
    rng=Random.default_rng(),
    kwargs...,
)
    check = FC.PlotUtils.pit_ecdf_check(rng, chn, param, observed, prob)
    return _plot_ppc_pit_ecdf!(ax, check; kwargs...)
end
function FC.Makie.ppc_pit_ecdf!(
    ax::Makie.Axis,
    pit_values::AbstractVector{<:Real};
    prob=0.99,
    kwargs...,
)
    return _plot_ppc_pit_ecdf!(ax, FC.PlotUtils.pit_ecdf_check(pit_values, prob); kwargs...)
end

function FC.Makie.ppc_pit_ecdf!(chn::FC.FlexiChain, param, observed; kwargs...)
    return FC.Makie.ppc_pit_ecdf!(Makie.current_axis(), chn, param, observed; kwargs...)
end
function FC.Makie.ppc_pit_ecdf!(pit_values::AbstractVector{<:Real}; kwargs...)
    return FC.Makie.ppc_pit_ecdf!(Makie.current_axis(), pit_values; kwargs...)
end
