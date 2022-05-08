using Dates
using NCDatasets
using StatsBase
using Unitful
using Statistics
using ClimateBase
using OrderedCollections
using SplitApplyCombine

include(srcdir("dataset", "l2_lcfa_merge.jl"))

lat_degree_to_km(::Quantity) = 110.540f0u"km/°"
lon_degree_to_km(degrees::Quantity) = 111.32f0*cos(degrees)u"km/°"

km_to_lat_degree(::Quantity) = (1.f0/110.54f0)u"°/km"
km_to_lon_degree(degrees::Quantity) = (1.f0/lon_degree_to_km(degrees))

# measures taken from https://es.wikipedia.org/wiki/Geograf%C3%ADa_del_Per%C3%BA#Puntos_extremos
const PERU_N = (-3//100)u"°"
const PERU_S = (-16517//900)u"°"
const PERU_E = (-27463//400)u"°"
const PERU_W = (-11711//144)u"°"

StatsBase.push!(h::Histogram,::NTuple,::Missing) = h

function gridrange(resolution::Quantity, N, S, E, W)
  lat_degrees = km_to_lat_degree(resolution) * resolution
  lat_degrees = uconvert(u"°", lat_degrees)
  lat_range = S:lat_degrees:N
  lon_degrees = mean(km_to_lon_degree.(lat_range)) * resolution
  lon_degrees = uconvert(u"°", lon_degrees)
  lat_range_val = Float32(S.val):lat_degrees.val:Float32(N.val)
  lon_range_val = Float32(W.val):lon_degrees.val:Float32(E.val)
  (lon_range_val, lat_range_val)
end

function generate_grid_lat_lon(resolution::Quantity{T}, N=PERU_N, S=PERU_S, E=PERU_E, W=PERU_W) where {T}
  lon_range_val, lat_range_val = gridrange(resolution, N, S, E, W)
  Histogram((lon_range_val, lat_range_val), Float32)
end

function groupby_floor(records::AbstractVector{FlashRecords}, p::Period)
  g = group(x -> Dates.floor(x.time_start, p), records)
  OrderedDict(sort(collect(zip(keys(g), values(g))), by = first))
end

# Receives a list of records, and return a climate array representing the FED
# It's possible to specify the corners of the grid and both spatial and temporal
# resolution
function generate_climarray(records::AbstractVector{FlashRecords}, s::Quantity, t::Period, N=PERU_N, S=PERU_S, E=PERU_E, W=PERU_W)
  groups = groupby_floor(records, t)
  lon_range, lat_range = gridrange(s, N, S, E, W)
  grid = Histogram((lon_range, lat_range, 1:length(groups)+1), Float32)
  for (i, group) in enumerate(values(groups))
    for r in group
      append!(grid, (r.longitude, r.latitude, fill!(zeros(Float32, length(r.longitude)), i)))
    end
    view(grid.weights, :, :, i) ./= length(group)
  end
  lon_dim = Lon(lon_range[begin:end-1])
  lat_dim = Lat(lat_range[begin:end-1])
  time_dim = Ti(collect(keys(groups)))
  ClimArray(grid.weights, (lon_dim, lat_dim, time_dim); name="FED", attrib=Dict())
end


# Adapted from https://github.com/JuliaClimate/ClimateBase.jl/blob/35b5e8f85638b7f1d3127b7a446de38afba2c6b6/src/io/netcdf_write.jl#L40
function ncwrite_compressed(file::String, Xs; globalattr = Dict(), deflatelevel)
  if any(X -> hasdim(X, Coord), Xs)
    error("""
    Outputing `UnstructuredGrid` coordinates to .nc files is not yet supported,
    but it is an easy fix, see source of `ncwrite`.
    """)
  end

  ds = NCDataset(file, "c"; attrib = globalattr)
  for (i, X) in enumerate(Xs)
    n = string(X.name)
    if n == ""
      n = "x$i"
      @warn "$i-th ClimArray has no name, naming it $(n) instead."
    end
    ClimateBase.add_dims_to_ncfile!(ds, dims(X))
    attrib = X.attrib
    isnothing(attrib) && (attrib = Dict())
    dnames = ClimateBase.dim_to_commonname.(dims(X))
    data = Array(X)
    ClimateBase.defVar(ds, n, data, (dnames...,); attrib, deflatelevel)
  end
  close(ds)
end

function ncwrite_compressed(file::String, X::ClimArray; globalattr = Dict(), deflatelevel=1)
  ncwrite_compressed(file, (X,); globalattr, deflatelevel)
end