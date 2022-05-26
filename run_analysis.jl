using Pkg
Pkg.activate(".")

using BenchmarkTools, Plots, LaTeXStrings

include("src/ParametersJSON.jl")
include("src/Lattices/CubicLattice2D.jl")
include("src/Ashkin_Teller/AT_Hamiltonian.jl")
include("src/Ashkin_Teller/AT_State.jl")
include("src/Monte_Carlo_Core/MonteCarloCore.jl")
include("src/SimulationParameters.jl")
include("src/File_Handling/FileHandling.jl")
include("src/Spin_Lattice/HyperfineFields.jl")

model_name = "Ashkin-Teller"
import_directory = simulation_date_directory(model_name, Dates.now())

sim_params = import_paramters(import_directory, AT_2DCL_Metro_Params{Float64}, "job-1")

for (betadx, β) ∈ enumerate(sim_params.mc_params.βvalues)
    temperature = round(1/β, digits=3)
    println("\nAnalyzing T = $temperature data...\n")
    # sim_params, analysis_states = import_simulation(import_directory, AT_2DCL_Metro_Params{Float64}, "job-1")
    analysis_states = import_simulation(import_directory, AT_2DCL_Metro_Params{Float64}, "betadx-$(betadx)")
    analysis_latt = (reciprocal_type(sim_params.latt_params))(sim_params.latt_params)
    analysis_ham  = (reciprocal_type(sim_params.ham_params))(analysis_latt, sim_params.ham_params)

    (num_dof, num_states) = size(analysis_states)
    num_AT_sites = num_dof / NUM_AT_COLORS

    data_t = eltype(analysis_states)
    sweep_indices = sweeps_per_export(sim_params.mc_params) .* (1:1:num_states)
    sigma_indices = 1:NUM_AT_COLORS:num_dof
    tau_indices   = 2:NUM_AT_COLORS:num_dof

    analysis_states[tau_indices, :] *= -1

    # Energies, sigma and tau mags
    energies = zeros(data_t, num_states)
    mags = zeros(data_t, NUM_AT_COLORS, num_states)
    @inbounds for idx ∈ eachindex(1:num_states)
        energies[idx] = AT_total_energy(analysis_states[:, idx], analysis_ham.params, analysis_latt) / num_AT_sites
        mags[1, idx] = sum(analysis_states[sigma_indices, idx]) / num_AT_sites
        mags[2, idx] = sum(analysis_states[tau_indices,   idx]) / num_AT_sites
    end

    energy_plt = plot( sweep_indices, energies,
                    color=:green, xticks=nothing,
                    ylabel = L"$E/N$",
                    label = nothing)

    sigma_plt = plot( sweep_indices, mags[1, :], 
                    color=:blue, xticks=nothing,
                    ylabel = L"$N^{-1}\sum_i \sigma_i$", 
                    label=nothing)

    tau_plt   = plot( sweep_indices, mags[2, :], 
                    color=:orange, xlabel = "MC Sweeps",
                    ylabel = L"$N^{-1}\sum_i \tau_i$", 
                    label=nothing)


    timerecordplt = plot( energy_plt, sigma_plt, tau_plt, layout=(3,1), link = :x,
                          plot_title="\$\\beta = $(β)\\,J^{-1} = ($(temperature)\\,J)^{-1}\$")
    savefig(timerecordplt, joinpath(import_directory, "time_records_T-$(temperature).png"))

    @time all_fluctuations = populate_all_hyperfine_fluctuations(Out_of_Plane, analysis_states, analysis_latt)
    fluct_dists = analyze_fluctuations!(all_fluctuations, analysis_states, analysis_latt; analysis = mean)

    for (typedx, type) ∈ enumerate(mag_vector_types)
        println("Magnetic model: $type")
        @show mean(fluct_dists[:, typedx])
    end

    histplt = histogram(fluct_dists;
                        xlabel = L"$\mathcal{W}(\mathbf{x})$ $(\textrm{ T}/\mu_B)^2$", ylabel="Counts",
                        label = permutedims(replace.(String.(Symbol.(mag_vector_types)), "_" => " ")),
                        plot_title="\$\\beta = $(β)\\,J^{-1} = ($(temperature)\\,J)^{-1}\$",
                        legend = :topright,
                        alpha = 0.7, linecolor = :match)

    savefig(histplt, joinpath(import_directory, "W_histograms_T-$(temperature).png"))
    vscodedisplay(histplt)
end