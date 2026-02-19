# macKinect User Guide

## 1. First Launch

On first launch, macKinect resolves the core in this order:

1. Existing selected core (`Application Support/core/current.json`)
2. Bundled embedded core (`assets/bundled/...`)
3. System fallback (if available)

If no core is available, use **Core Options** to install one.

## 2. Connect to Hardware

1. Plug in your Proxmark3.
2. Click **Refresh Ports**.
3. Confirm the selected port (Iceman-like ports are preferred automatically).
4. Click **Connect**.

## 3. Standard Scans

Open **Read** tab:

- **Scan HF**: single high-frequency search.
- **Scan LF**: single low-frequency search.
- **Scan EMV**: EMV scan command.
- **Continuous HF**: repeated HF scan loop.
- **Continuous LF**: repeated LF scan loop.
- **Stop Scan**: interrupts current scan loop.

## 4. Advanced Tab

Open **Advanced** tab:

1. Choose **Group** (HF / LF / EMV / Utility).
2. Choose **Action**.
3. Choose **Preset**.
4. Click **Add to chain** to queue commands.
5. Click **Run chain** to execute sequentially.

You can also add manual commands in **Custom command**.

## 5. Core Management

Use **Core Options** in top bar:

- **Update Current Core**
- **Download Latest Stable**
- **Download Experimental/Beta**
- **Add Separate Core**
- **Install Local Core**

## 6. Documentation

Use the **Docs** button (top bar) or **Documentation** button in **Advanced** page.

## 7. Common Troubleshooting

### Device not found

- Reconnect USB.
- Refresh ports.
- Verify selected `/dev/tty.*` or `/dev/cu.*` path.
- Try disconnect/connect from the app.

### Command appears to do nothing

- Check **Tools & Console** for command output.
- Verify device is connected before running scan/advanced commands.

### Core update not available

- Update/download uses GitHub release assets.  
  If no compatible asset is found, use **Install Local Core**.
