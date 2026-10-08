# iic-osic-tools-scripts

Scripts that let every user on a shared Linux host start their own
[IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS) desktop (VNC in the
browser) with rootless Podman. All users run the image from **one shared,
read-only image store**, so the ~13 GB image exists only once on the host.

- [For users](#for-users)
- [For admins](#for-admins)
- [How it works](#how-it-works)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

---

## For users

Log in to the host (e.g. with SSH) and run:

```bash
iic-osic-tools start
```

It prints a URL such as `http://host.example.org:50050/?password=…`. Open it
in your browser to get the desktop with all EDA tools.

| Command                 | What it does                                               |
|-------------------------|------------------------------------------------------------|
| `iic-osic-tools start`  | Starts your container, or shows the URL if it is running   |
| `iic-osic-tools stop`   | Stops your container                                       |
| `iic-osic-tools status` | Shows whether your container is running                    |
| `iic-osic-tools url`    | Prints your URL (with the password) again                  |
| `iic-osic-tools newpw`  | Creates a new password (takes effect after stop and start) |

Good to know:

- **Save your work in `/foss/designs`.** It is the folder `~/iic-tools-data`
  in your home directory on the host (and so also on your network home share).
  Everything else in the container is reset on every start.
- **`~/iic-tools-data` is private** (mode 0700), `iic-osic-tools start` sets
  this on every start. Keep it that way: your Claude login is stored there.
- **Claude Code** can be installed in the container once, in a terminal of the
  desktop:

  ```bash
  curl -fsSL https://claude.ai/install.sh | bash
  ```

  The `claude` command, its updates, your settings and your login are kept in
  `~/iic-tools-data` (in `.claude`, `.claude-bin` and `.claude-versions`,
  about 250 MB) and survive restarts. It is separate from a Claude Code you
  may use on the host itself.
- **Your password and port stay the same** across restarts. The password is
  stored in `~/.config/iic-osic-tools/vnc.env`. Do not share the URL, it
  contains the password.
- **The container keeps running after you log out.** `iic-osic-tools start`
  enables "lingering" for your account for that. Stop it with
  `iic-osic-tools stop` when you no longer need it.
- **If you get "Port … is used by another program"**, someone else is
  listening on your port. Tell the admin, and run `iic-osic-tools newpw`
  before you open your URL again.
- **If you get "has no port" or "has no sub-UID range"**, your account is not
  enabled yet. Ask the admin.

---

## For admins

### Files

| Repository file                              | Install to                                       | Purpose                                                  |
|----------------------------------------------|--------------------------------------------------|----------------------------------------------------------|
| `bin/iic-osic-tools`                         | `/usr/local/bin/iic-osic-tools`                  | User command, starts the personal container              |
| `sbin/iic-osic-tools-enable`                 | `/usr/local/sbin/iic-osic-tools-enable`          | Enables users: sub-UID range, port, firewall             |
| `sbin/podman-subid-add`                      | `/usr/local/sbin/podman-subid-add`               | Adds/removes sub-UID/GID ranges for rootless Podman      |
| `sbin/iic-osic-tools-image-update`           | `/usr/local/sbin/iic-osic-tools-image-update`    | Pulls/updates the image in the shared store              |
| `etc/containers/storage-iic-osic-tools.conf` | `/etc/containers/storage-iic-osic-tools.conf`    | Podman storage config with the shared image store        |
| `etc/profile.d/iic-osic-tools.sh`            | `/etc/profile.d/iic-osic-tools.sh`               | Selects that config for `podman` in login shells         |
| `etc/environment.d/50-iic-osic-tools.conf`   | `/etc/environment.d/50-iic-osic-tools.conf`      | Selects that config for Podman in systemd user services  |
| `etc/iic-osic-tools/iic-osic-tools.conf`     | `/etc/iic-osic-tools/iic-osic-tools.conf`        | Local settings (port range, firewall zone), never overwritten |
| `install.sh`                                 | –                                                | Installs or updates all of the above                     |

Created at runtime: `/etc/iic-osic-tools/ports` (port assignments, by
`iic-osic-tools-enable`), entries in `/etc/subuid` and `/etc/subgid` (by
`podman-subid-add`), and the image store `/var/local/eda/images`.

### Requirements

- Podman (rootless), `fuse-overlayfs`, `firewalld` (optional), `ss` (iproute2)
- A local user `eda` that owns the shared image store, with lingering enabled
  (`loginctl enable-linger eda`)

### Installation (as root)

```bash
cd iic-osic-tools-scripts
./install.sh -n     # dry run: shows what would be installed (works as any user)
./install.sh        # installs or updates all files
```

`install.sh` copies all files to the places in the table above, owned by
root, and skips files that are up to date. Run it again after every update
of the repository. **Keep the files owned by root:** root runs the `sbin`
scripts, so whoever can write them can run commands as root.

Local settings go into `/etc/iic-osic-tools/iic-osic-tools.conf`, which
`install.sh` creates once and never overwrites:

| Setting               | Default | Meaning                                                        |
|-----------------------|---------|----------------------------------------------------------------|
| `PORT_MIN`/`PORT_MAX` | 50050/50100 | Range of the users' web ports                              |
| `FW_ZONE`             | (empty) | firewalld zone of the users' interface, empty = default zone (`firewall-cmd --get-active-zones`) |

Then create the shared image store (this pulls ~13 GB):

```bash
mkdir -p /var/local/eda/images && chown eda: /var/local/eda/images
/usr/local/sbin/iic-osic-tools-image-update
```

openSUSE's `sudo` does not search `/usr/local/sbin`, so call these scripts
with their full path when you use `sudo`.

### Enabling and disabling users

```bash
/usr/local/sbin/iic-osic-tools-enable 'DOMAIN\jdoe' alice bob
/usr/local/sbin/iic-osic-tools-enable --disable bob
```

`iic-osic-tools-enable`

1. gives the user a sub-UID/GID range (via `podman-subid-add`), if they have
   none yet,
2. assigns the lowest free port from **50050–50100** and records it in
   `/etc/iic-osic-tools/ports`,
3. opens that port in `firewalld` (runtime and permanent).

Running it again for an enabled user changes nothing, but repairs a missing
firewall rule. `--disable` closes the port in the firewall and frees it for
other users; the sub-UID range stays (remove it with
`podman-subid-add --remove user`).

Quote AD user names (`'DOMAIN\jdoe'`), otherwise the shell removes the
backslash. A user who already used Podman before getting the sub-UID range
needs `podman system migrate` once, so Podman picks up the range;
`iic-osic-tools start` detects that and runs it itself.

The range has 51 ports, so at most 51 users can be enabled at the same time.
Change `PORT_MIN`/`PORT_MAX` in `/etc/iic-osic-tools/iic-osic-tools.conf` if you need more, and
keep it clear of other services (the `eda_server_*` containers of
IIC-OSIC-TOOLS use 50001 upwards).

### Updating the image

```bash
/usr/local/sbin/iic-osic-tools-image-update     # as root or as eda
```

It pulls `docker.io/hpretl/iic-osic-tools:latest` into the shared store and
makes it readable for all users. Running containers keep the old image; users
get the new one with `iic-osic-tools stop` and `iic-osic-tools start`.

**Never call a plain `podman pull` or `podman --root /var/local/eda/images pull`
for the store**, always use this script: layers pulled without its options are
not readable for the other users. Remove old images (the script prints the
command) or prune the store only when no user container runs on them.

---

## How it works

### Shared read-only image store

`/var/local/eda/images` is a normal Podman storage directory of user `eda`.
`iic-osic-tools-image-update` pulls with the storage option
`force_mask = "shared"`: all image files are stored readable for everyone, and
their real owner and mode go into the extended attribute
`user.containers.override_stat`. `fuse-overlayfs` applies these attributes in
the containers, so e.g. `/etc/shadow` is still `root:shadow 0640` inside.

The other users' Podman reads the store as an **additional image store**
(`additionalimagestores` in `storage-iic-osic-tools.conf`). Rootless Podman
ignores that setting in `/etc/containers/storage.conf`, so the config is
selected with `CONTAINERS_STORAGE_CONF`, set in `/etc/profile.d`,
`/etc/environment.d` and by `iic-osic-tools` itself. Each user keeps their own
storage in `~/.local/share/containers`; a running container only adds a few
MB there.

### The user container

`iic-osic-tools start` runs, in essence:

```bash
podman run -d --rm --replace --pull=never --name iic-osic-tools-<user> \
    --user <uid>:<gid> --userns=keep-id --passwd=false \
    --security-opt seccomp=unconfined \
    --sysctl net.ipv4.ip_unprivileged_port_start=0 \
    -p <port>:80 --env-file ~/.config/iic-osic-tools/vnc.env \
    -e CLAUDE_CONFIG_DIR=/foss/designs/.claude -e PATH=<image PATH>:/headless/.local/bin \
    -v ~/iic-tools-data:/foss/designs:rw \
    -v ~/iic-tools-data/.claude-bin:/headless/.local/bin:rw \
    -v ~/iic-tools-data/.claude-versions:/headless/.local/share/claude:rw \
    docker.io/hpretl/iic-osic-tools:latest
```

- `--userns=keep-id` keeps the user's UID in the container, so files in
  `/foss/designs` have the right owner on both sides.
- `--passwd=false`: with `keep-id`, Podman would look up the user to write an
  `/etc/passwd` entry, which fails for AD (winbind) users inside the user
  namespace. The image does not need the entry.
- `--env-file` passes the VNC password, so it never shows up in `ps`.
- `--pull=never`: a missing shared image is a setup problem, and a pull would
  put a private 13 GB copy into the user's home.
- `--rm --replace`: every start creates a fresh container and so picks up image
  updates; only `~/iic-tools-data` persists. The container's own home
  (`/headless`) comes from the image and holds the desktop and tool settings
  of the image (Xfce, `.bashrc`, KLayout plugins, the Veryl toolchain, …).
- `~/iic-tools-data` has mode 0700. The host, the container (thanks to
  `keep-id`) and Samba (which accesses files as the logged-in user) all work
  as the same Unix user, so no group or ACL settings are needed. 0750 would
  not be private: domain users share one primary group.
- Claude Code: `CLAUDE_CONFIG_DIR` moves `~/.claude` and `~/.claude.json`. The
  native installer always puts the `claude` command into `~/.local/bin`
  (`/headless/.local/bin`) and the versions into `$XDG_DATA_HOME/claude`.
  `XDG_DATA_HOME` is not changed for the whole container, as other tools of the
  image keep data in `/headless/.local/share`; instead, only these two
  directories are mounted from `~/iic-tools-data`.
- The VNC password stays in `~/.config/iic-osic-tools` on the host, outside
  `~/iic-tools-data`, so it is not visible in the container.
- Container names allow only `[a-zA-Z0-9_.-]`, so `DOMAIN\jdoe` becomes
  `iic-osic-tools-DOMAIN_jdoe`.

### Sub-UID/GID ranges

Rootless Podman maps the IDs of the image (root, shadow, …) to a range of
otherwise unused host IDs, which root grants in `/etc/subuid` and
`/etc/subgid`. `useradd` creates such ranges for local users, but AD users
never get one. `podman-subid-add` adds them:

- entries use the **user name** (`DOMAIN\jdoe:200000001:65536`). Podman looks
  the range up by name for `keep-id`; a numeric UID entry is only accepted by
  `newuidmap`, which leads to `runc` errors. Numeric entries are converted.
- ranges start above all existing ones, at 1000000 at least (above the
  winbind ID ranges),
- each range is larger than the user's UID and GID, which `keep-id` needs.

---

## Security notes

- **A sub-UID range lets a user run any image with rootless Podman**, not only
  IIC-OSIC-TOOLS. That grants no privileges on the host: "root" in a rootless
  container is the user, and the extra IDs belong to nobody else. Restricting
  registries or images is not enforceable (users can override the Podman
  config); CPU/memory limits per user (systemd `user-.slice`) and disk quotas
  are.
- **The VNC traffic is plain HTTP**, and the URL contains the password. Use it
  only in a trusted network, or put an HTTPS reverse proxy in front.
- **Port hijacking:** any local user can listen on a free port above 1024. While
  a user's container is stopped, someone else could listen on that user's port
  and capture the password from the URL. `iic-osic-tools start` then fails with
  "Port … is used by another program". Root finds the owner with
  `ss -ltnpe 'sport = :50050'`; the victim should run `iic-osic-tools newpw`.
- **The scripts in `/usr/local/sbin` must be owned by root** and not writable
  for others.

---

## Troubleshooting

| Message                                                           | Cause and fix |
|-------------------------------------------------------------------|---------------|
| `has no port in /etc/iic-osic-tools/ports` / `has no sub-UID range` | User not enabled: `iic-osic-tools-enable user` |
| `no subuid ranges found for user …`                               | Missing or numeric sub-UID entry: `iic-osic-tools-enable user`, then `podman system migrate` as the user (`iic-osic-tools start` does that itself) |
| `runc create failed: … no mapping found for uid 0`                | Same as above |
| `Image … not found in the shared store`                           | Store missing or not readable: run `iic-osic-tools-image-update`; as the user, `podman images` must list the image with `R/O true` |
| `failed to get current user: user: unknown userid …`              | Old `iic-osic-tools` without `--passwd=false`, install the current version |
| `current system boot ID differs from cached boot ID`              | A Podman runtime directory in `/tmp` survived a reboot. Run Podman with `XDG_RUNTIME_DIR=/run/user/<uid>` (lingering on), or delete the directories named in the message |
| The URL times out from other computers, but works on the host or through `ssh -L <port>:localhost:<port>` | The port is not open in firewalld (e.g. assigned before the firewall support, or in the wrong zone): run `iic-osic-tools-enable user` again, check `FW_ZONE` and `firewall-cmd --get-active-zones` |
| The image was pulled into the user's home                         | The user's Podman does not see the shared store: check `podman info --format '{{.Store.ConfigFile}}'` and `CONTAINERS_STORAGE_CONF`; a personal `~/.config/containers/storage.conf` is ignored while the variable is set |

---

## License

Apache License 2.0, the same as IIC-OSIC-TOOLS. See [LICENSE](LICENSE).
