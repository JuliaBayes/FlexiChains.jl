# Accept PalmerPenguins download
ENV["DATADEPS_ALWAYS_ACCEPT"] = "true"

using Pkg: Pkg
Pkg.develop(Pkg.PackageSpec(; path=dirname(@__DIR__)))

using Documenter
using DocumenterInterLinks
using DocumenterVitepress

using FlexiChains

using AbstractMCMC: AbstractMCMC
using CairoMakie: CairoMakie, Makie
using DataFrames: DataFrames
using DimensionalData: DimensionalData
using DynamicPPL: DynamicPPL
using InferenceObjects: InferenceObjects
using MCMCChains: MCMCChains
using MCMCDiagnosticTools: MCMCDiagnosticTools
using MonteCarloMeasurements: MonteCarloMeasurements
using PairPlots: PairPlots
using PalmerPenguins: PalmerPenguins
using Pigeons: Pigeons
using Plots: Plots
using PosteriorDB: PosteriorDB
using PosteriorStats: PosteriorStats
using Statistics: Statistics
using StatsBase: StatsBase
using StatsPlots: StatsPlots
using VarNames: VarNames

links = InterLinks(
    "AdvancedHMC" => "https://turinglang.org/AdvancedHMC.jl/stable/",
    "DimensionalData" => "https://rafaqz.github.io/DimensionalData.jl/stable/",
    "DynamicPPL" => "https://turinglang.org/DynamicPPL.jl/stable/",
    "MCMCDiagnosticTools" => "https://turinglang.org/MCMCDiagnosticTools.jl/stable/",
    "PosteriorDB" => "https://sethaxen.github.io/PosteriorDB.jl/stable/",
    "PosteriorStats" => "https://julia.arviz.org/PosteriorStats/stable/",
    "Plots" => "https://docs.juliaplots.org/stable/",
    "StatsBase" => "https://juliastats.org/StatsBase.jl/stable/",
    "Julia" => "https://docs.julialang.org/en/v1/",
    "VarNames" => "https://juliabayes.org/VarNames.jl/stable/",
)

modules = [
    FlexiChains,
    Base.get_extension(FlexiChains, :FlexiChainsDynamicPPLExt),
    Base.get_extension(FlexiChains, :FlexiChainsInferenceObjectsExt),
    Base.get_extension(FlexiChains, :FlexiChainsMCMCChainsExt),
    Base.get_extension(FlexiChains, :FlexiChainsMakieExt),
    Base.get_extension(FlexiChains, :FlexiChainsMonteCarloMeasurementsExt),
    Base.get_extension(FlexiChains, :FlexiChainsPairPlotsExt),
    Base.get_extension(FlexiChains, :FlexiChainsPigeonsExt),
    Base.get_extension(FlexiChains, :FlexiChainsPosteriorDBExt),
    Base.get_extension(FlexiChains, :FlexiChainsPosteriorStatsDynamicPPLExt),
    Base.get_extension(FlexiChains, :FlexiChainsPosteriorStatsExt),
    Base.get_extension(FlexiChains, :FlexiChainsRecipesBaseExt),
    Base.get_extension(FlexiChains, :FlexiChainsStatsPlotsExt),
]

# Enable headless mode so that plots don't pop up when building docs.
old_GKSwstype = get(ENV, "GKSwstype", nothing)
ENV["GKSwstype"] = "100"

GITHUB_REPO = "github.com/JuliaBayes/FlexiChains.jl"
PAGES_BRANCH = "gh-pages"
DEV_BRANCH = "main"

makedocs(;
    sitename="FlexiChains.jl",
    format=DocumenterVitepress.MarkdownVitepress(
        repo=GITHUB_REPO,
        devbranch=DEV_BRANCH,
        devurl="dev",
    ),
    modules=modules,
    pages=[
        "index.md",
        "Usage" => [
            "datastructure.md",
            "indexing.md",
            "samples.md",
            "summarising.md",
            "arrays.md",
            "modifying.md",
            "serialising.md",
            "Plotting" => ["plotting.md", "makie.md", "plots.md", "aog.md"],
        ],
        "Integrations" => [
            "advancedhmc.md",
            "arviz.md",
            "custom_sampler.md",
            "MCMCChains.jl" => ["mcmcchains.md", "migration.md"],
            "montecarlomeasurements.md",
            "pairplots.md",
            "parallelmcmc.md",
            "pigeons.md",
            "posteriordb.md",
            "posteriorstats.md",
            "stan.md",
            "tables.md",
            "turing.md",
        ],
        "About" => ["contributing.md", "why.md", "whynot.md"],
        "api.md",
    ],
    checkdocs=:exports,
    warnonly=false,
    doctest=false,
    plugins=[links],
)

DocumenterVitepress.deploydocs(;
    repo=GITHUB_REPO,
    target=joinpath(@__DIR__, "build"),
    branch=PAGES_BRANCH,
    devbranch=DEV_BRANCH,
    push_preview=true,
)

# Restore original environment variable
if isnothing(old_GKSwstype)
    delete!(ENV, "GKSwstype")
else
    ENV["GKSwstype"] = old_GKSwstype
end
nothing
