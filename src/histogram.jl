# --------------------------------------------------------------------
function hist_range(v::Vector{T}; range=[NaN,NaN], bs=NaN, nbins=0) where T <: Real
    ivalid = findall(isfinite.(v))
    if nbins > 0
        isnan(range[1])  &&  (range[1] = minimum(v[ivalid]))
        isnan(range[2])  &&  (range[2] = maximum(v[ivalid]))
        rr = Base.range(range[1], range[2], nbins+1)
        @assert length(rr)  == nbins+1
        @assert minimum(rr) == range[1]
        @assert maximum(rr) == range[2]
    elseif isfinite(bs)
        isnan(range[1])  &&  (range[1] = minimum(v[ivalid]) - bs/2)
        isnan(range[2])  &&  (range[2] = maximum(v[ivalid]) + bs/2)
        rr = range[1]:bs:range[2]
        if maximum(rr) < range[2]
            rr = range[1]:bs:(range[2] + bs)
        end
        @assert minimum(rr) <= range[1]
        @assert maximum(rr) >= range[2]
    else
        rr = hist_range(v, range=range, nbins=Int(ceil(log2(length(v)))) + 1)  # Sturges's formula
    end
    return rr
end


"""
    hist_bins(h::StatsBase.Histogram{T <: Real, 1, R}; side=:left, pad=true)

Returns the coordinates of the bins for a 1D histogram.

Note: the returned coordinates depend on value of the `side` keyword:
- `side=:left` (default): coordinates are returned for the left sides of each bin;
- `side=:center`: coordinates are returned for the center of each bin;
- `side=:right`: coordinates are returned for the right sides of each bin;

If the `pad` keyword is `true` two extra bins are added at the beginning and at the end.
"""
function hist_bins(h::StatsBase.Histogram{T, 1, R}; side=:left, pad=true) where {T <: Real, R}
    if side == :left
        if pad
            return [h.edges[1][1]; h.edges[1]]
        else
            return h.edges[1][1:end-1]
        end
    elseif side == :right
        if pad
            return [h.edges[1]; h.edges[1][end]]
        else
            return h.edges[1][2:end]
        end
    end
    @assert side == :center "Side must be one of `left`, `right` or `center`"
    center = collect(h.edges[1][1:end-1] .+ h.edges[1][2:end]) ./ 2
    if pad
        return [h.edges[1][1]; center; h.edges[1][end]]
    else
        return center
    end
end

"""
    hist_bins(h::StatsBase.Histogram{T <: Real, 2, R}, axis)

Returns the coordinates of the bins for a 2D histogram along the specified axis.

Note: unlike 1D case, the returned coordinate are always located in the center of the bins.
"""
hist_bins(h::StatsBase.Histogram{T, 2, R}, axis::Int) where {T <: Real, R} =
    collect(h.edges[axis][1:end-1] .+ h.edges[axis][2:end]) ./ 2

"""
    hist_weights(h::StatsBase.Histogram{T <: Real, 1, R}; pad=true)
    hist_weights(h::StatsBase.Histogram{T <: Real, 2, R})

Returns the weights of each bin in a histogram.

Note: in the 1D case, if the `pad` keyword is `true` two extra bins
with zero counts are added at the beginning and at the end.
"""
function hist_weights(h::StatsBase.Histogram{T, 1, R}; pad=true) where {T <: Real, R}
    if pad
        return [zero(T); h.weights; zero(T)] .* 1.
    end
    return h.weights .* 1.
end
hist_weights(h::StatsBase.Histogram{T, 2, R}) where {T <: Real, R} = h.weights .* 1.



"""
    hist(v::Vector{T}; range=extrema(v), bs=NaN, nbins=0) where T <: Real

Calculates the histogram of the values in `v`.

# Arguments
- `v`: a vector of values to compute the histogra;
- `range`: values of the left edge of the first bin and of the right edge of the last bin;
- `bs`: size of histogram bins;
- `nbins`: number of bins in the histogram;

If `nbins` is given `bs` is ignored.
Internally, `hist` invokes `StatsBase.fit(Histogram...)` and returns the same data type (see [here](https://juliastats.org/StatsBase.jl/stable/empirical/#Histograms)).  The only difference is that `hist` also accounts for entries on outer edges so that the sum of histogram counts is equal to the length of input vector.  As a consequence, the `closed=` keyword is no longer meaningful. Consider the following example:
```
julia> using StatsBase
julia> v = collect(1:5);
julia> h1 = fit(Histogram, v, 1:5, closed=:left)
julia> h2 = hist(v, range=[1,5], bs=1)
julia> print(h1.weights)
[1, 1, 1, 1]
julia> print(h2.weights)
[1, 1, 1, 2]
julia> @assert length(v) == sum(h1.weights)  # this raises an error!
julia> @assert length(v) == sum(h2.weights)  # this is fine!
```

# Example
```julia
v = randn(1000)
h = hist(v, range=[-3.5, 3.5], bs=0.5)
@gp h  # preview

# Custom appearence
@gp    hist_bins(h) hist_weights(h) "w steps t 'Histogram' lw 3"
@gp :- hist_bins(h) hist_weights(h) "w fillsteps t 'Shaded histogram'" "set style fill transparent solid 0.5"
@gp :- hist_bins(h) hist_weights(h) "w lp t 'side=:left' lw 3"
@gp :- hist_bins(h, side=:center) hist_weights(h) "w lp t 'side=:center' lw 3"
@gp :- hist_bins(h, side=:right)  hist_weights(h) "w lp t 'side=:right' lw 3"
```
"""
function hist(v::Vector{T}; w=Vector{T}(), kws...) where T <: Real
    rr = hist_range(v; kws...)
    if length(w) == 0
        hh = fit(Histogram, v,             rr, closed=:left)
    else
        @assert length(w) == length(v)
        hh = fit(Histogram, v, weights(w), rr, closed=:left)
    end

    # Ensure entries equal to range[2] are accounted for (i.e., ignore the closed= specification)
    i = findall(v .== maximum(hh.edges[1]))
    if length(i) > 0
        if length(w) == 0
            hh.weights[end] += length(i)
        else
            hh.weights[end] += sum(w[i])
        end
    end
    return hh
