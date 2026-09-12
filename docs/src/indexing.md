# [Indexing](@id indexing)

A `FlexiChain` stores data in a  _rich_ format: instead of just storing a raw matrix of data, it also includes information about the iteration numbers and chain numbers.

Additionally, `FlexiSummary` objects (which you get when performing any kind of summarisation on a chain, e.g. with [`summarystats`](@ref)) also sometimes store information about which summary functions were applied (especially when there are multiple of these).

This information is used when constructing the `DimensionalData.DimArray` outputs that you see when indexing into a `FlexiChain` or `FlexiSummary` object.
But, on top of this, it also allows you to more surgically index into these objects using this information.

This page first begins with some illustrative examples, which might be the clearest way to demonstrate the indexing behaviour.
If you prefer reading a fuller specification, the sections below that describe the exact behaviour in more detail.

## Examples: chains

Let's first set up a chain.
We'll use a chain sampled from the prior, but to make it look more interesting we'll drop the first 100 iterations (mimicking MCMC warmup).

```@example 1
using FlexiChains, DynamicPPL, Distributions, LinearAlgebra

@model function f()
    x ~ MvNormal(zeros(2), I)
end

chn = FlexiChains._make_prior_chain(f(), 105, 2)
chn = chn[iter=101:End]  # drop the first 100 iterations
```

Notice how the iteration numbers in the resulting chain start from 101, not 1.

```@example 1
# Picking out a single parameter; this returns a `DimMatrix`.
chn[@varname(x)]
```

When indexing with plain integer indices, these refer to the _entries_ in the chain, not the iteration numbers.

```@example 1
# This picks out the first of the iterations (note: this has iteration number 101)
chn[@varname(x), iter=1]
```

!!! warning "Keyword arguments to `getindex`"

    Note that keyword arguments when indexing with square brackets must be separated from positional arguments by a comma. Using a semicolon will lead to an error.

```@example 1
# You can also select a specific chain
chn[@varname(x), iter=1, chain=2]
```

```@example 1
# This picks out iteration number 101
chn[@varname(x), iter=At(101)]
```

```@example 1
# This picks out iteration numbers 101 through 103
chn[@varname(x), iter=101..103]
```

```@example 1
# If you only want the first element of `x`:
chn[@varname(x[1])]
```

```@example 1
# You can specify a vector of parameters
chn[[@varname(x[1]), :logjoint]]
```

This last one returns a `FlexiChain` object, because multiple keys were specified.
The data that we didn't care for, such as `@varname(x[2])`, are simply dropped.

Notice that this also gives us a way to 'flatten' a `FlexiChain` object such that all of its keys point to scalar values.
We just need to find a full set of sub-`VarName`s, like the following.
In practice you don't need to construct this set yourself: FlexiChains has an internal function, called `_split_varnames`, that will do this for you.

```@example 1
chn[[@varname(x[1]), @varname(x[2])]]
```

## Examples: summaries

Calling any summary function such as `mean`, `std`, or `summarystats` on a `FlexiChain` object will return a `FlexiSummary` object.

```@example 1
sm = summarystats(chn)
```

Notice two things:

 1. This summary no longer has `iter` or `chain` dimensions, because the summary statistics have been calculated over all iterations and chains. However, it has a `stat` dimension, which we will need to use when accessing the data.
 2. The variable `x` has been broken up for you into its components `x[1]` and `x[2]`.

Indexing is very similar as for chains, but there is an additional `stat` dimension which lets you specify which summary statistic you want to access.

```@example 1
sm[@varname(x[1]), stat=:mean]
```

!!! note "Named statistic shorthand"

    Passing a `Symbol` to `stat` is shorthand for a named lookup: `stat=:mean` is
    equivalent to `stat=At(:mean)`. Other selectors follow DimensionalData.jl's usual
    behaviour; for example, `stat=1` selects the first statistic by position.

If only a single summary function was applied, e.g. via `mean(chn)`, then the `stat` dimension will be automatically collapsed for you; you won't need to again specify `stat` when indexing.

```@example 1
sm_mean = mean(chn)
sm_mean[@varname(x[1])]
```

If you don't want to split the VarNames up, you can specify this as a keyword argument.

```@example 1
sm_mean_nosplit = mean(chn; split_varnames=false)
sm_mean_nosplit[@varname(x)]
```

If you collapse only over iterations (for example), then you can specify the `chain` keyword argument (and likewise for `iter` if you collapse over chains).

```@example 1
sm_iter = mean(chn; dims=:iter)
sm_iter[@varname(x[1]), chain=2]
```

## Positional arguments

When indexing into a `FlexiChain` (or `FlexiSummary`) object, you can use one optional positional argument.
This positional argument can either be an object pointing to a single key, in which case a `DimMatrix` is returned; or it can be an object pointing to multiple keys, in which case a `FlexiChain` (or `FlexiSummary`) is returned.

