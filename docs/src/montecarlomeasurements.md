# [MonteCarloMeasurements.jl](@id integrations-montecarlomeasurements)

[Documentation for MonteCarloMeasurements.jl ↗](https://baggepinnen.github.io/MonteCarloMeasurements.jl/stable/)

MonteCarloMeasurements.jl is a package that lets you treat probability distributions as first-class numbers.
FlexiChains contains an extension which allows you to directly convert a `FlexiChain` into a collection of `MonteCarloMeasurements.Particles` objects, in essence creating `Particles` from the distribution which the chain represents.

```@example montecarlomeasurements
using FlexiChains

chn = FlexiChains.EXAMPLE_CHAIN
```

```@example montecarlomeasurements
using MonteCarloMeasurements: Particles

pdict = Particles(chn)
```

```@example montecarlomeasurements
# Calculates the distribution of `mu + tau` (for example).
pdict[@vn(mu)] + pdict[@vn(tau)]
```

Notice that `pdict[@vn(mu)]` can be constructed quite trivially without an extension via

```@example montecarlomeasurements
Particles(vec(chn[@vn(mu)]))
```

However, FlexiChains' extension additionally handles array- and NamedTuple-valued variables for you, such as `theta` above.

```@example montecarlomeasurements
pdict[@vn(theta)]
```

The default output is an `OrderedDict`, which is not always the most convenient type to work with.
If you prefer a `NamedTuple`, you can pass this as an argument to the constructor:

```@example montecarlomeasurements
pnt = Particles(chn, NamedTuple)
```

This can be easier to use sometimes but note that since NamedTuple keys are plain `Symbol`s this conversion might be lossy depending on your chain's parameter type.

## Unhandled parameter types

Not every parameter can be meaningfully converted into a `Particles` object.
For example, Cholesky factors (`x ~ LKJCholesky(...)`) are not supported and will error.
If you want to convert a chain that contains such a variable into a `Particles` object, subset the chain first to only include the parameters you want to convert, e.g.

```julia
Particles(chn[[param1, param2, param3]])
```

## Docstrings

```@docs
MonteCarloMeasurements.Particles
```
