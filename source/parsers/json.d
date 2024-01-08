module parsers.json;
import std.system;
import buildapi;
import std.json;
import std.file;
import etc.c.zlib;

BuildRequirements parse(string filePath, string subConfiguration = "")
{
    import std.path;
    ParseConfig c = ParseConfig(true, dirName(filePath), subConfiguration);
    return parse(parseJSON(std.file.readText(filePath)), c);
}

/** 
 * Params:
 *   json = A dub.json equivalent
 * Returns: 
 */
BuildRequirements parse(JSONValue json, ParseConfig cfg)
{
    import std.exception;
    ///Setup base of configuration before finding anything
    BuildRequirements buildRequirements = getDefaultBuildRequirement(cfg);
    immutable static  handler = [
        "name": (ref BuildRequirements req, JSONValue v, ParseConfig c){if(c.firstRun) req.cfg.name = v.str;},
        "targetType": (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.targetType = targetFrom(v.str);},
        "targetPath": (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.outputDirectory = v.str;},
        "importPaths": (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.importDirectories = v.strArr;},
        "libPaths":  (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.libraryPaths = v.strArr;},
        "libs":  (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.libraries = v.strArr;},
        "versions":  (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.versions = v.strArr;},
        "lflags":  (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.linkFlags = v.strArr;},
        "dflags":  (ref BuildRequirements req, JSONValue v, ParseConfig c){req.cfg.dFlags = v.strArr;},
        "configurations": (ref BuildRequirements req, JSONValue v, ParseConfig c)
        {
            if(c.firstRun)
            {
                enforce(v.type == JSONType.array, "'configurations' must be an array.");
                enforce(v.array.length, "'configurations' must have at least one member.");
                c.firstRun = false;
                JSONValue configurationToUse = v.array[0];
                foreach(JSONValue projectConfiguration; v.array)
                {
                    JSONValue* name = "name" in projectConfiguration;
                    enforce(name, "'configurations' must have a 'name' on each");
                    if(name.str == c.subConfiguration)
                    {
                        configurationToUse = projectConfiguration;
                        break;
                    }
                }
                req.cfg = req.cfg.merge(parse(configurationToUse, c).cfg);
                req.targetConfiguration = configurationToUse["name"].str;
            }
        },
        "dependencies": (ref BuildRequirements req, JSONValue v, ParseConfig c)
        {
            import std.path;
            import std.exception;
            import package_searching.dub;
            foreach(string depName, JSONValue value; v.object)
            {
                Dependency newDep = Dependency(depName);
                if(value.type == JSONType.object) ///Uses path style
                {
                    const(JSONValue)* depPath = "path" in value;
                    const(JSONValue)* depVer = "version" in value;
                    enforce(depPath || depVer, "Dependency named "~ depName ~ " must contain at least a \"path\" or \"version\" property.");
                    if(depPath)
                        newDep.path = depPath.str;
                    if(depVer)
                    {
                        if(!depPath) newDep.path = package_searching.dub.getPackagePath(depName, depVer.str, req.cfg.name);
                        newDep.version_ = depVer.str;
                    }
                }
                else if(value.type == JSONType.string) ///Version style
                {
                    newDep.version_ = value.str;
                    newDep.path = package_searching.dub.getPackagePath(depName, value.str);
                }
                if(newDep.path.length && !isAbsolute(newDep.path)) newDep.path = buildNormalizedPath(c.workingDir, newDep.path);
                import std.algorithm.searching:countUntil;
                ptrdiff_t depIndex = countUntil!((a) => a.name == newDep.name)(req.dependencies);
                if(depIndex == -1)
                    req.dependencies~= newDep;
                else
                {
                    newDep.subConfiguration = req.dependencies[depIndex].subConfiguration;
                    req.dependencies[depIndex] = newDep;
                }
            }
        },
        "subConfigurations": (ref BuildRequirements req, JSONValue v, ParseConfig c)
        {
            enforce(v.type == JSONType.object, "Subconfigurations must be an object conversible to string[string]");

            if(req.dependencies.length == 0)
            {
                foreach(string key, JSONValue value; v)
                    req.dependencies~= Dependency(key, null, null, value.str);
            }
            else
            {
                foreach(ref Dependency dep; req.dependencies)
                {
                    JSONValue* subCfg = dep.name in v;
                    if(subCfg)
                        dep.subConfiguration = subCfg.str;
                }
            }
        }
    ];

    string[] unusedKeys;
    foreach(string key, JSONValue v; json)
    {
        bool mustExecuteHandler = true;
        auto fn = key in handler;
        if(!fn)
        {
            CommandWithFilter filtered = CommandWithFilter.fromKey(key);
            fn = filtered.command in handler;
            //TODO: Add mathesCompiler
            mustExecuteHandler = filtered.matchesOS(os);
        }
        if(fn && mustExecuteHandler)
            (*fn)(buildRequirements, v, cfg);
        else
            unusedKeys~= key;
    }

    ///Fix dependencies name to change from `:` to `_`
    foreach(ref Dependency dep; buildRequirements.dependencies)
    {
        import std.string:replace;
        dep.name = dep.name.replace(":", "_");
    }
    // if(cfg.firstRun) writeln("WARNING: Unused Keys -> ", unusedKeys);

    return buildRequirements;
}

