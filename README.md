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

