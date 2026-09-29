# QiuBar battery reader -- 输出已配对 BLE 设备电量 JSON（已在真机验证：RAPOO 键鼠可读出 96%/85%）
# ponytail: 仅覆盖 BLE(Battery Service 0x180F)；纯经典蓝牙 HID（老设备）Windows 不暴露电量。
# 注: COM 对象(IAsyncOperation/IBuffer)不能过 PS 函数参数边界/直接绑定，一律反射调用。
param([int]$ParentPid = 0, [switch]$Watch)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ---------- -Watch：常驻监听模式，蓝牙设备连上时输出一行 BT-ARRIVE ----------
# WMI 每 2s 扫一次 PnP 新节点，只认 BTHENUM(蓝牙枚举)/BTHLE(BLE) 前缀；事件驱动，平时零 CPU。
if ($Watch) {
  try {
    Register-CimIndicationEvent -Query "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_PnPEntity' AND (TargetInstance.DeviceID LIKE 'BTHENUM%' OR TargetInstance.DeviceID LIKE 'BTHLE%')" -SourceIdentifier QiuWatch | Out-Null
  } catch {
    [Console]::Out.WriteLine("BT-WATCH-ERR $($_.Exception.Message)")
    [Console]::Out.Flush(); exit 1
  }
  while ($true) {
    $e = Wait-Event -SourceIdentifier QiuWatch -Timeout 5
    if (-not $e) {
      # 空闲心跳：父进程没了就自杀，避免留下孤儿常驻
      if ($ParentPid -and -not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
      continue
    }
    Start-Sleep -Milliseconds 1200                        # 等一次连接冒出的整串服务节点到齐
    Get-Event -SourceIdentifier QiuWatch | Remove-Event   # 合并成一帧信号
    [Console]::Out.WriteLine('BT-ARRIVE')
    [Console]::Out.Flush()
  }
  exit 0
}

$json = '[]'
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $TypeBle   = [Windows.Devices.Bluetooth.BluetoothLEDevice,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
  $TypeInfos = [Windows.Devices.Enumeration.DeviceInformationCollection,Windows.Devices.Enumeration,ContentType=WindowsRuntime]
  $TypeGS    = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
  $TypeGC    = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicsResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
  $TypeGR    = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattReadResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
  $FromBuffer = [Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime].GetMethod('FromBuffer')
  $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Fin($task) { $task.Wait(10000) | Out-Null; $task.Result }
  function T($type, $op) { $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op)) }

  $out = @()
  $sel = [Windows.Devices.Bluetooth.BluetoothLEDevice]::GetDeviceSelectorFromPairingState($true)
  $infos = Fin (T $TypeInfos ([Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime]::FindAllAsync($sel)))

  foreach ($info in $infos) {
    $dev = $null; $level = -1; $name = "$($info.Name)".Trim()
    try {
      $dev = Fin (T $TypeBle ([Windows.Devices.Bluetooth.BluetoothLEDevice]::FromIdAsync($info.Id)))
      if ($dev) {
        if (-not $name) { $name = "$($dev.Name)".Trim() }
        $connected = ($dev.ConnectionStatus.ToString() -eq 'Connected')
        $svcs = Fin (T $TypeGS ($dev.GetGattServicesAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)))
        foreach ($s in $svcs.Services) {
          if ($s.Uuid.ToString() -ne '0000180f-0000-1000-8000-00805f9b34fb') { continue }
          $chars = Fin (T $TypeGC ($s.GetCharacteristicsAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)))
          foreach ($c in $chars.Characteristics) {
            if ($c.Uuid.ToString() -ne '00002a19-0000-1000-8000-00805f9b34fb') { continue }
            $r = Fin (T $TypeGR ($c.ReadValueAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)))
            if ($r.Value -and $r.Value.Length -ge 1) {
              $level = [int]$FromBuffer.Invoke($null, @($r.Value)).ReadByte()
            }
          }
        }
      }
    } catch {} finally { if ($dev) { $dev.Dispose() } }
    if ($name) { $out += [ordered]@{ name = $name; address = $info.Id; battery = [int]$level; connected = [bool]$connected } }
  }
  if ($out.Count -gt 0) { $json = ConvertTo-Json -InputObject $out -Compress }
} catch {}
[Console]::Out.Write($json)
