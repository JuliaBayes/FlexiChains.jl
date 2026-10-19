# For library authors

If you are the author of a Julia library and want to integrate FlexiChains with your package: first of all, thank you for your interest!
If you need any kind of help, please don't hesitate to open an issue or reach out.

This page contains a single tip for integrating FlexiChains, namely...

## Use `VarName` as the key type

It is *strongly recommended* to use [`VarNames.VarName`](@extref) as the key type.
This type, as well as the `@vn` macro that is used to create `VarName`s, is re-exported by FlexiChains.
Furthermore, an alias `VNChain` is provided for `FlexiChain{VarName}`.

FlexiChains is technically general in its key type, and indeed still retains an alias `SymChain` for `FlexiChain{Symbol}`.
Previous versions of FlexiChains have used `Symbol` and sometimes even `String` (the horror!) as key types.
However, this is no longer recommended because:

 1. It leads to fragmentation of APIs, and is just confusing for users to deal with.

 2. `VarName` is strictly more powerful than `Symbol`.
    For example, if you have a vector-valued variable `@vn(x)`, you can use `chn[@vn(x[1])` to refer to the first element of `x`, whereas you cannot do this with a `Symbol` key.
    This is demonstrated thoroughly on [the indexing page](@ref indexing).

    You might wonder whether this is worth it if you don't have any parameters with fancy shapes.
    However, as it turns out, FlexiChains allows you to index into `VarName` chains with plain `Symbol`s.
    As long as `:x` unambiguously refers to a single keyg (that is, as long as you don't have an `Extra` that _also_ happens to be named `:x`), then `chn[:x]` will let you access `chn[@vn(x)]`, without having to spell out the macro.
    So, in the simple case, `VarName` doesn't even lead to any loss of ergonomics.

 3. Prior to v0.7, one of the drawbacks of `VarName` was that the `VarNamedTuple` type was defined in DynamicPPL.jl, which was not a hard dependency of FlexiChains (for good reason!).
    This meant that a lot of useful functionality was not available unless you happened to already be using DynamicPPL.
    For example, `rand(chain)` would just give you a boring dictionary rather than a `VarNamedTuple`, which is much more useful.
    In v0.7, `VarNamedTuple` was moved to the `VarNames` package, which FlexiChains depends on, and this is no longer a problem.
