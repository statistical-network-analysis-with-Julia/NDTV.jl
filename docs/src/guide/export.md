# Export

This guide covers how to export dynamic network animations from NDTV.jl to various formats including HTML, video, and GIF.

## Overview

After computing a layout with [`render_animation`](@ref) or [`layout_sequence`](@ref), you can export the result in several formats:

| Format | Function | Requirements | Interactive? |
|--------|----------|-------------|--------------|
| HTML | [`export_html`](@ref) | None | Yes |
| Video (MP4) | [`export_movie`](@ref) | FFmpeg | No |
| GIF | [`export_gif`](@ref) | ImageMagick | No |

## Export Workflow

The typical export workflow is:

```julia
using NetworkDynamic
using NDTV

# 1. Create and populate your dynamic network
dnet = DynamicNetwork(10; observation_start=0.0, observation_end=100.0)
for i in 1:10
    activate!(dnet, 0.0, 100.0; vertex=i)
end
activate!(dnet, 0.0, 50.0; edge=(1, 2))
activate!(dnet, 25.0, 75.0; edge=(2, 3))
activate!(dnet, 50.0, 100.0; edge=(3, 4))

# 2. Compute the animation layout
layout = render_animation(dnet;
    algorithm=FRLayout(),
    n_frames=100
)

# 3. Export to your desired format
export_html(layout, "animation.html")
```

## HTML Export

HTML export creates a self-contained HTML file with an embedded animation viewer. This is the recommended format for sharing and presentation because it requires no external software.

### Basic Usage

```julia
export_html(layout, "my_animation.html")
```

### Configuration

Use [`HTMLConfig`](@ref) to customize the output:

```julia
config = HTMLConfig(
    width=800,       # Canvas width in pixels
    height=600,      # Canvas height in pixels
    controls=true    # Show playback controls
)

export_html(layout, "my_animation.html"; config=config)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `width` | `Int` | `800` | Canvas width in pixels |
| `height` | `Int` | `600` | Canvas height in pixels |
| `controls` | `Bool` | `true` | Show play/pause/scrub controls |

### Output Details

The generated HTML file contains:
- A `<canvas>` element for rendering the network
- Frame data embedded as JSON
- JavaScript for animation playback
- Time range information (start to end)

```julia
result = export_html(layout, "output.html")
println(result.filepath)    # "output.html"
println(result.n_frames)    # Number of frames in the animation
```

### When to Use HTML

- **Presentations**: Interactive playback in any web browser
- **Sharing**: Single file, no dependencies required to view
- **Exploration**: Scrub through time points interactively
- **Web integration**: Embed in websites or Jupyter notebooks

## Video Export

Video export creates an MP4 (or other codec) video file using FFmpeg. This produces a fixed-framerate video suitable for embedding in presentations or publications.

### Requirements

Video export requires [FFmpeg](https://ffmpeg.org/) to be installed and available on your system PATH:

```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# macOS with Homebrew
brew install ffmpeg

# Verify installation
ffmpeg -version
```

### Basic Usage

```julia
export_movie(layout, "my_animation.mp4")
```

### Configuration

Use [`VideoConfig`](@ref) to customize the output:

```julia
config = VideoConfig(
    fps=30,           # Frames per second
    width=800,        # Video width in pixels
    height=600,       # Video height in pixels
    codec="h264"      # Video codec
)

export_movie(layout, "my_animation.mp4"; config=config)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fps` | `Int` | `30` | Frames per second |
| `width` | `Int` | `800` | Video width in pixels |
| `height` | `Int` | `600` | Video height in pixels |
| `codec` | `String` | `"h264"` | Video codec (h264, h265, vp9) |

### Choosing FPS and Frame Count

The total animation duration depends on both the number of frames and the FPS:

```text
duration = n_frames / fps
```

| n_frames | FPS | Duration |
|----------|-----|----------|
| 100 | 30 | 3.3 seconds |
| 100 | 10 | 10 seconds |
| 300 | 30 | 10 seconds |
| 600 | 30 | 20 seconds |

```julia
# 10-second animation at 30 fps
layout = render_animation(dnet; n_frames=300)
export_movie(layout, "animation.mp4";
    config=VideoConfig(fps=30)
)
```

### When to Use Video

- **Publications**: Embed in supplementary materials
- **Presentations**: Fixed playback, no interaction needed
- **Social media**: Widely supported format
- **Large audiences**: Guaranteed playback without browser requirements

## GIF Export

GIF export creates an animated GIF using ImageMagick. GIFs are widely supported but have lower quality than video and larger file sizes.

### Requirements

GIF export requires [ImageMagick](https://imagemagick.org/) to be installed:

```bash
# Ubuntu/Debian
sudo apt install imagemagick

# macOS with Homebrew
brew install imagemagick

# Verify installation
convert --version
```

### Basic Usage

```julia
export_gif(layout, "my_animation.gif")
```

### Configuration

Use [`GIFConfig`](@ref) to customize the output:

```julia
config = GIFConfig(
    fps=10,           # Frames per second (lower for smaller files)
    width=400,        # GIF width in pixels
    height=400,       # GIF height in pixels
    loop=0            # Loop count (0 = infinite)
)

