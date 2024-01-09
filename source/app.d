import std.algorithm:countUntil;
import std.conv:to;
import std.array;
import std.path;
import std.file;
import std.process;
import std.stdio;

import buildapi;
import parsers.automatic;
import tree_generators.dub;



string formatError(string err)
{
    import std.algorithm.searching:countUntil;
    if(err.countUntil("which cannot be read") != -1)
    {
        ptrdiff_t moduleNameStart = err.countUntil("`") + 1;
        ptrdiff_t moduleNameEnd = err[moduleNameStart..$].countUntil("`") + moduleNameStart;
        string moduleName = err[moduleNameStart..moduleNameEnd];

        return err~"\nMaybe you forgot to add the module '"~moduleName~"' source root to import paths?
        Dubv2 Failed!";
    }
    return err~"\nDubv2 Failed!";
}
/**
* DubV2 work with input -> output on each step. It must be almost stateless.
* ** CLI will be optionally implemented later. 
* ** Cache will be optionally implemented later
* 
* FindProject -> ParseProject -> MergeWithEnvironment -> ConvertToBuildFlags ->
* Build
*/
int main(string[] args)
{
    import building.cache;
    import package_searching.entry;
    import package_searching.dub;
    static import parsers.environment;
    static import command_generators.dmd;

    //TEST -> Take from args[1] the workingDir.
    string workingDir = std.file.getcwd();
    if(args.length > 1)
    {
        if(!isAbsolute(args[1])) 
            workingDir = buildNormalizedPath(workingDir, args[1]);
        else workingDir = args[1];
    }

    if(isUpToDate(workingDir))
    {

    }
    else
    {
        import std.datetime.stopwatch;
        import std.system;
        import building.compile;
        StopWatch st = StopWatch(AutoStart.yes);
        BuildRequirements req = parseProject(workingDir);
        import std.stdio;
        req.cfg = req.cfg.merge(parsers.environment.parse());



        ProjectNode tree = getProjectTree(req);
        ProjectNode[][] expandedDependencyMatrix = fromTree(tree);
        printMatrixTree = expandedDependencyMatrix;
        if(!buildProject(expandedDependencyMatrix, "dmd"))
            throw new Error("Build failure");

        writeln("Built project in ", (st.peek.total!"msecs"), " ms.") ;
    }

    return 0;
}