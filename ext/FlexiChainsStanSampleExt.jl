module FlexiChainsStanSampleExt

using FlexiChains: FlexiChains
using StanSample: SampleModel

"""
    FlexiChains.from_stansample(sm::StanSample.SampleModel, key_spec=nothing)::FlexiChain

Convert a `StanSample.SampleModel` object to a `FlexiChain`. Sampling must already
have been run on `sm` (e.g. with `stan_sample(sm; data)`).

This reads the Stan CSV files that StanSample.jl wrote to disk, using
[`FlexiChains.from_stan_csv`](@ref); see its docstring for details of how columns are
converted into keys, and the `key_spec` argument.
"""
function FlexiChains.from_stansample(
    sm::SampleModel,
    key_spec::Union{Nothing,Tuple}=nothing,
)
    if sm.thin > 1
        @info "Note that StanSample.jl does not pass the `thin` argument to CmdStan, so the saved Stan CSV file and the resulting FlexiChain will contain all iterations. If you want to thin the chain, you can do so by indexing, using e.g. `chn[iter=At(1001:4:2000)]`."
    end
    return FlexiChains.from_stan_csv(sm.output_base * "_chain", sm.num_chains, key_spec)
end

end # module
