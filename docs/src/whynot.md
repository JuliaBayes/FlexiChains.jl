# Why not FlexiChains?

Since I wrote one whole page saying why you _should_ use FlexiChains, here are the counterarguments, or at least those I can think of.

## Performance and type stability

FlexiChains uses dictionaries as its internal storage, and it is fundamentally not type stable to index into a dictionary with an abstract value type.
Consequently, the vast majority of operations in FlexiChains are not type stable.
They can sometimes also be slower than equivalent operations in MCMCChains.

Personally, I don't consider this to be important.
Chain manipulation and data access are hardly performance bottlenecks in a typical Bayesian workflow.
However, that isn't an excuse for gratuitously poor performance!
If you find an instance where FlexiChains is unbearably slow, please do open an issue.
I'm more than happy to look into it, or to suggest ways of working around it.

### For the interested reader...

Performance differences typically arise because of the different data representation.
In general, FlexiChains has a richer, more high-level, data structure, which avoids destroying information at early stages of processing.
In contrast, MCMCChains immediately flattens everything into a 3D array.

If you feed a chain back into a Turing model, e.g. with `predict`, Turing is actually much happier with the high-level, original data representation.
With MCMCChains you have to pay the cost of 'unflattening'.
That's why [FlexiChains is typically faster when interfacing with Turing models](@ref why).

Now, flattening is actually quite an expensive operation since it involves essentially reshuffling the entire chain's data in memory and is therefore `O(niters * nchains * nparams)`.
Generally the means that things that involve flat representations of data (a simple example being conversion to DataFrame) are faster with MCMCChains, because this cost has already been paid upfront.
With FlexiChains, you have to pay this cost every time you want to do something that requires a flat representation.

```@example flat
using FlexiChains: FlexiChain, Parameter
using Chairmarks, DataFrames

niter, nchain, nparam = 1000, 4, 100
d = [Dict(Parameter(:x) => randn(nparam)) for _ in 1:niter, _ in 1:nchain]
c = FlexiChain{Symbol}(niter, nchain, d)
nothing # hide
```

```@example flat
# FlexiChains
@be DataFrame(c) samples=50 evals=1
```

```@example flat
using MCMCChains
m = MCMCChains.Chains(c)

# MCMCChains
@be DataFrame(m) samples=50 evals=1
```

However, you should be aware that this is not entirely a fair comparison, and the 'flattening' part of MCMCChains _has already taken place when the chain is constructed_.
In particular, if you are doing some sampling via `sample(...; chain_type=MCMCChains.Chains)`, note that the chain construction is part of the `sample` call, and thus it will **appear** as if you are just waiting for MCMC sampling to finish, when in fact you are **also** waiting for the chain to be flattened.
(If you have noticed MCMC sampling often being stuck at 100% for a while, this is why.)

To show a fairer comparison, we can flatten the FlexiChain first.
Note that `DataFrame(c)` defers to `DataFrame(Wide(c))` (see the [Tables.jl integration section](@ref integrations-tables) for more details).
The constructor of `Wide` does the flattening for us, so if we pre-compute that, you will find that FlexiChains' performance is not so bad after all!

```@example flat
using FlexiChains: Wide
w = Wide(c)
@be DataFrame(w) samples=50 evals=1
```

## Feature set

There are still one or two more plotting and statistics functions that MCMCChains has that FlexiChains does not have yet.

(Note that this isn't entirely a drawback: there are things in FlexiChains that MCMCChains doesn't have too.)

I would be very happy to accept PRs porting some of this functionality to FlexiChains!

In the meantime, you can always [convert your FlexiChain to a `DataFrame`](@ref integrations-tables), or an [`MCMCChains.Chains`](@ref) if you really need to.
