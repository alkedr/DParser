module generate;

import parser;
import astdump;
import std.stdio : File, stdout, writef, writeln;
import std.file : remove;
import std.process : executeShell;



template Callback(T) {
	alias Callback = void delegate(const dstring code, T node);
}


struct Field(string code, alias generator) {}
auto field(string code, alias generator)() {
	return Field!(code, generator)();
}


void combine(T)(const dstring code, T node, Callback!T callback) {
	callback(code, node);
}

void combine(T)(const dstring[] codes, T node, Callback!T callback) {
	foreach (code; codes) {
		callback(code, node);
	}
}

void combine(T, string fieldName, alias generator)(Field!(fieldName, generator) field, T node, Callback!T callback) {
	generator(
		(code, subnode) {
			static if (__traits(compiles, __traits(getMember, node, fieldName) ~= subnode)) {
				__traits(getMember, node, fieldName) ~= subnode;
				callback(code, node);
				__traits(getMember, node, fieldName) = __traits(getMember, node, fieldName)[0..$-1];
			} else {
				__traits(getMember, node, fieldName) = subnode;
				callback(code, node);
			}
		}
	);
}


void combineNodeImpl(T, args...)(const dstring existingCode, T existingNode, Callback!T callback) {
	static if (args.length == 0) {
		existingNode.wholeText = existingCode;
		existingNode.begin = Cursor(0);
		existingNode.end = Cursor(cast(uint)existingCode.length);
		callback(existingCode, existingNode);
	} else {
		combine!T(args[0], existingNode,
			(code, node) {
				combineNodeImpl!(T, args[1..$])(existingCode ~ code, node, callback);
			}
		);
	}
}

void combineNode(T, args...)(Callback!T callback) {
	combineNodeImpl!(T, args)("", new T, callback);
}

template sequence(args...) {
	alias sequence = args;
}

void aggregate(T, args...)(Callback!T callback) {
	static if (args.length > 0) {
		args[0](callback);
		aggregate!(T, args[1..$])(callback);
	}
}


void run(string name, alias generator)() {
	int testsCount, failedCount;
	writef("%s %10d", name, testsCount);
	stdout.flush();
	generator(
		(code, node) {
			testsCount++;

			auto actualAst = codeToAstString(code);
			auto dumper = new ASTDumpVisitor;
			dumper.visit(node);
			auto correctAst = dumper.result;

			if (correctAst != actualAst) {
				failedCount++;
				writeln("\n'", code, "'");
				File("tmp.d",   "w").writeln(correctAst);
				File("tmp.ast", "w").writeln(actualAst);
				writeln(executeShell("git diff --no-index --color --unified=999999999 tmp.d tmp.ast | tail -n +6").output);
				remove("tmp.d");
				remove("tmp.ast");
				writef("%s %10d  \x1b[31;01m%d\x1b[0m", name, testsCount, failedCount);
				stdout.flush();
			} else {
				if (testsCount % 4096 == 0) {
					writef("\u000D%s %10d  %s%d\x1b[0m", name, testsCount, (failedCount == 0) ? "\x1b[32;01m" : "\x1b[31;01m", failedCount);
					stdout.flush();
				}
			}
		}
	);
	writef("\u000D%s %10d  %s%d\x1b[0m\n", name, testsCount, (failedCount == 0) ? "\x1b[32;01m" : "\x1b[31;01m", failedCount);
}


void main() {
	enum {
		whitespace = ["\u0020"d, "\u0009", "\u000B", "\u000C"],
		lineBreak = ["\u000D"d, "\u000A", "\u000D\u000A", "\u2028", "\u2029"],
		fullSeparator = whitespace ~ lineBreak,   //TODO: comments

		sep = [" "d, "   "],
	};

	immutable auto opt(immutable dstring[] arg) { return arg ~ ""; }


	alias identifier = combineNode!(Identifier, ["a", "b0d"]);

	auto moduleNamePart = field!("parts", identifier);
	alias moduleSep = sequence!(opt(sep), ".", opt(sep));
	alias moduleName = aggregate!(ModuleName,
		combineNode!(ModuleName, moduleNamePart),
		combineNode!(ModuleName, moduleNamePart, moduleSep, moduleNamePart),
		combineNode!(ModuleName, moduleNamePart, moduleSep, moduleNamePart, moduleSep, moduleNamePart)
	);

	alias moduleDeclaration = aggregate!(ModuleDeclaration,
		combineNode!(ModuleDeclaration, "module", sep, field!("name", moduleName), opt(sep), ";"),
	);


	alias _import = combineNode!(Import, field!("moduleName", moduleName));

	alias importDeclaration = aggregate!(ImportDeclaration,
		combineNode!(ImportDeclaration, "import", sep, field!("imports", _import), opt(sep), ";")
	);


	run!("module", moduleDeclaration);
	run!("import", importDeclaration);
}
