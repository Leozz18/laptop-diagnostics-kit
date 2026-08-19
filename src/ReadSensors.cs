using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using LibreHardwareMonitor.Hardware;

internal sealed class UpdateVisitor : IVisitor
{
    public void VisitComputer(IComputer computer)
    {
        computer.Traverse(this);
    }

    public void VisitHardware(IHardware hardware)
    {
        hardware.Update();
        foreach (IHardware sub in hardware.SubHardware)
        {
            sub.Accept(this);
        }
    }

    public void VisitSensor(ISensor sensor)
    {
    }

    public void VisitParameter(IParameter parameter)
    {
    }
}

internal static class Program
{
    private static int Main(string[] args)
    {
        string outPath = args.Length > 0 ? args[0] : "sensors.json";
        try
        {
            var computer = new Computer
            {
                IsCpuEnabled = true,
                IsGpuEnabled = true,
                IsMemoryEnabled = true,
                IsMotherboardEnabled = true,
                IsControllerEnabled = true,
                IsStorageEnabled = true,
                IsNetworkEnabled = false,
                IsBatteryEnabled = true
            };
            computer.Open();
            var visitor = new UpdateVisitor();
            computer.Accept(visitor);
            Thread.Sleep(900);
            computer.Accept(visitor);

            var sb = new StringBuilder(8192);
            sb.Append('[');
            bool first = true;
            foreach (IHardware hw in computer.Hardware)
            {
                AppendHardware(sb, hw, ref first);
            }
            sb.Append(']');
            File.WriteAllText(outPath, sb.ToString(), new UTF8Encoding(false));
            computer.Close();
            return 0;
        }
        catch (Exception ex)
        {
            File.WriteAllText(outPath, "{\"error\":\"" + Escape(ex.Message) + "\"}", new UTF8Encoding(false));
            return 1;
        }
    }

    private static void AppendHardware(StringBuilder sb, IHardware hardware, ref bool first)
    {
        foreach (ISensor sensor in hardware.Sensors)
        {
            if (!sensor.Value.HasValue)
            {
                continue;
            }
            if (!first)
            {
                sb.Append(',');
            }
            first = false;
            string unit = UnitFor(sensor.SensorType);
            sb.Append("{\"hardware\":\"").Append(Escape(hardware.Name)).Append('"');
            sb.Append(",\"hardwareType\":\"").Append(Escape(hardware.HardwareType.ToString())).Append('"');
            sb.Append(",\"sensor\":\"").Append(Escape(sensor.Name)).Append('"');
            sb.Append(",\"sensorType\":\"").Append(Escape(sensor.SensorType.ToString())).Append('"');
            sb.Append(",\"reading\":").Append(sensor.Value.Value.ToString("G", CultureInfo.InvariantCulture));
            if (sensor.Min.HasValue)
            {
                sb.Append(",\"min\":").Append(sensor.Min.Value.ToString("G", CultureInfo.InvariantCulture));
            }
            if (sensor.Max.HasValue)
            {
                sb.Append(",\"max\":").Append(sensor.Max.Value.ToString("G", CultureInfo.InvariantCulture));
            }
            sb.Append(",\"unit\":\"").Append(Escape(unit)).Append("\"}");
        }
        foreach (IHardware sub in hardware.SubHardware)
        {
            AppendHardware(sb, sub, ref first);
        }
    }

    private static string UnitFor(SensorType type)
    {
        switch (type)
        {
            case SensorType.Temperature: return "C";
            case SensorType.Fan: return "RPM";
            case SensorType.Load: return "%";
            case SensorType.Clock: return "MHz";
            case SensorType.Power: return "W";
            case SensorType.Voltage: return "V";
            case SensorType.Data: return "GB";
            case SensorType.SmallData: return "MB";
            case SensorType.Throughput: return "B/s";
            case SensorType.Control: return "%";
            case SensorType.Level: return "%";
            default: return "";
        }
    }

    private static string Escape(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "";
        }
        var sb = new StringBuilder(value.Length);
        foreach (char c in value)
        {
            switch (c)
            {
                case '\\': sb.Append("\\\\"); break;
                case '"': sb.Append("\\\""); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 32)
                    {
                        sb.Append("\\u").Append(((int)c).ToString("x4"));
                    }
                    else
                    {
                        sb.Append(c);
                    }
                    break;
            }
        }
        return sb.ToString();
    }
}
