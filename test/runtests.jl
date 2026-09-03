using Test: @testset

if get(ENV, "UPDATE_REFIMAGES", "") == "1"
    # Only update reference images.
    include("plots/ref.jl")
else
    @testset verbose = true "FlexiChains.jl" begin
        include("Aqua.jl")
        include("chain.jl")
        include("summaries.jl")
        include("diagnostics.jl")
        include("interface.jl")
        include("varname.jl")
        include("flatten.jl")
        include("ext/advancedhmc.jl")
        include("ext/mcmcchains.jl")
        include("ext/dynamicppl.jl")
        include("serialise.jl")
        include("stancsv.jl")
        include("ext/montecarlomeasurements.jl")
        include("ext/posteriordb.jl")
        include("ext/posteriorstats.jl")
        include("ext/inferenceobjects.jl")
        include("plots/quantile_utils.jl")
        include("plots/dotplot.jl")
        include("plots/ref.jl")
    end
end
