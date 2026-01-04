#!/usr/bin/env julia
using ArgParse, CSV, DataFrames, Pipe, Logging

s = ArgParseSettings()
@add_arg_table! s begin
    "--dir", "-d"
        help = "OCTRTA output directory"
        arg_type = String
        required = true
    "--output", "-o"
        help = "Output directory"
        arg_type = String
        required = false
        default = "."
end

# Helper function for reading in CSV data silently

function load_csv(path::String)
    df = with_logger(NullLogger()) do
        CSV.read(path, DataFrame)
    end
    return df
end

parsed_args = parse_args(ARGS, s)

# Get the filenames of the 'One Code To Rule Them All' output files
octrta_fns = readdir(parsed_args["dir"])

if length(octrta_fns) == 0
    error("No files found in the specified OCTRTA output directory.")
end

# If an output directory was specified, create it if it doesn't exist
if !isdir(parsed_args["output"])
    mkpath(parsed_args["output"])
end

# Filter filenames for transposons and LTRs
octrta_tp_fns = octrta_fns |> filter(fn -> endswith(fn, "transposons.csv"))
octrta_ltr_fns = octrta_fns |> filter(fn -> endswith(fn, "ltr.csv"))

if length(octrta_tp_fns) == 0 && length(octrta_ltr_fns) == 0
    error("No OCTRTA transposon or LTR output files found in the specified directory.")
end

println("Found $(length(octrta_tp_fns)) transposon files and $(length(octrta_ltr_fns)) LTR files.")
println("Aggregating data...")

# Read in the transposon and ltr data as DataFrames
octrta_tp_dfs = 
    map(fn -> load_csv(joinpath(parsed_args["dir"], fn)), 
    octrta_tp_fns
    ) |> filter(df -> nrow(df) > 0)

octrta_ltr_dfs = 
    map(fn -> load_csv(joinpath(parsed_args["dir"], fn)), 
    octrta_ltr_fns
    ) |> filter(df -> nrow(df) > 0)

# Concatenate the DataFrames for transposons and LTRs
df = DataFrame()
if length(octrta_tp_dfs) > 0
    df = vcat(df, vcat(octrta_tp_dfs...))
end
if length(octrta_ltr_dfs) > 0
    df = vcat(df, vcat(octrta_ltr_dfs...))
end

df_compat = select(df, ["Query","Beg.", "End.", "Family", "Element"])
rename!(df_compat,
    "Query" => "Chromosome",
    "Beg." => "Start",
    "End." => "End",
    "Family" => "Type",
    "Element" => "Family"
)
df_compat.GeneID = map(chr -> length(split(chr, "|")) == 2 ? split(chr,"|")[2] : "", df_compat.Chromosome)
df_compat.Chromosome = map(chr -> split(chr, "|")[1], df_compat.Chromosome)

println("Aggregation complete. Writing output files...")

# Write out the aggregated DataFrames to CSV files
CSV.write(joinpath(parsed_args["output"], "aggregated.csv"), df)
CSV.write(joinpath(parsed_args["output"], "aggregated_compat.csv"), df_compat)

println("Done.")