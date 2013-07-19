package commands;

import legacy.Warnings;
import legacy.FindAndReplace;
import legacy.FindAndReplace.FindAndReplaceObject;
import sys.io.FileOutput;
import massive.sys.cmd.Command;
import sys.io.File;
import sys.FileSystem;
import utils.CommandUtils;

class ConvertCommand extends Command
{
    private var autoContinue:Bool = false;

    override public function execute():Void
    {
        if (console.args.length > 2)
        {
            this.error("You have not provided the correct arguments.");
        }

        var convertPath = "";

        if (console.args[1] != null)
            convertPath = console.args[1];

        if(console.getOption("-y") != null)
            autoContinue = true;

        var makeBackup = true;
        if(console.getOption("-nb") != null)
            makeBackup = false;


        convertProject(convertPath, makeBackup);
    }

    /**
	 * Convert an old HaxeFlixel project
	 */

    private function convertProject(ConvertPath:String = "", MakeBackup:Bool = true):Void
    {
        if (ConvertPath == "")
        {
            ConvertPath = Sys.getCwd();
        }
        else
        {
            if (!StringTools.startsWith(ConvertPath, "/"))
            {
                ConvertPath = Sys.getCwd() + CommandUtils.stripPath(ConvertPath);
            }
        }

        if(!autoContinue)
        {
            var continueConvert = CommandUtils.askYN("Do you want to convert " + ConvertPath);

            if (continueConvert == Answer.Yes)
            {
                Sys.println("");
                convert(ConvertPath, MakeBackup);
            }
            else
            {
                Sys.println("Cancelling Convert.");
                exit();
            }
        }
        else
        {
            Sys.println("");
            convert(ConvertPath, MakeBackup);
        }
    }

    private function convert(ConvertPath:String, MakeBackup:Bool):Void
    {
        if (FileSystem.exists(ConvertPath))
        {
            Sys.println(" Converting :" + ConvertPath);
            Sys.println("");

            if (MakeBackup)
            {
                var backupFolder = ConvertPath + "_backup";

                if (!FileSystem.exists(backupFolder))
                {
                    var backup = CommandUtils.copyRecursivley(ConvertPath, backupFolder);
                    if (backup)
                    {
                        Sys.println("Backup copied to " + backupFolder);
                    }
                    else
                    {
                        error("A problem occured when making a backup at " + backupFolder);
                    }
                }
                else
                {
                    if(!autoContinue)
                    {
                        var overwrite = CommandUtils.askYN("There is already a backup at " + backupFolder + ", do you want to overwrite it?");

                        if (overwrite == Answer.Yes)
                        {
                            createBackup( ConvertPath, backupFolder);
                        }
                        else
                        {
                            Sys.println("Cancelled");
                            exit();
                        }
                    }
                    else
                    {
                        createBackup( ConvertPath, backupFolder);
                    }
                }
            }

            if (FileSystem.exists(ConvertPath))
            {
                var warnings:Array<WarningResult> = convertProjectFolder(ConvertPath, true);

                if (warnings.length > 0)
                {
                    var logFileName = "convert.log";
                    var filePath = ConvertPath + "/" + logFileName;

                    writeWarningsToFile(filePath, warnings, ConvertPath);

                    Sys.println("Log written to " + filePath);
                }
            }
            else
            {
                Sys.println(" ");
                Sys.println(" Warning there was a problem with the path to convert.");
                Sys.println(" " + ConvertPath);
                Sys.println(" ");
            }
        }
        else
        {
            Sys.println("Warning cannot find " + ConvertPath);
            Sys.println("");
        }
    }

    private inline function displayWarnings(warnings:Array<WarningResult>):Void
    {
        Sys.println("");
        Sys.println(warnings.length + " Warnings");

        for (warning in warnings)
        {
            Sys.println("");
            Sys.println(" File Path    :" + warning.filePath);
            Sys.println(" Line Number  :" + warning.lineNumber);
            Sys.println(" Issue        :" + warning.oldCode);
            Sys.println(" Solution     :" + warning.newCode);
        }

        Sys.println("");
        Sys.println(" Warning although this command updates a lot, its not perfect.");
        //todo wiki page
        Sys.println(" Please visit haxeflixel.com/wiki/convert for further documentation on converting old code.");
        Sys.println("");
    }

    private inline function createBackup(ConvertPath:String, BackupFolder:String):Void
    {
        var backup = CommandUtils.copyRecursivley(ConvertPath, BackupFolder);
        if (backup)
        {
            Sys.println("Backup copied to " + BackupFolder);
        }
        else
        {
            error("A problem occured when making a backup at " + BackupFolder);
        }
    }


