# 🌞 DMS Brightness Plugin

A lightweight brightness control plugin for **Dank Material Shell (DMS)** on Linux.

Supports both:

* 🖥️ Internal displays (via `brightnessctl`)
* 🖥️ External monitors (via `ddcutil`)

---

## ✨ Features

* 🔆 Adjust brightness directly from DMS panel
* 🎯 Per-monitor control (no cross interference)
* ⚡ Fast response with debounce mechanism
* 🔄 One-click presets (0%, 25%, 50%, 75%, 100%)
* 🔍 Auto-detect available displays
* 💤 Minimal CPU usage (no background polling)

---

## 📦 Requirements

Make sure you have the following installed:

```bash
# For internal display brightness
sudo pacman -S brightnessctl

# For external monitor (DDC/CI)
sudo pacman -S ddcutil
```

> ⚠️ For `ddcutil`, you may need I2C permissions:

```bash
sudo modprobe i2c-dev
sudo usermod -aG i2c $USER
```

Then log out and log back in.

---

## 🚀 Installation

### Method 1: Manual

1. Clone the repository:

```bash
git clone https://github.com/smithyyang/dms-brightness-plugin.git
```

2. Copy files into DMS plugin directory:

```bash
cp -r dms-brightness-plugin ~/.config/DankMaterialShell/plugins/ddcBrightness
```

3. Restart DMS

---

### Method 2: Direct copy (recommended)

Copy these files into:

```bash
~/.config/DankMaterialShell/plugins/ddcBrightness/
```

* `plugin.json`
* `DdcBrightness.qml`

---

## 🖥️ Usage

* Open DMS panel
* Click the brightness icon
* Adjust sliders per monitor

---

## ⚙️ How It Works

* Uses `brightnessctl` for laptop/internal screens
* Uses `ddcutil` for external monitors via DDC/CI
* Runs a **one-time scan** at startup (no continuous background scanning)
* Applies brightness changes via lightweight subprocess calls

---


## 🛠️ Troubleshooting

### No external monitor detected

```bash
ddcutil detect
```

If nothing shows:

* Check if your monitor supports DDC/CI
* Enable DDC/CI in monitor settings

---

### Permission issues

```bash
sudo usermod -aG i2c $USER
```

---

## 📸 Screenshot (optional)

<img width="387" height="449" alt="1774626917902622219" src="https://github.com/user-attachments/assets/922841d6-b877-4065-811b-24951bda51d9" />


---

## 🤝 Contributing

Pull requests are welcome!

---

## 📄 License

MIT License
---

## 👨‍💻 Author

Made by **@smithyyang**

---

## ⭐ If you like it

Give this repo a star ⭐
