"""
    network_expectedCF(net::HybridNetwork; showprogressbar=true,
            inheritancecorrelation=0)

Calculate the quartet concordance factors (qCF) expected from the multispecies
coalescent along network `net`. Output: `(q,t)` where `t` is a list of taxa,
and `q` is a list of 4-taxon set objects of type `PhyloNetworks.QuartetT{datatype}`.
In each element of `q`, `taxonnumber` gives the indices in `taxa`
of the 4 taxa of interest; and `data` contains the 3 concordance factors, for the
3 unrooted topologies in the following order:
`t1,t2|t3,t4`, `t1,t3|t2,t4` and `t1,t4|t2,t3`.
This output is similar to that of `PhyloNetworks.countquartetsintrees` when
1 individual = 1 taxon, with 4-taxon sets listed in the same order
(same output `t`, then same order of 4-taxon sets in `q`).

Assumption: the network should have **edge lengths in coalescent units**.

By default, lineages at a hybrid node come from a parent (chosen according
to inheritance probabilities γ) *independently* across lineages.
With option `inheritancecorrelation > 0`, lineages have positive dependence,
e.g. to model locus-specific inheritance probabilities, randomly drawn from a
Beta distribution with mean γ across all loci. If `inheritancecorrelation` is
set to 1, then all lineages at a given locus inherit from the same
(randomly sampled) parent. More generally, the lineages' parents
are distributed according to a Dirichlet process with base distribution determined
by the γ values, and with concentration parameter α = (1-r)/r, that is, r = 1/(1+α),
where `r` is the input inheritance correlation.

# examples
```jldoctest
julia> using PhyloNetworks, QuartetNetworkGoodnessFit

julia> # network with 3_2 cycles, causing some anomalous quartets
       net = readTopology("(D:1,((C:1,#H25:0):0.1,((((B1:10,B2:1):1.5,#H1:0):10.8,((A1:1,A2:1):0.001)#H1:0::0.5):0.5)#H25:0::0.501):1);");

julia> # using PhyloPlots; plot(net, showedgelength=true);

julia> q,t = network_expectedCF(net); # anomalous: A1, A2, {B1 or B2}, {C or D}
Calculation quartet CFs for 15 quartets...
0+---------------+100%
  ***************

julia> show(q[1].taxonnumber)
[1, 2, 3, 4]
julia> show(q[1].data)
[0.8885456713760765, 0.05572716431196175, 0.05572716431196175]

julia> for qi in q
         println(join(t[qi.taxonnumber],",") * ": " * string(round.(qi.data, sigdigits=3)))
       end
A1,A2,B1,B2: [0.889, 0.0557, 0.0557]
A1,A2,B1,C: [0.168, 0.416, 0.416]
A1,A2,B2,C: [0.168, 0.416, 0.416]
A1,B1,B2,C: [0.0372, 0.0372, 0.926]
A2,B1,B2,C: [0.0372, 0.0372, 0.926]
A1,A2,B1,D: [0.168, 0.416, 0.416]
A1,A2,B2,D: [0.168, 0.416, 0.416]
A1,B1,B2,D: [0.0372, 0.0372, 0.926]
A2,B1,B2,D: [0.0372, 0.0372, 0.926]
A1,A2,C,D: [0.69, 0.155, 0.155]
A1,B1,C,D: [0.793, 0.103, 0.103]
A2,B1,C,D: [0.793, 0.103, 0.103]
A1,B2,C,D: [0.793, 0.103, 0.103]
A2,B2,C,D: [0.793, 0.103, 0.103]
B1,B2,C,D: [1.0, 9.42e-7, 9.42e-7]

```
"""
function network_expectedCF(net::HybridNetwork; showprogressbar=true,
            inheritancecorrelation=0)
    net.node[net.root].leaf && error("The root can't be a leaf.")
    PN.check_nonmissing_nonnegative_edgelengths(net,
        "Edge lengths are needed in coalescent units to calcualte expected CFs.")
    all(e.gamma >= 0.0 for e in net.edge) || error("some γ's are missing for hybrid edges: can't calculate expected CFs.")
    inheritancecorrelation >= 0 || error("the inheritance correlation should be non-negative")
    inheritancecorrelation <= 1 || error("the inheritance correlation should be <= 1")
    taxa = sort!(tipLabels(net))
    taxonnumber = Dict(taxa[i] => i for i in eachindex(taxa))
    ntax = length(taxa)
    nCk = PN.nchoose1234(ntax) # matrix to rank 4-taxon sets
    qtype = MVector{3,Float64} # 3 floats: CF12_34, CF13_24, CF14_23; initialized at 0.0
    numq = nCk[ntax+1,4]
    quartet = Vector{PN.QuartetT{qtype}}(undef, numq)
    ts = [1,2,3,4]
    for qi in 1:numq
        quartet[qi] = PN.QuartetT(qi, SVector{4}(ts), MVector(0.,0.,0.))
        # next: find the 4-taxon set with the next rank,
        #       faster than using the direct mapping function
        ind = findfirst(x -> x>1, diff(ts))
        if ind === nothing ind = 4; end
        ts[ind] += 1
        for j in 1:(ind-1)
            ts[j] = j
        end
    end
    if showprogressbar
        nstars = (numq < 50 ? numq : 50)
        nquarnets_perstar = (numq/nstars)
        println("Calculation quartet CFs for $numq quartets...")
        print("0+" * "-"^nstars * "+100%\n  ")
        stars = 0
        nextstar = Integer(ceil(nquarnets_perstar))
    end
    for qi in 1:numq
        network_expectedCF!(quartet[qi], net, taxa, taxonnumber, inheritancecorrelation)
        if showprogressbar && qi >= nextstar
            print("*")
            stars += 1
            nextstar = Integer(ceil((stars+1) * nquarnets_perstar))
        end
    end
    showprogressbar && print("\n")
    return quartet, taxa
