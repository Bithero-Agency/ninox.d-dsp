/*
 * Copyright (C) 2024 Mai-Lapyst
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/** 
 * Main module for code generation of dsp templates.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/Mai-Lapyst, Mai-Lapyst)
 */
module ninox.dsp.main;

import std.stdio;
import std.getopt;
import std.datetime.systime : Clock;
import std.path;
import std.file : write, exists, isDir;
import std.string;
import std.process : environment;
import std.regex;

/// Verbose logging flag
bool verbose = false;

string output_dir = null;
string input_path = null;
string package_name = null;

/// Transforms a (relative) path to a module name
string pathToModule(string path) {
    return path.replace(dirSeparator, ".");
}

/// Base for all nodes in a template
class Node {}

/// Slot for rendering a layout's content
class SlotNode : Node {}

/// Render a template inside another one
class IncludeNode : Node {
    string name;
    string ctxExpr = null;
}

/// Raw text or character data
class TextNode : Node {
    string content;
}

/// Evaluate a dlang expression and emit it as a string
class ExprNode : Node {
    string expr;
}

/// Lookup variable in the data given via the rendering context
class VarNode : Node {
    string var;
}

/// Dlang code to be emitted
class CodeNode : Node {
    string code;
}

/// A template
class Template {
    string layout = null;
    string headCode = null;
    string attrs = null;
    bool hasSlot = false;

    Node[] nodes;
}

/// Parses a dsp template from a file
Template parseTemplate(string inputFile) {
    auto templ = new Template();

    auto file = fopen(inputFile.toStringz, "rt".toStringz);
    if (file is null) {
        throw new Exception("Could not open file " ~ inputFile);
    }
    scope (exit) {
        fclose(file);
    }

    Node current = null;

    void skipWs() {
        while (!feof(file)) {
            char c;
            fread(&c, char.sizeof, 1, file);
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                continue;
            }
            fseek(file, -1, SEEK_CUR);
            return;
        }
    }

    string readIdent() {
        string id = "";
        while (!feof(file)) {
            char c;
            fread(&c, char.sizeof, 1, file);
            if (c == '%') {
                fseek(file, -1, SEEK_CUR);
                return id;
            }
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                return id;
            }
            id ~= c;
        }
        return id;
    }

    string readVarKey() {
        string id = "";
        while (!feof(file)) {
            char c;
            fread(&c, char.sizeof, 1, file);
            if (c == ']') {
                fseek(file, -1, SEEK_CUR);
                return id;
            }
            id ~= c;
        }
        return id;
    }

    void consumeClose() {
        skipWs();
        char[2] buf;
        if (fread(&buf, char.sizeof, 2, file) != 2 || buf != "%>") {
            throw new Exception("Expected closing '%>'");
        }
    }

    void appendTextnode(char c) {
        auto text = cast(TextNode) current;
        if (text is null) {
            text = new TextNode();
            templ.nodes ~= text;
            current = text;
        }
        if (c == '"') {
            text.content ~= "\\\"";
        } else {
            text.content ~= c;
        }
    }

    string readTagContent(char end = '>') {
        string content = "";
        while (!feof(file)) {
            char c;
            fread(&c, char.sizeof, 1, file);
            if (c != '%') {
                content ~= c;
                continue;
            }
            fread(&c, char.sizeof, 1, file);
            if (c != end) {
                content ~= c;
                continue;
            }
            fseek(file, -2, SEEK_CUR);
            break;
        }
        return content;
    }

    void trimPrevText() {
        if (auto text = cast(TextNode) current) {
            //writeln("DBG: |", text.content, "|");
            while (true) {
                char c = text.content[$-1];
                if (c == ' ' || c == '\t') {
                    text.content = text.content[0..$-1];
                    continue;
                }
                break;
            }
            //writeln("DBG: |", text.content, "|");
        }
    }

    void skipWsUntilNewline() {
        while (!feof(file)) {
            char c;
            fread(&c, char.sizeof, 1, file);
            if (feof(file)) break;
            if (c == ' ' || c == '\t' || c == '\r') continue;
            if (c == '\n') break;
        }
    }

    while (!feof(file)) {
        char c;
        fread(&c, char.sizeof, 1, file);
        if (feof(file)) break;
        if (c == '<') {
            fread(&c, char.sizeof, 1, file);
            if (feof(file)) break;
            if (c != '%') {
                appendTextnode('<');
                appendTextnode(c);
                continue;
            }

            string id = readIdent();

            bool isStrippedAfter = false;
            if (id[$-1] == '!') {
                id = id[0..$-1];
                trimPrevText();
                isStrippedAfter = true;
            }
            else if (id[0] == '!') {
                id = id[1..$];
                trimPrevText();
                isStrippedAfter = true;
            }
            else if (id[0] == '-') {
                id = id[1..$];
                trimPrevText();
            }
            else if (id[$-1] == '-') {
                id = id[0..$-1];
                isStrippedAfter = true;
            }

            switch (id) {
                case "layout": {
                    if (templ.layout !is null) {
                        throw new Exception("Cannot have more than one '<%layout ... %>' directive.");
                    }
                    skipWs();
                    templ.layout = readIdent().strip();
                    consumeClose();
                    break;
                }
                case "head": {
                    current = null;
                    templ.headCode ~= readTagContent();
                    consumeClose();
                    break;
                }
                case "d": {
                    current = null;
                    auto code = new CodeNode();
                    code.code = readTagContent();
                    templ.nodes ~= code;
                    consumeClose();
                    break;
                }
                case "slot": {
                    if (templ.hasSlot) {
                        throw new Exception("Cannot have more than one '<%slot%>' directive.");
                    }

                    current = null;
                    templ.nodes ~= new SlotNode();
                    templ.hasSlot = true;
                    skipWs();
                    consumeClose();
                    break;
                }
                case "inc": {
                    current = null;
                    auto inc = new IncludeNode();
                    inc.name = readIdent();
                    inc.ctxExpr = readTagContent().strip();
                    templ.nodes ~= inc;
                    consumeClose();
                    break;
                }
                case "attrs": {
                    if (templ.attrs !is null) {
                        throw new Exception("Cannot have more than one '<%attrs ... %>' directive.");
                    }
                    templ.attrs = readTagContent().strip();
                    consumeClose();
                    break;
                }
                default: {
                    throw new Exception("Unknown template directive: " ~ id);
                }
            }

            if (isStrippedAfter) skipWsUntilNewline();
        }
        else if (c == '{') {
            fread(&c, char.sizeof, 1, file);
            if (feof(file)) {
                appendTextnode('{');
                break;
            }
            if (c != '%') {
                appendTextnode('{');
                appendTextnode(c);
                continue;
            }

            current = null;
            auto expr = new ExprNode();
            expr.expr = readTagContent('}');
            templ.nodes ~= expr;

            char[2] buf;
            if (fread(&buf, char.sizeof, 2, file) != 2 && buf != "%}") {
                throw new Exception("Expected closing '%}'");
            }
        }
        else if (c == '[') {
            fread(&c, char.sizeof, 1, file);
            if (feof(file)) {
                appendTextnode('[');
                break;
            }
            if (c != '[') {
                appendTextnode('[');
                appendTextnode(c);
                continue;
            }

            auto var = readVarKey().strip();

            char[2] buf;
            if (fread(&buf, char.sizeof, 2, file) != 2 && buf != "]]") {
                throw new Exception("Expected closing ']]'");
            }

            current = null;
            auto node = new VarNode();
            node.var = var;
            templ.nodes ~= node;
        }
        else {
            appendTextnode(c);
        }
    }

    return templ;
}

