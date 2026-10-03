function _default_forestplot_axis()
    return (xlabel="value",)
end

function _draw_point_and_intervals!(ax, y, color, point_val, interval_sets)
    nlevels = length(interval_sets)
    for (k, intervals) in enumerate(reverse(interval_sets))
        lw = nlevels == 1 ? 3.0 : 1.5 + 2.5 * ((k - 1) / (nlevels - 1))
        for (lo, hi) in intervals
            Makie.linesegments!(
                ax,
                [Makie.Point2f(lo, y), Makie.Point2f(hi, y)];
                color=color,
                linewidth=lw,
            )
        end
    end
    return Makie.scatter!(ax, [point_val], [y]; color=color, markersize=10)
end

####################
# Makie.forestplot #
####################

"""
    FlexiChains.Makie.forestplot(
        chn::FC.FlexiChain[, param_or_params];
        point::Symbol=:median,
        interval::Symbol=:quantile,
        hdi_method::Symbol=:unimodal,
        levels::Tuple=$(FC.PlotUtils.DEFAULT_INTERVALS),
        pool_chains::Bool=false,
        kwargs...,
    )

Create a forest (caterpillar) plot for the specified parameters in the chain. Each parameter
is shown as a point estimate with one or more credible interval bars.

$(FC.PlotUtils._PARAM_DOCSTRING("FlexiChains.Makie.forestplot"))

# Keyword arguments

- `point::Symbol`: the point estimate to use. Must be `:mean` or `:median`. Defaults to
  `:median`.

- `interval::Symbol`: the method to use for computing credible intervals. Must be
  `:quantile` or `:hdi`. Defaults to `:quantile`. Note that to use `:hdi` you must have
  PosteriorStats.jl loaded.

- `hdi_method::Symbol`: if `interval=:hdi`, the method to use for computing HDIs. Defaults to
  `:unimodal`; please see [the PosteriorStats.jl documentation](@extref PosteriorStats.hdi)
  for details.

- `levels`: a tuple of credible interval widths, e.g. `(0.5, 0.94)` for 50% and 94%
  intervals. Wider intervals are drawn with thinner lines.

- `pool_chains::Bool`: whether to pool data from all chains or plot each chain separately. Defaults to `false`.
$(MAKIE_KWARGS_DOCSTRING)
"""
function FC.Makie.forestplot(
    chn::FC.FlexiChain,
    param_or_params=FC.Parameter.(FC.parameters(chn));
    point::Symbol=:median,
    interval::Symbol=:quantile,
    hdi_method::Symbol=:unimodal,
    levels=FC.PlotUtils.DEFAULT_INTERVALS,
    pool_chains::Bool=false,
    legend_position::Symbol=:bottom,
    figure=(;),
    axis=(;),
    legend=(;),
    kwargs...,
)
    chn, plot_names = FC.PlotUtils.subset_and_split_chain(chn, param_or_params)
    keys_to_plot = keys(chn)
    isempty(keys_to_plot) && throw(ArgumentError("no parameters to plot"))
    kstrs = [FC.PlotUtils.get_plot_param_name(k, plot_names) for k in keys_to_plot]
    nparams = length(keys_to_plot)
    fig = Makie.Figure(;
        size=(
            FC.PlotUtils.DEFAULT_WIDTH,
            max(FC.PlotUtils.DEFAULT_HEIGHT, 50 * nparams + 100),
        ),
        figure...,
    )
    nchains = FC.nchains(chn)
    colors = determine_chain_colors(pool_chains ? 1 : nchains, NamedTuple(kwargs))
    a, p = FC.Makie.forestplot!(
        Makie.Axis(fig[1, 1]; _default_forestplot_axis()..., axis...),
        FC.PlotUtils.FlexiChainForest(
            chn,
            collect(keys_to_plot),
            kstrs,
            pool_chains,
            point,
            interval,
            hdi_method,
            levels,
        );
        kwargs...,
    )
    if !pool_chains
        maybe_add_legend(fig, chn, colors, legend_position; legend...)
    end
    return Makie.FigureAxisPlot(fig, a, p)
end

