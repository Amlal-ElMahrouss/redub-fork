module cli.dub;

/// The URL to the official package registry and it's default fallback registries.
static immutable string[] defaultRegistryURLs = [
	"https://code.dlang.org/",
	"https://codemirror.dlang.org/",
	"https://dub.bytecraft.nl/",
	"https://code-mirror.dlang.io/",
];



enum SkipRegistry
{
    none,
    standard,
    configured,
    all
}

enum Color
{
    auto_ = "auto",
    always = "always",
    never = "never"
}

struct DubCommonArguments
{
    @("Path to operate in instead of the current working dir")
    string root;

    @("Loads a custom recipe path instead of dub.json/dub.sdl")
    string recipe;

    @(
        "Search the given registry URL first when resolving dependencies. Can be specified multiple times. Available registry types:" ~
        "  DUB: URL to DUB registry (default)" ~
        "  Maven: URL to Maven repository + group id containing dub packages as artifacts. E.g. mvn+http://localhost:8040/maven/libs-release/dubpackages"
    )
    string registry;

    @("Sets a mode for skipping the search on certain package registry types:" ~
        "  none: Search all configured or default registries (default)" ~
        "  standard: Don't search the main registry (e.g. "~defaultRegistryURLs[0]~")" ~
        "  configured: Skip all default and user configured registries"~
        "  all: Only search registries specified with --registry"
    )
    @("skip-registry")
    SkipRegistry skipRegistry;

    @("Do not perform any action, just print what would be done")
    bool annotate;

    @("Read only packages contained in the current directory")
    bool bare;

    @("Print diagnostic output")
    @("v|verbose")
    bool verbose;
    @("Print debug output")
    bool vverbose;

    @("Only print warnings and errors")
    @("q|quiet")
    bool quiet;
    @("Only print errors")
    bool verror;
    @("Print no messages")
    bool vquiet;

    @("Configure colored output. Accepted values:"~
        "       auto: Colored output on console/terminal,"~
        "             unless NO_COLOR is set and non-empty (default)"~
        "     always: Force colors enabled"~
        "      never: Force colors disabled"
    )
    Color color;

    @("Puts any fetched packages in the specified location [local|system|user].")
    string cache;

    string getRoot(string workingDir) const
    {
        import std.path;
        if(isAbsolute(root)) return root;
        return buildNormalizedPath(workingDir, root);
    }

    string getRecipe(string workingDir) const
    {
        import std.path;
        if(isAbsolute(recipe))  return recipe;
        return buildNormalizedPath(getRoot(workingDir), recipe);
    }
}

struct DubArguments
{
    DubCommonArguments cArgs;
    DubBuildArguments build;
    
    @("Specifies the type of build to perform. Note that setting the DFLAGS environment variable will override the build type with custom flags.",
    "Possible names:")
    @("b|build")
    string buildType;

    @("Builds the specified configuration. Configurations can be defined in dub.json")
    @("c|config")
    string config;

    @(
        "Specifies the compiler binary to use (can be a path)" ~
        "Arbitrary pre- and suffixes to the identifiers below are recognized (e.g. ldc2 or dmd-2.063) and matched to the proper compiler type:" ~
        "dmd, gdc, ldc, gdmd, ldmd"
    )
    string compiler = "dmd";

    @("Force a different architecture (e.g. x86 or x86_64)")
    @("a|arch")
    string arch;

    @("Define the specified `debug` version identifier when building - can be used multiple times")
    @("d|debug")
    string[] debugVersions;
    
    @(
        "Define the specified `version` identifier when building - can be used multiple times."~
        "Use sparingly, with great power comes great responsibility! For commonly used or combined versions "~
        "and versions that dependees should be able to use, create configurations in your package."
    ) @("d-version")
    string[] versions;

    @("Do not resolve missing dependencies before building")
    bool nodeps;

    @("Specifies the way the compiler and linker are invoked. Valid values:" ~
    "  separate (default), allAtOnce, singleFile") 
    @("build-mode")
    string buildMode;

    @("Treats the package name as a filename. The file must contain a package recipe comment.")
    bool single;

    @("Deprecated option that does nothing.")
    @("force-remove")
    bool forceRemove;

    @("[Experimental] Filter version identifiers and debug version identifiers to improve build cache efficiency.")
    string[] filterVersions;
}


struct DubBuildArguments
{
    @("Builds the project in the temp folder if possible.")
    @("temp-build")
    bool tempBuild;

    @("Use rdmd instead of directly invoking the compiler")
    bool rdmd;


    @("Forces a recompilation even if the target is up to date")
    @("f|force")
    bool force;

    @(`Automatic yes to prompts. Assume "yes" as answer to all interactive prompts.`)
    @("y/yes")
    bool yes;

    @("Don't enter interactive mode.")
    @("n|non-interactive")
    bool nonInteractive;

    @("Build all dependencies, even when main target is a static library.")
    bool deep;
}


import std.getopt;

GetoptResult betterGetopt(T)(ref string[] args, out T opts) if(is(T == struct))
{
    alias _ = opts;
    return mixin("getopt(args, " ~ genGetoptCall!(T)("_") ~ ")");
}

private string genGetoptCall(T)(string memberName  )
{
    import std.traits:isFunction;
    string ret;
    static foreach(mem; __traits(allMembers, T))
    {{
        alias member = __traits(getMember, T, mem);
        static if(!isFunction!(typeof(member)))
        {
            static if(is(typeof(member) == struct))
            {
                ret~= genGetoptCall!(typeof(member))(memberName~"."~mem);
            }
            else
            {
                alias att = __traits(getAttributes, member);
                static if(att.length == 2) 
                    ret~= att[1].stringof ~ ", "~att[0].stringof;
                else
                    ret~= mem.stringof~", "~att[0].stringof;
                ret~=", &"~memberName~"."~mem~", ";
            }
        }
    }}
    return ret;
}