immutable auto ctxDataRe = regex("@");
immutable auto ctxEmitRe = regex("\\$\\(");

/// Generates a dlang sourcefile for an dsp template file
string genDModule(string inputFile, string module_name) {
    string code = `
/**
 * Generated at ` ~ Clock.currTime.toString ~ `
 * from ` ~ relativePath(inputFile, input_path) ~ `
 * by ninox.d-dsp
 * $(LINK https://github.com/Bithero-Agency/ninox.d-dsp)
 */
module ` ~ package_name ~ "." ~ module_name ~ `;

import ninox.dsp;

`;

    auto templ = parseTemplate(inputFile);
    if (templ.headCode !is null) {
        code ~= "// Generated by <%head ... %> directive:\n";
        code ~= templ.headCode;
        code ~= "// End <%head ... %>\n";
    }

    code ~= "public void renderTemplate(ref Context ctx, void delegate() emitSlot = null) ";
    if (templ.attrs !is null) {
        code ~= templ.attrs ~ " ";
    }
    code ~= "{
    import std.conv : to;
";

    if (templ.layout !is null) {
        code ~= "    import " ~ package_name ~ "." ~ templ.layout ~ " : renderLayout = renderTemplate;\n";
        code ~= "    renderLayout(ctx, () {\n";
    }

    foreach (node; templ.nodes) {
        if (auto text = cast(TextNode) node) {
            code ~= "ctx.emit(\"";
            code ~= text.content;
            code ~= "\");\n";
        }
        else if (auto dcode = cast(CodeNode) node) {
            code ~= dcode.code
                .replaceAll(ctxDataRe, "ctx.data")
                .replaceAll(ctxEmitRe, "ctx.emit(")
            ;
        }
        else if (cast(SlotNode) node) {
            code ~= "emitSlot();";
        }
        else if (auto expr = cast(ExprNode) node) {
            code ~= "ctx.emit(";
            code ~= expr.expr.replaceAll(ctxDataRe, "ctx.data") ~ ".to!(const char[])";
            code ~= ");\n";
        }
        else if (auto var = cast(VarNode) node) {
            code ~= "ctx.emit(ctx.data[\"";
            code ~= var.var;
            code ~= "\"].to!(const char[]));\n";
        }
        else if (auto inc = cast(IncludeNode) node) {
            code ~= "{\n    import " ~ package_name ~ "." ~ pathToModule(inc.name) ~ " : renderTemplate;\n";
            if (inc.ctxExpr is null || inc.ctxExpr.strip().length == 0) {
                code ~= "    renderTemplate(ctx);\n";
            } else {
                code ~= "    auto _ctx = ctx.withData(" ~ inc.ctxExpr.replaceAll(ctxDataRe, "ctx.data") ~ ");\n";
                code ~= "    renderTemplate(_ctx);\n";
            }
            code ~= "}\n";
        }
        else {
            throw new Exception("Unknown node");
        }
    }

    if (templ.layout !is null) {
        code ~= "    });\n";
    }

    code ~= "}\n";

    return code;
}

