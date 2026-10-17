# [Turing.jl](@id integrations-turing)

[Documentation for Turing.jl ↗](https://turinglang.org/docs)

## For users

**Turing is currently only compatible with FlexiChains v0.6.
Please see [the documentation for that version](https://juliabayes.org/FlexiChains.jl/v0.6/).**

Up until version 0.6, FlexiChains has used the `VarName` and `VarNamedTuple` types defined in AbstractPPL.jl and DynamicPPL.jl respectively.
Note that if you stick to v0.6 of FlexiChains, everything will still work perfectly fine, and you can more or less stop reading here.
Indeed this should still be enforced by the compat bounds on Turing!

### What changed?

FlexiChains v0.7 now uses its own types, which is functionally the same as Turing's, but is not the same type.
In order to maintain some level of compatibility, FlexiChains v0.7 still defines the same functionality on the old VarName types, but there is no guarantee that this will continue to exist in a future breaking release of FlexiChains.
The reason for these compatibility shims is mostly to ensure that there will be a version of FlexiChains that is compatible with both the old and new types (otherwise, it will be impossible to e.g. use Turing together with another package that requires the new types).
However, for most users you should really just use v0.6 and not worry about all of this.

This docs page will be updated if things change.

## For developers

There may be situations where you need to use Turing together with FlexiChains v0.7, for example if you want to use a package that requires the new types.

If you use the released version of Turing, this will not work, because of Turing's compat bounds.
(This may work in the future, but there is no guarantee.)
Instead, you can use [this fork of Turing](https://github.com/JuliaBayes/Turing.jl).
This fork papers over the differences above by:

 1. updating the compat bounds; and
 2. redefining the default chain type in Turing to be the _old_ `VNChain` instead of the new one.

This means that when you call `sample(...)` in Turing, you will get an _old_ `VNChain` object, with different types from what is currently `FlexiChains.VNChain` in v0.7.
In general this should not pose a massive problem since there's no real situation where you might want to directly compare the chain objects themselves.
However, you might well find that you might want to unify the types, e.g. if it reduces duplication in downstream analysis code.
(For example, old-VNChains must be indexed into with `AbstractPPL.VarName`, but new ones must use `VarNames.VarName`.)
To do this, you can use the `FlexiChains.upgrade` function, which will convert an old chain into a new one.
Likewise, if you have a new chain and want to convert it into an old one, you can use `FlexiChains.downgrade`.

```@docs
FlexiChains.upgrade
FlexiChains.downgrade
```
