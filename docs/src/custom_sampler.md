# AbstractMCMC.jl samplers

If you have written a sampler that uses the AbstractMCMC interface, then you can get 'free' support for bundling into a `FlexiChain{VarName}` and a `FlexiChain{Symbol}` respectively by overloading [`FlexiChains.to_vnt_and_stats`](@ref) and [`FlexiChains.to_nt_and_stats`](@ref) for your sampler's transition type.

Specifically, your sampler must implement `AbstractMCMC.step`, which returns a tuple of `(transition, state)`.
The first of these two objects is what is passed to the functions above.

As a concrete example, let's use the following setup:

```@example sampler
using FlexiChains: FlexiChains, FlexiChain
using AbstractMCMC

struct M <: AbstractMCMC.AbstractModel end
struct S <: AbstractMCMC.AbstractSampler end
struct T end
function AbstractMCMC.step(rng, ::M, ::S, state=nothing; kwargs...)
    T(), nothing
end
```

Here `T` represents what AbstractMCMC calls a 'transition': it is the first return value of `AbstractMCMC.step`.
Of course, in practice, your transition will carry more information than this.

Now suppose you want to sample with this and obtain a `FlexiChain{Symbol}`.
You should then overload `to_nt_and_stats` to return a tuple of two `NamedTuple`s, the first being the parameter values, and the second being any `Extra`s to include in the chain:

```@example sampler
FlexiChains.to_nt_and_stats(::T) = ((; hello=1.0), (; world=2.0))
```

Then you can do

```@example sampler
sample(M(), S(), 10; chain_type=FlexiChain{Symbol})
```

Likewise, you can overload `to_vnt_and_stats` to obtain a `FlexiChain{VarName}`.
This must return a tuple of a `VarNames.VarNamedTuple` and a `NamedTuple`:

```@example sampler
using VarNames: VarNamedTuple, VarName
FlexiChains.to_vnt_and_stats(::T) = (VarNamedTuple(hello=1.0), (; world=2.0))
sample(M(), S(), 10; chain_type=FlexiChain{VarName})
```

## Docstrings

```@docs
FlexiChains.to_vnt_and_stats
FlexiChains.to_nt_and_stats
```