end

"""
    network_expectedCF!(quartet::QuartetT, net::HybridNetwork, taxa, taxonnumber,
            inheritancecorrelation)

Update `quartet.data` to contain the quartet concordance factors expected from
the multispecies coalescent along network `net` for the 4-taxon set `taxa[quartet.taxonnumber]`.
`taxa` should contain the tip labels in `net`. `quartet.taxonnumber` gives the
indices in `taxa` of the 4 taxa of interest. `taxonnumber` should be a dictionary
mapping taxon labels in to their indices in `taxa`, for easier lookup.

`net` is not modified.

For `inheritancecorrelation` see [`network_expectedCF`](@ref).
Its value should be between 0 and 1 (not checked by this internal function).
"""
function network_expectedCF!(quartet::PN.QuartetT{MVector{3,Float64}},
                             net::HybridNetwork, taxa, taxonnumber,
                             inheritancecorrelation)
    net = deepcopy(net)
    PN.removedegree2nodes!(net)
    # delete all taxa except for the 4 in the quartet
    for taxon in taxa
        taxonnumber[taxon] in quartet.taxonnumber && continue
        deleteleaf!(net, taxon, simplify=false, unroot=false)
        # would like unroot=true but deleteleaf! throws an error when the root is connected to 2 outgoing hybrid edges
    end
    quartet.data .= network_expectedCF_4taxa!(net, taxa[quartet.taxonnumber], inheritancecorrelation)
    # for i in 1:3 quartet.data[i] = qCF[i]; end
    return quartet
end

