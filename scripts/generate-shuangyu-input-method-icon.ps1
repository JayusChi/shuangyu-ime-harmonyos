param(
    [string]$SourcePath = $(Join-Path $PSScriptRoot '..\entry\src\main\resources\base\media\startIcon.png'),
    [string]$OutputPath = $(Join-Path $PSScriptRoot '..\entry\src\main\resources\base\media\shuangyu_input_method_raster.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$resolvedSource = [IO.Path]::GetFullPath($SourcePath)
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
    throw "App icon source not found: $resolvedSource"
}

if (-not ('ShuangyuInputMethodIconGenerator' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

public static class ShuangyuInputMethodIconGenerator
{
    private static int ClampByte(double value)
    {
        return (int)Math.Max(0, Math.Min(255, Math.Round(value)));
    }

    private static int FeatherAlpha(Color color)
    {
        int minimum = Math.Min(color.R, Math.Min(color.G, color.B));
        int maximum = Math.Max(color.R, Math.Max(color.G, color.B));
        int chroma = maximum - minimum;
        double brightness = Math.Max(0.0, Math.Min(1.0, (minimum - 125.0) / 105.0));
        double neutrality = Math.Max(0.0, Math.Min(1.0, (135.0 - chroma) / 95.0));
        return ClampByte(255.0 * Math.Pow(brightness * neutrality, 0.70));
    }

    public static void Generate(string sourcePath, string outputPath)
    {
        using (Bitmap source = new Bitmap(sourcePath))
        using (Bitmap output = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
        {
            for (int outputY = 0; outputY < output.Height; outputY++)
            {
                int sourceTop = outputY * source.Height / output.Height;
                int sourceBottom = Math.Max(sourceTop + 1, (outputY + 1) * source.Height / output.Height);
                for (int outputX = 0; outputX < output.Width; outputX++)
                {
                    int sourceLeft = outputX * source.Width / output.Width;
                    int sourceRight = Math.Max(sourceLeft + 1, (outputX + 1) * source.Width / output.Width);
                    int alphaTotal = 0;
                    int samples = 0;
                    for (int sourceY = sourceTop; sourceY < sourceBottom; sourceY++)
                    {
                        for (int sourceX = sourceLeft; sourceX < sourceRight; sourceX++)
                        {
                            alphaTotal += FeatherAlpha(source.GetPixel(sourceX, sourceY));
                            samples++;
                        }
                    }
                    int averagedAlpha = samples == 0 ? 0 : alphaTotal / samples;
                    int alpha = averagedAlpha < 18 ? 0 : ClampByte((averagedAlpha - 10) * 1.15);
                    output.SetPixel(outputX, outputY, Color.FromArgb(alpha, 35, 35, 35));
                }
            }
            output.Save(outputPath, ImageFormat.Png);
        }
    }
}
'@
}

$directory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
[ShuangyuInputMethodIconGenerator]::Generate($resolvedSource, $resolvedOutput)
Write-Host "Generated exact app-icon feather mask: $resolvedOutput"
