# [Serialising chains](@id serialising)

You can serialise and deserialise `FlexiChain` and `FlexiSummary` objects using either the [Serialization.jl standard library](@extref Julia Serialization), or [JLD2.jl](https://juliaio.github.io/JLD2.jl/stable/).

!!! important "Versions must match"

    When you deserialise any object, you should make sure that the package versions you are using exactly match the versions that were used to serialise the object.
    This is most easily accomplished by using `Manifest.toml` files.

    This is because serialisation relies on the internal structure of the object, which may change between versions.
    Note that because serialisation also uses private fields, which may change in any version of a package (even non-breaking ones), you cannot rely on semantic versioning guarantees.
    Thus, if you want to ensure that deserialisation will work correctly, you should make sure that you are using exactly the same patch version.
    If you use a different version of any package, deserialisation *may* work, but there is no guarantee that it will.

    Furthermore, because a FlexiChain may also contain objects from other libraries (for example sampler states), you must make sure that *all* packages you are using have fully matching versions, not just FlexiChains.jl.

Here is an example with the standard library:

```@example serialization
using FlexiChains, Serialization

chn = FlexiChains.EXAMPLE_CHAIN
```

```@example serialization
fname = "mychain"
serialize(fname, chn)

chn2 = deserialize(fname)
isequal(chn, chn2)
```

And with JLD2.jl:

```@example serialization
using JLD2

fname, key = "chain.jld2", "chain"
save(fname, Dict(key => chn))
chn2 = load(fname, key)

isequal(chn, chn2)
```

Note two things:

 1. If the serialisation and deserialisation steps are performed in different Julia sessions, you need to make sure that you have all necessary packages loaded in the second session before you perform the deserialisation.
    For example, if you are loading a Turing.jl chain that was sampled with `save_state=true`, then you should load Turing.jl before deserialising, because Turing provides the sampler state types.

 2. If you are testing the integrity of (de)serialisation, you may find that `isequal()` on sampler state types may not return `true` even when the sampler states are the same.
    This is because Julia's default definition of equality for structs is based on object identity, not on field values.
    For example, the following returns `false` because `[1] !== [1]`.

    ```@example serialization
    struct Foo{T}
        t::T
    end
    
    Foo([1]) == Foo([1])
    ```
