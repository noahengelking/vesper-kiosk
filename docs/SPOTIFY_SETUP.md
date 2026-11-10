# Spotify setup

Vesper uses Spotify's Web API with the OAuth 2.0 Authorization Code flow with
PKCE. You need your own Spotify developer application. You do **not** need a
Spotify client secret, and you should never put a client secret in this
project.

## 1. Requirements

- A Spotify account.
- Spotify Premium is required for playback control through the Web API
  (play, pause, skip, seek, volume, shuffle, repeat, transfer playback).
- A browser for the one-time OAuth authorization.

## 2. Create a Spotify developer account and app

1. Sign in at <https://developer.spotify.com/dashboard>.
2. Accept the Spotify Developer Terms if prompted.
3. Click **Create app**.
4. Fill in:
   - **App name**: e.g. `Vesper Kiosk`
   - **App description**: e.g. `Local touch kiosk dashboard`
   - **Redirect URI**: exactly `http://127.0.0.1:8888/callback`
   - **Which API/SDKs are you planning to use?** select **Web API**
5. Save the app.
6. Open the app settings and copy the **Client ID**.
   Do not copy or use the client secret.

The redirect URI must match exactly. If it differs, Spotify will reject the
login with a redirect-URI error.

## 3. Put the Client ID in the local config

From the repository root:

```bash
cp dashboard/config.example.json dashboard/config.json
```

Edit `dashboard/config.json`:

```json
{
  "client_id": "paste-your-spotify-client-id-here"
}
```

This file is ignored by Git. Never commit it and never add the client secret.

## 4. Authorize Vesper

Run the login helper:

```bash
python3 dashboard/spotify_login.py
```

It will print an authorization URL. Open that URL in a browser and approve the
requested scopes.

If you are installing on a headless kiosk over SSH, first forward the callback
port from your Mac:

```bash
ssh -L 8888:127.0.0.1:8888 <kiosk-user>@<kiosk-ip>
```

Then run `spotify_login.py` on the kiosk and open the printed URL in your Mac
browser.

The helper requests these scopes:

- `user-read-playback-state`
- `user-modify-playback-state`
- `user-read-currently-playing`
- `playlist-read-private`
- `playlist-read-collaborative`
- `user-read-recently-played`
- `user-library-read`

On success, tokens are stored at:

```text
~/.config/desk-dashboard/spotify.json
```

The dashboard server refreshes the access token automatically. Keep
`spotify.json` private. Do not commit it.

## 5. Optional: Spotify Connect device through Soloist

Vesper can control an existing Spotify Connect device without Soloist. If you
want the kiosk itself to appear as a Spotify Connect device named `Vesper`, you
need to install and configure Soloist separately.

If you use Soloist, put its API key in:

```text
~/.config/desk-dashboard/soloist.env
```

Example:

```bash
SOLOIST_API_KEY=your-soloist-api-key
chmod 600 ~/.config/desk-dashboard/soloist.env
```

This key is separate from the Spotify developer Client ID. It is also ignored
by Git.

## 6. Where all private data belongs

| Data | Location | Committed? |
| --- | --- | --- |
| Spotify Client ID | `dashboard/config.json` | No |
| Spotify OAuth access/refresh tokens | `~/.config/desk-dashboard/spotify.json` | No |
| Calendar ICS URLs | `~/.config/desk-dashboard/calendar.urls` | No |
| Soloist API key | `~/.config/desk-dashboard/soloist.env` | No |
| Wi-Fi credentials | `/etc/wpa_supplicant/*.conf` | No |
| Kiosk username/home path | systemd unit files on your machine | Not generic examples |

If Spotify login says your app is in development mode, only accounts added
under the app's **User Management** settings can use it. Add your own Spotify
account there while developing.