/// Adds to ignore files
void addToIgnoreFile(string ignorefile, string path) {
    import std.file : exists, isFile, readText;
    import std.algorithm.searching : canFind;

    if (!exists(ignorefile)) {
        return;
    }

    if (!isFile(ignorefile)) {
        return;
    }

    auto content = readText(ignorefile);
    if (!content.canFind(path)) {
        auto f = File(ignorefile, "a+");
        scope(exit) f.close();

        if (content[$-1] != '\n') {
            f.rawWrite("\n");
        }
        f.rawWrite(path);
        f.rawWrite("\n");
    }
}

immutable help_banner = (
`Usage: ninox-d_dsp:srcgen <options>

Options:
`);
immutable usage_hint = "For usage, run: ninox-d_dsp --help";

int main(string[] args) {
    try {
        auto help = getopt(
            args,
            "p|package", "The module path to use as prefix", &package_name,
            "o|output" , "Output path to write sourcefiles", &output_dir,
            "i|input"  , "Input path to search for .dsp files", &input_path,
            "v|verbose", "Enables verbose printing", &verbose,
        );

        if (help.helpWanted) {
            defaultGetoptPrinter(help_banner, help.options);
            return false;
        }
    }
    catch (GetOptException e) {
        stderr.writeln(e.msg);
        stderr.writeln(usage_hint);
        return 1;
    }

    if (output_dir == null || input_path == null || package_name == null) {
        stderr.writeln("Please specify --output, --input and --package!");
        stderr.writeln(usage_hint);
        return 1;
    }

    writeln("Info ninox.d-dsp: using ", output_dir, " as output directory");
    writeln("Info ninox.d-dsp: using ", input_path, " as input base");

    input_path = buildNormalizedPath(absolutePath(input_path));

    auto globs = [
        buildNormalizedPath(input_path, "*.dsp"),
        buildNormalizedPath(input_path, "**", "*.dsp"),
    ];

    import glob : glob;
    foreach (input_glob; globs) {
        foreach (file; glob(input_glob)) {
            auto rel_path = relativePath(file, input_path);
            writeln("Info ninox.d-dsp: process ", rel_path);

            auto out_path = buildNormalizedPath(output_dir, rel_path ~ ".gen.d");
            auto out_dir = dirName(out_path);

            if (!exists(out_dir)) {
                import std.file : mkdirRecurse;
                mkdirRecurse(out_dir);
            }
            else if (!isDir(out_dir)) {
                stderr.writeln("Cannot write to ", out_path, ": ", out_dir, " is not a directory!");
                return 1;
            }

            auto resultDcode = genDModule(file, stripExtension(rel_path).pathToModule);
            write(out_path, resultDcode);
        }
    }

    auto root_dir = environment.get("DUB_PACKAGE_DIR");
    if (root_dir != null) {
        writeln("Info ninox.d-dsp: using ", root_dir, " as package root to populate ignore files");
        addToIgnoreFile(buildNormalizedPath(root_dir, ".gitignore"), "*.dsp.gen.d");
        addToIgnoreFile(buildNormalizedPath(root_dir, ".hgignore"), "*.dsp.gen.d");
    }

    return 0;
}

