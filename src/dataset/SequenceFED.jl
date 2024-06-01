using HDF5
using DrWatson
using Random

function read_from_file(path)
  h5read(path, "FED")
end

function read_from_folder(path)
  paths = readdir(path; join=true)
  datasets = read_from_file.(paths)
  cat(datasets...; dims=4)
end

function get_dataset(; splitratio, batchsize, N, path, kwargs...)
  @assert ispath(path) "$path is not a path"
  if isfile(path)
    dataset = read_from_file(path)
  elseif isdir(path)
    dataset = read_from_folder(path)
  end
  @info "rotating dataset"
  Random.seed!(42)
  dataset = cat(dataset, mapslices(Base.Fix2(rotr90, 1), dataset, dims=(1,2)))
  dataset[:, :, :, shuffle(axes(dataset, 4)), :] = dataset
  dataset = cat(dataset, mapslices(rot180, dataset, dims=(1,2)))

  TOTAL_SAMPLES = size(dataset, 4)
  TOTAL_FRAMES = size(dataset, 5)
  last_train_sample_index = ceil(Int, TOTAL_SAMPLES * splitratio)
  dataset_train = view(dataset, :, :, :, 1:last_train_sample_index, :)
  dataset_test = view(dataset, :, :, :, last_train_sample_index+1:TOTAL_SAMPLES, :)

  x_train = (copy(view(dataset_train, :, :, :, t:t+batchsize-1, 1:N)) for t in 1:batchsize:size(dataset_train, 4)-batchsize+1)
  y_train = (copy(view(dataset_train, :, :, :, t:t+batchsize-1, N+1:TOTAL_FRAMES)) for t in 1:batchsize:size(dataset_train, 4)-batchsize+1)
  train_data = zip(x_train, y_train)

  x_test = (copy(view(dataset_test, :, :, :, t:t+batchsize-1, 1:N)) for t in 1:batchsize:size(dataset_test, 4)-batchsize+1)
  y_test = (copy(view(dataset_test, :, :, :, t:t+batchsize-1, N+1:TOTAL_FRAMES)) for t in 1:batchsize:size(dataset_test, 4)-batchsize+1)
  test_data = zip(x_test, y_test)

  train_data, test_data
end
