# What's in a FlexiChain?

A `FlexiChain{T}`, at its core, is a wrapper around a dictionary which maps *keys* to *matrices* of size (`niters x nchains`).

Let's start by setting up an example `FlexiChain`.
Don't worry too much about the code to generate it; the important part is the object that is created.

```@example datastructure
using FlexiChains: FlexiChains, FlexiChain, VarName, @varname, Parameter, Extra

N_iters, N_chains = 100, 3
values = Dict(
    Parameter(@varname(x)) => rand(N_iters, N_chains),
    Parameter(@varname(y)) => rand(1:5, N_iters, N_chains),
    Parameter(@varname(z)) => [randn(2) for _ in 1:N_iters, _ in 1:N_chains],
    Extra(:something) => rand(N_iters, N_chains),
)
chain = FlexiChain{VarName}(N_iters, N_chains, values)
```

## Keys: parameters and extras

Each key in a chain can be either a [`Parameter{<:T}`](@ref FlexiChains.Parameter) or an [`Extra`](@ref FlexiChains.Extra).
Each `Parameter` or `Extra` itself carries a *name*, which can be retrieved with [`FlexiChains.get_name`](@ref).
For a `Parameter{T}`, the name must be a `T`.
For an `Extra`, the name must be a `Symbol`, regardless of the parameter key type.

You can list all keys, all parameters, or all extras:

```@example datastructure
keys(chain)
```

```@example datastructure
FlexiChains.parameters(chain)
```

```@example datastructure
FlexiChains.extras(chain)
```

## Values: matrices

Because each key maps to a different matrix, FlexiChains can store values of different types and sizes.

For example, `x` is stored as `Float64`, and `z` as a `Vector{Float64}`.
Indexing into a chain returns an `niters x nchains` matrix of these samples:

```@example datastructure
chain[@varname(x)]
```

```@example datastructure
chain[@varname(z)]
```

To obtain the number of iterations or chains, you can use [`FlexiChains.niters`](@ref) and [`FlexiChains.nchains`](@ref):

```@example datastructure
FlexiChains.niters(chain), FlexiChains.nchains(chain)
```

Alternatively, `size(chain)` returns `(niters, nchains)`:

```@example datastructure
size(chain)
```

Notice that there is no measure of the *number of parameters*.
Unlike other chains packages, such as MCMCChains.jl, FlexiChains does not have a third 'parameter axis'.
If you want to get such a number, you can use `length(keys(chain))` or `length(FlexiChains.parameters(chain))`.
