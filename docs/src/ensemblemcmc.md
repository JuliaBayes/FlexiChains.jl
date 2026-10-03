# EnsembleMCMC.jl

[`FlexiChains.from_ensemblemcmc`](@ref) converts results from
[`EnsembleMCMC.sample!`](https://juliabayes.org/EnsembleMCMC.jl/api/) without
pooling walkers or losing sweep order.

```@example ensemble
using FlexiChains, EnsembleMCMC, Random123

initial = [-1.0 0 1 0; 0 -1 0 1]
state = initialize(Philox4x((42, 1)), x -> -sum(abs2, x) / 2, initial;
                   walker_ids=[11, 23, 37, 41])
step!(state, 100)
draws = sample!(state, 20)
chain = FlexiChains.from_ensemblemcmc(draws; iter_indices=101:120)
size(chain) # 20 sweeps, one ensemble
```

The `:positions` parameter is a coordinate-by-walker matrix for each sweep.
Stacking these matrices exposes named iteration, chain, coordinate, and walker
dimensions. Walker labels preserve the sampler's `walker_ids`.

```@example ensemble
positions = chain[:positions, stack=true]
size(positions) # (20, 1, 2, 4)
positions[walker=At(23)] # one walker's trajectory
```

Pass one name per coordinate to get separate walker-valued parameters:

```@example ensemble
named = FlexiChains.from_ensemblemcmc(draws; param_names=[:alpha, :beta])
named[:alpha, stack=true][walker=At(23)]
named[@varname(alpha[2])] # second walker (ID 23)
```

The extras `:log_density` and `:accepted` retain a value per walker per sweep.
The extra `:move_index` retains one value per sweep.

Positions, log densities, and acceptance flags share storage with `draws`.
Mutations through either object affect the other. Use `stack=false` to access
the stored views; `stack=true` materializes an array. Conversion still allocates
containers and copies labels and scalar move indices. Use `deepcopy(chain)`
when an independent copy is needed.

The chain uses `VarName` keys, so both whole-parameter symbol access and
component indexing work. Component indices refer to array positions, not walker IDs.

Pass multiple results as `FlexiChains.from_ensemblemcmc(draws1, draws2)` to
represent **independent ensemble runs** as separate chains. Their shapes and
ordered walker IDs must match. Do not pass successive chunks of the same run
as separate chains. Each run must contain at least one sweep, since an empty
chain cannot retain the dimensions of its array-valued draws.

!!! warning "Diagnostics and pooling"
    Walkers within one ensemble are not independent chains. This conversion
    preserves them as components of the ensemble state, not as chain indices.
    Ordinary summaries and diagnostics operate on coordinate/walker components;
    they do not describe a pooled posterior estimator. This extension adds no
    automatic pooling or ensemble-specific ESS, MCSE, or convergence diagnostics.

## API

```@autodocs
Modules = [Base.get_extension(FlexiChains, :FlexiChainsEnsembleMCMCExt)]
```
