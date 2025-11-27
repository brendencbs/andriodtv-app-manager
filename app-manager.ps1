<#
.SYNOPSIS
    Android TV App Manager (Debloater Pro) - GUI Edition
.DESCRIPTION
    A WinForms based GUI to manage, uninstall, and restore applications on Android TV via ADB.
    Features search, safety filters, and context menus to identify packages.
.NOTES
    Requires ADB in system PATH.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- GLOBAL CONFIG ---
$script:adbPath = "adb" # Assumes in PATH. Change if needed.
$script:connected = $false

# --- ADB FUNCTIONS ---

function Get-AdbStatus {
    $dev = & $script:adbPath devices 2>&1 | Select-String "device$"
    if ($dev) { return $true } else { return $false }
}

function Get-Apps {
    param([string]$Type) # 'Enabled' or 'Disabled'

    $cmdFilter = if ($Type -eq 'Disabled') { '-d' } else { '-e' }
    $raw = & $script:adbPath shell pm list packages $cmdFilter 2>&1

    $list = @()
    foreach ($line in $raw) {
        if ($line -match "package:(.*)") {
            $pkg = $matches[1].Trim()
            $isSystem = $true
            # Simple heuristic: if it doesn't start with android. or com.google, might be user
            # A more accurate way requires 'pm list packages -3', but we want a unified list for the grid

            $obj = [PSCustomObject]@{
                PackageName = $pkg
                Type = "Unknown"
            }
            $list += $obj
        }
    }
    return $list
}

function Uninstall-App {
    param($pkg)
    # user 0 uninstall keeps data on disk so it can be restored
    $res = & $script:adbPath shell pm uninstall --user 0 $pkg 2>&1
    return $res
}

function Restore-App {
    param($pkg)
    # install-existing brings back the app for user 0
    $res = & $script:adbPath shell cmd package install-existing $pkg 2>&1
    return $res
}

# --- GUI GENERATION ---

# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Android TV Manager - Master Edition"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

# Status Bar
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Checking ADB..."
$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

# Tabs (Uninstall vs Restore)
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"
$form.Controls.Add($tabControl)

# --- TAB 1: INSTALLED APPS ---
$tabInstalled = New-Object System.Windows.Forms.TabPage
$tabInstalled.Text = "Installed Apps (Uninstall)"
$tabInstalled.Padding = New-Object System.Windows.Forms.Padding(10)
$tabControl.Controls.Add($tabInstalled)

# Top Panel (Search & Refresh)
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Dock = "Top"
$panelTop.Height = 40
$tabInstalled.Controls.Add($panelTop)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh List"
$btnRefresh.Location = New-Object System.Drawing.Point(0, 5)
$btnRefresh.Size = New-Object System.Drawing.Size(100, 30)
$btnRefresh.BackColor = [System.Drawing.Color]::LightBlue
$panelTop.Controls.Add($btnRefresh)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Search:"
$lblSearch.Location = New-Object System.Drawing.Point(120, 12)
$lblSearch.AutoSize = $true
$panelTop.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(170, 9)
$txtSearch.Size = New-Object System.Drawing.Size(300, 25)
$panelTop.Controls.Add($txtSearch)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Right-click an app to Google it."
$lblHint.ForeColor = [System.Drawing.Color]::Gray
$lblHint.Location = New-Object System.Drawing.Point(480, 12)
$lblHint.AutoSize = $true
$panelTop.Controls.Add($lblHint)

# Grid View
$gridInstalled = New-Object System.Windows.Forms.DataGridView
$gridInstalled.Dock = "Fill"
$gridInstalled.AllowUserToAddRows = $false
$gridInstalled.RowHeadersVisible = $false
$gridInstalled.SelectionMode = "FullRowSelect"
$gridInstalled.MultiSelect = $true
$gridInstalled.AutoSizeColumnsMode = "Fill"
$gridInstalled.BackgroundColor = [System.Drawing.Color]::White

# Columns
$colCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.HeaderText = "Select"
$colCheck.Width = 50
$gridInstalled.Columns.Add($colCheck) | Out-Null

$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.HeaderText = "Package Name"
$colName.ReadOnly = $true
$gridInstalled.Columns.Add($colName) | Out-Null

# Context Menu (Right Click)
$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$ctxItemSearch = $ctxMenu.Items.Add("Google this Package Name")
$gridInstalled.ContextMenuStrip = $ctxMenu

$tabInstalled.Controls.Add($gridInstalled)
$gridInstalled.BringToFront()

# Bottom Panel (Action)
$panelBot = New-Object System.Windows.Forms.Panel
$panelBot.Dock = "Bottom"
$panelBot.Height = 50
$tabInstalled.Controls.Add($panelBot)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "UNINSTALL SELECTED"
$btnUninstall.Dock = "Right"
$btnUninstall.Width = 150
$btnUninstall.BackColor = [System.Drawing.Color]::IndianRed
$btnUninstall.ForeColor = [System.Drawing.Color]::White
$btnUninstall.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelBot.Controls.Add($btnUninstall)

# --- TAB 2: RESTORE APPS ---
$tabRestore = New-Object System.Windows.Forms.TabPage
$tabRestore.Text = "Restore Deleted Apps"
$tabRestore.Padding = New-Object System.Windows.Forms.Padding(10)
$tabControl.Controls.Add($tabRestore)

