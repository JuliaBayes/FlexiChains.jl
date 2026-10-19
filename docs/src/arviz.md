# ArviZ.jl

[Documentation for ArviZ.jl ↗](https://julia.arviz.org/ArviZ/stable/)

FlexiChains contains an extension that allows you to convert a `FlexiChain` into an `InferenceObjects.InferenceData` (InferenceObjects.jl is one of the sublibraries of ArviZ.jl, and is re-exported by ArviZ).

```@docs
InferenceObjects.convert_to_inference_data
```

For example:

```@example arviz
using InferenceObjects, FlexiChains

chn = FlexiChains.EXAMPLE_CHAIN
```

```@example arviz
idata = InferenceObjects.convert_to_inference_data(chn)
```

You can combine multiple `InferenceData` objects with `merge`.
For example, if you have a chain containing parameters and a chain containing pointwise log-likelihoods, you can merge them into a single `InferenceData` object:

```julia
llike_idata = InferenceObjects.convert_to_inference_data(llike_chn; group=:log_likelihood)

idata_merged = merge(idata, llike_idata)
```

From here you can use the full functionality of ArviZ.jl, which includes various plotting and analysis tools: please see [the ArviZ.jl documentation](https://julia.arviz.org/ArviZ/stable/) for more info.
