@doc raw"""
    quarnetGoFtest!(net::HybridNetwork, df::DataFrame, optbl::Bool; quartetstat=:LRT, correction=:simulation, seed=1234, nsim=1000, verbose=false, keepfiles=false)
    quarnetGoFtest!(net::HybridNetwork, dcf::DataCF,   optbl::Bool; kwargs...)

Goodness-of-fit test for the adequacy of the multispecies network coalescent,
to see if a given population or species network explains the
quartet concordance factor data adequately.
The network needs to be of level 1 at most (trees fullfil this condition),
and have branch lengths in coalescent units.
The test assumes a multinomial distribution for the observed quartet
concordance factors (CF), such that information on the number of genes for each
four-taxon set (`ngenes` field) must be present.

For each four-taxon set, an outlier p-value is obtained by comparing a
test statistic (-2log likelihood ratio by default) to a chi-square distribution
with 2 degrees of freedom (see below for other options).

The four-taxon sets are then categorized as outliers or not, according to their
outlier p-values (outlier if p<0.05).
Finally, a one-sided goodness-of-fit test is performed on the frequency of
outlier 4-taxon sets to see if there are more outliers than expected.
The z-value for this test corresponds to the null hypothesis that
5% outlier p-values are < 0.05 (versus more than 5%):

```math
z = \frac{\mathrm{proportion.outliers} - 0.05}{\sqrt{0.05 \times 0.95/\mathrm{number.4taxon.sets}}}.
```

This z-value corresponds to a test that assumes independent outlier p-values
across 4-taxon sets: it makes no correction for dependence.

To correct for dependence with `correction=:simulation`, the distribution of
z-values is obtained by simulating gene trees under the coalescent along the
network (after branch length optimization if `optbl=true`)
using [PhyloCoalSimulations](https://github.com/JuliaPhylo/PhyloCoalSimulations.jl).
The z-score is calculated on each simulated data set.
Under independence, these z-scores have mean 0 and variance 1.
Under dependence, these z-scores still have mean 0, but an inflated variance.
This variance σ² is estimated from the simulations, and the corrected p-value
is obtained by comparing the original z value to N(0,σ²).
When `correction=:none`, σ is taken to be 1 (independence): *not* recommended!

- The first version takes a `DataFrame` where each row corresponds to a given
  four-taxon set. The data frame is modified by having an additional another column
  containing the p-values corresponding to each four-taxon set.
- The second version takes a `DataCF` object and modifies it by updating
  the expected concordance factors stored in that object.

Note that `net` is **not** modified.

# arguments

- `optbl`: when `false`, branch lengths in `net` are taken as is, and need to be
  in coalescent units.
  When `optbl=true`, branch lengths in `net` are optimized, to optimize the
  pseudo log likelihood score as in SNaQ (see
  [here](https://JuliaPhylo.github.io/PhyloNetworks.jl/stable/lib/public/#PhyloNetworks.topologyMaxQPseudolik!)).
  In both cases, any missing branch length is assigned a value with
  [`ultrametrize!`](@ref), which attempts to make the major tree ultrametric
  (but never modifies an existing edge length).
  Missing branch lengths may arise if they are not identifiable, such as
  lengths of external branches if there is a single allele per taxon.
  The network is returned as part of the output.

# keyword arguments

- `quartetstat`: the test statistic used to obtain an outlier p-value for
  each four-taxon set, which is then compared to a chi-squared distribution
  with 2 degrees of freedom to get a p-value.
  * `:LRT` is the default, for the likelihood ratio:
    ``2n_\mathrm{genes} \sum_{j=1}^3 {\hat p}_j (\log{\hat p}_j - \log p_j)``
    where ``p_j``
    is the quartet CF expected from the network, and ``{\hat p}_j`` is the
    quartet CF observed in the data.
  * `:Qlog` for the Qlog statistics (Lorenzen, 1995):
    ``2n_\mathrm{genes} \sum_{j=1}^3 \frac{({\hat p}_j - p_j)^2}{p_j (\log{\hat p}_j - \log p_j)}``
    and
  * `:pearson` for Pearon's chi-squared statistic, which behaves poorly when
    one or more expected counts are low (e.g. less than 5):
    ``n_\mathrm{genes} \sum_{j=1}^3 \frac{({\hat p}_j - p_j)^2 }{p_j}``
- `correction=:simulation` to correct for dependence across 4-taxon.
  Use `:none` to turn off simulations and the correction for dependence.
- `seed=1234`: master seed to control the seeds for gene tree simulations.
- `nsim=1000`: number of simulated data sets. Each data set is simulated to have the
  median number of genes that each 4-taxon sets has data for.
- `verbose=false`: turn to `true` to see progress of simulations and
  to diagnose potential issues.
- `keepfiles=false`: if true, simulated gene trees are written to files, one
  file for each of the 1000 simulations. If created (with `keepfiles=true`),
  these files are stored in a newly created folder
  whose name starts with `jl_` and is placed in the current directory.

# output

1. p-value of the overall goodness-of-fit test (corrected for dependence if requested)
2. uncorrected z value test statistic
3. estimated σ for the test statistic used for the correction (1.0 if no correction)
4. a vector of outlier p-values, one for each four-taxon set
5. network (first and second versions):
   `net` with loglik field updated if `optbl` is false;
    copy of `net` with optimized branch lengths and loglik if `optbl` is true
6. in case `correction = :simulation`, vector of simulated z values
   (`nothing` if `correction = :none`). These z-values could be used to
   calculate an empirical p-value (instead of the p-value in #1), as the
   proportion of simulated z-values that are ⩾ the observed z-value (in #2).

# references

- Ruoyi Cai & Cécile Ané (2021).
  Assessing the fit of the multi-species network coalescent to multi-locus data.
  Bioinformatics, 37(5):634-641.
  doi: [10.1093/bioinformatics/btaa863](https://doi.org/10.1093/bioinformatics/btaa863)

- Lorenzen (1995).
  A new family of goodness-of-fit statistics for discrete multivariate data.
  Statistics & Probability Letters, 25(4):301-307.
  doi: [10.1016/0167-7152(94)00234-8](https://doi.org/10.1016/0167-7152(94)00234-8)
"""
function quarnetGoFtest!(net::HybridNetwork,  df::DataFrame, optbl::Bool; kwargs...)
    d = readTableCF(df);
    res = quarnetGoFtest!(net, d, optbl; kwargs...);
    df[!,:p_value] .= res[4] # order in "res": overallpval, uncorrected z-value, sigma, pval, ...
    return res
