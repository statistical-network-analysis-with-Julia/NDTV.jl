using Documenter
using NDTV

DocMeta.setdocmeta!(NDTV, :DocTestSetup, :(using NDTV); recursive=true)

makedocs(
    sitename = "NDTV.jl",
    modules = [NDTV],
    authors = "Statistical Network Analysis with Julia",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://Statistical-network-analysis-with-Julia.github.io/NDTV.jl",
        edit_link = "main",
    ),
    repo = "https://github.com/Statistical-network-analysis-with-Julia/NDTV.jl/blob/{commit}{path}#{line}",
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "User Guide" => [
            "Animation Layout" => "guide/animation.md",
            "Layout Algorithms" => "guide/layout.md",
            "Export" => "guide/export.md",
        ],
        "API Reference" => [
            "Types" => "api/types.md",
            "Layout" => "api/layout.md",
            "Export" => "api/export.md",
        ],
    ],
    warnonly = [:missing_docs, :docs_block, :cross_references],
)

deploydocs(
    repo = "github.com/Statistical-network-analysis-with-Julia/NDTV.jl.git",
    devbranch = "main",
    versions = [
        "stable" => "dev",
        "dev" => "dev",
    ],
    push_preview = true,
)
