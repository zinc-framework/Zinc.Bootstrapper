using System.Runtime.InteropServices;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using static Bullseye.Targets;
using static SimpleExec.Command;

//NOTE: Requires ClangSharpPInvokeGenerator to be installed as a global tool

List<string> EmptyList = new List<string>();
flag traverse = new flag("traverse", EmptyList);
flag remap = new flag("remap", EmptyList);

var outputPath = File.ReadAllText("config.txt");
Console.WriteLine("passing output path as: " + outputPath);

//platform include paths for bindgen
//win
//https://developercommunity.visualstudio.com/t/msvc-2022-preview-2-143030401-missing-stddefh-and/1477719
//https://www.reddit.com/r/VisualStudio/comments/sd8w5f/some_c_headers_dont_come_with_visual_studio_tools/
List<string> windows = ["C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/ucrt"];

//macos
List<string> macos = [
    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include", 
    "/Library/Developer/CommandLineTools/usr/lib/clang/13.0.0/include/"
];

//linux?
List<string> linux = [];

//assing current platform to var
var platformDefines = RuntimeInformation.RuntimeIdentifier switch
{
    "win-x64" => windows,
    "osx-arm64" => macos,
    "osx-x64" => macos,
    "linux-x64" => linux,
    _ => EmptyList
};

