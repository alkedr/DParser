module generate;

import parser;
import astdump : codeToAstString;
import std.stdio : File, stdout, writef, writefln, writeln;
import std.file : remove;
import std.string : format;
import std.conv : to, dtext;
import std.array : replicate;
import std.process : executeShell;
import std.exception : assumeUnique;



void combineImpl(implArgs...)(const string arg, void delegate(const string code, const string ast) f, string code, string ast) {
	combine!(implArgs[1..$])(f, code ~ arg, ast);
}

void combineImpl(implArgs...)(const(string[]) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	foreach (newCode; arg) combine!(implArgs[1..$])(f, code ~ newCode, ast);
}

void combineImpl(implArgs...)(const(string[string]) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	foreach (newCode, newAst; arg) combine!(implArgs[1..$])(f, code ~ newCode, ast ~ newAst);
}

void combineImpl(implArgs...)(void function(void delegate(const string code, const string ast) f) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	arg((const string newCode, const string newAst) {
		combine!(implArgs[1..$])(f, code ~ newCode, ast ~ newAst);
	});
}

void combineImpl(implArgs...)(void delegate(void delegate(const string code, const string ast) f) arg, void delegate(const string code, const string ast) f, string code, string ast) {
	arg((const string newCode, const string newAst) {
		combine!(implArgs[1..$])(f, code ~ newCode, ast ~ newAst);
	});
}

void combine(args...)(void delegate(const string code, const string ast) f, string code = "", string ast = "") {
	static if (args.length == 0) f(code, ast); else combineImpl!(args)(args[0], f, code, ast);
}

int level = 0;
string indent(int l = level) {
	return replicate("  ", l);
}

void combineNode(args...)(void delegate(const string code, const string ast) f, string code = "", string ast = "") {
	int l = level++;
	combine!(args[1..$])(
		(const string newCode, const string newAst) {
			f(newCode, format("%sast.%s '%s':\n", indent(l), args[0], newCode) ~ newAst);
		}
	);
	level--;
}

string field(string name, T)(const T value) {
	return format("%s%s: '%s'\n", indent, name, to!string(value));
}


void main() {
	immutable auto whitespace = ["\u0020", "\u0009", "\u000B", "\u000C"].assumeUnique;
	immutable auto lineBreak = ["\u000D", "\u000A", "\u000D\u000A", "\u2028", "\u2029"].assumeUnique;
	immutable auto sep = whitespace ~ lineBreak;

	immutable auto opt(immutable string[] arg) { return arg ~ ""; }


	auto moduleName = (void delegate(const string code, const string ast) f) {
		combineNode!("ModuleName", "a", opt(sep), ".", opt(sep), "bcd", opt(sep), ".", opt(sep), "e")(
			(const string code, const string ast) {
				f(code, ast ~ field!"name"(["a", "bcd", "e"].join(".")) ~ field!"parts"(["a", "bcd", "e"]));
			}
		);
	};

	auto moduleDeclaration = (void delegate(const string code, const string ast) f) {
		combineNode!("ModuleDeclaration", "module", sep, moduleName, opt(sep), ";")(f);
	};



	void run(string name, void delegate(void delegate(const string code, const string ast)) generator) {
		int testsCount, failedCount;
		writef(name~" %10d", testsCount);
		stdout.flush();
		generator(
			(const string code, const string correctAst) {
				string actualAst = codeToAstString(code);
				testsCount++;

				if (correctAst != actualAst) {
					failedCount++;
					writeln("\n'", code, "'");
					File("tmp.d",   "w").writeln(correctAst);
					File("tmp.ast", "w").writeln(actualAst);
					writeln(executeShell("git diff --no-index --color --unified=999999999 tmp.d tmp.ast | tail -n +6").output);
					remove("tmp.d");
					remove("tmp.ast");
					writef(name~" %10d  \x1b[31;01m%d\x1b[0m", testsCount, failedCount);
					stdout.flush();
				} else {
					if (testsCount % 4096 == 0) {
						writef("\u000D"~name~" %10d  %s%d\x1b[0m", testsCount, (failedCount == 0) ? "\x1b[32;01m" : "\x1b[31;01m", failedCount);
						stdout.flush();
					}
				}
			}
		);
		writefln("\u000D"~name~" %10d  %s%d\x1b[0m", testsCount, (failedCount == 0) ? "\x1b[32;01m" : "\x1b[31;01m", failedCount);
	}


	run("module", moduleDeclaration);
}
