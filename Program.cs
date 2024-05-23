﻿using System.Runtime.InteropServices;
using System.CommandLine;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using static Bullseye.Targets;
using static SimpleExec.Command;

//NOTE: Requires ClangSharpPInvokeGenerator to be installed as a global tool
var foo = new Option<string>(["--outputPath", "-o",], "output path folder for bindings/libs");

List<string> EmptyList = new List<string>();
flag traverse = new flag("traverse", EmptyList);
flag remap = new flag("remap", EmptyList);

var bindgenBase = new rsp("base", 
[
    new ("config",
    [
        "latest-codegen",
        "single-file",
        // "exclude-funcs-with-body",
        "generate-aggressive-inlining",
        "generate-file-scoped-namespaces",
        "log-exclusions",
        "log-potential-typedef-remappings",
        "log-visited-files",
        "generate-cpp-attributes"
    ]),
    new ("additional",[
        "-Wno-ignored-attributes",
        "-Wno-nullability-completeness",
        "-Wunused-function"
    ])
]);

var sokol_settings = new rsp("sokol_settings", rspInclude: bindgenBase, flags:
[
    new("include-directory", [
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include",
        "/Library/Developer/CommandLineTools/usr/lib/clang/13.0.0/include/",
        "./libs/sokol/src/sokol",
        "./libs/sokol/src/"
    ]),
    new("define-macro", [
        "SOKOL_DLL",
        "SOKOL_NO_ENTRY",
        "SOKOL_TRACE_HOOKS"
    ]),
    new("namespace", "Zinc.Internal.Sokol"),
    new("libraryPath", "sokol")
]);

