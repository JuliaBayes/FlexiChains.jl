import Random: Random
import StatsBase: StatsBase

"""
    Base.rand(rng::Random.AbstractRNG, chn::FlexiChain, dims::Int...; parameters_only=false, weights=nothing)

Sample uniformly from a FlexiChain with replacement.

Pass `weights::StatsBase.AbstractWeights` to sample with probabilities proportional to
the weights instead. Supply one weight per sample, with all iterations of the first
chain followed by all iterations of the second chain, and so on.

`rand([rng,] chn)` returns a single sample, whereas `rand([rng,] chn, dims...)` returns an
`Array` of samples with dimensions `dims...`. The `parameters_only` keyword specifies
whether the returned samples include only parameters, or both parameters and extras.

In general, the return type of `rand` is the same as the return type of
`FlexiChains.parameters_at` or `FlexiChains.values_at` (but wrapped in an `Array` if `dims`
is not empty). This means that the return type can depend on the 'structure' stored in the 
`FlexiChain`.

For example, if `chn::FlexiChain{VarName}` was constructed using Turing.jl, `rand(chn)` will
return a `DynamicPPL.ParamsWithStats`, and `rand(chn, parameters_only=true)` will return a
`DynamicPPL.VarNamedTuple`.
"""
function Base.rand(
    rng::Random.AbstractRNG,
    chn::FlexiChain,
    dims::Int...;
    parameters_only=false,
    weights::Union{Nothing,StatsBase.AbstractWeights}=nothing,
)
    func = parameters_only ? FlexiChains.parameters_at : FlexiChains.values_at
    ci = CartesianIndices(size(chn))
    idxs = if weights === nothing
        rand(rng, ci, dims...)
    else
        # Array sampling checks weight lengths even for scalar requests.
        selected = StatsBase.sample(rng, ci, weights, dims)
        isempty(dims) ? selected[] : selected
    end
    return if isempty(dims)
        i, c = idxs.I
        func(chn; iter=i, chain=c)
    else
        map(idxs) do idx
            i, c = idx.I
            func(chn; iter=i, chain=c)
        end
    end
end
function Base.rand(chn::FlexiChain, dims::Int...; parameters_only=false, weights=nothing)
    return rand(
        Random.default_rng(),
        chn,
        dims...;
        parameters_only=parameters_only,
        weights=weights,
    )
end
