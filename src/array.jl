
"""
    AbstractNeighborhoodArray <: StaticArray

Supertype for arrays with a [`Neighborhood`](@ref),
a [BoundaryCondition](@ref), and [`Padding`](@ref).
"""
abstract type AbstractNeighborhoodArray{S,R,T,N,A,H,BC,P} <: AbstractArray{T,N} end

boundary_condition(A::AbstractNeighborhoodArray) = A.boundary_condition
padding(A::AbstractNeighborhoodArray) = A.padding
Base.@propagate_inbounds neighborhood(A::AbstractNeighborhoodArray, I::Tuple) =
    update_neighborhood(A, CartesianIndex(I))
Base.@propagate_inbounds neighborhood(A::AbstractNeighborhoodArray, I::Union{CartesianIndex,Int}...) =
    neighborhood(A, CartesianIndex(to_indices(A, I)))
Base.@propagate_inbounds neighborhood(A::AbstractNeighborhoodArray, I::CartesianIndex) =
    update_neighborhood(A, I)
Base.@propagate_inbounds neighborhood(A::AbstractNeighborhoodArray) =
    A.neighborhood

"""
    neighbors(hood::Neighborhood, A::AbstractArray, I) => SArrayt

Get a single neighborhood from an array, as a `Tuple`, checking bounds.
"""
@inline neighbors(A::AbstractNeighborhoodArray, I::NTuple{<:Any,Int}) = neighbors(A, I...)
@inline neighbors(A::AbstractNeighborhoodArray, I::Int...) = neighbors(A, CartesianIndex(I))
@inline function neighbors(A::AbstractNeighborhoodArray{<:Any,R,<:Any,N}, I::CartesianIndex) where {R,N}
    if A.padding isa Halo # Conditional has checks internally
        low = CartesianIndex(ntuple(_ -> -R, N))
        high = CartesianIndex(ntuple(_ -> R, N))
        checkbounds(parent(A), I + low)
        checkbounds(parent(A), I + high)
    end
    return unsafe_neighbors(A, I)
end

# function Base.show(io, mime::MIME"text/plain", A::AbstractNeighborhoodArray)
#     invoke(show, (AbstractArray,), A)
#     println()
#     show(io, mime, neighborhood(A))
#     println()
#     show(io, mime, boundary_condition(A))
#     println()
#     show(io, mime, padding(A))
# end

# Iterate over the parent for `Conditional` padding, 2x faster.
Base.iterate(A::AbstractNeighborhoodArray{<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,<:Conditional}, args...) =
    iterate(parent(A), args...)
Base.parent(A::AbstractNeighborhoodArray) = A.parent
for f in (:getindex, :view, :dotview)
    @eval begin
        Base.@propagate_inbounds function Base.$f(A::AbstractNeighborhoodArray, I::Union{Colon,Int64,AbstractArray}...)
            @boundscheck checkbounds(A, I...)
            @inbounds Base.$f(parent(A), I...)
        end
        Base.@propagate_inbounds function Base.$f(A::AbstractNeighborhoodArray, i1::Int, I::Int...)
            @boundscheck checkbounds(A, i1, I...)
            @inbounds Base.$f(parent(A), i1, I...)
        end
    end
end
Base.@propagate_inbounds Base.setindex!(d::AbstractNeighborhoodArray, x, I::Int...) =
    setindex!(parent(d), x, I...)
Base.@propagate_inbounds Base.setindex!(d::AbstractNeighborhoodArray, x, I...) =
    setindex!(parent(d), x, I...)
Base.size(::AbstractNeighborhoodArray{S}) where S = tuple_contents(S)

# Return a SizedArray with similar, instead of a StaticArray
Base.similar(A::AbstractNeighborhoodArray) = similar(parent(parent(A)), size(A))
Base.similar(A::AbstractNeighborhoodArray, ::Type{T}) where T = similar(parent(parent(A)), T, size(A))
Base.similar(A::AbstractNeighborhoodArray, I::Tuple{Int,Vararg{Int}}) = similar(parent(parent(A)), I)
Base.similar(A::AbstractNeighborhoodArray, ::Type{T}, I::Tuple{Int,Vararg{Int}}) where T =
    similar(parent(parent(A)), T, I)