end

function quarnetGoFtest!(net::HybridNetwork, dcf::DataCF, optbl::Bool;
                         quartetstat::Symbol=:LRT, correction::Symbol=:simulation,
                         seed=1234::Int, nsim=1000::Int, verbose=false::Bool, keepfiles=false::Bool)
    correction in [:simulation, :none] || error("correction ($correction) must be one of :none or :simulation")
    quartetstat in [:LRT, :Qlog, :pearson] || error("$quartetstat is not a valid quartetstat option")
    if optbl
        net_saved = net
        # default tolerance values are too lenient
        net = topologyMaxQPseudolik!(net,dcf, ftolRel=1e-12, ftolAbs=1e-10, xtolRel=1e-10, xtolAbs=1e-10)
        reroot!(net, net_saved) # restore the root where it was earlier
    else
        net = deepcopy(net) # because we may assign values to missing branch lengths
    end
    # below: to update expected CFs. not quite done by topologyMaxQPseudolik!
    topologyQPseudolik!(net,dcf)
    # assign values to missing branch lengths
    # hybrid-lambda required a time-consistent and ultrametric network...
    # PhyloCoalSimulations.simulatecoalescent still requires no missing edge length.
    ultrametrize!(net, false) # verbose=false bc ultrametricity & time-consistency are allowed with PhyloCoalSimulations
    outlierp_fun! = ( quartetstat ==  :LRT ? multinom_lrt! :
                     (quartetstat == :Qlog ? multinom_qlog! : multinom_pearson!))
    gof_zval, outlierpvals = quarnetGoFtest(dcf.quartet, outlierp_fun!)
    sig = 1.0 # 1 if independent: correction for dependence among 4-taxon set outlier pvalues
    sim_zvals = nothing
    if correction == :simulation
        # expCF in dcf correspond to net: assumption made below
        sig, sim_zvals = quarnetGoFtest_simulation(net, dcf, outlierp_fun!, seed, nsim, verbose, keepfiles)
    end
    overallpval = normccdf(gof_zval/sig) # one-sided: P(Z > z)
    return (overallpval, gof_zval, sig, outlierpvals, net, sim_zvals)
end

