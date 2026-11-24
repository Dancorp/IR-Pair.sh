# IR-Pair.sh: use an IR remote with 240-MP

Navigate [240-MP](https://github.com/anthonycaccese/240-MP) with an infrared remote control, using a small IR receiver wired to your Raspberry Pi and a script run from the **Scripts module**.

Pairing is done with the remote and the TV screen: the script asks "Press UP...", waits for the button you press, and remembers it. Once paired, the remote works like a keyboard in 240-MP. Nothing in 240-MP itself is modified.

It works with **any infrared remote whose protocol is known to `ir-keytable`** (NEC, RC-5, RC-6, Sony and more). The script learns the buttons of *your* remote, so there is no remote-specific profile to maintain.

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

1. Download `IR-PAIR.sh` and `IR-PAIR.txt` from [this repository](https://github.com/Dancorp/IR-Pair.sh).
2. Put both files in the scripts directory:
   - Raspberry Pi OS, SteamOS or Linux: `~/.local/share/240-MP/user_scripts`

   Or, from a terminal on the Pi:

   ```
   cd ~/.local/share/240-MP/user_scripts
   curl -O https://raw.githubusercontent.com/Dancorp/IR-Pair.sh/main/IR-PAIR.sh
   curl -O https://raw.githubusercontent.com/Dancorp/IR-Pair.sh/main/IR-PAIR.txt
   chmod +x IR-PAIR.sh
   ```
3. In 240-MP, open `Settings > Scripts`, run `Rescan Scripts`, and set `Enabled` to `On`.
4. Open the Scripts module and run `IR Remote Pairing`.

## Use

The script checks that everything is in place, then asks for each button in turn:

```
>> Press UP on the remote (20s)
```

Press the button you want to use. The script confirms the code it received, then moves on. If nothing is received within 20 seconds, that action is skipped. If you press a button already used for another action, it is refused and you can try again.

| Action | What it does in 240-MP |
|---|---|
| UP / DOWN / LEFT / RIGHT | Navigate |
| SELECT (OK) | Confirm |
| BACK | Go back |
| PLAY/PAUSE | Play / pause |

A summary table is shown at the end, and the pairing is kept after a reboot.

**To redo only some buttons**, add their names to the `args` line of `IR-PAIR.txt` (for example `args = select back`) and run the script again. Names: `up down left right select back play_pause`.

---

## Limitations

- **Setup is not 100% in the interface.** Editing `config.txt`, installing `ir-keytable` and the `sudo` setup are done once, outside 240-MP. Only the pairing itself is done from the Scripts module.
- **`sudo` is required.** Either passwordless `sudo` (Option A) or a fresh token each time (Option B), because the Scripts console cannot ask for a password.
- **Only protocols known to `ir-keytable` are supported.** A very unusual remote may not be detected at all.
- **Pairing is driven by the remote.** The Scripts console does not take keyboard input, so a remote that sends no signal cannot be paired.
- **Seven actions only** (listed above). More require editing the script.
- **The remote acts as a keyboard on the whole system**, not only in 240-MP.
- **No power-on by remote:** a Raspberry Pi 3/4 cannot be started by an IR signal.
- Tested on: *(Pi model, OS version, remote model)*. Feedback on other hardware is welcome.

## Troubleshooting

| Message or symptom | What to do |
|---|---|
| `ir-keytable is not installed` | Run `sudo apt install ir-keytable`. |
| `Passwordless sudo is required` | Use Option A or B above. |
| `No IR receiver detected` | Check the `dtoverlay` line, reboot, check the wiring and the GPIO number. |
| Nothing received during pairing | Aim the remote at the receiver and check its battery. |
| Buttons do nothing after pairing | Restart 240-MP. Then run `sudo ir-keytable -s rc0 -t` in a terminal and press a button: you should see a key name such as `KEY_UP`. |
| Pairing lost after a reboot | Run the pairing again and check that it ends without error. |

## Uninstall

```
sudo rm /etc/rc_keymaps/mp240.toml
sudo sed -i '/mp240/d' /etc/rc_maps.cfg
sudo rm -f /etc/sudoers.d/mp240-ir
rm -r ~/.local/share/240-MP/ir
```

Then delete the script files from the scripts directory, and remove the `dtoverlay=gpio-ir` line from `config.txt` if you no longer need the receiver.

---

Made for [240-MP](https://github.com/anthonycaccese/240-MP) by Anthony Caccese.