var bindgenBase = new rsp("base", 
[
    new ("config",
    [
        "latest-codegen",
        "single-file",
        "exclude-funcs-with-body",
        "generate-aggressive-inlining",
        // "generate-file-scoped-namespaces",
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
        ..platformDefines,
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
        $"{outputPath}/bindings/sokol/Sokol.App.cs",
        rspInclude:sokol_settings),
    new ("sokol_audio", 
        "./libs/sokol/src/sokol/sokol_audio.h",
        "saudio_",
        "Audio",
        $"{outputPath}/bindings/sokol/Sokol.Audio.cs",
        rspInclude:sokol_settings),
    new ("sokol_color", 
        "./libs/sokol/bindgen/sokol_color_bindgen_helper.h",
        "sg_color_",
        "Color",
        $"{outputPath}/bindings/sokol/Sokol.Color.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_color.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_fontstash", 
        "./libs/sokol/bindgen/sokol_fontstash_bindgen_helper.h",
        "sfons_",
        "Fontstash",
        $"{outputPath}/bindings/sokol/Sokol.Fontstash.cs",
        [
            traverse with { flagParams = [
                "./libs/sokol/src/fontstash.h",
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
        $"{outputPath}/bindings/sokol/Sokol.DebugText.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_debugtext.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_gfx", 
        "./libs/sokol/src/sokol/sokol_gfx.h",
        "sg_",
        "Gfx",
        $"{outputPath}/bindings/sokol/Sokol.Graphics.cs",
        rspInclude:sokol_settings),
    new ("sokol_gfx_imgui", 
        "./libs/sokol/bindgen/sokol_gfx_imgui_bindgen_helper.h",
        "sg_imgui_",
        "GfxDebugGUI",
        $"{outputPath}/bindings/sokol/Sokol.Graphics.DebugGUI.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_gfx_imgui.h"]},
            remap with { flagParams = ["FILE*=@void*"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_glue", 
        "./libs/sokol/bindgen/sokol_glue_bindgen_helper.h",
        "sg_",
        "Glue",
        $"{outputPath}/bindings/sokol/Sokol.Glue.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/sokol_glue.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_gl", 
        "./libs/sokol/bindgen/sokol_gl_bindgen_helper.h",
        "sgl_",
        "GL",
        $"{outputPath}/bindings/sokol/Sokol.GL.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol/util/sokol_gl.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_gp", 
        "./libs/sokol/bindgen/sokol_gp_bindgen_helper.h",
        "sgp_",
        "GP",
        $"{outputPath}/bindings/sokol/Sokol.GP.cs",
        [
            traverse with { flagParams = ["./libs/sokol/src/sokol_gp/sokol_gp.h"]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_imgui", 
        "./libs/sokol/bindgen/sokol_imgui_bindgen_helper.h",
        "simgui_",
        "ImGUI",
        $"{outputPath}/bindings/sokol/Sokol.ImGUI.cs",
        [
            traverse with { flagParams = [
                "./libs/sokol/src/sokol/util/sokol_imgui.h",
                "./libs/cimgui/src/cimgui/cimgui.h"
            ]},
            remap with { flagParams = [
                "FILE*=@void*",
                "__sFILE*=@void*",
                // "__arglist=@params string[] args" //NOTE: this broke in ClangSharpPInvokeGenerator 18.1.0 and issue filed - need to manually remap the types
            ]}
        ],
        rspInclude:sokol_settings),
    new ("sokol_log", 
        "./libs/sokol/src/sokol/sokol_log.h",
        "",
        "Log",
        $"{outputPath}/bindings/sokol/Sokol.Log.cs",
        rspInclude:sokol_settings),
    new ("sokol_time", 
        "./libs/sokol/src/sokol/sokol_time.h",
        "stm_",
        "Time",
        $"{outputPath}/bindings/sokol/Sokol.Time.cs",
        rspInclude:sokol_settings),
]);

var stb_settings = new rsp("stb_settings", rspInclude: bindgenBase, flags:
[
    new("include-directory",
    [
        ..platformDefines,
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
        $"{outputPath}/bindings/stb/STB.Image.cs",
        [
            new("define-macro","STBI_NO_STDIO"),
        ],
        rspInclude:stb_settings),
]);

var cute_settings = new rsp("cute_settings", rspInclude: bindgenBase, flags:
[
    new("include-directory", [
        ..platformDefines,
        "./libs/cute/src/cute_headers"
    ]),
    new("namespace", "Zinc.Internal.Cute"),
    new("libraryPath", "cute")
]);
var cute = new lib("cute", [
    new ("c2", 
        "./libs/cute/bindgen/c2_bindgen_helper.h",
        "",
        "C2",
        $"{outputPath}/bindings/cute/Cute.C2.cs",
        [
            traverse with { flagParams = ["./libs/cute/src/cute_headers/cute_c2.h"]}
        ],
        rspInclude:cute_settings),
]);

var box2d_settings = new rsp("box2d_settings", rspInclude: bindgenBase, flags:
[
    new("include-directory", [
        ..platformDefines,
        "./libs/box2d/src/box2d/include/box2d"
    ]),
    new("namespace", "Zinc.Internal.Box2D"),
    new("libraryPath", "box2d")
]);
var box2d = new lib("box2d", [
    new ("box2d", 
        "./libs/box2d/bindgen/box2d_bindgen_helper.h",
        "",
        "Box2D",
        $"{outputPath}/bindings/box2d/Box2D.cs",
        [
            traverse with { flagParams = [
                "./libs/box2d/src/box2d/include/box2d/box2d.h",
                "./libs/box2d/src/box2d/include/box2d/base.h",
                "./libs/box2d/src/box2d/include/box2d/types.h",
                "./libs/box2d/src/box2d/include/box2d/math_functions.h",
                "./libs/box2d/src/box2d/include/box2d/id.h",
                "./libs/box2d/src/box2d/include/box2d/collision.h",
            ]}
        ],
        rspInclude:box2d_settings),
]);
    

List<lib> buildLibs = [
    sokol,
    stb,
    cute,
    box2d
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
    Target($"{l.libName}:build", () => Run(ZigExePath,$"build -Dfile-path={outputPath} --build-file {buildpath(l.libName)}"));
    Target($"{l.libName}:build:wasm", () => Run(ZigExePath,$"build -Dfile-path={outputPath} -Dtarget=wasm32-emscripten --build-file {buildpath(l.libName)}"));

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