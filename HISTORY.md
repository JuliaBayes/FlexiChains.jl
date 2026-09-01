# 0.6.38

`DimArray(::FlexiChain)` and `DimArray(::FlexiSummary)` (as well as the plain `Array` versions) now take an additional `split_varnames` keyword argument, which determines whether or not vector-valued parameters (or summary statistics) are broken up into scalar leaves.
The default is `true` which retains the existing behaviour.

# 0.6.37

Fixed a bug where `pairplot(chn)` would fail if `chn` had chains that were not 1-indexed.

# 0.6.36

Added an extension for MonteCarloMeasurements.jl which allows you to convert a `FlexiChain` into a `Particles`.

# 0.6.35

`FlexiSummary` now pretty-prints a table as long as there is at most one non-collapsed dimension.

In particular, this means that things like `mean(chn; dims=:iter)` and `mean(chn; dims=:chain)` will now pretty-print a table of means, instead of forcing the user to index into it to see the results.

# 0.6.34

Added a shorthand for `getindex` on `FlexiSummary`: `s[key, stat=:mystat]` is now equivalent to `s[key, stat=At(:mystat)]`.
(The latter still works as usual.)

# 0.6.33

Implemented `Makie.violin` on FlexiChains.

# 0.6.32

Fixed a bug where `pushforward_discrete` would override user-specified axis attributes for `xticks`, or `yticks` (depending on whether `vertical == true`), `xlabel`, and `ylabel`.

# 0.6.31

Improved the resulting key type when attempting to construct `VNChain`s from `FlexiChains.from_mcmcchains`, `FlexiChains.map_keys`, or `FlexiChains.map_parameters`.

# 0.6.30

A legend is now automatically added to the axis when using `pushforward_hist`.

