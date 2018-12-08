"""
All outputs must inherit from AbstractOutput.

Simulation outputs are decoupled from simulation behaviour and in
many cases can be used interchangeably.
"""
abstract type AbstractOutput{T} <: AbstractVector{T} end

@premix struct Frames{T<:AbstractVector}
    "An array that holds each frame of the simulation"
    frames::T
end

@premix struct Ok
    running::Array{Bool}
end

@premix struct FPS{F,TS,TR}
    fps::F
    showmax_fps::F
    timestamp::TS
    tref::TR
    store::Bool
end

struct HasFPS end
struct NoFPS end

"Generic ouput constructor. Converts init array to vector of frames."
(::Type{F})(init::T, args...; kwargs...) where F <: AbstractOutput where T <: AbstractMatrix = 
    F(T[init], args...; kwargs...)

# Base methods
length(o::AbstractOutput) = length(o.frames)
size(o::AbstractOutput) = size(o.frames)
firstindex(o::AbstractOutput) = firstindex(o.frames)
lastindex(o::AbstractOutput) = lastindex(o.frames)
getindex(o::AbstractOutput, i) = getindex(o.frames, i)
setindex!(o::AbstractOutput, x, i) = setindex!(o.frames, x, i)
push!(o::AbstractOutput, x) = push!(o.frames, x)
append!(o::AbstractOutput, x) = append!(o.frames, x)


# Custom methods
is_running(o::AbstractOutput) = o.running[1]

set_running!(o::AbstractOutput, val) = o.running[1] = val

is_async(o::AbstractOutput) = false

clear!(o::AbstractOutput) = deleteat!(o.frames, 1:length(o))

has_fps(o::O) where O = :fps in fieldnames(O) ? HasFPS() : NoFPS()

fps(o) = o.fps

store_frame!(o::AbstractOutput, frame, t) = store_frame!(has_fps(o), o, frame, t)
store_frame!(::HasFPS, o, frame, t) = 
    if length(o) == 0
        push!(o, frame)
    elseif o.store
        push!(o, similar(o[1]))
        update_frame!(o, frame, t)
    else
        update_frame!(o, frame, 1)
    end
store_frame!(::NoFPS, o, frame, t) = update_frame!(o, frame, t)

update_frame!(o, frame, t) = begin
    sze = size(o[1])
    for j in 1:sze[2]
        for i in 1:sze[1]
            @inbounds o[t][i, j] = frame[i, j]
        end
    end
end

curframe(o::AbstractOutput, t) = curframe(has_fps(o), o, t)
curframe(::HasFPS, o, t) = o.store ? t : 1
curframe(::NoFPS, o, t) = t

is_showable(o::AbstractOutput, t) = is_showable(has_fps(o), o, t)
is_showable(::HasFPS, o, t) = true # TODO working max fps. o.timestamp + (t - o.tref)/o.showmax_fps < time()
is_showable(::NoFPS, o, t) = false

finalize!(o::AbstractOutput, args...) = nothing

initialize!(o::AbstractOutput, args...) = initialize!(has_fps(o), o, args...)
initialize!(::HasFPS, args...) = nothing
initialize!(::NoFPS, args...) = nothing

delay(o, t) = delay(has_fps(o), o, t)
delay(::HasFPS, o, t) = sleep(max(0.0, o.timestamp + (t - o.tref)/fps(o) - time()))
delay(::NoFPS, o, t) = nothing

set_timestamp!(o, t) = set_timestamp!(has_fps(o), o, t)
set_timestamp!(::HasFPS, o, t) = begin
    o.timestamp = time()
    o.tref = t
end
set_timestamp!(::NoFPS, o, t) = nothing

struct HasMinMax end
struct NoMinMax end
has_minmax(m) = begin
    fn = fieldnames(typeof(m))
    :min in fn && :max in fn ? HasMinMax() : NoMinMax
end

normalize_frame(a::AbstractArray, o) = normalize_frame(has_minmax(o), a, o)
normalize_frame(::HasMinMax, a::AbstractArray, o) = normalize_frame(a, o.min, o.max)
normalize_frame(::NoMinMax, a::AbstractArray, o) = a
normalize_frame(a::AbstractArray, min::Number, max::Number) = (a .- min) ./ (max - min)


"""
    show_frame(output::AbstractOutput, [t])
Show the last frame of the output, or the frame at time t.
"""
show_frame(o::AbstractOutput) = show_frame(o, lastindex(o))
show_frame(o::AbstractOutput, t::Number) = show_frame(o, o[curframe(o, t)], t)
show_frame(o::AbstractOutput, frame::AbstractMatrix) = show_frame(o, frame, 0)
show_frame(o::AbstractOutput, frame, t) = nothing


" peremute image dimensions for Images.jl based outputs "
images_image(o, frame) = process_image(o, permutedims(normalize_frame(o, frame), (2,1)))


" Convert frame matrix to RGB24 "
process_image(o, frame) = Images.RGB24.(frame)

"""
    savegif(filename::String, output::AbstractOutput)
Write the output array to a gif.
Saving very large gifs may trigger a bug in imagemagick.
"""
savegif(filename::String, o::AbstractOutput) =
    FileIO.save(filename, cat(images_image.((o,), o)..., dims=3))
