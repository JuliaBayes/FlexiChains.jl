# [PosteriorDB.jl](@id integrations-posteriordb)

[Documentation for PosteriorDB.jl ↗](@extref PosteriorDB :doc:`index`)

FlexiChains allows you to load reference posteriors (i.e., chains sampled in Stan) from PosteriorDB.

To see a list of all available reference posteriors, use [`FlexiChains.available_posteriordb_references`](@ref):

```@example posteriordb
using PosteriorDB, FlexiChains

FlexiChains.available_posteriordb_references()
```

To load a reference posterior, use [`FlexiChains.from_posteriordb`](@ref):

```@example posteriordb
chn = FlexiChains.from_posteriordb("eight_schools-eight_schools_centered")
```

Vector-valued parameters, which PosteriorDB stores as separate scalar entries (e.g. `theta[1]`, ..., `theta[8]`), are recombined into a single parameter:

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
FlexiChains.available_posteriordb_references
```