The legend should be an improvement to almost all use cases, but in case it is not desired, it is possible (but not elegant) to [modify](https://github.com/JuliaBayes/FlexiChains.jl/pull/278#issuecomment-4948379988) or [delete](https://discourse.julialang.org/t/makie-how-to-remove-a-legend-from-an-axis/65876/8) the legend after having created the figure.

# 0.6.29

Fixed a bug where `FlexiChains.from_mcmcchains` would error if given Parameters with different `VarName`s (which made it very hard to convert an `MCMCChains.Chains` object to a `VNChain`, instead of the standard `SymChain`).

Improved the behaviour of `map_keys` and `map_parameters` to give better key types in the output FlexiChain.

# 0.6.28

Added a function `FlexiChains.from_mcmcchains` to convert from an `MCMCChains.Chains` object.
This supersedes the previous `FlexiChain{Symbol}(::MCMCChains.Chains)` constructor, which is now deprecated.

# 0.6.27

Added a function `FlexiChains.from_pigeons` to convert a Pigeons.jl sampling result into a `FlexiChain`.
Please see [the docs](https://juliabayes.org/FlexiChains.jl/stable/integrations/#integrations-pigeons) for more info.

# 0.6.26

Improved the default parameter names used when plotting.
When a parameter is a `DimVector` and has `Symbol` or `String` labels in its dimensions, the default plot names will now use those labels instead of generic `x[1]`, `x[2]`, etc.

# 0.6.25

Improved the error message when `transform_values` is passed an invalid output key type.

# 0.6.24

Improved performance on a number of FlexiChains functions, including the Tables.jl interface.

Fixed a bug where `Wide(::FlexiSummary; parameters_only=false)` would incorrectly yield results where the `Parameter` or `Extra` wrapper was dropped.

# 0.6.23

The plotting functions `pushforward_hist`, `pushforward_continuous`, and `pushforward_discrete` now use Makie's default figure size instead of that determined by `setup_figure_and_layout()`.

# 0.6.22

When pretty-printing a FlexiChain, the size of array-valued parameters is now shown in the summary table.

# 0.6.21

Added `FlexiChains.transform_values` which maps a function over the values stored in a `FlexiChain`, returning a new `FlexiChain` with the transformed values.
Please see [the docs](https://juliabayes.org/FlexiChains.jl/stable/modifying) for more information and example usecases.

# 0.6.20

Added Makie implementations of pushforward plots, following the examples in [Michael Betancourt's visualisation tools](https://github.com/betanalpha/mcmc_visualization_tools/).
These allow you to visualise the way in which posterior uncertainty is propagated through a function.
Full worked examples of these are given in [the docs](https://juliabayes.org/FlexiChains.jl/stable/makie/#Pushforward-plots).

# 0.6.19

Improved the internal structure of `VNChain`s constructed from `Array`s, such that `rand(chn)` returns `DynamicPPL.ParamsWithStats` or `DynamicPPL.VarNamedTuple` (but unfortunately, only if DynamicPPL is loaded, since those types are defined there).

# 0.6.18

Re-export `Begin` and `End` from DimensionalData.jl, to make indexing into FlexiChains easier.

# 0.6.17

Added the exported alias `SymChain` for `FlexiChain{Symbol}`.

# 0.6.16

Added `FlexiChains.Makie.ridgeline` and `FlexiChains.Makie.forestplot` for creating ridgeline and forest plots with a Makie backend.
Note that these functions do *not* have `FlexiChains.mridgeline` and `FlexiChains.mforestplot` aliases!

# 0.6.15

Added compatibility with OrderedCollections@2.

# 0.6.14

Added compatibility with AbstractPPL@0.15 and DynamicPPL@0.42.

# 0.6.13

Moved plotting functions into the `FlexiChains.Plots` and `FlexiChains.Makie` submodules.

What used to be called `FlexiChains.traceplot` (the Plots.jl backend) is now `FlexiChains.Plots.traceplot`, and what used to be called `FlexiChains.mtraceplot` (the Makie.jl backend) is now `FlexiChains.Makie.traceplot`.

The intention for this is to make it easier to switch between plotting backends, and to make the naming more consistent and intuitive.

The old functions are retained as aliases, but they are deprecated and will be removed in the future.

# 0.6.12

Added `Base.merge(fs1::FlexiSummary, fs2::FlexiSummary)` to merge two summaries together.

The resulting `FlexiSummary` will have keys that are the union of the keys of `fs1` and `fs2`, as well as statistics that are the union of the statistics of `fs1` and `fs2`.

In general, the value for a given key and statistic in the merged summary will be taken from `fs2` if it exists, and from `fs1` otherwise.
For key/statistic combinations that don't exist in either summary, the value will be `missing`.

For the most part, it is expected that the two summaries being merged will have either the same keys (in which case this amounts to concatenation of statistics), or the same statistics (i.e., concatenation of keys).

# 0.6.11

Added the `split_interval` keyword argument to `PosteriorStats.hdi(::FlexiChain)` and `PosteriorStats.eti(::FlexiChain)`, which allows you to specify that the returned interval should be split into its lower and upper bounds as separate statistics.

# 0.6.10

Implemented Makie-backed `FlexiChains.mmeanplot` and `FlexiChains.mautocorplot`.

# 0.6.9

Implemented `Plots.violin` for `FlexiChain`s.

# 0.6.8

Implemented a Tables.jl interface for `Wide(::FlexiSummary)`.
Unlike `Wide(::FlexiChain)`, where each parameter is given a different column, for a `FlexiSummary` each _statistic_ is given a different column, and the parameters are split up into rows.

`FlexiSummary` itself also has a default Tables.jl interface which simply delegates to `Wide`.

# 0.6.7

Add an InferenceObjects.jl extension, which allows conversion of a `FlexiChain` into an `InferenceObjects.InferenceData` via `InferenceObjects.convert_to_inference_data(chain::FlexiChain)`.

Add a method `Base.Symbol(::ParameterOrExtra)`, which converts the name of the parameter (or extra) to a `Symbol`.

# 0.6.6

Add an additional constructor to convert an array of `iters x chains x params` into a `FlexiChain`.
Please see the documentation for more information.

# 0.6.5

Minor improvements to documentation.

# 0.6.4

Extend the maximum width for the type column in the summary table.

# 0.6.3

Add a migration guide for MCMCChains users.

# 0.6.2

Implement conversion of `FlexiSummary` objects to `DimArray` and `Array`.

# 0.6.1

Add `StatsPlots.cornerplot` with Plots.jl backend.

# 0.6.0

## Breaking changes

Move FlexiChainsTuringExt to Turing itself, which will be released as part of Turing v0.45.

Note that this means that if you use FlexiChains 0.6 with Turing <= 0.44, you will get a small loss of functionality.
Specifically, `Turing.loadstate()` will not work (although `FlexiChains.last_sampler_state` will still work, and does exactly the same thing).

# 0.5.9

Support the `factorize=true` keyword argument for `DynamicPPL.pointwise_logdensities` and `PosteriorStats.loo`.

# 0.5.8

Add compatibility with DynamicPPL 0.41 and Turing 0.44.

# 0.5.7

Improve pretty-printing of `FlexiChain` and `FlexiSummary` objects.

# 0.5.6

Implemented a Tables.jl interface for FlexiChains, along with `Wide` and `Long` wrappers to control the output format.

Made the previously internal function `FlexiChains.get_name` public.
This function unwraps the `Parameter` or `Extra` wrapper from a key.

# 0.5.5

Added a new keyword argument `stack` to `getindex` on `FlexiChain`.
For array-valued parameters, `chain[key, stack=true]` will now return a stacked `DimArray` instead of a `DimArray{AbstractArray}`.
Conversely, `chain[key, stack=false]` will return a `DimArray{Array}` as before.

The same keyword argument can be used for indexing into `FlexiSummary` as well, with exactly the same implications.

The default value for `stack` is `false`, *except* for the case where the parameter is a `DimArray` of `DimArray`s, in which case the stacking happens by default, but with a deprecation warning.
In a future version this automatic stacking will be disabled, and to stack `DimArray`s you will have to explicitly set `stack=true`.

# 0.5.4

Added a method, `DimensionalData.DimArray(::FlexiChain, kwargs...)`, to convert a `FlexiChain` into a 3D `DimArray` with dimensions `(iters, chains, parameters)`.
A method for `Base.Array` has also been added, which is the same but drops the dimensional metadata.

Implemented `PosteriorStats.loo` for chains of log-likelihoods, as well as Turing.jl models.
Please see the documentation for more information about the PosteriorStats integration.

# 0.5.3

Added the `FlexiChains.rankplot` and `FlexiChains.mrankplot` functions for creating rank plots with Plots.jl and Makie.jl backends.

Also fixed a bug where `plotfunc(chn, :)` errored (for all plotting functions).

# 0.5.2

Added a method `MCMCDiagnosticTools.bfmi(chn::FlexiChain, energy_key)` to compute the Bayesian fraction of missing information (BFMI) for a chain.

# 0.5.1

Added the `divergences` and `divergences_kwargs` keyword arguments to `pairplot` to additionally superimpose a scatter plot of divergent transitions, as well as a keyword argument `args` that allows passing extra positional arguments to `pairplot`.

# 0.5.0

## Breaking changes

There are no breaking changes if you are only using `FlexiChain{VarName}` (i.e., `VNChain`).

When plotting or summarising `FlexiChain{Symbol}` and `FlexiChain{AbstractString}`, the keys will now be split up into their individual scalar-valued components, if possible.
For example, if you have a parameter `:x` which is a vector of length 3, then the keys `Symbol("x[1]")`, `Symbol("x[2]")`, and `Symbol("x[3]")` will be automatically generated and used when plotting and summarising.
Although this could arguably be called a new feature, this has been released as a breaking change in case users were relying on the old behaviour.

## New features

Implemented a PairPlots.jl extension for FlexiChains.
You can now call `pairplot(chn[, param_or_params])` to get a pair plot of the parameters in a chain.
Note that this requires PairPlots.jl as well as a Makie backend (e.g. GLMakie or CairoMakie) to be loaded.

Added methods for `AbstractMCMC.from_samples` and `AbstractMCMC.to_samples` to convert `FlexiChain{VarName}` to and from `DynamicPPL.VarNamedTuple`.

# 0.4.9

Implemented `MCMCDiagnosticTools.gelmandiag`, `MCMCDiagnosticTools.gelmandiag_multivariate`, and `MCMCDiagnosticTools.discretediag` for `FlexiChain`s.

# 0.4.8

Adds a new function `FlexiChains.from_stan_csv` to parse Stan CSV files, plus a method `FlexiChain{Symbol}(::StanSample.SampleModel)` to convert from a `SampleModel` to `FlexiChain` (if sampling has already been run on the `SampleModel`).

# 0.4.7

Allow conversion of any `FlexiChain{T}` to `MCMCChains.Chains`, as long as `Symbol(::T)` is defined.
Previously this conversion only worked for `T <: VarName`.

When indexing into a `FlexiChain{Symbol}` with a `Symbol`, FlexiChains now allows the symbol to resolve to an `Extra`, if such a key exists.
Previously this would only look up parameters.

# 0.4.6

Adds a new function, `FlexiChains.to_nt_and_stats`, which samplers can overload in order to automatically bundle samples into `FlexiChain{Symbol}`.

Also implements the above for AdvancedHMC.jl, meaning that you can define a model that satisfies the LogDensityProblems interface, sample from it with AdvancedHMC, and collect the results in a `FlexiChain{Symbol}`.

See the [integration docs page](https://juliabayes.org/FlexiChains.jl/stable/integrations) for more info.

# 0.4.5

Adds `FlexiChains.Prefixed` as a quick way to access `VarName`s that have an arbitrary prefix.

# 0.4.4

Added a new method `FlexiChain{Symbol}(::MCMCChains.Chains)` to convert a `MCMCChains.Chains` object into a `FlexiChain{Symbol}`.
(Note that, if you are sampling with Turing, this is a poorer representation of the chain: you can sample directly into a `VNChain` instead, which is a `FlexiChain{VarName}`.)

Also improved the fidelity of the conversion *to* `MCMCChains.Chains` (previously metadata like sampling times and sampler states were dropped; they will now be included).

# 0.4.3

When using `getindex` on a chain or a summary, the returned `DimArray` now has the parameter as its name.
Note that the name is stringified, so it is a lossy representation: this is because `DimensionalData` does not (publicly) allow the use of arbitrary types for array names (one can do it, but it requires overloading an internal method).

# 0.4.2

Added methods for `FlexiChains.values_at` and `FlexiChains.parameters_at` that take keyword arguments `iter` and `chain` instead of positional arguments.
If unspecified, they default to `:`, i.e., all iterations and chains.
This behaviour is designed to be consistent with that of `getindex` on FlexiChains.

The positional arguments are still supported, but will be removed in v0.5.

Fixed a few bugs in `values_at` and `parameters_at` where selectors or vectors of indices such as `[1, 2]` would fail.

# 0.4.1

Added the method `Base.rand([rng,] chn, [dims...])` to sample from a `FlexiChain`.

# 0.4.0

This is a breaking release, which is designed to add *true* support for DynamicPPL 0.40 and Turing 0.43, fixing the remaining issues that were present in FlexiChains v0.3.4.

## `values_at` and `parameters_at`

The most obvious change in this version is when using Turing.jl with FlexiChains.
If `chn` is a `VNChain` sampled from Turing,

  - `FlexiChains.values_at` will now return a `DynamicPPL.ParamsWithStats` instead of an `OrderedDict{ParameterOrExtra{<:VarName}}`.
  - `FlexiChains.parameters_at` will now return a `VarNamedTuple` instead of an `OrderedDict{VarName}`.

This is designed to maximise interoperability with other parts of DynamicPPL / Turing.
For example, it is now trivial to obtain a `VarNamedTuple` of parameters from a chain, and then re-evaluate the model at those parameters using `InitFromParams(FlexiChains.parameters_at(chn, i, j))`.
**Furthermore, by using `VarNamedTuple` as the intermediate data structure, we ensure that no loss of fidelity occurs when MCMC results are stored in a `FlexiChain`.**

## Reconstruction

`FlexiChain` now stores an extra field, `structures`, which is used to store information that converts the `OrderedDict{ParameterOrExtra,T}` data back into a richer format.

In order to do this, it introduces two new functions:

  - `FlexiChains.reconstruct_values(chn::FlexiChain{T}, i, j, structure)`
  - `FlexiChains.reconstruct_parameters(chn::FlexiChain{T}, i, j, structure)`

where `i` and `j` are the iteration and chain indices, and `structure` is the relevant entry in the `structures` field of the chain.

By default, these functions simply return an `OrderedDict` of values or parameters, which preserves old behaviour for chains that do not include any structures.
However, these functions can be overloaded to return richer data structures than `OrderedDict`.

The canonical example of this is with chains sampled from Turing.jl.
When sampling with Turing, the `structures` field of the resulting chain will contain one skeleton `VarNamedTuple` per iteration (see [the DynamicPPL documentation](https://turinglang.org/DynamicPPL.jl/stable/vnt/manipulation/) for more information about this).
When calling `FlexiChains.parameters_at(chain, i, j)`, the `reconstruct_parameters` function will use that skeleton to construct a `VarNamedTuple` of parameters, rather than an `OrderedDict`.
Likewise, when calling `FlexiChains.values_at(chain, i, j)`, the `reconstruct_values` function will use the skeleton to construct a `DynamicPPL.ParamsWithStats` of values.

**The end-result of this is that FlexiChains can fully support models where the shape or type of an array varies across iterations.**
(Note, however, that models where the shape or type changes *within* a single model evaluation are now forbidden by DynamicPPL: that is not something that can be patched by FlexiChains.)

## `to_varname_dict` -> `to_vnt_and_stats`

Previously, in the rare instance where your custom sampler returned an unusual type as the first return value of `AbstractMCMC.step`, you would have to implement `FlexiChains.to_varname_dict` to convert that type into an `OrderedDict{ParameterOrExtra{VarName}}`.
This has been replaced with `FlexiChains.to_vnt_and_stats`, which converts the type into a combination of `VarNamedTuple` (for parameters) and `NamedTuple` (for stats) instead.

Note that because `DynamicPPL.ParamsWithStats` is *exactly* a wrapper around a `VarNamedTuple` and a `NamedTuple`, you *may as well* just make your sampler return `ParamsWithStats`, and skip the faff of having to overload `to_vnt_and_stats` at all.

# 0.3.4

This patch adds compatibility for DynamicPPL 0.40 and Turing 0.43.
Specifically:

  - The signature of the `DynamicPPL.pointwise_logdensities` family of functions has been updated to match the new signature in DynamicPPL 0.40 (i.e., it no longer takes an optional `Val{whichlogprob}` argument).
  - Added an implementation of `AbstractMCMC.to_samples(::Type{ParamsWithStats}, chn, model)` (even though it is not used elsewhere in FlexiChains)

However, the user should note that this release is not *completely* compatible with DynamicPPL.
In particular, the following issues still remain.

  - `FlexiChains.parameters_at` returns an `OrderedDict{VarName}`.
    (It would ideally return a `VarNamedTuple`.)

  - Functions such as `returned` and `predict` assume that the shape of any array containing random variables is constant across all iterations.
    (DynamicPPL 0.40 already mandates that the shape of an array containing random variables does not change *within* a single model evaluation, but it is still possible for the shape to change *across* iterations.)

    For example, consider this model.

    ```julia
    @model function f()
        n ~ Poisson(5)
        x = zeros(n + 2)
        x[1] ~ Normal()
        x[2] ~ Normal()
    end
    ```

    In this model, although the shape of `x` is constant within one evaluation of the model, it can vary from iteration to iteration.
    Sampling a chain will work, but subsequently using that chain with `returned` or `predict` *may* give errors.
    (If *all* of the elements of `x` are random variables, then they will *definitely* work correctly.)

Note that these issues are also present in MCMCChains, and so none of these are reasons to avoid using FlexiChains.

These issues will be fixed in a future release of FlexiChains.
However, figuring out how to fix these is not an easy problem at all, and may take a while.
This version has therefore been released just to allow users to start using FlexiChains with the new versions of DynamicPPL and Turing.

# 0.3.3

Add compatibility for DimensionalData 0.30.

# 0.3.2

Remove the 'exported' `split_varnames` function (the function was removed in 0.2.0, but the export wasn't deleted.)

# 0.3.1

Documentation improvements only.

# 0.3.0

If a model's return value is a `DimArray`, then `returned(model, chain::VNChain)` will now stack the axes together (much like indexing into a FlexiChain).

# 0.2.2

This release contains only documentation updates.

# 0.2.1

This release introduces support for DynamicPPL v0.39 and Turing v0.42.
There are no user-facing changes, but you should see some performance improvements in functions such as `returned` and `predict`.

# 0.2.0

## Breaking changes

### `split_varnames`

`FlexiChains.split_varnames` has been removed (technically, renamed and made internal).
From a user's point of view, summarising and plotting chains will still automatically split VarNames up.
However, you cannot do this for your own chains any more.

### DynamicPPL functions like `returned`, `predict`, `logjoint`

In v0.1, FlexiChains guaranteed that if you called `split_varnames(chn)`, these functions would still work correctly on the resulting split chain.

In v0.2 this is no longer the case.
`returned` and `logjoint` will error, and `predict` will silently give wrong results.
This is the main rationale behind the removal of `split_varnames`.

In return for no longer working on split VarName chains, these functions have been made to run up to 10x faster on unsplit chains.

# 0.1.6

Implemented `InitFromParams(chain::VNChain, i, j)` to allow you to initialise sampling etc. from the `i`-th iteration of the `j`-th chain of a `VNChain`.
Please see [the documentation](https://juliabayes.org/FlexiChains.jl/stable/turing) for an example.
`i` and `j` can either be integers, or `At(...)` selectors.

# 0.1.5

Implemented `AbstractMCMC.to_chains` and `AbstractMCMC.from_chains` methods for converting `VNChain` to and from `DynamicPPL.ParamsWithStats`.
Please see the DynamicPPL documentation for more info about this.

# 0.1.4

Added some plotting methods with Makie.jl!
Please see [the docs](https://juliabayes.org/FlexiChains.jl/stable/plotting) for more information on what's available and how to use it.

# 0.1.3

Allow passing `layout` and `size` arguments to Plots.jl.

# 0.1.2

Added compatibility with DynamicPPL@0.38 and Turing@0.41.

# 0.1.1

Added extra methods to handle parameters which are `DimArray`-valued: instead of returning a `DimArray` of `DimArrays`, indexing with such a parameter now returns a stacked `DimArray`.

# 0.1.0

FlexiChains now has what I consider to be a reasonably stable core set of functionality, so I'm willing to release 0.1.0.

## Summaries

  - There is now [a dedicated page in the documentation for summaries](https://juliabayes.org/FlexiChains.jl/stable/summarising).
  - `StatsBase.mad`, `Statistics.quantile`, `StatsBase.geomean`, `StatsBase.harmmean`, and `StatsBase.iqr` have been implemented.
  - `PosteriorStats.hdi` and `PosteriorStats.eti` have been implemented in an extension.
  - The signature of functions passed to `FlexiChains.collapse` has been simplified. It used to be that the signature would differ depending on whether you were collapsing over iterations, chains, or both. Now all the function needs to do is to collapse a vector to a single value (regardless of which dimensions are being collapsed over).

# 0.0.3

## Plotting

(Some) plotting functionality has been added to FlexiChains!

Please see [the plotting docs](https://juliabayes.org/FlexiChains.jl/stable/plotting) for information.

## PosteriorDB.jl integration

You can now load a reference posterior from PosteriorDB.jl into a FlexiChain using `FlexiChains.from_posteriordb_ref`.
Please see the package documentation; an example is given there.
The key type of the resulting chain will be `String`, since PosteriorDB stores key names as strings.
(Unfortunately, there is no safe way to automatically convert these to `VarName` types.)

## `subset`

The `FlexiChains.subset()` function has been removed.
Instead of using `subset(chn, keys)` you can now use `chn[keys]`.

`FlexiChains.subset_parameters(chn)` and `FlexiChains.subset_extras(chn)` are still available.

## Equality

Fixed equality comparisons on FlexiChain and FlexiSummary (previously only the data would be compared, not the metadata).
`Base.:(==)` and `Base.isequal` now behave 'as expected'.

A new function `FlexiChains.has_same_data(chn1, chn2; strict)` has been added to compare only the data of two chains.

## Improved dictionary interface

On top of `Base.keys(chn)` and `FlexiChains.parameters(chn)`, the following functions have been added:

  - `Base.values(chn; parameters_only)`
  - `Base.pairs(chn; parameters_only)`

to extract the matrices, or key-matrix pairs, from a chain. The boolean `parameters_only` can be used to restrict the output to only parameter keys.

## `values_at` and `parameters_at`

These functions have been added to allow you to extract all values, or all parameters, at one or more iterations.
These can be extracted either as `Dict`, `NamedTuple`, or `ComponentArray` (the latter will require you to load ComponentArrays.jl first).

These functions replace what were previously called `get_dict_from_iter` and `get_parameter_from_at_iter`.

## Renaming keys

The `map_keys` and `map_parameters` functions have been introduced to allow you to rename keys in a chain if needed.

## Pointwise log probabilities

The set of DynamicPPL functions `pointwise_logdensities`, `pointwise_loglikelihoods`, and `pointwise_prior_logdensities` have been implemented for FlexiChains.
Note that these methods on FlexiChains return a FlexiChain itself, and you are not allowed to specify the output key type: it is always VarName.

## Other changes

`DynamicPPL.predict` on a FlexiChain now takes the `include_all` keyword argument, which controls whether parameter values are also included in the returned chain.
Please note that the default behaviour is different compared to MCMCChains.jl: FlexiChains by default uses `include_all=true`, whereas MCMCChains.jl uses `include_all=false`.

`vcat` now attempts to very smartly concatenate the iteration indices from two chains.
In any case, it should _always_ be that concatenating two chains will result in the iteration numbers of the second chain being higher than those of the first chain.

Fixed a bug where `hcat` and `vcat` would not preserve the order of keys in the resulting chain.

Fixed a bug where `predict` and `returned` would not work with chains that had already been split up by `VarName`s.

# 0.0.2

There are **many** breaking changes to FlexiChains.jl's interface in this release.
As the version number suggests, this is still a very early release of FlexiChains.jl, and the API is likely to change in future versions.
When the API has somewhat stabilised, the version number will be incremented to 0.1.0.

My current belief is that the core functionality of FlexiChains (base data types, indexing, and summary functions) is largely in place.
However, I would like to have some real-world battle testing before releasing 0.1.0.

The main changes in 0.0.2 are:

## DimensionalData.jl

Indexing into a FlexiChain now returns `DimensionalData.DimArray` types.

User-facing changes:

  - This is a much richer representation of the data and allows you to index into the resulting matrix with powerful selectors. To make this easier, FlexiChains re-exports all of DimensionalData's selectors.
  - The iteration and chain dimensions are now always explicitly represented, even if there is only one chain. This is probably for the better anyway since it makes the behaviour more consistent.
  - Functions such as `DynamicPPL.returned` now also return a `DimMatrix`.

Indexing into a `FlexiSummary` also returns `DimArray`s, unless all dimensions have been collapsed, in which case it just returns the single value in the array.

## Summaries

Summaries have been completely reworked.

User-facing changes:

  - `StatsBase.summarystats` provides a super-quick way to generate summary functions for an entire chain. If the chain type is VarName, this will additionally split VarNames up into their individual scalar-valued components. `summarystats` is re-exported by FlexiChains.
  - More high-level functions have been added, namely `ess`, `rhat`, and `mcse` from MCMCDiagnosticTools, as well as `Statistics.quantile`. All of these are re-exported by FlexiChains.
  - For low-level, highly customised summary functions, there is now only a single function: `FlexiChains.collapse`. This function also allows you to specify multiple summary functions of your choice.

Furthermore, if you collapse both the iteration and chain dimensions (this is the default when applying summary functions), a nice summary table will be pretty-printed in the REPL.

More internal changes:

There is only one return type, `FlexiSummary`, instead of the three different return types previously.
Indexing behaviour for `FlexiSummary` has been thoroughly designed to be as intuitive, and as similar to `FlexiChain` indexing, as possible.
Please see its docstring, as well as the built documentation, for more information.

## Indexing

In light of the DimensionalData.jl integration, as well as the new `FlexiSummary` format, indexing into chains and summaries has also been completely overhauled.
In particular, indexing can now be done with keyword arguments corresponding to the dimension names.
Furthermore, it is possible to provide a vector of keys to select multiple parameters at once (this will returns a new `FlexiChain` or `FlexiSummary` rather than the `DimArray` itself).

Please see the documentation for more information: there is one whole page dedicated to the indexing behaviour of FlexiChains.jl.

## Sizes as type parameters

The sizes of the chain and iteration dimensions are no longer type parameters of `FlexiChain`.
Instead of constructing a chain with `FlexiChain{TKey,NIter,NChains}(data)` you should now pass these as positional arguments, i.e., `FlexiChain{TKey}(NIter, NChains, data)`.
The same runtime checks are still performed.
This prevents overspecialisation of methods and leads to improved performance.

`FlexiChains.SizedMatrix` has been removed.
All underlying data is stored as raw `Array`s (2D for `FlexiChain`, 3D for `FlexiSummary`).

## Other things

The log-joint probability when sampling with Turing.jl is now stored under the key `Extra(:logjoint)` rather than `Extra(:lp)`.
This is simply to be more explicit about its meaning.

The order of keys in a `FlexiChain` is now guaranteed (and is preserved by all operations on chains).
If you want to construct a chain with a specific order of keys, you should ensure that the input data (either dict-of-arrays or array-of-dicts) can be iterated on to yield the keys in the desired order.
This is most easily done by using `OrderedCollections.OrderedDict`.
(Conversely, if the order does not matter, you can use any other `AbstractDict`.)
To reorder keys, you can index into the chain with a vector of keys in the desired order.

A `split_varnames` function has been added to split VarNames in a chain into their individual scalar components.

Small precompile workloads have been added to improve the time-to-first-chain and summary for typical Turing workflows.

Various fixes have been applied to the behaviour of `hcat`, `vcat`, and `merge`.
In particular `merge` now takes all metadata from the second argument (which mimics the behaviour of `merge` on base Julia types).

# 0.0.1

This is the initial release of FlexiChains.jl.

FlexiChains is a new package for working with Markov chains, with a particular emphasis on supporting features of Turing.jl.
As its name suggests, it is designed to be more flexible than the existing MCMCChains.jl library.
This means that, for example, vector-valued parameters are stored 'as is' without being broken up into individual indices.

This not only makes it much less clunky to work with large arrays; it also leads to performance gains (sometimes), improved compatibility with DynamicPPL.jl, and a more accurate representation of the parameters you have sampled.

Do consult [the documentation](http://juliabayes.org/FlexiChains.jl/) for more information, and please feel free to get in touch with issues or suggestions!
