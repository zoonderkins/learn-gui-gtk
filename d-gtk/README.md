# D macOS Calculator + Live FX (no API key)

- GUI: D + GtkD (GTK3)
- Live rates: https://api.exchangerate.host (no API key)
- Target: macOS Intel x64 (works on Apple Silicon via Rosetta if GTK installed)

## Install prerequisites (macOS)
```bash
# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# GTK 3 and D toolchain
brew install gtk+3 adwaita-icon-theme ldc dub
# (optional)
brew install pango cairo gdk-pixbuf
```

## Run
```bash
dub run
```

## Build release
```bash
dub build -b release
```

## Zip the build (example)
```bash
# After build, the binary is in ./d-mac-calc-fx
zip -r d-mac-calc-fx-macos.zip d-mac-calc-fx
```

> Note: First launch may warn about theme/icons. Install `adwaita-icon-theme` then re-run.

## Currencies
USD, EUR, JPY, CNY, MYR, TWD, SGD, GBP. Base is USD.
If online fetch fails, the app falls back to offline defaults.

License: MIT