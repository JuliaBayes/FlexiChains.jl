# [Converting to/from arrays](@id arrays)

Many MCMC libraries return samples in the form of 3D arrays.
FlexiChains therefore provides methods to convert from and to 3D arrays, to maximise interoperability with other libraries.

FlexiChains' representation of MCMC samples is richer than a plain array: it includes parameter/extra names, extra information about the structure of each parameter, metadata, and so on.
This means that when converting _from_ an array, you need to provide some additional information.
Likewise, when converting _to_ an array, some information will inevitably be lost.
However, the conversion methods are designed to bridge this gap as far as possible.

FlexiChains works with arrays that have dimensions **`iters x chains x parameters`**.

## [Converting from arrays](@id api-fromarray)

You can use a `FlexiChain` constructor to convert a 3D array to a `FlexiChain`.
It is easiest to explain by example (the docstring, which has all the necessary detail, is at the bottom of this page).
Here is a simple example where each column in the array corresponds to a scalar parameter:

```@example fromarray
using FlexiChains: FlexiChain, Parameter, Extra

arr = rand(10, 4, 3)   # 10 iterations, 4 chains, 3 parameters
names = (Parameter(:x), Parameter(:y), Extra(:lp))  # note: must be tuple

FlexiChain{Symbol}(arr, names)
```

For convenience, this constructor also allows you to specify parameters that are array-valued, by specifying their sizes.
In this example, the last four columns of `arr` will be interpreted as a single parameter `z` that is a 2x2 matrix:

```@example fromarray
arr = rand(10, 4, 6)   # 10 iterations, 4 chains, 6 (scalar) parameters

names = (
    Parameter(:x),            # Scalar
    Parameter(:y),            # Scalar
    Parameter(:z) => (2, 2),   # Matrix
)

chn = FlexiChain{Symbol}(arr, names)
```

You can see the reshaped parameter `z` here

```@example fromarray
chn[:z, iter=1, chain=1]
```

is derived from

```@example fromarray
arr[1, 1, 3:6]
```

## [Converting to arrays](@id api-flatten)

When flattening a `FlexiChain` to an array, the structure of each parameter is lost: array-valued parameters, for example, are flattened to consecutive columns.

To retain parameter names, you can convert to a `DimArray`, which will have a `:param` dimension that stores the names:

```@example fromarray
using FlexiChains: DimArray

# Create a chain from an array, much like above.
arr = randn(10, 4, 6)   # 10 iterations, 4 chains, 6 parameters
chn = FlexiChain{Symbol}(arr, (
    Parameter(:x),            # Scalar
    Parameter(:y),            # Scalar
    Parameter(:z) => (2, 2),   # Matrix
))

# Convert it back to an array.
da = DimArray(chn)
```

This should recover the data in the original array:

```@example fromarray
da == arr
```

If the parameter names are not needed, you can convert to a plain `Array` as well.

```@example fromarray
Array(chn)
```

## Summaries

`FlexiSummary` objects can also be converted *to* arrays: depending on how many of their dimensions were collapsed, the resulting array will have different dimensions.
However, there is presently no way to convert an array into a `FlexiSummary`.

```@example fromarray
using FlexiChains: summarystats

fs = summarystats(chn)
da = DimArray(fs)
```

## Docstrings

```@docs
FlexiChains.FlexiChain(::AbstractArray{T,3}, key_spec) where {T}
DimensionalData.DimArray(::FlexiChains.FlexiChain)
DimensionalData.DimArray
Base.Array(::FlexiChains.FlexiChain)
Base.Array
```