$lblRestoreInfo = New-Object System.Windows.Forms.Label
$lblRestoreInfo.Text = "These apps were uninstalled for the current user (0) but exist on the system image."
$lblRestoreInfo.Dock = "Top"
$tabRestore.Controls.Add($lblRestoreInfo)

$gridRestore = New-Object System.Windows.Forms.DataGridView
$gridRestore.Dock = "Fill"
$gridRestore.AllowUserToAddRows = $false
$gridRestore.RowHeadersVisible = $false
$gridRestore.SelectionMode = "FullRowSelect"
$gridRestore.AutoSizeColumnsMode = "Fill"
$gridRestore.BackgroundColor = [System.Drawing.Color]::White
# Add columns similar to above
$colCheckR = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheckR.HeaderText = "Select"
$colCheckR.Width = 50
$gridRestore.Columns.Add($colCheckR) | Out-Null
$colNameR = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNameR.HeaderText = "Package Name"
$colNameR.ReadOnly = $true
$gridRestore.Columns.Add($colNameR) | Out-Null

$tabRestore.Controls.Add($gridRestore)

$panelBotR = New-Object System.Windows.Forms.Panel
$panelBotR.Dock = "Bottom"
$panelBotR.Height = 50
$tabRestore.Controls.Add($panelBotR)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "RESTORE SELECTED"
$btnRestore.Dock = "Right"
$btnRestore.Width = 150
$btnRestore.BackColor = [System.Drawing.Color]::SeaGreen
$btnRestore.ForeColor = [System.Drawing.Color]::White
$panelBotR.Controls.Add($btnRestore)

$btnRefreshR = New-Object System.Windows.Forms.Button
$btnRefreshR.Text = "Refresh List"
$btnRefreshR.Dock = "Left"
$btnRefreshR.Width = 100
$panelBotR.Controls.Add($btnRefreshR)


# --- LOGIC & EVENTS ---

# Data Storage
$script:allApps = @()
$script:disabledApps = @()

$RefreshData = {
    if (-not (Get-AdbStatus)) {
        $statusLabel.Text = "Error: ADB Device not found. Connect USB/Wifi and enable Debugging."
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        return
    }

    $statusLabel.Text = "ADB Connected. Fetching packages..."
    $statusLabel.ForeColor = [System.Drawing.Color]::Green
    [System.Windows.Forms.Application]::DoEvents()

    # Load Installed
    $gridInstalled.Rows.Clear()
    $script:allApps = Get-Apps -Type 'Enabled'
    foreach ($app in $script:allApps) {
        $gridInstalled.Rows.Add($false, $app.PackageName) | Out-Null
    }

    # Load Disabled (Restorable)
    $gridRestore.Rows.Clear()
    $script:disabledApps = Get-Apps -Type 'Disabled'
    foreach ($app in $script:disabledApps) {
        $gridRestore.Rows.Add($false, $app.PackageName) | Out-Null
    }

    $statusLabel.Text = "Ready. Installed: $($script:allApps.Count) | Restorable: $($script:disabledApps.Count)"
}

$SearchFilter = {
    $term = $txtSearch.Text.ToLower()
    $gridInstalled.Rows.Clear()
    foreach ($app in $script:allApps) {
        if ($app.PackageName.ToLower().Contains($term)) {
            $gridInstalled.Rows.Add($false, $app.PackageName) | Out-Null
        }
    }
}

$DoUninstall = {
    $count = 0
    foreach ($row in $gridInstalled.Rows) {
        if ($row.Cells[0].Value -eq $true) {
            $pkg = $row.Cells[1].Value
            $statusLabel.Text = "Uninstalling $pkg..."
            [System.Windows.Forms.Application]::DoEvents()

            Uninstall-App -pkg $pkg
            $count++
        }
    }
    [System.Windows.Forms.MessageBox]::Show("Uninstalled $count apps.", "Complete")
    & $RefreshData
}

$DoRestore = {
    $count = 0
    foreach ($row in $gridRestore.Rows) {
        if ($row.Cells[0].Value -eq $true) {
            $pkg = $row.Cells[1].Value
            $statusLabel.Text = "Restoring $pkg..."
            [System.Windows.Forms.Application]::DoEvents()

            Restore-App -pkg $pkg
            $count++
        }
    }
    [System.Windows.Forms.MessageBox]::Show("Restored $count apps.", "Complete")
    & $RefreshData
}

$ContextMenuClick = {
    if ($gridInstalled.SelectedRows.Count -gt 0) {
        $pkg = $gridInstalled.SelectedRows[0].Cells[1].Value
        Start-Process "https://www.google.com/search?q=$pkg+android+tv"
    }
}

# Bind Events
$form.Add_Load($RefreshData)
$btnRefresh.Add_Click($RefreshData)
$btnRefreshR.Add_Click($RefreshData)
$txtSearch.Add_TextChanged($SearchFilter)
$btnUninstall.Add_Click($DoUninstall)
$btnRestore.Add_Click($DoRestore)
$ctxItemSearch.Add_Click($ContextMenuClick)

# Show Form
$form.ShowDialog() | Out-Null