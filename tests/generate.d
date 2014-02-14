module generate;

import std.stdio : File, writefln;
import std.string : format;
import std.conv : to;
import std.file : mkdir;

immutable auto whitespace = [ " ", "	", " 	" ];
immutable auto optionalWhitespace = whitespace ~ [""];

immutable auto packageNames = [ "a", "abc" ];


string[string] gen(void function(ref string[string], string, string) f) {
	string[string] result;
	foreach (whitespaceBefore; optionalWhitespace) {
		foreach (whitespaceAfter; optionalWhitespace) {
			f(result, whitespaceBefore, whitespaceAfter);
		}
	}
	return result;
}

void moduleDeclarationGenerator(ref string[string] map, string whitespaceBefore, string whitespaceAfter) {
	foreach (whitespaceAfterKeyword; whitespace) {
		foreach (packageName; packageNames) {
			foreach (whitespaceAfterPackageName; optionalWhitespace) {
				map[whitespaceBefore ~ "module" ~ whitespaceAfterKeyword ~ packageName ~ whitespaceAfterPackageName ~ ";" ~ whitespaceAfter] =
					format("ast.ModuleDeclaration '%s':\n  ast.ModuleName '%s':\n    name: '%s'\n    parts: '%s'",
							"module" ~ whitespaceAfterKeyword ~ packageName ~ whitespaceAfterPackageName ~ ";",
							packageName, packageName, to!string([packageName]));
			}
		}
	}
}


int main() {
	auto map = gen(&moduleDeclarationGenerator);
	int i = 0;
	foreach (key, value; map) {
		i++;
		auto dFile = File(format("tests/generated/%s_%04d.d", "module", i), "w");
		dFile.writeln(key);
		auto astFile = File(format("tests/generated/%s_%04d.d.ast", "module", i), "w");
		astFile.writeln(value);
	}
	return 0;
}