var sokol = new lib("sokol", [
    new ("sokol_app", 
        "./libs/sokol/src/sokol/sokol_app.h",
        "sapp_",
        "App",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.App.cs",
        rspInclude:sokol_settings),
    new ("sokol_audio", 
        "./libs/sokol/src/sokol/sokol_audio.h",
        "saudio_",
        "Audio",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Audio.cs",
        rspInclude:sokol_settings),
    new ("sokol_color", 
        "./libs/sokol/bindgen/sokol_color_bindgen_helper.h",
        "sg_color_",
        "Color",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Color.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_color.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_fontstash", 
        "./libs/sokol/bindgen/sokol_fontstash_bindgen_helper.c",
        // "./libs/sokol/src/fontstash.h",
        "sfons_",
        "Fontstash",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Fontstash.cs",
        [
            traverse with { flagParams = [
                "./libs/sokol/fontstash.h",
                "./libs/sokol/src/sokol/util/sokol_fontstash.h",
            ]},
            remap with { flagParams = [
                "FONScontext*=@void*",
            ]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_debugtext", 
        "./libs/sokol/bindgen/sokol_debugtext_bindgen_helper.h",
        "sdtx_",
        "DebugText",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.DebugText.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_debugtext.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_gfx", 
        "./libs/sokol/src/sokol/sokol_gfx.h",
        "sg_",
        "Gfx",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Graphics.cs",
        rspInclude:sokol_settings),
    new ("sokol_gfx_imgui", 
        "./libs/sokol/bindgen/sokol_gfx_imgui_bindgen_helper.h",
        "sg_imgui_",
        "GfxDebugGUI",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Graphics.DebugGUI.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_gfx_imgui.h"]},
            remap with { flagParams = ["FILE*=@void*"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_glue", 
        "./libs/sokol/bindgen/sokol_glue_bindgen_helper.h",
        "sg_",
        "Glue",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Glue.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/sokol_glue.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_gl", 
        "./libs/sokol/bindgen/sokol_gl_bindgen_helper.h",
        "sgl_",
        "GL",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.GL.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_gl.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_gp", 
        "./libs/sokol/bindgen/sokol_gp_bindgen_helper.h",
        "sgp_",
        "GP",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.GP.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol_gp/sokol_gp.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_imgui", 
        "./libs/sokol/bindgen/sokol_imgui_bindgen_helper.h",
        "simgui_",
        "ImGUI",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.ImGUI.cs",
        [
            traverse with { flagParams = [
                "./libs/sokol/src/sokol/util/sokol_imgui.h",
                "./libs/cimgui/src/cimgui/cimgui.h"
            ]},
            remap with { flagParams = [
                "FILE*=@void*",
                "__sFILE*=@void*",
                "__arglist=@params string[] args"
            ]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_log", 
        "./libs/sokol/src/sokol/sokol_log.h",
        "",
        "Log",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Log.cs",
        rspInclude:sokol_settings),
    new ("sokol_time", 
        "./libs/sokol/src/sokol/sokol_time.h",
        "stm_",
        "Time",
        "../Zinc.Core/src/generated/lib/sokol/Sokol.Time.cs",
        rspInclude:sokol_settings),
]);

var stb_settings = new rsp("stb_settings", rspInclude: bindgenBase, flags:
[
    new("include-directory",
    [
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include",
        "/Library/Developer/CommandLineTools/usr/lib/clang/13.0.0/include/",
        "./libs/stb/src/stb"
    ]),
    new("namespace", "Zinc.Internal.STB"),
    new("libraryPath", "stb")
]);
var stb = new lib("stb", [
    new ("stb_image", 
        "./libs/stb/src/stb/stb_image.h",
        "",
        "STB",
        "../Zinc.Core/src/generated/lib/stb/STB.Image.cs",
        [
            new("define-macro","STBI_NO_STDIO"),
        ],
        rspInclude:stb_settings),
]);

var cute_settings = new rsp("cute_settings", rspInclude: bindgenBase, flags:
[
    new("include-directory", [
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include",
        "./libs/cute/src/cute_headers"
    ]),
    new("namespace", "Zinc.Internal.Cute"),
    new("libraryPath", "cute")
]);
var cute = new lib("cute", [
    new ("c2", 
        "./libs/cute/src/cute_headers/cute_c2.h",
        "",
        "C2",
        "../Zinc.Core/src/generated/lib/cute/Cute.C2.cs",
        [
            new("traverse","./libs/cute/src/cute_headers/cute_c2.h"),
        ],
        rspInclude:cute_settings),
]);
    

List<lib> buildLibs = [
    sokol,
    stb,
    cute
];

var projectDir = Directory.GetCurrentDirectory();
Console.WriteLine(projectDir);
string bindgenpath(string libName,string rspFileName) => Path.Combine(projectDir, $"libs/{libName}/bindgen/{rspFileName}.rsp");
string buildpath(string libName) => Path.Combine(projectDir, $"libs/{libName}/build/build.zig");
Console.WriteLine(buildpath("sokol"));

var envFilePath = Path.Combine(projectDir, "obj", "Debug", "net8.0", "properties.env");
if (File.Exists(envFilePath))
{
    var envFile = File.ReadAllLines(envFilePath);
    foreach (var line in envFile)
    {
        var parts = line.Split("=",2);
        if (parts.Length == 2)
        {
            Environment.SetEnvironmentVariable(parts[0], parts[1]);
        }
    }
}
var ZigToolsetPath = Environment.GetEnvironmentVariable("ZigToolsetPath");
var ZigExePath = Environment.GetEnvironmentVariable("ZigExePath");
var ZigLibPath = Environment.GetEnvironmentVariable("ZigLibPath");
var ZigDocPath = Environment.GetEnvironmentVariable("ZigDocPath");

// args.ToList().ForEach(x => Console.WriteLine(x));
//check if args has index 1
if (args.Length > 1)
{
    Console.WriteLine(args[1]);
}



//log zig vars
Console.WriteLine($"ZigToolsetPath: {ZigToolsetPath}");
Console.WriteLine($"ZigExePath: {ZigExePath}");
Console.WriteLine($"ZigLibPath: {ZigLibPath}");
Console.WriteLine($"ZigDocPath: {ZigDocPath}");

foreach (var l in buildLibs)
{
    //sokol - build the lib and bindgen everything
    //sokol:build - builds the lib
    //sokol:bindgen - binds all the libs
    //sokol:bindgen:libname - binds the specified lib
    Target($"{l.libName}:build", () => Run(ZigExePath,$"build --build-file {buildpath(l.libName)}"));
    Target($"{l.libName}:build:wasm", () => Run(ZigExePath,$"build -Dtarget=wasm32-emscripten --build-file {buildpath(l.libName)}"));

    var reqRsps = new List<string>();
    foreach (var rsp in l.bindgen)
    {
        if (rsp.name == $"{l.libName}_settings")
        {
            //dont make a target for settings
            var b = rsp.Write();
            File.WriteAllText(b.name,b.contents);
            continue;
        }
        reqRsps.Add($"{l.libName}:bindgen:{rsp.name}");
        Target($"{l.libName}:bindgen:{rsp.name}:write_rsp", () =>
        {
            var b = rsp.Write();
            File.WriteAllText(b.name,b.contents);
        });
        
        Target($"{l.libName}:bindgen:{rsp.name}:emit_rsp", () =>
        {
            var b = rsp.Write();
            Console.Write(b);
        });
        
        Target($"{l.libName}:bindgen:{rsp.name}", DependsOn($"{l.libName}:bindgen:{rsp.name}:write_rsp"), () =>
        {
            try
            {
                Run("ClangSharpPInvokeGenerator", $"@{rsp.name}.rsp",handleExitCode: (code) =>
                {
                    if (code == 109)
                    {
                        Console.WriteLine("ERR: broken pipe (output too large?)");
                        return true;
                    }
                    return false;
                });
            }
            catch (Exception e)
            {
                Console.WriteLine("EXECPETION: " + e);
            }
            File.Delete($"{rsp.name}.rsp"); //delete the rsp after running
        });
    }
    
    Target($"{l.libName}:bindgen", DependsOn(reqRsps.ToArray()));
    Target($"{l.libName}", DependsOn($"{l.libName}:build", $"{l.libName}:bindgen"));
}

Target("echo", () => Console.WriteLine("echo"));
Target("default", DependsOn(buildLibs.Select(x => x.libName).ToArray()));

await RunTargetsAndExitAsync(args);


/*
 * DATA BELOW HERE--------------------------------------------------------------------------------
 *
 *
 *
 *
 *
 *
 *
 *
 *
 * 
 */

public record rsp
{
    public rsp(string name, List<flag> flags, rsp? rspInclude = null)
    {
        this.name = name;
        this.flags = flags;
        this.rspInclude = rspInclude;
    }

    public rsp(string name, string file, string prefixStrip, string methodClassName, string outputFile,
        List<flag>? flags = null, rsp? rspInclude = null)
    {
        this.name = name;
        this.rspInclude = rspInclude;
        var f = new List<flag>
        {
            new("file",file),
            new("methodClassName",methodClassName),
            new("output",
                outputFile
            )
        };
        if (prefixStrip != "")
        {
            f.Add(new("prefixStrip", prefixStrip));
        }
        if (flags != null)
        {
            f = new List<flag>(f.Union(flags));
        }

        this.flags = f;

    }

    public (string name,string contents) Write()
    {
        var sb = new StringBuilder();
        if (rspInclude != null)
        {
            var w = rspInclude.Write();
            sb.AppendLine(w.contents);
        }

        foreach (var flag in flags)
        {
            sb.AppendLine($"--{flag.flagName}");
            foreach (var p in flag.flagParams)
            {
                sb.AppendLine($"{p}");
            }
            
        }

        return ($"{name}.rsp", sb.ToString());
    }

    public string name { get; init; }
    public List<flag> flags { get; init; }
    public rsp? rspInclude { get; init; }
}
public record flag
{
    public string flagName { get; init; }
    public List<string> flagParams { get; init; }
    public flag(string flagName, List<string> flagParams)
    {
        this.flagName = flagName;
        this.flagParams = flagParams;
    }
    public flag(string flagName, string flagParam)
    {
        this.flagName = flagName;
        this.flagParams = new List<string>{flagParam};
    }
}

public record lib(string libName, List<rsp> bindgen);