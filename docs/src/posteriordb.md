# [PosteriorDB.jl](@id integrations-posteriordb)

[Documentation for PosteriorDB.jl ↗](@extref PosteriorDB :doc:`index`)

If you have loaded a `PosteriorDB.ReferencePosterior`, you can transform it into a `FlexiChain{VarName}` using [`FlexiChains.from_posteriordb`](@ref):

```@example posteriordb
using PosteriorDB, FlexiChains

pdb = PosteriorDB.database()
post = PosteriorDB.posterior(pdb, "eight_schools-eight_schools_centered")
ref = PosteriorDB.reference_posterior(post)

chn = FlexiChains.from_posteriordb(ref)
```

Array-valued parameters, which PosteriorDB stores as separate scalar entries (e.g. `theta[1]`, ..., `theta[8]`), are recombined into a single parameter:

```@example posteriordb
chn[@vn(theta), iter=1, chain=1]
```

but individual elements can still be accessed:

```@example posteriordb
chn[@vn(theta[1])]
```

You can then use all the functionality of FlexiChains on `chn`:

```@example posteriordb
summarystats(chn)
```

## Docstrings

```@docs
FlexiChains.from_posteriordb
FlexiChains.from_posteriordb_ref
```