export_gif(layout, "my_animation.gif"; config=config)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fps` | `Int` | `10` | Frames per second |
| `width` | `Int` | `400` | GIF width in pixels |
| `height` | `Int` | `400` | GIF height in pixels |
| `loop` | `Int` | `0` | Loop count (0 = infinite loop) |

### GIF Size Optimization

GIFs can become very large. To keep file sizes manageable:

```julia
# Reduce resolution
config = GIFConfig(width=200, height=200, fps=5)

# Use fewer frames
layout = render_animation(dnet; n_frames=30)
export_gif(layout, "small.gif"; config=config)
```

### When to Use GIF

- **Documentation**: Inline animations in README files
- **Messaging**: GIFs are supported in most chat platforms
- **Simple animations**: Short sequences with few frames
- **Previews**: Quick visual summaries of network dynamics

## Export Configuration Types

All export configurations subtype [`ExportConfig`](@ref):

```julia
abstract type ExportConfig end

struct VideoConfig <: ExportConfig ... end
struct GIFConfig <: ExportConfig ... end
struct HTMLConfig <: ExportConfig ... end
```

### Default Configurations

Each config type has sensible defaults:

```julia
# All defaults
VideoConfig()   # fps=30, 800x600, h264
GIFConfig()     # fps=10, 400x400, loop=0
HTMLConfig()    # 800x600, controls=true
```

## Format Comparison

| Feature | HTML | Video | GIF |
|---------|------|-------|-----|
| File size | Small | Medium | Large |
| Quality | High | High | Limited (256 colors) |
| Interactive | Yes | No | No |
| Dependencies | None (to view) | FFmpeg (to create) | ImageMagick (to create) |
| Browser support | Universal | Requires player | Universal |
| Best resolution | Any | Up to 4K | Under 600px |

## Complete Export Example

```julia
using NetworkDynamic
using NDTV

# Create a dynamic network
dnet = DynamicNetwork(15; observation_start=0.0, observation_end=100.0)

for i in 1:15
    activate!(dnet, 0.0, 100.0; vertex=i)
end

# Community 1 edges
for (i, j, t1, t2) in [(1,2,0,80), (1,3,0,80), (2,3,10,70)]
    activate!(dnet, Float64(t1), Float64(t2); edge=(i, j))
end

# Community 2 edges
for (i, j, t1, t2) in [(4,5,20,100), (4,6,20,100), (5,6,30,90)]
    activate!(dnet, Float64(t1), Float64(t2); edge=(i, j))
end

# Bridge edge connecting communities
activate!(dnet, 40.0, 60.0; edge=(3, 4))

# Compute animation
layout = render_animation(dnet;
    algorithm=FRLayout(iterations=150),
    n_frames=150
)

# Export in all three formats
export_html(layout, "communities.html";
    config=HTMLConfig(width=1024, height=768))

export_movie(layout, "communities.mp4";
    config=VideoConfig(fps=30, width=1920, height=1080))

export_gif(layout, "communities.gif";
    config=GIFConfig(fps=10, width=400, height=400))
```

## Return Values

All export functions return a named tuple with metadata:

```julia
# HTML export
result = export_html(layout, "out.html")
result.filepath    # "out.html"
result.n_frames    # Number of frames

# Video export
result = export_movie(layout, "out.mp4")
result.filepath    # "out.mp4"
result.n_frames    # Number of frames
result.fps         # Frames per second

# GIF export
result = export_gif(layout, "out.gif")
result.filepath    # "out.gif"
result.n_frames    # Number of frames
result.fps         # Frames per second
```

## Troubleshooting

### FFmpeg Not Found

If `export_movie` warns about FFmpeg:

```julia
# Check if FFmpeg is available
run(`ffmpeg -version`)
```

Install FFmpeg from [ffmpeg.org](https://ffmpeg.org/) or your system package manager.

### ImageMagick Not Found

If `export_gif` warns about ImageMagick:

```julia
# Check if ImageMagick is available
run(`convert --version`)
```

Install ImageMagick from [imagemagick.org](https://imagemagick.org/) or your system package manager.

### Large File Sizes

If exported files are too large:

1. Reduce `n_frames` in `render_animation`
2. Lower resolution in the config (`width`, `height`)
3. For GIF: reduce `fps` and dimensions
4. For video: use a more efficient codec (`"h265"`)

### Animation Too Fast or Slow

Adjust the relationship between `n_frames` and `fps`:

```julia
# Slow animation: many frames, low fps
layout = render_animation(dnet; n_frames=300)
export_movie(layout, "slow.mp4"; config=VideoConfig(fps=10))  # 30 seconds

# Fast animation: fewer frames, high fps
layout = render_animation(dnet; n_frames=60)
export_movie(layout, "fast.mp4"; config=VideoConfig(fps=30))  # 2 seconds
```