########################
# Single axis plotting #
########################
function FC.Makie.forestplot(
    grid::MakieGrids,
    chn::FC.FlexiChain,
    param_or_params;
    point::Symbol=:median,
    levels=FC.PlotUtils.DEFAULT_INTERVALS,
    interval::Symbol=:quantile,
    hdi_method::Symbol=:unimodal,
    pool_chains::Bool=false,
    axis=(;),
    kwargs...,
)
    chn, plot_names = FC.PlotUtils.subset_and_split_chain(chn, param_or_params)
    ks = collect(keys(chn))
    kstrs = [FC.PlotUtils.get_plot_param_name(k, plot_names) for k in ks]
    return FC.Makie.forestplot!(
        Makie.Axis(grid; _default_forestplot_axis()..., axis...),
        FC.PlotUtils.FlexiChainForest(
            chn,
            ks,
            kstrs,
            pool_chains,
            point,
            interval,
            hdi_method,
            levels,
        );
        kwargs...,
    )
end

function FC.Makie.forestplot!(
    ax::Makie.Axis,
    chn::FC.FlexiChain,
    param_or_params;
    point::Symbol=:median,
    levels=FC.PlotUtils.DEFAULT_INTERVALS,
    interval::Symbol=:quantile,
    hdi_method::Symbol=:unimodal,
    pool_chains::Bool=false,
    kwargs...,
)
    chn, plot_names = FC.PlotUtils.subset_and_split_chain(chn, param_or_params)
    ks = collect(keys(chn))
    kstrs = [FC.PlotUtils.get_plot_param_name(k, plot_names) for k in ks]
    return FC.Makie.forestplot!(
        ax,
        FC.PlotUtils.FlexiChainForest(
            chn,
            ks,
            kstrs,
            pool_chains,
            point,
            interval,
            hdi_method,
            levels,
        );
        kwargs...,
    )
end

function FC.Makie.forestplot!(chn::FC.FlexiChain, param_or_params; kwargs...)
    return FC.Makie.forestplot!(Makie.current_axis(), chn, param_or_params; kwargs...)
end

function FC.Makie.forestplot!(ax::Makie.Axis, d::FC.PlotUtils.FlexiChainForest; kwargs...)
    params = d.params
    nparams = length(params)
    nchains = FC.nchains(d.chn)
    colors = determine_chain_colors(d.pool_chains ? 1 : nchains, NamedTuple(kwargs))

    p = nothing
    function get_point(data)
        return if d.point === :median
            FC.median(data)
        elseif d.point === :mean
            FC.mean(data)
        else
            # d.point should be checked in the inner constructor
            error("d.point=$(d.point). This should not happen! Please report this bug.")
        end
    end
    function get_intervals(data, level)
        # Return a vector of (lower, upper) tuples, one for each interval to plot for
        # the given level.
        return if d.interval === :quantile
            lower, upper = FC.PlotUtils.level_to_quantile_bounds(level)
            [(FC.quantile(data, lower), FC.quantile(data, upper))]
        elseif d.interval === :hdi
            FC.PlotUtils.get_hdi_intervals(data, level, d.hdi_method)
        else
            # d.interval should be checked in the inner constructor
            error(
                "d.interval=$(d.interval). This should not happen! Please report this bug.",
            )
        end
    end
    get_all_intervals(data) = map(level -> get_intervals(data, level), d.levels)

    for (i, param) in enumerate(params)
        y_base = Float64(nparams - i + 1)
        data = FC._get_raw_data(d.chn, param)
        FC.PlotUtils.check_eltype_is_real(data)

        if d.pool_chains
            pooled = vec(data)
            p = _draw_point_and_intervals!(
                ax,
                y_base,
                only(colors),
                get_point(pooled),
                get_all_intervals(pooled),
            )
        else
            dodge_total = min(0.4, 0.15 * nchains)
            offsets =
                nchains > 1 ?
                collect(range(dodge_total / 2, -dodge_total / 2; length=nchains)) : [0.0]
            for (j, (datacol, offset)) in enumerate(zip(eachcol(data), offsets))
                col = collect(datacol)
                p = _draw_point_and_intervals!(
                    ax,
                    y_base + offset,
                    colors[j],
                    get_point(col),
                    get_all_intervals(col),
                )
            end
        end
    end
    ax.yticks = (Float64.(nparams:-1:1), d.param_names)
    Makie.ylims!(ax, 0.5, nparams + 0.5)
    return Makie.AxisPlot(ax, p)
end
