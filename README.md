# IR-Pair.sh: use an IR remote with 240-MP

Navigate [240-MP](https://github.com/anthonycaccese/240-MP) with an infrared remote control, using a small IR receiver wired to your Raspberry Pi and a script run from the **Scripts module**.

Pairing is done with the remote and the TV screen: the script lists the keys to pair, waits for the button you press for each one, and remembers it. Once paired, the remote works like a keyboard in 240-MP. Nothing in 240-MP itself is modified.

It works with **any infrared remote whose protocol is known to `ir-keytable`** (NEC, RC-5, RC-6, Sony and more). The script learns the buttons of *your* remote, so there is no remote-specific profile to maintain. That includes the remote of your TV, or an old VCR / DVD remote from a drawer.

The keys to pair are listed in a simple text file (`IR-PAIR.conf`): enable a key by removing a `#`, and 240-MP gets a new remote button.

---

## What you need

### 1. An IR receiver

A 3-pin IR receiver (VS1838B or TSOP38xx type, about 1 EUR) wired to the Pi:

| Receiver | Raspberry Pi header |
|---|---|
| VCC | Pin 1 (3.3V) |
| GND | Pin 6 (GND) |
| OUT (data) | Pin 12 (GPIO 18) |

The pin order differs between manufacturers: check the datasheet of your receiver, and make sure it accepts 3.3V.

### 2. Enable the receiver in `config.txt`

Add this line to `config.txt`, then reboot the Pi:

```
dtoverlay=gpio-ir,gpio_pin=18
```

You can edit the file from a computer (it is on the boot partition of the SD card) or on the Pi itself (`/boot/firmware/config.txt` on recent Raspberry Pi OS, `/boot/config.txt` on older versions). Replace `18` if you used another GPIO.

### 3. Install `ir-keytable`

In a terminal on the Pi (keyboard or SSH):

```
sudo apt install ir-keytable
```

This is the only package needed.

### 4. Allow the script to use `sudo`

The script needs administrator rights, and the Scripts module cannot type a password for you. Pick one of these two options:

**Option A: remove the sudo password (permanent, recommended)**

```
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/mp240-ir
sudo chmod 440 /etc/sudoers.d/mp240-ir
```

This gives your user passwordless `sudo`. It is fine on a Pi dedicated to 240-MP, but think twice on a shared machine.

**Option B: activate a sudo token just before running the script (temporary)**

In a terminal on the Pi, run:

```
sudo -v
```

Enter your password, then launch the script from 240-MP within the next ~15 minutes. You will need to repeat this each time. This may not work on every setup: if the script still reports that sudo is not available, use Option A.

---

## Install

Same method as the [YT-DLP updater](https://github.com/anthonycaccese/240-MP/wiki/YT%E2%80%90DLP):

1. Download these three files from [this repository](https://github.com/Dancorp/IR-Pair.sh):
   - `IR-PAIR.sh`: the script
   - `IR-PAIR.txt`: the Scripts module entry
   - `IR-PAIR.conf`: the list of keys to pair
2. Put them all in the scripts directory (they must keep the same base name):
   - Raspberry Pi OS, SteamOS or Linux: `~/.local/share/240-MP/user_scripts`

   Or, from a terminal on the Pi:

   ```
   cd ~/.local/share/240-MP/user_scripts
   curl -O https://raw.githubusercontent.com/Dancorp/IR-Pair.sh/main/IR-PAIR.sh
   curl -O https://raw.githubusercontent.com/Dancorp/IR-Pair.sh/main/IR-PAIR.txt
   curl -O https://raw.githubusercontent.com/Dancorp/IR-Pair.sh/main/IR-PAIR.conf
   chmod +x IR-PAIR.sh
   ```
3. In 240-MP, open `Settings > Scripts`, run `Rescan Scripts`, and set `Enabled` to `On`.
4. Open the Scripts module and run `IR Remote Pairing`.

---

## Use

The script checks that everything is in place, then lists the keys to pair. Press the matching button on your remote each time:

```
  240-MP - IR remote pairing
  --------------------------
  Checks ............. OK (rc0)

  Press each button on the REMOTE (7 keys):

  [1/7] Navigate up          OK
  [2/7] Navigate down        OK
  [3/7] Navigate left        18s
  ...

  Saved. 7/7 keys paired.
```

A countdown runs on the current line. After 20 seconds without a signal the key is skipped. If you press a button already used for another key, it is refused and you can try again. The pairing is kept after a reboot.

### Choose the keys: `IR-PAIR.conf`

`IR-PAIR.conf` lists the keys the script pairs, one per line, with a description shown during pairing:

```
KEY_UP        Navigate up
KEY_ENTER     Select / confirm (OK)
#KEY_VOLUMEUP Volume up
```

- A line starting with `#` is ignored: that key is not paired.
- Remove the `#` to enable a key, add it back to stop managing it.
- By default the keys needed to navigate are enabled: up, down, left, right, enter, escape and space (play / pause).
- The file contains a long list of other keys (playback, volume, channels, menu, color buttons, digits, function keys, power), all commented out. Any valid Linux key name (`KEY_...`) can be added on a new line.

Enabling a key only makes the remote send it. 240-MP (or the system) must react to that key for it to do something.

### Re-pair or add keys: the `args` line

The `args` line of `IR-PAIR.txt` controls what the script does:

| `args` | Effect |
|---|---|
| *(empty)* | Pair every enabled key, starting from scratch |
| `new` | Pair only the enabled keys that have no code yet (use after enabling a key) |
| `enter esc` | Re-pair only the listed keys (the `KEY_` prefix is optional) |

---

## Limitations

- **Setup is not 100% in the interface.** Editing `config.txt`, installing `ir-keytable` and the `sudo` setup are done once, outside 240-MP. Only the pairing itself is done from the Scripts module.
- **`sudo` is required.** Either passwordless `sudo` (Option A) or a fresh token each time (Option B), because the Scripts console cannot ask for a password.
- **Only protocols known to `ir-keytable` are supported.** A very unusual remote may not be detected at all.
- **Pairing is driven by the remote.** The Scripts console does not take keyboard input, so a remote that sends no signal cannot be paired.
- **A paired key must be understood by 240-MP.** Adding keys to the config file does not teach 240-MP new shortcuts.
- **The remote acts as a keyboard on the whole system**, not only in 240-MP. Some keys (such as power) may trigger system actions.
- **TV remotes:** the TV receives the same signals as the Pi. Choose buttons that do nothing harmful on the TV side. Remotes using Bluetooth or radio instead of infrared cannot be used.
- **No power-on by remote:** a Raspberry Pi 3/4 cannot be started by an IR signal.
- Tested on: *(Pi model, OS version, remote model)*. Feedback on other hardware is welcome.

## Troubleshooting

| Message or symptom | What to do |
|---|---|
| `ir-keytable is not installed` | Run `sudo apt install ir-keytable`. |
| `sudo asks for a password...` | Use Option A or B above. |
| `No IR receiver detected` | Check the `dtoverlay` line, reboot, check the wiring and the GPIO number. |
| `No key is enabled` | Every line of `IR-PAIR.conf` is commented out: remove a `#`. |
| `Config file not found` | `IR-PAIR.conf` must be in the same folder as `IR-PAIR.sh` with the same base name. The script falls back to the default keys. |
| `Keymap not loaded` | Check the key names in `IR-PAIR.conf` (they must be valid `KEY_...` names). |
| Nothing received during pairing | Aim the remote at the receiver and check its battery. |
| Countdown lines pile up on screen | Set `COUNTDOWN=0` at the top of `IR-PAIR.sh`. |
| Buttons do nothing after pairing | Restart 240-MP. Then run `sudo ir-keytable -s rc0 -t` in a terminal and press a button: you should see a key name such as `KEY_UP`. |
| Pairing lost after a reboot | Run the pairing again and check that it ends without error. |

## Uninstall

```
sudo rm /etc/rc_keymaps/mp240.toml
sudo sed -i '/mp240/d' /etc/rc_maps.cfg
sudo rm -f /etc/sudoers.d/mp240-ir
rm -r ~/.local/share/240-MP/ir
```

Then delete `IR-PAIR.sh`, `IR-PAIR.txt` and `IR-PAIR.conf` from the scripts directory, and remove the `dtoverlay=gpio-ir` line from `config.txt` if you no longer need the receiver.

---

Made for [240-MP](https://github.com/anthonycaccese/240-MP) by Anthony Caccese.
