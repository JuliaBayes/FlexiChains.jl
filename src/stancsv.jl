using DelimitedFiles: readdlm

"""
    FlexiChains.from_stan_csv(
        base_path::AbstractString, num_chains::Integer, key_spec=nothing
    )::FlexiChain

Reads the Stan CSV files from `{base_path}_1.csv` through to `{base_path}_{num_chains}.csv`.
This is a convenience method that recognises the fact that CmdStan saves its outputs in this
format.

!!! note
    You do not need to provide the underscore before the chain number in the filename! That
    is, if your files are `example_1.csv` etc., then `base_path` should just be `"example"`.

See the other method of `from_stan_csv` for details of the `key_spec` argument.
"""
function from_stan_csv(
    base_path::AbstractString,
    num_chains::Integer,
    key_spec::Union{Nothing,Tuple}=nothing,
)
    if num_chains <= 0
        throw(ArgumentError("num_chains must be at least 1"))
    end
    csv_paths = ["$(base_path)_$(i).csv" for i in 1:num_chains]
    return from_stan_csv(csv_paths, key_spec)
end

"""
    FlexiChains.from_stan_csv(
        csv_paths::AbstractVector{<:AbstractString}, key_spec=nothing
    )::FlexiChain

Parse a set of Stan CSV files at the given paths.

These files must correspond to a set of compatible chains, i.e., their parameter names,
lengths (i.e., number of iterations), and other data should be consistent. This will be the
case if they were all drawn from the same call to Stan's sampling. However, note that
FlexiChains does only a rudimentary set of checks to ensure consistency: the user should be
responsible for ensuring that the CSVs read in are valid.

If `key_spec` is not provided, columns that end in double-underscores (`__`) are treated as
`Extra`s (the underscores will be stripped), and all other columns as `Parameter{Symbol}`s,
giving a `FlexiChain{Symbol}`.

If `key_spec` is provided, it is passed directly to the `FlexiChain` from-array constructor,
and the key type of the resulting `FlexiChain` is inferred from it. `key_spec` must cover
every column of the CSV files, in order, including the sampler columns (e.g. `lp__`) that
CmdStan writes before the model's own parameters. This lets you, for example, use `VarName`
keys, or group array-valued parameters together: since CmdStan writes arrays in
column-major order, `Parameter(@vn(Sigma)) => (2, 2)` will correctly reconstruct a 2x2
matrix `Sigma` from the columns `Sigma.1.1`, `Sigma.2.1`, `Sigma.1.2`, `Sigma.2.2`.

Please see [the `FlexiChain` constructor documentation](@ref
FlexiChains.FlexiChain(::AbstractArray{T,3}, key_spec) where {T}) for details on what
`key_spec` is allowed.
"""
function from_stan_csv(
    csv_paths::AbstractVector{<:AbstractString},
    key_spec::Union{Nothing,Tuple}=nothing,
)
    isempty(csv_paths) && throw(ArgumentError("no CSV paths provided"))

    # Parse sampling settings from the first CSV. This is pretty ugly, but well, it doesn't
    # have to be pretty.
    first_csv_path = first(csv_paths)
    if !isfile(first_csv_path)
        throw(
            ArgumentError(
                "could not find Stan CSV file for chain 1 at path: $first_csv_path",
            ),
        )
    end
    nsamples = nothing
    thin = nothing
    save_warmup = nothing
    nwarmup = nothing
    open(first_csv_path) do io
        for line in eachline(io)
            startswith(line, '#') || break
            m = match(r"^#\s*num_samples\s*=\s*(\d+)", line)
            m !== nothing && (nsamples = parse(Int, m.captures[1]))
            m = match(r"^#\s*thin\s*=\s*(\d+)", line)
            m !== nothing && (thin = parse(Int, m.captures[1]))
            m = match(r"^#\s*save_warmup\s*=\s*(true|false)", line)
            m !== nothing && (save_warmup = m.captures[1] == "true")
            m = match(r"^#\s*num_warmup\s*=\s*(\d+)", line)
            m !== nothing && (nwarmup = parse(Int, m.captures[1]))
        end
    end
    if any(x -> x === nothing, [nsamples, thin, save_warmup, nwarmup])
        throw(
            ArgumentError(
                "failed to parse sampling settings from CSV metadata comments; please check the CSV file at $first_csv_path and ensure it contains the expected metadata comments for num_samples, thin, save_warmup, and num_warmup",
            ),
        )
    end

    iter_indices = if save_warmup
        warmup_iters = 1:nwarmup
        sample_iters = range(nwarmup + 1, step=thin, stop=nwarmup + nsamples)
        vcat(warmup_iters, sample_iters)
    else
        range(nwarmup + 1, step=thin, stop=nwarmup + nsamples)
    end
    niters = length(iter_indices)

    # Read chains from CSV files into Dict(Symbol => Vector{Float64})
    header = nothing
    data = []
    sampling_times = Union{Float64,Missing}[]
    for (i, csv_path) in enumerate(csv_paths)
        if !isfile(csv_path)
            throw(
                ArgumentError(
                    "could not find Stan CSV file for chain $i at path: $csv_path",
                ),
            )
        end
        data_i, header_i = readdlm(csv_path, ','; header=true, comments=true)
        # data_i should be niters x nparams
        if i == 1
            push!(data, data_i)
            header = header_i
        else
            if size(data_i) != size(data[1])
                throw(
                    ArgumentError(
                        "data from chain $i (file: $csv_path) has size $(size(data_i)), which does not match $(size(data[1])) in chain 1 (file: $(csv_paths[1]))",
                    ),
                )
            end
            if header != header_i
                throw(
                    ArgumentError(
                        "column names from chain $i (file: $csv_path) are not consistent with chain 1 (file: $(csv_paths[1]))",
                    ),
                )
            end
            push!(data, data_i)
        end
        # Parse sampling time from footer comments
        push!(sampling_times, _parse_stan_sampling_time(csv_path))
    end
    data = stack(data) # niters x nparams x nchains

    if key_spec !== nothing
        # The FlexiChain from-array constructor expects (niters, nchains, nparams).
        return FlexiChain{_infer_key_type(key_spec)}(
            permutedims(data, (1, 3, 2)),
            key_spec;
            iter_indices=iter_indices,
            sampling_time=sampling_times,
        )
    end

    data_dict = OrderedDict{ParameterOrExtra{<:Symbol},Matrix{Float64}}()
    # Sort out parameters vs extras based on header names
    for (i, colname) in enumerate(header)
        if endswith(colname, "__")
            data_dict[Extra(Symbol(colname[1:(end-2)]))] = data[:, i, :]
        else
            data_dict[Parameter(Symbol(colname))] = data[:, i, :]
        end
    end
    return FlexiChain{Symbol}(
        niters,
        length(csv_paths),
        data_dict;
        iter_indices=iter_indices,
        sampling_time=sampling_times,
    )
end

function _parse_stan_sampling_time(csv_path::AbstractString)
    for line in Iterators.reverse(eachline(csv_path))
        m = match(r"([\d.]+)\s*seconds\s*\(Total\)", line)
        m !== nothing && return parse(Float64, m.captures[1])
    end
    return missing
end