private string[] strArr(JSONValue target)
{
    JSONValue[] arr = target.array;
    string[] ret = new string[](arr.length);
    foreach(i, JSONValue v; arr) 
        ret[i] = v.str;
    return ret;
}

private string[] strArr(JSONValue target, string prop)
{
    if(prop in target)
        return strArr(target[prop]);
    return [];
}

private bool isOS(string osRep)
{
    switch(osRep)
    {
        case "posix", "linux", "osx", "windows": return true;
        default: return false;
    }
}
private bool matchesOS(string osRep, OS os)
{
    final switch(osRep) with(OS)
    {
        case "posix": return os == solaris || 
                             os == dragonFlyBSD || 
                             os == freeBSD || 
                             os ==  netBSD ||
                             os == openBSD || 
                             os == otherPosix || 
                             "linux".matchesOS(os) || 
                             "osx".matchesOS(os);
        case "linux": return os == linux || os == android;
        case "osx": return os == osx || os == iOS || os == tvOS || os == watchOS;
        case "windows": return os == win32 || os == win64;
    }
}

struct CommandWithFilter
{
    string command;
    string compiler;
    string targetOS;

    bool matchesOS(OS os){return targetOS && parsers.json.matchesOS(targetOS, os);}

    /** 
     * Splits command-compiler-os into a struct.
     * Input examples:
     * - dflags-osx
     * - dflags-ldc-osx
     * - dependencies-windows
     * Params:
     *   key = Any key matching input style
     * Returns: 
     */
    static CommandWithFilter fromKey(string key)
    {
        import std.string;
        CommandWithFilter ret;

        string[] keys = key.split("-"); 
        if(keys.length == 1)
            return ret;
        ret.command = keys[0];
        ret.compiler = keys[1];

        if(keys.length == 3) ret.targetOS = keys[2];
        if(isOS(ret.compiler)) swap(ret.compiler, ret.targetOS);
        return ret;
    }
}

private void swap(T)(ref T a, ref T b)
{
    T temp = b;
    b = a;
    a = temp;
}

/** 
* Every parse step can't return a parse dependency.
* If they are null, that means they they won't be deferred. If they return something, that means
* they will need to wait for this dependency to be completed. 
*   (They will only be checked after complete parse)
*/
private alias ParseDependency = string;


struct ParseConfig
{
    bool firstRun;
    string workingDir;
    string subConfiguration;
    bool hasCheckedSubdependencies;
}


BuildRequirements getDefaultBuildRequirement(ParseConfig cfg)
{
    BuildRequirements req = BuildRequirements.defaultInit;
    req.version_ = "~master";
    req.targetConfiguration = cfg.subConfiguration;
    req.cfg.workingDir = cfg.workingDir;
    return req;
}