"""
    NeighborhoodArray <: AbstractNeighborhoodArray

An array with a [`Neighborhood`](@ref) and a [BoundaryCondition](@ref), and [`Padding`](@ref).

For most uses a `NeighborhoodArray` works exactly the same as a regular array.

Except it can be indexed at any point with `neighborhood` to return a filled
`Neighborhood` object, or `neighbors` to return an `SVector` of neighbors.

## Example

```
using Neighborhoods
A = NeighborhoodArray((1:10) * (10:20)'; neighborhood=Moore(2), boundary_condition=Wrap())
A .*= 2 # Broadcast works as usual
hood = neighborhood(A, 5, 10)

# ouput
Moore{1, 2, 8, StaticArraysCore.SVector{8, Int64}}
?????????
?????????
with neighbors:
8-element StaticArraysCore.SVector{8, Int64} with indices SOneTo(8):
 144
 180
 216
 152
 228
 160
 200
 240
"""
struct NeighborhoodArray{S,R,T,N,A<:AbstractArray{T,N},H<:Neighborhood{R,N},BC,P} <: AbstractNeighborhoodArray{S,R,T,N,A,H,BC,P}
    parent::A
    neighborhood::H
    boundary_condition::BC
    padding::P
    function NeighborhoodArray{S,R,T,N,A,H,BC,P}(parent::A, h::H, bc::BC, padding::P) where {S,R,T,N,A,H,BC,P}
        map(tuple_contents(S), _radii(Val{N}(), R)) do s, rs
            max(map(abs, rs)...) < s || throw(ArgumentError("neighborhood radius is larger than array axis $s"))
        end
        return new{S,R,T,N,A,H,BC,P}(parent, h, bc, padding)
    end
end
function NeighborhoodArray(parent::AbstractArray, hood::Neighborhood{R}, bc, padding) where R
    padded_parent = pad_array(padding, bc, hood, parent)
    S = Tuple{_size(padding, hood, padded_parent)...}
    NeighborhoodArray{S,R}(padded_parent, hood, bc, padding)
end
NeighborhoodArray{S}(parent::AbstractArray, hood::Neighborhood{R}, bc, padding) where {S,R} =
    NeighborhoodArray{S,R}(parent, hood, bc, padding)
NeighborhoodArray{S,R}(parent::A, h::H, bc::BC, padding::P) where {S,A<:AbstractArray{T,N},H<:Neighborhood{R},BC,P} where {R,T,N} =
    NeighborhoodArray{S,R,T,N,A,H,BC,P}(parent, h, bc, padding)
function NeighborhoodArray(parent::AbstractArray{<:Any,N}, neighborhood=Window{1,N}();
    boundary_condition=Remove(zero(eltype(parent))),
    padding=Conditional(),
) where N
    NeighborhoodArray(parent, neighborhood, boundary_condition, padding)
end

_size(::Conditional, ::Neighborhood, parent) = size(parent)
_size(::Halo, ::Neighborhood{R}, parent) where R = size(parent) .- 2R

function Adapt.adapt_structure(to, A::NeighborhoodArray{S}) where S
    newparent = Adapt.adapt(to, parent(A))
    NeighborhoodArray{S}(newparent, neighborhood(A), boundary_condition(A), padding(A))
end

ConstructionBase.constructorof(::Type{<:NeighborhoodArray{S}}) where S = NeighborhoodArray{S}

# Neighborhood vector

struct LazyNeighborhoodVector{L,T,R,N,H,A<:AbstractNeighborhoodArray{<:Any,<:Any,T,N,<:Any,H}} <: StaticVector{L,T}
    parent::A
    center::CartesianIndex{N}
    LazyNeighborhoodVector(a::A, I::CartesianIndex) where {A<:AbstractNeighborhoodArray{S,R,T,N,<:Any,H}} where {S,R,T,N,H<:Neighborhood{R,N,L}} where {L} =
        new{L,T,R,N,H,A}(a, I)
end
LazyNeighborhoodVector(A, I::Tuple) = LazyNeighborhoodVector(A, CartesianIndex(I))
# S,R,T,N,A,H,BC,P

Base.parent(v::LazyNeighborhoodVector) = v.parent
neighborhood(v::LazyNeighborhoodVector) = neighborhood(parent(v))
center(v::LazyNeighborhoodVector) = v.center

Base.@propagate_inbounds function Base.getindex(v::LazyNeighborhoodVector, i::Int)
    neighbor_getindex(parent(v), indexat(neighborhood(v), center(v), i)) 
end

Base.size(v::LazyNeighborhoodVector) = (length(v),)
Base.length(::LazyNeighborhoodVector{Tuple{L}}) where L = L


# Internals

"""
    unsafe_readneighbors(hood::Neighborhood, A::AbstractArray, I) => SArray

Get a single neighborhood from an array, as a `Tuple`, without checking bounds.
"""
@inline unsafe_neighbors(A::AbstractNeighborhoodArray, I::CartesianIndex) =
    unsafe_neighbors(A, neighborhood(A), I)
@inline function unsafe_neighbors(A::AbstractNeighborhoodArray, hood::Neighborhood, I::CartesianIndex)
    map(indices(hood, I)) do P
        @inbounds neighbor_getindex(A, CartesianIndex(P))
    end