"""
    network_expectedCF_4taxa!(net::HybridNetwork, fourtaxa, inheritancecorrelation)

Return the quartet concordance factors expected from the multispecies coalescent
along network `net`, where the 3 quartet topologies are ordered following the
ordering of taxon names in `fourtaxa`, that is: if `fourtaxa` is a,b,c,d,
then the concordance factors are listed in this order:

    (qCF(ab|cd), qCF(ac|bd), qCF(ad,bc))

Assumptions about `net`:
- has 4 taxa, and those are the same as `fourtaxa`
- no degree-2 nodes, except perhaps for the root
- edge lengths are non-missing
- hybrid edge γ's are non-missing

The network is modified as follows: what's above the LSA is removed,
the 2 edges incident to the root are fused (if the root is of degree 2),
and external degree-2 blobs are removed. `net` is then simplified recursively
by removing hybrid edges for the recursive calculation of qCFs.

For `inheritancecorrelation` see [`network_expectedCF`](@ref).
Its value should be between 0 and 1 (not checked by this internal function).
"""
function network_expectedCF_4taxa!(net::HybridNetwork, fourtaxa, inheritancecorrelation)
    deleteaboveLSA!(net)
    # make sure the root is of degree 3+
    if length(net.node[net.root].edge) <= 2
        PN.fuseedgesat!(net.root, net)
    end
    # find and delete degree-2 blobs along external edges
    bcc = biconnectedComponents(net, true) # true: ignore trivial blobs
    entry = PN.biconnectedcomponent_entrynodes(net, bcc)
    entryindex = indexin(entry, net.nodes_changed)
    exitnodes = PN.biconnectedcomponent_exitnodes(net, bcc, false) # don't redo the preordering
    bloborder = sortperm(entryindex) # pre-ordering for blobs in their own blob tree
    function isexternal(ib) # is bcc[ib] of degree 2 and adjacent to an external edge?
        # yes if: 1 single exit adjacent to a leaf
        length(exitnodes[ib]) != 1 && return false
        ch = getchildren(exitnodes[ib][1])
        return length(ch) == 1 && ch[1].leaf
    end
    for ib in reverse(bloborder)
        isexternal(ib) || continue # keep bcc[ib] if not external of degree 2
        for he in bcc[ib]
            he.isMajor && continue
            # deletion of a hybrid can hide the deletion of another: check that he is still in net
            any(e -> e===he, net.edge) || continue
            # delete minor hybrid edge with options unroot=true: to make sure the
            # root remains of degree 3+, in case a degree-2 blob starts at the root
            # simplify=true: bc external blob
            PN.deletehybridedge!(net,he, false,true,false,true,false)
        end
    end
    ndes = 4 # number of taxa descendant from lowest hybrid node
    if net.numHybrids > 0
        preorder!(net)
        # find a lowest hybrid node and # of taxa below it
        hyb = net.nodes_changed[findlast(n -> n.hybrid, net.nodes_changed)]
        funneledge = [e for e in hyb.edge if getparent(e) === hyb]
        ispolytomy = length(funneledge) > 1
        funneldescendants = union([PN.descendants(e) for e in funneledge]...)
        ndes = length(funneldescendants)
        n2 = (ispolytomy ? hyb : getchild(funneledge[1]))
        ndes > 2 && n2.leaf && error("2+ descendants below the lowest hybrid, yet n2 is a leaf. taxa: $(fourtaxa)")
    end
    if ndes > 2 # simple formula for qCF: find cut edge and its length
        # inheritance correlation has no impact
        # pool of cut edges below. contains NO external edge, bc n2 not leaf (if reticulation), nice tree ow
        cutpool = (net.numHybrids == 0 ? net.edge :
                    [e for e in n2.edge if getparent(e) === n2])
        filter!(e -> !getchild(e).leaf, cutpool)
        net.numHybrids > 0 || length(cutpool) <= 1 ||
            error("2+ cut edges, yet 4-taxon tree, degree-3 root and no degree-2 nodes. taxa: $(fourtaxa)")
        sistertofirst = 2    # arbitrarily correct if 3-way polytomy (no cut edge)
        internallength = 0.0 # correct if polytomy
        for e in cutpool
            internallength += e.length
            hwc = hardwiredCluster(e, fourtaxa)
            sistertofirst = findnext(x -> x == hwc[1], hwc, 2)
        end
        minorcf = exp(-internallength)/3
        majorcf = 1.0 - 2 * minorcf
        qCF = (sistertofirst == 2 ? MVector{3,Float64}(majorcf,minorcf,minorcf) :
              (sistertofirst == 3 ? MVector{3,Float64}(minorcf,majorcf,minorcf) :
                                    MVector{3,Float64}(minorcf,minorcf,majorcf) ))
        return qCF
    end
    ndes > 0 || error("weird: hybrid node has no descendant taxa")
    # by now, there are 1 or 2 taxa below the lowest hybrid
    qCF = MVector{3,Float64}(0.0,0.0,0.0) # mutated later
    parenthedge = [e for e in hyb.edge if getchild(e) === hyb]
    all(h.hybrid for h in parenthedge) || error("hybrid $(hyb.number) has a parent edge that's a tree edge")
    parenthnumber = [p.number for p in parenthedge]
    nhe = length(parenthedge)
    if ndes == 1 # weighted qCFs average of the nhe (often = 2) displayed networks
        # inheritance correlation has no impact
        for i in 1:nhe # keep parenthedge[i], remove all others
            gamma = parenthedge[i].gamma
            simplernet = ( i < nhe ? deepcopy(net) : net ) # last case: to save memory allocation
            for j in 1:nhe
                j == i && continue # don't delete hybrid edge i!
                pe_index = findfirst(e -> e.number == parenthnumber[j], simplernet.edge)
                PN.deletehybridedge!(simplernet, simplernet.edge[pe_index],
                    false,true,false,false,false) # ., unroot=true, ., simplify=false,.
            end
            qCF .+= gamma .* network_expectedCF_4taxa!(simplernet, fourtaxa, inheritancecorrelation)
        end
        return qCF
    end
    # by now: 2 descendant below the lowest hybrid node: hardest case
    # weighted qCFs average of 3 networks: 2 displayed, 1 "parental" (unless same parents)
    sameparents = (inheritancecorrelation == 1)
    oneminusrho = 1 - inheritancecorrelation
    hwc = hardwiredCluster(parenthedge[1], fourtaxa)
    sistertofirst = findnext(x -> x == hwc[1], hwc, 2)
    internallength = ( ispolytomy ? 0.0 : funneledge[1].length)
    deepcoalprob = exp(-internallength)
    # initialize qCF: when the 2 descendants coalesce before reaching the hybrid node
    qCF = (sistertofirst == 2 ? MVector{3,Float64}(1.0-deepcoalprob,0.0,0.0) :
          (sistertofirst == 3 ? MVector{3,Float64}(0.0,1.0-deepcoalprob,0.0) :
                                MVector{3,Float64}(0.0,0.0,1.0-deepcoalprob) ))
    # no coalescence on cut-edge: delete it and extract parental networks
    ispolytomy || PN.shrinkedge!(net, funneledge[1])
    # shrinkedge! requires PhyloNetworks v0.15.2
    childedge = [e for e in hyb.edge if getparent(e) === hyb]
    length(childedge) == 2 ||
      error("2-taxon subtree, but not 2 child edges after shrinking the cut edge.")
    all(getchild(e).leaf for e in childedge) ||
      error("2-taxon subtree, cut-edge shrunk, but the 2 edges aren't both external")
    childnumber = [e.number for e in childedge]
    for i in 1:nhe
      weighti = deepcoalprob * parenthedge[i].gamma
      for j in (sameparents ? i : 1):i # if inheritancecorrelation=1 then i!=j has probability 0
        gammaj = parenthedge[j].gamma
        simplernet = ( i < nhe || j < nhe ? deepcopy(net) : net )
        # delete all hybedges other than i & j
        for k in 1:nhe
            (k == i || k ==j) && continue # don't delete hybrid edges i or j
            pe_index = findfirst(e -> e.number == parenthnumber[k], simplernet.edge)
            PN.deletehybridedge!(simplernet, simplernet.edge[pe_index],
                false,true,false,false,false) # ., unroot=true,., simplify=false,.
        end
        if i != j
            # detach childedge[2] from hyb and attach it to hyb's parent j
            pej_index = findfirst(e -> e.number == parenthnumber[j], simplernet.edge)
            pej = simplernet.edge[pej_index]
            pn = getparent(pej)
            hn = getchild(pej) # hyb node, but in simplernet
            ce2_index = findfirst(e -> e.number == childnumber[2], simplernet.edge)
            ce2 = simplernet.edge[ce2_index]
            PN.removeEdge!(hn,ce2)
            hn_index = findfirst(x -> x === hn, ce2.node)
            ce2.node[hn_index] = pn # ce2.isChild1 remains synchronized
            push!(pn.edge, ce2)
            # then delete hybedge j
            PN.deletehybridedge!(simplernet, pej,
                false,true,false,false,false) # ., unroot=true,., simplify=false,.)
        end
        qCF_subnet = network_expectedCF_4taxa!(simplernet, fourtaxa, inheritancecorrelation)
        if i == j
            prob = weighti * (gammaj * oneminusrho + inheritancecorrelation)
            qCF .+= prob .* qCF_subnet
        else # add subnetwork with flipped assignment of the 2 taxa to parents i & j
            flipped_ij = (sistertofirst == 2 ? [1,3,2] :
                         (sistertofirst == 3 ? [3,2,1] : [2,1,3] ))
            prob = weighti * gammaj * oneminusrho
            qCF .+= prob .* (qCF_subnet .+ qCF_subnet[flipped_ij])
        end
      end
    end
    return qCF
end
