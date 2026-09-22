# PKG Browser

A PS5 payload that puts a tile on the home screen. Opening it lists the packages sitting on
your PC and installs the one you pick, chosen **on the console** with the controller.

It is the mirror image of pushing packages from a PC: nothing sends anything. You point the
console at a folder once, and from then on the console browses and installs by itself.

New to this? [MANUAL.md](MANUAL.md) is the same thing in four steps, without the jargon.

## The flow

1. **Send `pkg-browser.elf`** to the ELF loader. It publishes a **PKG Browser** tile in the
   Media area and starts a web server on port **9050**. Nothing else happens — no browser
   opens, no app launches.
2. **Open `http://<console-ip>:9050/sources`** from a PC or phone and add the folder your
   packages are in — type an address, or use **Browse** to walk the console's own
   filesystem and pick a folder by looking at it.
3. **Open the tile** on the console. The deeplink hands `http://127.0.0.1:9050/` to the
   console browser and the packages appear as cards.
4. **Choose one.** It is handed to the console's installer and proceeds from there.

Packages are listed by their real title, read from the `param.json` inside each one, with
the file name beneath. Nothing is downloaded to find it: a PS5 debug package keeps
`param.json` in the clear near the *end* of the file, so it is located with ranged reads
working backwards from the end. Titles are remembered, so a list is only slow the first
time. A retail package is encrypted and stays listed by file name.

Step 2 is once per source. After that the console is self-sufficient.

## Sources

A source is one of:

| kind | example | notes |
|---|---|---|
| Windows share | `\\192.168.1.10\Users\you\games` | read over SMB, no PC-side app |
| network folder | `http://192.168.1.10:8000/pkgs/` | anything serving a directory index |
| console folder | `/data/pkgs`, a mounted USB stick | scanned directly |

For the network kind, the simplest route is [PKG Share](../ps5-pkg-share), a small Windows
app that serves a folder — local or a `\\host\share` path — and copies the address to paste
in here. `python -m http.server 8000` inside your packages folder does the same job.
nginx `autoindex` and Apache listings work too — the index is read for any `href` ending in
`.pkg`, which is the one thing they all agree on.

## Windows shares

A share is added exactly as it is written in Explorer, with the Windows user name and
password for that PC in the two fields beside it. Nothing has to be running on the PC.

The console has no SMB client of its own, so the payload carries [libsmb2][libsmb2]; build it
into the SDK once with `tools/build_libsmb2.sh`. Against Windows 11 it negotiates SMB 3.1.1
with mandatory signing, which is what recent builds insist on.

Two things follow from how Windows is set up by default:

- **Guest access will not work.** Windows disables it, so a user name and password are
  required even for a folder that looks open. If the PC signs in with a Microsoft account,
  the user name is usually that email address.
- **The password is stored in plain text** in `/data/pkg-browser/sources.txt`, because it has
  to be replayed on every connection. It is shown as `***` in the interface, but anyone with
  the console's filesystem can read it. Use an account you are willing to have on the console.

Installing from a share needs one more step than it looks. `sceAppInstUtilInstallByPackage`
fetches from a URL and knows nothing about SMB, so the package is republished at
`http://127.0.0.1:9050/stream/<name>.pkg` and read off the share a range at a time as the
installer asks for it. Nothing is copied to the console's disk on the way, which matters when
a package is 100 GB.

[libsmb2]: https://github.com/sahlberg/libsmb2

## Plain http sources

Only plain `http://` is supported. The payload carries no TLS, which keeps it small and its
failures obvious; sources live on your own network, where that costs nothing.

Sources are kept in `/data/pkg-browser/sources.txt` and survive restarts.

**Browse** walks a folder, showing what is in it and offering a button to adopt it as a
source. It works two ways:

- **On the console**, from `/` — easier than remembering where a USB stick mounts.
- **On a PC**, by walking a listing that PC serves. The console has no access to a PC's
  disk at all, so this only works for a folder the PC is serving: run
  [PKG Share](../ps5-pkg-share), add the address it gives you, then Browse from there.
  Sub-folders are walkable, so one shared folder covers a whole tree.

## Re-sending the payload

A copy already running holds port 9050, and a second copy cannot bind to it. So on
startup the new copy asks whatever is on that port to stand down, through a `/quit` route,
then waits a few seconds for the port before giving up.

This only works when the copy being replaced also has `/quit` — a build from before this
existed answers 404 and keeps the port, and the console has to be restarted to clear it.
The log says which happened.

## Why the console fetches it directly

The console appends `?product=…&serverIpAddr=…&r=…` to any URL it is given, using a literal
`?` without checking whether the URL already has a query string. A plain LAN directory has
no query string, so nothing breaks. Pre-signed links from file hosts do have one, which is
why handing *those* to the console fails — but they are not what this tool points at.

## Building

Needs the [ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk).

```bash
mkdir build && cd build
PATH=/opt/ps5-payload-sdk/bin:$PATH prospero-cmake ..
make
```

Output is `build/pkg-browser.elf`.

