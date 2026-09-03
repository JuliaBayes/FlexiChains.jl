module FlexiChainsPigeonsDynamicPPLExt

using Pigeons: Pigeons
using DynamicPPL: DynamicPPL, LogDensityFunction, UnlinkAll, ParamsWithStats, Model

using FlexiChains: FlexiChains
using AbstractMCMC

function FlexiChains._internal_from_pigeons(pt::Pigeons.PT, lp::Pigeons.TuringLogPotential)
    # This is niter x nchains x nparams -- but the last param is actually the log density
    # (which we won't need; we'll get it from reevaluation) so we drop it
    sarr = FlexiChains._faithful_sample_array(pt)[:, :, 1:(end-1)]
    # Note that Pigeons unfortunately returns us a **flattened vector** of **unlinked**
    # parameters, which is annoying. Because it's flattened, we don't have any way to
    # extract the original parameter structure, so we need to feed it back through a
    # LogDensityFunction.
    #
    # It's MOSTLY safe to use a LDF because Pigeons only handles models with fixed sizes
    # (this is stated in the Pigeons docs). Unexpected stuff WILL happen if you have a model
    # where the parameters have variable ordering, but in such a case things will get very
    # weird on the Pigeons end already, and there's nothing we can do about it here.
    # Because the parameters are unlinked we use UnlinkAll() here.
    ldf = LogDensityFunction(lp.model, UnlinkAll())
    # Then the usual stuff, reevaluate and make a chain.
    pwss = [ParamsWithStats(s, ldf) for s in eachslice(sarr, dims=(1, 2))]
    chn = AbstractMCMC.from_samples(FlexiChains.FlexiChain{DynamicPPL.VarName}, pwss)
end

end # module