    /**
	 * Recursively use find and replace on *.hx files inside a project directory
	 * 
	 * @param   ProjectPath     Path to scan recursivley 
	 */

    private inline function convertProjectFolder(ProjectPath:String, Display:Bool = false):Array<WarningResult>
    {
        var warnings:Array<WarningResult> = new Array<WarningResult>();

        if (FileSystem.exists(ProjectPath))
        {
            for (fileName in FileSystem.readDirectory(ProjectPath))
            {
                if (FileSystem.isDirectory(ProjectPath + "/" + fileName) && fileName != "_backup")
                {
                    var recursiveWarnings:Array<WarningResult> = convertProjectFolder(ProjectPath + "/" + fileName, false);

                    if (recursiveWarnings != null)
                    {
                        for (warning in recursiveWarnings)
                        {
                            warnings.push(warning);
                        }
                    }
                }
                else
                {
                    if (StringTools.endsWith(fileName, ".hx"))
                    {
                        var filePath:String = ProjectPath + "/" + fileName;
                        var sourceText:String = sys.io.File.getContent(filePath);
                        var originalText:String = Reflect.copy(sourceText);
                        var replacements:Array<FindAndReplaceObject> = FindAndReplace.init();

                        for (replacement in replacements)
                        {
                            var obj:FindAndReplaceObject = replacement;
                            sourceText = StringTools.replace(sourceText, obj.find, obj.replacement);

							if(obj.importValidate != null && CommandUtils.strmatch(obj.find, sourceText))
							{
								var newText = CommandUtils.addImportToFileString(sourceText, obj.importValidate);

								if (newText != null)
								{
									sourceText = newText;
								}
							}

                            if (originalText != sourceText)
                            {
                                FileSystem.deleteFile(filePath);
                                var o:FileOutput = sys.io.File.write(filePath, true);
                                o.writeString(sourceText);
                                o.close();
                            }
                        }

                        var warningsCurrent = scanFileForWarnings(filePath);

                        if (warningsCurrent != null)
                        {
                            for (warning in warningsCurrent)
                            {
                                warnings.push(warning);
                            }
                        }
                    }
                }
            }
        }

        return warnings;
    }

    /**
	 * Write a warning log to a file
	 * @param  FilePath                 String to as the destination for the log file
	 * @param  Warnings<WarningResult>  Array containing all the WarningResults
	 * @param  ConvertProjectPath       The path that the convert command was performed on
	 */
    static public function writeWarningsToFile(FilePath:String, Warnings:Array<WarningResult>, ConvertProjectPath:String):Void
    {
        var fileObject = File.write(FilePath, false);

        fileObject.writeString("flixel-tools convert warning log" + "\n");
        fileObject.writeString("Converted Path " + ConvertProjectPath + "\n");
        fileObject.writeString("Please visit haxeflixel.com/wiki/convert for further documentation on converting old code.");
        fileObject.writeString("\n\n");

        for (warning in Warnings)
        {
            fileObject.writeString("\n");
            fileObject.writeString("File Path    :" + warning.filePath + "\n");
            fileObject.writeString("Line Number  :" + warning.lineNumber + "\n");
            fileObject.writeString("Issue        :" + warning.oldCode + "\n");
            fileObject.writeString("Solution     :" + warning.newCode + "\n");
        }

        fileObject.writeString("\n");
        fileObject.writeString(" / End of Log.");

        fileObject.close();
    }

    /**
	 * Scans a file for a string to warn about
	 * @param  FilePath the path of the file to scan
	 * @return          WarningResult with data for what the warning was and info
	 */
    static public function scanFileForWarnings(FilePath:String):Array<WarningResult>
    {
        var results = new Array<WarningResult>();

        // open and read file line by line
        var fin = File.read(FilePath, false);

        try
        {
            var lineNum = 0;
            while (true)
            {
                var str = fin.readLine();
                lineNum++;
                var warnings = Warnings.warningList;

                for (warning in warnings.keys())
                {
                    var fix = warnings.get(warning);
                    var search = new EReg("\\b" + warning + "\\b", "");
                    var match = search.match(str);

                    if (match)
                    {
                        var result:WarningResult =
                        {
                            oldCode : warning,
                            newCode : fix,
                            lineNumber : Std.string(lineNum),
                            filePath : FilePath
                        };

                        results.push(result);
                    }
                }
            }
        }
        catch (ex:haxe.io.Eof){}

        fin.close();

        return results;
    }
}

/**
 * Warning Result for warning about old code that cannot be updated manually
 */
typedef WarningResult = {
    var oldCode:String;
    var newCode:String;
    var lineNumber:String;
    var filePath:String;
}