The tile icon travels inside the payload, because it has to exist on the console before
anything of ours is running there. `assets/tile-source.jpg` is the artwork;
`tools/prepare_icon.py` centre-crops and resizes it to a 512x512 `assets/icon0.png`, and
`tools/embed_asset.py` turns that into `generated/icon_asset.cpp`, which is compiled in.

```bash
python tools/prepare_icon.py assets/tile-source.jpg assets/icon0.png
python tools/embed_asset.py assets/icon0.png generated/icon_asset.cpp tile_icon0_png
```

Changing the artwork republishes the tile: the payload compares the icon on the console with
the one it carries, so a new icon reaches a console that already has a tile. The home screen
only rereads it on its next scan, so a changed icon appears after the UI restarts.

## Watching what it does

Everything is written to the kernel log, which is the only way to watch a payload that has
no screen of its own:

```bash
nc <console-ip> 3232
```

Every line is prefixed `[pkg-browser]`: startup, the tile being published, each HTTP
request, what each source returned, and the result of every install.

On-screen notifications are kept for the few things worth interrupting someone about — the
payload being ready, and an install being registered.

## How the tile works

A tile does not need a signed package. The system shows an app that exists as two files:

```
/user/app/<id>/sce_sys/param.json        what the home UI shows
/user/app/<id>/sce_sys/icon0.png         the tile icon
```

`applicationCategoryType` 65536 puts it in the Media area.

That shape is copied from Payload Manager, which is installed and working on the console this
was developed against. It matters that it is copied exactly. An earlier version here also
wrote a `/system_ex/app/<id>` half and a `param.json` carrying the fields a real package has
-- `contentId`, `sdkVersion`, `requiredSystemSoftwareVersion`, `masterVersion`. Payload
Manager has none of them, and with them the system accepted the files and never showed the
tile. The `contentId` was malformed as well: the tail of one is sixteen characters and this
had fifteen.

Deleting a tile from the home screen does **not** delete these files. The system records that
the app is gone and keeps that record across restarts, so rewriting the same id achieves
nothing. **Reinstall tile** therefore republishes under the next id -- `PBRW00002`, then
`PBRW00003` -- clearing out every earlier one first. The id in use is kept in
`/data/pkg-browser/tile-id.txt`, and `GET /tile` reports it along with what is on disk.

`sceAppInstUtilAppInstallTitleDir` would register the result, but it is **not exported on
every firmware**. On the console this was built against it is reached three ways and fails
all three, which the log spells out:

- the weak import links as null
- `kernel_dynlib_dlsym` finds `libSceAppInstUtil.sprx` loaded, but the module does not
  export the name
- no other AppInstUtil module is loaded to try instead

The directories are written regardless and the home UI picks them up on its next scan. The
practical consequence is that **deleting the tile from the home screen does not delete the
files** — the system only forgets its own record of them — so re-sending the payload changes
nothing on screen. **Reinstall tile** on the Sources page rewrites the files, and the console
has to restart before the tile comes back.

`sceAppInstUtilAppInstallAll` **is** the fallback, and on this console it is the one that
works: `AppInstallTitleDir` cannot be reached at all, and `AppInstallAll` returns 0 and puts
the tile on the home screen. An earlier note here said calling it killed the process. That was
wrong, and worth saying why: a payload that fails to load leaves the previous instance holding
port 9050, so the console keeps answering and a build that never ran looks exactly like one
that died. `/health` now reports the build stamp and start time so the two cannot be confused.

Publishing is skipped when the tile is already in place, so re-sending the payload is cheap.

### Every optional import is weak

The ELF loader resolves imports **before** `main` runs, so one symbol a firmware does not
export takes the payload down before it can log anything — which looks, from the outside,
exactly like sending the file did nothing:

```
[payload.elf] Unable to resolve 'sceAppInstUtilAppInstallTitleDir'
# process pid=1172, payload.elf calls exit() exit_value=ffffffff
```

So every optional import is declared weak and null-checked. A null check is necessary but
not sufficient: see `sceAppInstUtilAppInstallAll` above.

## State of it

Run on hardware. The payload starts, publishes the tile files, serves on 9050, and answers
`/health` and both pages:

```
[pkg-browser] starting, build Sep 18 2026 09:17:34
[pkg-browser] publishing tile PKG Browser (PBRW00001) into the Media area
[pkg-browser] wrote /user/app/PBRW00001/sce_sys/param.json (497 bytes)
[pkg-browser] wrote /user/app/PBRW00001/sce_sys/icon0.png (2502 bytes)
[pkg-browser] server starting on port 9050
```

Still unproven: whether the tile actually appears in the Media area without
`sceAppInstUtilAppInstallTitleDir` to register it, whether the console browser accepts a
plain `http://` deeplink, and whether an `eboot.bin` turns out to be required. Installing a
package from a source has not been exercised end to end yet either.

## Credits

The PS5 install path — that `sceBgftServiceInt*` is gone and
`sceAppInstUtilInstallByPackage` replaces it — was worked out by
[etaHEN](https://github.com/etaHEN/etaHEN) and by
[cy33hc/ps5-ezremote-dpi](https://github.com/cy33hc/ps5-ezremote-dpi). The directory shape
that publishes a tile follows the `install_app` sample in the
[ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk) and GFS Downloader's use of it.
This code is written from those published findings rather than derived from them.