end

"""
    update_neighborhood(x, A::AbstractArray, I) => Neighborhood

Set the neighbors of a neighborhood to values from the array A around index `I`.
Bounds checks will reduce performance, aim to use `unsafe_setneighbors` directly.
"""
Base.@propagate_inbounds update_neighborhood(A::AbstractNeighborhoodArray, I::CartesianIndex) =
    setneighbors(neighborhood(A), neighbors(A, I))

Base.@propagate_inbounds function neighbor_getindex(A::AbstractNeighborhoodArray, I::CartesianIndex)
    neighbor_getindex(A, boundary_condition(A), padding(A), I)
end
# If `Halo` padded we can just use regular `getindex`
# on the parent array, which is an `OffsetArray`
Base.@propagate_inbounds function neighbor_getindex(A::AbstractNeighborhoodArray, ::BoundaryCondition, pad::Halo, I::CartesianIndex)
    @boundscheck checkbounds(parent(A), I)
    @inbounds parent(A)[I]
end
# `Conditional` needs handling. For Wrap we swap the side.
# This also means we don't need bounds checking as the
# neighborhood can't be larger than the array itself.
function neighbor_getindex(A::AbstractNeighborhoodArray{S}, ::Wrap, pad::Conditional, I::CartesianIndex) where S
    sz = tuple_contents(S)
    wrapped_inds = map(Tuple(I), sz) do i, s
        i < 1 ? i + s : (i > s ? i - s : i)
    end
    return @inbounds A[wrapped_inds...]
end
# For Remove we use padval if out of bounds
function neighbor_getindex(A::AbstractNeighborhoodArray, x::Remove, pad::Conditional, I::CartesianIndex)
    return checkbounds(Bool, A, I) ? (@inbounds A[I]) : x.padval
end

# update_boundary!
# Reset or wrap boundary where required. This allows us to ignore
# bounds checks on neighborhoods and still use a wraparound grid.
update_boundary!(As::Tuple) = map(update_boundary!, As)
update_boundary!(A::NeighborhoodArray) =
    update_boundary!(A, padding(A), boundary_condition(A))
# Conditional sets boundary conditions on the fly
update_boundary!(A::AbstractNeighborhoodArray, ::Conditional, ::BoundaryCondition) = A
# Halo needs updating
function update_boundary!(A::AbstractNeighborhoodArray{S,R}, ::Halo, bc::Remove) where {S<:Tuple{L},R} where {L}
    # Use the inner array so broadcasts over views works on GPU
    # they don't through the `OffsetArray` wrapper
    src = parent(parent(A))
    @inbounds src[vcat(1:R, L+R+1:L+2R)] .= Ref(padval(bc))
    return A
end
function update_boundary!(A::AbstractNeighborhoodArray{S,R}, ::Halo, bc::Remove) where {S<:Tuple{Y,X},R} where {Y,X}
    src = parent(parent(A))
    # Sides
    @inbounds src[1:Y, vcat(1:R, X+R+1:X+2R)] .= Ref(padval(bc))
    @inbounds src[vcat(1:R, Y+R+1:Y+2R), R+1:X+R] .= Ref(padval(bc))
    return A
end
function update_boundary!(A::AbstractNeighborhoodArray{S,R}, ::Halo, bc::Remove) where {S<:Tuple{Z,Y,X},R} where {Z,Y,X}
    src = parent(parent(A))
    @inbounds src[axes(src, 1), axes(src, 2), vcat(1:R, X+R+1:X+2R)] .= Ref(padval(bc))
    @inbounds src[axes(src, 1), vcat(1:R, Y+R+1:Y+2R), axes(src, 3)] .= Ref(padval(bc))
    @inbounds src[vcat(1:R, Z+R+1:Z+2R), axes(src, 2), axes(src, 3)] .= Ref(padval(bc))
    return A
end
function update_boundary!(A::AbstractNeighborhoodArray{S,R}, ::Halo, ::Wrap) where {S<:Tuple{L},R} where {L}
    src = parent(A)
    startpad = 1:R
    endpad = L+R+1:L+2R
    startvals = R+1:2R
    endvals = L+1:L+R
    @assert length(startpad) == length(endvals) == R
    @assert length(endpad) == length(startvals) == R
    @inbounds src[startpad] .= src[endvals]
    @inbounds src[endpad] .= src[startvals]
    return A
