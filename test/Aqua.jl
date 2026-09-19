module AquaTests

using Aqua: Aqua
using FlexiChains: FlexiChains
using Test

@info "Testing Aqua.jl"

@testset verbose=true "aqua.jl" begin
    Aqua.test_all(FlexiChains)
end

end
