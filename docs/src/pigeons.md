# [Pigeons.jl](@id integrations-pigeons)

[Documentation for Pigeons.jl ↗](https://pigeons.run)

Pigeons.jl is a package that provides algorithms such as parallel tempering for challenging posterior distributions.
FlexiChains provides a function, [`FlexiChains.from_pigeons`](@ref), to convert a `Pigeons.PT` object into a `FlexiChain`.
This works with any model that Pigeons supports, including DynamicPPL models and others.

## Turing.jl models

!!! warning "Versions and compatibility"

    There are a few tricky things to be aware of here.

    **Firstly, if you are using Turing with FlexiChains, it's very likely that you are using FlexiChains v0.6.**
    You should check this by inspecting your Project.toml or Manifest.toml: if this is indeed the case, please refer to [the v0.6 documentation](https://juliabayes.org/FlexiChains.jl/v0.6/pigeons).

    Secondly, although Pigeons has had a compatibility patch for DynamicPPL 0.41/0.42 merged, this has not yet been released.
    To work around this, you can use the main branch of Pigeons.jl directly.

!!! note "Must load DifferentiationInterface"

    Note that Pigeons' DynamicPPL extension requires DifferentiationInterface as one of its triggers.
    DI used to be a hard dependency of DynamicPPL, so this used to always be loaded, but [since DynamicPPL v0.42 it is no longer a dependency](https://github.com/TuringLang/DynamicPPL.jl/pull/1363).
    This means that you must explicitly load DI to use the Pigeons extension, even though we don't call any of its functions directly.

The following example uses a Turing model as the log-density function (the exact model is modified slightly from the [Pigeons docs](https://pigeons.run/stable/input-turing/)):

```@example pigeons
using Pigeons, FlexiChains, Distributions
import DifferentiationInterface
using DynamicPPL: @model, @varname, filldist

@model function my_turing_model(n_trials, n_successes)
    p ~ filldist(Uniform(0, 1), 1, 2)
    n_successes ~ Binomial(n_trials, prod(p))
    return n_successes
end
```

When sampling, you have to specify `record=[traces]` so that the actual samples are stored in the returned `Pigeons.PT` struct.
This object can then be converted to a `FlexiChain{AbstractPPL.VarName}`.

```@example pigeons
my_turing_target = TuringLogPotential(my_turing_model(100, 50))
pt = pigeons(; target=my_turing_target, record=[traces])
chn = FlexiChains.from_pigeons(pt)
```

!!! note

    Technically, it's stored as a lazy reshape/view of a 1 × 2 matrix.
    This is because of performance optimisations in Bijectors.jl and DynamicPPL, which avoid materialising the actual matrix unless really needed.
    If for any reason you want to materialise it, you can use [`FlexiChains.transform_values`](@ref modifying-values) to apply `collect` to each sample:

    ```@example pigeons
    chn2 = FlexiChains.transform_values(chn, @varname(p) => collect)
    ```

## Other models

Sampling with other models also works, and will return a `VNChain` (i.e., `FlexiChain{VarNames.VarName}`).
Here is another example lifted from the [Pigeons docs](https://pigeons.run/stable/input-julia), where a custom log-density function is used.

```@example pigeons
using Random

struct MyLogPotential
    n_trials::Int
    n_successes::Int
end
function (log_potential::MyLogPotential)(x)
    p1, p2 = x
    ((0 < p1 < 1) && (0 < p2 < 1)) || return -Inf
    logpdf(Binomial(log_potential.n_trials, p1 * p2), log_potential.n_successes)
end
Pigeons.initialization(::MyLogPotential, ::Random.AbstractRNG, ::Int) = [0.5, 0.5]
pt = pigeons(;
    target=MyLogPotential(100, 50),
    reference=MyLogPotential(0, 0),
    record=[traces],
)
```

By default, `from_pigeons` will return a `VNChain` with a single vector-valued parameter, `@vn(param)`:

```@example pigeons
chn = FlexiChains.from_pigeons(pt)
```

## Docstrings

```@docs
FlexiChains.from_pigeons
```