To specify a single key, you can use:

  - a parameter name (e.g. for a `FlexiChain{T}`, an object of type `T`);
  - a `VarName` or sub-`VarName`, for a `FlexiChain{VarName}` (i.e. `VNChain`);
  - a `FlexiChains.Extra` for non-parameter keys;
  - a `Symbol`, as long as it [refers to an unambiguous key](@ref symbol-indexing);
  - a `FlexiChains.Parameter` (this is mentioned for completeness; as a user you probably don't need to do this)

On the other hand, you could specify multiple keys via:

  - a `Vector` containing any combination of the above;
  - a colon `:`, which refers to all keys in the chain or summary.

If a positional argument is not specified, it defaults to `:`.

## Keyword arguments: chains

### `iter` and `chain`

In addition to the positional argument, you can also specify the `iter` and `chain` keyword arguments when indexing into the `FlexiChain` object.
(`FlexiSummary` objects are covered right below this.)
Both of these are optional, and exist to allow you to select data from specific iterations and/or chains.

!!! warning "Keyword arguments to getindex"

    When indexing with square brackets, the keyword arguments must be separated from positional arguments by **a comma, not a semicolon** as is usual for other Julia functions.
    That is to say, you should use:

    ```julia
    chn[param, iter=iter, chain=chain]
    # this is also fine, albeit a bit wordy
    getindex(chn, param; iter=iter, chain=chain)
    ```

    rather than

    ```julia
    # this will error
    # chn[param; iter=iter, chain=chain]
    ```

The allowed values for these keyword arguments almost exactly mimic the behaviour of DimensionalData.jl.
Suppose that you sampled a chain with 100 iterations, but with a thinning factor of 2.
FlexiChains will record this information, and its iteration numbers will be `1:2:199` (i.e. 1, 3, 5, ..., 199).

For clarity, we will refer to the actual iteration numbers (1, 3, 5, ..., 199) as _iteration numbers_, and the entries in the chain (1st entry, 2nd entry, ..., 100th entry) as _entries_.

You can then specify, for example:

| `iter=...`        | Description                                                           |
|:----------------- |:--------------------------------------------------------------------- |
| `5`               | the fifth entry in the chain, i.e. iteration number 9                 |
| `At(9)`           | iteration number 9                                                    |
| `Not(5)`          | all entries except the fifth one, i.e. all iteration numbers except 9 |
| `Not(At(9))`      | all entries except iteration number 9                                 |
| `6..30`           | all iteration numbers between 6 and 30, i.e. all but the first entry  |
| `2:10`            | 2nd through 10th entries, i.e. iteration numbers 6 through 30         |
| `[At(9), At(30)]` | this will get the entries corresponding to iteration numbers 9 and 30 |
| `:`               | all entries (i.e. all iteration numbers)                              |

For convenience, FlexiChains re-exports the `DimensionalData.jl` selectors such as `Not`, `At`, and `..`.

The same applies to the `chain` keyword argument, except that here you are selecting which chains to include.
This is slightly less interesting because chains are always numbered consecutively starting from 1.
Consequently, `i` and `At(i)` have the same meaning.
Nonetheless, you can still use all the same selectors as described above, e.g. `Not(2)` to drop the second chain.

Finally, note that regular `begin` and `end` cannot be used with the `iter` and `chain` keyword arguments, because Julia's lowering pass does not handle those appropriately for keyword arguments.
In place of this you can use `Begin` and `End`, which are [semantically equivalent and re-exported from DimensionalData](@extref DimensionalData Begin-End-indexing).

```@example 1
chn[@varname(x), iter=(Begin+1):End]
```

For more information about DimensionalData's selectors, please see [their docs](@extref DimensionalData Selectors).

### `stack`

The `stack` keyword argument only affects parameters which are arrays; other parameters ignore it.

If `stack=false` (the default), then accessing an array-valued parameter will return a `DimArray` of `Array`s.
If `stack=true`, then the array-valued parameter will be stacked into a single `DimArray`.
Note that the parameter's axes will be placed at the *end* of the returned DimArray.
Thus, for example if the parameter `:x` is a `Vector{T}`, then `chn[:x]` will return a `DimArray{T,3}` with shape `(iters, chains, length(x))`.

!!! note "DimArray"

    In the current version of FlexiChains, for DimArray-valued parameters the stacking happens by default. This will be removed in a future version: you will have to explicitly specify `stack=true` to get this behaviour.

## Keyword arguments: summaries

!!! note "Positional arguments"

    The positional argument when indexing into a `FlexiSummary` objects is exactly the same as for `FlexiChain`. Only keyword arguments behave differently.

There are two differences between a `FlexiChain` and a `FlexiSummary` in terms of their indexing behaviour:

  - `FlexiSummary` objects contain one additional dimension, called `stat`.
  - `FlexiSummary` dimensions may be _collapsed_, meaning that they cannot be indexed into.

Consequently, there are three possible keyword arguments: `iter`, `chain`, and `stat`; but depending on which dimensions have been collapsed, you may not be able to use them.

### `iter` and `chain`

In general, if you apply a summary function like `mean` without specifying dimensions, then both `iter` and `chain` dimensions will be collapsed.

If you have performed the mean over a single dimension only, such as via `summary = mean(chn; dims=:iter)`, then the `iter` dimension will be collapsed, but you can still index into the `chain` dimension using `summary[key, chain=...]`.

### `stat`

In general, the `stat` dimension is generally:

  - **not collapsed** if multiple summary functions were applied, e.g. via `summarystats(chn)`;
  - **collapsed** if a single summary function was applied, e.g. via `mean(chn)`.

Unlike the `iter` and `chain` dimensions, the `stat` dimension's indices are `Symbol`s instead of numbers.
Thus, for example, if you have a summary that contains the `mean` and `std` of the chain, you could use:

| `stat=...`       | Description                          |
|:---------------- |:------------------------------------ |
| `1`              | the first statistic, i.e. `:mean`    |
| `At(:mean)`      | the `:mean` statistic                |
| `:mean`          | shorthand for `At(:mean)`            |
| `Not(At(:mean))` | everything but the `:mean` statistic |

### `stack`

The `stack` keyword argument behaves the same as for `FlexiChain` objects.
