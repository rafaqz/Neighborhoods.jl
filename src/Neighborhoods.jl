module Neighborhoods

using Adapt, 
      ConstructionBase,
      KernelAbstractions,
      OffsetArrays,
      Setfield,
      StaticArrays,
      UnicodeGraphics

export Neighborhood, Window, Kernel, Moore, VonNeumann, Positional, Layered
export NeighborhoodArray
export BoundaryCondition, Wrap, Remove
export Padding, Conditional, Halo

export neighborhood, neighbors, offsets, indices, distances, radius, diameter, kernel, kernelproduct
export broadcast_neighborhood, broadcast_neighborhood!

include("neighborhood.jl")
include("boundary.jl")
include("padding.jl")
include("array.jl")
include("broadcast_neighborhood.jl")

include("neighborhoods/window.jl")
include("neighborhoods/moore.jl")
include("neighborhoods/vonneumman.jl")
include("neighborhoods/positional.jl")
include("neighborhoods/layered.jl")
include("neighborhoods/kernel.jl")

end # Module Neighborhoods