end


"""
    hist(v1::Vector{T1 <: Real}, v2::Vector{T2 <: Real}; range1=[NaN,NaN], bs1=NaN, nbins1=0, range2=[NaN,NaN], bs2=NaN, nbins2=0)

Calculates the 2D histogram of the values in `v1` and `v2`.

# Arguments
- `v1`: a vector of values along the first dimension;
- `v2`: a vector of values along the second dimension;
- `range1`: values of the left edge of the first bin and of the right edge of the last bin, along the first dimension;
- `range1`: values of the left edge of the first bin and of the right edge of the last bin, along the second dimension;
- `bs1`: size of histogram bins along the first dimension;
- `bs2`: size of histogram bins along the second dimension;
- `nbins1`: number of bins along the first dimension;
- `nbins2`: number of bins along the second dimension;

If `nbins1` (`nbins2`) is given `bs1` (`bs2`) is ignored.
Internally, `hist` invokes `StatsBase.fit(Histogram...)` and returns the same data type (see [here](https://juliastats.org/StatsBase.jl/stable/empirical/#Histograms)).  See help for `hist` in 1D for a discussion on the differences.

# Example
```julia
v1 = randn(1000)
v2 = randn(1000)
h = hist(v1, v2, bs1=0.5, bs2=0.5)
@gp h  # preview
@gp "set size ratio -1" "set autoscale fix" hist_bins(h, 1) hist_bins(h, 2) hist_weights(h) "w image notit"
```
"""
function hist(v1::Vector{T}, v2::Vector{T};
              w=Vector{T}(),
              range1=[NaN,NaN], bs1=NaN, nbins1=0,
              range2=[NaN,NaN], bs2=NaN, nbins2=0) where {T <: Real}
    rr1 = hist_range(v1; range=range1, bs=bs1, nbins=nbins1)
    rr2 = hist_range(v2; range=range2, bs=bs2, nbins=nbins2)
    if length(w) == 0
        hh = fit(Histogram, (v1, v2),             (rr1, rr2), closed=:left)
    else
        @assert length(v1) == length(v2) == length(w)
        hh = fit(Histogram, (v1, v2), weights(w), (rr1, rr2), closed=:left)
    end

    # Ensure entries equal to range[2] are accounted for (i.e., ignore the closed= specification)
    ii = findall((v1 .== maximum(hh.edges[1]))  .|
                 (v2 .== maximum(hh.edges[2])))
    for i1 in 1:(length(hh.edges[1])-1)
        for i2 in 1:(length(hh.edges[2])-1)
            j = ii[findall((hh.edges[1][i1] .<= v1[ii] .<= hh.edges[1][i1+1])  .&
                           (hh.edges[2][i2] .<= v2[ii] .<= hh.edges[2][i2+1]))]
            if length(j) > 0
                if length(w) == 0
                    hh.weights[end, i2] += length(j)
                else
                    hh.weights[end, i2] += sum(w[j])
                end
            end
        end
    end
    return hh
end

# Allow missing values in input
function hist(v::Vector{Union{Missing,T}}; kw...) where T <: Real
    ii = findall(.!ismissing.(v))
    nmissing = length(v) - length(ii)
    (nmissing > 0)  &&  (@info "Neglecting missing values ($(nmissing))")
    hist(convert(Vector{T}, v[ii]); kw...)
end

function hist(v1::Union{Vector{T1}, Vector{Union{Missing,T1}}},
              v2::Union{Vector{T2}, Vector{Union{Missing,T2}}}; kw...) where {T1 <: Real, T2 <: Real}
    @assert length(v1) == length(v2)
    ii = findall(.!ismissing.(v1)  .&  .!ismissing.(v2))
    nmissing = length(v1) - length(ii)
    (nmissing > 0)  &&  (@info "Neglecting missing values ($(nmissing))")
    hist(convert(Vector{T1}, v1[ii]), convert(Vector{T2}, v2[ii]), kw...)
end
