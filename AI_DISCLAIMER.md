# AI Assistance Disclaimer

Vesper Kiosk was developed with substantial assistance from generative AI
tools.

AI-assisted code can be useful, but it can also contain mistakes, incomplete
assumptions, security issues or integrations that only make sense for one
particular device. Before relying on this project:

- Review every service unit and shell command before running it.
- Keep the dashboard, gesture and audio servers bound to localhost.
- Never expose the kiosk control APIs directly to the public internet.
- Audit the Spotify, Soloist, calendar and Wi-Fi credential handling.
- Test hardware-specific pieces such as `trackpad.py`, brightness control,
  touchpad detection and Sway keybindings on your own machine.
- Keep private configuration out of Git and out of backups that may be shared.

The project is provided under the MIT License and without warranty.
