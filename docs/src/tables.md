# [Tables.jl](@id integrations-tables)

[Documentation for Tables.jl ↗](https://tables.juliadata.org/stable/)

FlexiChains implements a Tables.jl interface which allows you to easily convert a `FlexiChain` or `FlexiSummary` into any type that consumes tabular data, e.g., a `DataFrame`.

## Chains

In fact, FlexiChains implements *two* different Tables.jl interfaces for chains which produce wide-format and long-format tables respectively.

This is best demonstrated with our example chain.
However, we'll cut down the eight schools to just two:

```@example tables
using FlexiChains

chn = FlexiChains.transform_values(FlexiChains.EXAMPLE_CHAIN, @vn(theta) => (x -> x[1:2]))
```

### Wide format

Now we can convert this into a wide-format `DataFrame` by wrapping the chain in [`Wide`](@ref):

```@example tables
using DataFrames

DataFrame(Wide(chn))
```

Wide format is the default layout for `FlexiChain`s, so if you aren't specifying any additional keyword arguments to `Wide`, you technically don't have to wrap it at all:

```@example tables
DataFrame(chn) == DataFrame(Wide(chn))
```

### Long format

To get a long-format `DataFrame`, you can wrap the chain in [`Long`](@ref):

```@example tables
DataFrame(Long(chn))
```

Although this isn't on display here, you should be aware that this will promote parameters to a common type (most often `Float64`), because all parameter values must be stored in a single column.

Both the [`Wide`](@ref) and [`Long`](@ref) wrapper structs accept keyword arguments which determine whether array-valued parameters (like `z`) are split up, and whether or not to include the `Extra` keys in the chain as well.

## Summaries

For `FlexiSummary`, the long format is not supported: only the wide format is implemented.
In contrast to `Wide(::FlexiChain)`, where each _parameter_ is given a different column, the wide format for `FlexiSummary` splits each _statistic_ into a separate column.

```@example tables
fs = summarystats(chn)
DataFrame(Wide(fs))
```

Like for `FlexiChain`, the `Wide` wrapper is the default Tables.jl implementation for `FlexiSummary`, so you can also just do `DataFrame(fs)`.

`Wide(::FlexiSummary)` takes the same keyword arguments as `Wide(::FlexiChain)`.

!!! note "Splitting VarNames"

    Please note that the act of summarising will typically already cause array-valued variables to be split up.
    If this has already been done, then using `Wide(...; split_varnames=false)` cannot reverse this!

    ```@example tables
    w = Wide(mean(chn), split_varnames=false)
    DataFrame(w)
    ```

    Notice how `theta[1]` and `theta[2]` are already split up despite the `split_varnames=false` argument.
    If you want to prevent this, you need to specify `split_varnames=false` at the summary step as well:

    ```@example tables
    w = Wide(mean(chn; split_varnames=false), split_varnames=false)
    DataFrame(w)
    ```

## Docstrings

```@docs
Wide
Long
```