"""
    quarnetGoFtest(quartet::Vector{Quartet}, outlierp_fun!::Function)
    quarnetGoFtest(outlier_pvalues::AbstractVector)

Calculate an outlier p-value for each `quartet` according to function `outlierp_fun!`
(or take outlier-values as input: second version) and calculate the z-value
to test the null hypothesis that 5% of the p-values are < 0.05, versus
the one-sided alternative of more outliers than expected.

See [`quarnetGoFtest!`](@ref) for more details.

Output:
- z-value
- outlier p-values (first version only)
"""
function quarnetGoFtest(quartet::Vector{Quartet}, outlierp_fun!::Function)
   for q in quartet
        q.ngenes > 0 || error("quartet $q does not have info on number of genes")
    end
    pval = fill(-1.0, length(quartet))
    outlierp_fun!(pval, quartet) # calculate outlier p-values
    gof_zval = quarnetGoFtest(pval)
    return (gof_zval, pval)
end

function quarnetGoFtest(pval::AbstractVector)
    # uncorrected z-value: from one-sided test after binning p-values into [0,.05) and [.05,1.0]
    nsmall = count(p -> p < 0.05, pval)
    ntot = count(p -> isfinite(p), pval)
    ntot == length(pval) || @warn "$(length(pval) - ntot) outlier p-value(s) is/are Inf of NaN..."
    gof_zval = (nsmall/ntot - 0.05)/sqrt(0.0475/ntot) # 0.0475 = 0.05 * (1-0.05)
    return gof_zval
end

"""
    quarnetGoFtest_simulation(net::HybridNetwork, dcf::DataCF, outlierp_fun!::Function,
                              seed::Int, nsim::Int, verbose::Bool, keepfiles::Bool)

Simulate gene trees under the multispecies coalescent model along network `net`
using [PhyloCoalSimulations](https://github.com/JuliaPhylo/PhyloCoalSimulations.jl).
The quartet concordance factors (CFs) from these simulated gene trees are used
as input to `outlierp_fun!` to categorize each 4-taxon set as an outlier
(p-value < 0.05) or not.
For each simulated data set, a goodness-of-fit z-value is calculated by
comparing the proportion of outlier 4-taxon sets to 0.05. The standard deviation
of these z-values (assuming a mean of 0), and the z-values themselves are returned.

Used by [`quarnetGoFtest!`](@ref).

**Warning**: The quartet CFs expected from `net` are assumed to be stored in
`dcf.quartet[i].qnet.expCF`. This is *not* checked.
"""
function quarnetGoFtest_simulation(net::HybridNetwork, dcf::DataCF, outlierp_fun!::Function,
        seed::Int, nsim::Int, verbose::Bool, keepfiles::Bool)
    ngenes = ceil(Int, median(q.ngenes for q in dcf.quartet))
    # how to handle case when different #genes across quartets? need taxon set for each gene, not just ngenes.
    seed!(seed) # master seed
    repseed = rand(1:10_000_000_000, nsim) # 1 seed for each simulation
    nq = length(dcf.quartet)
    pval = fill(-1.0, nq) # to be re-used across simulations, but NOT shared between processes
    sim_zval = SharedArray{Float64}(nsim) # to be shared between processes
    # expected CFs: in dcf.quartet[i].qnet.expCF[j] for 4-taxon set i and resolution j
    # BUT countquartetsintrees might list 4-taxon sets in a different order, and might list
    # the 4 taxa within a set in a different order -> need to re-order resolutions within a set
    # previously: suffix "_1" instead of "" because hybrid-Lambda adds suffix "_1" to all taxon names (if individual/tip)
    expCF, taxa = expectedCF_ordered(dcf, net, "") # 'taxa' gives the map i -> taxon[i]
    if keepfiles
        genetreedir = mktempdir(pwd()) # temporary directory to store gene tree files
    end
    @sync @distributed for irep in 1:nsim
        verbose && @info "starting replicate $irep"
        seed!(repseed[irep])
        treelist = simulatecoalescent(net, ngenes, 1)
        keepfiles && writeMultiTopology(treelist, joinpath(genetreedir, "genetrees_rep$irep.trees"));
        length(treelist) == ngenes || @warn "unexpected number of gene trees, file $gt" # sanity check
        obsCF, t = countquartetsintrees(treelist; showprogressbar=verbose)
        # on 1 replicate only, check that the taxa come in the correct order
        irep == 1 && (taxa == t || error("different order of taxa used by countquartetsintrees"))
        outlierp_fun!(pval, (q.data for q in obsCF), expCF) # calculate outlier p-values
        sim_zval[irep] = quarnetGoFtest(pval)
    end
    mean_z2 = sum(sim_zval.^2)/nsim
    sigma = sqrt(mean_z2) # estimated sigma, assuming mean=0
    # check that the mean z values fit with "true mean z = 0"
    # if not, would point to a bug: mismatch btw simulated gene trees and expected CFs
    mean_z = sum(sim_zval)/nsim
    var_z = mean_z2 - mean_z^2 # 0 if nsim=1
    abs(mean_z / sqrt(var_z/nsim)) < 4 || nsim==1 || # conservative: -4 < z-statistic < 4
        @warn """The simulated z values are far from 0: with a mean of $(round(mean_z,digits=4))
        and a standard deviation of $(round(sqrt(var_z),digits=4)).
        Perhaps you ran very few simulations for the correction; or have few loci
        and some quartets with very low discordance? You may want to run many
        simulations (1000 or more) then calculate an empirical p-value, like this:

        gof = quarnetGoFtest!(your_network, your_data, etc.)
        zvalue_observed = gof[2]
        zvalue_bootstrap = sort!(gof[6]) # long vector: sorted z-values simulated under the network
        using Statistics # if not done earlier: to get access to "mean" function
        pvalue = mean(zvalue_bootstrap .>= zvalue_observed) # one-sided test: Prob(Z > z)
        """
    return sigma, sim_zval
