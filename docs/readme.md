# notes to maintain documentation

- built with [Documenter](https://juliadocs.github.io/Documenter.jl)
- deployed [here](https://JuliaPhylo.github.io/QuartetNetworkGoodnessFit.jl/dev/)
  (go to `dev/` or `stable/`)
  using github and files committed to the `gh-pages` branch.

## how it works: overview

- `.travis.yml` asks to run `docs/make.jl` after a successful test & build.
- the julia script `docs/make.jl` has these steps:
  1. run `makedocs()` from `Documenter`: make the documentation;
     runs all `jldoctest` blocks in the source files,
     to check that the output in the blocks matches the actual output;
     translate the "Documenter md" documentation files into html files.
  2. run `deploydocs(...)` from Documenter: push files on `gh-pages` branch.

## what to update

- check Julia version in `.github/workflows/documentation.yml`
- update Documenter version in `docs/Project.toml`, and fix
  anything that the update might have broken.

## to make a local version of the website

```shell
julia --project=docs/ -e 'using Pkg; Pkg.instantiate(); Pkg.develop(PackageSpec(path=pwd()))'
julia --project=docs/ --color=yes docs/make.jl
```

or interactively in `docs/`:
```shell
pkg> activate .
pkg> instantiate
pkg> dev ~/.julia/dev/QuartetNetworkGoodnessFit
julia> include("make.jl")
```

it will:
- test the `jldoctest` blocks of examples in the docstrings
- create or updates a `build/` directory with html files
