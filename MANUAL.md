# PKG Browser — manual

Browse fpkg files on your PC from the PS5, and install them.

## 1. Share the folder (PC, once)

Start → type `powershell` → right-click **Windows PowerShell** → **Run as administrator**:

```
.\tools\setup_windows_share.ps1 -Path <gamefolder path>
```

- Press Enter for the user name `ps5`
- Type a password, twice — it cannot be blank

Write down the address it prints, like `\\192.168.1.50\games`.

## 2. Send the payload

Send `pkg-browser.elf` to the PS5.
**PKG Browser** is then in your library, under Media.

## 3. Add your folder (once)

On the PS5: **Settings → Network → View Connection Status**, note the IP address.

From a phone or PC, open `http://YOUR-PS5-IP:9050/sources` and fill in:

| Folder | `\\192.168.1.50\games` |
|---|---|
| User name | `ps5` |
| Password | the one you set |

Press **Add source**.

## 4. Install

Open **PKG Browser** → search if you need to → **Install**.
