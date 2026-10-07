# Steam Family Search

Adds a **FAMILY** badge to games in the Steam app's store search when you can already play them through your Steam Family.

Steam only tells you this on a game's own page. This shows it right in the search list, so you don't buy something your family already owns.

![Search results with FAMILY badges](https://github.com/user-attachments/assets/6cdf3737-4ef8-4bff-951f-5fac467a0756)

## How to run

1. Download this repo (**Code → Download ZIP**) and unzip it.
2. Double-click `Steam Family.bat`.
3. Open **Store → Search** in Steam.

That's it. Nothing to install, and no window stays open. If Steam is already open, it restarts once (but never while you're in a game).

Run it each time you start Steam. It stops by itself when you close Steam. Tip: put a shortcut to `Steam Family.bat` on your desktop and use it to open Steam.

## How it works

1. Steam's store is a web page shown by a browser built into Steam.
2. The `.bat` starts Steam with that browser's developer mode on. This is a standard Steam option.
3. A small PowerShell script (`steam-family.ps1`) waits in the background. Whenever you open the store, it adds the badge script (`steam-family-search.user.js`) to the page.
4. The badge script asks Steam which games your family shares with you. Steam uses the same list for the "In Family Library" message on game pages. The script then puts badges on those games.

## Is it safe?

- It only talks to Steam. No other servers.
- No passwords or logins needed.
- It only adds badges. It never buys anything or changes your account.
- No Steam files are changed, and nothing runs when Windows starts.
- Developer mode only works from your own PC and turns off when Steam closes.

## How to remove

Close Steam and delete this folder.

---

Not affiliated with or endorsed by Valve. Steam is a trademark of Valve Corporation. Game images in the screenshot belong to their publishers.
