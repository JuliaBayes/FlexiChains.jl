###################
# Makie overloads #
###################

module Makie

export traceplot,
    traceplot!,
    rankplot,
    rankplot!,
    mixeddensity,
    mixeddensity!,
    meanplot,
    meanplot!,
    autocorplot,
    autocorplot!,
    pushforward_continuous,
    pushforward_continuous!,
    pushforward_discrete,
    pushforward_discrete!,
    pushforward_hist,
    pushforward_hist!,
    ridgeline,
    ridgeline!,
    forestplot,
    forestplot!,
    dotplot,
    dotplot!

# The non-mutating versions have docstrings in the extension.

function traceplot end

"""
    FlexiChains.Makie.traceplot!

Mutating version of [`FlexiChains.Makie.traceplot`](@ref), for use with existing
`Makie.Axis` objects.
"""
function traceplot! end

function rankplot end

"""
    FlexiChains.Makie.rankplot!

Mutating version of [`FlexiChains.Makie.rankplot`](@ref), for use with existing `Makie.Axis`
objects.
"""
function rankplot! end

function mixeddensity end

"""
    FlexiChains.Makie.mixeddensity!

Mutating version of [`FlexiChains.Makie.mixeddensity`](@ref), for use with existing
`Makie.Axis` objects.
"""
function mixeddensity! end

function meanplot end

"""
    FlexiChains.Makie.meanplot!

Mutating version of [`FlexiChains.Makie.meanplot`](@ref), for use with existing `Makie.Axis`
objects.
"""
function meanplot! end

function autocorplot end

"""
    FlexiChains.Makie.autocorplot!

Mutating version of [`FlexiChains.Makie.autocorplot`](@ref), for use with existing
`Makie.Axis` objects.
"""
function autocorplot! end

function pushforward_continuous end

"""Mutating version of [`FlexiChains.Makie.pushforward_continuous`](@ref)."""
function pushforward_continuous! end

function pushforward_discrete end

"""Mutating version of [`FlexiChains.Makie.pushforward_discrete`](@ref)."""
function pushforward_discrete! end

function pushforward_hist end

"""Mutating version of [`FlexiChains.Makie.pushforward_hist`](@ref)."""
function pushforward_hist! end
function ridgeline end

"""
    FlexiChains.Makie.ridgeline!

Mutating version of [`FlexiChains.Makie.ridgeline`](@ref), for use with existing
`Makie.Axis` objects.
"""
function ridgeline! end

function forestplot end

"""
    FlexiChains.Makie.forestplot!

Mutating version of [`FlexiChains.Makie.forestplot`](@ref), for use with existing
`Makie.Axis` objects.
"""
function forestplot! end

function dotplot end

"""
    FlexiChains.Makie.dotplot!

Mutating version of [`FlexiChains.Makie.dotplot`](@ref), for use with existing `Makie.Axis`
objects.
"""
function dotplot! end

end # module