end

"""
    expectedCF_ordered(dcf::DataCF, net::HybridNetwork, suffix=""::AbstractString)

Expected quartet concordance factors in `dcf`, but ordered as they would be if
output by `PhyloNetworks.countquartetsintrees`.
Output:
- 2-dimentional `SharedArray` (number of 4-taxon sets x 3).
  `dcf.quartet[i].qnet.expCF[j]` for 4-taxon set `i` and resolution `j`
  is stored in row `qi` and column `k` if `qi` is the rank of 4-taxon set `i`
  (see `PhyloNetworks.quartetrank`). This rank depends on how taxa are ordered.
- vector of taxon names, whose order matters. These are tip labels in `net` with
  suffix `suffix` added, then ordered alphabetically, or
  numerically if taxon names can be parsed as integers.
"""
function expectedCF_ordered(dcf::DataCF, net::HybridNetwork, suffix=""::AbstractString)
    nq = length(dcf.quartet)
    expCF = SharedArray{Float64, 2}(nq,3)
    # careful ordering: ["t","t_0"] ordered differently after we add suffix "_1"
    taxa = PN.sort_stringasinteger!(tipLabels(net) .* suffix) # same as done in countquartetsintrees
    nsuff = length(suffix)
    taxonnumber = Dict(chop(taxa[i];tail=nsuff) => i for i in eachindex(taxa))
    ntax = length(taxa)
    nCk = PN.nchoose1234(ntax) # matrix used to ranks 4-taxon sets
    nq == nCk[ntax+1,4] || error("dcf is assumed to contain ALL $(nCk[ntax+1,4]) four-taxon sets, but contains $nq only.")
    ptype = Vector{Int8}(undef,4) # permutation vector to sort the 4 taxa
    resperm = Vector{Int8}(undef,3) # permutation to sort the 3 resolutions accordingly
    for q in dcf.quartet
        tn = map(i->taxonnumber[i], q.taxon)
        sortperm!(ptype, tn)
        qi = PN.quartetrank(tn[ptype]..., nCk)
        # next: find the corresponding permutation of the 3 CFs.
        # this permutation is invariant to permuting ptype like: [a b c d] -> [c d a b] or [b a d c]
        # modify ptype to have 1 first, then only 6 permutations, corresponding to 6 permutations of 3 resolutions
        ptype .-= 0x01
        if ptype[1]==0x00
            resperm[1] = ptype[2]
            resperm[2] = ptype[3]
            resperm[3] = ptype[4]
        elseif ptype[2]==0x00 # consider ptype[[2,1,4,3]] to put 0(=1-1) first
            resperm[1] = ptype[1]
            resperm[2] = ptype[4]
            resperm[3] = ptype[3]
        elseif ptype[3]==0x00 # consider ptype[[3,4,1,2]] to put 0(=1-1) first
            resperm[1] = ptype[4]
            resperm[2] = ptype[1]
            resperm[3] = ptype[2]
        else # consider ptype[[4,3,2,1]] to put 0(=1-1) first instead of last
            resperm[1] = ptype[3]
            resperm[2] = ptype[2]
            resperm[3] = ptype[1]
        end
        expCF[qi,:] = q.qnet.expCF[resperm]
    end
    return expCF, taxa
