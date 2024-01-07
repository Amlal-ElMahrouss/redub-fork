module parsers.automatic;
public import buildapi;
static import parsers.json;

BuildRequirements parseProject(string projectWorkingDir, string subConfiguration="")
{
    import std.path;
    import package_searching.entry;
    string projectFile = findEntryProjectFile(projectWorkingDir);
    BuildRequirements req;
    switch(extension(projectFile))
    {
        case ".json":  req = parsers.json.parse(projectFile, subConfiguration); break;
        case null: break;
        default: throw new Error("Unsupported project type "~projectFile~" at dir "~projectWorkingDir);
    }
    return req;
}