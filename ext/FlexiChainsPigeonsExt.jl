module FlexiChainsPigeonsExt

using Pigeons: Pigeons
using FlexiChains: FlexiChains, FlexiChain, VarName, @vn, Parameter, Extra

"""
    FlexiChains.from_pigeons(pt::Pigeons.PT)

Convert the result of a Pigeons.jl sampling run into a `FlexiChain`.

The run must have been performed with `pigeons(; ... record = [traces, ...])` so that the
samples can be obtained. If this was not included, then this function will error.

The output type depends on the kind of model sampled from:

- DynamicPPL models will produce `FlexiChain{AbstractPPL.VarName}`.
- Other models will produce `VNChain`, i.e., `FlexiChain{VarNames.VarName}`.

## Other models

For non-DynamicPPL models, the parameter names are taken from Pigeons:

- If the target does not provide parameter names, Pigeons generates the names `param_1`,
  `param_2`, etc. In this case, all the parameters are combined into a single
  vector-valued parameter, `@vn(param)`.
- Otherwise (e.g. for Stan models), each name that Pigeons returns becomes its own
  parameter. For example, a Stan model with parameters `p1` and `p2` will give a chain with
  `@vn(p1)` and `@vn(p2)`.

In both cases, the log-density is stored as `Extra(:log_density)`.

## DynamicPPL models

Note that for DynamicPPL models, calling `from_pigeons` will result in the model being
reevaluated in order to recover the structure of the parameters. This is necessary because
Pigeons stores a flattened version of the parameters. It should generally be the case that
the time taken for this reevaluation is negligible compared to the actual sampling time.

The reevaluation isn't without benefit, though: you will also obtain (for free) the
breakdown of the log-density between prior and likelihood, plus any `x := expr` variables in
the model, which Pigeons does not save.
"""
function FlexiChains.from_pigeons(pt::Pigeons.PT)
    return FlexiChains._internal_from_pigeons(pt, pt.inputs.target)
end

# Reimplementation of Pigeons.sample_array, which avoids converting to Float unnecessarily
# See: https://github.com/Julia-Tempering/Pigeons.jl/issues/445
# 
# Returns niters x nchains x nparams array (NOTE: this differs from `Pigeons.sample_array`
# which returns niters x nparams x nchains). Also note that the last 'parameter' is the
# log-density.
function FlexiChains._faithful_sample_array(pt::Pigeons.PT)
    # NOTE: chains_with_samples is internal -- but I can't inline its definition because it
    # itself uses internal stuff! The only way to fix this is to upstream this
    # implementation into Pigeons.sample_array. See issue above.
    chains = Pigeons.chains_with_samples(pt)
    # Vector of Vector of samples, where each sample is itself a Vector.
    vec_vec_samples = [Pigeons.get_sample(pt, chn) for chn in chains]
    # This is nparams x niters x nchains
    arr = stack(stack(vec_vec_samples))
    return permutedims(arr, (2, 3, 1))
end

function FlexiChains._internal_from_pigeons(pt::Pigeons.PT, ::Any)
    sarr = FlexiChains._faithful_sample_array(pt)
    param_names = Pigeons.sample_names(pt)[1:(end-1)] # Drop logdensity.
    # Pigeons will generate String parameter names for Stan models, so we eagerly convert to
    # Symbol here. (Also, annoyingly, it puts the String names in a Vector{Any}, which this
    # fixes.)
    param_names = map(Symbol, param_names)
    nparams = length(param_names)
    # For models that don't have names, Pigeons will generate `:param_1`, `:param_2`, etc.
    # In such a case we can just lump them into a single vector parameter. This is a bit of
    # a hack because we are essentially reverse-engineering Pigeons's default, but there
    # isn't really any other way to do it.
    ks = if all(i -> param_names[i] == Symbol("param_$i"), 1:nparams)
        (Parameter(@vn(param)) => (nparams,), Extra(:log_density))
    else
        (map(n -> Parameter(VarName{n}()), param_names)..., Extra(:log_density))
    end
    return FlexiChain{VarName}(sarr, ks)
end

end # module