end

"""
    multinom_pearson!(pval::AbstractVector{Float64}, quartet::Vector{Quartet})
    multinom_pearson!(pval::AbstractVector{Float64}, obsCF, expCF::AbstractMatrix{Float64})

Calculate outlier p-values (one per four-taxon set)
using Pearson's chi-squared statistic under a multinomial distribution
for the observed concordance factors.
"""
function multinom_pearson!(pval::AbstractVector{Float64}, quartet::Vector{Quartet})
    nq = length(quartet)
    for i in 1:nq
        qt = quartet[i]
        phat = qt.obsCF
        p = qt.qnet.expCF
        ngenes = qt.ngenes
        ipstat = ngenes * sum((phat .- p).^2 ./ p)
        pval[i] = chisqccdf(2, ipstat)
    end
    return nothing
end
function multinom_pearson!(pval::AbstractVector{Float64}, obsCF, expCF::AbstractMatrix{Float64})
    for (i,o) in enumerate(obsCF) # o = [observedCF, ngenes]
        p = expCF[i,:]
        ipstat = o[4] * sum((o[1:3] .- p).^2 ./ p)
        pval[i] = chisqccdf(2, ipstat)
    end
end


"""
    multinom_qlog!(pval::AbstractVector{Float64}, quartet::Vector{Quartet})
    multinom_qlog!(pval::AbstractVector{Float64}, obsCF, expCF::AbstractMatrix{Float64})

Calculate outlier p-values (one per four-taxon set)
using the Qlog statistic (Lorenzen, 1995),
under a multinomial distribution for the observed concordance factors.
"""
function multinom_qlog!(pval::AbstractVector{Float64}, quartet::Vector{Quartet})
    nq = length(quartet)
    for i in 1:nq
        qt = quartet[i]
        phat = qt.obsCF
        p = qt.qnet.expCF
        ngenes = qt.ngenes
        mysum = 0.0
        for j in 1:3
            if phat[j] > eps(Float64) && !isapprox(phat[j],p[j]; atol=1e-20)
                mysum += (phat[j]-p[j])^2/(p[j]*(log(phat[j])-log(p[j])))
            end
        end
        iqstat = 2 * ngenes * mysum
        pval[i] = chisqccdf(2,iqstat)
    end
    return nothing
end
function multinom_qlog!(pval::AbstractVector{Float64}, obsCF, expCF::AbstractMatrix{Float64})
    for (i,o) in enumerate(obsCF) # o = [observedCF, ngenes]
        p = expCF[i,:]
        mysum = 0.0
        for j in 1:3
            if o[j] > eps(Float64) && !isapprox(o[j],p[j]; atol=1e-20)
                mysum += (o[j]-p[j])^2/(p[j]*(log(o[j])-log(p[j])))
            end
        end
        iqstat = 2 * o[4] * mysum
        pval[i] = chisqccdf(2,iqstat)
    end
end

"""
    multinom_lrt!(pval::AbstractVector{Float64}, quartet::Vector{Quartet})
    multinom_lrt!(pval::AbstractVector{Float64}, obsCF, expCF::AbstractMatrix{Float64})

Calculate outlier p-values (one per four-taxon set)
using the likelihood ratio test under a multinomial distribution
for the observed concordance factors.
"""
function multinom_lrt!(pval::AbstractVector{Float64}, quartet::Vector{Quartet})
    nq = length(quartet)
    for i in 1:nq
        qt = quartet[i]
        phat = qt.obsCF
        p = qt.qnet.expCF
        ngenes = qt.ngenes
        mysum = 0.0
        for j in 1:3
            if phat[j] > eps(Float64)
                mysum += phat[j]*log(phat[j]/p[j])
            end
        end
        igstat = 2 * ngenes * mysum
        pval[i] = chisqccdf(2,igstat)
    end
    return nothing
end
function multinom_lrt!(pval::AbstractVector{Float64}, obsCF, expCF::AbstractMatrix{Float64})
    for (i,o) in enumerate(obsCF) # o = [observedCF, ngenes]
        p = expCF[i,:]
        mysum = 0.0
        for j in 1:3
            if o[j] > eps(Float64)
                mysum += o[j]*log(o[j]/p[j])
            end
        end
        igstat = 2 * o[4] * mysum
        pval[i] = chisqccdf(2,igstat)
    end
    return nothing
end