end
function update_boundary!(A::AbstractNeighborhoodArray{S,R}, ::Halo, ::Wrap) where {S<:Tuple{Y,X},R} where {Y,X}
    src = parent(parent(A))
    n_xs, n_ys = X, Y
    startpad_x = startpad_y = 1:R
    endpad_x = n_xs+R+1:n_xs+2R
    endpad_y = n_ys+R+1:n_ys+2R
    start_x = start_y = R+1:2R
    end_x = n_xs+1:n_xs+R
    end_y = n_ys+1:n_ys+R
    xs = 1:n_xs+2R
    ys = 1:n_ys+2R

    @assert length(startpad_x) == length(start_x) == R
    @assert length(endpad_x) == length(end_x) == R
    @assert length(startpad_y) == length(start_y) == R
    @assert length(endpad_y) == length(end_y) == R
    @assert map(length, (xs, ys)) === size(src)

    CI = CartesianIndices
    # Sides ---
    @inbounds src[CI((xs, startpad_y))] .= src[CI((xs, end_y))]
    @inbounds src[CI((xs, endpad_y))]   .= src[CI((xs, start_y))]
    @inbounds src[CI((startpad_x, ys))] .= src[CI((end_x, ys))]
    @inbounds src[CI((endpad_x, ys))]   .= src[CI((start_x, ys))]

    # Corners ---
    @inbounds src[CI((startpad_x, startpad_y))] .= src[CI((end_x, end_y))]
    @inbounds src[CI((startpad_x, endpad_y))]   .= src[CI((end_x, start_y))]
    @inbounds src[CI((endpad_x, startpad_y))]   .= src[CI((start_x, end_y))]
    @inbounds src[CI((endpad_x, endpad_y))]     .= src[CI((start_x, start_y))]

    return after_update_boundary!(A)
end
function update_boundary!(A::AbstractNeighborhoodArray{S,R}, ::Halo, ::Wrap) where {S<:Tuple{Z,Y,X},R} where {Z,Y,X}
    src = parent(parent(A))
    n_xs, n_ys, n_zs = X, Y, Z
    startpad_x = startpad_y = startpad_z = 1:R
    endpad_x = n_xs+R+1:n_xs+2R
    endpad_y = n_ys+R+1:n_ys+2R
    endpad_z = n_ys+R+1:n_zs+2R
    start_x = start_y = start_z = R+1:2R
    end_x = n_xs+1:n_xs+R
    end_y = n_ys+1:n_ys+R
    end_z = n_zs+1:n_zs+R
    xs = 1:n_xs+2R
    ys = 1:n_ys+2R
    zs = 1:n_zs+2R

    @assert length(startpad_x) == length(start_x) == R
    @assert length(endpad_x) == length(end_x) == R
    @assert length(startpad_y) == length(start_y) == R
    @assert length(endpad_y) == length(end_y) == R
    @assert map(length, (xs, ys, zs)) === size(src)

    CI = CartesianIndices
    # Sides ---
    # X
    @inbounds copyto!(src, CI((startpad_x, ys, zs)), src, CI((end_x, ys, zs)))
    @inbounds copyto!(src, CI((endpad_x, ys, zs)), src, CI((start_x, ys, zs)))
    # Y
    @inbounds copyto!(src, CI((xs, startpad_y, zs)), src, CI((xs, end_y, zs)))
    @inbounds copyto!(src, CI((xs, endpad_y, zs)), src, CI((xs, start_y, zs)))
    # Z
    @inbounds copyto!(src, CI((xs, ys, startpad_z)), src, CI((xs, ys, end_z)))
    @inbounds copyto!(src, CI((xs, ys, endpad_z)), src, CI((xs, ys, start_z)))

    # Corners ---
    @inbounds src[CI((startpad_x, startpad_y, startpad_z))] .= src[CI((end_x, end_y, end_z))]
    @inbounds src[CI((startpad_x, startpad_y, endpad_z))] .= src[CI((end_x, end_y, start_z))]
    @inbounds src[CI((startpad_x, endpad_y, startpad_z))] .= src[CI((end_x, start_y, end_z))]
    @inbounds src[CI((startpad_x, endpad_y, endpad_y))] .= src[CI((end_x, start_y, start_z))]
    @inbounds src[CI((endpad_x, endpad_y, endpad_z))] .= src[CI((start_x, start_y, start_z))]
    @inbounds src[CI((endpad_x, startpad_y, endpad_z))] .= src[CI((end_x, start_y, start_z))]
    @inbounds src[CI((endpad_x, endpad_y, startpad_z))] .= src[CI((start_x, start_y, end_z))]
    @inbounds src[CI((endpad_x, startpad_y, startpad_z))] .= src[CI((start_x, end_y, end_z))]
    return after_update_boundary!(A)
end

# Allow additional boundary updating behaviours
after_update_boundary!(A) = A

radii(x::Int, s::NTuple{N}) where N = ntuple(_ -> ntuple(_ -> x, Val{N}()), Val{N}())
radii(x::Tuple, s::Tuple) = x

