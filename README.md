# texpress

`texpress` is a minimal LaTeX toolchain for Arch Linux and VS Code. It uses **Tectonic** (a Rust-based TeX engine that fetches packages on-demand) and standalone scripts (`latexmk`, `texcount`) to keep the installation footprint small.

---

## 📊 Footprint & Comparison

| Metric | Full TeX Live (`texlive-full`) | TeX Live Basic (`texlive-basic`) | TinyTeX | **texpress** |
| :--- | :--- | :--- | :--- | :--- |
| **Installed Disk Size** | ~4.5 GB | ~1.2 GB | ~350 MB | **~58 MB** (binary) |
| **Warm Package Cache** | Included in 4.5 GB | Excluded | Variable | **~37 MB** (on-demand) |
| **Total Disk Footprint** | **~4,500 MB** | **~1,200 MB** | **~350 MB** | **~95 MB** |
| **TeX Package Setup** | Pre-installed 4,000+ pkgs | Manual `tlmgr` | Manual `tlmgr` | **100% Automatic** |
| **Engine Language** | Legacy C (Web2C) | Legacy C (Web2C) | Legacy C (Web2C) | **Modern Rust (XeTeX)** |
| **VS Code Integration** | Manual recipe setup | Manual recipe setup | Manual recipe setup | **Automated 1-click** |

---

## 🚀 Quick Start

Run the automated installer:

```bash
git clone https://github.com/sea-deep/texpress.git
cd texpress
./setup.sh
```

### What `setup.sh` does automatically:
1. **Installs Tectonic**: Attempts pacman first, falling back to a rootless release binary in `~/.local/bin/tectonic`.
2. **Installs CTAN `latexmk` & `texcount`**: Downloads lightweight standalone scripts into `~/.local/bin/` without pulling in `texlive-binextra`.
3. **Configures `~/.latexmkrc`**: Directs `latexmk` calls to Tectonic with `--synctex` enabled.
4. **Configures VS Code**: Automatically merges `tectonic` recipes and `onSave` triggers into your VS Code `settings.json`.

> [!NOTE]
> `setup.sh` is 100% **idempotent**. You can safely run it repeatedly without breaking existing settings.

---

## 💻 VS Code & LaTeX Workshop Integration

`texpress` configures [LaTeX Workshop](https://marketplace.visualstudio.com/items?itemName=james-yu.latex-workshop) to use Tectonic out-of-the-box.

### Key VS Code Shortcuts:
- **Build Document**: `Ctrl` + `Alt` + `B`
- **View PDF in Tab**: `Ctrl` + `Alt` + `V`
- **SyncTeX (Forward Search)**: `Ctrl` + `Alt` + `J`
- **SyncTeX (Inverse Search)**: `Ctrl` + Click inside PDF tab

### Generated Settings snippet:
```json
{
  "latex-workshop.latex.recipe.default": "tectonic",
  "latex-workshop.latex.autoBuild.run": "onSave",
  "latex-workshop.view.pdf.viewer": "tab",
  "latex-workshop.latex.recipes": [{ "name": "tectonic", "tools": ["tectonic"] }],
  "latex-workshop.latex.tools": [{
    "name": "tectonic",
    "command": "tectonic",
    "args": ["-X", "compile", "%DOC_EXT%", "--keep-intermediates", "--keep-logs", "--synctex"]
  }]
}
```

---

## 📈 Benchmarks

Run the benchmark suite across sample corpora (`simple`, `math`, `multi`):

```bash
./bench/run-bench.sh
```

### Benchmark Results (Intel Core i5-8350U)

| Backend | Corpus | Phase | Compilation Time | Peak RSS Memory | PDF Output Size |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **tectonic** | `simple` | cold | 1.84s | 48 MB | 15.6 KB |
| **tectonic** | `simple` | warm | 0.28s | 36 MB | 15.6 KB |
| **tectonic** | `math` | cold | 2.12s | 52 MB | 22.5 KB |
| **tectonic** | `math` | warm | 0.34s | 41 MB | 22.5 KB |
| **tectonic** | `multi` | cold | 2.45s | 58 MB | 18.3 KB |
| **tectonic** | `multi` | warm | 0.41s | 44 MB | 18.3 KB |

*Cold builds include initial downloading and caching of necessary TeX packages.*

---

## 📦 Standalone AUR Package

`texpress` includes a standalone AUR PKGBUILD for `latexmk` located in `aur/latexmk-standalone/`. This package allows Arch users to install `latexmk` without installing `texlive-binextra` or `texlive-basic`.

### Build & Verify Locally:
```bash
cd aur/latexmk-standalone
makepkg -sf
```

### Push to AUR:
```bash
git clone ssh://aur@aur.archlinux.org/latexmk-standalone.git
cp aur/latexmk-standalone/PKGBUILD aur/latexmk-standalone/.SRCINFO latexmk-standalone/
cd latexmk-standalone
git add PKGBUILD .SRCINFO
git commit -m "feat: initial release of standalone latexmk v4.88"
git push origin master
```

---

## 📄 License

[MIT License](LICENSE)
