# Powerlevel10k Font Installation

For the best terminal experience with Powerlevel10k theme, you should install the **MesloLGS NF** font on your local machine.

## Why Install the Font?

The Powerlevel10k theme uses special glyphs and icons that require a compatible font. Without it, you'll see broken characters and missing icons in your terminal.

## Installation Instructions

### Automatic Installation (Recommended)

Download and install all four font files:

- [MesloLGS NF Regular.ttf](https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf)
- [MesloLGS NF Bold.ttf](https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf)
- [MesloLGS NF Italic.ttf](https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf)
- [MesloLGS NF Bold Italic.ttf](https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf)

### Platform-Specific Steps

#### Windows
1. Download the font files
2. Right-click each file and select "Install" or "Install for all users"
3. Restart VS Code

#### macOS
1. Download the font files
2. Double-click each file and click "Install Font"
3. Restart VS Code

#### Linux
1. Download the font files
2. Move them to `~/.local/share/fonts/` or `/usr/share/fonts/`
3. Run `fc-cache -f -v` to refresh font cache
4. Restart VS Code

## VS Code Configuration

The font is already configured in the devcontainer settings:
```json
"terminal.integrated.fontFamily": "MesloLGS NF"
```

If you're not using the devcontainer, add this to your VS Code settings manually.

## Reconfiguring Powerlevel10k

If you want to reconfigure the theme appearance, run:
```bash
p10k configure
```

This will start the interactive configuration wizard.

## Troubleshooting

**Q: I still see broken characters after installing the font**
- Make sure you've restarted VS Code completely
- Verify the font is installed by checking your system's font manager
- Try setting the font manually in VS Code: Settings → Terminal › Integrated: Font Family → `MesloLGS NF`

**Q: The font looks different in other terminals**
- You'll need to configure the font in each terminal application you use (terminal.app, iTerm2, Windows Terminal, etc.)

## More Information

For detailed documentation, visit the official Powerlevel10k repository:
https://github.com/romkatv/powerlevel10k
