# handbrake-episode-ripper

Headless PowerShell workflow for ripping DVD TV episodes with `HandBrakeCLI` on Windows.

## Requirements

- Windows PowerShell
- `HandBrakeCLI`
- `libdvdcss-2.dll` available to HandBrakeCLI
- A loaded DVD drive

## Usage

Run the script and follow the prompts for:

- season directory
- season number, if it cannot be inferred from the folder name
- title selection, only if the disc scan is ambiguous

If you enter a directory like `Season 02`, the script creates it under `output/` if it does not already exist.

Override the default series name with the `-SeriesName` parameter if needed.
Example: `-SeriesName "My Show"`

## Output

Ripped episodes are saved as `.mp4` files using season-aware names like:

- `Everybody Loves Raymond - s02e01.mp4`
- `Everybody Loves Raymond - s02e02.mp4`

Run logs are written to `logs/`.
Season output directories are written under `output/`.

## Naming

- If the season directory already contains `.mp4` files, the script continues that naming pattern.
- If the directory is empty, the script uses the folder name and default series name to build filenames.
- If needed, the default series name can be overridden with the `-SeriesName` parameter.

## Troubleshooting

- If scan fails with encryption errors, make sure `libdvdcss-2.dll` is available to HandBrakeCLI.
- If title selection is ambiguous, the script allows manual title entry.
- If HandBrake only sees one title, check the scan output and disc handling.

## Authors
- Jason Figueroa and [SafeCode-Box 🛡️](https://github.com/jasonfigueroa/SafeCode-Box)

## License

[MIT](LICENSE)
