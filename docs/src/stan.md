# [Stan](@id integrations-stan)

## From CSV files

FlexiChains has a function to read in chains stored in Stan CSV format:

```@docs
FlexiChains.from_stan_csv
```

This of course assumes that you already have the CSV files on disk somewhere, e.g. if you have run Stan externally.

## StanSample.jl

If you are using [StanSample.jl](https://github.com/StanJulia/StanSample.jl) you can also read data directly from a `SampleModel` once you have sampled with it.

!!! note

    This code block is not run, as running it would necessitate setting up CmdStan on GitHub runners.

```julia
using StanSample, FlexiChains

sm = SampleModel(args...)
# Note: this mutates `sm` -- StanSample has a rather unconventional interface
stan_sample(sm; data)

chn = FlexiChains.from_stansample(sm)
```

By default, both `from_stansample` and `from_stan_csv` return a `FlexiChain{Symbol}`, where each column of the CSV is a separate key (e.g. `Symbol("theta.1")`).
If you want `VarName` keys, or want to group array-valued parameters back together, you can pass a `key_spec` tuple as the last argument.
This works in exactly the same way as for [the `FlexiChain` from-array constructor](@ref arrays) and [the MCMCChains converter](@ref integrations-mcmcchains).
Note that `key_spec` must also cover the sampler columns that Stan writes first:

```julia
using FlexiChains: Parameter, Extra, @vn

key_spec = (
    Extra(:lp),
    Extra(:accept_stat),
    Extra(:stepsize),
    Extra(:treedepth),
    Extra(:n_leapfrog),
    Extra(:divergent),
    Extra(:energy),
    Parameter(@vn(theta)) => (8,),
    Parameter(@vn(mu)),
    Parameter(@vn(tau)),
)

chn = FlexiChains.from_stansample(sm, key_spec)
```

```@docs
FlexiChains.from_stansample
```

If you are using [BridgeStan.jl](https://roualdes.us/bridgestan/latest/languages/julia.html) and/or [StanLogDensityProblems.jl](https://sethaxen.github.io/StanLogDensityProblems.jl/stable/) plus a native Julia sampler, you should check whether there is an integration for the sampler in question.
For example if you use AdvancedHMC.jl then you can pass the `chain_type=FlexiChain{Symbol}` keyword argument (see [above](@ref integrations-advancedhmc)).

(If the sampler in question does *not* have an integration with FlexiChains, please feel free to open an issue!)
